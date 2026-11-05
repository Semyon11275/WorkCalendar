"""Package the Flutter Windows channel without portable user data."""
import argparse,hashlib,json,zipfile
from pathlib import Path

def package(root,output,version):
 root=Path(root);output=Path(output)
 paths=[root/'workcalendar.exe']+list(root.glob('*.dll'))+list((root/'data').rglob('*'))
 files=[]
 for path in paths:
  if path.is_symlink():raise ValueError('Symlink payload')
  if not path.is_file():continue
  rel=path.relative_to(root).as_posix()
  if rel.startswith('data/') and not (rel.startswith('data/flutter_assets/') or rel in ('data/app.so','data/icudtl.dat')):raise ValueError('Non-runtime data')
  files.append(dict(path=rel,size=path.stat().st_size,sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
 output.parent.mkdir(parents=True,exist_ok=True)
 with zipfile.ZipFile(output,'w',zipfile.ZIP_DEFLATED) as z:
  for f in files:z.write(root/f['path'],f['path'])
  z.writestr('.workcalendar-release.json',json.dumps(dict(product='workcalendar-flutter',version=version,files=files)))
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('root');p.add_argument('output');p.add_argument('version');a=p.parse_args();package(a.root,a.output,a.version)