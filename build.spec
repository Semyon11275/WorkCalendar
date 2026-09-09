# -*- mode: python ; coding: utf-8 -*-
"""PyInstaller 打包配置：GUI 版（无控制台）+ CLI 版（有控制台，Agent 无头导入）。

产物: dist/DesignSchedule/DesignSchedule.exe        （双击使用）
      dist/DesignSchedule/DesignSchedule-cli.exe    （--import 无头导入）
"""
import os

# 注意：spec 由 PyInstaller exec 执行，没有 __file__；用 cwd（在项目根运行 pyinstaller）
ROOT = os.getcwd()

COMMON = dict(
    pathex=[ROOT],
    datas=[(os.path.join(ROOT, 'web'), 'web')],
    hiddenimports=['webview', 'clr_loader'],
    excludes=[
        # 注意：不要排除 http.server / socketserver（API 服务器运行时依赖），
        # 也不要排除 email（http.server 内部依赖它）
        # 注意：distutils 不可列入 excludes（PyInstaller 6.x + setuptools 环境会报
        # "Target module distutils already imported as ExcludedModule"）
        'tkinter', 'unittest', 'pydoc', 'doctest',
        'pydoc_data', 'lib2to3', 'sqlite3', 'xmlrpc',
        'pdb', 'curses',
    ],
    noarchive=False,
)

a_gui = Analysis([os.path.join(ROOT, 'run_gui.py')], **COMMON)
a_cli = Analysis([os.path.join(ROOT, 'app', 'cli_entry.py')], **COMMON)

pyz_gui = PYZ(a_gui.pure, a_gui.zipped_data)
pyz_cli = PYZ(a_cli.pure, a_cli.zipped_data)

exe_gui = EXE(
    pyz_gui, a_gui.scripts,
    exclude_binaries=True,
    name='WorkCalendar',
    console=False,          # GUI：双击无黑窗
    icon=os.path.join(ROOT, 'calendar-icon.ico'),
)
exe_cli = EXE(
    pyz_cli, a_cli.scripts,
    exclude_binaries=True,
    name='WorkCalendar-cli',
    console=True,           # CLI：Agent 可读 stdout
    icon=os.path.join(ROOT, 'calendar-icon.ico'),
)

coll = COLLECT(
    exe_gui, exe_cli,
    a_gui.binaries, a_gui.zipfiles, a_gui.datas,
    name='WorkCalendar',
)
