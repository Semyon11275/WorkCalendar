# -*- coding: utf-8 -*-
"""存储层：JSON 读写、原子写、自动备份、单写者队列、导入目录监听、损坏自愈。

设计要点：
- 所有写操作经 submit() 进入单写者队列，串行执行（界面/HTTP/文件监听三路安全）。
- 原子写：先写 .tmp 再 os.replace，断电不损坏主文件。
- 每次写前自动备份（保留 BACKUP_KEEP 份）；启动时自检，损坏则回滚最近可用备份。
- import/ 目录监听线程：发现 *.json / *.md 新文件即回调导入（由调用方提供处理器）。
"""
from __future__ import annotations

import json
import logging
import os
import queue
import shutil
import threading
from datetime import date, datetime
from typing import Callable, Optional

from .models import (SCHEMA_VERSION, Award, Competition, ValidationError,
                     now_iso)

log = logging.getLogger("design-schedule")

BACKUP_KEEP = 20
WATCH_INTERVAL = 2.0           # 导入目录扫描间隔（秒）
WATCH_EXTS = (".json", ".md")


class StorageError(Exception):
    pass


class Store:
    """单写者 JSON 存储。线程安全：所有写操作经 submit() 串行执行。"""

    def __init__(self, data_dir: str, load_now: bool = True):
        self.data_dir = os.path.abspath(data_dir)
        self.main_path = os.path.join(self.data_dir, "competitions.json")
        self.awards_path = os.path.join(self.data_dir, "awards.json")
        self.backup_dir = os.path.join(self.data_dir, "backups")
        self.import_dir = os.path.join(self.data_dir, "import")
        self.import_done_dir = os.path.join(self.import_dir, "done")
        self.logs_dir = os.path.join(self.data_dir, "logs")
        self.agent_port_path = os.path.join(self.data_dir, "agent_port.txt")
        self.state_path = os.path.join(self.data_dir, "state.json")
        self.certificates_dir = os.path.join(self.data_dir, "certificates")

        self._lock = threading.RLock()          # 保护内存副本
        self._write_queue: "queue.Queue[Callable[[], object]]" = queue.Queue()
        self._writer_thread = None
        self._watch_thread = None
        self._watch_handler: Optional[Callable[[str], None]] = None
        self._stop = threading.Event()
        self._writer_tls = threading.local()    # 标记"当前线程即写线程"（防嵌套提交死锁）

        self._competitions: dict[str, Competition] = {}   # id -> Competition
        self._awards: dict[str, Award] = {}               # id -> Award
        self._last_loaded = ""

        self._ensure_dirs()
        if load_now:
            self.load()

    # ------------------------------------------------------------------
    # 目录与日志
    # ------------------------------------------------------------------

    def _ensure_dirs(self):
        for d in (self.data_dir, self.backup_dir, self.import_dir,
                  self.import_done_dir, self.logs_dir, self.certificates_dir):
            os.makedirs(d, exist_ok=True)

    def _logfile(self) -> str:
        return os.path.join(self.logs_dir, datetime.now().strftime("app_%Y-%m-%d.log"))

    def info(self, msg: str):
        try:
            with open(self._logfile(), "a", encoding="utf-8") as f:
                f.write(f"[{datetime.now().strftime('%H:%M:%S')}] {msg}\n")
        except OSError:
            pass
        log.info(msg)

    def error(self, msg: str, tb: str = ""):
        """错误落盘（含可选堆栈），便于排查。"""
        try:
            with open(self._logfile(), "a", encoding="utf-8") as f:
                f.write(f"[{datetime.now().strftime('%H:%M:%S')}] [ERROR] {msg}\n")
                if tb:
                    for line in tb.strip().splitlines()[-25:]:
                        f.write(f"    {line}\n")
        except OSError:
            pass
        log.error(msg)

    # ------------------------------------------------------------------
    # 加载 / 自愈
    # ------------------------------------------------------------------

    def load(self) -> dict:
        """加载主文件；不存在→空库；解析失败→尝试回滚最近备份。返回加载报告。"""
        report = {"recovered": False, "error": None, "count": 0}
        if not os.path.exists(self.main_path):
            self._competitions = {}
            report["count"] = 0
            self._load_awards()
            return report
        raw = self._read_raw(self.main_path)
        comps = None
        if raw is not None:
            try:
                comps = self._parse_raw(raw, self.main_path)
            except StorageError:
                comps = None  # 文件可读但内容损坏 → 走恢复
        if comps is None:
            restored = self._restore_from_backup()
            if restored:
                report["recovered"] = True
                raw2 = self._read_raw(self.main_path)
                if raw2 is not None:
                    comps = self._parse_raw(raw2, self.main_path)
            if comps is None:
                report["error"] = "主文件损坏且无可用备份，已保留原文件供排查"
                raise StorageError(report["error"])
        self._competitions = {c.id: c for c in comps}
        report["count"] = len(comps)
        self._load_awards()
        return report

    def _load_awards(self):
        """加载 awards.json（独立文件）。损坏/缺失 → 空获奖库，不影响主流程。"""
        self._awards = {}
        if not os.path.exists(self.awards_path):
            return
        raw = self._read_raw(self.awards_path)
        if raw is None:
            return
        try:
            data = json.loads(raw)
        except json.JSONDecodeError:
            return
        items = data.get("awards") if isinstance(data, dict) else data
        if not isinstance(items, list):
            return
        for it in items:
            if not isinstance(it, dict):
                continue
            try:
                a = Award.from_dict(it)
                self._awards[a.id] = a
            except ValidationError:
                continue

    @staticmethod
    def _read_raw(path: str) -> Optional[str]:
        """读文件；损坏/不可读返回 None。"""
        try:
            with open(path, encoding="utf-8") as f:
                return f.read()
        except (OSError, UnicodeDecodeError):
            return None

    def _parse_raw(self, raw: str, path: str) -> list:
        try:
            data = json.loads(raw)
        except json.JSONDecodeError as e:
            raise StorageError(f"JSON 解析失败: {path}: {e}")
        items = data.get("competitions") if isinstance(data, dict) else data
        if not isinstance(items, list):
            raise StorageError(f"数据文件顶层必须是对象或数组: {path}")
        comps = []
        for it in items:
            if not isinstance(it, dict):
                continue
            try:
                comps.append(Competition.from_dict(it))
            except ValidationError:
                continue  # 坏记录跳过，不拖垮整库
        return comps

    def _restore_from_backup(self) -> bool:
        backups = self._list_backups()
        if not backups:
            return False
        # 坏主文件先改名保留，供排查
        try:
            shutil.copy2(self.main_path, self.main_path + ".corrupt")
        except OSError:
            pass
        for b in backups:  # 从新到旧尝试
            raw = self._read_raw(b)
            if raw is None:
                continue
            try:
                comps = self._parse_raw(raw, b)
            except StorageError:
                continue
            if comps is not None:
                self._atomic_write(self.main_path, raw)
                self.info(f"已从备份恢复: {os.path.basename(b)} ({len(comps)} 条)")
                return True
        return False

    # ------------------------------------------------------------------
    # 备份
    # ------------------------------------------------------------------

    def _list_backups(self, prefix: str = "competitions_") -> list:
        if not os.path.isdir(self.backup_dir):
            return []
        files = [os.path.join(self.backup_dir, f)
                 for f in os.listdir(self.backup_dir)
                 if f.startswith(prefix) and f.endswith(".json")]
        return sorted(files, key=os.path.getmtime, reverse=True)

    def _rotate_backups(self):
        for old in self._list_backups("competitions_")[BACKUP_KEEP:] + \
                self._list_backups("awards_")[BACKUP_KEEP:]:
            try:
                os.remove(old)
            except OSError:
                pass

    def backup_now(self) -> str:
        """立即备份，返回备份文件路径（比赛+获奖各一份）。"""
        self._ensure_dirs()
        ts = datetime.now().strftime("%Y%m%d_%H%M%S_%f")
        dst = os.path.join(self.backup_dir, f"competitions_{ts}.json")
        if os.path.exists(self.main_path):
            shutil.copy2(self.main_path, dst)
        else:
            with open(dst, "w", encoding="utf-8") as f:
                json.dump({"schema_version": SCHEMA_VERSION,
                           "updated_at": now_iso(), "competitions": []}, f,
                          ensure_ascii=False, indent=2)
        self._backup_awards(ts)
        self._rotate_backups()
        self.info(f"手动备份: {dst}")
        return dst

    def _backup_awards(self, ts: str):
        """获奖数据单独备份 awards_*.json。"""
        dst = os.path.join(self.backup_dir, f"awards_{ts}.json")
        if os.path.exists(self.awards_path):
            shutil.copy2(self.awards_path, dst)
        else:
            with open(dst, "w", encoding="utf-8") as f:
                json.dump({"schema_version": SCHEMA_VERSION,
                           "updated_at": now_iso(), "awards": []}, f,
                          ensure_ascii=False, indent=2)

    # ------------------------------------------------------------------
    # 单写者队列
    # ------------------------------------------------------------------

    def start(self):
        """启动写队列线程与导入目录监听线程。"""
        if self._writer_thread is None or not self._writer_thread.is_alive():
            self._writer_thread = threading.Thread(target=self._writer_loop,
                                                   name="store-writer", daemon=True)
            self._writer_thread.start()
        if self._watch_thread is None or not self._watch_thread.is_alive():
            self._watch_thread = threading.Thread(target=self._watch_loop,
                                                  name="import-watch", daemon=True)
            self._watch_thread.start()

    def stop(self):
        self._stop.set()
        self._write_queue.put(lambda: None)  # 唤醒

    def submit(self, fn: Callable[[], object], timeout: float = 10.0):
        """把写操作放入单写者队列并等待执行完毕，返回结果。

        重入安全：已在写线程内（如导入引擎内部再写）→ 直接执行，避免自我等待死锁。
        """
        if getattr(self._writer_tls, "in_writer", False):
            return fn()
        result: dict = {}
        done = threading.Event()

        def _run():
            try:
                result["value"] = fn()
            except Exception as e:  # noqa: BLE001 —— 队列里兜住一切异常
                result["error"] = e
            finally:
                done.set()

        self._write_queue.put(_run)
        if not done.wait(timeout):
            raise StorageError("写操作超时")
        if "error" in result:
            raise result["error"]
        return result.get("value")

    def _writer_loop(self):
        while not self._stop.is_set():
            try:
                fn = self._write_queue.get(timeout=0.2)
            except queue.Empty:
                continue
            self._writer_tls.in_writer = True
            try:
                fn()
            except Exception as e:  # noqa: BLE001
                log.exception("写队列任务失败: %s", e)
            finally:
                self._writer_tls.in_writer = False
                self._write_queue.task_done()

    # ------------------------------------------------------------------
    # 原子写 / 主文件落盘
    # ------------------------------------------------------------------

    def _atomic_write(self, path: str, content: str):
        tmp = path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            f.write(content)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, path)

    def save(self, competitions: Optional[dict] = None, backup: bool = True) -> dict:
        """落盘（单写者队列中调用或直接调用均安全）。

        顺序：先原子写主文件，再备份新状态 —— 备份永远代表"最近一次已知良好数据"，
        恢复时取最新可用备份即可回到最近状态。
        """
        with self._lock:
            comps = competitions if competitions is not None else self._competitions
            data = {
                "schema_version": SCHEMA_VERSION,
                "updated_at": now_iso(),
                "competitions": [c.to_dict() for c in sorted(
                    comps.values(), key=lambda c: c.deadline)],
            }
            content = json.dumps(data, ensure_ascii=False, indent=2)
            self._atomic_write(self.main_path, content)
            if backup:
                self.backup_now()
            self._competitions = comps
            self.info(f"已保存 {len(comps)} 条")
            return {"count": len(comps)}

    # ------------------------------------------------------------------
    # 数据访问（读）
    # ------------------------------------------------------------------

    def all(self) -> list:
        with self._lock:
            return sorted(self._competitions.values(), key=lambda c: c.deadline)

    def get(self, cid: str) -> Optional[Competition]:
        with self._lock:
            return self._competitions.get(cid)

    def upsert(self, comp: Competition) -> Competition:
        """插入或更新（经写队列，写前自动备份）。"""
        def _do():
            with self._lock:
                comp.updated_at = now_iso()
                self._competitions[comp.id] = comp
                self.save()
            return comp
        return self.submit(_do)

    def upsert_many(self, comps: list) -> int:
        """批量插入/更新（经写队列，单次落盘 + 备份）。"""
        def _do():
            with self._lock:
                for c in comps:
                    c.updated_at = now_iso()
                    self._competitions[c.id] = c
                self.save()
            return len(comps)
        return self.submit(_do)

    def delete(self, cid: str) -> bool:
        def _do():
            with self._lock:
                if cid not in self._competitions:
                    return False
                del self._competitions[cid]
                self.save()
                return True
        return self.submit(_do)

    def replace_all(self, comps: dict) -> dict:
        def _do():
            with self._lock:
                self._competitions = dict(comps)
                return self.save()
        return self.submit(_do)

    # ------------------------------------------------------------------
    # 获奖数据（Award）
    # ------------------------------------------------------------------

    def save_awards(self, awards: Optional[dict] = None, backup: bool = True) -> dict:
        """获奖数据落盘（原子写 + 自动备份 awards_*.json）。"""
        with self._lock:
            items = awards if awards is not None else self._awards
            data = {
                "schema_version": SCHEMA_VERSION,
                "updated_at": now_iso(),
                "awards": [a.to_dict() for a in sorted(
                    items.values(), key=lambda a: (a.award_date or date(9999, 1, 1)).isoformat())],
            }
            content = json.dumps(data, ensure_ascii=False, indent=2)
            self._atomic_write(self.awards_path, content)
            if backup:
                self._backup_awards(datetime.now().strftime("%Y%m%d_%H%M%S_%f"))
                self._rotate_backups()
            self._awards = items
            self.info(f"已保存获奖 {len(items)} 条")
            return {"count": len(items)}

    def all_awards(self) -> list:
        with self._lock:
            return sorted(self._awards.values(),
                          key=lambda a: (a.award_date or date(9999, 1, 1)).isoformat())

    def get_award(self, aid: str) -> Optional[Award]:
        with self._lock:
            return self._awards.get(aid)

    def upsert_award(self, award: Award) -> Award:
        def _do():
            with self._lock:
                award.updated_at = now_iso()
                self._awards[award.id] = award
                self.save_awards()
            return award
        return self.submit(_do)

    def upsert_awards_many(self, awards: list) -> int:
        def _do():
            with self._lock:
                for a in awards:
                    a.updated_at = now_iso()
                    self._awards[a.id] = a
                self.save_awards()
            return len(awards)
        return self.submit(_do)

    def delete_award(self, aid: str) -> bool:
        def _do():
            with self._lock:
                if aid not in self._awards:
                    return False
                del self._awards[aid]
                self.save_awards()
                return True
        return self.submit(_do)

    def save_certificate(self, fname: str, data: bytes) -> str:
        """保存证书凭证文件到 data/certificates/，返回文件名（防路径穿越）。"""
        import re as _re
        safe = _re.sub(r"[^0-9A-Za-z_.\-\u4e00-\u9fff]", "_", os.path.basename(fname))
        if not safe:
            safe = "cert"
        path = os.path.join(self.certificates_dir, safe)
        with open(path, "wb") as f:
            f.write(data)
        self.info(f"已保存凭证文件: {safe}")
        return safe

    def write_state(self, state: dict):
        """写 data/state.json（Agent 免调用可读状态）。"""
        try:
            self._atomic_write(self.state_path,
                               json.dumps(state, ensure_ascii=False, indent=2))
        except OSError:
            pass

    # ------------------------------------------------------------------
    # 导入目录监听
    # ------------------------------------------------------------------

    def set_watch_handler(self, handler: Callable[[str], None]):
        """handler(path)：收到新文件时回调（解析/去重/落盘由调用方完成）。"""
        self._watch_handler = handler

    def _watch_loop(self):
        seen = set()
        while not self._stop.is_set():
            try:
                files = [f for f in os.listdir(self.import_dir)
                         if f.lower().endswith(WATCH_EXTS)
                         and not f.startswith(".")]
                for fname in files:
                    path = os.path.join(self.import_dir, fname)
                    key = fname + "|" + str(os.path.getmtime(path))
                    if key in seen:
                        continue
                    seen.add(key)
                    if self._watch_handler is not None:
                        try:
                            self._watch_handler(path)
                        except Exception as e:  # noqa: BLE001
                            log.exception("导入回调失败: %s", e)
            except OSError:
                pass
            self._stop.wait(WATCH_INTERVAL)
