/* TileGrid (DynamicGridLayout): the responsive tile grid. apple/Sources/HassDesign/DynamicGridLayout.swift; patterns/dynamic-grid.md.
 *
 * Column count = floor((width + spacing) / (minCellWidth + spacing)) clamped to 1...maxColumns; leftover width is shared by every track; minCellWidth
 * scales with Dynamic Type (AX5 gives one column); equalRowHeights makes every row
 * the tallest tile's height. The browser's `repeat(auto-fill, minmax())` gives exactly these rules. **Hinge-aware even columns:** with a hinge set
 * (the unfolded Duo, any pose) the count rounds DOWN to an even number, never below two (5 becomes 4, 3 becomes 2; a single track stays single), so no
 * track pair straddles the fold: measured after layout, because only the grid knows its own width.
 * Four is a FLOOR on iPad, never a cap: tile grids pass max 6 unless a design reason bounds them (Chores quick links stop at 4).
 * A tile built with `data-wide="1"` (a navigation tile that carries discs: Custom Lights, the Lights overview rooms, the Security System link) takes two tracks, as the app's content-aware tiles do.
 * **Short rows fill (duo-widths rule 1, owner 2026-11-04, every family; UKGridSolver `fill: .share`).** A row that leaves tracks unused (a lone tile, a short
 * last row, a row cut short because the next item did not fit) fills its width; no item gets less than its placed span; counts and row membership never change.
 *   A grid of ONE row shares the width equally (max-min fair: an item already wider than the equal share keeps its width), so 3 in 4 tracks are thirds.
 *   A grid of MORE THAN ONE row fills in whole tracks so every edge stays on the track lines of the other rows: spare tracks go one at a time to the
 *   narrowest item, ties to the later item (4 + 3 is 4 + 1, 1, 2; 2 in 3 tracks is 1, 2; a 1 + 2 row in 4 is 2, 2).
 *   A band is a wall: while a Duo is slightly closed (`data-posture="part"`, vertical hinge) a grid that crosses it fills each side in whole tracks, an item
 *   never crosses the band, and an empty side stays empty. Fully open there is no band, so a lone tile spans the whole row (the owner's "four-width button").
 *   A heading (`.gridheader`) or an item already spanning `1 / -1` is its own row and is untouched.
 *   `fill: 'none'` keeps short rows leading at the track width (duo-widths rule 4): set automatically for small controls (min under 100 pt,
 *   DynamicGridMetrics.controlMaxWidth) and for aspect-ratio media (every item a CameraTile `.ui-cam` or ImageCard `.ui-img`); pass it for choice chips,
 *   remote app tiles and dials.
 * props: {items:Array<Node|GlassTile props>, min?:150 (pt, scaled), max?:6, gap?:12, equal?:boolean (default true), span?:{index:2}, fill?:'share'|'none', ctx?}
 * Section-header helper: pass a PageSectionHeader node with class `gridheader` to take a whole row; in an equal-rows grid it keeps its own height (the tile rows share
 * the tallest tile, the heading rows stay `auto`). A scaled minimum wider than the container is capped at the container (AX5 gives one full-width column, never an overflow).
 */
(function () {
  var h = Mock.h;
  var CONTROL_MAX = 100;   // DynamicGridMetrics.controlMaxWidth: a grid of smaller controls never fills

  /** Max-min fair shares of `total` tracks among items whose own spans are `spans` (fractions allowed): items wider than the equal share keep their width. */
  function fairShares(spans, total) {
    var out = spans.slice(), fixed = {}, left = total, open = spans.length, changed = true;
    while (changed && open) {
      changed = false;
      var eq = left / open;
      spans.forEach(function (s, i) { if (!fixed[i] && s > eq) { fixed[i] = true; out[i] = s; left -= s; open -= 1; changed = true; } });
      if (!changed) spans.forEach(function (s, i) { if (!fixed[i]) out[i] = eq; });
    }
    return out;
  }
  /** Whole-track fill of one run: spare tracks one at a time to the narrowest item, ties to the later item. */
  function wholeTracks(run, tracks) {
    var spare = tracks - run.reduce(function (a, r) { return a + r.s; }, 0);
    while (spare > 0 && run.length) {
      var pick = 0;
      run.forEach(function (r, i) { if (r.s <= run[pick].s) pick = i; });
      run[pick].s += 1; spare -= 1;
    }
  }
  /**
   * Places the grid's items in rows exactly as auto-placement does (no dense packing), then fills the short rows (see the header).
   * @param {HTMLElement} g the grid
   * @param {number} n the track count after the hinge rounding
   * @param {boolean} band a vertical band crosses the grid (slightly closed Duo): fill each side, never across it
   */
  function fillRows(g, n, band) {
    var kids = Array.prototype.filter.call(g.children, function (c) { return c.nodeType === 1; });
    kids.forEach(function (c) { if (c.dataset.gc0 == null) c.dataset.gc0 = c.style.gridColumn || ''; c.style.gridColumn = c.dataset.gc0; });
    g.style.gridTemplateColumns = 'repeat(' + n + ',minmax(0,1fr))';
    g.dataset.fill = 'none';
    if (n < 2) return;
    var side = band && n % 2 === 0 ? n / 2 : 0, rows = [], row = null, at = 0;
    kids.forEach(function (c) {
      if (c.classList.contains('gridheader') || /^1\s*\/\s*-1$/.test(c.dataset.gc0)) { if (row) rows.push(row); row = null; at = 0; return; }
      var s = Math.min(c.classList.contains('span2') ? 2 : 1, side || n);
      if (side && at < side && at + s > side) at = side;          // never across the band: move to the trailing side
      if (!row || at + s > n) { if (row) rows.push(row); row = []; at = 0; }
      row.push({ c: c, s: s, start: at }); at += s;
    });
    if (row) rows.push(row);
    if (!rows.length) return;
    g.dataset.fill = rows.length === 1 && !side ? 'share' : 'tracks';
    if (side) {
      rows.forEach(function (r) {
        [r.filter(function (x) { return x.start < side; }), r.filter(function (x) { return x.start >= side; })].forEach(function (run, k) {
          if (!run.length) return;
          wholeTracks(run, side);
          var col = k * side;
          run.forEach(function (x) { x.c.style.gridColumn = (col + 1) + ' / span ' + x.s; col += x.s; });
        });
      });
      return;
    }
    if (rows.length === 1) {   // one row: equal shares, one template column per item
      var r0 = rows[0], used = r0.reduce(function (a, x) { return a + x.s; }, 0);
      if (used >= n) return;
      var shares = fairShares(r0.map(function (x) { return x.s; }), n);
      g.style.gridTemplateColumns = shares.map(function (f) { return 'minmax(0,' + (+f.toFixed(4)) + 'fr)'; }).join(' ');
      r0.forEach(function (x) { x.c.style.gridColumn = 'auto'; });
      return;
    }
    rows.forEach(function (r) {
      if (r.reduce(function (a, x) { return a + x.s; }, 0) >= n) return;
      wholeTracks(r, n);
      r.forEach(function (x) { x.c.style.gridColumn = 'span ' + x.s; });
    });
  }
  function TileGrid(p) {
    var g = h('div.ui-grid' + (p.equal === false ? '' : '.eq'), { style: { '--min': (p.min || 150) + 'px', '--max': p.max || 6, '--gap': (p.gap == null ? 12 : p.gap) + 'px' } });
    (p.items || []).forEach(function (it, i) { var n = it && it.nodeType ? it : Mock.components.GlassTile(it); if ((p.span && p.span[i] === 2) || n.dataset.wide === '1') n.classList.add('span2'); g.appendChild(n); });
    var min = p.min || 150, gap = p.gap == null ? 12 : p.gap, max = p.max || 6;
    var media = p.items && p.items.length && Array.prototype.every.call(g.children, function (c) { return c.classList.contains('ui-cam') || c.classList.contains('ui-img'); });
    var fill = p.fill || (min < CONTROL_MAX || media ? 'none' : 'share');
    g.dataset.fillMode = fill;
    if (window.ResizeObserver) {
      var frame = 0, lastW = -1, lastSc = -1;
      /** Applies the hinge rounding and, for an equal-rows grid with section headers, the row tracks. Runs a frame after the observer fires, and only when the
       *  width or the text scale changed, so writing the tracks never feeds the observer inside the same frame (no "ResizeObserver loop" warning). */
      var apply = function () {
        frame = 0;
        var screen = g.closest('.screen, .k-plain');
        var w = g.clientWidth, sc = parseFloat(screen ? getComputedStyle(screen).getPropertyValue('--sc') : 1) || 1;
        if (!w || (w === lastW && sc === lastSc)) return;
        lastW = w; lastSc = sc;
        var n = Math.max(1, Math.min(max, Math.floor((w + gap) / (Math.min(w, min * sc) + gap))));   // a minimum wider than the container is capped at the container
        g.dataset.cols = n;
        var hinge = screen && screen.dataset.hinge && !g.closest('[data-fold="columns"]');   // a grid wholly on one side of the fold keeps its own columns (crossesFold false)
        if (hinge && n >= 2 && n % 2) { n -= 1; g.dataset.even = 'true'; }   // DynamicGridMetrics.evenRounded
        if (hinge) g.style.gridTemplateColumns = 'repeat(' + n + ',minmax(0,1fr))';
        g.dataset.cols = n;
        if (fill === 'share') fillRows(g, n, !!(hinge && screen.dataset.hinge === 'v' && screen.dataset.posture === 'part'));
        // equalRowHeights with heading rows: tile rows share the tallest tile's height, a header row (.gridheader) keeps its own height.
        if (g.classList.contains('eq') && g.querySelector(':scope > .gridheader')) {
          var cols = hinge ? n : (getComputedStyle(g).gridTemplateColumns.split(' ').length || n), rows = [], at = 0;
          Array.prototype.forEach.call(g.children, function (c) {
            if (c.classList.contains('gridheader')) { if (at) rows.push('1fr'); rows.push('auto'); at = 0; return; }
            var span = c.classList.contains('span2') ? Math.min(2, cols) : 1;
            if (at + span > cols) { rows.push('1fr'); at = 0; }
            at += span;
          });
          if (at) rows.push('1fr');
          g.style.gridTemplateRows = rows.join(' ');
          g.style.gridAutoRows = 'auto';
        }
      };
      var ro = new ResizeObserver(function () { if (!frame) frame = requestAnimationFrame(apply); });
      ro.observe(g);
    }
    return g;
  }
  var sample = ['Kitchen', 'Office', 'Gym', 'Guest Room', 'Hallway', 'Garage', 'Back Deck'].map(function (n) { return { title: n + ' Light', subtitle: 'Off', symbol: 'lightbulb', family: 'lights' }; });
  function demo(n, p) { return { items: sample.slice(0, n), min: p.min, max: p.max }; }
  Mock.register('TileGrid', TileGrid, { source: 'apple/Sources/HassUI/UIKitPort/Design/UKDynamicGrid.swift', props: '{items, min, max, gap, equal, span, fill}',
    variants: [{ id: 'default', label: 'min 150, max 6 (short last row in whole tracks)', props: Object.assign(demo(7, {}), {}) }, { id: 'one-row', label: 'one row of 3 (equal shares)', props: demo(3, { max: 4 }) },
      { id: 'lone', label: 'a lone tile spans its row', props: demo(1, { max: 4 }) }, { id: 'max2', label: 'max 2 (room page sections)', props: demo(3, { max: 2, min: 150 }) },
      { id: 'wide', label: 'min 240 (wide cards)', props: demo(4, { min: 240, max: 3 }) }, { id: 'none', label: "fill: 'none' (choice chips, aspect media)", props: Object.assign(demo(3, { max: 4 }), { fill: 'none' }) }],
    states: [{ id: 'default', label: 'Fills to the width; columns follow Dynamic Type and the hinge; short rows fill their section', props: demo(7, {}) }] });
  Mock.components.DynamicGrid = TileGrid;
})();
