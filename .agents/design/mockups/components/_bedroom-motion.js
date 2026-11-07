/* Component-mockup helpers for the bedroom-motion batch (not part of the kit; promote to kit candidates are noted in each mockup).
 * Mock.cm: swatches on the page and sheet surfaces (what Mock.componentConfig draws for registered components), small playable motion demos
 * and the CSS they need. Everything uses kit tokens (var(--...)); durations come from Mock.anim.ms (MotionTokens). No raster, no network.
 */
(function () {
  'use strict';
  var h = Mock.h, I = Mock.icon;
  var CM = Mock.cm = {};
  var CSS = [
    '.cm-note{font:12px var(--font);opacity:.7;margin-top:8px}',
    '.cm-row{display:flex;align-items:center;gap:12px;flex-wrap:wrap}',
    '.cm-play{font:600 13px var(--font);min-height:36px;padding:4px 14px;border-radius:999px;border:0;background:var(--g-tint-fill);color:#fff;cursor:pointer}',
    '.cm-play:disabled{opacity:.5}',
    '.cm-track{position:relative;height:36px;border-radius:18px;background:color-mix(in srgb,var(--ink,#fff) 12%,transparent);overflow:hidden;flex:1;min-width:160px}',
    '.cm-ball{position:absolute;left:3px;top:3px;width:30px;height:30px;border-radius:50%;background:var(--g-tint-fill);box-shadow:0 1px 3px rgba(0,0,0,.35)}',
    '.cm-tok{display:grid;grid-template-columns:minmax(150px,200px) 1fr auto;gap:12px;align-items:center;padding:10px 0;border-top:.5px solid var(--sep,rgba(255,255,255,.14))}',
    '.cm-tok:first-child{border-top:0}',
    '.cm-tok code{font:600 13px var(--mono);background:none;padding:0}',
    '.cm-tok .m{font:var(--fs-foot) var(--font);opacity:.75}',
    '@media (max-width:560px){.cm-tok{grid-template-columns:1fr}}',
    '.cm-chip{display:inline-flex;align-items:center;gap:8px;padding:8px 14px;border-radius:999px;font:600 var(--fs-sub) var(--font);background:var(--fill-tertiary);color:var(--ink,#fff);transition:background-color var(--t-state) var(--ease-state),color var(--t-state) var(--ease-state)}',
    '.cm-chip.on{background:var(--g-tint-fill);color:#fff}',
    '.cm-code{font:12px var(--mono);white-space:pre-wrap;opacity:.8}',
    '.cm-tbl{width:100%;border-collapse:collapse;font:var(--fs-foot) var(--font)}',
    '.cm-tbl th,.cm-tbl td{text-align:left;padding:6px 8px;border-bottom:.5px solid var(--sep,rgba(255,255,255,.14));vertical-align:middle}',
    '.cm-tbl th{font-weight:600;opacity:.7;white-space:nowrap}',
    '.cm-tbl code{font:12px var(--mono);background:none;padding:0}',
  ].join('\n');
  var st = document.createElement('style'); st.id = 'cm-css'; st.textContent = CSS; document.head.appendChild(st);

  /** One swatch box: surface 'page' (always dark, over a gradient) or 'sheet' (follows the appearance control). */
  CM.swatch = function (ctx, surface, label, node, note, o) {
    o = o || {};
    var cls = surface === 'page' ? 'page.g-dark' : 'sheet.in-sheet.' + (ctx.appearance === 'dark' ? 'g-dark' : 'g-light');
    var ax = ctx.axSize;   /* at accessibility sizes a fixed-width swatch would be narrower than one word of text: take the row */
    return h('div.k-swatch.' + cls, { style: { width: o.w && !ax ? o.w + 'px' : (ax ? '100%' : ''), flex: ax ? '0 0 100%' : (o.w ? 'none' : '1 1 ' + (o.min || 260) + 'px'), maxWidth: '100%' } },
      h('div.k-cap', surface + ' · ' + label), h('div.in', node), note ? h('div.cm-note', note) : null);
  };
  /** specs: [{label, build(surface) | node, note?, w?, min?}] drawn on each surface in o.surfaces (default both). */
  CM.grid = function (ctx, specs, o) {
    o = o || {};
    var out = h('div', { style: { display: 'flex', flexDirection: 'column', gap: '18px' } });
    (o.surfaces || ['page', 'sheet']).forEach(function (s) {
      var wrap = h('div.k-swatch-grid');
      specs.forEach(function (sp) { wrap.appendChild(CM.swatch(ctx, s, sp.label, typeof sp.build === 'function' ? sp.build(s) : sp.node, sp.note, sp)); });
      out.appendChild(wrap);
    });
    return out;
  };
  /** A DynamicGridLayout column rule in pure CSS: as many columns as fit (floor((w + gap) / (min + gap))), clamped to max, one full-width column when a single
   *  scaled minimum is wider than the container. The kit's TileGrid keeps a track at its minimum and overflows at AX5. Promote to kit. */
  CM.fitGrid = function (g) {
    g.style.gridTemplateColumns = 'repeat(auto-fill, minmax(max(min(100%, calc(var(--min) * var(--sc))), calc((100% - (var(--max) - 1) * var(--gap)) / var(--max))), 1fr))';
    return g;
  };
  /** A grid of cards for a gate or a context: same rule, given min and max. */
  CM.cards = function (nodes, min, max) {
    var g = h('div.ui-grid', { style: { '--min': (min || 150) + 'px', '--max': max || 2, '--gap': '12px' } }, nodes);
    return CM.fitGrid(g);
  };
  /** A Play button that disables itself while its promise runs. */
  CM.play = function (fn, label) {
    var b = h('button.cm-play', { type: 'button' }, label || 'Play');
    b.addEventListener('click', function () { b.disabled = true; Promise.resolve().then(fn).catch(function (e) { if (window.console) console.error(e); }).then(function () { b.disabled = false; }); });
    return b;
  };
  /** Web Animations helper that honours Reduce Motion (the kit's Mock.settings). */
  CM.anim = function (el, frames, opts) {
    if (!el || !el.animate) return Promise.resolve();
    var a = el.animate(frames, Object.assign({ fill: 'both' }, opts)); return a.finished.catch(function () {});
  };
})();
