# -*- coding: utf-8 -*-
"""导入引擎：解析（JSON 三种形态 / Markdown 表格）、去重、字段级合并、报告。

所有通道（文件监听 / HTTP / 界面粘贴）共用本模块，行为一致。
"""
from __future__ import annotations

import json
import os
import re
from typing import Optional

from .models import (Competition, ValidationError, dedup_key, make_id, now_iso)
from .storage import Store

# Markdown 表头 → 字段 的中英文别名
_MD_COL_ALIASES = {
    "name": ["名称", "name", "比赛", "比赛名称"],
    "deadline": ["截止", "deadline", "截止日期", "截止时间", "提交截止"],
    "suggested_deadline": ["临期线", "建议死线", "建议截止", "校内截止", "suggested_deadline"],
    "category": ["类别", "category", "分类"],
    "organizer": ["主办方", "organizer", "主办"],
    "website": ["官网", "website", "网址", "链接", "官网链接"],
    "requirements": ["要求", "requirements", "作品要求"],
    "notes": ["备注", "notes", "说明"],
}

# 顶层结构键（Agent 常见三种形态）
_ACCEPTED_KEYS = {"competitions", "items", "records", "data"}


class ImportReport(dict):
    """导入报告：{added, updated, skipped, errors: [{name, reason}]}"""

    @property
    def total(self) -> int:
        return self["added"] + self["updated"] + self["skipped"]


def new_report() -> ImportReport:
    return ImportReport(added=0, updated=0, skipped=0, errors=[])


# ---------------------------------------------------------------------------
# 解析
# ---------------------------------------------------------------------------

def parse_json_text(text: str) -> list:
    """解析 JSON 文本 → 记录字典列表。支持：单条对象 / 数组 / {competitions:[...]}。"""
    try:
        data = json.loads(text)
    except json.JSONDecodeError as e:
        raise ValidationError(f"JSON 解析失败: {e}")
    if isinstance(data, dict):
        for key in _ACCEPTED_KEYS:
            if key in data:
                data = data[key]
                break
    if isinstance(data, dict):
        return [data]  # 单条记录
    if isinstance(data, list):
        return [d for d in data if isinstance(d, dict)]
    raise ValidationError("JSON 顶层必须是对象或数组")


def parse_markdown_table(text: str) -> list:
    """解析 Markdown 表格 → 记录字典列表。首行表头按别名映射字段。"""
    lines = [l.strip() for l in text.splitlines()
             if l.strip().startswith("|") and "|" in l.strip()[1:]]
    if len(lines) < 2:
        raise ValidationError("未找到 Markdown 表格")
    header = [c.strip() for c in lines[0].strip().strip("|").split("|")]
    if all(re.fullmatch(r"[\s\-:|]+", c) for c in
           [c.strip() for c in lines[1].strip().strip("|").split("|")]):
        lines = lines[:1] + lines[2:]

    # 表头 → 字段映射（支持别名；未知列忽略）
    field_map = []
    for col in header:
        f = None
        for field, aliases in _MD_COL_ALIASES.items():
            if col in aliases:
                f = field
                break
        field_map.append(f)

    records = []
    for ln in lines[1:]:
        cells = [c.strip() for c in ln.strip().strip("|").split("|")]
        rec = {}
        for i, cell in enumerate(cells):
            if i < len(field_map) and field_map[i] and cell:
                rec[field_map[i]] = cell
        if rec.get("name") or rec.get("deadline"):
            records.append(rec)
    return records


def parse_text(text: str) -> list:
    """自动探测格式：JSON 优先，失败则尝试 Markdown 表格。"""
    stripped = text.strip()
    if not stripped:
        raise ValidationError("内容为空")
    if stripped.startswith(("{", "[")):
        try:
            return parse_json_text(stripped)
        except ValidationError:
            pass  # 落到 Markdown
    try:
        return parse_markdown_table(stripped)
    except ValidationError:
        raise ValidationError("无法识别内容格式（支持 JSON 或 Markdown 表格）")


# ---------------------------------------------------------------------------
# 去重 / 合并 / 导入
# ---------------------------------------------------------------------------

def _merge_records(old: Competition, new_data: dict) -> Competition:
    """字段级合并：新数据仅覆盖非空字段；保留用户补充与手动标记。"""
    merged = old.to_dict()
    for k, v in new_data.items():
        if v is None or v == "" or v == [] or v == {}:
            continue
        merged[k] = v
    # 手动标记永不被导入覆盖
    if old.status_override:
        merged["status_override"] = old.status_override
    merged["id"] = old.id
    merged["created_at"] = old.created_at
    merged["updated_at"] = now_iso()
    return Competition.from_dict(merged)


def import_records(store: Store, records: list,
                   update_existing: bool = False, force_update: bool = False) -> ImportReport:
    """批量导入（经单写者队列执行）。

    update_existing: 全局开关 —— 命中已存在记录时覆盖更新。
    force_update:    单条记录带 force_update=true 时覆盖更新。
    返回导入报告；任何异常都记录到 errors，不影响其余记录。
    """
    report = new_report()

    def _do() -> ImportReport:
        existing = {c.id: c for c in store.all()}
        index = {dedup_key(c.name, c.deadline): c for c in existing.values()}
        to_upsert: list[Competition] = []
        now = now_iso()

        for raw in records:
            if not isinstance(raw, dict):
                report["errors"].append({"name": str(raw)[:30], "reason": "记录不是对象"})
                continue
            try:
                comp = Competition.from_dict(raw)
            except ValidationError as e:
                report["errors"].append({"name": str(raw.get("name", "?")), "reason": str(e)})
                continue

            key = dedup_key(comp.name, comp.deadline)
            dup = index.get(key)
            force = bool(raw.get("force_update")) or (update_existing and dup is not None)
            if dup is not None and not force:
                report["skipped"] += 1
                continue
            if dup is not None and force:
                merged = _merge_records(dup, raw)
                merged.id = dup.id
                merged.created_at = dup.created_at
                index[key] = merged
                to_upsert.append(merged)
                report["updated"] += 1
                continue
            comp.id = make_id(comp.name, comp.deadline)
            if comp.created_at in ("", None):
                comp.created_at = now
            comp.updated_at = now
            index[key] = comp
            to_upsert.append(comp)
            report["added"] += 1

        if to_upsert:
            store.upsert_many(to_upsert)
        return report

    return store.submit(_do)


# ---------------------------------------------------------------------------
# 文件通道辅助（通道 A：import/ 目录监听）
# ---------------------------------------------------------------------------

def handle_import_file(store: Store, path: str, update_existing: bool = False,
                       archive: bool = True) -> Optional[ImportReport]:
    """处理导入文件：解析 → 导入 → 报告。

    archive=True（文件监听通道）：成功移入 done/ 并附报告，失败留原地附 .error.txt。
    archive=False（无头 --import 通道）：不移动源文件（Agent 自己的文件保留原位），
    报告写入 done/ 目录。
    """
    fname = os.path.basename(path)
    if not os.path.isfile(path):
        _write_error(path, "文件不存在")
        return None
    try:
        with open(path, encoding="utf-8") as f:
            text = f.read()
    except (OSError, UnicodeDecodeError) as e:
        _write_error(path, f"读取失败: {e}")
        return None

    try:
        records = parse_text(text)
    except ValidationError as e:
        _write_error(path, str(e))
        return None

    report = import_records(store, records, update_existing=update_existing)

    # 归档：成功移入 done/（附报告），失败留原地附错误说明
    done_path = os.path.join(store.import_done_dir, fname)
    try:
        if archive:
            os.replace(path, done_path)
        with open(done_path + ".report.json", "w", encoding="utf-8") as f:
            json.dump(dict(report), f, ensure_ascii=False, indent=2)
    except OSError:
        pass
    return report


def _write_error(path: str, reason: str):
    try:
        with open(path + ".error.txt", "w", encoding="utf-8") as f:
            f.write(reason + "\n")
    except OSError:
        pass
