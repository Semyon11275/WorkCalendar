"""GitHub updater: trusted release metadata, verified download, external installer."""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import threading
import urllib.error
import urllib.request

REPO = 'Semyon11275/WorkCalendar'
API = f'https://api.github.com/repos/{REPO}/releases?per_page=30'
MAX_SIZE = 512 * 1024 * 1024

def version(value):
    m = re.fullmatch(r'v?(\d+)\.(\d+)\.(\d+)', value or '')
    if not m: raise ValueError('只接受正式语义版本号')
    return tuple(map(int, m.groups()))

def select_release(releases, current):
    candidates = []
    for r in releases:
        if r.get('draft') or r.get('prerelease'): continue
        try: v = version(r.get('tag_name'))
        except ValueError: continue
        # Legacy and Flutter packages must never be mixed automatically.
        if v[:2] != (0, 5) or v <= version(current): continue
        candidates.append((v, r))
    if not candidates: return None
    v, r = max(candidates, key=lambda item: item[0])
    label = '.'.join(map(str, v))
    expected = f'WorkCalendar-Windows-x64-v{label}.zip'
    a = next((a for a in r.get('assets', []) if a.get('name') == expected), None)
    if not a or not re.fullmatch(r'sha256:[0-9a-fA-F]{64}', a.get('digest') or ''):
        raise ValueError('新版缺少可校验的 Windows 更新包，请稍后重试')
    expected_url = f'https://github.com/{REPO}/releases/download/{r["tag_name"]}/{expected}'
    if a.get('browser_download_url') != expected_url:
        raise ValueError('更新下载地址不受信任')
    size = a.get('size')
    if type(size) is not int or not 0 < size <= MAX_SIZE: raise ValueError('更新包大小非法')
    return dict(version=label, url=expected_url, size=size,
                sha256=a['digest'][7:].lower(), notes=str(r.get('body') or '')[:12000])

def digest(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b''): h.update(chunk)
    return h.hexdigest()

class Updater:
    def __init__(self, root, current, installer, close=None, opener=urllib.request.urlopen):
        self.root = Path(root).resolve()
        self.work = self.root / '.updates'
        self.current = current
        self.installer = Path(installer)
        self.close = close
        self.opener = opener
        self.lock = threading.Lock()
        self.busy = False
        self.state = dict(status='idle', current=current, available=None, progress=0, error='')
        try:
            result = json.loads((self.work/'result.json').read_text(encoding='utf-8-sig'))
            if result.get('status') == 'failed':
                self.state.update(status='error', error='上次更新失败：' + str(result.get('error', '详见更新日志')))
        except (OSError, ValueError):
            pass

    def snapshot(self):
        return dict(self.state, install_supported=bool(self.close and getattr(sys, 'frozen', False) and sys.platform == 'win32'))

    def start(self, action):
        if action not in ('check', 'download'): raise ValueError('未知更新操作')
        with self.lock:
            if self.busy: return self.snapshot()
            self.busy = True
            self.state.update(status='checking' if action == 'check' else 'downloading', error='')
        def run():
            try: getattr(self, action)()
            except Exception as exc: self.state.update(status='error', error=str(exc))
            finally:
                with self.lock: self.busy = False
        threading.Thread(target=run, name='release-updater', daemon=True).start()
        return self.snapshot()

    def check(self):
        req = urllib.request.Request(API, headers={'User-Agent':'WorkCalendar-Updater', 'Accept':'application/vnd.github+json'})
        with self.opener(req, timeout=20) as response:
            raw = response.read(2 * 1024 * 1024 + 1)
        if len(raw) > 2 * 1024 * 1024: raise ValueError('发布元数据过大')
        releases = json.loads(raw)
        if not isinstance(releases, list): raise ValueError('发布元数据格式错误')
        info = select_release(releases, self.current)
        self.state.update(available=info, status='available' if info else 'current', progress=0)
        if info and self.valid_download(info): self.state.update(status='ready', progress=100)

    def valid_download(self, info):
        path = self.work / 'update.zip'
        return path.is_file() and path.stat().st_size == info['size'] and digest(path) == info['sha256']

    def download(self):
        info = self.state['available']
        if not info: raise ValueError('请先检查更新')
        self.work.mkdir(exist_ok=True)
        if self.work.is_symlink(): raise ValueError('更新目录不可为链接')
        partial = self.work / 'update.zip.part'
        h = hashlib.sha256(); count = 0
        req = urllib.request.Request(info['url'], headers={'User-Agent':'WorkCalendar-Updater'})
        try:
            with self.opener(req, timeout=60) as response, partial.open('wb') as f:
                for block in iter(lambda: response.read(1024 * 1024), b''):
                    count += len(block)
                    if count > info['size']: raise ValueError('更新包超过声明大小')
                    h.update(block); f.write(block)
                    self.state['progress'] = int(count * 100 / info['size'])
            if count != info['size'] or h.hexdigest() != info['sha256']:
                raise ValueError('更新包校验失败，未安装')
            os.replace(partial, self.work / 'update.zip')
            self.state.update(status='ready', progress=100)
        finally:
            partial.unlink(missing_ok=True)

    def install(self):
        with self.lock:
            if self.busy or self.state['status'] != 'ready': raise ValueError('请先下载更新')
            if not self.snapshot()['install_supported']: raise ValueError('仅打包后的 Windows 桌面程序支持安装')
            if not self.valid_download(self.state['available']): raise ValueError('更新包已改变，请重新下载')
            self.busy = True
        try:
            script = self.work / 'apply-update.ps1'
            shutil.copy2(self.installer, script)
            info = self.state['available']
            job = dict(root=str(self.root), zip=str(self.work/'update.zip'), version=info['version'],
                       pid=os.getpid(), sha256=info['sha256'], exe='WorkCalendar.exe')
            job_path = self.work/'job.json'
            job_path.write_text(json.dumps(job, ensure_ascii=False), encoding='utf-8')
            subprocess.Popen(['powershell.exe','-NoProfile','-ExecutionPolicy','Bypass','-File',str(script),'-JobFile',str(job_path)],
                             creationflags=subprocess.CREATE_NO_WINDOW | subprocess.DETACHED_PROCESS,
                             stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            self.state['status'] = 'installing'
            threading.Timer(1, self.close).start()
        except Exception:
            self.busy = False
            raise
        return self.snapshot()