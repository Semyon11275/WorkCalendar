import hashlib, json, tempfile, unittest
from pathlib import Path
from PIL import Image
from app.models import Competition, new_competition
from app.storage import Store, StorageError
from app.previews import ensure_preview
class Regression(unittest.TestCase):
 def test_import_preserves_unloadable_records(self):
  with tempfile.TemporaryDirectory() as d:
   p=Path(d)/'competitions.json'
   raw=json.dumps({'competitions':[{'name':'bad','deadline':'invalid'}]})
   p.write_text(raw,encoding='utf-8')
   store=Store(d);store.start()
   try:
    with self.assertRaises(StorageError): store.upsert(new_competition('new','2027-01-01'))
    self.assertEqual(p.read_text(encoding='utf-8'),raw)
    self.assertEqual(store.all(),[])
   finally:store.stop()
 def test_post_deadline_milestone(self):
  c=Competition.from_dict({'name':'contest','deadline':'2027-01-01','milestones':[{'name':'awards','date':'2027-03-01'}]})
  self.assertEqual(len(c.milestones),1)
 def test_headless_preview_preserves_original(self):
  with tempfile.TemporaryDirectory() as d:
   p=Path(d)/'certificate.png';Image.new('RGB',(3000,2000),'blue').save(p)
   before=hashlib.sha256(p.read_bytes()).digest()
   self.assertTrue(ensure_preview(d,p.name))
   self.assertEqual(before,hashlib.sha256(p.read_bytes()).digest())
   target=Path(str(p)+'.preview.jpg')
   with Image.open(target) as im:self.assertLessEqual(max(im.size),1600)
   mtime=target.stat().st_mtime_ns
   self.assertTrue(ensure_preview(d,p.name));self.assertEqual(mtime,target.stat().st_mtime_ns)