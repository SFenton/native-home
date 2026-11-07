/* Food batch helper: the pieces of the Food hub, Recipes grid and recipe detail that the kit does not have, built from kit parts.
 * Loaded by every mockup of the `food` batch with <script src="...pages/food/_food.js"> AFTER kit.js. Local to the batch (AUTHORING.md: a shared helper lives beside
 * the mockups). Promote to kit: SuggestedRecipesCarousel, RecipeIngredientRow (+ ChipFlow, RecipeFactRow, GroceryAction), ContentUnavailable, the expanded floating
 * search, the recipe detail pane, ten symbols (book, carrot, frying.pan, ...), the title ellipsis rule in `.ui-mhead`.
 *
 * Source of truth for every number here: apple/Sources/HassUI/Features/Food/*.swift (FoodHubScreen, RecipesScreen, RecipeDetailView, RecipeDetailRows,
 * SuggestedRecipesCarousel), HassCore/Recipes/RecipeFormatting.swift and HassUI/Features/Gallery/FoodGallery.swift (fixture titles, ingredients, steps).
 * Sample data is fixture data: no real recipes, photos or inventory.
 */
(function () {
  'use strict';
  if (window.Food) return;
  var h = Mock.h, I = Mock.icon;
  function K() { return Mock.components; }
  var F = window.Food = {};

  /* ---------------------------------------------------------------- symbols the kit lacks (SF Symbol names FoodSymbols and the recipe sheet use) */
  function path(d) { return '<path d="' + d + '"/>'; }
  function circ(x, y, r) { return '<circle cx="' + x + '" cy="' + y + '" r="' + r + '"/>'; }
  function rect(x, y, w, hh, r) { return '<rect x="' + x + '" y="' + y + '" width="' + w + '" height="' + hh + '" rx="' + (r || 0) + '"/>'; }
  var NEW = {
    'book': path('M12 6.6C10.2 5.2 7.2 4.7 4 5.2v12.6c3.2-.5 6.2 0 8 1.4 1.8-1.4 4.8-1.9 8-1.4V5.2c-3.2-.5-6.2 0-8 1.4zM12 6.6v12.6'),
    'carrot': path('M13.4 6.6l4 4L5 19z') + path('M15.4 8.6 18 6M16.4 9.6l3-1.6M14.4 7.6 16 5') + path('M9.5 12.5l2 2M7.5 15.5l1.5 1.5'),
    'frying.pan': circ(10, 13.5, 6.5) + circ(10, 13.5, 3.4) + path('M15.4 9.2 21 5'),
    'takeoutbag.and.cup.and.straw': path('M4.5 9h9.5l-.9 11H5.4z') + path('M6.8 9V7a2.5 2.5 0 0 1 5 0v2') + path('M16.5 12h3.6l-.5 8h-2.6z M17.4 12V9.5l1.6-1'),
    'hand.raised': rect(7, 10.5, 10, 9, 3) + path('M8.8 10.5V6M11.1 10.5V4.5M13.4 10.5V5M15.7 10.5V7M7 14.2 5 12.4'),
    'pause.circle': circ(12, 12, 8.5) + path('M10 9v6M14 9v6'),
    'character.bubble': path('M5 5h14a1.5 1.5 0 0 1 1.5 1.5v8A1.5 1.5 0 0 1 19 16h-6.5L8 20v-4H5a1.5 1.5 0 0 1-1.5-1.5v-8A1.5 1.5 0 0 1 5 5z') + path('M9 13l2-5 2 5M9.8 11.5h2.4'),
    'arrow.up.right.square': path('M13 4.5h6.5V11M19.5 4.5 11 13M17.5 14v4.5a1.5 1.5 0 0 1-1.5 1.5H5.5A1.5 1.5 0 0 1 4 18.5V8a1.5 1.5 0 0 1 1.5-1.5H10'),
    'circle': circ(12, 12, 8.5),
    'list.bullet': circ(4.8, 7, 1) + circ(4.8, 12, 1) + circ(4.8, 17, 1) + path('M9.5 7h10.5M9.5 12h10.5M9.5 17h10.5'),
    'list.number': path('M9.5 7h10.5M9.5 12h10.5M9.5 17h10.5M4.5 5.6l1.5-1V9.4M4.3 13.4h2.6l-2.6 3.1h2.6'),
  };
  Object.keys(NEW).forEach(function (n) { if (!Mock.symbols[n]) Mock.symbols[n] = NEW[n]; });
  if (Mock.missingIcons) ['book', 'carrot', 'frying.pan', 'takeoutbag.and.cup.and.straw', 'hand.raised', 'pause.circle', 'character.bubble', 'arrow.up.right.square', 'circle', 'list.bullet', 'list.number'].forEach(function (n) { delete Mock.missingIcons[n]; });

  /* ---------------------------------------------------------------- local CSS (kit tokens only; prefix fd-) */
  var css = [
    /* a one-line inline title ellipsises like a system navigation bar title */
    '.ui-mhead .ct .ti { white-space: nowrap; overflow: hidden; text-overflow: ellipsis; max-width: 100%; flex: none; }',
    /* the atlas page's `.k-wrap h1/h2/p` rules reach inside the device frame (promote to kit: scope them); restore the app's type */
    '.k-wrap .ui-t-large { font: 700 var(--fs-lt)/1.2 var(--font-d); letter-spacing: .01em; margin: 0; }',
    '.k-wrap .ui-hdr h2 { font: 700 var(--fs-t3)/1.2 var(--font-d); letter-spacing: 0; margin: 0; }',
    '.k-wrap .ui-formhead { margin: 0 0 8px 16px; max-width: none; } .k-wrap .ui-formfoot { margin: 8px 16px 0; max-width: none; }',
    '.k-wrap .screen p, .k-wrap .k-swatch p, .k-wrap .k-plain p { max-width: none; }',
    '.ui-img.row .thumb { width: 72px; height: 72px; }',
    '.fd-stack { display: flex; flex-direction: column; gap: 24px; min-width: 0; }',
    '.fd-col { flex: 1 1 0; min-width: 0; display: flex; flex-direction: column; gap: 24px; }',
    '.fd-sec { display: flex; flex-direction: column; gap: 12px; min-width: 0; }',
    /* suggested recipes carousel */
    '.fd-inner { display: flex; flex-direction: column; gap: 8px; min-width: 0; }',
    '.fd-vp { position: relative; } .fd-vp.clip { overflow: hidden; }',
    '.fd-strip { display: flex; align-items: flex-start; will-change: transform; }',
    '.fd-page { flex: none; box-sizing: border-box; padding-right: 10px; display: grid; gap: 10px; align-items: start; }',
    '.fd-ph { aspect-ratio: 1 / .78; border-radius: 22px; background: var(--g-module-thin); }',
    '.k-reduce-transparency .fd-ph { background: #1C1C1E; }',
    '.fd-dots { display: flex; justify-content: center; align-items: center; gap: 8px; min-height: 44px; }',
    '.fd-dots i { width: 7px; height: 7px; border-radius: 50%; background: rgba(235, 235, 245, .24); display: block; } .fd-dots i.on { background: #fff; }',
    '.fd-cell { position: relative; min-width: 0; }',
    '.fd-cell.sel::after { content: ""; position: absolute; inset: 0; border-radius: 22px; box-shadow: inset 0 0 0 3px #409CFF; pointer-events: none; }',
    /* ContentUnavailableView, and the Recipes empty block */
    '.fd-cuv { display: flex; flex-direction: column; align-items: center; text-align: center; gap: 8px; padding: 24px 16px; color: var(--ink, #fff); }',
    '.fd-cuv .gl { font-size: 44px; color: var(--fd-sec, rgba(235, 235, 245, .6)); line-height: 1; } .fd-cuv .gl .ui-sym { width: 1em; height: 1em; }',
    '.fd-cuv .ti { font: 700 var(--fs-t3)/1.2 var(--font-d); margin: 0; } .fd-cuv .ds { margin: 0; font-size: var(--fs-body); color: var(--fd-sec, rgba(235, 235, 245, .6)); }',
    '.fd-cuv .act { margin-top: 8px; }',
    '.in-sheet { --fd-sec: var(--ink-sheet-2); } .g-dark, .screen { --fd-sec: rgba(235, 235, 245, .7); }',
    '.in-sheet .fd-cuv .ds { color: var(--ink-sheet-2); }',
    '.fd-empty { display: flex; flex-direction: column; align-items: center; text-align: center; gap: 12px; padding: 72px 24px 24px; }',
    '.fd-empty .gl { font-size: var(--fs-lt); color: var(--fd-sec); line-height: 1; } .fd-empty .ti { font: 700 var(--fs-t2)/1.2 var(--font-d); } .fd-empty .ds { color: var(--fd-sec); font-size: var(--fs-body); }',
    /* recipes grid */
    '.fd-sorted { color: var(--g-secondary-on-wallpaper); font-size: var(--fs-body); margin: 0; }',
    '.fd-grid { display: grid; gap: 12px; align-items: start; }',
    '.fd-footer { display: flex; flex-direction: column; align-items: center; gap: 8px; padding: 12px 0 24px; font-size: var(--fs-body); color: var(--g-secondary-on-wallpaper); }',
    '.fd-retry { min-height: 44px; padding: 0 20px; border-radius: 999px; border: 0; background: color-mix(in srgb, #409CFF 20%, transparent); color: #409CFF; font: 600 var(--fs-body)/1.2 var(--font); cursor: pointer; }',
    '.fd-xs { flex: 1; display: flex; align-items: center; gap: 8px; padding-left: 16px; min-height: 52px; border-radius: 999px; color: #fff; }',
    '.fd-xs .ui-sym { width: 20px; height: 20px; color: var(--g-secondary-on-wash); }',
    '.fd-xs input { flex: 1; min-width: 0; background: none; border: 0; outline: 0; color: #fff; font: inherit; font-size: var(--fs-body); }',
    '.fd-xs button { width: 44px; height: 44px; display: grid; place-items: center; background: none; border: 0; color: var(--g-secondary-on-wash); cursor: pointer; font-size: var(--fs-t3); }',
    /* the split pane */
    '.fd-pane { position: absolute; z-index: 12; background: #000; color: #fff; display: flex; flex-direction: column; border-left: .5px solid rgba(255, 255, 255, .22); }',
    '.fd-pane .hd { display: flex; align-items: baseline; gap: 12px; padding: 8px 16px; flex: none; }',
    '.fd-pane .hd h2 { margin: 0; flex: 1; min-width: 0; font: 600 var(--fs-hd)/1.25 var(--font); }',
    '.fd-pane .hd .ui-circle { align-self: center; }',
    '.fd-pane .dv { height: .5px; background: rgba(255, 255, 255, .22); flex: none; }',
    '.fd-pane .bd { flex: 1 1 auto; min-height: 0; overflow-y: auto; scrollbar-width: none; padding: 12px 16px 16px; }',
    '.fd-pane .bd::-webkit-scrollbar { display: none; } .fd-pane .tb { flex: none; padding: 8px 16px; }',
    /* recipe detail content */
    '.fd-dc { display: flex; flex-direction: column; gap: 24px; min-width: 0; }',
    '.fd-center { min-height: 100%; display: flex; flex-direction: column; justify-content: center; gap: 24px; }',
    '.fd-hero { aspect-ratio: 16 / 10; border-radius: 26px; background: var(--sheet-cell); position: relative; overflow: hidden; display: grid; place-items: center; }',
    '.fd-hero .ph { position: absolute; inset: 0; } .fd-hero .gl { position: relative; font-size: var(--fs-lt); color: var(--fd-sec); }',
    '.fd-lhead { font: 600 var(--fs-sub)/1.2 var(--font); color: var(--ink-sheet-2); margin: 0 0 8px 16px; }',
    '.fd-lhead.quiet { font-weight: 400; }',
    '.fd-block { display: flex; flex-direction: column; min-width: 0; }',
    '.fd-fact .acc { color: var(--ink-sheet-2); text-align: right; font-size: var(--fs-body); } .ts-ax5 .fd-fact .acc { text-align: left; }',
    '.fd-link { color: var(--ink-action); } .fd-link .rg { color: var(--ink-action) !important; }',
    '.fd-ing { align-items: flex-start; } .fd-ing .tx { gap: 8px; } .fd-ing .rg { font-size: var(--fs-t3); align-self: flex-start; }',
    '.fd-mark.on { color: #30D158 !important; } .g-light .fd-mark.on { color: #34C759 !important; } .fd-mark.off { color: var(--ink-sheet-2) !important; }',
    '.fd-ing .ti { color: var(--ink); } .fd-ing .note { font-size: var(--fs-foot); color: var(--ink-sheet-2); }',
    '.fd-chips { display: flex; flex-wrap: wrap; gap: 8px; }',
    '.fd-chip { font-size: var(--fs-foot); color: var(--ink-sheet-2); padding: 4px 8px; border-radius: 999px; background: rgba(142, 142, 147, .16); line-height: 1.25; }',
    '.fd-step { display: flex; align-items: baseline; gap: 12px; padding: 12px 16px; min-height: 52px; width: 100%; box-sizing: border-box; position: relative; }',
    '.fd-step + .fd-step::before { content: ""; position: absolute; top: 0; right: 0; left: 16px; height: .5px; background: var(--sep); }',
    '.fd-step b { font-weight: 600; font-variant-numeric: tabular-nums; color: var(--ink-sheet-2); font-size: var(--fs-body); } .fd-step span { flex: 1; font-size: var(--fs-body); color: var(--ink); }',
    '.fd-notice { display: flex; gap: 8px; align-items: flex-start; font-size: var(--fs-foot); color: var(--ink-sheet-2); } .fd-notice .ui-sym { margin-top: 2px; }',
    '.fd-lr { display: flex; align-items: center; gap: 12px; min-height: 52px; padding: 12px 16px; color: var(--ink-action); font-size: var(--fs-body); width: 100%; background: none; border: 0; text-align: left; cursor: pointer; }',
    '.fd-lr .rg { width: calc(28px * var(--sc)); display: grid; place-items: center; flex: none; }',
    '.fd-gro { display: flex; flex-direction: column; gap: 8px; } .fd-gro .why { font-size: var(--fs-foot); color: var(--ink-sheet-2); margin: 0; }',
    '.fd-gro .done { display: flex; align-items: center; justify-content: center; gap: 8px; min-height: 44px; font: 600 var(--fs-hd)/1.25 var(--font); color: var(--ink); } .fd-gro .done .ui-sym { color: #30D158; } .g-light .fd-gro .done .ui-sym { color: #34C759; }',
    '.fd-gro .ui-primary .ui-arc { margin-right: 0; }',
    /* filter sheet rows */
    '.fd-sl { flex-direction: column; align-items: stretch !important; gap: 8px; padding: 12px 16px; } .fd-sl .top { display: flex; justify-content: space-between; gap: 8px; align-items: baseline; }',
    '.fd-sl .top .va { font-variant-numeric: tabular-nums; color: var(--ink-sheet-2); } .fd-dis { opacity: .5; }',
    '.ui-field > .ui-seg { flex: 1; }',
    '.fd-phsym { position: absolute; inset: 0; display: grid; place-items: center; font-size: var(--fs-lt); color: rgba(235, 235, 245, .6); } .fd-phsym .ui-sym { width: 1em; height: 1em; }',
    '.fd-lbl { display: flex; align-items: center; gap: 8px; flex: 1; }',
    '.fd-lbl .ui-sym { color: var(--ink-sheet-2); }',
  ].join('\n');
  var st = document.createElement('style'); st.textContent = css; document.head.appendChild(st);

  /* ---------------------------------------------------------------- fixtures (FoodGallery.swift) */
  F.titles = ['Lemon Garlic Chicken', 'Tomato Basil Soup', 'Mushroom Risotto', 'Black Bean Tacos', 'Spinach Lasagna', 'Thai Green Curry', 'Banana Bread', 'Shakshuka', 'Chicken Tikka Masala', 'Caesar Salad',
    'Beef Stir-Fry', 'Pumpkin Pancakes', 'Vegetable Paella', 'Pesto Pasta', 'French Onion Soup', 'Salmon Teriyaki', 'Chili Con Carne', 'Greek Lemon Potatoes', 'Apple Crumble', 'Fried Rice'];
  /** Card i (0-based) as FoodFixtures.catalog builds it: required 4 + i%7, matched = max(0, required - i%5). */
  F.card = function (i) {
    var round = Math.floor(i / 20), req = 4 + i % 7, matched = Math.max(0, req - i % 5);
    return { id: i + 1, title: F.titles[i % 20] + (round ? ' ' + (round + 1) : ''), req: req, matched: matched, text: matched + ' of ' + req + ' Ingredients', cookidoo: i % 4 === 0 };
  };

  /** The card indices (0...119, FoodFixtures.catalog) in the order FixtureRecipeService answers: availability (coverage desc), expiring soon, alphabetical; ties by id. */
  F.order = function (sort, n, query) {
    var all = []; for (var i = 0; i < 120; i++) { var c = F.card(i); c.i = i; c.cov = c.matched / c.req * 100; c.exp = i % 3 === 0 ? i % 9 : 99999; all.push(c); }
    if (query) all = all.filter(function (c) { return c.title.toLowerCase().indexOf(query.toLowerCase()) >= 0; });
    all.sort(function (a, b) {
      var k = sort === 'alphabetical' ? (a.title < b.title ? -1 : a.title > b.title ? 1 : 0) : (sort === 'expiry' ? a.exp - b.exp : b.cov - a.cov);
      return k || a.id - b.id;
    });
    return all.slice(0, n || 12).map(function (c) { return c.i; });
  };
  var HUES = [38, 12, 32, 96, 8, 118, 44, 4, 24, 128];
  /** A stand-in recipe photo: a warm radial, a different hue per recipe (the kit's recipe scene is one orange). */
  F.photo = function (i) {
    var hue = HUES[i % HUES.length];
    return 'radial-gradient(70% 70% at ' + (30 + (i * 13) % 40) + '% 40%, hsl(' + hue + ' 62% 56%), hsl(' + hue + ' 56% 30%) 70%, hsl(' + hue + ' 40% 13%))';
  };
  function paint(node, i) {
    var p = node.querySelector('.photo, .thumb'); if (p) p.style.background = F.photo(i);
    return node;
  }
  F.imageCard = function (ctx, i, o) {
    o = o || {};
    var c = F.card(i);
    var node = K().ImageCard({ title: o.title || c.title, subtitle: o.subtitle === false ? null : o.subtitle, scene: 'recipe', ctx: ctx });
    node.setAttribute('aria-label', (o.title || c.title) + (o.subtitle ? ', ' + o.subtitle : '') + '. Opens recipe details');
    return paint(node, i);
  };

  /* ---------------------------------------------------------------- headers and notices */
  F.section = function (title, content, detail) { return h('div.fd-sec', K().PageSectionHeader({ title: title, detail: detail }), content); };
  /** ContentUnavailableView: a large secondary symbol, a bold title and a secondary description. */
  F.cuv = function (symbol, title, description, action) {
    return h('div.fd-cuv', { role: 'group', 'aria-label': title + (description ? '. ' + description : '') }, h('span.gl', { html: I(symbol) }), h('h3.ti', title), description ? h('p.ds', description) : null, action ? h('div.act', action) : null);
  };
  F.notice = function (text) { return h('div.fd-notice', { role: 'status' }, h('span', { html: I('info.circle') }), h('span', text)); };
  F.lhead = function (text, quiet) { return h('div.fd-lhead' + (quiet ? '.quiet' : ''), { role: 'heading', 'aria-level': '2' }, text); };

  /** ContentGate with the spinner's VoiceOver label ("Loading Food & Recipes"); the label is spoken, never drawn (ContentGate.swift). */
  F.gate = function (phase, content, label, height) {
    var g = K().ContentGate({ phase: phase, content: content });
    var arc = g.querySelector('.ui-arc'); if (arc) arc.setAttribute('aria-label', label || 'Loading');
    if (height) { g.style.minHeight = height + 'px'; }
    return g;
  };

  /* ---------------------------------------------------------------- Suggested Recipes carousel (SuggestedRecipesCarousel.swift) */
  /** Columns and rows for a width (web recommendationLayout; SuggestedRecipesCarousel.layout). */
  F.layout = function (w, ax) {
    var sp = 10;
    if (ax) return { cols: Math.min(10, Math.max(1, Math.floor((w + sp) / (440 + sp)))), rows: 2 };
    return { cols: Math.min(10, Math.max(2, Math.ceil((w + sp) / (220 + sp)))), rows: w >= 900 ? 2 : 3 };
  };
  /**
   * The carousel: header with "Page n of 5", pages of ImageCards, dots. props: {ctx, phase:'ready'|'loading'|'failed'|'empty', page, clips, width, long}.
   * Pages clip to the carousel's own width when it shares a row (split columns) or at accessibility sizes; otherwise the next page peeks into the margin.
   * The returned node has .go(n, animate) (the VoiceOver adjustable action: standard 0.3 s, a jump under Reduce Motion) and .pageCount().
   */
  F.carousel = function (o) {
    var ctx = o.ctx || Mock.current, ax = !!ctx.axSize, phase = o.phase || 'ready', page = o.page || 0, clipped = !!o.clips || ax;
    var width0 = o.width || (ctx.contentW - 32), curW = width0, pages = 5;
    var strip = h('div.fd-strip'), vp = h('div.fd-vp' + (clipped ? '.clip' : ''), strip);
    var dots = h('div.fd-dots', { role: 'slider', 'aria-label': 'Suggestion page', tabindex: 0 });
    var header = K().PageSectionHeader({ title: o.title || 'Suggested Recipes', detail: phase === 'failed' ? null : 'Page 1 of 5' });
    var inner = h('div.fd-inner');
    var root = h('div.fd-sec', { role: 'group', 'aria-label': 'Suggested recipes', dataset: { phase: phase } }, header, inner);
    if (phase === 'failed') { inner.appendChild(F.cuv('fork.knife', 'Suggestions Unavailable', 'Suggested recipes are temporarily unavailable.')); return root; }
    inner.appendChild(vp);
    function setDetail() {
      var d = header.querySelector('.detail');
      if (pages > 1) { if (!d) { d = h('span.detail'); header.appendChild(d); } d.textContent = 'Page ' + (page + 1) + ' of ' + pages; } else if (d) d.remove();
      dots.setAttribute('aria-valuemin', 1); dots.setAttribute('aria-valuemax', pages); dots.setAttribute('aria-valuenow', page + 1); dots.setAttribute('aria-valuetext', (page + 1) + ' of ' + pages);
      Array.prototype.forEach.call(dots.children, function (d2, k) { d2.classList.toggle('on', k === page); });
    }
    function build(w) {
      var L = F.layout(w, ax), size = L.cols * L.rows;
      pages = phase === 'ready' ? Math.max(1, Math.min(5, Math.ceil(40 / size))) : (phase === 'empty' ? 1 : 5);
      page = Math.min(page, pages - 1);
      strip.innerHTML = '';
      for (var pg = 0; pg < pages; pg++) {
        var g = h('div.fd-page', { style: { width: w + 'px', gridTemplateColumns: 'repeat(' + L.cols + ',minmax(0,1fr))' }, dataset: { page: pg } });
        for (var slot = 0; slot < size; slot++) {
          var idx = pg * size + slot;
          if (phase === 'ready') { if (idx < 40) g.appendChild(h('div.fd-cell', F.imageCard(ctx, idx, { title: o.long && idx === 1 ? 'Slow-Cooked Pulled Pork Sandwiches With Pickled Onions and a Very Long Title' : undefined, subtitle: false }))); }
          else if (phase === 'loading') g.appendChild(h('div.fd-ph', { 'aria-hidden': 'true' }));
        }
        strip.appendChild(g);
      }
      dots.innerHTML = ''; if (pages > 1) for (var k = 0; k < pages; k++) dots.appendChild(h('i'));
      strip.style.transform = 'translateX(' + (-page * w) + 'px)';
      setDetail();
    }
    build(width0);
    if (pages > 1) inner.appendChild(dots);
    if (window.ResizeObserver) new ResizeObserver(function () { var w = vp.clientWidth; if (w && Math.abs(w - curW) > 1) { curW = w; build(w); } }).observe(vp);
    root.pageCount = function () { return pages; };
    root.go = function (n, animate) {
      var from = -page * curW; page = Math.max(0, Math.min(pages - 1, n)); var to = -page * curW;
      setDetail();
      var reduce = !!Mock.settings.reduceMotion;
      if (animate && !reduce && strip.animate) {
        var a = strip.animate([{ transform: 'translateX(' + from + 'px)' }, { transform: 'translateX(' + to + 'px)' }], { duration: Mock.anim.ms.standard(), easing: Mock.anim.easing.standard, fill: 'both' });
        a.finished.then(function () { strip.style.transform = 'translateX(' + to + 'px)'; a.cancel(); }, function () {});
      } else strip.style.transform = 'translateX(' + to + 'px)';
      return Mock.sleep(animate && !reduce ? Mock.anim.ms.standard() + 40 : 40);
    };
    return root;
  };

  /* ---------------------------------------------------------------- Food hub (FoodHubScreen.swift) */
  var SPACES = [
    { title: 'Pantry', sub: '61 Items • 1 Expiring Soon', symbol: 'fork.knife', family: 'pantry', loc: 'shelf' },
    { title: 'Fridge', sub: '38 Items • 2 Expiring Soon', symbol: 'refrigerator', family: 'fridge', loc: 'cooler' },
    { title: 'Freezer', sub: '22 Items • 1 Expiring Soon', symbol: 'snowflake', family: 'freezer', loc: 'freezer' },
    { title: 'Spice Rack', sub: '17 Items • 0 Expiring Soon', symbol: 'takeoutbag.and.cup.and.straw', family: 'spice', loc: 'spice_rack' },
    { title: 'Cabinet', sub: '5 Items • 0 Expiring Soon', symbol: 'cabinet', family: 'cabinet', loc: 'cabinet' },
  ];
  F.spaces = SPACES;
  /** The pieces of the hub in the order the code stacks them: recipe sections then inventory sections. o: {phase, page, allFood, spaces, pending, long} */
  F.hubParts = function (ctx, o) {
    o = o || {};
    var split = !!ctx.canSplit;
    var colW = split ? (ctx.contentW - 32 - 24) / 2 : ctx.contentW - 32;
    var car = F.carousel({ ctx: ctx, phase: o.phase || 'ready', page: o.page || 0, clips: split, width: colW, long: o.long });
    var all = K().GlassTile({ title: 'All Recipes', symbol: 'book', family: 'recipes', isActive: true, kind: 'navigate' });
    all.setAttribute('data-id', 'food.allRecipes');
    var tiles = function (list) { return K().TileGrid({ min: 150, max: 4, equal: true, items: list }); };
    var allFood = F.section('All Food', tiles([{ title: 'All Food', subtitle: o.allFood || '143 Items • 4 Expiring Soon', symbol: 'carrot', family: 'food', isActive: true, kind: 'navigate', pending: o.pending }]));
    var spaces = F.section('Food Spaces', tiles(SPACES.map(function (s) { return { title: s.title, subtitle: (o.spaces && o.spaces[s.loc]) || s.sub, symbol: s.symbol, family: s.family, isActive: true, kind: 'navigate', pending: o.pending }; })));
    return { recipe: [car, all], inventory: [allFood, spaces], carousel: car };
  };
  /** Two equal columns with a 24 pt gap (HStack, spacing xl): the code does NOT use SplitPolicy.geometry here, so the hinge band is not honoured. */
  F.split50 = function (left, right) { return h('div', { style: { display: 'flex', gap: '24px', alignItems: 'flex-start' } }, h('div.fd-col', left), h('div.fd-col', right)); };
  F.hubBody = function (ctx, o) {
    var parts = F.hubParts(ctx, o);
    return ctx.canSplit ? [F.split50(parts.recipe, parts.inventory)] : parts.recipe.concat(parts.inventory);
  };
  /** The hub as a pushed page under Home (Quick Links opens it; HomeRoute.food). o: {phase, page, gate:'spinner'|'loading'|null, page:{...Mock.page opts}} */
  F.hubPage = function (ctx, o) {
    o = o || {};
    var body = F.hubBody(ctx, o);
    if (o.gate) {
      var gate = F.gate(o.gate, h('div.fd-stack', body), 'Loading Food & Recipes');
      gate.style.height = Math.round(ctx.h - ctx.device.barTop - 150) + 'px'; gate.style.overflow = 'hidden';
      body = [gate];
    }
    return Mock.page(ctx, Object.assign({ title: 'Food & Recipes', section: 'home', back: 'Home', badge: 3, choresBadge: 2, body: body }, o.pageOpts));
  };

  /* ---------------------------------------------------------------- Recipes grid (RecipesScreen.swift) */
  F.sortSummary = function (sort) { return sort === 'alphabetical' ? 'Sorted Alphabetically' : 'Sorted by ' + (sort === 'expiry' ? 'Expiring Soon' : 'Ingredients Available'); };
  /** Columns for a width: 160 pt cards, at least two, up to 8; at accessibility sizes 320 pt cells and no minimum (RecipeGrid.columnCount). */
  F.gridCols = function (w, ax) { var n = Math.max(1, Math.min(8, Math.floor((w + 12) / ((ax ? 320 : 160) + 12)))); return ax ? n : Math.max(2, n); };
  F.floatingBar = function (ctx, o) {
    o = o || {};
    var K2 = K();
    if (o.searchOpen) {
      var inp = h('input', { type: 'text', value: o.query || '', placeholder: 'Search recipes', 'aria-label': 'Search recipes' });
      return h('div.ui-fab', { role: 'toolbar' }, h('div.ui-glass.fd-xs', h('span', { html: I('magnifyingglass') }), inp, h('button', { type: 'button', 'aria-label': 'Close Search', html: I('xmark') })));
    }
    var bar = K2.FloatingActionBar({ ctx: ctx, search: { prompt: 'Search recipes', text: o.query || '' }, actions: [
      { id: 'sort', title: 'Sort', symbol: 'arrow.up.arrow.down', showsTitle: false, active: !!o.sortActive },
      { id: 'filter', title: 'Filter', symbol: 'line.3.horizontal.decrease', showsTitle: false, active: !!o.filterActive }] });
    var s = bar.querySelector('.search'); if (s && o.query) s.style.color = '#fff';
    return bar;
  };
  /**
   * The results region. o: {width (content width of the column), count, selected, sort, footer:'loading'|'failed'|'hydrating'|null, long, phase:'loaded'|'failed'|'empty'|'empty-search'|'loading'|'reload'}
   * Everything sits in a results ContentGate; the floating bar stays outside it.
   */
  F.results = function (ctx, o) {
    var ax = !!ctx.axSize, phase = o.phase || 'loaded', inner;
    var colW = o.width || ctx.contentW;
    if (phase === 'failed') inner = h('div', { style: { minHeight: Math.round(ctx.h - ctx.device.barTop - 330) + 'px', display: 'flex', alignItems: 'center', justifyContent: 'center' } }, F.cuv('exclamationmark.triangle', 'Unable to Load Recipes', null, K().PrimaryButton({ title: 'Retry', inline: true })));
    else if (phase === 'empty' || phase === 'empty-search') inner = h('div.fd-empty', h('span.gl', { html: I('magnifyingglass'), 'aria-hidden': 'true' }), h('h3.ti', 'No Recipes Found'), h('p.ds', phase === 'empty' ? 'No recipes matched the current filters.' : 'Try a different search or loosen the recipe filters.'));
    else {
      var cols = F.gridCols(colW - 32, ax), grid = h('div.fd-grid', { style: { gridTemplateColumns: 'repeat(' + cols + ',minmax(0,1fr))' } });
      for (var i = 0; i < (o.count || 12); i++) {
        var order = o.order || F.order(o.sort || 'availability', o.count || 12, o.query), idx = order[i]; if (idx == null) break; var c = F.card(idx);
        var title = o.long && i === 1 ? 'Slow-Cooked Pulled Pork Sandwiches With Pickled Onions and a Very Long Title' : undefined;
        grid.appendChild(h('div.fd-cell' + (o.selected === idx ? '.sel' : ''), { 'aria-selected': o.selected === idx ? 'true' : null }, F.imageCard(ctx, idx, { title: title, subtitle: c.text })));
      }
      var foot = null;
      if (o.footer === 'failed') foot = h('div.fd-footer', h('span', 'Unable to load more recipes.'), h('button.fd-retry', { type: 'button' }, 'Retry'));
      else if (o.footer === 'loading' || o.footer === 'hydrating') foot = h('div.fd-footer', K().ArcProgress({ label: o.footer === 'hydrating' ? 'Finding more recipes' : 'Loading more recipes', size: 'compact' }));
      inner = h('div.fd-stack', { style: { gap: '12px' } }, h('div.fd-sorted', F.sortSummary(o.sort || 'availability')), grid, foot);
    }
    var gatePhase = phase === 'loading' || phase === 'reload' ? 'spinner' : 'ready';
    var gate = F.gate(gatePhase, inner, 'Loading Recipes');
    if (gatePhase === 'spinner' || phase === 'failed' || phase === 'empty' || phase === 'empty-search') { gate.style.minHeight = Math.round(ctx.h - ctx.device.barTop - 330) + 'px'; }
    return gate;
  };
  /** The Recipes page. o: {phase, sort, sortActive, filterActive, query, searchOpen, footer, selected, detail:{tab,...}, count, long, connection, pageOpts} */
  F.recipesPage = function (ctx, o) {
    o = o || {};
    var pane = !!(o.detail && ctx.canSplit), g = ctx.splitGeometry;
    /* The page narrows to the leading pane; the detail pane fills the rest. Today the code splits into two equal halves (RecipesPage reads SplitPolicy.allowsSplit only);
       with the owner's 2026-10-24 hinge rule (in flight) the divider is the hinge band while a Duo is slightly closed and the midpoint of the free space otherwise. */
    var leftW = pane ? (g ? g.leading : Math.floor(ctx.contentW / 2)) : ctx.contentW;
    var gate = F.results(ctx, Object.assign({ width: leftW, selected: pane ? o.selected : null }, o));
    var bar = F.floatingBar(ctx, { query: o.query, searchOpen: o.searchOpen, sortActive: o.sortActive, filterActive: o.filterActive });
    var page = Mock.page(ctx, Object.assign({ title: 'Recipes', section: 'home', back: 'Food & Recipes', badge: 3, choresBadge: 2, connection: o.connection, body: [gate], floating: bar }, o.pageOpts));
    if (pane) {
      var band = g ? g.band : 1;
      page.style.setProperty('--split-inset', (ctx.contentW - leftW) + 'px');
      var dp = F.detailPane(ctx, Object.assign({ left: leftW + band, top: ctx.device.barTop + 44 + 54 }, o.detail));
      dp.dataset.detailPane = ctx.splitAtHinge ? 'hinge' : 'midpoint'; dp.dataset.band = band;
      page.appendChild(dp);
    }
    return page;
  };

  /* ---------------------------------------------------------------- recipe detail (RecipeDetailView.swift, RecipeDetailRows.swift) */
  var TABS = [{ id: 'general', title: 'General', symbol: 'info.circle' }, { id: 'ingredients', title: 'Ingredients', symbol: 'checklist' }, { id: 'instructions', title: 'Instructions', symbol: 'frying.pan' }];
  F.tabs = TABS;
  /** The section bar for a sheet: ModalTabBarStyle.form gives icons on compact width, TEXT titles only on regular width (the kit draws an icon over the title there, which only the badged form does). */
  F.tabBar = function (ctx, tabs, selected) {
    var node = K().ModalTabBar({ tabs: tabs || TABS, selected: selected, ctx: ctx });
    var badged = (tabs || TABS).some(function (t) { return t.badge; });
    if (!ctx.compact && !ctx.axSize && !badged) { Array.prototype.forEach.call(node.querySelectorAll('svg'), function (v) { v.remove(); }); node.classList.remove('titled'); }
    return node;
  };
  F.D = { title: 'Lemon Garlic Chicken', coverage: '3 of 5 Ingredients', cookidoo: 'Cookidoo Chicken Bowl' };
  var FACTS = [['Yield', 'Serves 4', 'person.2'], ['Prep Time', '15 min', 'timer'], ['Cook Time', '45 min', 'flame'], ['Total Time', '1 hr', 'clock'], ['Difficulty', 'Easy', 'gauge.with.dots.needle.50percent'],
    ['Category', 'Main course', 'fork.knife'], ['Source', 'Spoonacular', 'book'], ['Locale', 'en-US', 'mappin.and.ellipse'], ['Freshness', 'Current · Oct 1, 2026', 'arrow.clockwise']];
  var COOK_FACTS = [['Source', 'Cookidoo', 'book'], ['Locale', 'en-US', 'mappin.and.ellipse'], ['Freshness', 'Current · Oct 1, 2026', 'arrow.clockwise']];
  /** Ingredients as RecipeFormatting.title / chips / sourceDetail produce them for FoodFixtures.detail. mark: on (green check), off (empty circle), unsure (question mark). */
  F.ING = [
    { group: 'Chicken', title: 'Chicken thighs · 6 pieces', mark: 'on', chips: ['Exact Inventory Match', 'Product: Chicken Thighs'], state: 'have' },
    { group: 'Chicken', title: 'Lemons · 2', mark: 'off', chips: ['Missing from Inventory', 'Inventory quantity may be insufficient'], state: 'missing' },
    { group: 'Chicken', title: 'Garlic · 4 cloves', mark: 'unsure', chips: ['Inventory Match Uncertain', 'Quantity sufficiency is unknown'], source: 'garlic, minced', match: 'Garlic bulb', state: 'uncertain' },
    { group: 'To finish', title: 'Olive oil · 2 tbsp', mark: 'on', chips: ['Staple', 'Quantity sufficiency is unknown'], state: 'staple' },
    { group: 'To finish', title: 'Fresh thyme · a few sprigs', mark: 'off', chips: ['Missing from Inventory', 'Optional', 'Quantity sufficiency is unknown'], state: 'missing' },
    { group: 'To finish', title: 'Butter · 1–2 tbsp', mark: 'on', chips: ['Missing from Inventory', 'Your override: have it', 'Quantity sufficiency is unknown'], state: 'override' },
  ];
  F.chipFlow = function (chips) { return h('div.fd-chips', chips.map(function (c) { return h('span.fd-chip', c); })); };
  /** One ingredient row (IngredientRow): mark, title, chips, source and match lines. checklist:false is the quantities-only form (glyph-less, notes). */
  F.ingredientRow = function (ing, o) {
    o = o || {}; var checklist = o.checklist !== false;
    var name = ing.title;
    var spoken = name + (checklist ? ', ' + (ing.mark === 'on' ? 'On hand' : 'Not on hand') : '');
    var tx = h('span.tx', h('span.ti', name),
      checklist ? F.chipFlow(ing.chips) : (ing.notes && ing.notes.length ? F.chipFlow(ing.notes) : null),
      ing.source ? h('span.note', 'Source: ' + ing.source) : null, ing.match ? h('span.note', 'Matched as ' + ing.match) : null);
    var kids = [];
    if (checklist) kids.push(h('span.rg.fd-mark.' + (ing.mark === 'on' ? 'on' : 'off'), { html: I(ing.mark === 'on' ? 'checkmark.circle.fill' : (ing.mark === 'unsure' ? 'questionmark.circle' : 'circle'), { fill: ing.mark === 'on' }) }));
    kids.push(tx);
    return h('div.ui-mrow.fd-ing', { role: 'listitem', 'aria-label': spoken + (checklist ? '. ' + ing.chips.join('. ') + (ing.source ? '. Source: ' + ing.source : '') + (ing.match ? '. Matched as ' + ing.match : '') : ''), style: { '--sep-inset': checklist ? 'calc(16px + 28px * var(--sc) + 12px)' : '16px' } }, kids);
  };
  F.factRow = function (f) {
    var r = K().ModuleRow({ title: f[0], symbol: f[2], accessory: h('span', f[1]) });
    r.classList.add('fd-fact'); r.setAttribute('role', 'listitem'); r.setAttribute('aria-label', f[0] + ', ' + f[1]);
    return r;
  };
  F.linkRow = function (title) { return h('button.fd-lr', { type: 'button', role: 'link' }, h('span.rg', { html: I('arrow.up.right.square') }), h('span', title)); };
  /** A titled list of plain names (FactList). */
  F.factList = function (title, items) { return h('div.fd-block', F.lhead(title), K().ModuleList({ hasGlyphs: false, rows: items.map(function (t) { return h('div.ui-mrow', { role: 'listitem' }, h('span.tx', h('span.ti', t))); }) })); };
  /** The grocery action in one of its states: idle, adding, added, failed, disabled (reason text). */
  F.grocery = function (state, reason) {
    var K2 = K(), box = h('div.fd-gro', { dataset: { state: state } });
    if (state === 'added') {
      box.appendChild(h('div.done', { role: 'status' }, h('span', { html: I('checkmark.circle.fill', { fill: true }) }), 'Added to Grocery List'));
      box.appendChild(h('p.why', 'Pantryhub: 2 added. Home Assistant mirror: 2 added.'));
      return box;
    }
    var btn = K2.PrimaryButton({ title: 'Add to Grocery List', symbol: 'cart.badge.plus', disabled: state === 'adding' || state === 'disabled' });
    if (state === 'adding') { var b = btn.querySelector('span'); if (b) b.replaceWith(K2.ArcSpinner({ size: 'inline', label: 'Adding' })); }
    box.appendChild(btn);
    var why = state === 'adding' ? 'Adding missing ingredients…' : (state === 'disabled' ? (reason || 'No missing ingredients to add.') : 'Adds the missing ingredients for this recipe to your shopping list.');
    box.appendChild(h('p.why', why));
    if (state === 'failed') box.appendChild(K2.InlineAlert({ message: 'Pantryhub: 1 failed. Pantryhub did not report service success.', severity: 'error' }));
    return box;
  };
  /**
   * The detail's content for a tab. o: {phase:'loaded'|'loading'|'failed'|'unsupported', tab, cookidoo, noPhoto, grocery, groceryReason, noIngredients, noInstructions, grouped, truncated, longName}
   * Returns one node; Instructions and the messages centre vertically while they fit (owner 2026-10-16).
   */
  F.detailContent = function (ctx, o) {
    o = o || {}; var K2 = K(), phase = o.phase || 'loaded', tab = o.tab || 'general';
    if (phase === 'loading') return h('div.fd-center', { style: { alignItems: 'center' } }, K2.ArcSpinner({ size: 'page', label: 'Loading recipe details' }), h('span', { style: { color: 'var(--ink-sheet-2)', fontSize: 'var(--fs-sub)' } }, 'Loading recipe details'));
    if (phase === 'failed') return h('div.fd-center', F.cuv('exclamationmark.triangle', 'Unable to Load Recipe', 'Unable to load recipe details.'));
    if (phase === 'unsupported') return h('div.fd-center', F.cuv('exclamationmark.triangle', 'Recipe Details Unsupported', 'The installed Pantryhub integration is too old to show recipe details.'));
    var out = h('div.fd-dc');
    if (tab === 'general') {
      out.appendChild(h('div.fd-hero', { role: 'img', 'aria-label': 'Recipe photo' }, o.noPhoto ? null : h('div.ph', { style: { background: F.photo(o.cookidoo ? 4 : 1) } }), o.noPhoto ? h('span.gl', { html: I('fork.knife') }) : null));
      out.appendChild(K2.ModuleList({ rows: (o.cookidoo ? COOK_FACTS : FACTS).map(F.factRow) }));
      if (o.cookidoo) out.appendChild(F.notice('Servings, time, difficulty, and equipment are not available in the cached Cookidoo metadata.'));
      else { out.appendChild(F.factList('Devices', ['Oven'])); out.appendChild(F.factList('Additional Equipment', ['Baking dish', 'Zester'])); }
      out.appendChild(K2.ModuleList({ hasGlyphs: true, rows: [F.linkRow(o.cookidoo ? 'Open in Cookidoo' : 'Open Source Recipe')] }));
    } else if (tab === 'ingredients') {
      if (o.truncated) out.appendChild(F.notice('This ingredient list is truncated.'));
      if (o.noIngredients) out.appendChild(F.cuv('list.bullet', 'No Ingredients Available', 'Ingredient details are not available for this recipe.'));
      else ['Chicken', 'To finish'].forEach(function (g) {
        out.appendChild(h('div.fd-block', F.lhead(g), K2.ModuleList({ hasGlyphs: true, rows: F.ING.filter(function (i) { return i.group === g; }).map(function (i) { return F.ingredientRow(i); }) })));
      });
      out.appendChild(F.grocery(o.grocery || 'idle', o.groceryReason));
    } else {
      var inner;
      if (o.cookidoo) {
        inner = h('div', { style: { display: 'flex', flexDirection: 'column', alignItems: 'center', textAlign: 'center', gap: '12px' } },
          h('span', { style: { fontSize: 'var(--fs-lt)', color: 'var(--ink-sheet-2)' }, html: I('arrow.up.right.square') }), h('h3', { style: { margin: 0, font: '600 var(--fs-hd)/1.25 var(--font)' } }, 'Instructions are on Cookidoo'),
          h('p', { style: { margin: 0, color: 'var(--ink-sheet-2)', fontSize: 'var(--fs-sub)' } }, 'Official Cookidoo step text stays on Cookidoo and is not stored or shown here.'), K2.PrimaryButton({ title: 'Open in Cookidoo', symbol: 'arrow.up.right.square' }));
      } else if (o.noInstructions) inner = F.cuv('list.number', 'No Instructions Available', 'Instructions are not available for this recipe.');
      else {
        var steps = ['Heat the oven to 425°F and zest the lemons.', 'Toss the chicken with garlic, olive oil, lemon juice and zest.', 'Roast for 40 minutes, basting halfway, then rest with butter and thyme.'];
        var groups = o.grouped ? [{ label: 'Marinate', steps: [1, 2] }, { label: null, steps: [3] }] : [{ label: null, steps: [1, 2, 3] }];
        inner = h('div.fd-dc');
        if (o.truncated) inner.appendChild(F.notice('These instructions are truncated.'));
        groups.forEach(function (g, gi) {
          var heading = g.label ? g.label : (groups.length === 1 ? null : 'Section ' + (gi + 1));
          inner.appendChild(h('div.fd-block', heading ? F.lhead(heading, !g.label) : null, K2.ModuleList({ hasGlyphs: false, rows: g.steps.map(function (n) { return h('div.fd-step', { role: 'listitem', 'aria-label': 'Step ' + n + '. ' + steps[n - 1] }, h('b', n + '.'), h('span', steps[n - 1])); }) })));
        });
      }
      return h('div.fd-center', inner);
    }
    return out;
  };
  /** Mock.sheet options for the recipe detail sheet (a large page sheet with the bottom glass tab bar; recipe stays full screen). */
  F.detailOpts = function (ctx, o) {
    o = o || {}; var loaded = !o.phase || o.phase === 'loaded';
    return { title: o.cookidoo ? F.D.cookidoo : (o.longName ? 'Slow-Cooked Pulled Pork Sandwiches With Pickled Onions' : F.D.title), subtitle: F.D.coverage, detent: 'large', size: 'page', trailing: 'close',
      content: F.detailContent(ctx, o), tabs: loaded ? F.tabBar(ctx, TABS, o.tab || 'general') : null };
  };
  /** The trailing pane of a split (RecipeDetailPane): its own header with the title and Close, the content and the glass tab bar; dark on black. */
  F.detailPane = function (ctx, o) {
    o = o || {};
    var loaded = !o.phase || o.phase === 'loaded';
    var pane = h('div.fd-pane.g-dark.in-sheet', { role: 'region', 'aria-label': 'Recipe detail', style: { left: o.left + 'px', right: ctx.rail + 'px', top: '0', bottom: '0', paddingTop: o.top + 'px' } },
      h('div.hd', h('h2', { role: 'heading', 'aria-level': '2' }, o.cookidoo ? F.D.cookidoo : F.D.title), K().SheetCloseItem()), h('div.dv'),
      h('div.bd', F.detailContent(ctx, o)), loaded ? h('div.tb', F.tabBar(ctx, TABS, o.tab || 'general')) : null);
    return pane;
  };
  /** The recipe detail over the hub or the Recipes page (sheet) or beside the grid (pane on a split-capable window). */
  F.detailOver = function (ctx, o) {
    o = o || {};
    if (o.over === 'recipes') {
      if (ctx.canSplit) return F.recipesPage(ctx, { selected: 0, detail: o, count: 12 });
      return Mock.sheet(ctx, Object.assign(F.detailOpts(ctx, o), { presenter: F.recipesPage(ctx, { selected: null, count: 12 }) }));
    }
    return Mock.sheet(ctx, Object.assign(F.detailOpts(ctx, o), { presenter: F.hubPage(ctx, {}) }));
  };

  /* ---------------------------------------------------------------- sort and filter sheets (RecipesScreen.swift, FilterSheet.swift) */
  var SORTS = [['availability', 'Ingredients Available', 'Prioritize recipes you can make from current inventory.'], ['expiry', 'Expiring Soon', 'Prioritize recipes that use ingredients nearing expiration.'], ['alphabetical', 'Alphabetical', 'Sort recipe titles from A to Z.']];
  F.SORTS = SORTS;
  F.sortContent = function (draft, current) {
    return K().FilterSheet({ canReset: draft !== 'availability', sections: [{ title: 'Sort By', options: SORTS.map(function (s) { return { title: s[1], subtitle: s[2], selected: s[0] === draft }; }) }] });
  };
  /** Sheet options for Sort Recipes. o: {draft, current} */
  F.sortOpts = function (o) {
    o = o || {}; var draft = o.draft || 'availability', current = o.current || 'availability';
    return { title: 'Sort Recipes', detent: o.detent || 'fitted', size: 'form', leading: 'cancel', trailing: 'confirm', confirm: { title: 'Apply', enabled: draft !== current }, content: F.sortContent(draft, current) };
  };
  var HORIZON = { '7 Days': 'Use ingredients expiring within the next week.', '30 Days': 'Use ingredients expiring within the next month.', '90 Days': 'Use ingredients expiring within the next three months.' };
  function sliderRow(title, pct, disabled) {
    return h('div.ui-field.fd-sl' + (disabled ? '.fd-dis' : ''), { role: 'group', 'aria-label': title + ', ' + pct + ' percent' }, h('div.top', h('span.lb', title), h('span.va', pct + '%')), K().Slider({ value: pct / 100, label: title }));
  }
  /** The Filter Recipes form content. o: {coverage, expiringOnly, horizon:'7 Days', availability, expiry, alphabetical} */
  F.filterContent = function (o) {
    o = o || {}; var K2 = K(), horizon = o.horizon || '7 Days';
    var coverage = h('div.ui-form', sliderRow('Minimum Ingredients Available', o.coverage || 0));
    var expiring = h('div.ui-form', h('div.ui-field', { style: { minHeight: '52px' } }, h('span.fd-lbl', h('span', { html: I('clock') }), 'Expiring Ingredients Only'), K2.Toggle({ on: !!o.expiringOnly, label: 'Expiring Ingredients Only' })),
      h('div.ui-field' + (o.expiringOnly ? '' : '.fd-dis'), K2.SegmentedChoice({ options: ['7 Days', '30 Days', '90 Days'], selected: horizon, label: 'Expiring Within' })));
    var rank = h('div.ui-form', sliderRow('Availability Weight', o.availability == null ? 100 : o.availability, !!o.alphabetical), sliderRow('Expiry Weight', o.expiry == null ? 25 : o.expiry, !!o.alphabetical));
    return K2.FilterSheet({ canReset: !!o.canReset, sections: [
      { title: 'Ingredient Coverage', content: coverage, footer: 'Only show recipes where at least this percentage of required ingredients is available.' },
      { title: 'Expiring Ingredients', content: expiring, footer: HORIZON[horizon] },
      { title: 'Ranking Strength', content: rank, footer: o.alphabetical ? 'Weights are unavailable while recipes are sorted alphabetically.' : 'Tune how strongly available and expiring ingredients influence ranked recipe results.' }] });
  };
  /** Sheet options for Filter Recipes. o as filterContent plus {changed, subtitle, detent} */
  F.filterOpts = function (o) {
    o = o || {};
    var n = (o.coverage > 0 ? 1 : 0) + (o.expiringOnly ? 1 : 0);
    return { title: 'Filter Recipes', subtitle: n ? (n === 1 ? '1 Filter On' : n + ' Filters On') : null, detent: o.detent || 'fitted', size: 'form', leading: 'cancel', trailing: 'confirm',
      confirm: { title: 'Apply', enabled: !!o.changed }, content: F.filterContent(Object.assign({ canReset: n > 0 || (o.availability != null && o.availability !== 100) || (o.expiry != null && o.expiry !== 25) }, o)) };
  };


  /* ---------------------------------------------------------------- push demos for the Transitions lists */
  /** The staged page is the ORIGIN; the destination built by `dest(ctx)` pushes in on top (system push, motion.md 4.2), then the stage is put back. */
  F.pushOnto = function (stage, dest) {
    var ctx = Mock.current, from = stage.querySelector('.ui-page'); if (!from) return Promise.resolve();
    var to = dest(ctx); from.parentNode.insertBefore(to, from.nextSibling);
    return Mock.anim.push(from, to).then(function () { return Mock.sleep(600); }).then(function () { to.remove(); Mock.anim.reset(stage); });
  };
  /** The staged page is the DESTINATION; the origin built by `origin(ctx)` sits under it and shifts left while the staged page pushes in. */
  F.pushInto = function (stage, origin) {
    var ctx = Mock.current, to = stage.querySelector('.ui-page'); if (!to) return Promise.resolve();
    var from = origin(ctx); to.parentNode.insertBefore(from, to);
    return Mock.anim.push(from, to).then(function () { return Mock.sleep(600); }).then(function () { from.remove(); Mock.anim.reset(stage); });
  };
  /** A Home page for the "from" side of a push (chips and the weather card are left out: only the header and title matter here). */
  F.homeStub = function (ctx) { return Mock.page(ctx, { title: 'Home', section: 'home', badge: 3, choresBadge: 2, body: [K().ChipRail({ chips: Mock.chips.home() })] }); };

  /* ---------------------------------------------------------------- helpers for component mockups */
  /** Swatches like Mock.componentConfig draws them, for local builders. items: [{label, note, width, surfaces, render(ctx, surface)}] */
  F.swatches = function (ctx, items, o) {
    o = o || {}; var surfaces = o.surfaces || ['page', 'sheet'];
    var out = h('div', { style: { display: 'flex', flexDirection: 'column', gap: '18px' } });
    surfaces.forEach(function (surface) {
      var wrap = h('div.k-swatch-grid');
      items.forEach(function (it) {
        if (it.surfaces && it.surfaces.indexOf(surface) < 0) return;
        var box = h('div.k-swatch.' + (surface === 'page' ? 'page.g-dark' : 'sheet.in-sheet.' + (ctx.appearance === 'dark' ? 'g-dark' : 'g-light')), { style: { flex: it.width ? 'none' : '1 1 ' + (o.min || 260) + 'px', width: it.width ? it.width + 'px' : '', maxWidth: '100%' } },
          h('div.k-cap', surface + ' · ' + it.label), h('div.in', it.render(ctx, surface)), it.note ? h('div', { style: { font: '12px var(--font)', opacity: .7, marginTop: '8px' } }, it.note) : null);
        wrap.appendChild(box);
      });
      out.appendChild(wrap);
    });
    return out;
  };
  /** A device frame built inside a component page, scaled down: build(ctx2) returns a Mock.page or Mock.sheet node. */
  F.miniDevice = function (ctx, key, build, gz) {
    var c2 = Mock.ctx(key, { appearance: ctx.appearance, ts: ctx.ts, reduceMotion: ctx.reduceMotion, reduceTransparency: ctx.reduceTransparency });
    var prev = Mock.current; Mock.current = c2;
    var fr; try { fr = Mock.frame(c2, build(c2)); } finally { Mock.current = prev; }
    return h('div.k-gz', { style: { '--gz': gz || .6 } }, fr);
  };
})();
