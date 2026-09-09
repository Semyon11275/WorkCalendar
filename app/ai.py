# -*- coding: utf-8 -*-
"""AI 助手后端：LLM 对话 + 工具调用（操作比赛/获奖数据）。

支持的厂商均为 OpenAI 兼容 chat/completions 接口，预设三家（均可改 base_url/model）：
- DeepSeek   https://api.deepseek.com        deepseek-chat
- 智谱 GLM   https://open.bigmodel.cn/api/paas/v4  glm-4-flash
- 小米 MiMo  https://api.siliconflow.cn/v1   XiaomiMiMo/MiMo-7B-RL（经硅基流动）

配置存 data/ai_config.json（明文本地，密钥不上传）。
"""
import json
import os
import re
import time
import traceback
import urllib.error
import urllib.request
from datetime import date

from .models import Award, Competition, ValidationError, new_award, new_competition

AI_PROVIDERS = {
    "deepseek": {"label": "DeepSeek", "base_url": "https://api.deepseek.com",
                 "model": "deepseek-chat",
                 "key_url": "https://platform.deepseek.com（申请 API Key）"},
    "glm": {"label": "智谱 GLM", "base_url": "https://open.bigmodel.cn/api/paas/v4",
            "model": "glm-5.3-flash",
            "key_url": "https://open.bigmodel.cn（申请 API Key，glm-4-flash 免费）"},
    "mimo": {"label": "小米 MiMo", "base_url": "https://api.siliconflow.cn/v1",
             "model": "XiaomiMiMo/MiMo-7B-RL",
             "key_url": "https://cloud.siliconflow.cn（经硅基流动调用 MiMo）"},
    "custom": {"label": "自定义（OpenAI 兼容）", "base_url": "", "model": "", "key_url": ""},
}

SYSTEM_PROMPT = (
    "你是「工作日历」桌面应用内置的日程助手，帮用户管理大学生设计类比赛日程和获奖记录。"
    "今天的日期是 {today}。当前库里共 {count} 个比赛。\n"
    "规则：\n"
    "1. 查询/统计用工具，不要编造数据；回答截止时间一律给『临期线』（用户真正要赶的日期）并附官方截止对照。\n"
    "2. 添加比赛至少要 name 和 deadline（YYYY-MM-DD）；用户没说清就先追问，不要编造日期。\n"
    "3. 删除和修改前先复述你理解的目标条目；删除必须先得到用户明确确认。\n"
    "4. 回答用简洁中文，操作完成后用一句话汇报结果。\n"
    "5. 用户可能发来获奖证书图片：用视觉能力提取奖项名称/级别/等级/获奖日期/比赛全称/作者与指导老师，"
    "然后调用 add_award 建档（识别不出的字段不要编造，留空并在回复里询问）；图片会自动存为该记录的凭证文件。"
    "6. 用户要求检索比赛时的固定动作序列：第一步 fetch_page 抓取 https://www.shejijingsai.com/（设计竞赛网列表页）；"
    "第二步对列表中感兴趣的比赛 fetch_page 其详情页核实；仍不足时再 search_web 并使用 site:shejijingsai.com 或 site:edu.cn 限定。"
    "如果用户直接给了官网/报名页链接，fetch_page 该链接读取后整理。"
    "7.【活动边界，必须遵守】你的全部能力仅限于通过上述工具操作本应用的工作日历数据（比赛/获奖/统计）。"
    "你没有文件系统、命令行、数据库等任何系统级访问能力；不要尝试读取、写入或列举任何本地文件/目录，"
    "也不要执行与工作日历无关的系统操作；网络访问仅限 fetch_page/search_web 两个工具。"
    "用户的证书图片会由系统自动存入应用数据目录，与你无关。"
)

TOOLS = [
    {"type": "function", "function": {
        "name": "list_competitions",
        "description": "列出/搜索比赛，返回名称、id、临期线、官方截止、倒计时、状态",
        "parameters": {"type": "object", "properties": {
            "keyword": {"type": "string", "description": "按名称/主办方/备注模糊搜索"},
            "status": {"type": "string", "enum": ["not_started", "open", "submitting", "urgent",
                                                  "past_suggested", "overdue", "submitted", "done", "abandoned"],
                       "description": "按状态过滤"},
            "limit": {"type": "integer", "description": "最多返回条数，默认 20"},
        }}},
    },
    {"type": "function", "function": {
        "name": "get_stats",
        "description": "获取统计：总数、各状态数、7 天内截止、紧急区列表",
        "parameters": {"type": "object", "properties": {}},
    }},
    {"type": "function", "function": {
        "name": "add_competition",
        "description": "新增比赛。name 与 deadline 必填（YYYY-MM-DD）",
        "parameters": {"type": "object", "properties": {
            "name": {"type": "string"}, "deadline": {"type": "string"},
            "suggested_deadline": {"type": "string", "description": "临期线，缺省自动按缓冲推算"},
            "category": {"type": "string"}, "organizer": {"type": "string"},
            "website": {"type": "string"}, "requirements": {"type": "string"},
            "notes": {"type": "string"},
            "submission": {"type": "object", "properties": {
                "method": {"type": "string", "description": "报名方式"},
                "target": {"type": "string", "description": "官方报名页"},
                "fee": {"type": "string", "description": "参赛费用，如 免费 / 50元/件"}},
                "description": "报名/提交方式、入口与费用"},
            "eligibility": {"type": "string", "description": "参赛对象/资格限制"},
            "ai_allowed": {"type": "string", "description": "是否允许 AI/代码辅助：允许/不允许/未说明"},
            "physical_required": {"type": "string", "description": "是否需要实物：需要/不需要/部分"},
            "prizes": {"type": "string", "description": "奖金/荣誉"},
            "region": {"type": "string", "description": "地区限制"},
            "priority": {"type": "string", "enum": ["高", "中", "低"], "description": "推荐优先级"},
            "verify_status": {"type": "string", "enum": ["已核实", "未核实", "存疑"], "description": "核验状态"},
            "deliverables": {"type": "array", "items": {"type": "string"}, "description": "主要交付物"},
            "milestones": {"type": "array", "items": {"type": "object", "properties": {
                "name": {"type": "string"}, "date": {"type": "string"}}}},
        }, "required": ["name", "deadline"]},
    }},
    {"type": "function", "function": {
        "name": "update_competition",
        "description": "按 id 或名称更新比赛字段（只传需要改的字段）",
        "parameters": {"type": "object", "properties": {
            "id": {"type": "string"}, "name": {"type": "string", "description": "按名称定位（模糊，需唯一）"},
            "deadline": {"type": "string"}, "suggested_deadline": {"type": "string"},
            "category": {"type": "string"}, "organizer": {"type": "string"},
            "website": {"type": "string"}, "requirements": {"type": "string"},
            "notes": {"type": "string"},
            "status_override": {"type": "string", "enum": ["submitted", "done", "abandoned", ""]},
        }},
    }},
    {"type": "function", "function": {
        "name": "delete_competition",
        "description": "按 id 或名称删除比赛（调用前必须已获用户确认）",
        "parameters": {"type": "object", "properties": {
            "id": {"type": "string"}, "name": {"type": "string"},
        }},
    }},
    {"type": "function", "function": {
        "name": "list_awards",
        "description": "列出获奖记录（名称、级别、等级、一作、日期）",
        "parameters": {"type": "object", "properties": {
            "keyword": {"type": "string"}, "level": {"type": "string"},
        }},
    }},
    {"type": "function", "function": {
        "name": "add_award",
        "description": "新增获奖记录（用户发来获奖证书图片时，识别后调用本工具建档）",
        "parameters": {"type": "object", "properties": {
            "name": {"type": "string", "description": "奖项名称，如「XX大赛 省级一等奖」"},
            "level": {"type": "string", "enum": ["校级", "市级", "省级", "国家级", "国际级"]},
            "award_rank": {"type": "string", "description": "奖项等级：一等奖/金奖/铜奖…"},
            "award_date": {"type": "string", "description": "获奖日期 YYYY-MM-DD"},
            "competition": {"type": "string", "description": "关联比赛全称"},
            "is_first_author": {"type": "boolean", "description": "是否一作/独立完成"},
            "role": {"type": "string", "description": "作者角色：一作/二作/参与…"},
            "notes": {"type": "string", "description": "其他信息：作者名单、指导老师、主办方等"},
        }, "required": ["name"]},
    }},
    {"type": "function", "function": {
        "name": "search_web",
        "description": "联网搜索（必应中文）：返回标题/链接/摘要。"
                       "检索比赛务必优先使用 site: 限定可信来源，例如 query 写"
                       "「site:shejijingsai.com 大学生设计大赛」；拿到链接后调 fetch_page 读正文核实。",
        "parameters": {"type": "object", "properties": {
            "query": {"type": "string", "description": "搜索关键词，如「2026 大学生 AIGC 设计大赛 截止」"},
            "limit": {"type": "integer", "description": "返回条数，默认 8"},
        }, "required": ["query"]},
    }},
    {"type": "function", "function": {
        "name": "fetch_page",
        "description": "抓取指定 URL 网页的正文文本（去标签，截断约 8000 字）。"
                       "用于核实比赛官网/报名页内容。检索新比赛时优先抓取来源列表页："
                       "https://www.shejijingsai.com/（设计竞赛网首页，含最新竞赛）。",
        "parameters": {"type": "object", "properties": {
            "url": {"type": "string", "description": "http/https 网页地址"},
        }, "required": ["url"]},
    }},
]

MAX_TOOL_ROUNDS = 14

# 预置建议来源（用户指定 + 常用可信源），AI 检索/抓取时优先使用
RECOMMENDED_SOURCES = (
    "【建议信息来源（优先使用）】\n"
    "1. 设计竞赛网 https://www.shejijingsai.com/ ——大陆大学生设计竞赛最全聚合站，"
    "首页即最新竞赛列表；直接 fetch_page 抓取该首页，提取各比赛的名称/截止/官网链接；"
    "search_web 时可用 site:shejijingsai.com 关键词 限定。\n"
    "2. 微信公众号「设计赛」——通过搜狗微信搜索 https://weixin.sogou.com/weixin?type=2&query=设计大赛 "
    "检索其文章；文章页（mp.weixin.qq.com）可 fetch_page 读取。\n"
    "3. 其他可信补充：各地政府/文旅官网征集页、高校官网通知页（search_web 用 site:edu.cn 限定）。\n"
    "检索策略：先 fetch_page 抓 shejijingsai.com 列表页 → 对感兴趣条目 fetch_page 其详情页核实截止日期与费用 → "
    "按来源要求字段整理入库。"
)

TOOL_LABELS = {
    "list_competitions": "查询比赛", "get_stats": "统计日程",
    "add_competition": "写入比赛", "update_competition": "更新比赛",
    "delete_competition": "删除比赛", "list_awards": "查询获奖",
    "add_award": "写入获奖", "fetch_page": "抓取网页", "search_web": "联网搜索",
}

# 隐藏前置提示词（不展示给用户）：添加/整理比赛时的固定来源要求，随对话注入 system
SOURCE_REQUIREMENTS = (
    "【比赛来源要求（固定规范，须严格遵守）】\n"
    "当前日期 {today}，尽可能全面地检索并核查仍可报名、且截止日期至少还有 7 天的比赛，"
    "面向中国大陆大学生，优先免费或低费用。范围按最新标准扩展：传统平面/包装/品牌/视觉传达/文创/IP，"
    "也包括 UI/UX、交互设计、信息可视化、创意编程、生成艺术、网页与轻量 App 原型、数字媒体、AIGC、"
    "AI 应用创意、AI Agent、HCI、互动装置数字原型、游戏/严肃游戏、服务设计、数据驱动设计、"
    "智能产品概念与可演示原型、数字文旅与公共文化科技、企业 Hackathon/高校计算机+设计交叉赛事。"
    "优先筛选不要求重资产硬件制作、不依赖大型团队、可通过代码/原型/视频演示完成主要交付的赛事，"
    "同时保留高质量包装/平面赛事。\n"
    "核实并整理以下字段：比赛名称、主办方、官方网站/官方报名页、截止日期、距离截止天数、参赛费用、"
    "参赛对象/资格限制、适合方向、主要交付物、是否允许 AI/代码辅助、是否需要实物、奖金/荣誉、"
    "报名方式、地区限制、推荐优先级、核验状态、备注。\n"
    "字段落库映射：参赛费用→submission.fee；报名方式→submission.method；官方报名页→submission.target；"
    "参赛对象/资格限制→eligibility；是否允许 AI/代码辅助→ai_allowed；是否需要实物→physical_required；"
    "奖金/荣誉→prizes；地区限制→region；推荐优先级→priority(高/中/低)；核验状态→verify_status"
    "(已核实/未核实/存疑)；适合方向→category 与 tags。\n"
    "对收费不明/资格不清/官网无法核实的项目必须把 verify_status 标为『存疑』并在 notes 说明原因。"
    "去重（同名同截止视为重复，不要重复录入）并尽可能多整理。"
    "收集到足够信息后应立即汇总输出，不要反复搜索；每次搜索/抓取后先总结已获得的内容。"
)


from .safe_fetch import fetch_raw as _fetch_url_raw


class AiConfig:
    """data/ai_config.json 读写（密钥不出本机）。"""

    def __init__(self, data_dir: str):
        self.path = os.path.join(data_dir, "ai_config.json")

    def load(self) -> dict:
        cfg = {"provider": "deepseek", "api_key": "", "model": "", "base_url": "", "web_search": True}
        if os.path.isfile(self.path):
            try:
                with open(self.path, encoding="utf-8") as f:
                    cfg.update(json.load(f))
            except (OSError, json.JSONDecodeError):
                pass
        return cfg

    def save(self, data: dict) -> dict:
        cfg = self.load()
        for k in ("provider", "api_key", "model", "base_url"):
            if k in data and data[k] is not None:
                cfg[k] = str(data[k]).strip()
        cfg["web_search"] = bool(data.get("web_search", cfg.get("web_search", True)))
        with open(self.path + ".tmp", "w", encoding="utf-8") as f:
            json.dump(cfg, f, ensure_ascii=False, indent=2)
        os.replace(self.path + ".tmp", self.path)
        return cfg


def public_config(cfg: dict) -> dict:
    """对外视图：不回传完整密钥。"""
    provider = AI_PROVIDERS.get(cfg.get("provider"), AI_PROVIDERS["deepseek"])
    key = cfg.get("api_key", "")
    return {
        "ok": True,
        "provider": cfg.get("provider", "deepseek"),
        "provider_label": provider["label"],
        "model": cfg.get("model") or provider["model"],
        "base_url": cfg.get("base_url") or provider["base_url"],
        "has_key": bool(key),
        "web_search": bool(cfg.get("web_search", True)),
        "key_mask": (key[:4] + "…" + key[-4:]) if len(key) > 8 else ("已设置" if key else ""),
        "key_url": provider["key_url"],
        "providers": {k: {"label": v["label"], "base_url": v["base_url"],
                          "model": v["model"], "key_url": v["key_url"]}
                      for k, v in AI_PROVIDERS.items()},
    }


def _resolve(cfg: dict) -> tuple:
    provider = AI_PROVIDERS.get(cfg.get("provider"), AI_PROVIDERS["deepseek"])
    base = (cfg.get("base_url") or provider["base_url"]).rstrip("/")
    model = cfg.get("model") or provider["model"]
    return base, model


def _call_provider(cfg: dict, messages: list, tools: list | None, timeout: int = 60) -> dict:
    base, model = _resolve(cfg)
    if cfg.get("provider") == "glm" and cfg.get("web_search", True):
        timeout = max(timeout, 180)  # 智谱服务端联网搜索较慢，放宽超时
    url = base + "/chat/completions"

    def _post(msgs, tool_body):
        body = {"model": model, "messages": msgs}
        if tool_body:
            body["tools"] = tool_body
            body["tool_choice"] = "auto"
        req = urllib.request.Request(
            url, json.dumps(body).encode("utf-8"),
            {"Content-Type": "application/json",
             "Authorization": "Bearer " + cfg.get("api_key", "")})
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                return json.loads(resp.read().decode("utf-8"))
        except urllib.error.HTTPError as e:
            detail = ""
            try:
                detail = json.loads(e.read().decode("utf-8")).get("error", {}).get("message", "")
            except Exception:
                pass
            hint = {401: "API Key 无效或未授权，请检查设置里的 Key",
                    403: "API Key 无权限（可能未开通该模型）",
                    404: "接口地址不对：检查 base_url（通常以 /v1 或 /api/paas/v4 结尾）",
                    429: "调用频率超限或额度不足，请稍后再试"}.get(e.code)
            raise RuntimeError(f"接口返回 {e.code}：{detail or e.reason}"
                               + (f"（{hint}）" if hint and detail else "")) from None
        except (urllib.error.URLError, TimeoutError, OSError) as e:
            reason = str(getattr(e, 'reason', '') or e)
            if ("getaddrinfo" in reason or "refused" in reason.lower()
                    or "10061" in reason or "10049" in reason):
                raise RuntimeError("连不上接口地址，请检查 base_url 是否正确、对方服务是否在线") from None
            if "timed out" in reason.lower() or "10060" in reason:
                raise RuntimeError("连接超时，请检查网络后重试") from None
            raise RuntimeError(f"网络错误：{reason}") from None

    # 智谱 GLM：服务端联网搜索工具（搜索在智谱侧执行，无需本机代理）
    use_ws = cfg.get("provider") == "glm" and cfg.get("web_search", True)
    try:
        if use_ws:
            ws_tool = [{"type": "web_search", "web_search": {
                "enable": True, "search_engine": "search_std", "search_result_count": 5}}]
            return _post(messages, (tools or []) + ws_tool)
        return _post(messages, tools)
    except RuntimeError as e:
        # 该模型/接口不支持 web_search 工具时：去掉联网搜索重试一次（函数工具保留）
        if use_ws and ("web_search" in str(e) or "1302" in str(e) or "工具" in str(e)):
            return _post(messages, tools)
        raise


class ToolBox:
    """把 LLM 的工具调用落到 Store。定位支持 id 或名称（名称模糊匹配，需唯一）。"""

    def __init__(self, store):
        self.store = store

    def _find(self, args: dict):
        cid = str(args.get("id") or "")
        if cid:
            return self.store.get(cid), None
        name = str(args.get("name") or "").strip()
        if not name:
            return None, "需要提供 id 或 name"
        low = name.lower()
        hits = [c for c in self.store.all() if low in c.name.lower()]
        if not hits:
            return None, f"没有找到名称含「{name}」的比赛"
        if len(hits) > 1:
            names = "；".join(c.name for c in hits[:5])
            return None, f"「{name}」匹配到 {len(hits)} 条（{names}…），请说明更完整的名称或提供 id"
        return hits[0], None

    def execute(self, name: str, args: dict) -> dict:
        try:
            fn = getattr(self, "tool_" + name, None)
            if fn is None:
                return {"error": f"未知工具 {name}"}
            return fn(args or {})
        except ValidationError as e:
            return {"error": str(e)}

    def tool_list_competitions(self, args: dict) -> dict:
        today = date.today()
        kw = str(args.get("keyword") or "").lower()
        status = args.get("status")
        limit = max(1, min(int(args.get("limit") or 20), 100))
        rows = []
        for c in self.store.all():
            s = c.status(today)
            if kw and kw not in (c.name + c.organizer + c.notes).lower():
                continue
            if status and s != status:
                continue
            d = c.to_dict()
            rows.append({"id": c.id, "name": c.name, "status": s,
                         "suggested_deadline": c.effective_suggested().isoformat(),
                         "deadline": c.deadline.isoformat(),
                         "days_left": (c.effective_suggested() - today).days,
                         "category": c.category})
        rows.sort(key=lambda r: r["suggested_deadline"])
        return {"total_matched": len(rows), "shown": min(len(rows), limit),
                "competitions": rows[:limit]}

    def tool_get_stats(self, args: dict) -> dict:
        today = date.today()
        comps = self.store.all()
        by_status = {}
        for c in comps:
            s = c.status(today)
            by_status[s] = by_status.get(s, 0) + 1
        urgent = [{"name": c.name, "suggested_deadline": c.effective_suggested().isoformat(),
                   "days_left": (c.effective_suggested() - today).days}
                  for c in comps
                  if c.status(today) not in ("submitted", "done", "abandoned", "overdue")
                  and 0 <= (c.effective_suggested() - today).days <= 7]
        urgent.sort(key=lambda u: u["days_left"])
        return {"total": len(comps), "by_status": by_status, "due_in_7": urgent}

    def tool_add_competition(self, args: dict) -> dict:
        args = {k: v for k, v in args.items() if v not in (None, "")}
        # 来源要求字段落库映射
        sub = dict(args.get("submission") or {})
        for src, dst in (("fee", "fee"), ("signup_method", "method"), ("official_signup_url", "target")):
            if args.get(src):
                sub[dst] = str(args[src])
        if sub:
            args["submission"] = sub
        for k in ("fee", "signup_method", "official_signup_url"):
            args.pop(k, None)
        if isinstance(args.get("deliverables"), str):
            args["deliverables"] = [x.strip() for x in re.split(r"[、;；\n]", args["deliverables"]) if x.strip()]
        if args.get("suited_for") and not args.get("category"):
            args["category"] = str(args["suited_for"])
        comp = new_competition(str(args.get("name", "")), args.get("deadline"),
                               **{k: v for k, v in args.items() if k not in ("name", "deadline")})
        self.store.upsert(comp)
        return {"ok": True, "id": comp.id, "name": comp.name,
                "suggested_deadline": comp.effective_suggested().isoformat()}

    def tool_update_competition(self, args: dict) -> dict:
        by_id = bool(str(args.get("id") or ""))
        comp, err = self._find(args)
        if err:
            return {"error": err}
        merged = comp.to_dict()
        for k, v in args.items():
            if k == "id" or v is None:
                continue
            if k == "name" and not by_id:
                continue  # 按名称定位时 name 是定位符，不改名
            merged[k] = v
        merged["id"] = comp.id
        merged["created_at"] = comp.created_at
        updated = Competition.from_dict(merged)
        self.store.upsert(updated)
        return {"ok": True, "id": comp.id, "name": updated.name,
                "deadline": updated.deadline,
                "suggested_deadline": updated.effective_suggested().isoformat(),
                "status_override": updated.status_override}

    def tool_delete_competition(self, args: dict) -> dict:
        comp, err = self._find(args)
        if err:
            return {"error": err}
        self.store.delete(comp.id)
        return {"ok": True, "deleted": comp.id, "name": comp.name}

    def tool_list_awards(self, args: dict) -> dict:
        kw = str(args.get("keyword") or "").lower()
        level = args.get("level")
        rows = []
        for a in self.store.all_awards():
            if kw and kw not in (a.name + a.competition + a.notes).lower():
                continue
            if level and a.level != level:
                continue
            rows.append({"name": a.name, "level": a.level, "award_rank": a.award_rank,
                         "is_first_author": a.is_first_author,
                         "award_date": a.award_date.isoformat() if hasattr(a.award_date, "isoformat") else (a.award_date or "")})
        return {"total": len(rows), "awards": rows[:50]}

    def tool_add_award(self, args: dict) -> dict:
        kwargs = {k: v for k, v in args.items() if k != "name" and v not in (None, "")}
        if kwargs.get("is_first_author") is not None:
            kwargs["is_first_author"] = bool(kwargs["is_first_author"])
        award = new_award(str(args.get("name", "")), **kwargs)
        self.store.upsert_award(award)
        ad = award.award_date.isoformat() if hasattr(award.award_date, "isoformat") else (award.award_date or "")
        return {"ok": True, "id": award.id, "name": award.name, "level": award.level,
                "award_rank": award.award_rank, "award_date": ad}

    def tool_search_web(self, args: dict) -> dict:
        """必应中文搜索（DeepSeek/MiMo 无联网的搜索通道）。解析失败时提示改用 fetch_page。"""
        import re as _re
        import html as _html
        from urllib.parse import quote, urlparse
        query = str(args.get("query") or "").strip()
        limit = max(3, min(int(args.get("limit") or 8), 15))
        if not query:
            return {"error": "缺少搜索关键词"}
        url = "https://cn.bing.com/search?q=" + quote(query) + "&count=" + str(limit + 5)
        req = urllib.request.Request(url, headers={
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
                          "(KHTML, like Gecko) Chrome/124.0 Safari/537.36",
            "Accept-Language": "zh-CN,zh;q=0.9"})
        try:
            with urllib.request.urlopen(req, timeout=15) as resp:
                html = resp.read(1024 * 1024).decode("utf-8", errors="replace")
        except (urllib.error.URLError, TimeoutError, OSError) as e:
            return {"error": f"搜索失败：{e}。替代方案：请用户提供官网链接后用 fetch_page 读取。"}
        results = []
        # 解析必应结果块 <li class="b_algo">：<h2><a href=...>标题</a></h2>…<p>摘要</p>
        for block in _re.findall(r'<li class="b_algo".*?</li>', html, _re.S)[:limit]:
            m_url = _re.search(r'<h2[^>]*><a[^>]+href="([^"]+)"', block)
            m_title = _re.search(r'<h2[^>]*><a[^>]*>(.*?)</a>', block, _re.S)
            if not (m_url and m_title):
                continue
            snip = _re.search(r'<p[^>]*>(.*?)</p>', block, _re.S)
            clean = lambda t: _html.unescape(_re.sub(r"<[^>]+>", "", t)).strip()
            item = {"title": clean(m_title.group(1)), "url": m_url.group(1)}
            if snip:
                item["snippet"] = clean(snip.group(1))[:200]
            results.append(item)
        if not results:
            return {"error": "搜索结果解析为空（搜索引擎页面可能变化）。"
                             "替代方案：请用户提供官网链接后用 fetch_page 读取。"}
        return {"query": query, "total": len(results), "results": results,
                "hint": "可用 fetch_page 读取任一链接正文核实详情"}

    def tool_fetch_page(self, args: dict) -> dict:
        """抓取网页正文（DeepSeek/MiMo 等无联网接口的替代：用户提供 URL，本机代理抓取）。"""
        import re as _re
        from urllib.parse import urlparse, quote
        url = str(args.get("url") or "").strip()
        if not _re.match(r"^https?://", url, _re.I):
            return {"error": "仅支持 http/https 地址"}
        # URL 含非 ASCII（中文关键词/路径）时进行百分号编码，保留结构字符
        parts = urlparse(url)
        path_q = quote(parts.path, safe="/%@")
        query_q = quote(parts.query, safe="=&?/%")
        url = parts.scheme + "://" + parts.netloc + path_q + (("?" + query_q) if parts.query else "")
        host = (urlparse(url).hostname or "").lower()
        if (not host or host in ("localhost",) or host.endswith(".local")
                or _re.match(r"^(127\.|10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.|0\.|\[)", host)
                or host == "0.0.0.0"):
            return {"error": "禁止访问内网/本机地址"}
        req = urllib.request.Request(url, headers={
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) WorkCalendar/0.2",
            "Accept-Language": "zh-CN,zh;q=0.9"})
        try:
            raw = _fetch_url_raw(url, timeout=15)
            html = raw
        except RuntimeError as e:
            return {"error": str(e)}
        except (urllib.error.URLError, TimeoutError, OSError) as e:
            return {"error": f"抓取失败：{e}"}
        html = _re.sub(r"(?is)<(script|style|noscript|svg)[^>]*>.*?</\1>", " ", html)
        text = _re.sub(r"(?s)<[^>]+>", " ", html)
        import html as _html
        text = _html.unescape(text)
        text = _re.sub(r"[ \t\r\f\v]+", " ", text)
        text = _re.sub(r"\n\s*\n+", "\n", text).strip()
        if not text:
            return {"error": "页面无文本内容（可能是纯图片页）"}
        return {"url": url, "length": len(text),
                "text": text[:8000] + ("…(已截断)" if len(text) > 8000 else "")}


def chat(cfg: dict, store, messages: list, on_status=None) -> dict:
    """跑一轮完整对话（含工具循环），返回 {reply, trace}。成功/失败均写日志。
    on_status(text) 用于向前端轮播实时状态。"""
    if not cfg.get("api_key"):
        raise RuntimeError("尚未配置 API Key，请先在设置里填写并保存")
    base, model = _resolve(cfg)
    if not base or not model:
        raise RuntimeError("请补全接口地址 base_url 和模型名 model")
    today = date.today().isoformat()
    sys = (SYSTEM_PROMPT.format(today=today, count=len(store.all()))
           + "\n\n" + SOURCE_REQUIREMENTS.format(today=today)
           + "\n\n" + RECOMMENDED_SOURCES)
    msgs = [{"role": "system", "content": sys}] + messages[-20:]
    box = ToolBox(store)
    trace = []
    t0 = time.time()
    try:
        result = _chat_loop(cfg, msgs, box, trace, on_status=on_status)
    except Exception as e:
        store.error(f"AI 调用失败({model}): {e}", traceback.format_exc())
        raise
    store.info(f"AI 调用成功 {model} 工具{len(trace)}次 耗时{time.time() - t0:.1f}s")
    return result


def _chat_loop(cfg, msgs, box: ToolBox, trace: list, on_status=None) -> dict:
    def _status(text):
        if on_status:
            try: on_status(text)
            except Exception: pass
    _status("思考中…")
    for _round in range(MAX_TOOL_ROUNDS):
        _status(f"第 {_round + 1} 轮 · 分析中…")
        if _round == MAX_TOOL_ROUNDS - 2:
            msgs.append({"role": "system", "content":
                "这是最后一轮：请立即基于已获取的信息汇总作答，不要再调用任何工具。"})
        resp = _call_provider(cfg, msgs, TOOLS)
        try:
            msg = resp["choices"][0]["message"]
        except (KeyError, IndexError, TypeError):
            raise RuntimeError(f"接口响应格式异常：{str(resp)[:200]}")
        calls = msg.get("tool_calls") or []
        if not calls:
            return {"reply": msg.get("content") or "（空回复）", "trace": trace}
        msgs.append({"role": "assistant", "content": msg.get("content") or "",
                     "tool_calls": calls})
        for tc in calls:
            fn = (tc.get("function") or {})
            name = fn.get("name", "")
            try:
                args = json.loads(fn.get("arguments") or "{}")
            except json.JSONDecodeError:
                args = {}
            _status(f"{TOOL_LABELS.get(name, name)}…")
            result = box.execute(name, args)
            trace.append({"tool": name, "args": args,
                          "result_id": result.get("id") if isinstance(result, dict) else None})
            msgs.append({"role": "tool", "tool_call_id": tc.get("id", ""),
                         "content": json.dumps(result, ensure_ascii=False, default=str)})
    return {"reply": "（连续多轮工具调用未收敛，请换个问法或分步操作）", "trace": trace}
