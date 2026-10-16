/* ================= 动效包（移植自「今天吃啥」动效独立包 2026-10-16） =================
   移植了适合桌面侧边栏结构的三组效果，参数与曲线保持原包一致：
   1. 视图切换：斜边揭示（dock-motion.js）
      新页 clip-path 斜多边形揭示 + -24×方向/12px 位移，旧页快照 +10×方向/-4px，
      420ms cubic-bezier(.18,.72,.18,1)；斜边宽 min(180px, 46%)。
   2. 点击弹性反馈（motion.js）
      命中元素 scale .93 → 1.045 → 1，280ms cubic-bezier(.2,.8,.2,1)。
   3. 详情抽屉文字刷出（detail-motion.js）
      打开抽屉后内容块错峰揭示：标题横向遮罩、正文纵向遮罩，总时间轴 420ms。
   降级：系统 prefers-reduced-motion 或 body.motion-reduced 时全部跳过（原包同款开关）。
   未移植：菜单架/封面 WebGL 飞行/玻璃折射（依赖手机端 shelf/tabbar/封面结构，本应用无对应物）。 */
(function () {
  'use strict';
  if (window.__wcMotionPackReady) return;
  window.__wcMotionPackReady = true;

  var reduced = function () {
    return document.body.classList.contains('motion-reduced') ||
      (window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches);
  };

  /* ---------- 样式 ---------- */
  var st = document.createElement('style');
  st.id = 'wcMotionStyle';
  st.textContent = [
    '#mainArea{position:relative;}',
    '.wc-page-snapshot{position:absolute;left:0;right:0;z-index:45;pointer-events:none;overflow:hidden;box-sizing:border-box;}',
    '.wc-view-incoming{position:relative;z-index:46;}'
  ].join('');
  (document.head || document.documentElement).appendChild(st);

  /* ---------- 1. 视图切换：斜向揭示 ---------- */
  var activeAnims = [], activeSnapshot = null, activeTarget = null;
  function installViewTransition() {
    if (typeof window.go !== 'function' || window.go.__wcWrapped) return;
    var original = window.go;
    var wrapped = function (view) {
      var host = document.getElementById('mainArea');
      var views = Array.from(document.querySelectorAll('.view'));
      var prev = views.find(function (v) { return !v.classList.contains('hidden'); });
      var target = document.getElementById('view-' + view);
      var navOrder = Array.from(document.querySelectorAll('.nav-item')).map(function (n) { return n.dataset.view; });
      original(view);
      if (!host || !target || !prev || prev === target || prev.id === target.id) return;
      if (reduced() || !target.animate) return;
      var direction = navOrder.indexOf(view) > navOrder.indexOf(prev.id.replace('view-', '')) ? 1 : -1;

      /* 中断处理（原包 dock-motion：新切换前取消进行中的动画并移除旧快照）——
         快速连点不堆叠动画，一次点击只播一次切换；也避免旧清理回调误删新视图层级 */
      activeAnims.forEach(function (a) { try { a.cancel(); } catch (e) {} });
      activeAnims = [];
      if (activeSnapshot) { activeSnapshot.remove(); activeSnapshot = null; }
      if (activeTarget && activeTarget !== target) { activeTarget.classList.remove('wc-view-incoming'); }
      activeTarget = target;

      /* 旧页快照：放在 mainArea 内（同一层叠上下文），避免盖住侧栏 */
      var rect = prev.getBoundingClientRect(), hostRect = host.getBoundingClientRect();
      var snapshot = prev.cloneNode(true);
      snapshot.removeAttribute('id');
      snapshot.querySelectorAll('[id]').forEach(function (n) { n.removeAttribute('id'); });
      snapshot.classList.remove('hidden', 'anim-in');
      snapshot.classList.add('wc-page-snapshot');
      snapshot.inert = true;
      snapshot.setAttribute('aria-hidden', 'true');
      Object.assign(snapshot.style, {
        top: (rect.top - hostRect.top + host.scrollTop) + 'px',
        height: Math.min(rect.height, host.clientHeight) + 'px'
      });
      host.appendChild(snapshot);
      activeSnapshot = snapshot;

      /* 新页：去掉默认 fadeUp，改用斜边揭示（原包 dock-motion 参数） */
      target.classList.remove('anim-in');
      target.classList.add('wc-view-incoming');
      var width = target.clientWidth || 1;
      var slant = Math.min(180, width * 0.46) / width * 100;
      var polygon = function (p) {
        var edge = (100 + slant) * p;
        var x = function (v) { return direction > 0 ? v : 100 - v; };
        return 'polygon(' + x(0) + '% 0,' + x(edge) + '% 0,' + x(edge - slant) + '% 100%,' + x(0) + '% 100%)';
      };
      var incoming = target.animate(
        [{ clipPath: polygon(0), transform: 'translate(' + (-24 * direction) + 'px,12px)' },
         { clipPath: polygon(1), transform: 'none' }],
        { duration: 420, easing: 'cubic-bezier(.18,.72,.18,1)' });
      var outgoing = snapshot.animate(
        [{ transform: 'none' }, { transform: 'translate(' + (10 * direction) + 'px,-4px)' }],
        { duration: 420, easing: 'cubic-bezier(.18,.72,.18,1)' });
      activeAnims = [incoming, outgoing];
      incoming.finished.catch(function () {}).then(function () {
        snapshot.remove();
        /* 只有仍是当前动画时才摘层级，被中断的新一轮切换不受影响 */
        if (activeAnims[0] === incoming) {
          target.classList.remove('wc-view-incoming');
          activeTarget = null;
        }
      });
      outgoing.finished.catch(function () {});
    };
    wrapped.__wcWrapped = true;
    window.go = wrapped;
  }
  if (typeof window.go === 'function') installViewTransition();
  else document.addEventListener('DOMContentLoaded', installViewTransition);

  /* ---------- 2. 点击弹性反馈 ---------- */
  document.addEventListener('click', function (e) {
    if (reduced()) return;
    var el = e.target.closest ? e.target.closest('.nav-item, .btn, .card[class*="cursor-pointer"]') : null;
    if (!el || !el.animate) return;
    requestAnimationFrame(function () {
      /* 只动当前可见的那一个（同名按钮多处时） */
      if (el.offsetParent === null) return;
      el.animate(
        [{ transform: 'scale(.93)' }, { transform: 'scale(1.045)', offset: .6 }, { transform: 'scale(1)' }],
        { duration: 280, easing: 'cubic-bezier(.2,.8,.2,1)' });
    });
  }, false);

  /* ---------- 3. 详情抽屉文字刷出 ---------- */
  /* 抽屉 #drawer 由 openDetail / viewAwardDetail 打开（移除 hidden）。
     这里观察 class 变化，对抽屉内容块按原包 detail-motion 的时间轴错峰揭示：
     前两块（渐变头 + 标题）横向遮罩，其余纵向遮罩，420ms 总时间轴。 */
  function revealDrawer() {
    var panel = document.getElementById('drawerPanel');
    if (!panel || reduced() || !panel.animate) return;
    var header = panel.children[0];
    var blocks = header ? [header] : [];
    var body = panel.children[1];
    if (body) Array.prototype.push.apply(blocks, Array.from(body.children));
    blocks.forEach(function (n, i) {
      var horizontal = i < 2;
      /* 原包节奏：begin 0 / .09 / .18 / .27…（步进 .09，封顶 .43），end 与 begin 拉开 ≥ .3 */
      var begin = Math.min(.43, i * .09);
      var end = Math.min(1, begin + (horizontal ? .46 : .33));
      var frames = horizontal
        ? [{ clipPath: 'inset(0 100% 0 0)', transform: 'translateX(-10px)' },
           { clipPath: 'inset(0 0 0 0)', transform: 'none' }]
        : [{ clipPath: 'inset(0 0 100% 0)', transform: 'translate(-8px,-6px)' },
           { clipPath: 'inset(0 0 0 0)', transform: 'none' }];
      n.animate(frames, {
        duration: (end - begin) * 420,
        delay: begin * 420,
        easing: 'cubic-bezier(.215,.61,.355,1)'
      });
    });
  }
  function installDrawerReveal() {
    var drawer = document.getElementById('drawer');
    if (!drawer || drawer.__wcRevealBound) return;
    drawer.__wcRevealBound = true;
    new MutationObserver(function () {
      if (!drawer.classList.contains('hidden')) revealDrawer();
    }).observe(drawer, { attributes: true, attributeFilter: ['class'] });
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', installDrawerReveal);
  else installDrawerReveal();
})();
