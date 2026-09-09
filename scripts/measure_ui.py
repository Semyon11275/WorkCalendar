# -*- coding: utf-8 -*-
"""顶栏布局测量：注入 JS 逐元素读取几何数据，定位被压缩/溢出的元素。

用法: uv run python scripts/measure_ui.py [--width 1280] [--height 800]
"""
import argparse
import json
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import webview  # noqa: E402

from app.api import ApiServer  # noqa: E402
from app.storage import Store  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA_DIR = os.path.join(ROOT, ".demo", "data")

MEASURE_JS = r"""
(function(){
  const out = [];
  const header = document.querySelector('header');
  if (!header) return JSON.stringify({error: 'no header'});
  const hw = header.getBoundingClientRect().width;
  out.push({el: 'header', w: Math.round(hw), scrollW: header.scrollWidth,
            overflow: header.scrollWidth > hw + 1});
  [...header.children].forEach((el, i) => {
    const r = el.getBoundingClientRect();
    if (r.width <= 0) return;
    out.push({i, cls: String(el.className).slice(0, 70),
              w: Math.round(r.width), sw: el.scrollWidth, cw: el.clientWidth,
              compressed: el.scrollWidth > el.clientWidth + 1,
              right: Math.round(r.right)});
  });
  ['#searchBox', '#catFilter', '#statusFilter'].forEach(sel => {
    const el = document.querySelector(sel);
    if (!el) return;
    const r = el.getBoundingClientRect();
    out.push({sel, w: Math.round(r.width), sw: el.scrollWidth, cw: el.clientWidth,
              compressed: el.scrollWidth > el.clientWidth + 1});
  });
  document.querySelectorAll('header button').forEach((b, i) => {
    const r = b.getBoundingClientRect();
    out.push({btn: i, text: b.textContent.trim().slice(0, 8), w: Math.round(r.width),
              h: Math.round(r.height)});
  });
  return JSON.stringify(out);
})()
"""


def measure(width: int, height: int) -> str:
    store = Store(DATA_DIR)
    store.load()
    store.start()
    api = ApiServer(store, port=0, web_dir=os.path.join(ROOT, "web"))
    port = api.start()
    result = {}

    def run():
        time.sleep(3.5)
        try:
            result["data"] = window.evaluate_js(MEASURE_JS)
        except Exception as e:  # noqa: BLE001
            result["error"] = repr(e)
        time.sleep(0.5)
        window.destroy()

    window = webview.create_window("布局测量", f"http://127.0.0.1:{port}/",
                                   width=width, height=height)
    webview.start(run)
    api.stop()
    store.stop()
    if result.get("error"):
        return json.dumps({"error": result["error"]})
    return result.get("data", "[]")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--width", type=int, default=1280)
    ap.add_argument("--height", type=int, default=800)
    args = ap.parse_args()
    data = measure(args.width, args.height)
    rows = json.loads(data)
    print(f"=== 窗口 {args.width}x{args.height} ===")
    for r in rows:
        flag = "  <<< 被压缩!" if r.get("compressed") else ""
        print(json.dumps(r, ensure_ascii=False) + flag)
    overflow = [r for r in rows if r.get("overflow")]
    compressed = [r for r in rows if r.get("compressed")]
    print(f"\n结果: header溢出={len(overflow)} 元素被压缩={len(compressed)}")
