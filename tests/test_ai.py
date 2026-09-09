# -*- coding: utf-8 -*-
"""AI 助手测试：配置读写、密钥不回传、无 Key 报错、本地假 OpenAI 服务跑通工具调用循环。"""
import json
import os
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from tests.test_api import ApiTestBase


class TestAiConfig(ApiTestBase):
    def test_default_config_masks_key(self):
        code, data = self._req("GET", "/api/ai_config")
        self.assertEqual(code, 200)
        self.assertFalse(data["has_key"])
        self.assertIn("deepseek", data["providers"])

    def test_save_and_roundtrip(self):
        code, data = self._req("POST", "/api/ai_config",
                               {"provider": "glm", "api_key": "sk-test-1234567890"})
        self.assertEqual(code, 200)
        self.assertTrue(data["has_key"])
        self.assertEqual(data["provider"], "glm")
        self.assertNotIn("sk-test-1234567890", json.dumps(data))  # 密钥不回传
        code, data = self._req("GET", "/api/ai_config")
        self.assertTrue(data["has_key"])

    def test_chat_requires_key(self):
        code, data = self._req("POST", "/api/ai_chat",
                               {"messages": [{"role": "user", "content": "hi"}]})
        self.assertEqual(code, 200)
        self.assertFalse(data["ok"])
        self.assertIn("Key", data["error"])

    def test_chat_validates_messages(self):
        self._req("POST", "/api/ai_config", {"api_key": "sk-x"})
        code, data = self._req("POST", "/api/ai_chat", {"messages": []})
        self.assertEqual(code, 400)


class _FakeOpenAIHandler(BaseHTTPRequestHandler):
    """极简假 OpenAI 服务：第一轮回 tool_calls，第二轮回最终回复。"""
    state = {"round": 0}

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        _FakeOpenAIHandler.state["round"] += 1
        if _FakeOpenAIHandler.state["round"] == 1:
            msg = {"role": "assistant", "content": "", "tool_calls": [
                {"id": "call_1", "type": "function", "function": {
                    "name": "add_competition",
                    "arguments": json.dumps({"name": "AI 添加的比赛", "deadline": "2026-12-01"},
                                            ensure_ascii=False)}}]}
        else:
            msg = {"role": "assistant", "content": "已添加 ✅"}
        resp = json.dumps({"choices": [{"message": msg}]}).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(resp)))
        self.end_headers()
        self.wfile.write(resp)

    def log_message(self, *a):
        pass


class TestAiChatToolLoop(ApiTestBase):
    def test_tool_loop_adds_competition(self):
        # 起假 OpenAI 服务，配置为 custom 指向它
        srv = ThreadingHTTPServer(("127.0.0.1", 0), _FakeOpenAIHandler)
        port = srv.server_address[1]
        threading.Thread(target=srv.serve_forever, daemon=True).start()
        try:
            _FakeOpenAIHandler.state["round"] = 0
            self._req("POST", "/api/ai_config", {
                "provider": "custom", "api_key": "sk-fake",
                "base_url": f"http://127.0.0.1:{port}", "model": "fake-model"})
            code, data = self._req("POST", "/api/ai_chat",
                                   {"messages": [{"role": "user", "content": "加一个比赛"}]})
            self.assertEqual(code, 200)
            self.assertTrue(data["ok"])
            self.assertIn("已添加", data["reply"])
            self.assertEqual(data["trace"][0]["tool"], "add_competition")
            # 比赛真的入库了
            code, listing = self._req("GET", "/api/competitions")
            names = [c["name"] for c in listing["competitions"]]
            self.assertIn("AI 添加的比赛", names)
        finally:
            srv.shutdown()


class _WsRejectHandler(BaseHTTPRequestHandler):
    """带 web_search 工具的请求返回 400（模拟不支持联网的模型），否则正常。"""
    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        uses_ws = any(t.get("type") == "web_search" for t in (body.get("tools") or []))
        if uses_ws:
            resp = json.dumps({"error": {"message": "1302: 该模型不支持 web_search 工具"}}).encode()
            self.send_response(400)
        else:
            msg = {"role": "assistant", "content": "降级成功"}
            resp = json.dumps({"choices": [{"message": msg}]}).encode()
            self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(resp)))
        self.end_headers()
        self.wfile.write(resp)

    def log_message(self, *a):
        pass


class TestAiWebSearchFallback(ApiTestBase):
    def test_web_search_fallback(self):
        srv = ThreadingHTTPServer(("127.0.0.1", 0), _WsRejectHandler)
        port = srv.server_address[1]
        threading.Thread(target=srv.serve_forever, daemon=True).start()
        try:
            self._req("POST", "/api/ai_config", {
                "provider": "glm", "api_key": "sk-x", "web_search": True,
                "base_url": f"http://127.0.0.1:{port}", "model": "glm-5.3-flash"})
            code, data = self._req("POST", "/api/ai_chat",
                                   {"messages": [{"role": "user", "content": "hi"}]})
            self.assertEqual(code, 200)
            self.assertTrue(data["ok"])
            self.assertIn("降级成功", data["reply"])
        finally:
            srv.shutdown()

    def test_bad_base_url_friendly_error(self):
        self._req("POST", "/api/ai_config", {
            "provider": "custom", "api_key": "sk-x",
            "base_url": "http://127.0.0.1:9", "model": "x"})  # 9 端口必拒绝
        code, data = self._req("POST", "/api/ai_chat",
                               {"messages": [{"role": "user", "content": "hi"}]})
        self.assertEqual(code, 200)
        self.assertFalse(data["ok"])
        self.assertIn("连不上接口地址", data["error"])


class _ListToolsHandler(BaseHTTPRequestHandler):
    """第一轮回 list_competitions 工具调用，第二轮回最终回复。"""
    state = {"round": 0}
    def do_POST(self):
        json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        _ListToolsHandler.state["round"] += 1
        if _ListToolsHandler.state["round"] == 1:
            msg = {"role": "assistant", "content": "", "tool_calls": [
                {"id": "c1", "type": "function", "function": {"name": "list_competitions",
                 "arguments": "{}"}}]}
        else:
            msg = {"role": "assistant", "content": "列好了"}
        resp = json.dumps({"choices": [{"message": msg}]}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(resp)))
        self.end_headers()
        self.wfile.write(resp)
    def log_message(self, *a):
        pass


class TestAiListTool(ApiTestBase):
    def test_list_competitions_serializable(self):
        # 先造一条数据
        self._req("POST", "/api/competitions", {"name": "序列化测试", "deadline": "2026-12-01"})
        srv = ThreadingHTTPServer(("127.0.0.1", 0), _ListToolsHandler)
        port = srv.server_address[1]
        threading.Thread(target=srv.serve_forever, daemon=True).start()
        try:
            _ListToolsHandler.state["round"] = 0
            self._req("POST", "/api/ai_config", {
                "provider": "custom", "api_key": "sk-x",
                "base_url": f"http://127.0.0.1:{port}", "model": "fake"})
            code, data = self._req("POST", "/api/ai_chat",
                                   {"messages": [{"role": "user", "content": "列出比赛"}]})
            self.assertEqual(code, 200)
            self.assertTrue(data["ok"])
            self.assertIn("列好了", data["reply"])
            self.assertEqual(data["trace"][0]["tool"], "list_competitions")
        finally:
            srv.shutdown()


class TestAiLogging(ApiTestBase):
    def _logfiles(self):
        import glob
        return glob.glob(os.path.join(self.tmp, "logs", "*.log"))

    def test_ai_failure_logged(self):
        code, data = self._req("POST", "/api/ai_chat",
                               {"messages": [{"role": "user", "content": "hi"}]})
        self.assertTrue(data["ok"] is False)
        logs = self._logfiles()
        self.assertTrue(logs, "日志文件未生成")
        content = "".join(open(f, encoding="utf-8").read() for f in logs)
        self.assertIn("AI 调用失败", content)

    def test_client_log_endpoint(self):
        code, data = self._req("POST", "/api/client_log",
                               {"message": "前端测试报错", "stack": "Error: 前端测试报错\n    at line1"})
        self.assertEqual(code, 200)
        self.assertTrue(data["ok"])
        import glob, os
        logs = glob.glob(os.path.join(self.tmp, "logs", "client_*.log"))
        self.assertTrue(logs, "client 日志文件未生成")
        content = "".join(open(f, encoding="utf-8").read() for f in logs)
        self.assertIn("前端测试报错", content)
        self.assertIn("at line1", content)

    def test_client_log_requires_message(self):
        code, data = self._req("POST", "/api/client_log", {})
        self.assertEqual(code, 400)
