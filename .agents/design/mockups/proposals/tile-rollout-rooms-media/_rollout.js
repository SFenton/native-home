/* Local helper for the tile-rollout-rooms-media proposal (promote to kit only if the owner picks): small builders over the kit's GlassTile.
 *
 *   RO.T(spec)        one tile from a short spec: {t title, s subtitle, sym, fam, on, u unavailable, err, k:'nav'|'act'|'tog'|'sel'|'cmd'|'state', acts:[disc], prog, pt, wide, below, under, layout, lines, fill}
 *                     k 'nav' + acts is a navigation tile with discs left of the chevron; k 'act' + acts is an action tile (text . disc, no leading glyph);
 *                     k 'state' is the flat read-only face. Without acts a tile is drawn exactly as the app draws it today.
 *   RO.D(sym, label, on, dim)  a disc ({id, symbol, label, on, dim}); RO.pwr(title, on, dim) the Power disc.
 *   RO.grid(tiles)    the kit TileGrid (min 150); a tile flagged `wide` takes two tracks when the grid has two or more (its text + discs + chevron need the room).
 *   RO.block(o)       one labelled column of a state: {tags:[[text, cls]], label, note, kids}. RO.page / RO.sheet / RO.stack build the surface around blocks.
 *
 * Reuses, by loading and not copying: the kit (GlassTile, TileGrid, PageSectionHeader, Alert, ConfirmationDialog), the action-navigation-tiles helper (Mock.at: disc morph,
 * sentinel for the selection helper) and the selection-tiles helper (Mock.sel: SEL.tile 'C', the selected face with a check disc).
 */
(function () {
  var h = Mock.h, RO = Mock.ro = {};
  function K() { return Mock.components; }

  /* A local symbol: fan.slash (the closed vent). Drawn from the kit's fan with a slash. */
  (function () {
    var f = Mock.symbols['fan'], o = Array.isArray(f) ? f[0] : f;
    if (!Mock.symbols['fan.slash']) Mock.symbols['fan.slash'] = [o + '<path d="M4 3.5l16 17"/>'];
  })();

  var css = [
    '.ro-stack { display: flex; flex-direction: column; gap: 24px; }',
    '.ro-stack.cols { display: grid; align-items: start; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); }',
    '.ro-block { display: flex; flex-direction: column; gap: 12px; min-width: 0; }',
    '.ro-hd { display: flex; align-items: center; gap: 8px; flex-wrap: wrap; }',
    '.ro-tag { font: 700 12px / 1 -apple-system, system-ui, sans-serif; letter-spacing: .04em; text-transform: uppercase; padding: 6px 10px; border-radius: 99px; background: rgba(120, 120, 128, .55); color: #fff; white-space: nowrap; }',
    '.ro-tag.prop { background: #0A62C9; } .ro-tag.rec { background: #1E7B34; } .ro-tag.choice { background: #FFB340; color: #1c1c1e; } .ro-tag.alt { background: #6E5BB8; }',
    '.ro-lab { font: 600 var(--fs-sub, 15px) / 1.25 -apple-system, system-ui, sans-serif; color: var(--ink, #fff); }',
    '.ro-note { margin: 0; font-size: var(--fs-foot, 13px); line-height: 1.35; color: var(--ink-2, rgba(255, 255, 255, .85)); }',
    '.ro-note strong { color: var(--ink, #fff); }',
    '.ro-cap { margin: 4px 0 -4px; font: 600 var(--fs-foot, 13px) / 1.2 -apple-system, system-ui, sans-serif; color: var(--ink-2, rgba(255, 255, 255, .85)); }',
    '.ro-sub { display: flex; flex-direction: column; gap: 8px; }',
    '.ro-tbl { width: 100%; border-collapse: collapse; font-size: 14px; } .ro-tbl th, .ro-tbl td { text-align: left; vertical-align: top; padding: 8px 10px; border-bottom: 1px solid var(--k-line); }',
    '.ro-tbl th { font-weight: 600; background: color-mix(in srgb, var(--k-fg) 6%, transparent); } .ro-tbl td.n { white-space: nowrap; font-variant-numeric: tabular-nums; font-weight: 600; }',
    '.ro-tbl tr.choice td { background: color-mix(in srgb, #FFB340 14%, transparent); }',
    '.ro-pill { display: inline-block; font-size: 12px; font-weight: 700; padding: 2px 8px; border-radius: 99px; background: #FFB340; color: #1c1c1e; margin-left: 6px; white-space: nowrap; }',
    '.ro-rec { border-left: 4px solid var(--k-accent); background: var(--k-accent-soft); padding: 12px 16px; border-radius: 8px; }',
    '.ro-q { padding: 10px 14px; border: 1px solid var(--k-line); border-radius: 10px; background: var(--k-surface); margin-bottom: 8px; }',
    '.ro-q.choice { border-color: #FFB340; border-width: 2px; }',
    /* A stacked tile (Quick Links: glyph top-leading, name bottom) keeps its discs vertically centred beside the chevron, as every action tile does (the kit's stack puts them at the foot). */
    '.ui-tile.stack.has-discs { position: relative; }',
    '.ui-tile.stack.has-discs .discs { position: absolute; right: 36px; top: 50%; transform: translateY(-50%); margin: 0; }',
    '.ui-tile.stack.has-discs .tx { padding-right: 96px; }',
    '.ts-ax5 .ui-tile.stack.has-discs .discs { position: static; transform: none; margin: 8px 0 0; }',
    '.ts-ax5 .ui-tile.stack.has-discs .tx { padding-right: 0; }',
  ].join('\n');
  var st = document.createElement('style'); st.textContent = css; document.head.appendChild(st);

  /* ---------------------------------------------------------------- discs and tiles */
  RO.D = function (sym, label, on, dim) { return { id: sym, symbol: sym, label: label, on: !!on, dim: !!dim }; };
  RO.pwr = function (title, on, dim) { return RO.D('power', (on ? 'Turn Off ' : 'Turn On ') + title, on, dim); };

  var KIND = { nav: 'navigate', act: 'command', cmd: 'command', tog: 'toggle', sel: 'selection', state: 'state' };
  RO.T = function (s) {
    var k = s.k || 'nav', beh = null;
    if (s.acts && s.acts.length) beh = k === 'nav' ? 'navigate' : 'perform';
    if (k === 'state' && s.flat !== false) beh = 'inert';
    var n = Mock.tile({ title: s.t, subtitle: s.s, symbol: s.sym, family: s.fam, isActive: !!s.on, isUnavailable: !!s.u, isError: !!s.err, kind: KIND[k], selected: s.sel,
      progress: s.prog, progressTint: s.pt, behavior: beh, actions: s.acts, below: s.below, under: s.under, layout: s.layout, titleLines: s.lines, fill: s.fill });
    if (s.wide) n.dataset.wide = '1';
    if (s.id) n.setAttribute('data-ident', s.id);
    return n;
  };

  /** The kit grid; a `wide` tile takes two tracks (never more than the grid has) because its text, discs and chevron need the room. */
  RO.grid = function (tiles, o) {
    o = o || {};
    var g = K().TileGrid({ items: tiles, min: o.min || 150, max: o.max || 6, equal: o.equal !== false });
    function fit() {
      var cols = getComputedStyle(g).gridTemplateColumns.split(' ').filter(Boolean).length || 1;
      [].forEach.call(g.children, function (t) { if (t.dataset && t.dataset.wide === '1') t.style.gridColumn = cols > 1 ? 'span ' + Math.min(cols, 2) : ''; });
    }
    [60, 400, 1200].forEach(function (ms) { setTimeout(fit, ms); });
    if (window.ResizeObserver) new ResizeObserver(function () { setTimeout(fit, 0); }).observe(g);
    return g;
  };

  /* ---------------------------------------------------------------- blocks and surfaces */
  /** o: {tags:[[text, cls]], label, note, kids}. cls: today | prop | rec | choice | alt. */
  RO.block = function (o) {
    var kids = [h('div.ro-hd', (o.tags || []).map(function (t) { return h('span.ro-tag' + (t[1] ? '.' + t[1] : ''), t[0]); }), o.label ? h('span.ro-lab', o.label) : null)];
    if (o.note) kids.push(h('p.ro-note', o.note));
    return h('div.ro-block', kids, o.kids);
  };
  RO.cap = function (text) { return h('p.ro-cap', text); };
  RO.hdr = function (title) { return K().PageSectionHeader({ title: title }); };
  RO.sub = function (kids) { return h('div.ro-sub', kids); };
  RO.stack = function (ctx, blocks) { return h('div.ro-stack' + (ctx.regular && blocks.length > 1 ? '.cols' : ''), blocks); };

  /** A pushed page (back leads to `back`) with the blocks as its body. */
  RO.page = function (ctx, o) {
    var pg = Mock.page(ctx, { title: o.title, section: 'home', back: o.back || 'Home', badge: 3, choresBadge: 2, body: [RO.stack(ctx, o.blocks)], bottomPad: 32 });
    if (o.overlay) pg.appendChild(o.overlay);
    return pg;
  };
  /** A page sheet (large detent) with the blocks as its body. */
  RO.sheet = function (ctx, o) {
    return Mock.sheet(ctx, { title: o.title, subtitle: o.subtitle, detent: 'large', size: 'page', trailing: 'close', content: [RO.stack(ctx, o.blocks)], alert: o.alert });
  };
  RO.alertScrim = function (ctx, alertNode) { return h('div.ui-alert-scrim.' + (ctx.appearance === 'dark' ? 'g-dark' : 'g-light'), alertNode); };

  /** Flips a drawn tile between its off and on faces in place (the kit's colour slots cross-fade on the state token). */
  RO.flip = function (tile, on, sub) {
    var st = tile.querySelector('.st');
    tile.classList.toggle('off', !on); tile.classList.toggle('on', on);
    if (st && sub != null) st.textContent = sub;
    return Mock.sleep(Mock.anim.ms.state() + 80);
  };
})();
