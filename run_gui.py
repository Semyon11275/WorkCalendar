# -*- coding: utf-8 -*-
"""GUI 入口（顶层脚本，供 PyInstaller 与开发运行）。

说明：不能把 app/main.py 直接作为打包入口 —— 它内部用相对导入（from .api），
作为顶层脚本执行时没有包上下文会 ImportError。所有入口统一走本文件。
"""
import sys

from app.main import main

if __name__ == "__main__":
    sys.exit(main())
