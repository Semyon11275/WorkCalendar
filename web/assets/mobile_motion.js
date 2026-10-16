/* Mobile adaptation: tab reveal, touch feedback and detail content reveal. */
(() => {
  'use strict';
  if (window.__wcMobileMotion) return;
  window.__wcMobileMotion = true;
  const media = window.matchMedia('(prefers-reduced-motion: reduce)');
  const reduced = () => media.matches || document.body.classList.contains('motion-reduced');
  const active = new Set();
  function play(el, frames, options) {
    if (!el || !el.animate || reduced()) return null;
    const a = el.animate(frames, options);
    active.add(a);
    a.finished.catch(() => {}).then(() => active.delete(a));
    return a;
  }
  function cancelAll() { active.forEach(a => a.cancel()); active.clear(); }
  media.addEventListener?.('change', () => { if (reduced()) cancelAll(); });
  new MutationObserver(() => { if (reduced()) cancelAll(); })
    .observe(document.body, {attributes:true, attributeFilter:['class']});
  let tabAnimation;
  const originalGo = window.go;
  if (typeof originalGo === 'function') window.go = function(view) {
    const prev = document.querySelector('.tabbar-item.active')?.dataset.view;
    tabAnimation?.cancel();
    const result = originalGo.apply(this, arguments);
    if (prev === view) return result;
    const order = [...document.querySelectorAll('.tabbar-item')].map(n => n.dataset.view);
    const direction = order.indexOf(view) >= order.indexOf(prev) ? 1 : -1;
    // Animate the incoming page only: no duplicated forms, IDs or stale snapshots.
    tabAnimation = play(document.getElementById('view-' + view), [
      {clipPath: direction > 0 ? 'polygon(0 0,0 0,-35% 100%,0 100%)' : 'polygon(100% 0,100% 0,135% 100%,100% 100%)', transform:`translate(${direction * 16}px,6px)`,opacity:.45},
      {clipPath:direction > 0 ? 'polygon(0 0,135% 0,100% 100%,0 100%)' : 'polygon(100% 0,-35% 0,0 100%,100% 100%)',transform:'none',opacity:1}
    ], {duration:360,easing:'cubic-bezier(.18,.72,.18,1)'});
    return result;
  };
  const presses = new WeakMap();
  document.addEventListener('click', e => {
    const el = e.target.closest?.('button,.tabbar-item,.card[onclick]');
    if (!el || el.disabled || el.offsetParent === null) return;
    presses.get(el)?.cancel();
    const a = play(el,[{transform:'scale(.97)'},{transform:'scale(1.015)',offset:.65},{transform:'none'}],
      {duration:220,easing:'cubic-bezier(.2,.8,.2,1)'});
    if(a) presses.set(el,a);
  });
  for (const [pageId, bodyId] of [['detailPage','detailBody'],['awardDetailPage','awardDetailBody']]) {
    const page=document.getElementById(pageId), body=document.getElementById(bodyId);
    if(!page || !body) continue;
    let animations=[];
    new MutationObserver(() => {
      animations.forEach(a=>a.cancel()); animations=[];
      if(page.classList.contains('hidden') || reduced()) return;
      const header=body.firstElementChild;
      const blocks=[...(header?.querySelectorAll('h2') || []),...(body.children[1]?.children || [])];
      blocks.filter(n=>getComputedStyle(n).position!=='fixed').slice(0,8).forEach((el,i)=>{
        const a=play(el,[{opacity:0,transform:'translateY(8px)',clipPath:'inset(0 0 100% 0)'},
          {opacity:1,transform:'none',clipPath:'inset(0 0 0 0)'}],
          {duration:260,delay:Math.min(i*35,175),fill:'backwards',easing:'cubic-bezier(.215,.61,.355,1)'});
        if(a) animations.push(a);
      });
    }).observe(page,{attributes:true,attributeFilter:['class']});
  }
  document.addEventListener('visibilitychange',()=>{if(document.hidden)cancelAll();});
})();
