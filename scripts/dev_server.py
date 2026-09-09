# -*- coding: utf-8 -*-
"""开发调试服务器：只起 HTTP 服务不开窗口（浏览器冒烟测试用）。

用法: python scripts/dev_server.py [--data-dir DIR] [--port N]
"""
import argparse
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.api import ApiServer          # noqa: E402
from app.storage import Store          # noqa: E402

if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--data-dir", default="data")
    ap.add_argument("--port", type=int, default=17865)
    args = ap.parse_args()
    store = Store(args.data_dir)
    store.load()
    store.start()
    api = ApiServer(store, port=args.port, web_dir=os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "web"))
    port = api.start()
    print(f"SERVE http://127.0.0.1:{port}/  (Ctrl+C 退出)", flush=True)
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        api.stop()
