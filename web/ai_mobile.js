/* ================= AI 引擎（安卓本地版：CapacitorHttp 绕 CORS，工具直走本地数据层） =================
   仅 mobile.html 加载。桌面版走 Python 后端（app/ai.py），两者工具语义保持一致。 */
const AI_PROVIDERS_JS = {
  deepseek: { label: 'DeepSeek', base_url: 'https://api.deepseek.com', model: 'deepseek-chat' },
  glm: { label: '智谱 GLM', base_url: 'https://open.bigmodel.cn/api/paas/v4', model: 'glm-5.3-flash' },
  mimo: { label: '小米 MiMo', base_url: 'https://api.siliconflow.cn/v1', model: 'XiaomiMiMo/MiMo-7B-RL' },
  custom: { label: '自定义', base_url: '', model: '' },
};
function aiCfgJsGet() {
  try { return JSON.parse(localStorage.getItem('wc_ai_cfg') || 'null') || { provider: 'deepseek', api_key: '', model: '', base_url: '', web_search: true }; }
  catch (e) { return { provider: 'deepseek', api_key: '', model: '', base_url: '', web_search: true }; }
}
function aiCfgJsSave(cfg) { localStorage.setItem('wc_ai_cfg', JSON.stringify(cfg)); }
function aiToolDefsJs() {
  const str = (desc) => ({ type: 'string', description: desc });
  return [
    { type: 'function', function: { name: 'list_competitions', description: '列出/搜索比赛（含 id、临期线、倒计时、状态）', parameters: { type: 'object', properties: {
      keyword: str('按名称/主办方/备注模糊搜索'), status: str('状态过滤'), limit: { type: 'integer', description: '最多条数' } } } } },
    { type: 'function', function: { name: 'get_stats', description: '统计：总数、各状态、7 天内截止列表', parameters: { type: 'object', properties: {} } } },
    { type: 'function', function: { name: 'add_competition', description: '新增比赛，name/deadline 必填（YYYY-MM-DD）', parameters: { type: 'object', properties: {
      name: str('比赛名称'), deadline: str('官方截止'), suggested_deadline: str('临期线'), category: str('适合方向/类别'),
      organizer: str('主办方'), website: str('官网'), requirements: str('作品要求'), notes: str('备注'),
      fee: str('参赛费用'), signup_method: str('报名方式'), signup_url: str('官方报名页'),
      eligibility: str('参赛对象/资格限制'), ai_allowed: str('是否允许 AI/代码辅助'), physical_required: str('是否需要实物'),
      prizes: str('奖金/荣誉'), region: str('地区限制'), priority: str('推荐优先级:高/中/低'), verify_status: str('核验状态:已核实/未核实/存疑'),
      deliverables: { type: 'array', items: { type: 'string' }, description: '主要交付物' } },
      required: ['name', 'deadline'] } } },
    { type: 'function', function: { name: 'update_competition', description: '按 id 或名称更新比赛（只传要改的字段）', parameters: { type: 'object', properties: {
      id: str('比赛 id'), name: str('按名称定位'), deadline: str('官方截止'), suggested_deadline: str('临期线'),
      category: str('类别'), notes: str('备注'), status_override: str('submitted/done/abandoned 或空') } } } },
    { type: 'function', function: { name: 'delete_competition', description: '删除比赛（须先获用户确认）', parameters: { type: 'object', properties: {
      id: str('id'), name: str('名称') } } } },
    { type: 'function', function: { name: 'list_awards', description: '列出获奖记录', parameters: { type: 'object', properties: {
      keyword: str('关键词'), level: str('级别') } } } },
    { type: 'function', function: { name: 'add_award', description: '新增获奖记录（用户发来获奖证书图片时，识别后调用）', parameters: { type: 'object', properties: {
      name: str('奖项名称，如 XX大赛 省级一等奖'), level: str('校级/市级/省级/国家级/国际级'), award_rank: str('等级：一等奖/金奖…'),
      award_date: str('获奖日期 YYYY-MM-DD'), competition: str('关联比赛全称'), is_first_author: { type: 'boolean', description: '是否一作' },
      role: str('作者角色'), notes: str('作者名单/指导老师等') } },
      required: ['name'] } },
    { type: 'function', function: { name: 'fetch_page', description: '抓取 URL 网页正文文本，用于核实比赛官网/报名页', parameters: { type: 'object', properties: {
      url: str('http/https 地址') }, required: ['url'] } } },
  ];
}
async function aiExecToolJs(name, args) {
  args = args || {};
  const findComp = async (a) => {
    if (a.id) { const list = (await api('/api/competitions')).competitions; return list.find(c => c.id === a.id) || null; }
    const kw = String(a.name || '').trim().toLowerCase();
    if (!kw) throw new Error('需要提供 id 或 name');
    const hits = (await api('/api/competitions?keyword=' + encodeURIComponent(kw))).competitions
      .filter(c => c.name.toLowerCase().includes(kw));
    if (!hits.length) throw new Error('没有找到名称含「' + a.name + '」的比赛');
    if (hits.length > 1) throw new Error('「' + a.name + '」匹配到 ' + hits.length + ' 条，请提供更完整名称或 id');
    return hits[0];
  };
  if (name === 'list_competitions') {
    const q = new URLSearchParams(); q.set('sort', 'deadline');
    if (args.keyword) q.set('keyword', args.keyword);
    if (args.status) q.set('status', args.status);
    const d = await api('/api/competitions?' + q);
    const limit = Math.min(args.limit || 20, 100);
    return { total_matched: d.count, competitions: d.competitions.slice(0, limit).map(c => ({
      id: c.id, name: c.name, status: c.status, suggested_deadline: c.suggested_deadline,
      deadline: c.deadline, days_left: c.countdown, category: c.category })) };
  }
  if (name === 'get_stats') {
    const s = await api('/api/stats');
    return { total: s.total, by_status: s.by_status, due_in_7: (s.upcoming || []).filter(u => u.countdown <= 7)
      .map(u => ({ name: u.name, suggested_deadline: u.suggested_deadline, days_left: u.countdown })) };
  }
  if (name === 'add_competition') {
    const body = { ...args };
    const sub = {};
    for (const pair of [['fee', 'fee'], ['signup_method', 'method'], ['signup_url', 'target']])
      if (body[pair[0]]) { sub[pair[1]] = String(body[pair[0]]); delete body[pair[0]]; }
    if (Object.keys(sub).length) body.submission = sub;
    if (typeof body.deliverables === 'string') body.deliverables = body.deliverables.split(/[、;；\n]/).map(x => x.trim()).filter(Boolean);
    if (body.suited_for && !body.category) { body.category = body.suited_for; delete body.suited_for; }
    const r = await api('/api/competitions', { method: 'POST', body });
    return { ok: true, id: r.competition.id, name: r.competition.name,
             suggested_deadline: r.competition.suggested_deadline };
  }
  if (name === 'update_competition') {
    const c = await findComp(args);
    const body = { ...args };
    delete body.id;
    if (!args.id) delete body.name;  /* 按名称定位时不改名 */
    const r = await api('/api/competitions/' + c.id, { method: 'PUT', body });
    return { ok: true, id: c.id, name: r.competition.name, deadline: r.competition.deadline,
             suggested_deadline: r.competition.suggested_deadline };
  }
  if (name === 'delete_competition') {
    const c = await findComp(args);
    await api('/api/competitions/' + c.id, { method: 'DELETE' });
    return { ok: true, deleted: c.id, name: c.name };
  }
  if (name === 'list_awards') {
    const q = new URLSearchParams();
    if (args.keyword) q.set('keyword', args.keyword);
    if (args.level) q.set('level', args.level);
    const d = await api('/api/awards?' + q);
    return { total: d.count, awards: (d.awards || []).slice(0, 50).map(a => ({
      name: a.name, level: a.level, award_rank: a.award_rank, is_first_author: a.is_first_author, award_date: a.award_date })) };
  }
  if (name === 'add_award') {
    const body = { ...args };
    if (body.is_first_author !== undefined) body.is_first_author = !!body.is_first_author;
    const r = await api('/api/awards', { method: 'POST', body });
    return { ok: true, id: r.award.id, name: r.award.name, level: r.award.level,
             award_rank: r.award.award_rank, award_date: r.award.award_date || '' };
  }
  if (name === 'search_web') {
    const query = String(args.query || '').trim();
    if (!query) return { error: '缺少搜索关键词' };
    if (!window.Capacitor?.Plugins?.CapacitorHttp) return { error: '当前环境不支持搜索' };
    let html = '';
    try {
      const r = await window.Capacitor.Plugins.CapacitorHttp.get({
        url: 'https://cn.bing.com/search?q=' + encodeURIComponent(query) + '&count=10',
        headers: { 'Accept-Language': 'zh-CN,zh;q=0.9' }, connectTimeout: 10000, readTimeout: 15000 });
      html = typeof r.data === 'string' ? r.data : '';
    } catch (e) { return { error: '搜索失败：' + (e.message || e) + '。替代方案：请用户提供官网链接后用 fetch_page 读取。' }; }
    const results = [];
    const reBlock = /<li class="b_algo"[\s\S]*?<\/li>/g;
    let mBlock;
    while ((mBlock = reBlock.exec(html)) && results.length < Math.min(args.limit || 8, 15)) {
      const block = mBlock[0];
      const mu = block.match(/<h2[^>]*><a[^>]+href="([^"]+)"/);
      const mt = block.match(/<h2[^>]*><a[^>]*>([\s\S]*?)<\/a>/);
      if (!mu || !mt) continue;
      const ms = block.match(/<p[^>]*>([\s\S]*?)<\/p>/);
      const clean = (t) => { const ta = document.createElement('textarea'); ta.innerHTML = t.replace(/<[^>]+>/g, ''); return ta.value.trim(); };
      const item = { title: clean(mt[1]), url: mu[1] };
      if (ms) item.snippet = clean(ms[1]).slice(0, 200);
      results.push(item);
    }
    if (!results.length) return { error: '搜索结果解析为空。替代方案：请用户提供官网链接后用 fetch_page 读取。' };
    return { query, total: results.length, results, hint: '可用 fetch_page 读取任一链接正文核实详情' };
  }
  if (name === 'fetch_page') {
    const url = encodeURI(String(args.url || '').trim());
    if (!/^https?:\/\//i.test(url)) return { error: '仅支持 http/https 地址' };
    let host = '';
    try { host = new URL(url).hostname.toLowerCase(); } catch (e) { return { error: 'URL 非法' }; }
    if (!host || host === 'localhost' || host.endsWith('.local') ||
        /^(127\.|10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.)/.test(host)) return { error: '禁止访问内网/本机地址' };
    if (!window.Capacitor?.Plugins?.CapacitorHttp) return { error: '当前环境不支持抓取' };
    if (!window.Capacitor?.Plugins?.SafeWeb) return { error: '安全网页模块不可用，请更新应用' };
    const r = await window.Capacitor.Plugins.SafeWeb.fetchPage({ url });
    let html = typeof r.data === 'string' ? r.data : '';
    html = html.replace(/<(script|style|noscript|svg)[^>]*>[\s\S]*?<\/\1>/gi, ' ').replace(/<[^>]+>/g, ' ');
    const ta = document.createElement('textarea'); ta.innerHTML = html;
    const text = ta.value.replace(/[ \t\r\f\v]+/g, ' ').replace(/\n\s*\n+/g, '\n').trim();
    if (!text) return { error: '页面无文本内容' };
    return { url, length: text.length, text: text.slice(0, 8000) + (text.length > 8000 ? '…(已截断)' : '') };
  }
  return { error: '未知工具 ' + name };
}
async function aiProviderCallJs(cfg, msgs, tools) {
  const p = AI_PROVIDERS_JS[cfg.provider] || AI_PROVIDERS_JS.deepseek;
  const base = (cfg.base_url || p.base_url || '').replace(/\/$/, '');
  const model = cfg.model || p.model;
  const body = { model, messages: msgs, tools, tool_choice: 'auto' };
  if (cfg.provider === 'glm' && cfg.web_search !== false) {
    body.tools = tools.concat([{ type: 'web_search', web_search: { enable: true, search_result_count: 5 } }]);
  }
  let r;
  try {
    r = await window.Capacitor.Plugins.CapacitorHttp.request({
      url: base + '/chat/completions', method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + (cfg.api_key || '') },
      data: body, connectTimeout: 10000, readTimeout: 60000,
    });
  } catch (e) {
    /* 原生网络错误转人话：连不上（地址错/服务关/防火墙）、超时等 */
    const m = String(e?.message || e);
    if (/failed to connect|ECONNREFUSED|connect/i.test(m)) throw new Error('连不上接口地址，请检查 base_url 是否正确、对方服务是否在线');
    if (/timeout|timed out/i.test(m)) throw new Error('连接超时，请检查网络后重试');
    throw new Error(m);
  }
  if (r.status >= 400) {
    let detail = '';
    try { detail = (JSON.parse(r.data).error || {}).message || ''; } catch (e) {}
    throw new Error('接口返回 ' + r.status + '：' + (detail || r.status));
  }
  return typeof r.data === 'string' ? JSON.parse(r.data) : r.data;
}
async function aiChatJs(messages, onStatus) {
  const cfg = aiCfgJsGet();
  if (!cfg.api_key) throw new Error('尚未配置 API Key，请先在本页设置里填写并保存');
  const p = AI_PROVIDERS_JS[cfg.provider] || AI_PROVIDERS_JS.deepseek;
  const today = localToday();
  const sys = '你是「工作日历」手机应用内置的日程助手，帮用户管理大学生设计类比赛日程和获奖记录。今天的日期是 ' + today
    + '。当前库里共 ' + (S.comps || []).length + ' 个比赛。\n'
    + '规则：1.查询/统计用工具，不要编造数据；截止时间一律给「临期线」并附官方截止对照。'
    + '2.添加比赛至少要 name 和 deadline（YYYY-MM-DD）；用户没说清就先追问，不要编造日期。'
    + '3.删除和修改前先复述目标条目；删除必须先得到用户明确确认。4.回答用简洁中文，操作后一句话汇报结果。\n'
    + '【比赛来源要求（固定规范）】当前日期 ' + today + '，整理比赛时面向中国大陆大学生、仍可报名且截止至少还有 7 天、优先免费或低费用；'
    + '范围含平面/包装/品牌/视觉/文创/IP 及 UI/UX、交互、信息可视化、创意编程、生成艺术、AIGC、AI Agent、HCI、游戏、服务设计、数据驱动设计等；'
    + '优先可由代码/原型/视频完成交付的赛事，保留高质量包装/平面赛事。字段尽量齐：名称、主办方、官网/报名页、截止、费用、资格、适合方向、交付物、'
    + '是否允许 AI、是否需实物、奖金、报名方式、地区、优先级(高/中/低)、核验状态(已核实/未核实/存疑)、备注。'
    + '收费不明/资格不清/无法核实的必须标 verify_status=存疑 并在 notes 说明。同名同截止去重。'
    + '字段落库：费用→fee，报名方式→signup_method，报名页→signup_url，其余→同名参数。';
  let msgs = [{ role: 'system', content: sys }, ...messages.slice(-20)];
  const tools = aiToolDefsJs();
  const trace = [];
  const LABELS = { list_competitions: '查询比赛', get_stats: '统计日程', add_competition: '写入比赛',
    update_competition: '更新比赛', delete_competition: '删除比赛', list_awards: '查询获奖',
    add_award: '写入获奖', fetch_page: '抓取网页', search_web: '联网搜索' };
  const say = (t) => { if (onStatus) try { onStatus(t); } catch (e) {} };
  say('思考中…');
  for (let i = 0; i < 6; i++) {
    say('第 ' + (i + 1) + ' 轮 · 分析中…');
    const resp = await aiProviderCallJs(cfg, msgs, tools);
    const msg = resp?.choices?.[0]?.message;
    if (!msg) throw new Error('接口响应格式异常');
    const calls = msg.tool_calls || [];
    if (!calls.length) return { reply: msg.content || '（空回复）', trace };
    msgs.push({ role: 'assistant', content: msg.content || '', tool_calls: calls });
    for (const tc of calls) {
      const fn = tc.function || {};
      let args = {};
      try { args = JSON.parse(fn.arguments || '{}'); } catch (e) {}
      say(LABELS[fn.name] || (fn.name + '…'));
      let result;
      try { result = await aiExecToolJs(fn.name, args); }
      catch (e) { result = { error: e.message }; }
      trace.push({ tool: fn.name, args });
      msgs.push({ role: 'tool', tool_call_id: tc.id || '', content: JSON.stringify(result) });
    }
  }
  return { reply: '（连续多轮工具调用未收敛，请换个问法）', trace };
}
