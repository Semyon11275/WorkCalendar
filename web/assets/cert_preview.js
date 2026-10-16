/* ================= 证书预览图（PC 端，2026-10-17；0.5.0 修订） =================
   为图片类凭证生成 <原名>.preview.jpg（长边 ≤1600px，目标 ~200KB），
   通过 POST /api/certificates 存回 data/certificates/。
   手机经 /api/sync_certificate?preview=1 拉取预览并以独立文件落盘（原名.preview.jpg），
   原件与预览互不覆盖；电脑展示始终用原件。
   命名含完整原名（a.png.preview.jpg），避免 a.png / a.jpg 同挤 a_preview.jpg 冲突。
   触发：上传后即时生成；详情页/获奖页后台补齐（并发限制 2，防内存峰值）。
   幂等：生成前先探测已有预览（跨重启也生效）；失败不标记完成，本会话可重试。 */
(function () {
  'use strict';
  if (window.__wcCertPreview) return;
  const IMG_RE = /\.(jpe?g|png|webp|gif)$/i;
  const done = new Set();      /* 已存在或已生成（成功才入列，失败可重试） */
  const inflight = new Set();
  const MAX_CONCURRENCY = 2;

  function previewName(f) { return f + '.preview.jpg'; }

  function toJpeg(blob, maxEdge, quality) {
    return createImageBitmap(blob).then(function (bmp) {
      const scale = Math.min(1, maxEdge / Math.max(bmp.width, bmp.height));
      const c = document.createElement('canvas');
      c.width = Math.max(1, Math.round(bmp.width * scale));
      c.height = Math.max(1, Math.round(bmp.height * scale));
      const ctx = c.getContext('2d');
      ctx.fillStyle = '#fff';  /* JPEG 无透明通道，铺白底 */
      ctx.fillRect(0, 0, c.width, c.height);
      ctx.drawImage(bmp, 0, 0, c.width, c.height);
      try { bmp.close && bmp.close(); } catch (e) {}
      return new Promise(function (res, rej) {
        c.toBlob(function (b) { b ? res(b) : rej(new Error('转码失败')); }, 'image/jpeg', quality);
      });
    });
  }

  function blobToB64(blob) {
    return blob.arrayBuffer().then(function (buf) {
      const u8 = new Uint8Array(buf);
      let bin = '';
      for (let i = 0; i < u8.length; i += 32768) bin += String.fromCharCode.apply(null, u8.subarray(i, i + 32768));
      return btoa(bin);
    });
  }

  /* 用内存中的 File/Blob 直接生成（上传后即时调用，省一次回读） */
  async function generateFromFile(fname, file) {
    if (!IMG_RE.test(fname) || file.size <= 250 * 1024) return false;
    try {
      let blob = await toJpeg(file, 1600, 0.8);
      for (const step of [[1600, .72], [1280, .65], [1024, .55]]) {
        if (blob.size <= 230 * 1024) break;
        blob = await toJpeg(file, step[0], step[1]);
      }
      if (blob.size >= file.size) return false;  /* 压不动（本就紧凑），不生成 */
      const r = await api('/api/certificates', { method: 'POST', body: { name: previewName(fname), data: await blobToB64(blob) } });
      return !!r.ok;
    } catch (e) { return false; }
  }

  /* 后台补生成（详情页/获奖页调用）；返回是否新生成了预览。
     幂等：先探测已有预览（200 → 直接标记完成，跨重启有效）；
     失败不标记完成——本会话再次触发可重试。 */
  async function ensure(fname) {
    if (!IMG_RE.test(fname) || done.has(fname) || inflight.has(fname)) return false;
    inflight.add(fname);
    try {
      try {
        const probe = await fetch('/certificates/' + encodeURIComponent(previewName(fname)), { credentials: 'same-origin' });
        if (probe.ok) { done.add(fname); return false; }  /* 已有预览 */
      } catch (e) { /* 探测失败按无预览处理，走生成 */ }
      const resp = await fetch('/certificates/' + encodeURIComponent(fname), { credentials: 'same-origin' });
      if (!resp.ok) return false;  /* 原件缺失：不标记完成，留待重试 */
      const orig = await resp.blob();
      const made = await generateFromFile(fname, orig);
      if (made) done.add(fname);
      return made;
    } catch (e) {
      return false;  /* 失败可重试 */
    } finally {
      inflight.delete(fname);
    }
  }

  /* 全局共享队列：所有入口（获奖页批量、详情页、设置页按钮）共用一组 worker，
     并发上限是全局的 MAX_CONCURRENCY——同时触发多个批次也不会叠加 */
  const queue = [];
  const queued = new Set();
  let active = 0, batchMade = 0;
  function pump() {
    while (active < MAX_CONCURRENCY && queue.length) {
      const f = queue.shift();
      queued.delete(f);
      active++;
      ensure(f).then(function (ok) {
        if (ok) batchMade++;
      }).finally(function () {
        active--;
        if (active === 0 && queue.length === 0) {
          /* 整体空闲：汇报本轮生成数量并复位计数 */
          if (batchMade && typeof window.toast === 'function') {
            toast('已生成 ' + batchMade + ' 张压缩预览图，手机同步更省流量');
          }
          batchMade = 0;
        } else {
          pump();
        }
      });
    }
  }
  function ensureAll(fnames) {
    (fnames || []).forEach(function (f) {
      if (IMG_RE.test(f) && !done.has(f) && !inflight.has(f) && !queued.has(f)) {
        queued.add(f);
        queue.push(f);
      }
    });
    pump();
  }

  /* 待生成数量（done/inflight 之外的图片凭证）——设置页按钮用于判断是否已全部就绪 */
  function pending(fnames) {
    return (fnames || []).filter(function (f) { return IMG_RE.test(f) && !done.has(f) && !inflight.has(f); }).length;
  }

  window.__wcCertPreview = true;
  window.wcCertPreview = { previewName: previewName, generateFromFile: generateFromFile, ensure: ensure, ensureAll: ensureAll, pending: pending };
})();
