# -*- coding: utf-8 -*-
"""CLI 入口（console=True 打包）：Agent/脚本无头调用。

用法: WorkCalendar-cli.exe --import x.json
"""
import sys

from app.main import main

if __name__ == "__main__":
    sys.exit(main())
