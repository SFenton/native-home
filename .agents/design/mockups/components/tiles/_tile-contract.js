/* Shared helpers for the native tile contract (swipe to adjust, state words, tile ink, state groups): `window.TC`.
 *
 * Loaded after kit.js by brightness-tile, state-styled-tile, light-group-tile and dynamic-grid-layout. Nothing here edits _kit/: the CSS is one injected
 * <style id="tc-style"> and the builders return or change plain kit nodes.
 *
 * PROMOTE TO KIT: the swipe bubble (replacing BrightnessTile's `.ui-bubble`, whose offset predates the measured one), the ink rule (as `.ui-tile` rules under a
 * document flag) and the grouped grid (as a `groups` prop of TileGrid).
 *
 * Sources it mirrors (apple/Sources): HassDesign/{TileSwipe,TileInkDefault,TileFaceInk}.swift, HassCore/ServerUIComposition/{ServerUITileSwipe,ServerUIGridGroups}.swift,
 * HassUI/UIKitPort/Design/UKTileSwipeController.swift, HassUI/UIKitPort/ServerUI/{UKServerUITileSwipe,UKServerUIGridGrouping}.swift.
 * Measured values: build/evidence/screens/native-tilecontract-fba79957 (bubble 60 x 32 pt, "100%" 68 x 32 pt, at tile widths 170, 179 and 192 pt).
 */
(function () {
  'use strict';
  var h = Mock.h, K = Mock.components;
  var TC = window.TC = {};

  var css = [
    /* The swipe bubble: a dark capsule with white text in both appearances, row-title semibold 15 pt with monospaced digits, 12 pt side padding,
       32 pt tall and at least 60 pt wide (44 and 84 pt at accessibility sizes), never wider than its tile. */
    '.tc-bub{position:absolute;z-index:6;display:grid;place-items:center;box-sizing:border-box;padding:0 12px;border-radius:99px;background:#2C2C2E;color:#fff;max-width:100%;',
    'font:600 15px/1 var(--font);font-variant-numeric:tabular-nums;box-shadow:0 2px 6px rgba(0,0,0,.3);pointer-events:none;white-space:nowrap;transform:translateX(-50%)}',
    '.tc-bub.ax{font-size:28px}',
    /* Annotation only: where the haptic detents fall. The app draws no marks. */
    '.tc-ruler{position:relative;height:18px;margin-top:6px}.tc-ruler i{position:absolute;top:0;width:1px;height:8px;background:currentColor;opacity:.55}',
    '.tc-ruler span{position:absolute;top:9px;left:0;right:0;font:11px/1 var(--font);opacity:.6;text-align:center}',
    /* sh.tile-ink-default@1 (option A). Under a document that declares the id, on the dark faces only (idle, active with no fill, warning): every state line
       draws the primary ink, and so does an icon with no colour of its own. Filled faces, the error face, a family tint, an authored tint and the warning's amber
       icon keep their ink; an unavailable tile keeps today's grey. */
    '.tc-ink .ui-tile.off:not(.unavail) .st,.tc-ink .ui-tile.tinted .st,.tc-ink .ui-tile.st-warning:not(.unavail) .st{color:var(--tile-ink)}',
    '.tc-ink .ui-tile.off[data-nofam]:not(.unavail):not(.st-warning) .glyph,.tc-ink .ui-tile.tinted[data-nofam] .glyph{color:var(--tile-ink)}',
    /* A group heading inside a sheet's grid keeps 8 pt above its title (UKPageSectionHeaderView inSheet); on a page it has none. */
    '.in-sheet .ui-grid>.gridheader.tc-hd{padding-top:8px}',
    '.tc-gap{height:44px}',
  ].join('\n');
  var st = document.createElement('style'); st.id = 'tc-style'; st.textContent = css; document.head.appendChild(st);

  /* ------------------------------------------------------------------ swipe to adjust */
  /** Sets a tile's band to `frac`, whichever face drew it (lit, power and off bands grow from the leading edge; a filled face shades what is left). */
  TC.setBand = function (tile, frac, o) {
    o = o || {};
    var band = tile.querySelector('.band'); if (!band) return;
    if (o.noBand) { band.remove(); return; }
    var shade = band.classList.contains('shade'), pct = Math.round((shade ? 1 - frac : frac) * 100), lead = shade ? !!o.rtl : !o.rtl;
    band.style.transition = 'none'; band.style.overflow = 'hidden'; band.style.width = pct + '%';
    band.style.left = lead ? '0' : 'auto'; band.style.right = lead ? 'auto' : '0';
    band.style.borderRadius = pct >= 97 ? '22px' : (lead ? '22px 0 0 22px' : '0 22px 22px 0');
  };
  /**
   * Draws a tile mid-swipe as built: the lift (1.03 and a shadow; the shadow only with Reduce Motion), the band at `frac`, and the bubble with `text`
   * centred over the band's edge, 8 pt clear of the tile's top and clamped inside the tile's width.
   * @param {HTMLElement} tile a kit tile
   * @param {number} frac 0...1 across the range (already snapped to the step)
   * @param {string} text the bubble's text: the value through `format`, or the tile's own word at 0
   * @param {{rtl?: boolean, top?: number, noBand?: boolean, ax?: boolean, status?: boolean}} [o] rtl mirrors the band and mapping; top overrides the
   *   bubble's offset (the top-of-scroller rule); ax draws the accessibility-size bubble; status false keeps the tile's own state line (a state tile)
   */
  TC.drag = function (tile, frac, text, o) {
    o = o || {};
    var w = o.ax ? 84 : 60, hh = o.ax ? 44 : 32, pos = (o.rtl ? 1 - frac : frac) * 100;
    if (!Mock.settings.reduceMotion) tile.style.transform = 'scale(1.03)';
    tile.style.boxShadow = '0 6px 12px rgba(0,0,0,.35)'; tile.style.zIndex = 5; tile.style.overflow = 'visible';
    TC.setBand(tile, frac, o);
    if (o.status !== false && tile.dataset.anim === 'brightness') { var s = tile.querySelector('.st'); if (s) s.textContent = text; }
    var old = tile.querySelector('.tc-bub, .ui-bubble'); if (old) old.remove();
    var b = h('span.tc-bub' + (o.ax ? '.ax' : ''), { 'aria-hidden': 'true' }, text);
    b.style.minWidth = w + 'px'; b.style.height = hh + 'px'; b.style.top = (o.top != null ? o.top : -(hh + 8)) + 'px';
    /* Centre on the band's edge, then keep the whole bubble inside the tile: half its own width from either edge. */
    function place(bw) { b.style.left = 'clamp(' + (bw / 2) + 'px, ' + pos + '%, calc(100% - ' + (bw / 2) + 'px))'; }
    place(w);
    tile.appendChild(b);
    requestAnimationFrame(function () { if (b.offsetWidth) place(b.offsetWidth); });   // "100%" is 68 pt wide: clamp on the drawn width
    return tile;
  };
  /** Ends a drawn swipe: the bubble and lift go; the band stays where release left it. */
  TC.release = function (tile) { var b = tile.querySelector('.tc-bub'); if (b) b.remove(); tile.style.transform = ''; tile.style.boxShadow = ''; tile.style.zIndex = ''; return tile; };
  /**
   * Plays a swipe through `values` (each on a detent or step), then releases.
   * @param {HTMLElement} tile a kit tile with a band
   * @param {Array<[number, string]>} values frac and bubble text per sample
   * @param {object} [o] TC.drag options
   */
  TC.play = function (tile, values, o) {
    var chain = Promise.resolve();
    values.forEach(function (v) { chain = chain.then(function () { TC.drag(tile, v[0], v[1], o); return Mock.sleep(420); }); });
    return chain.then(function () { TC.release(tile); return Mock.sleep(300); });
  };
  /**
   * Annotation under a tile: the detent lines, min + k x detent, both ends included. The app draws none; each is one selection tick.
   * @param {number} count detents across the span (10 for brightness at the default; at most 25)
   * @param {string} [label]
   */
  TC.ruler = function (count, label) {
    var r = h('div.tc-ruler', { 'aria-hidden': 'true' });
    for (var k = 0; k <= count; k++) { var t = h('i'); t.style.left = 'calc(' + (k / count * 100) + '% - ' + (k === count ? 1 : 0) + 'px)'; r.appendChild(t); }
    r.appendChild(h('span', label || (count + 1) + ' haptic detent lines (not drawn by the app)'));
    return r;
  };
  /** A tile over its detent ruler, with room above for the bubble. */
  TC.withRuler = function (tile, count, label) { return h('div', { style: { position: 'relative', paddingTop: '44px' } }, tile, TC.ruler(count, label)); };
  /** Room above a grid for the bubble of a first-row tile, so the page's own heading stays readable in the mockup. */
  TC.gap = function () { return h('div.tc-gap', { 'aria-hidden': 'true' }); };

  /* ------------------------------------------------------------------ state words */
  /**
   * The state line a light tile draws from authored words; an absent key is the app's word (production's text).
   * @param {{on?: string, off?: string, unavailable?: string, level?: string}} words `level` holds `{value}`
   * @param {{percent?: number, unavailable?: boolean, dims?: boolean}} s
   */
  TC.lightWord = function (words, s) {
    words = words || {};
    if (s.unavailable) return words.unavailable || 'Unavailable';
    if (!s.percent) return words.off || 'Off';
    if (s.dims === false) return words.on || 'On';
    return (words.level || '{value}%').replace('{value}', s.percent);
  };
  /** A room card's lights line: `on` for one light, `count` (holding `{count}`) for more. */
  TC.roomWord = function (words, s) {
    words = words || {};
    if (s.unavailable) return words.unavailable || 'Unavailable';
    if (!s.count) return words.off || 'Off';
    if (s.total === 1) return words.on || 'On';
    return (words.count || '{count} On').replace('{count}', s.count);
  };
  /** A brightness tile whose state line, spoken value and swipe bubble use the authored words. */
  TC.wordTile = function (p, words) {
    var t = K.BrightnessTile(p), text = TC.lightWord(words, p), s = t.querySelector('.st');
    if (s) s.textContent = text;
    t.setAttribute('aria-valuetext', text);
    return t;
  };

  /* ------------------------------------------------------------------ tile ink */
  /** Marks a subtree as drawn from a document that declares `sh.tile-ink-default@1`. */
  TC.ink = function (node, on) { if (on !== false) node.classList.add('tc-ink'); return node; };
  /** A kit tile; `nofam` marks an icon with no colour of its own (no family, no authored tint). */
  TC.tile = function (p, nofam) { var t = Mock.tile(p); if (nofam) t.dataset.nofam = '1'; return t; };

  /* ------------------------------------------------------------------ state groups */
  /** The face a tile draws, which is its group: `active` (lit, filled or tinted active), `idle`, or `unavailable`. */
  TC.face = function (tile) {
    var c = tile.classList;
    if (c.contains('unavail')) return 'unavailable';
    return c.contains('off') ? 'idle' : 'active';
  };
  /**
   * The items of one grouped grid: each group's title-only heading (a full row with the header trait) and its tiles in the grid's own order.
   * A group with no tiles is dropped, heading and all.
   * @param {HTMLElement[]} tiles in the grid's order
   * @param {Array<{id: string, title: string, states: string[]}>} groups one to three; every state in exactly one group
   */
  TC.groupItems = function (tiles, groups) {
    var out = [];
    groups.forEach(function (g) {
      var mine = tiles.filter(function (t) { return g.states.indexOf(TC.face(t)) >= 0; });
      if (!mine.length) return;
      var hd = K.PageSectionHeader({ title: g.title }); hd.classList.add('gridheader', 'tc-hd'); hd.dataset.group = g.id;
      out.push(hd); mine.forEach(function (t) { out.push(t); });
    });
    return out;
  };
  /** The preset when the option is switched on: "On", then "Off" holding Off and Unavailable. */
  TC.PRESET = [{ id: 'on', title: 'On', states: ['active'] }, { id: 'off', title: 'Off', states: ['idle', 'unavailable'] }];
  /**
   * One grouped grid. `make()` returns fresh tiles (the grid can then be rebuilt for the regroup motion).
   * @param {function(): HTMLElement[]} make
   * @param {Array} groups
   * @param {{min?: number, max?: number}} [o]
   */
  TC.grouped = function (make, groups, o) {
    o = o || {};
    var g = K.TileGrid({ items: TC.groupItems(make(), groups), min: o.min || 150, max: o.max || 4 });
    g.dataset.tcg = '1'; g._tc = { make: make, groups: groups, o: o };
    return g;
  };
  /**
   * Plays one tile changing group after a person's tap: the same tile slides to its place in the other group on `standard` (0.3 s); with Reduce Motion
   * it does not slide and fades in on `quick` (0.2 s). A house change or a reapply is applied with no animation (pass `animated: false`).
   * @param {HTMLElement} grid a TC.grouped grid
   * @param {string} title the tile's title
   * @param {function(HTMLElement[]): HTMLElement[]} change returns the tiles after the change
   * @param {{animated?: boolean}} [o]
   */
  TC.regroup = function (grid, title, change, o) {
    o = o || {};
    function find(g) { return [].filter.call(g.querySelectorAll('.ui-tile'), function (t) { var ti = t.querySelector('.ti'); return ti && ti.textContent === title; })[0]; }
    var from = find(grid), a = from && from.getBoundingClientRect(), c = grid._tc;
    var next = TC.grouped(function () { return change(c.make()); }, c.groups, c.o);
    grid.parentNode.replaceChild(next, grid);
    return Mock.sleep(80).then(function () {
      var to = find(next); if (!to || !a || o.animated === false) return Mock.sleep(500);
      var b = to.getBoundingClientRect(), sc = b.width / (to.offsetWidth || b.width) || 1;
      to.style.zIndex = 4;
      if (Mock.settings.reduceMotion) { to.style.transition = 'none'; to.style.opacity = '0'; to.getBoundingClientRect(); to.style.transition = 'opacity .2s ease-out'; to.style.opacity = '1'; }
      else {
        to.style.transition = 'none'; to.style.transform = 'translate(' + ((a.left - b.left) / sc) + 'px,' + ((a.top - b.top) / sc) + 'px)'; to.getBoundingClientRect();
        to.style.transition = 'transform .3s cubic-bezier(.2,.8,.2,1)'; to.style.transform = '';
      }
      return Mock.sleep(900);
    }).then(function () { return next; });
  };
})();
