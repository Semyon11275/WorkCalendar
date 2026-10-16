const fs = require('fs'), vm = require('vm'), assert = require('assert'), path = require('path');
const html = fs.readFileSync(path.join(__dirname, '../web/index.html'), 'utf8');
const fn = html.match(/function wcBufToB64\(buf\) \{[\s\S]*?\n\}/);
assert(fn, 'Upload encoder must exist');
const context = { Uint8Array, String, btoa: s => Buffer.from(s, 'binary').toString('base64') };
vm.createContext(context); vm.runInContext(fn[0], context);
const bytes = new Uint8Array(3 * 1024 * 1024); for (let i = 0; i < bytes.length; i++) bytes[i] = i % 256;
assert.equal(context.wcBufToB64(bytes.buffer), Buffer.from(bytes).toString('base64'));
console.log('PASS 3 MiB attachment encoding preserves every byte');
let active = 0, peak = 0, completed = 0;
const preview = { window: {}, console, fetch: async url => {
  if (url.endsWith('.preview.jpg')) return { ok: false };
  active++; peak = Math.max(peak, active);
  await new Promise(resolve => setTimeout(resolve, 5));
  active--; completed++;
  return { ok: true, blob: async () => ({ size: 1 }) };
} };
vm.createContext(preview);
vm.runInContext(fs.readFileSync(path.join(__dirname, '../web/assets/cert_preview.js'), 'utf8'), preview);
preview.window.wcCertPreview.ensureAll(['a.png', 'b.png', 'c.png']);
preview.window.wcCertPreview.ensureAll(['d.png', 'e.png', 'f.png']);
(async () => {
  const end = Date.now() + 5000;
  while (completed < 6 && Date.now() < end) await new Promise(resolve => setTimeout(resolve, 10));
  assert.equal(completed, 6, 'Both batches must drain'); assert.equal(active, 0);
  assert.equal(peak, 2, 'All batches share the same concurrency limit');
  console.log('PASS overlapping preview batches drain with global concurrency 2');
})().catch(e => { console.error(e); process.exitCode = 1; });
