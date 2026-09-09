# -*- coding: utf-8 -*-
"""接口层：本地 HTTP 服务（网页前端与 Agent 共用同一入口）。

- 绑定 127.0.0.1，可选 token 鉴权（data/api_token.txt）
- 路由：competitions / stats / import / schema / sync / backup / health / 静态前端
- 所有响应统一 JSON；错误带 HTTP 状态码 + 中文原因
"""
from __future__ import annotations

import json
import mimetypes
import os
import random
import re
import secrets
import socket
import threading
import time
from datetime import date, datetime, timedelta
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Optional
from urllib.parse import parse_qs, urlparse

from .importer import import_records, parse_text
from .models import (Award, Competition, SCHEMA_VERSION, ValidationError,
                     new_award, new_competition)
from . import ai as aimod
from .storage import Store, StorageError

VERSION = "0.4.2"

PAIR_TTL = 300  # 配对码有效期（秒）


def lan_ip() -> str:
    """获取局域网 IP（用于手机扫码配对 / 局域网访问）。"""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            s.connect(("8.8.8.8", 80))
            return s.getsockname()[0]
        finally:
            s.close()
    except OSError:
        return "127.0.0.1"


def lan_ips() -> list:
    """列出所有候选局域网 IPv4（多网卡机器上手机可能只可达其中一块网卡）。
    主选（lan_ip 的结果）排最前；过滤回环与链路本地地址。"""
    ips = []
    try:
        for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            ip = info[4][0]
            if ip not in ips and not ip.startswith("127.") and not ip.startswith("169.254."):
                ips.append(ip)
    except OSError:
        pass
    primary = lan_ip()
    if primary in ips:
        ips.remove(primary)
    return [primary] + ips

# 单条记录 → 前端展示对象（基础字段 + 计算字段）
_STATUS_LABELS = {
    "not_started": "未开始", "open": "报名中", "submitting": "进行中",
    "urgent": "即将截止", "past_suggested": "已过临期线", "overdue": "已截止",
    "submitted": "已提交", "done": "已完成", "abandoned": "已放弃",
}


def serialize(c: Competition, today: Optional[date] = None) -> dict:
    d = c.to_dict()
    d["countdown"] = c.countdown(today)
    d["official_countdown"] = c.official_countdown(today)
    d["status"] = c.status(today)
    d["status_label"] = _STATUS_LABELS.get(d["status"], d["status"])
    d["suggested_deadline"] = c.effective_suggested().isoformat()
    d["milestone_countdowns"] = c.milestone_countdowns(today)
    return d


def compute_stats(comps: list, today: Optional[date] = None) -> dict:
    today = today or date.today()
    by_status: dict = {}
    by_category: dict = {}
    upcoming = []
    weekly: dict = {}
    monthly: dict = {}
    completed = 0
    total = 0
    for c in comps:
        total += 1
        s = c.status(today)
        by_status[s] = by_status.get(s, 0) + 1
        if s in ("submitted", "done"):
            completed += 1
        cat = c.category or "未分类"
        by_category[cat] = by_category.get(cat, 0) + 1
        if s not in ("submitted", "done", "abandoned", "overdue"):
            d = c.effective_suggested()
            if d >= today:
                upcoming.append(serialize(c, today))
                wk = (d - today).days // 7
                weekly[wk] = weekly.get(wk, 0) + 1
                ym = d.strftime("%Y-%m")
                monthly[ym] = monthly.get(ym, 0) + 1
    upcoming.sort(key=lambda x: x["countdown"])
    # 未来 12 周序列（补零）
    weeks = [weekly.get(w, 0) for w in range(12)]
    # 未来 6 个月序列
    months = []
    for i in range(6):
        m = (today.replace(day=1) + timedelta(days=32 * i)).strftime("%Y-%m")
        months.append({"month": m, "count": monthly.get(m, 0)})
    return {
        "total": total,
        "by_status": by_status,
        "by_category": by_category,
        "upcoming": upcoming[:30],           # 紧急区（最多 30 条）
        "due_in_7": sum(1 for u in upcoming if u["countdown"] <= 7),
        "due_in_30": sum(1 for u in upcoming if u["countdown"] <= 30),
        "completed": completed,
        "weeks": weeks,
        "months": months,
        "today": today.isoformat(),
    }


class ApiHandler(BaseHTTPRequestHandler):
    server_version = "WorkCalendar/" + VERSION
    protocol_version = "HTTP/1.1"

    # ---------------- 基础 ----------------

    @property
    def app(self) -> "ApiServer":
        return self.server.app  # type: ignore[attr-defined]

    def log_message(self, fmt, *args):  # 静音默认日志（避免控制台刷屏）
        pass

    def _send(self, status: int, body: dict, raw: bool = False):
        data = json.dumps(body, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        # CORS：允许手机 App / 局域网浏览器跨域访问（同步与预览用）
        self.send_header("X-Content-Type-Options", "nosniff")
        if getattr(self, "issue_cookie", False):
            self.send_header("Set-Cookie", "wc_session=" + self.app.browser_session + "; HttpOnly; SameSite=Strict; Path=/certificates/")
        self.end_headers()
        self.wfile.write(data)

    def _send_error(self, status: int, msg: str, code: Optional[str] = None):
        if not getattr(self, 'body_read', False):
            try:
                length = int(self.headers.get('Content-Length') or 0)
                if 0 < length <= 72 * 1024 * 1024:
                    self.rfile.read(length)
            except (ValueError, OSError):
                pass
            self.body_read = True
        self._send(status, {"ok": False, "error": msg,
                            "code": code or "E_" + str(status)})

    def _read_json(self) -> dict:
        try:
            length = int(self.headers.get("Content-Length") or 0)
        except ValueError:
            raise ValidationError("Content-Length 非法")
        if length < 0 or length > 72 * 1024 * 1024:
            raise ValidationError("请求过大（上限 72MB）")
        if length <= 0:
            return {}
        raw = self.rfile.read(length)
        self.body_read = True
        try:
            data = json.loads(raw.decode("utf-8"))
        except (json.JSONDecodeError, UnicodeDecodeError):
            raise ValidationError("请求体不是合法 JSON")
        return data if isinstance(data, dict) else {"competitions": data}

    def _owner(self):
        return bool(self.app.token) and secrets.compare_digest(self.headers.get("X-API-Token", ""), self.app.token)

    def _check_token(self):
        return self._owner() or self._check_sync_token()

    def _check_sync_token(self):
        return self.headers.get("X-Sync-Token", "") in self.app.paired_tokens

    def _client_ip(self) -> str:
        return self.client_address[0] if self.client_address else ""

    def _is_loopback(self) -> bool:
        return self._client_ip() in ("127.0.0.1", "::1", "::ffff:127.0.0.1")

    def _dispatch(self, method: str):
        self.connection.settimeout(30)
        self.close_connection = True
        parsed = urlparse(self.path)
        path = parsed.path.rstrip("/") or "/"
        host = self.headers.get("Host", "")
        try:
            host_name = urlparse("http://" + host).hostname
            import ipaddress
            host_ok = host_name == "localhost" or bool(ipaddress.ip_address(host_name))
        except (ValueError, TypeError):
            host_ok = False
        if not host_ok:
            return self._send_error(403, "Host 不受信任")
        origin = self.headers.get("Origin")
        if origin and origin != "http://" + host:
            return self._send_error(403, "不允许跨站访问")
        if self.headers.get("Sec-Fetch-Site") == "cross-site":
            return self._send_error(403, "不允许跨站访问")
        if method == "OPTIONS":
            self.send_response(204)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        pair_owner = path in ("/api/pair/begin", "/api/pair/pending", "/api/pair/approve", "/api/pair/revoke")
        if pair_owner and not self._is_loopback():
            return self._send_error(403, "仅限电脑本机管理配对")
        public = path in ("/api/health", "/api/bootstrap", "/api/pair/confirm", "/api/pair/result")
        if path.startswith("/api/") and not public:
            if not self._check_token():
                return self._send_error(401, "API Token 无效或缺失")
            phone_paths = ("/api/export_all", "/api/import_all")
            if not self._owner() and path not in phone_paths:
                return self._send_error(403, "手机配对凭据仅允许数据同步")
        if path.startswith("/certificates/") and not self._owner():
            from http.cookies import SimpleCookie
            cookie = SimpleCookie()
            try:
                cookie.load(self.headers.get("Cookie", ""))
                value = cookie.get("wc_session")
                authorized = value and secrets.compare_digest(value.value, self.app.browser_session)
            except Exception:
                authorized = False
            if not authorized or not self._is_loopback():
                return self._send_error(401, "凭证访问需要本机授权")
        try:
            qs = parse_qs(parsed.query)
            m = re.fullmatch(r"/api/([\w-]+)/?(.*)", path)
            if m:
                name, rest = m.group(1), m.group(2).strip("/")
                handler = getattr(self, f"_api_{name}", None)
                if handler:
                    handler(method, rest, qs)
                    return
            if method == "GET" and path.startswith("/certificates/"):
                self._serve_certificate(path)
                return
            if method == "GET" and (path == "/" or path.startswith("/assets/")
                                    or path in ("/core.js", "/mobile.html", "/ai_files.js", "/ai_mobile.js")):
                self._serve_static(path)
                return
            self._send_error(404, f"未知路径: {method} {path}")
        except ValidationError as e:
            self._send_error(400, str(e), code="E_VALIDATION")
        except StorageError as e:
            self._send_error(500, str(e), code="E_STORAGE")
        except Exception as e:  # noqa: BLE001 —— 兜底，绝不裸崩
            import traceback
            try:
                self.app.store.error(f"接口 500 {method} {path}: {e}", traceback.format_exc())
            except Exception:
                pass
            self._send_error(500, f"内部错误: {e}", code="E_INTERNAL")

    do_GET = lambda self: self._dispatch("GET")      # noqa: E731
    do_POST = lambda self: self._dispatch("POST")    # noqa: E731
    do_PUT = lambda self: self._dispatch("PUT")      # noqa: E731
    do_DELETE = lambda self: self._dispatch("DELETE")  # noqa: E731
    do_OPTIONS = lambda self: self._dispatch("OPTIONS")  # noqa: E731

    # ---------------- 静态前端（降级模式 / 浏览器打开） ----------------

    def _serve_static(self, path: str):
        web_dir = self.app.web_dir
        if not web_dir:
            self._send_error(404, "前端资源未配置")
            return
        rel = "index.html" if path == "/" else path.lstrip("/")
        fpath = os.path.normpath(os.path.join(web_dir, rel))
        if os.path.commonpath([os.path.abspath(fpath), os.path.abspath(web_dir)]) != os.path.abspath(web_dir) or not os.path.isfile(fpath):
            self._send_error(404, "资源不存在")
            return
        ctype = mimetypes.guess_type(fpath)[0] or "application/octet-stream"
        with open(fpath, "rb") as f:
            data = f.read()
        self.send_response(200)
        self.send_header("Content-Type", ctype + ("; charset=utf-8" if ctype.startswith("text") else ""))
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    # ---------------- 证书凭证文件（只读） ----------------

    def _serve_certificate(self, path: str):
        """GET /certificates/<fname> → 读 data/certificates/<fname>（防路径穿越）。"""
        from urllib.parse import unquote
        fname = unquote(os.path.basename(path.rstrip("/")))
        fpath = os.path.normpath(os.path.join(self.app.store.certificates_dir, fname))
        if (os.path.commonpath([os.path.abspath(fpath), os.path.abspath(self.app.store.certificates_dir)]) != os.path.abspath(self.app.store.certificates_dir)
                or not os.path.isfile(fpath)):
            self._send_error(404, "凭证文件不存在")
            return
        ctype = mimetypes.guess_type(fpath)[0] or "application/octet-stream"
        with open(fpath, "rb") as f:
            data = f.read()
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Content-Security-Policy", "sandbox; default-src 'none'; img-src data:; style-src 'unsafe-inline'")
        self.end_headers()
        self.wfile.write(data)

    # ---------------- API 端点 ----------------

    def _api_health(self, method, rest, qs):
        if method != "GET":
            return self._send_error(405, "仅支持 GET")
        self._send(200, {"ok": True, "version": VERSION})

    def _api_schema(self, method, rest, qs):
        if method != "GET":
            return self._send_error(405, "仅支持 GET")
        self._send(200, {
            "schema_version": SCHEMA_VERSION,
            "required": ["name", "deadline"],
            "fields": {
                "name": "比赛名称(必填)", "deadline": "官方截止 YYYY-MM-DD(必填)",
                "suggested_deadline": "临期线 YYYY-MM-DD",
                "deadline_buffer_days": "缓冲天数(默认3)",
                "milestones": "[{name, date}] 中间节点",
                "category": "类别", "organizer": "主办方", "website": "官网链接",
                "signup_start": "报名开始", "signup_end": "报名结束",
                "requirements": "作品要求", "deliverables": "[交付物]",
                "submission": "{method,target,contact,fee,note} 去哪交",
                "format": "{file_types,max_size_mb,naming,note} 格式",
                "tags": "[标签]", "notes": "备注", "source": "agent|manual|file",
                "source_url": "来源链接", "force_update": "true=覆盖已存在",
            },
        })

    def _api_competitions(self, method, rest, qs):
        store = self.app.store
        if method == "GET" and not rest:
            comps = store.all()
            keyword = (qs.get("keyword", [""])[0] or "").strip().lower()
            cats = qs.get("category", [])
            statuses = qs.get("status", [])
            today = date.today()
            items = []
            for c in comps:
                if keyword and keyword not in (c.name + c.organizer + c.notes +
                                               " ".join(c.tags)).lower():
                    continue
                if cats and c.category not in cats:
                    continue
                if statuses and c.status(today) not in statuses:
                    continue
                items.append(serialize(c, today))
            sort = qs.get("sort", ["deadline"])[0]
            rev = qs.get("order", ["asc"])[0] == "desc"
            if sort == "name":
                items.sort(key=lambda x: x["name"], reverse=rev)
            elif sort == "created":
                items.sort(key=lambda x: x.get("created_at", ""), reverse=rev)
            else:
                items.sort(key=lambda x: (x["suggested_deadline"], x["name"]),
                           reverse=rev)
            self._send(200, {"competitions": items, "count": len(items)})
            return
        if method == "POST" and not rest:
            data = self._read_json()
            comp = new_competition(data.get("name", ""), data.get("deadline"), **{
                k: v for k, v in data.items() if k not in ("name", "deadline")})
            store.upsert(comp)
            self._send(201, {"ok": True, "competition": serialize(comp)})
            return
        if method in ("GET", "PUT", "DELETE") and rest:
            cid = rest.split("/")[0]
            comp = store.get(cid)
            if comp is None:
                self._send_error(404, f"记录不存在: {cid}", code="E_NOT_FOUND")
                return
            if method == "GET":
                self._send(200, {"competition": serialize(comp)})
                return
            if method == "PUT":
                data = self._read_json()
                merged = comp.to_dict()
                merged.update({k: v for k, v in data.items() if v is not None})
                merged["id"] = cid
                merged["created_at"] = comp.created_at
                updated = Competition.from_dict(merged)
                store.upsert(updated)
                self._send(200, {"ok": True, "competition": serialize(updated)})
                return
            if method == "DELETE":
                store.delete(cid)
                self._send(200, {"ok": True, "deleted": cid})
                return
        self._send_error(405, "不支持的组合")

    # ---------------- 获奖记录（Award） ----------------

    def _api_awards(self, method, rest, qs):
        store = self.app.store
        # 子路由: /api/awards/import | /api/awards/stats | /api/awards/<id>
        if rest == "import":
            return self._awards_import(method)
        if rest == "stats":
            return self._awards_stats(method)

        if method == "GET" and not rest:
            awards = store.all_awards()
            keyword = (qs.get("keyword", [""])[0] or "").strip().lower()
            levels = qs.get("level", [])
            first_only = qs.get("first", [""])[0] == "true"
            items = []
            for a in awards:
                if keyword:
                    search_text = (a.name + a.competition + a.notes +
                                   a.award_rank + a.role +
                                   " ".join(a.certificate_files) +
                                   str(a.extra.get("note", ""))).lower()
                    if keyword not in search_text:
                        continue
                if levels and a.level not in levels:
                    continue
                if first_only and not a.is_first_author:
                    continue
                items.append(a.to_dict())
            self._send(200, {"awards": items, "count": len(items)})
            return
        if method == "POST" and not rest:
            data = self._read_json()
            award = new_award(str(data.get("name", "")), **{
                k: v for k, v in data.items() if k != "name"})
            store.upsert_award(award)
            self._send(201, {"ok": True, "award": award.to_dict()})
            return
        if method in ("GET", "PUT", "DELETE") and rest:
            aid = rest.split("/")[0]
            award = store.get_award(aid)
            if award is None:
                self._send_error(404, f"获奖记录不存在: {aid}", code="E_NOT_FOUND")
                return
            if method == "GET":
                self._send(200, {"award": award.to_dict()})
                return
            if method == "PUT":
                data = self._read_json()
                merged = award.to_dict()
                merged.update({k: v for k, v in data.items() if v is not None})
                merged["id"] = aid
                merged["created_at"] = award.created_at
                updated = Award.from_dict(merged)
                store.upsert_award(updated)
                self._send(200, {"ok": True, "award": updated.to_dict()})
                return
            if method == "DELETE":
                store.delete_award(aid)
                self._send(200, {"ok": True, "deleted": aid})
                return
        self._send_error(405, "不支持的组合")

    def _awards_import(self, method):
        """POST /api/awards/import —— 批量导入获奖记录（Agent 通道）。"""
        if method != "POST":
            return self._send_error(405, "仅支持 POST")
        data = self._read_json()
        records = data.get("awards") or data.get("records") or []
        if isinstance(records, dict):
            records = [records]
        if not isinstance(records, list):
            return self._send_error(400, "awards 必须是数组")
        report = {"added": 0, "updated": 0, "skipped": 0, "errors": []}
        store = self.app.store
        existing = {a.id: a for a in store.all_awards()}
        to_save = []
        for raw in records:
            if not isinstance(raw, dict):
                report["errors"].append({"name": str(raw)[:30], "reason": "记录不是对象"})
                continue
            try:
                award = Award.from_dict(raw)
            except ValidationError as e:
                report["errors"].append({"name": str(raw.get("name", "?")), "reason": str(e)})
                continue
            dup = existing.get(award.id)
            if dup is not None and not raw.get("force_update"):
                report["skipped"] += 1
                continue
            if dup is not None:
                merged = dup.to_dict()
                merged.update({k: v for k, v in raw.items() if v not in (None, "", [])})
                merged["id"] = dup.id
                merged["created_at"] = dup.created_at
                award = Award.from_dict(merged)
                report["updated"] += 1
            else:
                report["added"] += 1
            existing[award.id] = award  # 同批内去重
            to_save.append(award)
        if to_save:
            store.upsert_awards_many(to_save)
        ok = not report["errors"]
        self._send(200 if ok else 207, {"ok": ok, "report": report})

    def _awards_stats(self, method):
        """GET /api/awards/stats —— 获奖统计（按级别/年份/一作）。"""
        if method != "GET":
            return self._send_error(405, "仅支持 GET")
        awards = self.app.store.all_awards()
        by_level: dict = {}
        by_year: dict = {}
        first_count = 0
        for a in awards:
            by_level[a.level] = by_level.get(a.level, 0) + 1
            if a.award_date:
                by_year[str(a.award_date.year)] = by_year.get(str(a.award_date.year), 0) + 1
            if a.is_first_author:
                first_count += 1
        self._send(200, {
            "total": len(awards),
            "by_level": by_level,
            "by_year": by_year,
            "first_author": first_count,
        })

    def _api_certificates(self, method, rest, qs):
        """POST /api/certificates —— 上传证书凭证文件 {name, data(base64)}。"""
        if method != "POST":
            return self._send_error(405, "仅支持 POST")
        import base64
        data = self._read_json()
        fname = str(data.get("name", "") or "cert")
        b64 = str(data.get("data", "") or "")
        if not b64:
            return self._send_error(400, "缺少文件内容 (data, base64)")
        try:
            raw = base64.b64decode(b64)
        except Exception:  # noqa: BLE001
            return self._send_error(400, "文件内容不是合法 base64")
        if len(raw) > 50 * 1024 * 1024:
            return self._send_error(400, "文件过大（上限 50MB）")
        saved = self.app.store.save_certificate(fname, raw)
        self._send(200, {"ok": True, "filename": saved,
                         "url": f"/certificates/{saved}"})

    # ---------------- 导入 / 同步 / 统计 ----------------

    def _api_import(self, method, rest, qs):
        if method != "POST":
            return self._send_error(405, "仅支持 POST")
        data = self._read_json()
        if "text" in data:  # 界面粘贴文本通道
            records = parse_text(str(data["text"]))
        elif "competitions" in data:
            records = data["competitions"]
        else:
            records = [data]
        update_existing = bool(data.get("update_existing")) or \
            qs.get("update", [""])[0] == "true"
        report = import_records(self.app.store, records,
                                update_existing=update_existing)
        ok = not report["errors"]
        self._send(200 if ok else 207, {"ok": ok, "report": dict(report),
                                        "total": self._total_after(report)})

    @staticmethod
    def _total_after(report: dict) -> int:
        return report["added"] + report["updated"] + report["skipped"] + len(report["errors"])

    def _api_sync(self, method, rest, qs):
        """整表同步（二期能力，直接实现）：mode=merge（按 id 合并）| replace（整表替换）。"""
        if method != "POST":
            return self._send_error(405, "仅支持 POST")
        data = self._read_json()
        mode = data.get("mode", "merge")
        records = data.get("competitions", [])
        if not isinstance(records, list):
            return self._send_error(400, "competitions 必须是数组")
        if mode == "replace":
            from .importer import new_report
            report = new_report()
            parsed = []
            errors = []
            for raw in records:
                try:
                    parsed.append(Competition.from_dict(raw))
                except ValidationError as e:
                    errors.append({"name": str(raw.get("name", "?")), "reason": str(e)})
            store = self.app.store
            if parsed:
                comps = {c.id: c for c in parsed}
                store.replace_all(comps)
            report["added"] = len(parsed)
            report["errors"] = errors
            self._send(200, {"ok": not errors, "report": dict(report), "total": len(parsed)})
            return
        report = import_records(self.app.store, records, update_existing=True)
        self._send(200, {"ok": not report["errors"], "report": dict(report)})

    def _api_stats(self, method, rest, qs):
        if method != "GET":
            return self._send_error(405, "仅支持 GET")
        self._send(200, compute_stats(self.app.store.all()))

    def _api_backup(self, method, rest, qs):
        if method != "POST":
            return self._send_error(405, "仅支持 POST")
        path = self.app.store.backup_now()
        self._send(200, {"ok": True, "backup": os.path.basename(path)})

    def _api_export(self, method, rest, qs):
        """POST /api/export {name, content} → 落盘 data/exports/<name>，返回绝对路径。
        桌面版导出专用（WebView 里 blob 下载落点不明，直接写文件 + 回报路径）。"""
        if method != "POST":
            return self._send_error(405, "仅支持 POST")
        body = self._read_json()
        name = str(body.get("name") or "").strip()
        content = str(body.get("content") or "")
        if not name or not content:
            return self._send_error(400, "缺少 name 或 content")
        # 白名单文件名：防路径穿越；仅允许 json/ics/html/txt 后缀
        if not re.fullmatch(r"[\w\u4e00-\u9fff.\- ]{1,80}", name) or not name.endswith((".json", ".ics", ".html", ".txt")):
            return self._send_error(400, "文件名非法（仅允许 json/ics/html/txt）")
        if len(content.encode("utf-8")) > 10 * 1024 * 1024:
            return self._send_error(400, "内容超过 10MB 上限")
        export_dir = os.path.join(self.app.store.data_dir, "exports")
        os.makedirs(export_dir, exist_ok=True)
        path = os.path.join(export_dir, name)
        with open(path, "w", encoding="utf-8") as f:
            f.write(content)
        self._send(200, {"ok": True, "path": path})

    def _api_export_backup(self, method, rest, qs):
        """POST /api/export_backup → 一键导出全部数据：比赛 + 获奖 + 证书文件打成 zip
        落到 data/exports/工作日历备份_时间.zip，返回绝对路径。"""
        if method != "POST":
            return self._send_error(405, "仅支持 POST")
        import zipfile
        store = self.app.store
        export_dir = os.path.join(store.data_dir, "exports")
        os.makedirs(export_dir, exist_ok=True)
        stamp = datetime.now().strftime("%Y%m%d_%H%M")
        path = os.path.join(export_dir, f"工作日历备份_{stamp}.zip")
        cert_dir = os.path.join(store.data_dir, "certificates")
        cert_files = sorted(os.listdir(cert_dir)) if os.path.isdir(cert_dir) else []
        with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
            z.writestr("导出说明.txt",
                       "工作日历全量备份（含比赛、获奖、证书）\n"
                       f"导出时间：{datetime.now().isoformat(timespec='seconds')}\n"
                       "恢复方式：把 competitions.json / awards.json 放回 data/ 目录（先关闭程序），"
                       "certificates/ 同理。\n")
            if os.path.isfile(store.main_path):
                z.write(store.main_path, "competitions.json")
            if os.path.isfile(store.awards_path):
                z.write(store.awards_path, "awards.json")
            for f in cert_files:
                fp = os.path.join(cert_dir, f)
                if os.path.isfile(fp):
                    z.write(fp, f"certificates/{f}")
        self._send(200, {"ok": True, "path": path,
                         "certificates": len(cert_files)})

    def _api_port(self, method, rest, qs):
        if method != "GET":
            return self._send_error(405, "仅支持 GET")
        self._send(200, {"port": self.app.port})

    def _api_pair(self, method, rest, qs):
        now = time.time()
        with self.app.pair_lock:
            self.app.pending_pairs = {k: v for k, v in self.app.pending_pairs.items() if v["expires"] > now}
            if rest == "begin" and method == "GET":
                code = f"{secrets.randbelow(1000000):06d}"
                self.app.pending_pairs.clear()
                self.app.pending_pairs[code] = {"expires": now + PAIR_TTL, "requested": False, "approved": None, "attempts": 0}
                return self._send(200, {"ok": True, "code": code, "url": f"http://{lan_ip()}:{self.app.port}", "ips": lan_ips(), "port": self.app.port, "expires_in": PAIR_TTL})
            if rest == "confirm" and method == "POST":
                body = self._read_json()
                code = str(body.get("code", ""))
                pair = self.app.pending_pairs.get(code)
                attempts = self.app.pair_attempts
                key = self._client_ip()
                hits, until = attempts.get(key, (0, now + 60))
                if until < now: hits, until = 0, now + 60
                attempts[key] = (hits + 1, until)
                self.app.pair_attempts = {k:v for k,v in attempts.items() if v[1] > now}
                if hits >= 10:
                    return self._send_error(429, "配对尝试过多，请稍后重试")
                if not pair or pair["requested"]:
                    return self._send_error(401, "配对码无效或已使用")
                request_id = secrets.token_urlsafe(24)
                pair.update(requested=True, request_id=request_id, ip=self._client_ip(), expires=now + 60)
                return self._send(202, {"ok": True, "pending": True, "request_id": request_id})
            if rest == "pending" and method == "GET":
                for code, pair in self.app.pending_pairs.items():
                    if pair["requested"] and pair["approved"] is None:
                        return self._send(200, {"ok": True, "pending": True, "code": code, "ip": pair["ip"]})
                return self._send(200, {"ok": True, "pending": False})
            if rest == "approve" and method == "POST":
                body = self._read_json()
                pair = self.app.pending_pairs.get(str(body.get("code", "")))
                if not pair or not pair["requested"] or pair["approved"] is not None:
                    return self._send_error(404, "没有待批准的请求")
                pair["approved"] = body.get("allow") is True
                if pair["approved"]:
                    pair["token"] = secrets.token_urlsafe(32)
                    self.app.paired_tokens.add(pair["token"])
                return self._send(200, {"ok": True})
            if rest == "result" and method == "POST":
                rid = str(self._read_json().get("request_id", ""))
                for pair in self.app.pending_pairs.values():
                    if pair.get("request_id") == rid and pair.get("ip") == self._client_ip():
                        if pair["approved"] is None:
                            return self._send(202, {"ok": True, "pending": True})
                        if not pair["approved"]:
                            return self._send_error(403, "电脑已拒绝配对")
                        return self._send(200, {"ok": True, "token": pair["token"]})
                return self._send_error(403, "请求不存在或已超时，请重新扫码")
            if rest == "revoke" and method == "POST":
                self.app.paired_tokens.clear()
                self.app.pending_pairs.clear()
                return self._send(200, {"ok": True})
        self._send_error(405, "不支持的配对操作")

    def _api_ai_config(self, method, rest, qs):
        """GET /api/ai_config → 配置视图（密钥不回传）；POST → 保存 {provider, api_key?, model?, base_url?}"""
        if method == "GET":
            self._send(200, aimod.public_config(self.app.ai_cfg.load()))
            return
        if method == "POST":
            data = self._read_json()
            cfg = self.app.ai_cfg.save(data)
            self._send(200, aimod.public_config(cfg))
            return
        self._send_error(405, "仅支持 GET/POST")

    def _api_ai_chat(self, method, rest, qs):
        """POST /api/ai_chat {messages:[{role,content}...]} → {ok, reply, trace}
        服务端跑完整工具循环，AI 可直接增删改查比赛数据。"""
        if method != "POST":
            return self._send_error(405, "仅支持 POST")
        data = self._read_json()
        messages = data.get("messages") or []
        def _ok(m):
            if not isinstance(m, dict) or m.get("role") not in ("user", "assistant"):
                return False
            c = m.get("content")
            return isinstance(c, str) or (m["role"] == "user" and isinstance(c, list))
        messages = [m for m in messages if _ok(m)]
        if not messages or messages[-1].get("role") != "user":
            return self._send_error(400, "messages 最后一条必须是 user 消息")
        try:
            result = aimod.chat(self.app.ai_cfg.load(), self.app.store, messages)
        except RuntimeError as e:
            import traceback
            try:
                self.app.store.error(f"AI 调用失败: {e}", traceback.format_exc())
            except Exception:
                pass
            self._send(200, {"ok": False, "error": str(e), "trace": []})
            return
        self._send(200, {"ok": True, **result})

    def _api_bootstrap(self, method, rest, qs):
        """GET /api/bootstrap → 仅限本机回环：下发 API Token 给本机前端。
        局域网/外部请求一律 403（手机走扫码配对获取 Sync Token）。"""
        if method != "GET":
            return self._send_error(405, "仅支持 GET")
        if not self._is_loopback():
            return self._send_error(403, "仅限本机访问", code="E_LOCAL_ONLY")
        if self.headers.get("X-WorkCalendar-Bootstrap") != "1":
            return self._send_error(403, "需要本机前端初始化请求")
        self.issue_cookie = True
        token = self.app.token or ""
        self._send(200, {"ok": True, "token": token})

    def _api_ai_chat_async(self, method, rest, qs):
        """POST /api/ai_chat_async {messages} → {ok, job_id}。后台线程执行，前端轮询 /api/ai_status。"""
        if method != "POST":
            return self._send_error(405, "仅支持 POST")
        data = self._read_json()
        messages = data.get("messages") or []

        def _ok(m):
            if not isinstance(m, dict) or m.get("role") not in ("user", "assistant"):
                return False
            c = m.get("content")
            return isinstance(c, str) or (m["role"] == "user" and isinstance(c, list))
        messages = [m for m in messages if _ok(m)]
        if not messages or messages[-1].get("role") != "user":
            return self._send_error(400, "messages 最后一条必须是 user 消息")
        job_id = secrets.token_hex(8)
        with self.app.ai_jobs_lock:
            self.app.ai_jobs[job_id] = {"running": True, "status": "排队中…", "started": time.time(),
                                    "result": None, "ts": time.time()}

        def _worker():
            job = self.app.ai_jobs.get(job_id)
            try:
                result = aimod.chat(self.app.ai_cfg.load(), self.app.store, messages,
                                    on_status=lambda t: job.update({"status": t}))
                job.update({"running": False, "result": {"ok": True, **result}})
            except RuntimeError as e:
                job.update({"running": False, "result": {"ok": False, "error": str(e), "trace": []}})
            except Exception as e:
                import traceback
                try:
                    self.app.store.error(f"AI 异步调用失败: {e}", traceback.format_exc())
                except Exception:
                    pass
                job.update({"running": False,
                            "result": {"ok": False, "error": f"内部错误: {e}", "trace": []}})
        threading.Thread(target=_worker, daemon=True).start()
        self._send(200, {"ok": True, "job_id": job_id})

    def _api_ai_status(self, method, rest, qs):
        """GET /api/ai_status?id=<job_id> → {running, status, result?}"""
        if method != "GET":
            return self._send_error(405, "仅支持 GET")
        job_id = (qs.get("id", [""])[0] or "").strip()
        with self.app.ai_jobs_lock:
            job = self.app.ai_jobs.get(job_id)
            # 清理 10 分钟前的旧任务
            now = time.time()
            for k in [k for k, v in self.app.ai_jobs.items() if now - v["ts"] > 600]:
                self.app.ai_jobs.pop(k, None)
        if not job:
            return self._send_error(404, "任务不存在或已过期")
        out = {"running": job["running"], "status": job["status"]}
        if not job["running"] and job["result"]:
            out.update(job["result"])
        self._send(200, out)

    def _api_open_folder(self, method, rest, qs):
        """POST /api/open_folder {target:'exports'|'logs'} → 资源管理器打开对应目录（仅限白名单）"""
        if method != "POST":
            return self._send_error(405, "仅支持 POST")
        data = self._read_json()
        target = str(data.get("target") or "")
        path = {"exports": os.path.join(self.app.store.data_dir, "exports"),
                "logs": self.app.store.logs_dir}.get(target)
        if not path:
            return self._send_error(400, "未知目录")
        os.makedirs(path, exist_ok=True)
        if not os.path.isdir(path):
            return self._send_error(404, "目录不存在")
        try:
            os.startfile(path)  # Windows 资源管理器
        except AttributeError:
            return self._send_error(500, "当前系统不支持打开文件夹")
        self._send(200, {"ok": True, "path": path})

    def _api_export_logs(self, method, rest, qs):
        """POST /api/export_logs → 打包 data/logs/*.log 到 data/exports/日志_时间.zip（反馈问题用）"""
        if method != "POST":
            return self._send_error(405, "仅支持 POST")
        import zipfile as _zip
        logs_dir = self.app.store.logs_dir
        log_files = sorted(f for f in os.listdir(logs_dir) if f.endswith(".log")) if os.path.isdir(logs_dir) else []
        if not log_files:
            return self._send_error(404, "暂无日志文件")
        os.makedirs(os.path.join(self.app.store.data_dir, "exports"), exist_ok=True)
        stamp = datetime.now().strftime("%Y%m%d_%H%M")
        path = os.path.join(self.app.store.data_dir, "exports", f"日志_{stamp}.zip")
        with _zip.ZipFile(path, "w", _zip.ZIP_DEFLATED) as z:
            for f in log_files:
                z.write(os.path.join(logs_dir, f), f)
        self._send(200, {"ok": True, "path": path, "count": len(log_files)})

    def _api_client_log(self, method, rest, qs):
        """POST /api/client_log {message, stack?} → 前端报错落盘 data/logs/client_日期.log"""
        if method != "POST":
            return self._send_error(405, "仅支持 POST")
        data = self._read_json()
        msg = str(data.get("message") or "")[:500]
        stack = str(data.get("stack") or "")[:2000]
        if not msg:
            return self._send_error(400, "缺少 message")
        try:
            store = self.app.store
            fp = os.path.join(store.logs_dir,
                              "client_" + datetime.now().strftime("%Y-%m-%d") + ".log")
            with open(fp, "a", encoding="utf-8") as f:
                f.write(f"[{datetime.now().strftime('%H:%M:%S')}] {msg}\n")
                if stack:
                    for line in stack.strip().splitlines()[:20]:
                        f.write(f"    {line}\n")
        except OSError:
            pass
        self._send(200, {"ok": True})

    def _api_export_all(self, method, rest, qs):
        """全量导出（同步用，GET /api/export_all）：比赛 + 获奖，含原始字段（不含计算字段）。"""
        if method != "GET":
            return self._send_error(405, "仅支持 GET")
        if not self._check_sync_token():
            return self._send_error(401, "请先扫码配对", code="E_PAIR")
        store = self.app.store
        self._send(200, {
            "ok": True,
            "version": VERSION,
            "exported_at": datetime.now().isoformat(timespec="seconds"),
            "competitions": [c.to_dict() for c in store.all()],
            "awards": [a.to_dict() for a in store.all_awards()],
        })

    def _api_import_all(self, method, rest, qs):
        """全量导入（同步用，POST /api/import_all）。mode=replace 以传入为准重建；mode=merge 按 id 合并。
        返回 {competitions/awards: {added, updated, skipped}}。"""
        if method != "POST":
            return self._send_error(405, "仅支持 POST")
        if not self._check_sync_token():
            return self._send_error(401, "请先扫码配对", code="E_PAIR")
        data = self._read_json()
        mode = data.get("mode", "merge")
        store = self.app.store
        comps_in = data.get("competitions") or []
        awards_in = data.get("awards") or []
        rep = {"competitions": {"added": 0, "updated": 0, "skipped": 0},
               "awards": {"added": 0, "updated": 0, "skipped": 0}}

        def _parse_comp(raw):
            c = Competition.from_dict(raw, strict=False)
            return c

        def _parse_award(raw):
            a = Award.from_dict(raw, strict=False)
            return a

        if mode == "replace":
            comp_map = {}
            for raw in comps_in:
                try:
                    c = _parse_comp(raw)
                    comp_map[c.id] = c
                except Exception:  # noqa: BLE001 —— 单条失败不中断
                    rep["competitions"]["skipped"] += 1
            store.replace_all(comp_map)
            rep["competitions"]["added"] = len(comp_map)
            aw_map = {}
            for raw in awards_in:
                try:
                    a = _parse_award(raw)
                    aw_map[a.id] = a
                except Exception:  # noqa: BLE001
                    rep["awards"]["skipped"] += 1
            store.save_awards(aw_map)
            rep["awards"]["added"] = len(aw_map)
        else:
            keep_comps, keep_awards = [], []
            for raw in comps_in:
                try:
                    c = _parse_comp(raw)
                    if store.get(c.id):
                        rep["competitions"]["updated"] += 1
                    else:
                        rep["competitions"]["added"] += 1
                    keep_comps.append(c)
                except Exception:  # noqa: BLE001
                    rep["competitions"]["skipped"] += 1
            for raw in awards_in:
                try:
                    a = _parse_award(raw)
                    if store.get_award(a.id):
                        rep["awards"]["updated"] += 1
                    else:
                        rep["awards"]["added"] += 1
                    keep_awards.append(a)
                except Exception:  # noqa: BLE001
                    rep["awards"]["skipped"] += 1
            store.upsert_many(keep_comps)
            store.upsert_awards_many(keep_awards)
        self._send(200, {"ok": True, "mode": mode, "report": rep})


class ApiServer:
    """本地 HTTP 服务。start() 后返回实际端口（port=0 → 随机）。"""

    def __init__(self, store: Store, port: int = 0, token: Optional[str] = None,
                 web_dir: Optional[str] = None, host: str = "127.0.0.1"):
        self.store = store
        self.token = token or secrets.token_urlsafe(32)
        self.browser_session = secrets.token_urlsafe(32)
        self.pair_lock = threading.RLock()
        self.pair_attempts = {}
        self.web_dir = web_dir
        self.port = port
        self.host = host
        self.paired_tokens: set = set()
        self.pair_approval: Optional[dict] = None
        self.ai_cfg = aimod.AiConfig(store.data_dir)
        self.ai_jobs = {}
        self.ai_jobs_lock = threading.Lock()
        self.pending_pairs: dict = {}
        self._httpd: Optional[ThreadingHTTPServer] = None
        self._thread: Optional[threading.Thread] = None

    def start(self) -> int:
        class Server(ThreadingHTTPServer):
            app: ApiServer
            daemon_threads = True

        self._httpd = Server((self.host, self.port), ApiHandler)
        self._httpd.app = self  # type: ignore[attr-defined]
        self.port = self._httpd.server_address[1]
        self._thread = threading.Thread(target=self._httpd.serve_forever,
                                        name="api-server", daemon=True)
        self._thread.start()
        return self.port

    def stop(self):
        if self._httpd:
            self._httpd.shutdown()
            self._httpd.server_close()
            self._httpd = None

    def try_bind(self) -> bool:
        """探测固定端口是否可绑定（单实例锁辅助）。"""
        import socket
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        try:
            s.bind((self.host, self.port))
            return True
        except OSError:
            return False
        finally:
            s.close()
