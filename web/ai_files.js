/* ================= AI 附件：图片 + 表格文件（CSV/Excel/JSON/文本） =================
   桌面/安卓共用。表格解析为文本后作为消息上下文发给 AI，
   AI 按来源要求规范逐行整理并调用 add_competition / add_award 录入。 */
const AI_TABLE_RE = /\.(csv|tsv|txt|md|json|xlsx|xls)$/i;
const AI_IMAGE_RE = /\.(png|jpe?g|webp|gif)$/i;
function aiIsTableFile(f) { return AI_TABLE_RE.test(f.name || ''); }
function aiIsImageFile(f) { return AI_IMAGE_RE.test(f.name || ''); }

/* xlsx/xls → JSON 行数组（依赖 assets/xlsx.full.min.js） */
function aiParseExcel(file) {
  return new Promise((resolve, reject) => {
    if (typeof XLSX === 'undefined') { reject(new Error('Excel 解析库未加载')); return; }
    const reader = new FileReader();
    reader.onerror = () => reject(new Error('读取失败'));
    reader.onload = () => {
      try {
        const wb = XLSX.read(reader.result, { type: 'array' });
        const sheets = {};
        for (const sn of wb.SheetNames) sheets[sn] = XLSX.utils.sheet_to_json(wb.Sheets[sn], { defval: '' });
        resolve(sheets);
      } catch (e) { reject(e); }
    };
    reader.readAsArrayBuffer(file);
  });
}

/* 表格文件 → 文本（JSON 行集），供 AI 整理 */
async function aiReadTableFile(file) {
  const name = file.name || '表格';
  if (/xlsx|xls$/i.test(name)) {
    const sheets = await aiParseExcel(file);
    let out = '';
    for (const sn of Object.keys(sheets)) {
      out += '\n【工作表 ' + sn + '】\n' + JSON.stringify(sheets[sn]);
    }
    return { kind: 'table', name, text: out.slice(0, 60000) || '(空表)' };
  }
  const text = (await file.text()).slice(0, 60000);
  return { kind: 'table', name, text };
}

/* 统一入口：按类型读取用户选择的文件 → 附件对象 */
async function aiMakeAttachment(file) {
  if (file.size > 10 * 1024 * 1024) throw new Error('附件不能超过 10MB');
  if (aiIsImageFile(file)) {
    return { kind: 'image', name: file.name, dataUrl: await aiDownscaleImage(file) };
  }
  if (aiIsTableFile(file)) {
    const t = await aiReadTableFile(file);
    return { kind: 'table', name: file.name, text: t.text };
  }
  throw new Error('不支持的文件类型（支持图片与 CSV/TSV/TXT/MD/JSON/Excel 表格）');
}
