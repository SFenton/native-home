/* Local helper for the selection-tiles proposal (promote to kit if the owner picks an option): tiles that CHOOSE rather than act, drawn four ways.
 * Reuses the action-tiles helper (Mock.at: grid, section, page, TileActionButton disc) and the kit's GlassTile and Toggle.
 *   A  check disc      : text . disc, disc = checkmark.circle.fill (selected) / circle (not); a number replaces the tick for ordered multi-select
 *   B1 toggle disc     : the Power disc (white when on) carrying the item's own glyph; the tile fills; an order number is a corner badge
 *   B2 system switch   : a real Toggle trailing on the tile; the order number can only go in the text
 *   C  selected face   : the tile fills in the family colour when selected, white check disc; an unselected tile is the plain off face with a circle
 * Everything is a STAND-IN for SwiftUI: the indicator is a Image(systemName:) / numbered symbol in a 44 pt hit target; B1 reuses TileActionButtonStyle; B2 is Toggle.
 */
(function () {
  var h = Mock.h, I = Mock.icon, AT = Mock.at, SEL = Mock.sel = {};
  function K() { return Mock.components; }

  var css = [
    '.sl-ind { --d: calc(44px * min(var(--sc, 1), 1.5)); width: var(--d); height: var(--d); display: grid; place-items: center; flex: none; position: relative; }',
    '.sl-c { --c: calc(28px * min(var(--sc, 1), 1.5)); width: var(--c); height: var(--c); border-radius: 50%; box-sizing: border-box; display: grid; place-items: center; position: relative;',
    '  border: 2px solid color-mix(in srgb, var(--tile-glyph, #fff) 85%, transparent); background: transparent; color: var(--fill, #333);',
    '  transition: background-color var(--t-quick) var(--ease-state), border-color var(--t-quick) var(--ease-state); }',
    '.sl-c > * { grid-area: 1 / 1; }',
    '.sl-c .tk { display: grid; place-items: center; opacity: 0; transform: scale(.5); transition: opacity var(--t-quick) cubic-bezier(0, 0, .2, 1), transform var(--t-quick) cubic-bezier(0, 0, .2, 1); }',
    '.sl-c .tk svg { width: calc(var(--c) * .56); height: calc(var(--c) * .56); }',
    '.sl-c .num { font: 700 calc(15px * min(var(--sc, 1), 1.5)) / 1 ui-rounded, -apple-system, system-ui, sans-serif; font-variant-numeric: tabular-nums; }',
    '.sl-c.on { background: #fff; border-color: #fff; } .sl-c.on .tk { opacity: 1; transform: none; }',
    '.ui-tile.on .sl-c:not(.on), .ui-tile.colored .sl-c:not(.on) { border-color: rgba(255, 255, 255, .7); }',   /* C: an unselected tile is the plain off face, but a ring on a filled tile stays white */
    '.k-reduce-motion .sl-c .tk { transform: none; }',
    '.ui-tile.unavail .sl-ind { opacity: .5; }',
    '.sl-badge { position: absolute; top: 2px; right: 0; min-width: 18px; height: 18px; border-radius: 9px; padding: 0 4px; box-sizing: border-box; display: grid; place-items: center;',
    '  background: #1c1c1e; color: #fff; font: 700 11px / 1 ui-rounded, -apple-system, system-ui, sans-serif; border: 1.5px solid #fff; z-index: 3; transition: opacity var(--t-quick) ease-out; }',
    '.sl-badge:empty { opacity: 0; }',
    '.ui-tile.sl-opt-b2 .acc .ui-toggle { margin: 0; }',
    '.sl-cells { display: flex; flex-wrap: wrap; gap: 16px; align-items: flex-start; }',
    '.sl-cell { flex: 0 1 398px; max-width: 100%; min-width: 0; }',
    '.sl-vo { width: 100%; border-collapse: collapse; font-size: 14px; } .sl-vo th, .sl-vo td { text-align: left; vertical-align: top; padding: 8px 10px; border-bottom: 1px solid var(--k-line); }',
    '.sl-vo th { font-weight: 600; background: color-mix(in srgb, var(--k-fg) 6%, transparent); } .sl-vo code { white-space: nowrap; }',
    '.sl-rec { border-left: 4px solid var(--k-accent); background: var(--k-accent-soft); padding: 12px 16px; border-radius: 8px; }',
    '.sl-q { padding: 10px 14px; border: 1px solid var(--k-line); border-radius: 10px; background: var(--k-surface); margin-bottom: 8px; }',
    '.sl-cmp td.c, .sl-cmp th.c { background: color-mix(in srgb, var(--k-accent) 8%, transparent); }',
  ].join('\n');
  var st = document.createElement('style'); st.textContent = css; document.head.appendChild(st);

  SEL.OPTS = [['A', 'A · Check disc'], ['B1', 'B1 · Toggle-styled disc'], ['B2', 'B2 · System switch'], ['C', 'C · Selected face']];
  var ORD = ['', '1st', '2nd', '3rd', '4th'];

  /** Fixtures (names from the app's config; the families are the ones these tiles use). multi: ordered multi-select. */
  SEL.cases = {
    sources: { title: 'Studio sources', family: 'media', sheet: false, page: 'Studio', back: 'Media', multi: false, one: 'On the TV',
      items: [{ id: 'Game Console', title: 'Game Console', symbol: 'gamecontroller', sel: true }, { id: 'server', title: 'Server', symbol: 'server.rack' }, { id: 'pc', title: 'Computer', symbol: 'pc' }, { id: 'Game', title: 'Game', symbol: 'sparkles' }] },
    travelers: { title: 'Solo Trip travelers', family: 'occupancy', page: 'Solo Trip', back: 'Settings', multi: false, one: 'Traveling',
      items: [{ id: 'alex', title: 'Alex', symbol: 'person', sel: true }, { id: 'sam', title: 'Sam', symbol: 'person' }] },
    vacuum: { title: 'Vacuum Rooms cards', family: 'cleaning', sheet: true, page: 'Robot Vacuum', multi: true,
      items: [{ id: 'kitchen', title: 'Kitchen', symbol: 'fork.knife', order: 2 }, { id: 'living', title: 'Living Room', symbol: 'sofa', order: 1 }, { id: 'office', title: 'Office', symbol: 'laptopcomputer', order: 3 }, { id: 'bedroom', title: 'Bedroom', symbol: 'bed.double' }] },
  };

  function subtitle(it, c) {
    if (it.unavail) return 'Unavailable';
    if (c.multi) return it.order ? 'Cleans ' + ORD[it.order] : 'Not included';
    return it.sel ? c.one : null;
  }

  /** The indicator / control on the trailing edge. */
  function control(opt, it, c) {
    var sel = !!it.sel || !!it.order, hide = { 'aria-hidden': 'true' };
    if (opt === 'B2') return K().Toggle({ on: sel, label: it.title });
    if (opt === 'B1') {
      var d = AT.disc({ id: it.id, label: it.title, symbol: it.symbol, tog: true, on: sel, pri: true }, { refine: true, hidden: true, disabled: !!it.unavail });
      d.dataset.sym = it.symbol;
      var badge = h('span.sl-badge', hide, c.multi && it.order ? String(it.order) : '');
      return h('span.sl-ind', d, badge);
    }
    var ring = h('span.sl-c' + (sel ? '.on' : ''), hide,
      h('span.tk', { html: I('checkmark', { weight: 3 }) }),
      c.multi ? h('span.num', { style: { opacity: sel ? 1 : 0 } }, it.order ? String(it.order) : '') : null);
    if (c.multi) ring.querySelector('.tk').style.display = 'none';
    return h('span.sl-ind', ring);
  }

  /** One tile drawn as option opt. it: {id, title, symbol, sel, order?, unavail?}; c: the case. */
  SEL.tile = function (opt, it, c) {
    var sel = !!it.sel || !!it.order, fills = (opt === 'B1' || opt === 'C') && sel, un = !!it.unavail;
    var ctl = control(opt, it, c);
    var props = { title: it.title, subtitle: subtitle(it, c), symbol: it.symbol, family: c.family, isActive: fills && !un, isUnavailable: un,
      kind: opt === 'B2' ? 'command' : (opt === 'B1' ? 'toggle' : 'selection'), selected: sel, accessory: ctl, accessoryWidth: opt === 'B2' ? 59 : 52 };
    var t = K().GlassTile(props);
    var gl = t.querySelector(':scope > .glyph'); if (gl) gl.remove();
    t.classList.add('no-glyph', 'at-b', 'at-carry', 'sl-opt-' + opt.toLowerCase());
    t.style.setProperty('--acc-w', opt === 'B2' ? 'calc(51px + 8px)' : 'calc(44px * min(var(--sc, 1), 1.5) + 8px)');
    t.dataset.sid = it.id; t.dataset.sopt = opt; t.dataset.sel = sel ? '1' : '0';
    if (un) t.setAttribute('aria-disabled', 'true');
    t._sel = { it: it, opt: opt, c: c };
    return t;
  };

  /** Re-targets a drawn tile to a new item state in place: classes flip (colour cross-fades on state, the indicator on quick), the number rolls. Resolves after the colour settles. */
  SEL.retarget = function (tile, it) {
    var s = tile._sel, f = SEL.tile(s.opt, it, s.c), gc = tile.style.gridColumn, gr = tile.style.gridRow;
    tile.className = f.className; tile.setAttribute('style', f.getAttribute('style') || ''); tile.style.gridColumn = gc; tile.style.gridRow = gr;
    ['aria-pressed', 'aria-label', 'aria-disabled'].forEach(function (a) { if (f.hasAttribute(a)) tile.setAttribute(a, f.getAttribute(a)); else tile.removeAttribute(a); });
    tile.dataset.sel = f.dataset.sel;
    var a = tile.querySelector('.st'), b = f.querySelector('.st');
    if (a && b) a.textContent = b.textContent; else if (!a && b) tile.querySelector('.tx').appendChild(b); else if (a && !b) a.remove();
    var oc = tile.querySelector('.sl-c'), nc = f.querySelector('.sl-c');
    if (oc && nc) { oc.className = nc.className; var on = oc.querySelector('.num'), nn = nc.querySelector('.num'); if (on && nn) { on.textContent = nn.textContent; on.style.opacity = nn.style.opacity; } }
    var od = tile.querySelector('.at-disc'), nd = f.querySelector('.at-disc');
    if (od && nd) { od.className = nd.className; od.disabled = nd.disabled; od.setAttribute('aria-label', nd.getAttribute('aria-label')); }
    var ob = tile.querySelector('.sl-badge'), nb = f.querySelector('.sl-badge'); if (ob && nb) ob.textContent = nb.textContent;
    var ot = tile.querySelector('.ui-toggle'), nt = f.querySelector('.ui-toggle');
    if (ot && nt) { ot.className = nt.className; ot.setAttribute('aria-checked', nt.getAttribute('aria-checked')); }
    tile._sel = { it: it, opt: s.opt, c: s.c };
    return Mock.sleep(Mock.anim.ms.state() + 30);
  };
  /** Applies a list of item states (matching tiles by data-sid) to every drawn option in a stage. */
  SEL.apply = function (stage, list) {
    var ps = [];
    list.forEach(function (it) {
      Array.prototype.slice.call(stage.querySelectorAll('.ui-tile[data-sid="' + it.id + '"]')).forEach(function (t) { if (t._sel) ps.push(SEL.retarget(t, Object.assign({}, t._sel.it, it))); });
    });
    return Promise.all(ps);
  };

  SEL.grid = function (ctx, opt, caseKey, o) {
    var c = SEL.cases[caseKey], items = (o && o.items) || c.items;
    return AT.grid(items.map(function (it) { return SEL.tile(opt, it, c); }), ctx, o && o.grid);
  };
  /** Sections for a state: one per option, so every option is on every device. */
  SEL.sections = function (ctx, caseKey, o) {
    return SEL.OPTS.map(function (x) { return AT.sec(x[1], SEL.grid(ctx, x[0], caseKey, o)); });
  };
  SEL.pageFor = function (ctx, caseKey, o) {
    var c = SEL.cases[caseKey], secs = SEL.sections(ctx, caseKey, o);
    if (c.sheet) {
      var wrap = h('div', { style: { display: 'flex', flexDirection: 'column', gap: '20px' } }, secs);
      return Mock.sheet(ctx, { title: c.page, subtitle: 'Rooms', detent: 'large', size: 'page', trailing: 'close', content: [wrap] });
    }
    return AT.page(ctx, { title: c.page, back: c.back, section: 'home', sections: secs, split: true });
  };
  /** The options section: a row per case, four phone-width swatches (A, B1, B2, C). */
  SEL.cells = function (caseKey, o) {
    var c = SEL.cases[caseKey], wrap = h('div.sl-cells');
    SEL.OPTS.forEach(function (x) {
      var box = h('div.k-swatch.page.g-dark.sl-cell', { style: { '--sc': 1 } }, h('div.k-cap', x[1]), h('div.in', SEL.grid(null, x[0], caseKey, Object.assign({ grid: { compact: true, max: 2 } }, o || {}))));
      wrap.appendChild(box);
    });
    return h('div', h('h3', c.title + (c.multi ? ' (multi-select, tap order = cleaning order)' : ' (choose one)')), wrap);
  };
})();
