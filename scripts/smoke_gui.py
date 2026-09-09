# -*- coding: utf-8 -*-
"""GUI 冒烟测试：开窗口 → 验证页面加载 → 自动关闭。

用法: uv run python scripts/smoke_gui.py
注意: 全部逻辑在 main() 内，import 本模块无副作用。
"""
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import webview  # noqa: E402

from app.api import ApiServer  # noqa: E402
from app.storage import Store  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA_DIR = os.path.join(ROOT, ".demo", "data")

_window = None  # 全局引用：pywebview 的 start(func) 不传参，func 内经全局访问


def verify():
    """窗口就绪后轮询页面真实状态。"""
    time.sleep(3)
    try:
        title = _window.evaluate_js("document.title")
        print("TITLE:", title, flush=True)
        has_chart = _window.evaluate_js("typeof echarts !== 'undefined'")
        print("ECHARTS:", has_chart, flush=True)
        stat = _window.evaluate_js(
            "document.querySelector('#portInfo')"
            " ? document.querySelector('#portInfo').textContent : 'N/A'")
        print("PORTINFO:", stat, flush=True)
        ok = title == "工作日历" and has_chart
        print("VERIFY:", "PASS" if ok else "CHECK", flush=True)
    except Exception as e:  # noqa: BLE001
        print("VERIFY_ERROR:", repr(e), flush=True)
    time.sleep(2)
    _window.destroy()


def main():
    global _window
    store = Store(DATA_DIR)
    store.load()
    store.start()
    api = ApiServer(store, port=17865, web_dir=os.path.join(ROOT, "web"))
    port = api.start()
    print(f"SERVE http://127.0.0.1:{port}/", flush=True)

    _window = webview.create_window(
        "冒烟测试", f"http://127.0.0.1:{port}/",
        width=1100, height=720)
    webview.start(verify)
    api.stop()
    print("SMOKE_DONE", flush=True)


if __name__ == "__main__":
    main()
