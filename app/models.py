# -*- coding: utf-8 -*-
"""领域模型：Competition 数据类、校验、状态与倒计时计算、去重键。

纯标准库、无副作用 —— 状态/倒计时全部为计算属性，不落盘。
"""
from __future__ import annotations

import hashlib
import re
from dataclasses import dataclass, field
from datetime import date, datetime, timedelta
from typing import Any, Optional

# ---------------------------------------------------------------------------
# 常量与默认值
# ---------------------------------------------------------------------------

DEFAULT_BUFFER_DAYS = 3          # 未填临期线时的默认缓冲天数
DEFAULT_REMINDER_DAYS = [7, 1]   # 默认提前提醒天数
URGENT_DAYS = 7                  # 临期线前 N 天进入"即将截止"
SCHEMA_VERSION = 1

VALID_OVERRIDES = {"submitted", "done", "abandoned"}
VALID_SOURCES = {"agent", "manual", "file"}
# 类别不做硬校验（宽松原则），仅作为筛选建议值
CATEGORY_HINTS = ["视觉传达", "工业设计", "环境艺术", "数字媒体", "服装设计", "综合"]

# ---- 获奖记录（Award）常量 ----
VALID_AWARD_LEVELS = ["校级", "市级", "省级", "国家级", "国际级"]
VALID_AWARD_ROLES = ["一作", "二作", "三作", "参与", "独立完成", "队长"]
AWARD_LEVEL_HINTS = ["校级", "市级", "省级", "国家级", "国际级"]

_DATE_RE = re.compile(r"^(\d{4})-(\d{1,2})-(\d{1,2})$")

# 全角 → 半角（字母/数字/常用标点/空格），用于名称归一化
_FW_SRC = ("ＡＢＣＤＥＦＧＨＩＪＫＬＭＮＯＰＱＲＳＴＵＶＷＸＹＺ"
           "ａｂｃｄｅｆｇｈｉｊｋｌｍｎｏｐｑｒｓｔｕｖｗｘｙｚ"
           "０１２３４５６７８９　（）：，。！？；‘’“”")
_FW_DST = ("ABCDEFGHIJKLMNOPQRSTUVWXYZ"
           "abcdefghijklmnopqrstuvwxyz"
           "0123456789 "  # 全角空格
           "():,.!?;"     # （）：，。！？；
           "''\"\"")      # ‘’“”
_FULLWIDTH_TRANS = str.maketrans(_FW_SRC, _FW_DST)
assert len(_FW_SRC) == len(_FW_DST) == 75


class ValidationError(Exception):
    """单条记录校验失败（携带可读中文原因）。"""


# ---------------------------------------------------------------------------
# 基础工具函数
# ---------------------------------------------------------------------------

def parse_date(value: Any) -> Optional[date]:
    """解析 YYYY-MM-DD（容错 1 位月/日）；非法输入返回 None，不抛异常。"""
    if value is None or value == "":
        return None
    if isinstance(value, datetime):
        return value.date()
    if isinstance(value, date):
        return value
    if isinstance(value, str):
        m = _DATE_RE.match(value.strip())
        if m:
            try:
                return date(int(m.group(1)), int(m.group(2)), int(m.group(3)))
            except ValueError:
                return None
    return None


def normalize_name(name: Any) -> str:
    """去重键用：去首尾空白、全角转半角（含字母数字）、统一大小写。"""
    if name is None:
        return ""
    s = str(name).strip()
    s = s.translate(_FULLWIDTH_TRANS)
    s = re.sub(r"\s+", " ", s)
    return s.casefold()


def dedup_key(name: Any, deadline: Any) -> str:
    """去重键 = 归一化名称 + '|' + 截止日期。同一条记录永远同键。"""
    d = parse_date(deadline)
    dstr = d.isoformat() if d else ""
    return f"{normalize_name(name)}|{dstr}"


def make_id(name: Any, deadline: Any) -> str:
    """id = 'c_' + 去重键哈希前 8 位（与去重键天然一致）。"""
    return "c_" + hashlib.sha1(dedup_key(name, deadline).encode("utf-8")).hexdigest()[:8]


def now_iso() -> str:
    return datetime.now().astimezone().isoformat(timespec="seconds")


# ---------------------------------------------------------------------------
# Competition 数据类
# ---------------------------------------------------------------------------

@dataclass
class Competition:
    """一条比赛记录。字段规则：name/deadline 必填，其余可选。

    status_override: null(跟随系统) | submitted | done | abandoned
    milestones: [{"name": str, "date": "YYYY-MM-DD"}, ...]
    """
    id: str
    name: str
    deadline: date
    suggested_deadline: Optional[date] = None
    deadline_buffer_days: Optional[int] = None
    milestones: list = field(default_factory=list)
    category: str = ""
    organizer: str = ""
    website: str = ""
    signup_start: Optional[date] = None
    signup_end: Optional[date] = None
    deadline_note: str = ""
    requirements: str = ""
    deliverables: list = field(default_factory=list)
    submission: dict = field(default_factory=dict)
    format: dict = field(default_factory=dict)
    tags: list = field(default_factory=list)
    status_override: Optional[str] = None
    reminder_days: list = field(default_factory=lambda: list(DEFAULT_REMINDER_DAYS))
    notes: str = ""
    source: str = "manual"
    source_url: str = ""
    created_at: str = ""
    updated_at: str = ""
    # 未知字段原样保留（向前兼容，不丢弃）
    extra: dict = field(default_factory=dict)

    # ------------------------------------------------------------------
    # 计算属性：临期线 / 倒计时 / 状态（永不落盘）
    # ------------------------------------------------------------------

    def effective_suggested(self) -> date:
        """临期线 = suggested_deadline，未填则 deadline − buffer_days（默认 3）。"""
        if self.suggested_deadline is not None:
            return self.suggested_deadline
        buf = self.deadline_buffer_days
        if buf is None:
            buf = DEFAULT_BUFFER_DAYS
        return self.deadline - timedelta(days=max(0, int(buf)))

    def countdown(self, today: Optional[date] = None) -> int:
        """距临期线剩余自然日（今天截止=0，已过=负）。"""
        return (self.effective_suggested() - (today or date.today())).days

    def official_countdown(self, today: Optional[date] = None) -> int:
        """距官方截止剩余自然日。"""
        return (self.deadline - (today or date.today())).days

    def status(self, today: Optional[date] = None) -> str:
        """自动状态 + override 叠加。"""
        if self.status_override in VALID_OVERRIDES:
            return self.status_override
        today = today or date.today()
        s = self.effective_suggested()
        if today > self.deadline:
            return "overdue"
        if today > s:
            return "past_suggested"
        if (s - today).days <= URGENT_DAYS:
            return "urgent"
        if self.signup_start and today < self.signup_start:
            return "not_started"
        if self.signup_end and today <= self.signup_end:
            return "open"
        return "submitting"

    def milestone_countdowns(self, today: Optional[date] = None) -> list:
        """里程碑逐条倒计时：[{"name":..., "date":..., "days": int}]。"""
        today = today or date.today()
        out = []
        for ms in self.milestones or []:
            d = parse_date(ms.get("date"))
            if d is None:
                continue
            out.append({"name": str(ms.get("name", "")), "date": d.isoformat(),
                        "days": (d - today).days})
        return out

    # ------------------------------------------------------------------
    # 序列化 / 反序列化
    # ------------------------------------------------------------------

    def to_dict(self) -> dict:
        d = {
            "id": self.id, "name": self.name, "deadline": self.deadline.isoformat(),
            "suggested_deadline": self.suggested_deadline.isoformat() if self.suggested_deadline else None,
            "deadline_buffer_days": self.deadline_buffer_days,
            "milestones": self.milestones,
            "category": self.category, "organizer": self.organizer, "website": self.website,
            "signup_start": self.signup_start.isoformat() if self.signup_start else None,
            "signup_end": self.signup_end.isoformat() if self.signup_end else None,
            "deadline_note": self.deadline_note, "requirements": self.requirements,
            "deliverables": self.deliverables, "submission": self.submission,
            "format": self.format, "tags": self.tags,
            "status_override": self.status_override, "reminder_days": self.reminder_days,
            "notes": self.notes, "source": self.source, "source_url": self.source_url,
            "created_at": self.created_at, "updated_at": self.updated_at,
        }
        d.update(self.extra or {})
        return d

    @classmethod
    def from_dict(cls, data: dict, strict: bool = True) -> "Competition":
        """从字典构造。strict=True 时校验必填与日期逻辑；否则尽量宽松（用于文件加载自愈）。"""
        name = str(data.get("name", "")).strip()
        deadline = parse_date(data.get("deadline"))
        if strict:
            if not name:
                raise ValidationError("name 不能为空")
            if deadline is None:
                raise ValidationError(f"deadline 不是有效日期: {data.get('deadline')!r}")
        elif not name or deadline is None:
            raise ValidationError("name/deadline 缺失或非法")

        suggested = parse_date(data.get("suggested_deadline"))
        signup_start = parse_date(data.get("signup_start"))
        signup_end = parse_date(data.get("signup_end"))
        override = data.get("status_override") or None
        if override is not None and override not in VALID_OVERRIDES:
            raise ValidationError(f"status_override 非法: {override!r}")

        if signup_start and signup_end and signup_start > signup_end:
            raise ValidationError("报名开始晚于报名结束")
        if suggested and suggested > deadline:
            raise ValidationError("临期线晚于官方截止")
        for ms in data.get("milestones") or []:
            if not isinstance(ms, dict):
                raise ValidationError("milestones 项必须是对象 {name, date}")
            d = parse_date(ms.get("date"))
            if d is None:
                raise ValidationError(f"milestone 日期非法: {ms!r}")
            if d > deadline:
                raise ValidationError(f"里程碑 {ms.get('name', '')} 晚于官方截止")

        known = {"id", "name", "deadline", "suggested_deadline", "deadline_buffer_days",
                 "milestones", "category", "organizer", "website", "signup_start",
                 "signup_end", "deadline_note", "requirements", "deliverables",
                 "submission", "format", "tags", "status_override", "reminder_days",
                 "notes", "source", "source_url", "created_at", "updated_at"}
        extra = {k: v for k, v in data.items() if k not in known}

        return cls(
            id=str(data.get("id") or make_id(name, deadline)),
            name=name, deadline=deadline,
            suggested_deadline=suggested,
            deadline_buffer_days=_int_or_none(data.get("deadline_buffer_days")),
            milestones=[{"name": str(m.get("name", "") or ""),
                         "date": parse_date(m.get("date")).isoformat()}
                        for m in (data.get("milestones") or [])],
            category=str(data.get("category", "") or ""),
            organizer=str(data.get("organizer", "") or ""),
            website=str(data.get("website", "") or ""),
            signup_start=signup_start, signup_end=signup_end,
            deadline_note=str(data.get("deadline_note", "") or ""),
            requirements=str(data.get("requirements", "") or ""),
            deliverables=list(data.get("deliverables") or []),
            submission=dict(data.get("submission") or {}),
            format=dict(data.get("format") or {}),
            tags=list(data.get("tags") or []),
            status_override=override,
            reminder_days=list(data.get("reminder_days") or DEFAULT_REMINDER_DAYS),
            notes=str(data.get("notes", "") or ""),
            source=str(data.get("source", "manual") or "manual"),
            source_url=str(data.get("source_url", "") or ""),
            created_at=str(data.get("created_at", "") or ""),
            updated_at=str(data.get("updated_at", "") or ""),
            extra=extra,
        )


def _int_or_none(v: Any) -> Optional[int]:
    if v is None or v == "":
        return None
    try:
        return max(0, int(v))
    except (TypeError, ValueError):
        return None


# ---------------------------------------------------------------------------
# Award 获奖记录
# ---------------------------------------------------------------------------

def make_award_id(name: Any, award_date: Any) -> str:
    """id = 'a_' + 去重键哈希前 8 位。"""
    d = parse_date(award_date)
    dstr = d.isoformat() if d else ""
    key = f"{normalize_name(name)}|{dstr}"
    return "a_" + hashlib.sha1(key.encode("utf-8")).hexdigest()[:8]


@dataclass
class Award:
    """一条获奖记录。name 必填，其余可选。

    level:            校级 | 市级 | 省级 | 国家级 | 国际级
    award_rank:       奖项等级（一等奖/金奖/银奖/铜奖/优秀奖/入围…自由文本）
    is_first_author:  是否一作（第一作者/独立完成）
    role:             作者角色（一作/二作/三作/参与/独立完成/队长…自由文本）
    competition:      关联的比赛名称（与 Competition.name 对应，便于跳转）
    certificate_files: 凭证文件列表（data/certificates/ 下的文件名或相对路径）
    """
    id: str
    name: str
    level: str = "校级"
    award_rank: str = ""
    is_first_author: bool = False
    role: str = ""
    competition: str = ""
    award_date: Optional[date] = None
    certificate_files: list = field(default_factory=list)
    notes: str = ""
    source: str = "manual"
    source_url: str = ""
    created_at: str = ""
    updated_at: str = ""
    extra: dict = field(default_factory=dict)

    # ------------------------------------------------------------------
    # 序列化 / 反序列化
    # ------------------------------------------------------------------

    def to_dict(self) -> dict:
        d = {
            "id": self.id, "name": self.name, "level": self.level,
            "award_rank": self.award_rank, "is_first_author": self.is_first_author,
            "role": self.role, "competition": self.competition,
            "award_date": self.award_date.isoformat() if self.award_date else None,
            "certificate_files": self.certificate_files,
            "notes": self.notes, "source": self.source, "source_url": self.source_url,
            "created_at": self.created_at, "updated_at": self.updated_at,
        }
        d.update(self.extra or {})
        return d

    @classmethod
    def from_dict(cls, data: dict, strict: bool = True) -> "Award":
        name = str(data.get("name", "")).strip()
        if strict and not name:
            raise ValidationError("name 不能为空")
        if not strict and not name:
            raise ValidationError("name 缺失")
        award_date = parse_date(data.get("award_date"))
        level = str(data.get("level", "校级") or "校级").strip()
        if level not in VALID_AWARD_LEVELS:
            level = "校级"  # 宽松：非法级别回落默认，不报错
        first = data.get("is_first_author")
        is_first = first is True or str(first).lower() in ("true", "1", "yes", "是", "一作", "第一作者")
        # 兼容旧导入：certificate/note 别名 → certificate_files/notes（2026-08-11 修复）
        certs = data.get("certificate_files") or data.get("certificate") or []
        if not isinstance(certs, list):
            certs = [certs] if certs else []
        known = {"id", "name", "level", "award_rank", "is_first_author", "role",
                 "competition", "award_date", "certificate_files", "notes",
                 "source", "source_url", "created_at", "updated_at"}
        extra = {k: v for k, v in data.items() if k not in known}
        return cls(
            id=str(data.get("id") or make_award_id(name, award_date)),
            name=name, level=level,
            award_rank=str(data.get("award_rank", "") or ""),
            is_first_author=is_first,
            role=str(data.get("role", "") or ""),
            competition=str(data.get("competition", "") or ""),
            award_date=award_date,
            certificate_files=[str(c) for c in certs],
            notes=str(data.get("notes") or data.get("note") or ""),
            source=str(data.get("source", "manual") or "manual"),
            source_url=str(data.get("source_url", "") or ""),
            created_at=str(data.get("created_at", "") or ""),
            updated_at=str(data.get("updated_at", "") or ""),
            extra=extra,
        )


def new_award(name: str, **kwargs) -> Award:
    """创建获奖记录（自动补 id / 时间戳 / source 校验）。"""
    if not name:
        raise ValidationError("name 必填")
    a = Award.from_dict({"name": name, **kwargs})
    a.id = make_award_id(a.name, a.award_date)
    ts = now_iso()
    a.created_at = a.created_at or ts
    a.updated_at = ts
    if a.source not in VALID_SOURCES:
        a.source = "manual"
    return a


# ---------------------------------------------------------------------------
# 便捷工厂
# ---------------------------------------------------------------------------

def new_competition(name: str, deadline: Any, **kwargs) -> Competition:
    """创建新记录（自动补 id / 时间戳 / source 校验）。"""
    d = parse_date(deadline)
    if not name or d is None:
        raise ValidationError("name 与 deadline 必填")
    c = Competition.from_dict({"name": name, "deadline": d.isoformat(), **kwargs})
    c.id = make_id(c.name, c.deadline)
    ts = now_iso()
    c.created_at = c.created_at or ts
    c.updated_at = ts
    if c.source not in VALID_SOURCES:
        c.source = "manual"
    return c
