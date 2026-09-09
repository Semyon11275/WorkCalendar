# -*- coding: utf-8 -*-
"""models 单元测试：校验 / 倒计时边界 / 状态机 / 临期线。"""
import unittest
from datetime import date

from app.models import (Competition, ValidationError, dedup_key, make_id,
                        new_competition, normalize_name, parse_date)


class TestParseDate(unittest.TestCase):
    def test_valid(self):
        self.assertEqual(parse_date("2026-09-15"), date(2026, 9, 15))
        self.assertEqual(parse_date("2026-9-5"), date(2026, 9, 5))
        self.assertEqual(parse_date(date(2026, 1, 1)), date(2026, 1, 1))

    def test_invalid(self):
        for bad in ("", None, "2026/09/15", "2026-13-01", "2026-02-30", "abc", 123):
            self.assertIsNone(parse_date(bad), bad)


class TestDedupKey(unittest.TestCase):
    def test_normalize(self):
        self.assertEqual(normalize_name("  2026 大赛  "), "2026 大赛")
        self.assertEqual(normalize_name("ＡＢＣ"), "abc")

    def test_key(self):
        k1 = dedup_key("中国包装创意设计大赛", "2026-09-15")
        k2 = dedup_key("中国包装创意设计大赛 ", "2026-9-15")
        k3 = dedup_key("中国包装创意设计大赛", "2026-09-16")
        self.assertEqual(k1, k2)   # 名称去空格 + 日期容错 → 同键
        self.assertNotEqual(k1, k3)

    def test_make_id_stable(self):
        self.assertEqual(make_id("A", "2026-01-01"), make_id("A", "2026-01-01"))
        self.assertEqual(len(make_id("A", "2026-01-01")), 10)  # c_ + 8


class TestCountdown(unittest.TestCase):
    def setUp(self):
        self.today = date(2026, 8, 4)

    def _c(self, deadline, **kw):
        return Competition.from_dict({"name": "X", "deadline": deadline, **kw})

    def test_basic(self):
        c = self._c("2026-08-11", suggested_deadline="2026-08-11")
        self.assertEqual(c.countdown(self.today), 7)
        self.assertEqual(c.official_countdown(self.today), 7)

    def test_today_due(self):
        c = self._c("2026-08-04", suggested_deadline="2026-08-04")
        self.assertEqual(c.countdown(self.today), 0)

    def test_past(self):
        c = self._c("2026-08-01", suggested_deadline="2026-08-01")
        self.assertEqual(c.countdown(self.today), -3)

    def test_year_boundary(self):
        c = self._c("2027-01-01", suggested_deadline="2027-01-01")
        self.assertEqual(c.countdown(date(2026, 12, 31)), 1)

    def test_leap_year(self):
        c = self._c("2028-02-29", suggested_deadline="2028-02-29")
        self.assertEqual(c.countdown(date(2028, 2, 28)), 1)
        self.assertEqual(c.countdown(date(2028, 3, 1)), -1)

    def test_default_buffer_shifts_countdown(self):
        # 未填临期线 → 默认按官方截止 − 3 天（缓冲）算倒计时
        c = self._c("2026-08-11")
        self.assertEqual(c.countdown(self.today), 4)      # 临期线 8/8
        self.assertEqual(c.official_countdown(self.today), 7)

    def test_suggested_deadline_priority(self):
        c = self._c("2026-09-15", suggested_deadline="2026-09-10")
        self.assertEqual(c.effective_suggested(), date(2026, 9, 10))
        self.assertEqual(c.countdown(self.today), 37)

    def test_buffer_default(self):
        c = self._c("2026-09-15")  # 无临期线 → deadline - 3
        self.assertEqual(c.effective_suggested(), date(2026, 9, 12))

    def test_buffer_custom(self):
        c = self._c("2026-09-15", deadline_buffer_days=7)
        self.assertEqual(c.effective_suggested(), date(2026, 9, 8))
        # 缓冲为 0 不产生负偏移
        c2 = self._c("2026-09-15", deadline_buffer_days=0)
        self.assertEqual(c2.effective_suggested(), date(2026, 9, 15))


class TestStatus(unittest.TestCase):
    def setUp(self):
        self.today = date(2026, 8, 4)

    def _c(self, deadline, **kw):
        return Competition.from_dict({"name": "X", "deadline": deadline, **kw})

    def test_not_started(self):
        c = self._c("2026-09-15", signup_start="2026-09-01", signup_end="2026-10-01")
        self.assertEqual(c.status(self.today), "not_started")

    def test_open(self):
        c = self._c("2026-09-15", signup_start="2026-08-01", signup_end="2026-08-10")
        self.assertEqual(c.status(self.today), "open")

    def test_submitting(self):
        c = self._c("2026-09-15", signup_start="2026-07-01", signup_end="2026-07-31")
        self.assertEqual(c.status(self.today), "submitting")

    def test_urgent_by_suggested(self):
        # 官方 8/15（还有 11 天）但临期线 8/8（还剩 4 天）→ urgent
        c = self._c("2026-08-15", suggested_deadline="2026-08-08")
        self.assertEqual(c.status(self.today), "urgent")

    def test_past_suggested_not_overdue(self):
        c = self._c("2026-08-20", suggested_deadline="2026-08-01")
        self.assertEqual(c.status(self.today), "past_suggested")

    def test_overdue(self):
        c = self._c("2026-08-01")
        self.assertEqual(c.status(self.today), "overdue")

    def test_override_wins(self):
        c = self._c("2026-08-01", status_override="submitted")
        self.assertEqual(c.status(self.today), "submitted")
        c2 = self._c("2026-08-20", suggested_deadline="2026-08-01", status_override="done")
        self.assertEqual(c2.status(self.today), "done")

    def test_milestone_countdowns(self):
        c = self._c("2026-09-15", milestones=[
            {"name": "校内初审", "date": "2026-09-01"},
            {"name": "缴费", "date": "2026-09-05"},
        ])
        ms = c.milestone_countdowns(self.today)
        self.assertEqual(len(ms), 2)
        self.assertEqual(ms[0]["days"], 28)
        self.assertEqual(ms[0]["name"], "校内初审")


class TestValidation(unittest.TestCase):
    def test_required(self):
        with self.assertRaises(ValidationError):
            Competition.from_dict({"deadline": "2026-09-15"})
        with self.assertRaises(ValidationError):
            Competition.from_dict({"name": "X"})

    def test_bad_dates(self):
        with self.assertRaises(ValidationError):
            Competition.from_dict({"name": "X", "deadline": "2026-13-40"})
        with self.assertRaises(ValidationError):
            Competition.from_dict({"name": "X", "deadline": "2026-09-15",
                                   "suggested_deadline": "2026-09-20"})  # 晚于官方
        with self.assertRaises(ValidationError):
            Competition.from_dict({"name": "X", "deadline": "2026-09-15",
                                   "signup_start": "2026-09-01",
                                   "signup_end": "2026-08-01"})

    def test_milestone_validation(self):
        # 里程碑晚于官方截止 → 报错
        with self.assertRaises(ValidationError):
            Competition.from_dict({"name": "X", "deadline": "2026-09-15",
                                   "milestones": [{"name": "y", "date": "2026-10-01"}]})
        # 里程碑日期非法 → 报错
        with self.assertRaises(ValidationError):
            Competition.from_dict({"name": "X", "deadline": "2026-09-15",
                                   "milestones": [{"name": "y", "date": "不是日期"}]})
        # 缺 name 的里程碑 → 宽松不报错
        c = Competition.from_dict({"name": "X", "deadline": "2026-09-15",
                                   "milestones": [{"date": "2026-09-01"}]})
        self.assertEqual(c.milestones[0]["name"], "")

    def test_unknown_fields_preserved(self):
        c = Competition.from_dict({"name": "X", "deadline": "2026-09-15",
                                   "future_field": "keepme"})
        d = c.to_dict()
        self.assertEqual(d["future_field"], "keepme")

    def test_new_competition(self):
        c = new_competition("测试大赛", "2026-09-15", category="综合")
        self.assertTrue(c.id.startswith("c_"))
        self.assertTrue(c.created_at)
        self.assertTrue(c.updated_at)
        self.assertEqual(c.source, "manual")
        # 重复创建同键记录 → 同 id（天然去重）
        c2 = new_competition("测试大赛", "2026-09-15")
        self.assertEqual(c.id, c2.id)


if __name__ == "__main__":
    unittest.main()
