/* Local helper for the tile-rollout-settings-more proposal (promote to kit only if the owner picks): draws each rolled-out surface "Today" beside "Proposed".
 * Everything proposed is the KIT GlassTile (`behavior`, `actions`, `under`, `accessory`) plus the selection-tiles helper (`Mock.sel`, loaded, not copied) for choose-one and
 * ordered multi-select tiles. Today's tiles come from each surface's own atlas helper (HF household forms, Chores, VS vacation and sprinklers, Mock.dv.vac vacuums).
 *
 * Maps to apple/Sources/HassDesign/GlassTile.swift (TileBehavior, TileActionButton) and HassCore/TileActions (PowerToggleActions, LockActions, VacuumActions, a new
 * CommandActions for the momentary power-recovery disc and a StopWateringActions). Every function here is a STAND-IN for a SwiftUI view; the notes say what the app does.
 */
(function () {
  var h = Mock.h, I = Mock.icon, RO = Mock.ro = {};
  function K() { return Mock.components; }

  var css = [
    '.ro-cap { margin: 14px 0 6px; font: 700 12px / 1.2 var(--mono); letter-spacing: .02em; color: var(--g-secondary-on-wallpaper, rgba(255,255,255,.85)); display: flex; flex-wrap: wrap; align-items: center; gap: 8px; }',
    '.ro-cap:first-child { margin-top: 0; } .in-sheet .ro-cap { color: var(--ink-sheet-2); }',
    '.ro-cap.prop { color: #7BE0A0; } .g-light .ro-cap.prop, .in-sheet.g-light .ro-cap.prop { color: #1B7A41; }',
    '.ro-cap.rec { color: #FFD60A; } .g-light .ro-cap.rec { color: #8A6A00; }',
    '.ro-tag { display: inline-block; padding: 2px 8px; border-radius: 99px; font: 700 11px / 1.3 var(--mono); background: #FFD60A; color: #1C1C1E; letter-spacing: .02em; }',
    '.ro-tag.alt { background: rgba(255,255,255,.2); color: inherit; }',
    '.ro-pair { display: flex; flex-direction: column; min-width: 0; }',
    '.ro-gap { display: flex; flex-direction: column; gap: 12px; min-width: 0; }',
    /* settings green: the tinted face carries the tint as the glyph colour, so a disc on a filled tile needs its ink restated */
    '.ui-tile.ro-t.tinted .disc:not(.on) { background: rgba(0,0,0,.18); color: #fff; }',
    '.ui-tile.ro-t.tinted .disc.on { background: #fff; color: var(--glyph); }',
    '.ui-tile.ro-t.error .disc { background: rgba(0,0,0,.18); color: #fff; }',
    '.ui-tile.ro-t.off .disc { background: rgba(255,255,255,.16); color: var(--tile-glyph); }',
    '.ui-tile.unavail .disc { opacity: .5; }',
    '.ui-tile.ro-ct-t .acc { right: 32px; }',
    '.ro-ct { min-width: 28px; height: 28px; padding: 0 8px; box-sizing: border-box; border-radius: 14px; display: grid; place-items: center; background: rgba(0,0,0,.2); color: #fff; font: 700 var(--fs-sub) / 1 var(--font-d, var(--font)); font-variant-numeric: tabular-nums; }',
    '.ui-tile .under .vc-flow { display: flex; flex-wrap: wrap; gap: 6px; margin-top: 8px; }',
    '.ro-note { margin: 8px 0 0; font-size: var(--fs-foot); color: var(--g-secondary-on-wallpaper, rgba(255,255,255,.85)); } .in-sheet .ro-note { color: var(--ink-sheet-2); }',
    '.ro-cells { display: flex; flex-wrap: wrap; gap: 16px; align-items: flex-start; } .ro-cell { flex: 0 1 398px; max-width: 100%; min-width: 0; }',
    '.ro-cmp { width: 100%; border-collapse: collapse; font-size: 14px; } .ro-cmp th, .ro-cmp td { text-align: left; vertical-align: top; padding: 8px 10px; border-bottom: 1px solid var(--k-line); }',
    '.ro-cmp th { font-weight: 600; background: color-mix(in srgb, var(--k-fg) 6%, transparent); } .ro-cmp td.c, .ro-cmp th.c { background: color-mix(in srgb, var(--k-accent) 8%, transparent); } .ro-cmp code { white-space: nowrap; }',
    '.ro-rec { border-left: 4px solid var(--k-accent); background: var(--k-accent-soft); padding: 12px 16px; border-radius: 8px; }',
    '.ro-q { padding: 10px 14px; border: 1px solid var(--k-line); border-radius: 10px; background: var(--k-surface); margin-bottom: 8px; }',
    '.ro-choice { padding: 12px 16px; border: 2px solid #FFD60A; border-radius: 10px; background: color-mix(in srgb, #FFD60A 12%, transparent); margin-bottom: 12px; }',
  ].join('\n');
  var st = document.createElement('style'); st.textContent = css; document.head.appendChild(st);

  /* ---------------------------------------------------------------- tiles */
  /** An ACTION tile: text then one 44 pt disc, no leading glyph (the disc carries the state glyph).
   *  o: {title, sub, tint|family, active, disc (symbol), label, id, discOn (white disc), busy, dim, unavailable, error, momentary} */
  RO.act = function (o) {
    var a = { id: o.id || 'act', symbol: o.disc, label: o.label || o.title, on: !!o.discOn, busy: !!o.busy, dim: !!o.dim || !!o.unavailable };
    var t = K().GlassTile({ title: o.title, subtitle: o.sub, symbol: o.disc, tint: o.tint, family: o.family, isActive: !!o.active, isUnavailable: !!o.unavailable, isError: !!o.error,
      kind: o.momentary ? 'command' : 'toggle', behavior: 'perform', actions: [a] });
    if (o.tint) t.classList.add('ro-t');
    if (o.disc === 'power') { var sv = t.querySelector('.disc svg'); if (sv) { sv.setAttribute('fill', 'none'); sv.removeAttribute('fill-opacity'); } }   /* kit discs fill every glyph; power is a pure stroke symbol and filled into a blob (promote the fix to kit) */
    return RO.tag(t, { n: 1, carry: true, max: o.maxState || (o.sub0 || 'Didn\'t Respond') });
  };
  /** A NAVIGATION tile: glyph, text, optional discs left of the chevron, chevron. o: {title, sub, symbol, tint|family, active, actions:[{id,symbol,label,on,dim,busy}], progress, under, accessory} */
  RO.nav = function (o) {
    var p = { title: o.title, subtitle: o.sub, symbol: o.symbol, tint: o.tint, family: o.family, isActive: !!o.active, isUnavailable: !!o.unavailable, isError: !!o.error,
      behavior: 'navigate', actions: o.actions || [], progress: o.progress, under: o.under, accessory: o.accessory, accessoryWidth: o.accessoryWidth };
    var t = K().GlassTile(p);
    if (o.tint) t.classList.add('ro-t');
    return (o.actions || []).length ? RO.tag(t, { n: o.actions.length, carry: false, max: o.maxState || '' }) : t;
  };
  /** A read-only tile (today's car tiles). */
  RO.flat = function (o) { return K().GlassTile({ title: o.title, subtitle: o.sub, symbol: o.symbol, tint: o.tint, isActive: !!o.active, isUnavailable: !!o.unavailable, kind: 'state' }); };

  /** Marks a tile for the content-aware grid (the first decision's width rule: a tile takes as many tracks as its title, its longest state and its discs need; AT.grid measures it). */
  RO.tag = function (t, o) {
    t.classList.add('at-b'); if (o.carry) t.classList.add('at-carry');
    t.dataset.opt = 'B'; t.dataset.n = o.n || 0; t.dataset.bn = 0; t.dataset.vol = '0'; t.dataset.maxState = o.max || '';
    return t;
  };

  /* ---------------------------------------------------------------- layout helpers */
  RO.cap = function (text, kind, tag) { return h('p.ro-cap' + (kind ? '.' + kind : ''), text, tag ? h('span.ro-tag' + (tag.alt ? '.alt' : ''), tag.text || tag) : null); };
  /** A grid. When any tile is tagged it is the content-aware grid (Mock.at.grid, tracks of 150 pt); untagged tiles in it count as one track with no discs. Otherwise the kit grid. */
  RO.grid = function (items, min, max) {
    var tagged = items.some(function (t) { return t.dataset && t.dataset.opt === 'B'; });
    if (!tagged) return K().TileGrid({ items: items, min: min || 150, max: max || 2, equal: false });
    items.forEach(function (t) { if (!t.dataset.opt) { t.dataset.opt = 'B'; t.dataset.n = 0; t.dataset.bn = 0; t.dataset.vol = '0'; t.dataset.maxState = ''; t.classList.add('at-b'); } });
    return Mock.at.grid(items, Mock.current, { max: max || 2 });
  };
  /** Today over Proposed (or only one of them, mode 'prop' | 'today'). tiles: {today:[nodes], prop:[nodes]}. */
  RO.pair = function (mode, tiles, o) {
    o = o || {};
    var kids = [];
    if (mode !== 'prop') { kids.push(RO.cap(o.todayLabel || 'Today', 'today')); kids.push(RO.grid(tiles.today, o.min, o.max)); }
    if (mode !== 'today') { kids.push(RO.cap(o.propLabel || 'Proposed', 'prop')); kids.push(RO.grid(tiles.prop, o.min, o.max)); }
    return h('div.ro-pair', kids);
  };
  /** Labelled grids stacked: rows = [{label, kind, tag, tiles, min, max}]. */
  RO.stack = function (rows) {
    return h('div.ro-pair', rows.reduce(function (a, r) { a.push(RO.cap(r.label, r.kind, r.tag)); a.push(r.node || RO.grid(r.tiles, r.min, r.max)); if (r.note) a.push(h('p.ro-note', r.note)); return a; }, []));
  };
  RO.note = function (t) { return h('p.ro-note', t); };
  RO.swatch = function (label, node) { return h('div.k-swatch.page.g-dark.ro-cell', { style: { '--sc': 1 } }, h('div.k-cap', label), h('div.in', node)); };

  /** A presenter page with an alert over it (the always-dark page, as V.disableAlert draws). */
  RO.alertOver = function (page, spec, ctx) {
    var alert = K().Alert({ title: spec.title, message: spec.message, buttons: [{ title: 'Cancel', role: 'cancel' }, { title: spec.confirm }], stacked: !!ctx.axSize });
    return h('div.ui-host', h('div.ui-presenter', page), h('div.ui-alert-scrim.g-dark', alert));
  };

  /** Tints the selection tiles' check disc and glyph for a tint-only family (Solo Trip uses its own blue, not a colour family). */
  RO.tintSel = function (t, color) { t.style.setProperty('--glyph', color); t.style.setProperty('--glyph-light', color); t.style.setProperty('--fill', color); return t; };
})();
