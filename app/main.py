# -*- coding: utf-8 -*-
"""程序入口：启动流程 / 无头导入模式 / 单实例锁 / pywebview 窗口（延迟导入）。

用法：
  python -m app.main                 # GUI 模式（需 pywebview）
  python -m app.main --import x.json # 无头导入（无需 pywebview），导入后退出
  python -m app.main --port 17865    # 固定端口（默认随机端口写入 agent_port.txt）
  python -m app.main --data-dir DIR  # 指定数据目录（默认 exe/脚本旁 data/）
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from datetime import date
from typing import Optional

from .api import ApiServer, VERSION
from .importer import handle_import_file
from .storage import Store

DEFAULT_PORT = 17865
APP_NAME = "工作日历"


def exe_dir() -> str:
    """exe 所在目录（打包后数据目录的宿主，便携式：拷贝整个目录即走）。"""
    if getattr(sys, "frozen", False):
        return os.path.dirname(sys.executable)
    return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def resource_dir() -> str:
    """打包资源目录（web/ 等）。PyInstaller 6.x onedir 把 datas 放在 _internal/。"""
    if getattr(sys, "frozen", False):
        base = os.path.dirname(sys.executable)
        internal = os.path.join(base, "_internal")
        return internal if os.path.isdir(internal) else base
    return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def data_dir_default() -> str:
    return os.path.join(exe_dir(), "data")


def load_token(data_dir: str) -> Optional[str]:
    """API Token：data/api_token.txt 存在则读取；不存在则自动生成并写入（首次运行）。"""
    p = os.path.join(data_dir, "api_token.txt")
    try:
        with open(p, encoding="utf-8") as f:
            t = f.read().strip()
        if t:
            return t
    except OSError:
        pass
    import secrets
    t = secrets.token_hex(16)
    try:
        with open(p, "w", encoding="utf-8") as f:
            f.write(t)
        try:
            os.chmod(p, 0o600)
        except OSError:
            pass
        print("已生成本机 API Token（data/api_token.txt）", file=sys.stderr)
    except OSError as e:
        raise RuntimeError(f"无法保存 API Token，已停止启动：{e}") from e
    return t


def forward_import_to_running_instance(port: int, path: str, token: str) -> bool:
    """单实例锁辅助：已有实例在跑 → 把导入请求转发给它（无头模式）。"""
    import urllib.request
    try:
        with open(path, encoding="utf-8") as f:
            text = f.read()
        req = urllib.request.Request(
            f"http://127.0.0.1:{port}/api/import",
            data=json.dumps({"text": text}).encode("utf-8"),
            headers={"Content-Type": "application/json", "X-API-Token": token}, method="POST")
        with urllib.request.urlopen(req, timeout=15) as resp:
            result = json.loads(resp.read().decode("utf-8"))
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return True
    except Exception as e:  # noqa: BLE001
        print(f"转发导入失败: {e}", file=sys.stderr)
        return False


def forward_awards_to_running_instance(port: int, path: str, token: str) -> bool:
    """单实例锁辅助：把获奖导入请求转发给已运行实例。"""
    import urllib.request
    try:
        with open(path, encoding="utf-8") as f:
            text = f.read()
        req = urllib.request.Request(
            f"http://127.0.0.1:{port}/api/awards/import",
            data=text.encode("utf-8"),
            headers={"Content-Type": "application/json", "X-API-Token": token}, method="POST")
        with urllib.request.urlopen(req, timeout=15) as resp:
            result = json.loads(resp.read().decode("utf-8"))
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return True
    except Exception as e:  # noqa: BLE001
        print(f"转发获奖导入失败: {e}", file=sys.stderr)
        return False


def run_awards_headless(store: Store, api: ApiServer, import_path: str) -> int:
    """无头导入获奖模式：启动服务 → 导入 → 写状态 → 退出。"""
    import urllib.request
    token = api.token
    store.start()
    api.start()
    with open(store.agent_port_path, "w", encoding="utf-8") as f:
        f.write(str(api.port))
    try:
        with open(import_path, encoding="utf-8") as f:
            text = f.read()
        req = urllib.request.Request(
            f"http://127.0.0.1:{api.port}/api/awards/import",
            data=text.encode("utf-8"),
            headers={"Content-Type": "application/json", "X-API-Token": token}, method="POST")
        with urllib.request.urlopen(req, timeout=30) as resp:
            result = json.loads(resp.read().decode("utf-8"))
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0 if result.get("ok") else 1
    except Exception as e:  # noqa: BLE001
        print(f"获奖导入失败: {e}", file=sys.stderr)
        return 1
    finally:
        api.stop()


def run_headless(store: Store, api: ApiServer, import_path: str) -> int:
    """无头导入模式：启动服务 → 导入 → 写状态 → 退出。"""
    store.start()
    api.start()
    store.write_state({"version": VERSION, "port": api.port,
                       "count": len(store.all()), "mode": "headless"})
    with open(store.agent_port_path, "w", encoding="utf-8") as f:
        f.write(str(api.port))
    report = handle_import_file(store, import_path, archive=False)
    if report is None:
        print("导入失败：文件无法解析（详见 .error.txt）", file=sys.stderr)
        api.stop()
        return 1
    print(json.dumps({"ok": not report["errors"], "report": dict(report),
                      "port": api.port}, ensure_ascii=False, indent=2))
    api.stop()
    return 0


def run_gui(store: Store, api: ApiServer, port: int) -> int:
    """GUI 模式：单实例锁 → 启动服务 → 打开 pywebview 窗口。"""
    # 单实例锁：固定端口被占 → 已有实例在跑
    if api.try_bind() is False:
        print("检测到已有实例在运行，本窗口退出（请查看原窗口）", file=sys.stderr)
        return 0
    store.start()
    actual_port = api.start()
    with open(store.agent_port_path, "w", encoding="utf-8") as f:
        f.write(str(actual_port))
    store.write_state({"version": VERSION, "port": actual_port,
                       "count": len(store.all()), "mode": "gui",
                       "today": date.today().isoformat()})

    # 每日首次启动自动备份
    today = date.today().isoformat()
    backups = os.listdir(store.backup_dir) if os.path.isdir(store.backup_dir) else []
    if not any(today in b for b in backups):
        store.backup_now()

    # 文件监听 → 导入回调（导入后刷新前端由 pywebview js_api 通知）
    def on_import_file(path: str):
        try:
            report = handle_import_file(store, path)
            if report is not None and window is not None:
                try:
                    window.evaluate_js(f"window.__onImport && window.__onImport({json.dumps(dict(report), ensure_ascii=False)})")
                except Exception:  # noqa: BLE001
                    pass
        except Exception as e:  # noqa: BLE001
            store.info(f"导入目录回调异常: {e}")

    window = None
    store.set_watch_handler(on_import_file)

    web_index = os.path.join(resource_dir(), "web", "index.html")
    if not os.path.exists(web_index):
        print(f"警告：前端页面缺失 {web_index}，请先完成 Step6", file=sys.stderr)

    try:
        import webview  # 延迟导入：无 pywebview 时 GUI 不可用，无头模式不受影响
    except ImportError:
        print("未安装 pywebview（GUI 需要）。两种选择：\n"
              "  1) 安装: uv add pywebview\n"
              "  2) 用浏览器模式: 直接打开 http://127.0.0.1:{actual_port}/\n"
              "无头导入仍可用: python -m app.main --import x.json", file=sys.stderr)
        input("按回车退出…")
        api.stop()
        return 1

    webview.create_window(
        APP_NAME,
        f"http://127.0.0.1:{actual_port}/",
        width=1280, height=820, min_size=(980, 640),
        js_api=None,  # 一期：前端轮询即可；文件导入刷新走 evaluate_js
    )
    # 关闭隐私模式并固定用户数据目录：否则 WebView2 每次启动都是全新环境，
    # localStorage（AI 会话/界面设置）不会跨重启保留。
    if getattr(sys, "frozen", False):
        app_base = os.path.dirname(sys.executable)
    else:
        app_base = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    storage_path = os.path.join(app_base, "webview_data")
    os.makedirs(storage_path, exist_ok=True)
    webview.start(private_mode=False, storage_path=storage_path)
    api.stop()
    return 0


def main(argv: Optional[list] = None) -> int:
    parser = argparse.ArgumentParser(prog="design-schedule", description=APP_NAME)
    parser.add_argument("--import", dest="import_path", metavar="FILE",
                        help="无头导入模式：导入比赛文件后退出（Agent/脚本用）")
    parser.add_argument("--import-awards", dest="awards_path", metavar="FILE",
                        help="无头导入获奖记录：导入获奖 JSON 后退出（Agent/脚本用）")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT,
                        help=f"固定端口（默认 {DEFAULT_PORT}，被占用自动回退随机端口）")
    parser.add_argument("--data-dir", default=None, help="数据目录（默认 data/）")
    args = parser.parse_args(argv)

    data_dir = args.data_dir or data_dir_default()
    store = Store(data_dir)
    try:
        load_report = store.load()
        if load_report.get("recovered"):
            print("提示：数据文件损坏，已自动从最近备份恢复", file=sys.stderr)
    except Exception as e:  # noqa: BLE001
        print(f"数据加载失败: {e}", file=sys.stderr)
        return 1

    try:
        token = load_token(data_dir)
    except RuntimeError as e:
        print(str(e), file=sys.stderr)
        return 1
    web_dir = os.path.join(resource_dir(), "web")
    api = ApiServer(store, port=args.port, token=token, web_dir=web_dir, host="0.0.0.0")  # 绑定全部网卡：手机扫码配对需要局域网可达

    def _probe_running() -> bool:
        import socket
        probe = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        try:
            probe.connect(("127.0.0.1", args.port))
            probe.close()
            return True
        except OSError:
            return False

    if args.awards_path:
        if _probe_running():
            return 0 if forward_awards_to_running_instance(args.port, args.awards_path, token) else 1
        return run_awards_headless(store, api, args.awards_path)
    if args.import_path:
        # 单实例转发：已有实例在跑 → 转发而非重复导入
        if _probe_running():
            return 0 if forward_import_to_running_instance(args.port, args.import_path, token) else 1
        return run_headless(store, api, args.import_path)
    return run_gui(store, api, args.port)


if __name__ == "__main__":
    sys.exit(main())
