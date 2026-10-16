
/* ================= 本地数据后端（安卓版：无 Python 后端，JS 复刻全部逻辑） ================= */
/* 桌面版（浏览器/WebView 访问 http://127.0.0.1）走 fetch；安卓 Capacitor 原生环境走本地后端。 */
const IS_LOCAL = !!(window.Capacitor && window.Capacitor.isNativePlatform && window.Capacitor.isNativePlatform());
const VERSION_LOCAL = '0.4.2';
const DEFAULT_BUFFER_DAYS = 3;
const URGENT_DAYS = 7;
const VALID_OVERRIDES = ['submitted', 'done', 'abandoned'];
const VALID_AWARD_LEVELS = ['校级', '市级', '省级', '国家级', '国际级'];
const STATUS_LABELS = {
  not_started: '未开始', open: '报名中', submitting: '进行中',
  urgent: '即将截止', past_suggested: '已过临期线', overdue: '已截止',
  submitted: '已提交', done: '已完成', abandoned: '已放弃',
};
const LOC_DIR = 'wc_data';
/* Capacitor Filesystem v6 目录必须是字符串：DATA=应用私有 getFilesDir（免权限，卸载才清除） */
const DIR_DATA = 'DATA';

function parseDate(v) {
  if (v === null || v === undefined || v === '') return null;
  if (v instanceof Date) return v.toISOString().slice(0, 10);
  const m = String(v).trim().match(/^(\d{4})-(\d{1,2})-(\d{1,2})$/);
  if (!m) return null;
  const d = new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]));
  return (d.getFullYear() === Number(m[1]) && d.getMonth() === Number(m[2]) - 1) ? `${m[1]}-${String(Number(m[2])).padStart(2, '0')}-${String(Number(m[3])).padStart(2, '0')}` : null;
}
const _FW_SRC = 'ＡＢＣＤＥＦＧＨＩＪＫＬＭＮＯＰＱＲＳＴＵＶＷＸＹＺａｂｃｄｅｆｇｈｉｊｋｌｍｎｏｐｑｒｓｔｕｖｗｘｙｚ０１２３４５６７８９　（）：，。！？；‘’“”';
const _FW_DST = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 ():,.!?;\'\'""';
function normalizeName(name) {
  let s = String(name ?? '').trim().split('').map(ch => {
    const i = _FW_SRC.indexOf(ch); return i >= 0 ? _FW_DST[i] : ch;
  }).join('');
  s = s.replace(/\s+/g, ' ');
  return s.toLowerCase();
}
function dedupKey(name, deadline) {
  const d = parseDate(deadline);
  return normalizeName(name) + '|' + (d || '');
}
/* 纯 JS SHA-1（id 与 Python hashlib.sha1 前 8 位一致，保证同步合并按 id 匹配） */
function sha1Hex(str) {
  const bytes = new TextEncoder().encode(str);
  let h = [0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476];
  const msg = new Uint8Array(bytes.length + 1 + 8 + 64 - ((bytes.length + 9) % 64));
  msg.set(bytes);
  msg[bytes.length] = 0x80;
  new DataView(msg.buffer).setUint32(msg.length - 4, bytes.length * 8, false);
  const rol = (n, c) => (n << c) | (n >>> (32 - c));
  for (let i = 0; i < msg.length; i += 64) {
    const w = [];
    for (let j = 0; j < 16; j++) w[j] = new DataView(msg.buffer).getUint32(i + j * 4, false);
    for (let j = 16; j < 80; j++) w[j] = rol(w[j - 3] ^ w[j - 8] ^ w[j - 14] ^ w[j - 16], 1);
    let [a, b, c, d, e] = h;
    for (let j = 0; j < 80; j++) {
      let f, k;
      if (j < 20) { f = (b & c) | (~b & d); k = 0x5A827999; }
      else if (j < 40) { f = b ^ c ^ d; k = 0x6ED9EBA1; }
      else if (j < 60) { f = (b & c) | (b & d) | (c & d); k = 0x8F1BBCDC; }
      else { f = b ^ c ^ d; k = 0xCA62C1D6; }
      const t = (rol(a, 5) + f + e + k + w[j]) >>> 0;
      e = d; d = c; c = rol(b, 30); b = a; a = t;
    }
    h = [(a + h[0]) >>> 0, (b + h[1]) >>> 0, (c + h[2]) >>> 0, (d + h[3]) >>> 0, (e + h[4]) >>> 0];
  }
  return h.map(n => n.toString(16).padStart(8, '0')).join('');
}
function makeId(name, deadline) { return 'c_' + sha1Hex(dedupKey(name, deadline)).slice(0, 8); }
function makeAwardId(name, awardDate) {
  const d = parseDate(awardDate);
  return 'a_' + sha1Hex(normalizeName(name) + '|' + (d || '')).slice(0, 8);
}
function nowIso() { return new Date().toISOString().replace('T', ' ').slice(0, 19); }
function localToday() {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}
function daysBetween(a, b) {
  return Math.round((new Date(a + 'T00:00:00') - new Date(b + 'T00:00:00')) / 864e5);
}
function effectiveSuggested(c) {
  if (c.suggested_deadline) return c.suggested_deadline;
  const buf = c.deadline_buffer_days === null || c.deadline_buffer_days === undefined ? DEFAULT_BUFFER_DAYS : Math.max(0, Number(c.deadline_buffer_days) || 0);
  const dl = new Date(c.deadline + 'T00:00:00');
  dl.setDate(dl.getDate() - buf);
  return `${dl.getFullYear()}-${String(dl.getMonth() + 1).padStart(2, '0')}-${String(dl.getDate()).padStart(2, '0')}`;
}
function compStatus(c, today) {
  if (VALID_OVERRIDES.includes(c.status_override)) return c.status_override;
  if (today > c.deadline) return 'overdue';
  if (today > effectiveSuggested(c)) return 'past_suggested';
  if (daysBetween(effectiveSuggested(c), today) <= URGENT_DAYS) return 'urgent';
  if (c.signup_start && today < c.signup_start) return 'not_started';
  if (c.signup_end && today <= c.signup_end) return 'open';
  return 'submitting';
}
function milestoneCountdowns(c, today) {
  return (c.milestones || []).map(m => ({
    name: String(m.name ?? ''), date: parseDate(m.date) || '',
    days: m.date ? daysBetween(m.date, today) : null,
  })).filter(m => m.date);
}
function serializeComp(c, today) {
  const out = { ...c };
  out.suggested_deadline = effectiveSuggested(c);
  out.countdown = daysBetween(effectiveSuggested(c), today);
  out.official_countdown = daysBetween(c.deadline, today);
  out.status = compStatus(c, today);
  out.status_label = STATUS_LABELS[out.status] || out.status;
  out.milestone_countdowns = milestoneCountdowns(c, today);
  return out;
}
function computeStats(comps, today) {
  const by_status = {}, by_category = {};
  let completed = 0, total = comps.length;
  const upcoming = [];
  const weekly = {}, monthly = {};
  for (const c of comps) {
    const s = compStatus(c, today);
    by_status[s] = (by_status[s] || 0) + 1;
    if (s === 'submitted' || s === 'done') completed++;
    const cat = c.category || '未分类';
    by_category[cat] = (by_category[cat] || 0) + 1;
    if (!['submitted', 'done', 'abandoned', 'overdue'].includes(s)) {
      const d = effectiveSuggested(c);
      if (d >= today) {
        upcoming.push(serializeComp(c, today));
        const wk = Math.floor(daysBetween(d, today) / 7);
        weekly[wk] = (weekly[wk] || 0) + 1;
        const ym = d.slice(0, 7);
        monthly[ym] = (monthly[ym] || 0) + 1;
      }
    }
  }
  upcoming.sort((a, b) => a.countdown - b.countdown);
  const weeks = Array.from({ length: 12 }, (_, i) => weekly[i] || 0);
  const months = [];
  const td = new Date(today + 'T00:00:00');
  for (let i = 0; i < 6; i++) {
    const m = new Date(td.getFullYear(), td.getMonth() + i, 1);
    const ym = `${m.getFullYear()}-${String(m.getMonth() + 1).padStart(2, '0')}`;
    months.push({ month: ym, count: monthly[ym] || 0 });
  }
  return {
    total, by_status, by_category,
    upcoming: upcoming.slice(0, 30),
    due_in_7: upcoming.filter(u => u.countdown <= 7).length,
    due_in_30: upcoming.filter(u => u.countdown <= 30).length,
    completed, weeks, months, today,
  };
}
/* ---- 本地文件存储（Capacitor Filesystem） ---- */
const LOC = {
  comps: [], awards: [], ready: false,
  async init() {
    if (!window.Capacitor?.Plugins?.Filesystem) return;
    const fs = window.Capacitor.Plugins.Filesystem;
    const ensure = async (path, dir) => {
      try { await fs.mkdir({ path, directory: dir, recursive: true }); } catch (e) { /* 已存在 */ }
    };
    try { await fs.mkdir({ path: LOC_DIR, directory: DIR_DATA, recursive: true }); } catch (e) {}
    await ensure(LOC_DIR + '/certificates', DIR_DATA);
    await ensure(LOC_DIR + '/backups', DIR_DATA);
    const readOrSeed = async (fname) => {
      const field = fname === 'awards.json' ? 'awards' : 'competitions';
      const path = LOC_DIR + '/' + fname;
      const validate = text => {
        const data = JSON.parse(text);
        if (!data || !Array.isArray(data[field]) || data[field].some(v => !v || typeof v !== 'object' || !v.id || !v.name)) throw new Error('数据结构损坏');
        return data;
      };
      let raw;
      try { raw = (await fs.readFile({ path, directory: DIR_DATA, encoding: 'utf8' })).data; }
      catch (e) {
        if (!/not exist|not found|ENOENT|OS-PLUG-FILE-0008/i.test(String(e.message || e.code || e))) throw new Error('读取失败，已停止写入以保护数据：' + fname);
        const empty = { schema_version: 1, updated_at: nowIso(), [field]: [] };
        await fs.writeFile({ path, directory: DIR_DATA, encoding: 'utf8', data: JSON.stringify(empty) });
        return empty;
      }
      try { return validate(raw); }
      catch (e) {
        // Preserve the original before any recovery; inability to preserve stops startup.
        await fs.writeFile({ path: path + '.' + Date.now() + '.corrupt', directory: DIR_DATA, encoding: 'utf8', data: raw });
        let files = [];
        try { files = (await fs.readdir({ path: LOC_DIR + '/backups', directory: DIR_DATA })).files; } catch (e) {}
        for (const f of files.filter(f => f.name.startsWith(field + '_') && f.name.endsWith('.json')).sort((a,b) => b.name.localeCompare(a.name))) {
          let text, restored;
          try { text = (await fs.readFile({ path: LOC_DIR + '/backups/' + f.name, directory: DIR_DATA, encoding: 'utf8' })).data; restored = validate(text); } catch (e) { continue; }
          await fs.writeFile({ path: path + '.tmp', directory: DIR_DATA, encoding: 'utf8', data: text });
          await fs.rename({ from: path + '.tmp', to: path, directory: DIR_DATA, toDirectory: DIR_DATA });
          this.recoveryMessage = '已从备份恢复 ' + fname + '，损坏原文件已保留。';
          return restored;
        }
        throw new Error(fname + ' 已损坏且无有效备份。原文件已保留，请从导出备份恢复；程序未清空数据。');
      }
    };
    this.comps = (await readOrSeed('competitions.json')).competitions || [];
    this.awards = (await readOrSeed('awards.json')).awards || [];
    this.ready = true;
  },
  writeQueue: Promise.resolve(),
  async atomicSave(field, records) {
    const text = JSON.stringify({ schema_version: 1, updated_at: nowIso(), [field]: records });
    const task = async () => {
      const fs = window.Capacitor.Plugins.Filesystem, path = LOC_DIR + '/' + field + '.json';
      let previous;
      try { previous = (await fs.readFile({ path, directory: DIR_DATA, encoding: 'utf8' })).data; }
      catch (e) { if (!/not exist|not found|ENOENT|OS-PLUG-FILE-0008/i.test(String(e.message || e.code || e))) throw e; }
      if (previous) await fs.writeFile({ path: LOC_DIR + '/backups/' + field + '_' + new Date().toISOString().replace(/\D/g, '') + '_' + Math.random().toString(16).slice(2) + '.json', directory: DIR_DATA, encoding: 'utf8', data: previous, recursive: true });
      await fs.writeFile({ path: path + '.tmp', directory: DIR_DATA, encoding: 'utf8', data: text, recursive: true });
      await fs.rename({ from: path + '.tmp', to: path, directory: DIR_DATA, toDirectory: DIR_DATA });
    };
    const pending = this.writeQueue.then(task);
    this.writeQueue = pending.catch(() => {});
    return pending;
  },
  async saveComps() { return this.atomicSave('competitions', this.comps); },
  async saveAwards() { return this.atomicSave('awards', this.awards); },
  async backup(prefix) {
    try {
      const fs = window.Capacitor.Plugins.Filesystem;
      const ts = new Date().toISOString().slice(0, 19).replace(/[-:T]/g, '').slice(0, 14);
      const fname = prefix + '_' + ts + '.json';
      const src = prefix === 'awards' ? this.awards : this.comps;
      await fs.writeFile({
        path: LOC_DIR + '/backups/' + fname, directory: DIR_DATA,
        data: JSON.stringify(prefix === 'awards' ? { schema_version: 1, updated_at: nowIso(), awards: src } : { schema_version: 1, updated_at: nowIso(), competitions: src }),
        encoding: 'utf8', recursive: true,
      });
      const list = await fs.readdir({ path: LOC_DIR + '/backups', directory: DIR_DATA });
      const mine = list.files.filter(f => f.name.startsWith(prefix + '_')).sort((a, b) => a.name < b.name ? 1 : -1);
      for (const old of mine.slice(20)) {
        try { await fs.deleteFile({ path: LOC_DIR + '/backups/' + old.name, directory: DIR_DATA }); } catch (e) {}
      }
    } catch (e) {}
  },
};
/* ---- 本地模式 API 路由（复刻 app/api.py） ---- */
async function apiLocal(method, pathname, qs, body) {
  const ok = (status, data) => ({ status, data });
  const err = (status, error, code) => ({ status, data: { ok: false, error, code: code || 'E_' + status } });
  const today = localToday();
  await LOC.init();
  if (method === 'GET' && pathname === '/api/health') return ok(200, { ok: true, version: VERSION_LOCAL, port: 0, data_dir: '手机本地', count: LOC.comps.length });
  if (method === 'GET' && pathname === '/api/stats') return ok(200, computeStats(LOC.comps, today));
  if (method === 'GET' && pathname === '/api/competitions') {
    const keyword = String(qs.get('keyword') || '').trim().toLowerCase();
    const cats = qs.getAll('category');
    const statuses = qs.getAll('status');
    let items = LOC.comps.map(c => serializeComp(c, today));
    if (keyword) items = items.filter(c => (c.name + c.organizer + c.notes + ' ' + (c.tags || []).join(' ')).toLowerCase().includes(keyword));
    if (cats.length) items = items.filter(c => cats.includes(c.category));
    if (statuses.length) items = items.filter(c => statuses.includes(c.status));
    const sort = qs.get('sort') || 'deadline';
    const rev = qs.get('order') === 'desc';
    if (sort === 'name') items.sort((a, b) => rev ? b.name.localeCompare(a.name) : a.name.localeCompare(b.name));
    else if (sort === 'created') items.sort((a, b) => rev ? String(b.created_at).localeCompare(String(a.created_at)) : String(a.created_at).localeCompare(String(b.created_at)));
    else items.sort((a, b) => rev ? b.suggested_deadline.localeCompare(a.suggested_deadline) : a.suggested_deadline.localeCompare(b.suggested_deadline));
    return ok(200, { competitions: items, count: items.length });
  }
  const cidMatch = pathname.match(/^\/api\/competitions\/([^/]+)$/);
  if (cidMatch) {
    const id = decodeURIComponent(cidMatch[1]);
    const idx = LOC.comps.findIndex(c => c.id === id);
    if (method === 'GET') return idx >= 0 ? ok(200, { competition: serializeComp(LOC.comps[idx], today) }) : err(404, '记录不存在');
    if (method === 'PUT') {
      if (idx < 0) return err(404, '记录不存在');
      const merged = { ...LOC.comps[idx], ...Object.fromEntries(Object.entries(body || {}).filter(([, v]) => v !== null && v !== undefined)), id };
      merged.created_at = LOC.comps[idx].created_at;
      const saved = parseComp(merged);
      LOC.comps[idx] = saved;
      await LOC.saveComps(); await LOC.backup('competitions');
      return ok(200, { ok: true, competition: serializeComp(saved, today) });
    }
    if (method === 'DELETE') {
      if (idx < 0) return err(404, '记录不存在');
      LOC.comps.splice(idx, 1);
      await LOC.saveComps(); await LOC.backup('competitions');
      return ok(200, { ok: true, deleted: id });
    }
  }
  if (method === 'POST' && pathname === '/api/competitions') {
    try {
      const c = parseComp({ ...(body || {}), source: 'manual' });
      c.id = makeId(c.name, c.deadline);
      if (!c.created_at) c.created_at = nowIso();
      c.updated_at = nowIso();
      LOC.comps = LOC.comps.filter(x => x.id !== c.id);
      LOC.comps.push(c);
      await LOC.saveComps(); await LOC.backup('competitions');
      return ok(201, { ok: true, competition: serializeComp(c, today) });
    } catch (e) { return err(400, e.message); }
  }
  if (method === 'POST' && pathname === '/api/import') {
    const text = String(body?.text || '').trim();
    if (!text) return err(400, '内容为空');
    let records;
    try { records = parseTextLocal(text); } catch (e) { return err(400, e.message); }
    const report = importRecordsLocal(records);
    await LOC.saveComps(); if (report.added || report.updated) await LOC.backup('competitions');
    return ok(200, { ok: true, report });
  }
  if (method === 'POST' && pathname === '/api/backup') {
    await LOC.backup('competitions'); await LOC.backup('awards');
    return ok(200, { ok: true, backup: '手机本地备份' });
  }
  if (method === 'POST' && pathname === '/api/import_all') {
    /* 同步落地点：从电脑拉取的全量快照写入本地（merge 按 id 合并 / replace 全量重建） */
    const mode = body?.mode || 'merge';
    const rep = { competitions: { added: 0, updated: 0, skipped: 0 }, awards: { added: 0, updated: 0, skipped: 0 } };
    const compsIn = body?.competitions || [];
    const awardsIn = body?.awards || [];
    if (mode === 'replace') {
      const map = {};
      for (const raw of compsIn) { try { const c = parseComp(raw); map[c.id] = c; } catch (e) { rep.competitions.skipped++; } }
      LOC.comps = Object.values(map);
      rep.competitions.added = LOC.comps.length;
      const amap = {};
      for (const raw of awardsIn) { try { const a = parseAward(raw); amap[a.id] = a; } catch (e) { rep.awards.skipped++; } }
      LOC.awards = Object.values(amap);
      rep.awards.added = LOC.awards.length;
    } else {
      const byId = new Map(LOC.comps.map(c => [c.id, c]));
      for (const raw of compsIn) {
        try {
          const c = parseComp(raw);
          if (byId.has(c.id)) rep.competitions.updated++; else rep.competitions.added++;
          byId.set(c.id, c);
        } catch (e) { rep.competitions.skipped++; }
      }
      LOC.comps = [...byId.values()];
      const aById = new Map(LOC.awards.map(a => [a.id, a]));
      for (const raw of awardsIn) {
        try {
          const a = parseAward(raw);
          if (aById.has(a.id)) rep.awards.updated++; else rep.awards.added++;
          aById.set(a.id, a);
        } catch (e) { rep.awards.skipped++; }
      }
      LOC.awards = [...aById.values()];
    }
    await LOC.saveComps(); await LOC.saveAwards();
    return ok(200, { ok: true, mode, report: rep });
  }
  if (method === 'GET' && pathname === '/api/awards') {
    const keyword = String(qs.get('keyword') || '').trim().toLowerCase();
    const levels = qs.getAll('level');
    const firstOnly = qs.get('first') === 'true';
    let items = LOC.awards.map(a => ({ ...a }));
    if (keyword) items = items.filter(a => (a.name + a.competition + a.notes + a.award_rank + a.role + ' ' + (a.certificate_files || []).join(' ')).toLowerCase().includes(keyword));
    if (levels.length) items = items.filter(a => levels.includes(a.level));
    if (firstOnly) items = items.filter(a => a.is_first_author);
    return ok(200, { awards: items, count: items.length });
  }
  if (method === 'GET' && pathname === '/api/awards/stats') {
    const by_level = {}, by_year = {};
    let first_count = 0;
    for (const a of LOC.awards) {
      by_level[a.level || '校级'] = (by_level[a.level || '校级'] || 0) + 1;
      if (a.award_date) by_year[a.award_date.slice(0, 4)] = (by_year[a.award_date.slice(0, 4)] || 0) + 1;
      if (a.is_first_author) first_count++;
    }
    return ok(200, { total: LOC.awards.length, by_level, by_year, first_author: first_count });
  }
  if (method === 'POST' && pathname === '/api/awards/import') {
    const records = body?.awards || body?.records || [];
    const list = Array.isArray(records) ? records : [records];
    const report = { added: 0, updated: 0, skipped: 0, errors: [] };
    const existing = new Map(LOC.awards.map(a => [a.id, a]));
    for (const raw of list) {
      if (!raw || typeof raw !== 'object') { report.errors.push({ name: String(raw).slice(0, 30), reason: '记录不是对象' }); continue; }
      try {
        const a = parseAward(raw);
        const dup = existing.get(a.id);
        if (dup && !raw.force_update) { report.skipped++; continue; }
        if (dup) {
          a.id = dup.id; a.created_at = dup.created_at;
          report.updated++;
        } else report.added++;
        existing.set(a.id, a);
      } catch (e) { report.errors.push({ name: String(raw.name || '?'), reason: e.message }); }
    }
    LOC.awards = [...existing.values()];
    await LOC.saveAwards(); if (report.added || report.updated) await LOC.backup('awards');
    return ok(report.errors.length ? 207 : 200, { ok: !report.errors.length, report });
  }
  const aidMatch = pathname.match(/^\/api\/awards\/([^/]+)$/);
  if (aidMatch) {
    const id = decodeURIComponent(aidMatch[1]);
    const idx = LOC.awards.findIndex(a => a.id === id);
    if (method === 'GET') return idx >= 0 ? ok(200, { award: { ...LOC.awards[idx] } }) : err(404, '获奖记录不存在');
    if (method === 'PUT') {
      if (idx < 0) return err(404, '获奖记录不存在');
      const merged = { ...LOC.awards[idx], ...Object.fromEntries(Object.entries(body || {}).filter(([, v]) => v !== null && v !== undefined)), id };
      merged.created_at = LOC.awards[idx].created_at;
      const saved = parseAward(merged);
      LOC.awards[idx] = saved;
      await LOC.saveAwards(); await LOC.backup('awards');
      return ok(200, { ok: true, award: { ...saved } });
    }
    if (method === 'DELETE') {
      if (idx < 0) return err(404, '获奖记录不存在');
      LOC.awards.splice(idx, 1);
      await LOC.saveAwards(); await LOC.backup('awards');
      return ok(200, { ok: true, deleted: id });
    }
  }
  if (method === 'POST' && pathname === '/api/awards') {
    try {
      const a = parseAward({ ...(body || {}), source: 'manual' });
      a.id = makeAwardId(a.name, a.award_date);
      if (!a.created_at) a.created_at = nowIso();
      a.updated_at = nowIso();
      LOC.awards = LOC.awards.filter(x => x.id !== a.id);
      LOC.awards.push(a);
      await LOC.saveAwards(); await LOC.backup('awards');
      return ok(201, { ok: true, award: { ...a } });
    } catch (e) { return err(400, e.message); }
  }
  if (method === 'POST' && pathname === '/api/certificates') {
    const fname = String(body?.name || 'cert');
    const b64 = String(body?.data || '');
    if (!b64) return err(400, '缺少文件内容');
    try {
      await window.Capacitor.Plugins.Filesystem.writeFile({ path: LOC_DIR + '/certificates/' + fname, directory: DIR_DATA, data: b64, recursive: true });
      return ok(201, { ok: true, filename: fname });
    } catch (e) { return err(500, '写入失败: ' + e.message); }
  }
  return err(404, '未知路径: ' + method + ' ' + pathname);
}
function parseComp(raw) {
  const name = String(raw.name || '').trim();
  const deadline = parseDate(raw.deadline);
  if (!name) throw new Error('name 不能为空');
  if (!deadline) throw new Error('deadline 不是有效日期');
  const suggested = parseDate(raw.suggested_deadline);
  if (suggested && suggested > deadline) throw new Error('临期线晚于官方截止');
  const ss = parseDate(raw.signup_start), se = parseDate(raw.signup_end);
  if (ss && se && ss > se) throw new Error('报名开始晚于报名结束');
  const override = raw.status_override || null;
  if (override && !VALID_OVERRIDES.includes(override)) throw new Error('status_override 非法');
  for (const ms of raw.milestones || []) {
    if (!parseDate(ms?.date)) throw new Error('milestone 日期非法');
    if (parseDate(ms.date) > deadline) throw new Error('里程碑晚于官方截止');
  }
  const known = new Set(['id', 'name', 'deadline', 'suggested_deadline', 'deadline_buffer_days', 'milestones', 'category', 'organizer', 'website', 'signup_start', 'signup_end', 'deadline_note', 'requirements', 'deliverables', 'submission', 'format', 'tags', 'status_override', 'reminder_days', 'notes', 'source', 'source_url', 'created_at', 'updated_at']);
  const extra = {};
  for (const k of Object.keys(raw)) if (!known.has(k)) extra[k] = raw[k];
  const c = {
    id: String(raw.id || makeId(name, deadline)),
    name, deadline,
    suggested_deadline: suggested,
    deadline_buffer_days: raw.deadline_buffer_days === '' || raw.deadline_buffer_days === null || raw.deadline_buffer_days === undefined ? null : Math.max(0, Number(raw.deadline_buffer_days) || 0),
    milestones: (raw.milestones || []).map(m => ({ name: String(m.name ?? ''), date: parseDate(m.date) })),
    category: String(raw.category || ''), organizer: String(raw.organizer || ''),
    website: String(raw.website || ''), signup_start: ss, signup_end: se,
    deadline_note: String(raw.deadline_note || ''), requirements: String(raw.requirements || ''),
    deliverables: Array.isArray(raw.deliverables) ? raw.deliverables : [], submission: raw.submission && typeof raw.submission === 'object' ? raw.submission : {},
    format: raw.format && typeof raw.format === 'object' ? raw.format : {}, tags: Array.isArray(raw.tags) ? raw.tags : [],
    status_override: override, reminder_days: Array.isArray(raw.reminder_days) && raw.reminder_days.length ? raw.reminder_days : [7, 1],
    notes: String(raw.notes || ''), source: String(raw.source || 'manual'), source_url: String(raw.source_url || ''),
    created_at: String(raw.created_at || ''), updated_at: String(raw.updated_at || ''),
    ...extra,
  };
  return c;
}
function parseAward(raw) {
  const name = String(raw.name || '').trim();
  if (!name) throw new Error('name 必填');
  const awardDate = parseDate(raw.award_date);
  let level = String(raw.level || '校级').trim();
  if (!VALID_AWARD_LEVELS.includes(level)) level = '校级';
  const first = raw.is_first_author;
  const isFirst = first === true || String(first).toLowerCase() === 'true' || String(first) === '1' || String(first) === '是' || String(first) === '一作' || String(first) === '第一作者';
  const certs = raw.certificate_files || raw.certificate || [];
  const certList = Array.isArray(certs) ? certs.map(String) : (certs ? [String(certs)] : []);
  const known = new Set(['id', 'name', 'level', 'award_rank', 'is_first_author', 'role', 'competition', 'award_date', 'certificate_files', 'notes', 'source', 'source_url', 'created_at', 'updated_at']);
  const extra = {};
  for (const k of Object.keys(raw)) if (!known.has(k)) extra[k] = raw[k];
  return {
    id: String(raw.id || makeAwardId(name, awardDate)),
    name, level, award_rank: String(raw.award_rank || ''), is_first_author: isFirst,
    role: String(raw.role || ''), competition: String(raw.competition || ''),
    award_date: awardDate, certificate_files: certList,
    notes: String(raw.notes || raw.note || ''), source: String(raw.source || 'manual'), source_url: String(raw.source_url || ''),
    created_at: String(raw.created_at || ''), updated_at: String(raw.updated_at || ''),
    ...extra,
  };
}
const MD_ALIASES = {
  name: ['名称', 'name', '比赛', '比赛名称'],
  deadline: ['截止', 'deadline', '截止日期', '截止时间', '提交截止'],
  suggested_deadline: ['临期线', '建议截止', '校内截止', 'suggested_deadline'],
  category: ['类别', 'category', '分类'],
  organizer: ['主办方', 'organizer', '主办'],
  website: ['官网', 'website', '网址', '链接', '官网链接'],
  requirements: ['要求', 'requirements', '作品要求'],
  notes: ['备注', 'notes', '说明'],
};
function parseTextLocal(text) {
  const stripped = text.trim();
  if (!stripped) throw new Error('内容为空');
  if (stripped.startsWith('{') || stripped.startsWith('[')) {
    try {
      let data = JSON.parse(stripped);
      if (data && typeof data === 'object' && !Array.isArray(data)) {
        for (const k of ['competitions', 'items', 'records', 'data']) {
          if (k in data) { data = data[k]; break; }
        }
      }
      if (Array.isArray(data)) return data.filter(d => d && typeof d === 'object');
      if (data && typeof data === 'object') return [data];
      throw new Error('JSON 顶层必须是对象或数组');
    } catch (e) {
      if (!(e instanceof SyntaxError)) throw e;
      /* 落到 Markdown */
    }
  }
  const lines = stripped.split('\n').map(l => l.trim()).filter(l => l.startsWith('|'));
  if (lines.length < 2) throw new Error('无法识别内容格式（支持 JSON 或 Markdown 表格）');
  const header = lines[0].replace(/^\||\|$/g, '').split('|').map(c => c.trim());
  let body = lines.slice(1);
  if (/^[\s\-:|]+$/.test(body[0].replace(/^\||\|$/g, ''))) body = body.slice(1);
  const fieldMap = header.map(col => {
    for (const [field, aliases] of Object.entries(MD_ALIASES)) if (aliases.includes(col)) return field;
    return null;
  });
  const records = [];
  for (const ln of body) {
    const cells = ln.replace(/^\||\|$/g, '').split('|').map(c => c.trim());
    const rec = {};
    cells.forEach((cell, i) => { if (i < fieldMap.length && fieldMap[i] && cell) rec[fieldMap[i]] = cell; });
    if (rec.name || rec.deadline) records.push(rec);
  }
  if (!records.length) throw new Error('未找到有效记录');
  return records;
}
function importRecordsLocal(records) {
  const report = { added: 0, updated: 0, skipped: 0, errors: [] };
  const index = new Map();
  for (const c of LOC.comps) index.set(dedupKey(c.name, c.deadline), c);
  const now = nowIso();
  for (const raw of records) {
    if (!raw || typeof raw !== 'object') { report.errors.push({ name: String(raw).slice(0, 30), reason: '记录不是对象' }); continue; }
    let comp;
    try { comp = parseComp(raw); } catch (e) { report.errors.push({ name: String(raw.name || '?'), reason: e.message }); continue; }
    const key = dedupKey(comp.name, comp.deadline);
    const dup = index.get(key);
    const force = Boolean(raw.force_update);
    if (dup && !force) { report.skipped++; continue; }
    if (dup && force) {
      const merged = { ...dup };
      for (const [k, v] of Object.entries(raw)) {
        if (v === null || v === undefined || v === '' || (Array.isArray(v) && !v.length) || (typeof v === 'object' && !Array.isArray(v) && !Object.keys(v).length)) continue;
        merged[k] = v;
      }
      if (dup.status_override) merged.status_override = dup.status_override;
      merged.id = dup.id; merged.created_at = dup.created_at; merged.updated_at = now;
      const saved = parseComp(merged);
      index.set(key, saved);
      report.updated++;
      continue;
    }
    comp.id = makeId(comp.name, comp.deadline);
    if (!comp.created_at) comp.created_at = now;
    comp.updated_at = now;
    index.set(key, comp);
    report.added++;
  }
  LOC.comps = [...index.values()];
  return report;
}
/* 证书 URL：本地模式读文件转 data URL，桌面模式走 /certificates/ 静态路由 */
async function certUrl(fname) {
  if (!IS_LOCAL) return '/certificates/' + encodeURIComponent(fname);
  try {
    const r = await window.Capacitor.Plugins.Filesystem.readFile({ path: LOC_DIR + '/certificates/' + fname, directory: DIR_DATA });
    const mime = /\.(jpe?g)$/i.test(fname) ? 'image/jpeg' : /\.png$/i.test(fname) ? 'image/png' : /\.webp$/i.test(fname) ? 'image/webp' : /\.gif$/i.test(fname) ? 'image/gif' : 'application/pdf';
    return 'data:' + mime + ';base64,' + r.data;
  } catch (e) { return ''; }
}
/* ================= 数据同步（手机 ↔ 电脑，局域网） ================= */
function syncToken() {
  try { return JSON.parse(localStorage.getItem('wc_pair') || 'null')?.token || null; } catch (e) { return null; }
}
function syncPairedUrl() {
  try { return JSON.parse(localStorage.getItem('wc_pair') || 'null')?.url || ''; } catch (e) { return ''; }
}
async function httpReq(base, path, opts = {}) {
  const headers = { 'Content-Type': 'application/json', ...(opts.headers || {}) };
  if (opts.sync && !headers['X-Sync-Token']) {
    const t = syncToken();
    if (t) headers['X-Sync-Token'] = t;
  }
  if (IS_LOCAL && window.Capacitor?.Plugins?.CapacitorHttp) {
    const Http = window.Capacitor.Plugins.CapacitorHttp;
    const r = await Http.request({
      url: base.replace(/\/$/, '') + path, method: opts.method || 'GET',
      data: opts.body, headers,
      connectTimeout: 8000, readTimeout: 30000,
    });
    return r.data;
  }
  const res = await fetch(base.replace(/\/$/, '') + path, {
    method: opts.method || 'GET',
    headers,
    body: opts.body ? JSON.stringify(opts.body) : undefined,
  });
  return res.json();
}
function fmtSyncReport(rep, isPull) {
  if (!rep) return '';
  const parts = [];
  const c = rep.competitions || {}, a = rep.awards || {};
  if (isPull) {
    parts.push(`比赛：新增 ${c.added || 0} · 更新 ${c.updated || 0}${c.skipped ? ` · 跳过 ${c.skipped}` : ''}`);
    parts.push(`获奖：新增 ${a.added || 0} · 更新 ${a.updated || 0}${a.skipped ? ` · 跳过 ${a.skipped}` : ''}`);
  } else {
    const pc = rep.competitions || rep.updated ? rep : {};
    parts.push(`比赛：新增 ${c.added || 0} · 更新 ${c.updated || 0}${c.skipped ? ` · 跳过 ${c.skipped}` : ''}`);
    parts.push(`获奖：新增 ${a.added || 0} · 更新 ${a.updated || 0}${a.skipped ? ` · 跳过 ${a.skipped}` : ''}`);
  }
  return parts.join('　');
}
function syncAddr() {
  let v = ($('syncAddr')?.value || '').trim();
  if (!v) v = localStorage.getItem('wc_sync_addr') || '';
  if (!v) return '';
  localStorage.setItem('wc_sync_addr', v);
  return v.replace(/\/$/, '');
}
async function syncPull() {
  const base = syncAddr();
  if (!base) return toast('先扫码配对或填电脑地址', 'warn');
  const btn = $('syncPullBtn'); if (btn) { btn.disabled = true; btn.textContent = '拉取中…'; }
  try {
    const d = await httpReq(base, '/api/export_all', { sync: true });
    if (!d.ok) throw new Error(d.error || (d.code === 'E_PAIR' ? '未配对（401）' : '电脑端返回异常'));
    const r = await apiLocal('POST', '/api/import_all', new URLSearchParams(), { mode: 'merge', competitions: d.competitions, awards: d.awards });
    toast('已从电脑拉取 ✅ ' + fmtSyncReport(r.data.report, true));
    await refresh(); refreshAwards().then(renderAwards);
    if ($('syncResult')) $('syncResult').textContent = '上次拉取：' + new Date().toLocaleTimeString() + '　' + fmtSyncReport(r.data.report, true);
    /* 顺带把电脑上的获奖凭证文件拉到本地（此前只同步 JSON，手机上看不了图）（2026-10-16） */
    syncCertificates(base, d.awards).catch(() => {});
  } catch (e) { toast('拉取失败：' + e.message, 'err'); if ($('syncResult')) $('syncResult').textContent = '拉取失败：' + e.message; }
  finally { if (btn) { btn.disabled = false; btn.textContent = '📥 从电脑拉取'; } }
}
/* 逐个下载电脑端 data/certificates/ 里被获奖记录引用、本地缺失的凭证文件。
   图片凭证优先取电脑端生成的压缩预览图（<原名>_preview.jpg，~200KB），
   以原名落盘——查看与体积都与原件体验一致，传输量大幅下降（2026-10-17）。 */
async function syncCertificates(base, awards) {
  if (!IS_LOCAL || !window.Capacitor?.Plugins?.Filesystem) return;
  const fs = window.Capacitor.Plugins.Filesystem;
  const names = [...new Set((awards || []).flatMap(a => a.certificate_files || []))];
  if (!names.length) return;
  await LOC.init();
  let done = 0, fetched = 0;
  const token = syncToken();
  const headers = token ? { 'X-Sync-Token': token } : {};
  for (const name of names) {
    try {
      let res = null, isPreview = false;
      if (/\.(jpe?g|png|webp|gif)$/i.test(name)) {
        /* 直接拉预览：命中即用（200 时响应体就是预览数据，无额外探测开销） */
        const pv = name.replace(/(\.[^.]+)$/, '_preview.jpg');
        res = await fetch(base + '/certificates/' + encodeURIComponent(pv), { headers, credentials: 'omit' });
        if (res.ok) isPreview = true;
      }
      if (!res || !res.ok) {
        /* 无预览：本地已有原件则跳过 */
        try { await fs.stat({ path: LOC_DIR + '/certificates/' + name, directory: DIR_DATA }); done++; continue; } catch (e) { /* 本地无 → 下载原件 */ }
        res = await fetch(base + '/certificates/' + encodeURIComponent(name), { headers, credentials: 'omit' });
      }
      if (!res.ok) continue;
      const buf = new Uint8Array(await res.arrayBuffer());
      let bin = '';
      for (let i = 0; i < buf.length; i += 32768) bin += String.fromCharCode.apply(null, buf.subarray(i, i + 32768));
      await fs.writeFile({ path: LOC_DIR + '/certificates/' + name, directory: DIR_DATA,
        data: btoa(bin), recursive: true });
      fetched++;
      void isPreview;
    } catch (e) { /* 单个失败跳过，不阻断整体 */ }
    done++;
    if (done === names.length && fetched > 0) toast(`凭证已同步 ${fetched}/${names.length} 个，点开即可查看`);
  }
}
async function syncPush() {
  const base = syncAddr();
  if (!base) return toast('先扫码配对或填电脑地址', 'warn');
  const btn = $('syncPushBtn'); if (btn) { btn.disabled = true; btn.textContent = '推送中…'; }
  try {
    await LOC.init();
    const r = await httpReq(base, '/api/import_all', { method: 'POST', body: { mode: 'merge', competitions: LOC.comps, awards: LOC.awards }, sync: true });
    if (!r.ok) throw new Error(r.error || (r.code === 'E_PAIR' ? '未配对（401）' : '电脑端返回异常'));
    toast('已推送到电脑 ✅ ' + fmtSyncReport(r.report || r, false));
    if ($('syncResult')) $('syncResult').textContent = '上次推送：' + new Date().toLocaleTimeString() + '　' + fmtSyncReport(r.report || r, false);
  } catch (e) { toast('推送失败：' + e.message, 'err'); if ($('syncResult')) $('syncResult').textContent = '推送失败：' + e.message; }
  finally { if (btn) { btn.disabled = false; btn.textContent = '📤 推送到电脑'; } }
}
/* ---- 扫码配对（LocalSend 式） ---- */
async function refreshPair() {
  try {
    const d = await api('/api/pair/begin');
    if (!d.ok) throw new Error(d.error || '配对服务不可用');
    if ($('pairCode')) $('pairCode').textContent = d.code;
    window.__pairPort = d.port || '';
    if ($('pairStatus')) $('pairStatus').innerHTML = '电脑地址：' + esc(d.url) + '　·　手机扫码后 5 分钟内有效'
      + (d.ips && d.ips.length > 1
        ? '<div class="mt-2">手机连不上时，试试其他网卡地址（点选填入手机「电脑地址」框）：</div>'
          + '<div class="flex flex-wrap gap-1.5 mt-1.5">' + d.ips.map(ip =>
              '<span class="badge bg-slate-100 text-slate-600 dark:bg-slate-700 dark:text-slate-300 cursor-pointer !py-1 hover:bg-indigo-50 dark:hover:bg-slate-600" data-ip="' + esc(ip) + '" onclick="usePairIp(this.dataset.ip)">' + esc(ip) + '</span>').join('')
          + '</div>'
        : '');
    const qrEl = $('pairQr');
    if (qrEl && typeof QRCode !== 'undefined') {
      qrEl.innerHTML = '';
      new QRCode(qrEl, { text: JSON.stringify({ app: 'wc', v: 1, url: d.url, code: d.code }), width: 112, height: 112, correctLevel: QRCode.CorrectLevel.M });
    } else if (qrEl) {
      qrEl.innerHTML = '<span class="muted text-xs">二维码库未加载</span>';
    }
  } catch (e) {
    if ($('pairStatus')) $('pairStatus').textContent = '配对码生成失败：' + e.message;
  }
}
/* 自绘取景器：getUserMedia 打开相机 + jsQR 逐帧解码（无 Google 服务也能用，有真实相机画面） */
function scanOverlayOpen() { return !!document.getElementById('scanOverlay'); }
function closeScanOverlay() {
  const ov = document.getElementById('scanOverlay');
  if (ov) { ov.dataset.closed = '1'; ov.remove(); }
}
function jsqrScan() {
  return new Promise((resolve, reject) => {
    if (typeof jsQR === 'undefined') { reject(new Error('解码库未加载')); return; }
    const ov = document.createElement('div');
    ov.id = 'scanOverlay';
    ov.style.cssText = 'position:fixed;inset:0;z-index:100;background:#0f172a;display:flex;flex-direction:column;align-items:center;justify-content:center';
    ov.innerHTML = `
      <div style="position:relative;width:min(86vw,420px);aspect-ratio:3/4;background:#000;border-radius:16px;overflow:hidden">
        <video id="scanVideo" playsinline muted style="position:absolute;inset:0;width:100%;height:100%;object-fit:cover"></video>
        <div style="position:absolute;inset:0;display:flex;align-items:center;justify-content:center;pointer-events:none">
          <div style="width:72%;aspect-ratio:1;border:2px solid rgba(129,140,248,.9);border-radius:16px;box-shadow:0 0 0 2000px rgba(15,23,42,.45)"></div>
        </div>
      </div>
      <div style="color:#e2e8f0;margin-top:16px;font-size:14px">对准电脑上的二维码</div>
      <button id="scanCancel" style="margin-top:14px;padding:10px 28px;border-radius:12px;border:0;background:#334155;color:#fff;font-size:14px">取消</button>`;
    document.body.appendChild(ov);
    const video = ov.querySelector('#scanVideo');
    let stream = null, raf = 0, done = false;
    const finish = (err, arg) => {
      if (done) return; done = true;
      cancelAnimationFrame(raf);
      if (stream) stream.getTracks().forEach(t => t.stop());
      ov.remove();
      setTimeout(() => (err ? reject(arg) : resolve(arg)), 0);
    };
    ov.querySelector('#scanCancel').addEventListener('click', () => finish(true, new Error('已取消扫码')));
    if (!navigator.mediaDevices?.getUserMedia) { finish(true, new Error('此环境不支持相机')); return; }
    navigator.mediaDevices.getUserMedia({ video: { facingMode: 'environment' }, audio: false })
      .then((s) => {
        if (done) { s.getTracks().forEach(t => t.stop()); return; }
        stream = s;
        video.srcObject = s;
        return video.play();
      })
      .then(() => {
        const canvas = document.createElement('canvas');
        const ctx = canvas.getContext('2d', { willReadFrequently: true });
        const tick = () => {
          if (done) return;
          if (!document.body.contains(ov)) { finish(true, new Error('已取消扫码')); return; }
          if (video.readyState === video.HAVE_ENOUGH_DATA) {
            canvas.width = video.videoWidth; canvas.height = video.videoHeight;
            if (canvas.width) {
              ctx.drawImage(video, 0, 0);
              const code = jsQR(ctx.getImageData(0, 0, canvas.width, canvas.height).data, canvas.width, canvas.height);
              if (code && code.data) { finish(false, code.data); return; }
            }
          }
          raf = requestAnimationFrame(tick);
        };
        raf = requestAnimationFrame(tick);
      })
      .catch((e) => finish(true, new Error('相机打开失败：' + (e.message || e.name || e))));
  });
}
/* 原生全屏扫码（GmsBarcodeScanner）：需要 Google 服务与扫码模块，不可用时抛错走回落 */
async function nativeScan() {
  const BS = window.Capacitor?.Plugins?.BarcodeScanner;
  if (!BS?.isGoogleBarcodeScannerModuleAvailable || typeof BS.scan !== 'function') throw new Error('原生扫码不可用');
  const avail = await BS.isGoogleBarcodeScannerModuleAvailable();
  if (!avail?.available) throw new Error('扫码模块未安装');
  const r = await BS.scan({ formats: ['QR_CODE'] });
  const bc = (r?.barcodes || [])[0];
  if (!bc?.rawValue) throw new Error('未识别到二维码');
  return bc.rawValue;
}
async function handlePairPayload(raw) {
  let data;
  try { data = JSON.parse(raw); } catch (e) { throw new Error('这不是工作日历的配对码'); }
  if (data.app !== 'wc' || !/^\d{6}$/.test(data.code)) throw new Error('这不是工作日历的配对码');
  const u = new URL(data.url);
  if (u.protocol !== 'http:' || u.username || u.password || u.pathname !== '/' || u.search || u.hash || !/^(10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.)/.test(u.hostname)) throw new Error('仅支持可信局域网中的电脑地址');
  let result = await httpReq(u.origin, '/api/pair/confirm', { method: 'POST', body: { code: data.code } });
  if (!result.ok) throw new Error(result.error || '配对失败');
  const requestId = result.request_id;
  if ($('pairStatus')) $('pairStatus').textContent = '请在电脑上核对并允许此次配对…';
  const deadline = Date.now() + 65000;
  while (result.pending && Date.now() < deadline) {
    await new Promise(resolve => setTimeout(resolve, 1000));
    result = await httpReq(u.origin, '/api/pair/result', { method: 'POST', body: { request_id: requestId } });
    if (!result.ok) throw new Error(result.error || '配对失败');
  }
  if (!result.token) throw new Error('等待电脑批准超时，请重新扫码');
  localStorage.setItem('wc_pair', JSON.stringify({ url: u.origin, token: result.token }));
  localStorage.setItem('wc_sync_addr', u.origin);
  if ($('syncAddr')) $('syncAddr').value = u.origin;
  if ($('pairStatus')) $('pairStatus').textContent = '已配对：' + u.origin;
  toast('配对成功');
}
async function scanPair() {
  const P = window.Capacitor?.Plugins;
  const BS = P?.BarcodeScanner;
  if (!BS && !navigator.mediaDevices?.getUserMedia) { toast('此设备不支持扫码', 'err'); return; }
  const btn = $('pairScanBtn'); if (btn) { btn.disabled = true; btn.textContent = '扫瞄中…'; }
  try {
    /* 相机权限：capawesome 插件返回字符串 granted/denied/prompt，旧插件返回 {camera:bool}，兼容两种；
       WebView 的 getUserMedia 同样依赖系统的 CAMERA 权限，必须先拿 */
    if (BS?.checkPermissions) {
      let perm = await BS.checkPermissions();
      if (!perm || perm.camera === 'denied' || perm.camera === false) perm = await BS.requestPermissions();
      const granted = perm && (perm.camera === true || perm.camera === 'granted' || perm.camera === undefined);
      if (!granted) throw new Error('相机权限未授予，请在系统设置里允许工作日历使用相机');
    }
    let raw = null;
    try { raw = await nativeScan(); } catch (e1) { raw = await jsqrScan(); }
    await handlePairPayload(raw);
  } catch (e) {
    if (e.message !== '已取消扫码') {
      toast('配对失败：' + e.message, 'err');
      if ($('pairStatus')) $('pairStatus').textContent = '配对失败：' + e.message;
    }
  } finally { if (btn) { btn.disabled = false; btn.textContent = '📷 扫一扫配对'; } }
}
/* ================= 全局状态 ================= */
const S = {
  comps: [], compsAll: null, stats: null, view: 'overview',
  filter: { keyword: '', cats: [], statuses: [], showAll: false },
  sort: { key: 'deadline', order: 'asc' },
  editingId: null, importHistory: [],
  charts: {}, dark: false,
};
/* ================= 过期隐藏（2026-10-17） =================
   截止已过 5 天且未标「已完成」→ 默认从列表/时间线隐藏；
   关键词搜索、显式状态筛选或「全览」时可见。 */
function isStaleHidden(c) {
  if ((c.status || '') === 'done') return false;
  if (!c.deadline) return false;
  return daysBetween(localToday(), c.deadline) >= 5;
}
function applyStaleHide(comps) {
  if (S.filter.keyword || (S.filter.statuses && S.filter.statuses.length) || S.filter.showAll) return comps || [];
  return (comps || []).filter(c => !isStaleHidden(c));
}
function staleHiddenCount() {
  if (!S.compsAll) return 0;
  return S.compsAll.filter(isStaleHidden).length;
}
const $ = (id) => document.getElementById(id);
const STATUS_COLOR = {
  urgent: 'bg-rose-100 text-rose-700 dark:bg-rose-900/40 dark:text-rose-300',
  past_suggested: 'bg-amber-100 text-amber-700 dark:bg-amber-900/40 dark:text-amber-300',
  overdue: 'bg-slate-200 text-slate-500 dark:bg-slate-700 dark:text-slate-400',
  submitted: 'bg-emerald-100 text-emerald-700 dark:bg-emerald-900/40 dark:text-emerald-300',
  done: 'bg-teal-100 text-teal-700 dark:bg-teal-900/40 dark:text-teal-300',
  abandoned: 'bg-slate-200 text-slate-500 dark:bg-slate-700 dark:text-slate-400',
  open: 'bg-sky-100 text-sky-700 dark:bg-sky-900/40 dark:text-sky-300',
  not_started: 'bg-slate-100 text-slate-600 dark:bg-slate-700 dark:text-slate-300',
  submitting: 'bg-indigo-100 text-indigo-700 dark:bg-indigo-900/40 dark:text-indigo-300',
};
const CAT_COLORS = ['bg-indigo-50 text-indigo-600 dark:bg-indigo-900/30 dark:text-indigo-300',
  'bg-rose-50 text-rose-600 dark:bg-rose-900/30 dark:text-rose-300',
  'bg-emerald-50 text-emerald-600 dark:bg-emerald-900/30 dark:text-emerald-300',
  'bg-amber-50 text-amber-600 dark:bg-amber-900/30 dark:text-amber-300',
  'bg-sky-50 text-sky-600 dark:bg-sky-900/30 dark:text-sky-300',
  'bg-violet-50 text-violet-600 dark:bg-violet-900/30 dark:text-violet-300',
  'bg-slate-100 text-slate-500 dark:bg-slate-700 dark:text-slate-400'];
function catColor(cat) { let h = 0; for (const ch of (cat || '')) h = (h * 31 + ch.charCodeAt(0)) % 997; return CAT_COLORS[h % CAT_COLORS.length]; }
function countdownBadge(c) {
  const d = c.countdown;
  if (c.status === 'submitted' || c.status === 'done') return `<span class="badge bg-emerald-50 text-emerald-600 border border-emerald-200/60 dark:bg-emerald-900/30 dark:text-emerald-300 dark:border-emerald-700">✓ 已${c.status === 'submitted' ? '提交' : '完成'}</span>`;
  if (c.status === 'abandoned') return `<span class="badge bg-slate-100 text-slate-400 dark:bg-slate-700 dark:text-slate-400">已放弃</span>`;
  if (d === 0) return `<span class="badge bg-gradient-to-r from-rose-600 to-red-500 text-white shadow-md shadow-rose-500/30 pulse-soft">⏰ 今天截止！</span>`;
  if (d < 0) {
    if (c.status === 'overdue') return `<span class="badge bg-slate-200 text-slate-500 dark:bg-slate-700 dark:text-slate-400">已过 ${-d} 天</span>`;
    return `<span class="badge bg-gradient-to-r from-amber-500 to-orange-500 text-white shadow-md shadow-amber-500/30">⚠ 已过临期线 ${-d} 天</span>`;
  }
  const cls = d <= 3 ? 'bg-gradient-to-r from-rose-600 to-red-500 text-white shadow-md shadow-rose-500/30'
    : d <= 7 ? 'bg-gradient-to-r from-rose-500 to-orange-500 text-white shadow-md shadow-rose-500/25'
    : d <= 30 ? 'bg-gradient-to-r from-amber-500 to-yellow-500 text-white shadow-md shadow-amber-500/25'
    : 'bg-gradient-to-r from-emerald-500 to-teal-500 text-white shadow-md shadow-emerald-500/25';
  return `<span class="badge ${cls}">剩 ${d} 天</span>`;
}
function statusBadge(c) {
  const cls = STATUS_COLOR[c.status] || 'bg-slate-100 text-slate-600';
  const map = { not_started: '未开始', open: '报名中', submitting: '进行中', urgent: '即将截止', past_suggested: '已过临期线', overdue: '已截止', submitted: '已提交', done: '已完成', abandoned: '已放弃' };
  return `<span class="badge ${cls}">${map[c.status] || c.status}</span>`;
}
function fmtDate(d) { return d ? d.slice(5).replace('-', '/') : '—'; }
function esc(s) { return String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c])); }
function safeUrl(u) {
  /* URL 协议白名单：仅允许 http/https/mailto，防 javascript: 伪协议注入 */
  u = String(u || '').trim();
  return /^(https?:|mailto:)/i.test(u) ? u : '';
}

/* ================= ECharts 实例管理（防泄漏 + resize） ================= */
function getChart(id) {
  if (S.charts[id]) { S.charts[id].dispose(); }
  S.charts[id] = echarts.init(document.getElementById(id));
  return S.charts[id];
}
window.addEventListener('resize', () => { for (const id in S.charts) S.charts[id].resize(); });

/* ================= API ================= */
let wcAuthPromise;
async function desktopToken() {
  if (!wcAuthPromise) wcAuthPromise = fetch('/api/bootstrap', { headers: { 'X-WorkCalendar-Bootstrap': '1' }, credentials: 'same-origin' })
    .then(async r => { const d = await r.json(); if (!r.ok || !d.token) throw new Error(d.error || '本机授权失败'); return d.token; })
    .catch(e => { wcAuthPromise = null; throw e; });
  return wcAuthPromise;
}
let pairPromptActive = false;
async function pollPairApproval() {
  if (IS_LOCAL || pairPromptActive) return;
  pairPromptActive = true;
  try {
    const d = await api('/api/pair/pending');
    if (d.pending) {
      const allow = window.confirm('设备 ' + d.ip + ' 请求同步工作日历数据。配对码：' + d.code + '\n仅在你刚刚扫码且设备信息一致时允许。');
      await api('/api/pair/approve', { method: 'POST', body: { code: d.code, allow } });
    }
  } catch (e) { /* Next poll retries; do not interrupt editing. */ }
  finally { pairPromptActive = false; }
}
if (!IS_LOCAL) window.addEventListener('DOMContentLoaded', () => setInterval(pollPairApproval, 1500));

async function api(path, opts = {}) {
  if (IS_LOCAL) {
    const u = new URL(path, 'http://local');
    const r = await apiLocal(opts.method || 'GET', u.pathname, u.searchParams, opts.body);
    if (!(r.status >= 200 && r.status < 300) && !r.data.ok) throw new Error(r.data.error || `HTTP ${r.status}`);
    return r.data;
  }
  const res = await fetch(path, {
    method: opts.method || 'GET',
    headers: { 'Content-Type': 'application/json', 'X-API-Token': await desktopToken() },
    credentials: 'same-origin',
    signal: AbortSignal.timeout(30000),
    body: opts.body ? JSON.stringify(opts.body) : undefined,
  });
  const data = await res.json();
  if (!res.ok && !data.ok) throw new Error(data.error || `HTTP ${res.status}`);
  return data;
}

/* 防抖（搜索框等输入联动共用） */
function debounce(fn, ms) { let t = null; return () => { clearTimeout(t); t = setTimeout(fn, ms); }; }

/* ================= 导出落地（三平台统一） ================= */
/* 安卓：写缓存后调系统分享面板（用户自选保存位置）；桌面服务：POST /api/export 落盘 data/exports/ 并回报路径；
   浏览器（含旧版 exe 兜底）：blob 下载。 */
async function download(name, content) {
  if (IS_LOCAL) {
    const P = window.Capacitor?.Plugins;
    try {
      if (!P?.Share || !P?.Filesystem) throw new Error('分享组件不可用');
      const r = await P.Filesystem.writeFile({ path: 'exports/' + name, directory: 'CACHE', data: content, encoding: 'utf8', recursive: true });
      await P.Share.share({ title: name, url: r.uri, dialogTitle: '保存或分享导出文件' });
      toast('已生成导出文件，可在分享面板选择保存位置');
      return;
    } catch (e) {
      const msg = String(e?.message || e);
      if (/cancel|取消/i.test(msg)) return;  /* 用户关掉了分享面板 */
      toast('导出失败：' + msg, 'err');
      return;
    }
  }
  try {
    const r = await api('/api/export', { method: 'POST', body: { name, content } });
    toast('已导出：' + r.path);
    const bi = $('backupInfo'); if (bi) bi.textContent = '最近导出：' + r.path;
    return;
  } catch (e) { /* 旧版 exe 无 /api/export → 浏览器下载兜底 */ }
  const blob = new Blob([content], { type: 'text/plain;charset=utf-8' });
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob); a.download = name; a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 3000);
  toast('已导出：' + name);
}

/* ================= 一键导出全部数据 ================= */
/* 桌面：服务端把 比赛+获奖+证书 打成 zip 到 data/exports/；手机：单文件 JSON 备份（含证书 base64），
   先固定写一份到应用目录 wc_data/导出/，再弹分享面板（选「保存到文件」可自选文件夹）。 */
async function exportAllData() {
  if (!IS_LOCAL) {
    try {
      const r = await api('/api/export_backup', { method: 'POST' });
      toast('已导出：' + r.path + '（含证书 ' + (r.certificates || 0) + ' 个）');
      const bi = $('backupInfo'); if (bi) bi.textContent = '最近导出：' + r.path;
    } catch (e) { toast('导出失败：' + e.message, 'err'); }
    return;
  }
  try {
    const fs = window.Capacitor?.Plugins?.Filesystem;
    let certs = {};
    try {
      const list = await fs.readdir({ path: LOC_DIR + '/certificates', directory: 'DATA' });
      for (const f of (list.files || [])) {
        try {
          const r = await fs.readFile({ path: LOC_DIR + '/certificates/' + f.name, directory: 'DATA' });
          certs[f.name] = r.data;  /* base64 */
        } catch (e) { /* 单个读取失败跳过 */ }
      }
    } catch (e) { /* 无证书目录 */ }
    const payload = {
      schema_version: 1,
      exported_at: nowIso(),
      kind: 'workcalendar_full_backup',
      competitions: (S.comps || []).map(c => { const { countdown, official_countdown, status, status_label, milestone_countdowns, ...rest } = c; return rest; }),
      awards: (S_AWARDS && S_AWARDS.list ? S_AWARDS.list : []).map(a => ({ ...a })),
      certificates: certs,
      note: '证书文件若为空，请在电脑端做全量备份（手机同步仅同步文字数据）。',
    };
    const name = '工作日历备份_' + new Date().toISOString().slice(0, 10) + '.json';
    const text = JSON.stringify(payload);
    await fs.writeFile({ path: LOC_DIR + '/导出/' + name, directory: 'DATA', data: text, encoding: 'utf8', recursive: true });
    const fixed = LOC_DIR + '/导出/' + name;
    const P = window.Capacitor?.Plugins;
    if (P?.Share) {
      try {
        const fr = await fs.getUri({ path: LOC_DIR + '/导出/' + name, directory: 'DATA' });
        await P.Share.share({ title: name, url: fr.uri, dialogTitle: '保存或分享导出文件（选「保存到文件」可自选文件夹）' });
      } catch (e) { /* 用户关闭分享面板：文件已在应用目录 */ }
    }
    toast('已导出：' + fixed);
  } catch (e) { toast('导出失败：' + (e.message || e), 'err'); }
}

/* 手机扫到的地址连不上时（多网卡），把候选 IP 填进电脑地址框 */
function usePairIp(ip) {
  const url = 'http://' + ip + ':' + (window.__pairPort || '');
  localStorage.setItem('wc_sync_addr', url);
  const sa = $('syncAddr'); if (sa) sa.value = url;
  toast('已填入 ' + url + '（把手机端「电脑地址」也改成这个）');
}

/* ---- AI 识图辅助：图片压缩 + 识别结果自动挂凭证（桌面/安卓共用） ---- */
function aiDownscaleImage(file) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onerror = () => reject(new Error('读取失败'));
    reader.onload = () => {
      const img = new Image();
      img.onerror = () => reject(new Error('不是有效图片'));
      img.onload = () => {
        const max = 1600;
        let w = img.width, h = img.height;
        if (Math.max(w, h) > max) { const k = max / Math.max(w, h); w = Math.round(w * k); h = Math.round(h * k); }
        const cv = document.createElement('canvas');
        cv.width = w; cv.height = h;
        cv.getContext('2d').drawImage(img, 0, 0, w, h);
        resolve(cv.toDataURL('image/jpeg', 0.85));
      };
      img.src = reader.result;
    };
    reader.readAsDataURL(file);
  });
}
async function aiAttachCerts(awardId, dataUrls) {
  const added = [];
  for (let i = 0; i < dataUrls.length; i++) {
    const b64 = String(dataUrls[i]).split(',')[1] || '';
    if (!b64) continue;
    try {
      const stamp = new Date().toISOString().replace(/[-:T]/g, '').slice(0, 14);
      const name = `cert_${stamp}_${i + 1}.jpg`;
      await api('/api/certificates', { method: 'POST', body: { name, data: b64 } });
      added.push(name);
    } catch (e) { /* 单个失败继续 */ }
  }
  if (added.length) {
    try {
      const cur = (await api('/api/awards/' + awardId)).award;
      await api('/api/awards/' + awardId, { method: 'PUT', body: { certificate_files: (cur.certificate_files || []).concat(added) } });
    } catch (e) { /* 记录合并失败不影响建档 */ }
  }
  return added;
}

/* ---- 前端报错上报：安卓写入 wc_data/logs/，桌面发 /api/client_log 落 data/logs/ ---- */
let _aiLogDirReady = false;
function reportClientError(message, stack) {
  try { console.error(message, stack || ''); } catch (e) {}
  const line = '[' + new Date().toLocaleTimeString() + '] ' + String(message).slice(0, 400)
    + (stack ? '\n    ' + String(stack).slice(0, 800).replace(/\n/g, '\n    ') : '') + '\n';
  try {
    if (IS_LOCAL && window.Capacitor?.Plugins?.Filesystem) {
      const fs = window.Capacitor.Plugins.Filesystem;
      const write = () => fs.appendFile({
        path: LOC_DIR + '/logs/client_' + localToday() + '.log',
        directory: 'DATA', data: line, encoding: 'utf8' });
      if (!_aiLogDirReady) {
        return fs.mkdir({ path: LOC_DIR + '/logs', directory: 'DATA', recursive: true })
          .catch(() => {}).then(() => { _aiLogDirReady = true; return write(); }).catch(() => {});
      }
      return write();
    }
    return api('/api/client_log', { method: 'POST', body: { message, stack } }).catch(() => {});
  } catch (e) { /* 日志失败静默 */ }
}

window.addEventListener('resize', () => { try { aiFitHeight(); } catch (e) {} });
window.addEventListener('error', e => reportClientError('JS: ' + e.message, e.error?.stack));
window.addEventListener('unhandledrejection', e => reportClientError('Promise: ' + (e.reason?.message || e.reason)));

/* ================= 外观接口：壁纸 + 桌面宠物 =================
   预留接口：window.WCDesk.setWallpaper(dataUrl)/clearWallpaper()
             window.WCPet.set(on)/isOn()/mount(el)——后续接更完整的宠物组件 */
function applyWallpaper() {
  let wp = null;
  try { wp = localStorage.getItem('wc_wallpaper'); } catch (e) {}
  let layer = document.getElementById('wallpaperLayer');
  if (!wp) { if (layer) layer.remove(); return; }
  if (!layer) {
    layer = document.createElement('div');
    layer.id = 'wallpaperLayer';
    layer.style.cssText = 'position:fixed;inset:0;z-index:0;pointer-events:none;background-size:cover;background-position:center;';
    document.body.insertBefore(layer, document.body.firstChild);
    /* 把静态内容抬到壁纸上层（已定位元素不受影响） */
    for (const el of document.body.children) {
      if (el.id === 'wallpaperLayer') continue;
      const cs = getComputedStyle(el);
      if (cs.position === 'static') { el.style.position = 'relative'; el.style.zIndex = '1'; }
    }
  }
  const dark = document.documentElement.classList.contains('dark');
  const tint = dark ? 'rgba(15,23,42,.88)' : 'rgba(248,250,252,.86)';
  layer.style.backgroundImage = `linear-gradient(${tint}, ${tint}), url("${wp}")`;
}
function wcPickWallpaper() {
  const inp = document.createElement('input');
  inp.type = 'file'; inp.accept = 'image/*';
  inp.onchange = async () => {
    if (!inp.files || !inp.files[0]) return;
    try {
      const dataUrl = await aiDownscaleImage(inp.files[0]);
      localStorage.setItem('wc_wallpaper', dataUrl);
      applyWallpaper();
      toast('壁纸已设置（自动淡化处理，不影响阅读）');
    } catch (e) { toast('设置失败：' + e.message, 'err'); }
  };
  inp.click();
}
function wcClearWallpaper() {
  try { localStorage.removeItem('wc_wallpaper'); } catch (e) {}
  applyWallpaper();
  toast('已恢复默认背景');
}
function initPet() {
  document.getElementById('petWidget')?.remove();
  let on = false;
  try { on = localStorage.getItem('wc_pet') === 'on'; } catch (e) {}
  if (!on) return;
  const el = document.createElement('div');
  el.id = 'petWidget';
  el.style.cssText = 'position:fixed;z-index:80;right:16px;top:72px;font-size:32px;cursor:pointer;user-select:none;filter:drop-shadow(0 3px 8px rgba(0,0,0,.3));transition:transform .2s;';
  el.textContent = '🐱';
  el.title = '喵？点我一下';
  const lines = ['记得看看最近的截止日期哦～', '今天也要加油画画！', '有新比赛就告诉我，我帮你记下来。', '累了就休息一下再肝～', '证书可以拍照发给 AI 助手建档哦！', '喵呜～今天也要元气满满！'];
  el.addEventListener('click', () => {
    el.style.transform = 'scale(1.3) rotate(-8deg)';
    setTimeout(() => el.style.transform = '', 220);
    toast('🐱 ' + lines[Math.floor(Math.random() * lines.length)]);
  });
  document.body.appendChild(el);
}
window.WCDesk = {
  setWallpaper(dataUrl) { try { localStorage.setItem('wc_wallpaper', dataUrl); } catch (e) {} applyWallpaper(); },
  clearWallpaper() { wcClearWallpaper(); },
};
window.WCPet = {
  set(on) { try { localStorage.setItem('wc_pet', on ? 'on' : 'off'); } catch (e) {} initPet(); },
  isOn() { try { return localStorage.getItem('wc_pet') === 'on'; } catch (e) { return false; } },
  mount(el) { if (el && el.nodeType === 1) { document.body.appendChild(el); } },
};
/* 启动时应用 */
try { applyWallpaper(); initPet(); } catch (e) {}
