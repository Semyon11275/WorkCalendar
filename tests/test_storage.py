# -*- coding: utf-8 -*-
"""storage 单元测试：原子写 / 备份轮转 / 损坏自愈 / 单写者 / CRUD。"""
import json
import os
import tempfile
import threading
import unittest

from app.models import new_competition
from app.storage import Store


class TestStoreBase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.store = Store(self.tmp)
        self.store.start()

    def tearDown(self):
        self.store.stop()


class TestCrud(TestStoreBase):
    def test_upsert_get_delete(self):
        c = new_competition("大赛A", "2026-09-15")
        self.store.upsert(c)
        self.assertEqual(len(self.store.all()), 1)
        self.assertIsNotNone(self.store.get(c.id))
        self.assertEqual(self.store.all()[0].name, "大赛A")
        # 更新同 id
        c2 = new_competition("大赛A", "2026-09-15", requirements="新")
        self.store.upsert(c2)
        self.assertEqual(len(self.store.all()), 1)
        self.assertEqual(self.store.all()[0].requirements, "新")
        # 删除
        self.assertTrue(self.store.delete(c.id))
        self.assertFalse(self.store.delete(c.id))  # 已不存在 → False
        self.assertEqual(len(self.store.all()), 0)

    def test_upsert_many_single_save(self):
        comps = [new_competition(f"大赛{i}", f"2026-09-{i+1:02d}") for i in range(5)]
        self.store.upsert_many(comps)
        self.assertEqual(len(self.store.all()), 5)

    def test_persistence_roundtrip(self):
        self.store.upsert(new_competition("大赛A", "2026-09-15", milestones=[
            {"name": "初审", "date": "2026-09-10"}], suggested_deadline="2026-09-10"))
        store2 = Store(self.tmp)
        self.assertEqual(len(store2.all()), 1)
        c = store2.all()[0]
        self.assertEqual(c.suggested_deadline.isoformat(), "2026-09-10")
        self.assertEqual(c.milestones[0]["name"], "初审")


class TestAtomicAndBackup(TestStoreBase):
    def test_backup_created_on_save(self):
        self.store.upsert(new_competition("A", "2026-09-15"))
        self.assertTrue(any(f.startswith("competitions_") for f in
                            os.listdir(self.store.backup_dir)))

    def test_backup_rotation(self):
        # 连续备份 25 次 → 保留不超过上限 20 份
        for i in range(25):
            self.store.backup_now()
        backups = [f for f in os.listdir(self.store.backup_dir)
                   if f.startswith("competitions_")]
        self.assertLessEqual(len(backups), 20)

    def test_atomic_write_no_tmp_left(self):
        self.store.upsert(new_competition("A", "2026-09-15"))
        self.assertFalse(os.path.exists(self.store.main_path + ".tmp"))


class TestSelfHeal(unittest.TestCase):
    def test_corrupt_recovery(self):
        tmp = tempfile.mkdtemp()
        s1 = Store(tmp)
        s1.start()
        s1.upsert(new_competition("重要比赛", "2026-09-15"))
        s1.stop()
        # 破坏主文件（可读但 JSON 非法）
        with open(s1.main_path, "w", encoding="utf-8") as f:
            f.write("{broken json!!!")
        s2 = Store(tmp, load_now=False)
        report = s2.load()
        self.assertTrue(report["recovered"])
        self.assertEqual(len(s2.all()), 1)
        self.assertEqual(s2.all()[0].name, "重要比赛")
        # 坏文件保留供排查
        self.assertTrue(os.path.exists(s1.main_path + ".corrupt"))

    def test_empty_dir(self):
        tmp = tempfile.mkdtemp()
        s = Store(tmp)
        report = s.load()
        self.assertEqual(report["count"], 0)
        self.assertEqual(len(s.all()), 0)


class TestSingleWriter(TestStoreBase):
    def test_concurrent_writes_serialized(self):
        """多线程同时写：结果一致、无损坏、无丢失。"""
        errors = []

        def worker(n):
            try:
                for i in range(10):
                    self.store.upsert(new_competition(f"并发{n}_{i}", f"2026-09-{i+1:02d}"))
            except Exception as e:  # noqa: BLE001
                errors.append(e)

        threads = [threading.Thread(target=worker, args=(t,)) for t in range(5)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()
        self.assertFalse(errors, errors)
        self.assertEqual(len(self.store.all()), 50)
        # 文件可正常解析
        with open(self.store.main_path, encoding="utf-8") as f:
            data = json.load(f)
        self.assertEqual(len(data["competitions"]), 50)

    def test_delete_false_not_timeout(self):
        # 回归：submit 返回 falsy 值不误判超时
        self.assertFalse(self.store.delete("c_nonexistent"))


class TestStateFile(TestStoreBase):
    def test_write_state(self):
        self.store.write_state({"version": 1, "count": 3, "port": 17865})
        with open(self.store.state_path, encoding="utf-8") as f:
            st = json.load(f)
        self.assertEqual(st["port"], 17865)


if __name__ == "__main__":
    unittest.main()
