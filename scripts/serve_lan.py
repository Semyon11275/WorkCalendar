# -*- coding: utf-8 -*-
"""局域网临时预览(技术验证用):绑 0.0.0.0 + 数据用副本,避免与正式程序冲突。
用法: python scripts/serve_lan.py [port]
手机浏览器访问 http://<电脑局域网IP>:<port>/
验证完成后删除,勿用于日常(无鉴权)。"""
import os
import shutil
import socket
import sys
import tempfile
import threading

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.api import ApiServer
from app.storage import Store

DATA_SRC = r"E:\Hermes\工作日历\WorkCalendar\data"


def lan_ip() -> str:
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("8.8.8.8", 80))
        return s.getsockname()[0]
    except Exception:
        return "127.0.0.1"
    finally:
        s.close()


def main() -> int:
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8899
    tmp = tempfile.mkdtemp(prefix="wc_lan_")
    data_dir = os.path.join(tmp, "data")
    shutil.copytree(DATA_SRC, data_dir)
    store = Store(data_dir)
    store.start()
    web_dir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "web")
    api = ApiServer(store, port=port, host="0.0.0.0", web_dir=web_dir)
    actual = api.start()
    ip = lan_ip()
    print(f"READY http://{ip}:{actual}/  (数据副本: {data_dir})")
    threading.Event().wait()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
