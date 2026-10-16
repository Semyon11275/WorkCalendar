/* ================= 证书预览图（PC 端，2026-10-17） =================
   为图片类凭证生成 <原名>_preview.jpg（长边 ≤1600px，目标 ~200KB），
   通过 POST /api/certificates 存回 data/certificates/。
   手机同步（core.js syncCertificates）优先取预览图、以原名落盘——
   传输量从每张数 MB 降到 ~200KB；原件保留在电脑上作为存档。
   触发点：award 上传后立即生成；详情页展示图片凭证时后台补生成。
   PDF 无法前端压缩，不做预览（手机回退原件）。 */
(function () {
  'use strict';
  if (window.__wcCertPreview) return;
  const IMG_RE = /\.(jpe?g|png|webp|gif)$/i;
  const done = new Set();      /* 本会话已处理（成功/确认无需） */
  const inflight = new Set();

  function previewName(f) { return f.replace(/(\.[^.]+)$/, '_preview.jpg'); }

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

  /* 后台补生成（详情页展示时逐个调用）；返回是否新生成了预览 */
  async function ensure(fname) {
    if (!IMG_RE.test(fname) || done.has(fname) || inflight.has(fname)) return false;
    inflight.add(fname);
    try {
      const resp = await fetch('/certificates/' + encodeURIComponent(fname), { credentials: 'same-origin' });
      if (!resp.ok) { done.add(fname); return false; }
      const orig = await resp.blob();
      const made = await generateFromFile(fname, orig);
      done.add(fname);
      return made;
    } catch (e) {
      done.add(fname);
      return false;
    } finally {
      inflight.delete(fname);
    }
  }

  /* 批量后台生成：完成后统一 toast 一次 */
  function ensureAll(fnames) {
    let made = 0, left = 0;
    (fnames || []).filter(IMG_RE.test.bind(IMG_RE)).forEach(function (f) {
      left++;
      ensure(f).then(function (ok) {
        if (ok) made++;
        if (--left === 0 && made && typeof window.toast === 'function') {
          toast('已生成 ' + made + ' 张压缩预览图，手机同步更省流量');
        }
      });
    });
  }

  /* 待生成数量（done/inflight 之外的图片凭证）——设置页按钮用于判断是否已全部就绪 */
  function pending(fnames) {
    return (fnames || []).filter(function (f) { return IMG_RE.test(f) && !done.has(f) && !inflight.has(f); }).length;
  }

  window.__wcCertPreview = true;
  window.wcCertPreview = { previewName: previewName, generateFromFile: generateFromFile, ensure: ensure, ensureAll: ensureAll, pending: pending };
})();
