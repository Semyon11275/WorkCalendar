# -*- coding: utf-8 -*-
"""importer 单元测试：解析 / 去重 / 幂等 / 字段级合并 / 文件通道。"""
import json
import os
import tempfile
import unittest

from app.importer import (handle_import_file, import_records, parse_json_text,
                          parse_markdown_table, parse_text)
from app.models import ValidationError
from app.storage import Store


def _sample(name="2026 包装大赛", deadline="2026-09-15", **kw):
    return {"name": name, "deadline": deadline, "category": "包装设计", **kw}


class TestParseJson(unittest.TestCase):
    def test_single_object(self):
        recs = parse_json_text(json.dumps(_sample()))
        self.assertEqual(len(recs), 1)
        self.assertEqual(recs[0]["name"], "2026 包装大赛")

    def test_array(self):
        recs = parse_json_text(json.dumps([_sample("A"), _sample("B")]))
        self.assertEqual(len(recs), 2)

    def test_competitions_key(self):
        recs = parse_json_text(json.dumps({"competitions": [_sample("A")]}))
        self.assertEqual(len(recs), 1)

    def test_items_key(self):
        recs = parse_json_text(json.dumps({"items": [_sample("A")]}))
        self.assertEqual(len(recs), 1)

    def test_invalid(self):
        with self.assertRaises(ValidationError):
            parse_json_text("{not json")


class TestParseMarkdown(unittest.TestCase):
    def test_table(self):
        text = """| 名称 | 截止 | 类别 | 官网 |
|---|---|---|---|
| 大赛A | 2026-09-15 | 视觉传达 | https://a.com |
| 大赛B | 2026-10-01 | 工业设计 | https://b.com |"""
        recs = parse_markdown_table(text)
        self.assertEqual(len(recs), 2)
        self.assertEqual(recs[0]["name"], "大赛A")
        self.assertEqual(recs[0]["deadline"], "2026-09-15")
        self.assertEqual(recs[0]["website"], "https://a.com")

    def test_english_headers(self):
        text = "| name | deadline |\n|---|---|\n| X | 2026-09-15 |"
        recs = parse_markdown_table(text)
        self.assertEqual(recs[0]["name"], "X")

    def test_parse_text_auto(self):
        # JSON 优先
        recs = parse_text(json.dumps(_sample("A")))
        self.assertEqual(recs[0]["name"], "A")
        # Markdown 兜底
        recs = parse_text("| 名称 | 截止 |\n|---|---|\n| Y | 2026-09-15 |")
        self.assertEqual(recs[0]["name"], "Y")
        # 都无法识别
        with self.assertRaises(ValidationError):
            parse_text("随便一段文字")


class TestImportCore(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.store = Store(self.tmp)
        self.store.start()

    def tearDown(self):
        self.store.stop()

    def test_add_and_idempotent(self):
        r1 = import_records(self.store, [_sample("A"), _sample("B", deadline="2026-10-01")])
        self.assertEqual(dict(r1), {"added": 2, "updated": 0, "skipped": 0, "errors": []})
        # 幂等：再导一次全部跳过
        r2 = import_records(self.store, [_sample("A"), _sample("B", deadline="2026-10-01")])
        self.assertEqual(r2["added"], 0)
        self.assertEqual(r2["skipped"], 2)
        self.assertEqual(len(self.store.all()), 2)

    def test_bad_record_isolated(self):
        r = import_records(self.store, [
            _sample("好记录"),
            {"name": "坏记录"},                      # 缺 deadline
            {"name": "坏日期", "deadline": "2026-99-99"},
        ])
        self.assertEqual(r["added"], 1)
        self.assertEqual(len(r["errors"]), 2)
        self.assertEqual(len(self.store.all()), 1)

    def test_update_existing(self):
        import_records(self.store, [_sample("A", requirements="旧要求")])
        r = import_records(self.store, [_sample("A", requirements="新要求")], update_existing=True)
        self.assertEqual(r["updated"], 1)
        self.assertEqual(r["skipped"], 0)
        c = self.store.all()[0]
        self.assertEqual(c.requirements, "新要求")

    def test_force_update_per_record(self):
        import_records(self.store, [_sample("A", requirements="旧")])
        r = import_records(self.store, [_sample("A", requirements="新", force_update=True)])
        self.assertEqual(r["updated"], 1)
        self.assertEqual(self.store.all()[0].requirements, "新")

    def test_field_level_merge_keeps_user_data(self):
        import_records(self.store, [_sample("A", requirements="旧", notes="用户备注")])
        # Agent 更新：只带 requirements，不带 notes → notes 保留；带空 notes → 也保留
        r = import_records(self.store, [_sample("A", requirements="新")], update_existing=True)
        c = self.store.all()[0]
        self.assertEqual(c.requirements, "新")
        self.assertEqual(c.notes, "用户备注")

    def test_override_never_overwritten(self):
        import_records(self.store, [_sample("A")])
        c = self.store.all()[0]
        c.status_override = "submitted"
        self.store.upsert(c)
        import_records(self.store, [_sample("A", status_override="done")], update_existing=True)
        self.assertEqual(self.store.all()[0].status_override, "submitted")

    def test_merge_milestones_and_suggested(self):
        import_records(self.store, [_sample("A")])
        r = import_records(self.store, [
            _sample("A", suggested_deadline="2026-09-10",
                    milestones=[{"name": "校内初审", "date": "2026-09-10"}])
        ], update_existing=True)
        self.assertEqual(r["updated"], 1)
        c = self.store.all()[0]
        self.assertEqual(c.suggested_deadline.isoformat(), "2026-09-10")
        self.assertEqual(len(c.milestones), 1)

    def test_many_records_speed(self):
        recs = [_sample(f"大赛{i:03d}", deadline=f"2026-{9 + i % 3:02d}-15") for i in range(50)]
        import time
        t0 = time.time()
        r = import_records(self.store, recs)
        dt = time.time() - t0
        self.assertEqual(r["added"], 50)
        self.assertLess(dt, 2.0, f"50 条导入耗时 {dt:.2f}s 超过 2s 红线")


class TestFileChannel(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.store = Store(self.tmp)
        self.store.start()

    def tearDown(self):
        self.store.stop()

    def test_handle_file_ok(self):
        path = os.path.join(self.store.import_dir, "test.json")
        with open(path, "w", encoding="utf-8") as f:
            json.dump({"competitions": [_sample("A"), _sample("B")]}, f, ensure_ascii=False)
        report = handle_import_file(self.store, path)
        self.assertIsNotNone(report)
        self.assertEqual(report["added"], 2)
        # 原文件移入 done/，报告落盘
        self.assertTrue(os.path.exists(os.path.join(self.store.import_done_dir, "test.json")))
        self.assertTrue(os.path.exists(
            os.path.join(self.store.import_done_dir, "test.json.report.json")))
        self.assertEqual(len(self.store.all()), 2)

    def test_handle_file_bad(self):
        path = os.path.join(self.store.import_dir, "bad.json")
        with open(path, "w", encoding="utf-8") as f:
            f.write("{broken")
        report = handle_import_file(self.store, path)
        self.assertIsNone(report)
        # 坏文件留在原地 + 错误说明
        self.assertTrue(os.path.exists(path))
        self.assertTrue(os.path.exists(path + ".error.txt"))


if __name__ == "__main__":
    unittest.main()
