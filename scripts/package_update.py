"""Build an updater-compatible ZIP; explicit payload allowlist excludes personal data."""
import argparse, hashlib, json, zipfile
from pathlib import Path

def package(root, output, version):
    root=Path(root); output=Path(output)
    paths=[root/'WorkCalendar.exe',root/'WorkCalendar-cli.exe']+sorted((root/'_internal').rglob('*'))
    source=Path(__file__).resolve().parents[1]
    for name in ('LICENSE','THIRD_PARTY_NOTICES.md'):
        import shutil
        shutil.copy2(source/name,root/name)
        paths.append(root/name)
    shutil.copytree(source/'LICENSES',root/'LICENSES',dirs_exist_ok=True)
    paths += sorted((root/'LICENSES').rglob('*'))
    files=[]
    for path in paths:
        if path.is_symlink(): raise ValueError('Symlink payload refused')
        if not path.is_file(): continue
        rel=path.relative_to(root).as_posix()
        if any(p.lower() in ('data','userdata','models') for p in Path(rel).parts): raise ValueError('Private data in payload')
        files.append({'path':rel,'size':path.stat().st_size,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
    if not any(f['path']=='_internal/python313.dll' for f in files): raise ValueError('Missing runtime')
    output.parent.mkdir(parents=True,exist_ok=True)
    with zipfile.ZipFile(output,'w',zipfile.ZIP_DEFLATED) as z:
        for f in files:z.write(root/f['path'],f['path'])
        z.writestr('.workcalendar-release.json',json.dumps({'version':version,'files':files}))
    return output
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('root');p.add_argument('output');p.add_argument('version');a=p.parse_args();print(package(a.root,a.output,a.version))