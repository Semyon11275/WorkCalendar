# -*- coding: utf-8 -*-
"""获奖记录（Award）模型 / 存储 / API 测试。"""
import json
import os
import tempfile
import unittest

from app.models import Award, new_award, make_award_id, ValidationError
from app.storage import Store
from app.api import ApiServer


class AwardModelTests(unittest.TestCase):
    def test_new_award_defaults(self):
        a = new_award("测试大赛 一等奖", level="国家级", is_first_author=True)
        self.assertEqual(a.level, "国家级")
        self.assertTrue(a.is_first_author)
        self.assertTrue(a.id.startswith("a_"))
        self.assertEqual(a.source, "manual")

    def test_award_roundtrip(self):
        a = new_award("测试大赛 银奖", level="省级", award_rank="银奖",
                      award_date="2026-05-01", role="一作",
                      competition="测试大赛", certificate_files=["cert1.jpg"])
        d = a.to_dict()
        b = Award.from_dict(d)
        self.assertEqual(b.name, a.name)
        self.assertEqual(b.level, "省级")
        self.assertEqual(b.award_date.isoformat(), "2026-05-01")
        self.assertEqual(b.certificate_files, ["cert1.jpg"])

    def test_invalid_level_falls_back(self):
        a = Award.from_dict({"name": "x", "level": "随便"})
        self.assertEqual(a.level, "校级")

    def test_missing_name_raises(self):
        with self.assertRaises(ValidationError):
            new_award("")

    def test_first_author_string_forms(self):
        for v in (True, "true", "1", "是", "一作"):
            a = Award.from_dict({"name": "x", "is_first_author": v})
            self.assertTrue(a.is_first_author, v)


class AwardStoreTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="wc_test_")
        self.store = Store(self.tmp)
        self.store.start()

    def tearDown(self):
        self.store.stop()

    def test_upsert_and_list(self):
        a = new_award("A赛 一等奖", level="国家级", award_date="2026-06-01")
        b = new_award("B赛 优秀奖", level="校级", award_date="2026-03-01")
        self.store.upsert_award(a)
        self.store.upsert_award(b)
        awards = self.store.all_awards()
        self.assertEqual(len(awards), 2)
        # 按日期升序
        self.assertEqual(awards[0].name, "B赛 优秀奖")
        # 落盘检查
        with open(os.path.join(self.tmp, "awards.json"), encoding="utf-8") as f:
            data = json.load(f)
        self.assertEqual(len(data["awards"]), 2)

    def test_reload(self):
        a = new_award("C赛 铜奖", level="省级")
        self.store.upsert_award(a)
        self.store.save_awards()
        s2 = Store(self.tmp)
        self.assertEqual(len(s2.all_awards()), 1)
        s2.stop()

    def test_delete_award(self):
        a = new_award("D赛 金奖")
        self.store.upsert_award(a)
        self.assertTrue(self.store.delete_award(a.id))
        self.assertEqual(len(self.store.all_awards()), 0)

    def test_certificate_save(self):
        fname = self.store.save_certificate("证书 图.jpg", b"jpegdata")
        self.assertIn("证书", fname)
        path = os.path.join(self.store.certificates_dir, fname)
        self.assertTrue(os.path.isfile(path))
        with open(path, "rb") as f:
            self.assertEqual(f.read(), b"jpegdata")

    def test_backup_includes_awards(self):
        self.store.upsert_award(new_award("E赛 一等奖"))
        backups = [f for f in os.listdir(self.store.backup_dir)
                   if f.startswith("awards_")]
        self.assertTrue(backups)


class AwardApiTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="wc_api_")
        self.store = Store(self.tmp)
        self.store.start()
        self.api = ApiServer(self.store, port=0)
        self.port = self.api.start()

    def tearDown(self):
        self.api.stop()
        self.store.stop()

    def _post(self, path, body):
        import urllib.request
        req = urllib.request.Request(
            f"http://127.0.0.1:{self.port}{path}",
            data=json.dumps(body).encode("utf-8"),
            headers={"Content-Type": "application/json", "X-API-Token": self.api.token}, method="POST")
        with urllib.request.urlopen(req, timeout=10) as resp:
            return json.loads(resp.read().decode("utf-8"))

    def _get(self, path):
        import urllib.request
        with urllib.request.urlopen(urllib.request.Request(f"http://127.0.0.1:{self.port}{path}", headers={"X-API-Token": self.api.token}),
                                    timeout=10) as resp:
            return json.loads(resp.read().decode("utf-8"))

    def test_awards_api_crud(self):
        import urllib.request
        r = self._post("/api/awards", {"name": "API赛 一等奖", "level": "国家级",
                                       "is_first_author": True})
        self.assertTrue(r["ok"])
        aid = r["award"]["id"]
        lst = self._get("/api/awards")
        self.assertEqual(lst["count"], 1)
        # 更新（PUT）
        req = urllib.request.Request(
            f"http://127.0.0.1:{self.port}/api/awards/{aid}",
            data=json.dumps({"award_rank": "金奖"}).encode("utf-8"),
            headers={"Content-Type": "application/json", "X-API-Token": self.api.token}, method="PUT")
        with urllib.request.urlopen(req, timeout=10) as resp:
            r2 = json.loads(resp.read().decode("utf-8"))
        self.assertEqual(r2["award"]["award_rank"], "金奖")
        # 统计
        st = self._get("/api/awards/stats")
        self.assertEqual(st["total"], 1)
        self.assertEqual(st["by_level"]["国家级"], 1)
        self.assertEqual(st["first_author"], 1)
        # 删除
        req = urllib.request.Request(
            f"http://127.0.0.1:{self.port}/api/awards/{aid}",
            method="DELETE", headers={"X-API-Token": self.api.token})
        with urllib.request.urlopen(req, timeout=10) as resp:
            r3 = json.loads(resp.read().decode("utf-8"))
        self.assertTrue(r3["ok"])
        self.assertEqual(self._get("/api/awards")["count"], 0)

    def test_awards_import_batch(self):
        r = self._post("/api/awards/import", {"awards": [
            {"name": "批量赛1 一等奖", "level": "省级"},
            {"name": "批量赛2 优秀奖", "level": "校级"},
            {"name": "批量赛1 一等奖", "level": "省级"},  # 重复 → skipped
        ]})
        self.assertTrue(r["ok"])
        self.assertEqual(r["report"]["added"], 2)
        self.assertEqual(r["report"]["skipped"], 1)

    def test_certificates_upload(self):
        import base64
        import urllib.parse
        r = self._post("/api/certificates", {"name": "证明.pdf",
                                             "data": base64.b64encode(b"pdfdata").decode()})
        self.assertTrue(r["ok"])
        self.assertIn("证明", r["filename"])
        # 读取验证（中文文件名需 URL 编码）
        import urllib.request
        with urllib.request.urlopen(
                urllib.request.Request(f"http://127.0.0.1:{self.port}{urllib.parse.quote(r['url'])}", headers={"X-API-Token": self.api.token}), timeout=10) as resp:
            self.assertEqual(resp.read(), b"pdfdata")


if __name__ == "__main__":
    unittest.main()
