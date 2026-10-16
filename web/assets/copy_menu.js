/* ================= PC 右键/快捷键复制支持 =================
   背景：桌面版 WebView2 在非 debug 模式下禁用了原生右键菜单
   （pywebview EdgeChromium: AreDefaultContextMenusEnabled = debug），
   导致图片、文字都无法直接复制。
   这里补一个自定义右键菜单 + Ctrl+C/Ctrl+A 兜底：
   - 图片：复制为位图（可直接粘贴到微信/文档），或复制图片地址
   - 图表（canvas）：复制为 PNG
   - 文字：选中后右键或 Ctrl+C 复制；Ctrl+A 全选
   - 链接：复制链接地址
   注意：文件放在 assets/ 下是因为后端静态白名单只放行
   /assets/ 前缀与 core.js 等既有文件，旧版 exe 无需重打包即可加载。 */
(function () {
  'use strict';
  if (window.__wcCopyMenuReady) return;
  window.__wcCopyMenuReady = true;

  var curMenu = null;

  function ensureStyle() {
    if (document.getElementById('wcCopyMenuStyle')) return;
    var st = document.createElement('style');
    st.id = 'wcCopyMenuStyle';
    st.textContent = [
      '.wcmenu{position:fixed;z-index:2147483000;min-width:190px;max-width:340px;padding:6px;margin:0;',
      'background:#fff;border:1px solid #e2e8f0;border-radius:14px;box-shadow:0 10px 34px rgba(15,23,42,.24);',
      'font-size:13px;line-height:1.4;color:#334155;user-select:none;animation:wcmenu-in .12s ease-out;}',
      '.dark .wcmenu,.wcmenu-dark{background:#1e293b;border-color:#334155;color:#cbd5e1;box-shadow:0 10px 34px rgba(0,0,0,.5);}',
      '@keyframes wcmenu-in{from{opacity:0;transform:translateY(-4px) scale(.98)}to{opacity:1;transform:none}}',
      '.wcmenu-item{display:flex;align-items:center;gap:8px;padding:7px 10px;border-radius:9px;cursor:pointer;}',
      '.wcmenu-item:hover{background:#f1f5f9;color:#0f172a;}',
      '.dark .wcmenu-item:hover{background:#334155;color:#f8fafc;}',
      '.wcmenu-item .wcmenu-sub{margin-left:auto;padding-left:16px;font-size:11px;color:#94a3b8;max-width:180px;',
      'overflow:hidden;text-overflow:ellipsis;white-space:nowrap;}',
      '.wcmenu-sep{height:1px;margin:5px 8px;background:#e2e8f0;}.dark .wcmenu-sep{background:#334155;}'
    ].join('');
    document.head.appendChild(st);
  }

  function toastWrap(msg, type) {
    if (typeof window.toast === 'function') { window.toast(msg, type || 'ok'); return; }
    console.log('[copy]', msg, type || '');
  }

  function isEditable(el) {
    return !!(el && (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA' || el.isContentEditable));
  }

  function selectionText() {
    try { var s = window.getSelection(); return s ? String(s) : ''; } catch (e) { return ''; }
  }

  function shortUrl(u) {
    var s = String(u).replace(/^https?:\/\//, '');
    return s.length > 26 ? s.slice(0, 26) + '…' : s;
  }

  /* ---------- 复制动作 ---------- */

  function copyTextRaw(text) {
    var t = String(text);
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(t)
        .then(function () { toastWrap('已复制'); })
        .catch(function () { legacyCopyText(t); });
    } else {
      legacyCopyText(t);
    }
  }

  /* 老环境兜底：隐藏 textarea + execCommand */
  function legacyCopyText(t) {
    try {
      var ta = document.createElement('textarea');
      ta.value = t;
      ta.style.cssText = 'position:fixed;left:-9999px;top:0;opacity:0;';
      document.body.appendChild(ta);
      ta.focus(); ta.select();
      var ok = document.execCommand('copy');
      ta.remove();
      toastWrap(ok ? '已复制' : '复制失败', ok ? 'ok' : 'err');
    } catch (e) {
      toastWrap('复制失败：' + (e && e.message || e), 'err');
    }
  }

  /* 任意来源 → PNG Blob（剪贴板位图只接受 image/png） */
  function imageToPng(src, imgEl) {
    return fetch(src, { mode: 'cors' })
      .then(function (r) {
        if (!r.ok) throw new Error('HTTP ' + r.status);
        return r.blob();
      })
      .catch(function () {
        /* 跨域图片 fetch 不到时，退回用页面上已加载的 <img> 画布导出；
           跨域且无 CORS 头的图会因画布污染失败——这类图只能复制地址。 */
        return blobFromImg(imgEl);
      })
      .then(function (blob) {
        if (!blob) throw new Error('无法读取图片');
        if (blob.type === 'image/png') return blob;
        return blobToPng(blob);
      });
  }

  function blobFromImg(imgEl) {
    if (!imgEl || !imgEl.complete || !imgEl.naturalWidth) return Promise.reject(new Error('图片尚未加载完成'));
    return new Promise(function (res, rej) {
      try {
        var c = document.createElement('canvas');
        c.width = imgEl.naturalWidth;
        c.height = imgEl.naturalHeight;
        c.getContext('2d').drawImage(imgEl, 0, 0);
        c.toBlob(function (b) { b ? res(b) : rej(new Error('画布导出失败')); }, 'image/png');
      } catch (e) { rej(e); }
    });
  }

  function blobToPng(blob) {
    return createImageBitmap(blob).then(function (bmp) {
      var c = document.createElement('canvas');
      c.width = bmp.width;
      c.height = bmp.height;
      var ctx = c.getContext('2d');
      /* JPEG 无透明通道：铺白底，避免透明区域渲染成黑色 */
      if (blob.type === 'image/jpeg') { ctx.fillStyle = '#fff'; ctx.fillRect(0, 0, c.width, c.height); }
      ctx.drawImage(bmp, 0, 0);
      return new Promise(function (res, rej) {
        c.toBlob(function (b) { b ? res(b) : rej(new Error('图片转码失败')); }, 'image/png');
      });
    });
  }

  function copyImage(src, imgEl) {
    if (!(navigator.clipboard && window.ClipboardItem)) {
      toastWrap('当前环境不支持复制图片位图，可复制图片地址', 'warn');
      return;
    }
    var png = imageToPng(src, imgEl);
    var job = null;
    try {
      /* 把 Promise 直接传给 ClipboardItem：在用户手势内发起写入，
         图片解码完成前不会丢手势（Chromium 97+ / WebView2 均支持） */
      job = navigator.clipboard.write([new ClipboardItem({ 'image/png': png })]);
    } catch (e) {
      job = png.then(function (blob) {
        return navigator.clipboard.write([new ClipboardItem({ 'image/png': blob })]);
      });
    }
    job.then(
      function () { toastWrap('图片已复制，可直接粘贴'); },
      function (err) {
        toastWrap('复制图片失败' + (err && err.message ? '：' + err.message : '') + '（跨域图片可改用“复制图片地址”）', 'err');
      });
  }

  function copyCanvas(canvas) {
    if (!(navigator.clipboard && window.ClipboardItem)) { toastWrap('当前环境不支持复制图表', 'warn'); return; }
    var png = new Promise(function (res, rej) {
      try {
        canvas.toBlob(function (b) { b ? res(b) : rej(new Error('图表导出失败')); }, 'image/png');
      } catch (e) { rej(e); }
    });
    var job = null;
    try {
      job = navigator.clipboard.write([new ClipboardItem({ 'image/png': png })]);
    } catch (e) {
      job = png.then(function (blob) { return navigator.clipboard.write([new ClipboardItem({ 'image/png': blob })]); });
    }
    job.then(
      function () { toastWrap('图表已复制为图片，可直接粘贴'); },
      function (err) { toastWrap('复制图表失败' + (err && err.message ? '：' + err.message : ''), 'err'); });
  }

  function selectAllBody() {
    var sel = window.getSelection();
    sel.removeAllRanges();
    var range = document.createRange();
    range.selectNodeContents(document.body);
    sel.addRange(range);
    toastWrap('已全选文字，Ctrl+C 或右键复制');
  }

  /* ---------- 菜单 UI ---------- */

  function hideMenu() {
    if (curMenu) { curMenu.remove(); curMenu = null; }
  }

  function showMenu(x, y, items) {
    ensureStyle();
    hideMenu();
    var m = document.createElement('div');
    m.className = 'wcmenu';
    items.forEach(function (it) {
      if (it === 'sep') {
        var s = document.createElement('div');
        s.className = 'wcmenu-sep';
        m.appendChild(s);
        return;
      }
      var d = document.createElement('div');
      d.className = 'wcmenu-item';
      var ic = document.createElement('span');
      ic.textContent = it.icon || '';
      var lb = document.createElement('span');
      lb.textContent = it.label;
      d.appendChild(ic);
      d.appendChild(lb);
      if (it.sub) {
        var sub = document.createElement('span');
        sub.className = 'wcmenu-sub';
        sub.textContent = it.sub;
        d.appendChild(sub);
      }
      d.addEventListener('click', function (ev) {
        ev.stopPropagation();
        ev.preventDefault();
        hideMenu();
        try { it.act(); } catch (e) { toastWrap('操作失败：' + (e && e.message || e), 'err'); }
      });
      m.appendChild(d);
    });
    document.body.appendChild(m);
    var r = m.getBoundingClientRect();
    m.style.left = Math.max(8, Math.min(x, window.innerWidth - r.width - 8)) + 'px';
    m.style.top = Math.max(8, Math.min(y, window.innerHeight - r.height - 8)) + 'px';
    curMenu = m;
  }

  /* ---------- 事件 ---------- */

  document.addEventListener('contextmenu', function (e) {
    hideMenu();
    if (e.defaultPrevented) return;
    var target = e.target;
    if (!target || !target.closest) return;
    var img = target.closest('img');
    var canvas = target.closest('canvas');
    var link = target.closest('a[href]');
    var sel = selectionText();
    var items = [];

    if (img) {
      var url = img.currentSrc || img.src || '';
      if (url) {
        items.push({ icon: '🖼️', label: '复制图片', act: function () { copyImage(url, img); } });
        if (url.indexOf('data:') !== 0) {
          items.push({ icon: '🔗', label: '复制图片地址', sub: shortUrl(url), act: function () { copyTextRaw(url); } });
        }
      }
    } else if (canvas) {
      items.push({ icon: '📊', label: '复制图表为图片', act: function () { copyCanvas(canvas); } });
    }
    if (link && link.href && link.href.indexOf('javascript:') !== 0) {
      if (items.length) items.push('sep');
      items.push({ icon: '🔗', label: '复制链接', sub: shortUrl(link.href), act: function () { copyTextRaw(link.href); } });
    }
    if (sel && sel.trim()) {
      if (items.length) items.push('sep');
      var preview = sel.trim().slice(0, 16);
      items.push({ icon: '📋', label: '复制文字', sub: sel.trim().length > 16 ? preview + '…' : preview, act: function () { copyTextRaw(sel); } });
    }
    var ae = null;
    for (var n = target; n && n !== document.body; n = n.parentElement) {
      if (isEditable(n)) { ae = n; break; }
    }
    if (ae && ae.value) {
      if (items.length) items.push('sep');
      var pv = String(ae.value).slice(0, 16);
      items.push({ icon: '📋', label: '复制输入内容', sub: String(ae.value).length > 16 ? pv + '…' : pv, act: function () { copyTextRaw(ae.value); } });
      items.push({ icon: '↔️', label: '全选输入', act: function () { ae.focus(); ae.select(); } });
    } else if (!items.length && !img && !canvas) {
      items.push({ icon: '↔️', label: '全选页面文字', act: selectAllBody });
    }

    if (!items.length) return;
    e.preventDefault();
    showMenu(e.clientX, e.clientY, items);
  }, false);

  /* WebView2 禁用浏览器加速键后，Ctrl+C/Ctrl+A 在部分环境下失效，这里补齐；
     输入框内的按键交给原生行为，避免干扰编辑。 */
  document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape') { hideMenu(); return; }
    var mod = e.ctrlKey || e.metaKey;
    if (!mod || e.altKey) return;
    var k = (e.key || '').toLowerCase();
    if (isEditable(document.activeElement)) return;
    if (k === 'a') {
      e.preventDefault();
      selectAllBody();
    } else if (k === 'c') {
      var t = selectionText();
      if (t) { e.preventDefault(); copyTextRaw(t); }
    }
  }, false);

  document.addEventListener('mousedown', function (e) {
    if (curMenu && !curMenu.contains(e.target)) hideMenu();
  }, true);
  window.addEventListener('blur', hideMenu);
  window.addEventListener('resize', hideMenu);
  window.addEventListener('scroll', hideMenu, true);
})();
