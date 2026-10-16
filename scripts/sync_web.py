"""Synchronize Android assets from the sole maintained web directory."""
from pathlib import Path
import shutil
import json

root = Path(__file__).resolve().parents[1]
target = root / 'android-app/www'
target.mkdir(parents=True, exist_ok=True)
for name in ['core.js', 'ai_files.js', 'ai_mobile.js']:
    shutil.copy2(root / 'web' / name, target / name)
shutil.copy2(root / 'web/mobile.html', target / 'index.html')
shutil.copy2(root / 'web/mobile.html', target / 'mobile.html')
shutil.copytree(root / 'web/assets', target / 'assets', dirs_exist_ok=True,
                ignore=shutil.ignore_patterns('SourceHanSerifCN-*'))
shutil.copytree(root / 'LICENSES', target / 'licenses', dirs_exist_ok=True)
for document in ['LICENSE', 'THIRD_PARTY_NOTICES.md']:
    shutil.copy2(root / document, target / 'licenses' / document)
# 清理历史同步进 www 的字体（仅忽略规则不够，旧文件会残留）
for font in (target / 'assets').glob('SourceHanSerifCN-*'):
    if font.is_file():
        font.unlink()
(target / 'seed').mkdir(exist_ok=True)
for field in ['competitions', 'awards']:
    (target / 'seed' / (field + '.json')).write_text(json.dumps({'schema_version': 1, field: []}), encoding='utf-8')
print('Android web assets synchronized')
