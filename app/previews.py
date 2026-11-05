"""Headless, atomic image previews. Never modify original certificates."""
import logging
import os
import threading
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from PIL import Image, ImageOps

_pool = ThreadPoolExecutor(max_workers=2, thread_name_prefix='certificate-preview')
_lock = threading.RLock()
_pending = set()

def ensure_preview(root, name):
    if Path(name).name != name or name.endswith('.preview.jpg'):
        return False
    if Path(name).suffix.lower() not in {'.png', '.jpg', '.jpeg', '.webp', '.gif'}:
        return False
    source = Path(root) / name
    target = Path(root) / (name + '.preview.jpg')
    with _lock:
        if not source.is_file():
            return False
        if target.is_file() and target.stat().st_mtime_ns >= source.stat().st_mtime_ns:
            return True
        tmp = Path(str(target) + '.tmp')
        try:
            with Image.open(source) as original:
                im = ImageOps.exif_transpose(original)
                im.thumbnail((1600, 1600))
                if im.mode in ('RGBA', 'LA') or 'transparency' in im.info:
                    rgba = im.convert('RGBA')
                    canvas = Image.new('RGB', rgba.size, 'white')
                    canvas.paste(rgba, mask=rgba.getchannel('A'))
                    im = canvas
                else:
                    im = im.convert('RGB')
                im.save(tmp, format='JPEG', quality=78, optimize=True)
            os.replace(tmp, target)
            return True
        except Exception:
            logging.getLogger(__name__).exception('Preview generation failed: %s', name)
            return False
        finally:
            if tmp.exists():
                tmp.unlink()

def schedule_preview(root, name):
    key = (str(root), name)
    with _lock:
        if key in _pending:
            return
        _pending.add(key)
    def run():
        try:
            return ensure_preview(root, name)
        finally:
            with _lock:
                _pending.discard(key)
    _pool.submit(run)