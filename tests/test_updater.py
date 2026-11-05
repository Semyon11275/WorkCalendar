import io, hashlib, json, tempfile, unittest, zipfile, subprocess
from pathlib import Path
from app.updater import select_release, Updater, version
ROOT=Path(__file__).resolve().parents[1]
def release(v='0.5.3', data=b'zip'):
 name=f'WorkCalendar-Windows-x64-v{v}.zip'
 return dict(tag_name='v'+v,assets=[dict(name=name,browser_download_url=f'https://github.com/Semyon11275/WorkCalendar/releases/download/v{v}/{name}',digest='sha256:'+hashlib.sha256(data).hexdigest(),size=len(data))])
class UpdateTests(unittest.TestCase):
 def test_select_and_channels(self):
  self.assertEqual(select_release([release()], '0.5.2')['version'],'0.5.3')
  self.assertIsNone(select_release([release('1.0.0'),release('0.5.1')], '0.5.2'))
  r=release();r['prerelease']=True;self.assertIsNone(select_release([r],'0.5.2'))
 def test_reject_unverified_source(self):
  for key,value in [('browser_download_url','https://evil.test/a'),('digest',''),('size',0)]:
   r=release();r['assets'][0][key]=value
   with self.assertRaises(ValueError):select_release([r],'0.5.2')
 def test_download_hash(self):
  with tempfile.TemporaryDirectory() as d:
   u=Updater(d,'0.5.2','unused',opener=lambda *a,**k:io.BytesIO(b'zip'))
   u.state['available']=select_release([release()],'0.5.2');u.download()
   self.assertEqual(u.state['status'],'ready');self.assertTrue(u.valid_download(u.state['available']))
   u.opener=lambda *a,**k:io.BytesIO(b'bad')
   with self.assertRaises(ValueError):u.download()
   self.assertEqual((u.work/'update.zip').read_bytes(),b'zip')
 def test_installer_preserves_data_and_blocks_traversal(self):
  for malicious in (False,True):
   with tempfile.TemporaryDirectory() as d:
    root=Path(d)/'app';work=Path(d)/'updates';root.mkdir();work.mkdir();(root/'data').mkdir()
    (root/'data/awards.json').write_text('KEEP');(root/'WorkCalendar.exe').write_bytes(b'old')
    content={'WorkCalendar.exe':b'new','_internal/python313.dll':b'runtime'}
    if malicious:content['data/awards.json']=b'bad'
    files=[dict(path=n,size=len(v),sha256=hashlib.sha256(v).hexdigest()) for n,v in content.items()]
    archive=work/'update.zip'
    with zipfile.ZipFile(archive,'w') as z:
     for n,v in content.items():z.writestr(n,v)
     z.writestr('.workcalendar-release.json',json.dumps(dict(version='0.5.3',files=files)))
    job=work/'job.json';job.write_text(json.dumps(dict(root=str(root),zip=str(archive),version='0.5.3',pid=0,testMode=True,sha256=hashlib.sha256(archive.read_bytes()).hexdigest())))
    r=subprocess.run(['powershell.exe','-NoProfile','-ExecutionPolicy','Bypass','-File',str(ROOT/'scripts/apply-update.ps1'),'-JobFile',str(job)],capture_output=True)
    self.assertEqual(r.returncode,1 if malicious else 0,(r.stdout,r.stderr))
    self.assertEqual((root/'data/awards.json').read_text(),'KEEP')
    self.assertEqual((root/'WorkCalendar.exe').read_bytes(),b'old' if malicious else b'new')
 def test_interrupted_install_recovery(self):
  with tempfile.TemporaryDirectory() as d:
   root=Path(d)/'app';work=Path(d)/'updates';root.mkdir();work.mkdir();(work/'backup').mkdir()
   (root/'WorkCalendar.exe').write_bytes(b'partial-new')
   (work/'backup/WorkCalendar.exe').write_bytes(b'old')
   (root/'WorkCalendar-cli.exe').write_bytes(b'new-file')
   (work/'journal.json').write_text(json.dumps({'status':'applying','entries':[{'path':'WorkCalendar.exe','existed':True},{'path':'WorkCalendar-cli.exe','existed':False}]}))
   job=work/'job.json';job.write_text(json.dumps({'root':str(root),'pid':0}))
   r=subprocess.run(['powershell.exe','-NoProfile','-ExecutionPolicy','Bypass','-File',str(ROOT/'scripts/apply-update.ps1'),'-JobFile',str(job),'-Recover'],capture_output=True)
   self.assertEqual(r.returncode,0,(r.stdout,r.stderr));self.assertEqual((root/'WorkCalendar.exe').read_bytes(),b'old');self.assertFalse((root/'WorkCalendar-cli.exe').exists())

 def test_update_blocks_direct_persistence(self):
  from app.storage import Store, StorageError
  with tempfile.TemporaryDirectory() as d:
   store=Store(d);store.update_pending=True
   with self.assertRaises(StorageError):store.save()
   with self.assertRaises(StorageError):store.save_awards()
   self.assertFalse(Path(store.main_path).exists())
