# -*- coding: utf-8 -*-
"""API 集成测试：起临时 HTTP 服务，用 urllib 真实请求全部端点。"""
import json
import tempfile
import unittest
import urllib.request
from datetime import date, timedelta

from app.api import ApiServer
from app.storage import Store


class ApiTestBase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.store = Store(self.tmp)
        self.store.start()
        self.api = ApiServer(self.store, port=0, web_dir=None)
        self.port = self.api.start()
        self.base = f"http://127.0.0.1:{self.port}"

    def tearDown(self):
        self.api.stop()
        self.store.stop()

    def _req(self, method, path, body=None, token="auto"):
        if token == "auto": token = self.api.token
        data = json.dumps(body).encode("utf-8") if body is not None else None
        req = urllib.request.Request(self.base + path, data=data, method=method,
                                     headers={"Content-Type": "application/json"})
        if token:
            req.add_header("X-API-Token", token)
        try:
            with urllib.request.urlopen(req, timeout=10) as resp:
                return resp.status, json.loads(resp.read().decode("utf-8"))
        except urllib.error.HTTPError as e:
            return e.code, json.loads(e.read().decode("utf-8"))

    def _sample(self, name="2026 包装大赛", deadline="2026-09-15", **kw):
        return {"name": name, "deadline": deadline, **kw}


class TestEndpoints(ApiTestBase):
    def test_health(self):
        code, data = self._req("GET", "/api/health")
        self.assertEqual(code, 200)
        self.assertTrue(data["ok"])
        self.assertIn("version", data)

    def test_crud_flow(self):
        # 创建
        code, data = self._req("POST", "/api/competitions",
                               self._sample("大赛A", requirements="原创"))
        self.assertEqual(code, 201)
        cid = data["competition"]["id"]
        self.assertTrue(cid.startswith("c_"))
        # 读取列表（含计算字段）
        code, data = self._req("GET", "/api/competitions")
        self.assertEqual(code, 200)
        self.assertEqual(data["count"], 1)
        item = data["competitions"][0]
        for f in ("countdown", "official_countdown", "status", "status_label",
                  "suggested_deadline", "milestone_countdowns"):
            self.assertIn(f, item)
        # 更新
        code, data = self._req("PUT", f"/api/competitions/{cid}",
                               {"requirements": "新要求"})
        self.assertEqual(code, 200)
        self.assertEqual(data["competition"]["requirements"], "新要求")
        # 详情
        code, data = self._req("GET", f"/api/competitions/{cid}")
        self.assertEqual(code, 200)
        # 删除
        code, data = self._req("DELETE", f"/api/competitions/{cid}")
        self.assertEqual(code, 200)
        code, data = self._req("GET", f"/api/competitions/{cid}")
        self.assertEqual(code, 404)

    def test_create_validation(self):
        code, data = self._req("POST", "/api/competitions", {"name": "缺日期"})
        self.assertEqual(code, 400)
        self.assertIn("deadline", data["error"])

    def test_import_endpoint(self):
        code, data = self._req("POST", "/api/import", {
            "competitions": [self._sample("A"), self._sample("B", deadline="2026-10-01")]})
        self.assertEqual(code, 200)
        self.assertEqual(data["report"]["added"], 2)
        # 幂等
        code, data = self._req("POST", "/api/import", {
            "competitions": [self._sample("A")]})
        self.assertEqual(data["report"]["skipped"], 1)
        # 文本通道（Markdown 表格）
        code, data = self._req("POST", "/api/import", {
            "text": "| 名称 | 截止 |\n|---|---|\n| MD大赛 | 2026-11-01 |"})
        self.assertEqual(data["report"]["added"], 1)
        # 坏记录隔离
        code, data = self._req("POST", "/api/import", {
            "competitions": [self._sample("好"), {"name": "坏"}]})
        self.assertEqual(data["report"]["added"], 1)
        self.assertEqual(len(data["report"]["errors"]), 1)
        self.assertEqual(code, 207)

    def test_stats(self):
        self._req("POST", "/api/competitions",
                  self._sample("A", (date.today() + timedelta(days=3)).isoformat()))
        self._req("POST", "/api/competitions",
                  self._sample("B", "2026-12-01", category="工业设计"))
        code, data = self._req("GET", "/api/stats")
        self.assertEqual(code, 200)
        self.assertEqual(data["total"], 2)
        self.assertGreaterEqual(data["due_in_7"], 1)
        self.assertEqual(len(data["weeks"]), 12)
        self.assertEqual(len(data["months"]), 6)
        self.assertIn("by_category", data)

    def test_sync_replace(self):
        code, data = self._req("POST", "/api/sync", {
            "mode": "replace",
            "competitions": [self._sample("X"), self._sample("Y")]})
        self.assertEqual(code, 200)
        self.assertEqual(data["report"]["added"], 2)
        code, data = self._req("GET", "/api/competitions")
        self.assertEqual(data["count"], 2)
        # 再次 replace 只保留新清单
        code, data = self._req("POST", "/api/sync", {
            "mode": "replace", "competitions": [self._sample("Z")]})
        code, data = self._req("GET", "/api/competitions")
        self.assertEqual(data["count"], 1)
        self.assertEqual(data["competitions"][0]["name"], "Z")

    def test_sync_merge(self):
        self._req("POST", "/api/competitions", self._sample("A"))
        code, data = self._req("POST", "/api/sync", {
            "mode": "merge", "competitions": [
                self._sample("A", requirements="同步来的要求"),
                self._sample("B")]})
        self.assertEqual(code, 200)
        code, data = self._req("GET", "/api/competitions")
        self.assertEqual(data["count"], 2)
        a = next(c for c in data["competitions"] if c["name"] == "A")
        self.assertEqual(a["requirements"], "同步来的要求")

    def test_schema(self):
        code, data = self._req("GET", "/api/schema")
        self.assertEqual(code, 200)
        self.assertEqual(data["required"], ["name", "deadline"])

    def test_backup(self):
        self._req("POST", "/api/competitions", self._sample("A"))
        code, data = self._req("POST", "/api/backup")
        self.assertEqual(code, 200)
        self.assertTrue(data["ok"])

    def test_unknown_path(self):
        code, data = self._req("GET", "/api/nonexistent")
        self.assertEqual(code, 404)


class TestTokenAuth(ApiTestBase):
    def setUp(self):
        super().setUp()
        self.api.token = "secret123"

    def test_token_required(self):
        # health 保持开放；本机回环请求含完整信息（count/data_dir），符合设计
        code, data = self._req("GET", "/api/health")
        self.assertEqual(code, 200)
        self.assertTrue(data["ok"])
        # 数据接口无/错 token → 401
        code, data = self._req("GET", "/api/competitions", token=None)
        self.assertEqual(code, 401)
        code, data = self._req("POST", "/api/competitions", self._sample(), token=None)
        self.assertEqual(code, 401)
        code, data = self._req("GET", "/api/competitions", token="wrong")
        self.assertEqual(code, 401)
        # 正确 token → 通过
        code, data = self._req("GET", "/api/competitions", token="secret123")
        self.assertEqual(code, 200)


class TestFiltering(ApiTestBase):
    def test_filter_by_category_status_keyword(self):
        from urllib.parse import quote
        # 日期用相对值：工业大赛 官方=今天+6（临期线=今天+3 → urgent）；
        # 视觉大赛 官方=今天+16（临期线=今天+13 → 不在紧急区）
        self._req("POST", "/api/competitions",
                  self._sample("视觉大赛", (date.today() + timedelta(days=16)).isoformat(), category="视觉传达"))
        self._req("POST", "/api/competitions",
                  self._sample("工业大赛", (date.today() + timedelta(days=6)).isoformat(), category="工业设计"))
        code, data = self._req("GET", "/api/competitions?category=" + quote("工业设计"))
        self.assertEqual(data["count"], 1)
        self.assertEqual(data["competitions"][0]["name"], "工业大赛")
        code, data = self._req("GET", "/api/competitions?keyword=" + quote("视觉"))
        self.assertEqual(data["count"], 1)
        code, data = self._req("GET", "/api/competitions?status=urgent")
        self.assertEqual(data["count"], 1)
        self.assertEqual(data["competitions"][0]["name"], "工业大赛")

    def test_sort_by_name(self):
        self._req("POST", "/api/competitions", self._sample("B", "2026-12-01"))
        self._req("POST", "/api/competitions", self._sample("A", "2026-09-01"))
        code, data = self._req("GET", "/api/competitions?sort=name&order=asc")
        names = [c["name"] for c in data["competitions"]]
        self.assertEqual(names, ["A", "B"])


if __name__ == "__main__":
    unittest.main()
