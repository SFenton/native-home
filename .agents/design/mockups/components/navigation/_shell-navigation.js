/* Local helpers for the shell-navigation batch (promote to kit: SN.board, SN.contentUnavailable, SN.rootPage, SN.pushedPage, SN.quickLinksSheet, SN.wallpaperBlur).
 * Loaded by every shell-navigation mockup with a relative <script src>. Nothing here changes the kit; it only composes kit components.
 * Never copy kit CSS: the few `.sn-*` rules below are layout glue for boards (several devices on one stage) and ContentUnavailableView.
 */
(function () {
  var h = Mock.h, K = Mock.components, I = Mock.icon;
  var SN = window.SN = {};

  var css = [
    '.sn-board{display:flex;flex-wrap:wrap;gap:28px 32px;align-items:flex-start;padding:4px 0}',
    '.sn-fig{margin:0;flex:none}',
    '.sn-fig figcaption{margin-top:8px;max-width:420px;font:12px/1.4 var(--mono);color:var(--k-fg2)}',
    '.sn-fig figcaption b{display:block;font:600 13px var(--font);color:var(--k-fg)}',
    '.sn-z{transform-origin:0 0}',
    '.sn-cuv{display:flex;flex-direction:column;align-items:center;justify-content:center;gap:8px;text-align:center;padding:0 24px;min-height:calc(var(--h) * .5);color:#fff}',
    '.sn-cuv svg{width:calc(48px * var(--sc, 1));height:calc(48px * var(--sc, 1));color:var(--g-secondary-on-wallpaper)}',
    '.sn-cuv h2{margin:4px 0 0;font:700 var(--fs-t2)/1.2 var(--font-d)}',
    '.sn-cuv p{margin:0;font:var(--fs-sub)/1.3 var(--font);color:var(--g-secondary-on-wallpaper)}',
    '.sn-row{display:flex;flex-wrap:wrap;gap:16px;align-items:center}',
    '.sn-mono{font:12px/1.4 var(--mono)}',
    /* house-backdrop: no photo yet (base colour only, modules still translucent) and Increase Contrast (every scrim stop 0.12 denser) */
    '.sn-nophoto .ui-wall::before{display:none}.sn-nophoto .ui-wall::after{background:none}',
    '.sn-ic .ui-wall::after{background:linear-gradient(180deg,rgba(0,0,0,.56) 0%,rgba(0,0,0,.57) 28%,rgba(0,0,0,.58) 50%,rgba(0,0,0,.64) 75%,rgba(0,0,0,.76) 100%)}',
    '.sn-dim{position:absolute;inset:0;z-index:5;background:rgba(0,0,0,.32);pointer-events:none}',
    /* measurement annotations on component boards */
    '.sn-meas{display:inline-flex;align-items:center;gap:6px;font:11px/1.2 var(--mono);color:var(--k-fg2)}',
    '.sn-meas i{display:inline-block;height:0;border-top:1.5px solid #ff9f0a;position:relative}',
    '.sn-meas i::before,.sn-meas i::after{content:"";position:absolute;top:-5px;height:8px;border-left:1.5px solid #ff9f0a}',
    '.sn-meas i::before{left:0}.sn-meas i::after{right:0}',
  ].join('\n');
  var st = document.createElement('style'); st.textContent = css; document.head.appendChild(st);

  /** A ctx for a device, carrying the stage's appearance, text size and accessibility switches. */
  SN.ctxFor = function (key, ctx) {
    return Mock.ctx(key, { appearance: ctx.appearance, ts: ctx.ts, reduceMotion: ctx.reduceMotion, reduceTransparency: ctx.reduceTransparency });
  };

  /**
   * Several framed devices on one stage (component mockups, which have no device frame of their own).
   * items: [{key, build(ctx)->Node, caption, title?, zoom?, ts?:override, reduceTransparency?}]
   */
  SN.board = function (ctx, items) {
    var out = h('div.sn-board');
    items.forEach(function (it) {
      var c = Mock.ctx(it.key, { appearance: ctx.appearance, ts: it.ts || ctx.ts, reduceMotion: ctx.reduceMotion, reduceTransparency: it.reduceTransparency != null ? it.reduceTransparency : ctx.reduceTransparency });
      var prev = Mock.current; Mock.current = c;
      var node; try { node = it.build(c); } finally { Mock.current = prev; }
      var dev = Mock.frame(c, node), d = c.device;
      var z = it.zoom || (d.w > 800 ? .5 : (d.w > 600 ? .62 : .78));
      var box = h('div.sn-z', { style: { zoom: z } }, dev);
      out.appendChild(h('figure.sn-fig', { dataset: { device: it.key } }, box, h('figcaption', h('b', it.title || d.short), it.caption || '')));
    });
    return out;
  };

  /** ContentUnavailableView: a large secondary symbol, a title, a description (Features/Placeholders/PlaceholderScreen.swift). */
  SN.contentUnavailable = function (o) {
    return h('div.sn-cuv', { role: 'group', 'aria-label': o.title + '. ' + o.description }, h('span', { 'aria-hidden': 'true', html: I(o.symbol, { size: 48, weight: 1.4 }) }), h('h2', o.title), h('p', o.description));
  };

  /* ------------------------------------------------------------------ trimmed tab roots and pushed pages (the page behind a flow) */
  function cameras(n) {
    var names = [['Front Door', 'front-door'], ['Driveway', 'driveway'], ['Upper Deck', 'upper-deck'], ['Lower Deck', 'lower-deck']].slice(0, n || 2);
    return h('div.ui-section', K.PageSectionHeader({ title: 'Cameras' }), K.TileGrid({ min: 160, max: 4, equal: false, items: names.map(function (x) { return K.CameraTile({ title: x[0], scene: x[1], state: 'live' }); }) }));
  }
  function section(title, kids) { return h('div.ui-section', K.PageSectionHeader({ title: title }), kids); }

  /** The body of a tab root, trimmed to what identifies the page (full pages belong to their own batches). */
  SN.rootBody = function (ctx, sec) {
    var frame = { x: 0, w: ctx.splitGeometry ? ctx.splitGeometry.leading : ctx.contentW };
    if (sec === 'security') return [K.ChipRail({ chips: [Mock.chips.security('armed_home'), Mock.chips.contacts('closed', 0)], frame: frame }), cameras(2)];
    if (sec === 'climate') return [K.ChipRail({ chips: [Mock.chips.climate('68–72°F', 70)], frame: frame }), section('Thermostat', K.TileGrid({ min: 150, max: 2, items: [
      { title: 'Thermostat Hub', subtitle: 'Heating to 70°', symbol: 'thermometer.medium', family: 'heating', isActive: true }, { title: 'Hallway Vent', subtitle: 'Open', symbol: 'wind', family: 'vents', isActive: true }] }))];
    if (sec === 'chores') return [section('Chore Lists', K.TileGrid({ min: 150, max: 4, items: [
      { title: 'Alex', subtitle: '2 Overdue', symbol: 'checklist', family: 'chore-resident1', isActive: true, kind: 'navigate' }, { title: 'Sam', subtitle: 'None Overdue', symbol: 'checklist', family: 'chore-resident2', isActive: true, kind: 'navigate' },
      { title: 'Groceries', subtitle: '7 Items', symbol: 'cart', family: 'groceries', isActive: true, kind: 'navigate' }, { title: 'Home', subtitle: '3 Open', symbol: 'house', family: 'chore-home', isActive: true, kind: 'navigate' }] }))];
    if (sec === 'settings') return [K.ModuleList({ rows: [{ title: 'Appearance', subtitle: 'Background Blur 50%', symbol: 'paintpalette', chevron: true }, { title: 'Household', symbol: 'person.2', chevron: true }, { title: 'Performance', symbol: 'gauge.with.dots.needle.50percent', chevron: true }, { title: 'Send Feedback', symbol: 'envelope', chevron: true }] })];
    var chips = K.ChipRail({ chips: Mock.chips.home(), frame: frame });
    var wx = K.WeatherCard({ condition: 'Partly Cloudy', temp: 48, hi: 58, lo: 38 });
    if (ctx.splitGeometry && ctx.hinge) return [Mock.split(ctx, { leading: [chips, wx], trailing: [cameras(2)] })];
    return [chips, wx, cameras(2)];
  };
  /** A tab root (or any section) as Mock.page draws it. o is merged into the Mock.page options. */
  SN.rootPage = function (ctx, sec, o) {
    var titles = { home: 'Home', security: 'Security', climate: 'Climate', chores: 'Chores', settings: 'Settings' };
    return Mock.page(ctx, Object.assign({ title: titles[sec] || sec, section: sec, badge: 3, choresBadge: 2, body: SN.rootBody(ctx, sec) }, o));
  };
  /** A page pushed under Home (a room): Back replaces the menu button; Quick Links and Profile stay. */
  SN.pushedPage = function (ctx, o) {
    o = o || {};
    var frame = { x: 0, w: ctx.contentW };
    return Mock.page(ctx, Object.assign({ title: o.title || 'Kitchen', back: 'Home', section: 'home', badge: 3, choresBadge: 2, body: o.body || [
      K.ChipRail({ chips: [Mock.chips.lights(2), { title: 'Climate', summary: '70°F', symbol: 'thermometer.medium', isActive: false }], frame: frame }),
      section('Lights', K.TileGrid({ min: 150, max: 2, items: [{ title: 'Kitchen Lights', subtitle: 'On at 70%', symbol: 'lightbulb', family: 'lights', isActive: true, progress: .7 }, { title: 'Table Light', subtitle: 'Off', symbol: 'lightbulb', family: 'lights', isActive: false }] })),
      section('Devices', K.TileGrid({ min: 150, max: 2, items: [{ title: 'Oven', subtitle: 'Off', symbol: 'flame', family: 'cooking', isActive: false }, { title: 'Dishwasher', subtitle: 'Idle', symbol: 'drop', family: 'water', isActive: false }] }))] }, o.page));
  };

  /* ------------------------------------------------------------------ Quick Links sheet (Features/Rooms/QuickLinksSheet.swift, QuickLinks.items) */
  SN.quickLinkTiles = function (o) {
    o = o || {};
    var tiles = [
      { title: 'Rooms', symbol: 'square.split.2x2', fill: 'var(--ql-rooms)', id: 'rooms' },
      { title: 'Security System', subtitle: 'Armed Home', symbol: 'shield', fill: 'var(--fam-sec-home-fill)', id: 'security-system' },
      { title: 'Food & Recipes', subtitle: '42 Items • 3 Expiring Soon', symbol: 'fork.knife', fill: 'var(--fam-food-fill)', id: 'food' },
      { title: 'Vacuums', symbol: 'robotic.vacuum', fill: 'var(--fam-cleaning-fill)', id: 'vacuums' },
      { title: 'Media', symbol: 'tv', fill: 'var(--fam-media-fill)', id: 'media' },
      { title: 'Custom Lights', symbol: 'lightbulb.2', fill: 'var(--ql-custom-lights)', id: 'custom-lights' },
    ];
    if (o.sprinklers !== false) tiles.push({ title: 'Sprinklers', symbol: 'sprinkler.and.droplets', fill: 'var(--fam-water-fill)', id: 'sprinklers' });
    return K.TileGrid({ min: 140, max: 2, items: tiles.map(function (t) {
      var n = K.GlassTile({ title: t.title, subtitle: t.subtitle, symbol: t.symbol, family: 'neutral', fill: t.fill, kind: 'navigate', layout: 'stack', titleLines: 2, isActive: false });
      n.dataset.ql = t.id; return n; }) });
  };
  SN.roomsGrid = function () {
    var rooms = [['Living Room', 'sofa', 'living-room'], ['Kitchen', 'fork.knife', 'kitchen'], ['Bedroom 1', 'bed.double', 'master-bedroom'], ['Gym', 'dumbbell', 'gym'], ['Office', 'pc', 'office'], ['Guest Room', 'bed.double', 'guest-room']];
    return K.TileGrid({ min: 140, max: 4, items: rooms.map(function (r) { var n = K.GlassTile({ title: r[0], symbol: r[1], family: 'neutral', room: r[2], kind: 'navigate', layout: 'stack', titleLines: 2, isActive: false }); n.dataset.room = r[2]; return n; }) });
  };
  /** The Quick Links sheet: a large page sheet (hassSheet(.page, height: .full)) with the tile grid, or Rooms pushed inside it. */
  SN.quickLinksSheet = function (ctx, o) {
    o = o || {};
    var rooms = o.detail === 'rooms';
    var content = h('div', { style: { padding: '8px 16px 24px', maxWidth: '560px', margin: '0 auto' } }, rooms ? SN.roomsGrid() : SN.quickLinkTiles(o));
    return Mock.sheet(ctx, { title: rooms ? 'Rooms' : 'Quick Links', detent: 'large', size: 'page', leading: rooms ? 'back' : 'none', trailing: 'close', content: content, presenter: o.presenter === false ? null : (o.presenter || SN.rootPage(ctx, 'home', o.pageOpts)) });
  };

  /* ------------------------------------------------------------------ wallpaper stand-in at a chosen blur (house-backdrop) */
  /** CSS classes `.sn-blur-<points*10>` that redraw the kit's wallpaper stand-in with another Gaussian (the kit's is the 16.8 pt default). */
  SN.wallpaperBlur = function (sigmas) {
    var rules = sigmas.map(function (s) {
      var svg = "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 402 874' preserveAspectRatio='xMidYMid slice'><defs><linearGradient id='s' x1='0' y1='0' x2='0' y2='1'><stop offset='0' stop-color='#6f89ad'/><stop offset='.32' stop-color='#a4a9b6'/><stop offset='.5' stop-color='#d9a779'/><stop offset='.62' stop-color='#463d41'/><stop offset='1' stop-color='#161c26'/></linearGradient><filter id='b' x='-20%' y='-20%' width='140%' height='140%'><feGaussianBlur stdDeviation='" + s + "'/></filter></defs><g" + (s > 0 ? " filter='url(#b)'" : '') + "><rect width='402' height='874' fill='url(#s)'/><path d='M-20 520 L90 470 L210 505 L300 455 L430 500 L430 900 L-20 900Z' fill='#2a3140'/><rect x='80' y='500' width='250' height='170' fill='#26282f'/><path d='M60 505 L205 420 L350 505Z' fill='#1f2229'/><rect x='112' y='540' width='40' height='54' fill='#f1b25e'/><rect x='168' y='540' width='40' height='54' fill='#e8a64d'/><rect x='226' y='540' width='40' height='54' fill='#f6c276'/><rect x='112' y='618' width='40' height='40' fill='#d99a46'/><rect x='226' y='618' width='40' height='40' fill='#f1b25e'/><path d='M0 700 L402 700' stroke='#fff' stroke-opacity='.5' stroke-width='3'/><ellipse cx='40' cy='640' rx='70' ry='90' fill='#182231'/><ellipse cx='380' cy='630' rx='80' ry='100' fill='#182231'/></g></svg>";
      return '.sn-blur-' + Math.round(s * 10) + ' .ui-wall::before{background-image:url("data:image/svg+xml;utf8,' + encodeURIComponent(svg) + '")}';
    });
    var el = document.createElement('style'); el.textContent = rules.join('\n'); document.head.appendChild(el);
  };


  /* ------------------------------------------------------------------ header strip (the bar alone, on a page-surface swatch) */
  /**
   * The header bar as Mock.page lays it out, cropped to the bar: [leading] ... [arc] [Quick Links] [Profile].
   * o: {width?:380, leading?:'menu'|'back'|null, title?:string (inline-large title in the leading slot), arc?:boolean, name?, badge?, offline?, rail?:boolean (Duo rail group, vertical), grouped?}
   */
  SN.strip = function (o) {
    o = o || {};
    var bar = h('div.ui-bar', { style: { position: 'relative', left: 'auto', right: 'auto', top: 'auto', width: (o.width || 380) + 'px', maxWidth: '100%', pointerEvents: 'auto' } });
    if (o.leading === 'menu') bar.appendChild(K.HamburgerButton());
    if (o.leading === 'back') bar.appendChild(K.BackButton({ label: 'Home' }));
    if (o.title) bar.appendChild(h('h1.ui-t-large', { style: { whiteSpace: 'nowrap', marginLeft: o.leading ? 0 : 4 } }, o.title));
    bar.appendChild(h('div.sp'));
    if (o.arc) bar.appendChild(K.ReconnectingArc({ on: true }));
    if (o.rail) bar.appendChild(K.RailGroup({ badge: o.badge }));
    else { bar.appendChild(K.QuickLinksButton()); bar.appendChild(K.ProfileButton({ name: o.name, badge: o.badge, offline: o.offline })); }
    return bar;
  };
  /** A page-surface swatch holding a strip, with a caption under it. */
  SN.stripSwatch = function (o, title, text) {
    return h('div', { style: { flex: 'none', maxWidth: '100%' } }, h('div.k-swatch.page', { style: { width: ((o.width || 380) + 28) + 'px', maxWidth: '100%' } }, h('div.k-cap', title), SN.strip(o)), text ? SN.cap('', text) : null);
  };

  /** Present a sheet over one board figure (component stages hold several devices): key is the figure's device, mk(ctx) returns Mock.sheet options. */
  SN.present = function (stage, key, mk, hold) {
    var screen = SN.screen(key) || stage;
    var c = SN.ctxFor(key, Mock.current), prev = Mock.current; Mock.current = c;
    var sheetOpts; try { sheetOpts = mk(c); } finally { Mock.current = c; }
    return Mock.presentDemo(screen, sheetOpts, { hold: hold || 1000 }).then(function () { Mock.current = prev; });
  };
  /** A stand-in Your Summary sheet (the Profile button opens it: hassSheet(.form, height: .full)). */
  SN.accountSheet = function (c) {
    return { title: 'Your Summary', detent: 'large', size: 'form', trailing: 'close', content: h('div', { style: { padding: '8px 16px 24px', maxWidth: '560px', margin: '0 auto' } },
      K.ModuleList({ rows: [{ title: 'Alex Morgan', subtitle: 'Signed in', symbol: 'person.crop.circle.fill' }, { title: 'Overdue Chores', subtitle: '2 items', symbol: 'checklist' }, { title: 'Expired Food', subtitle: '1 item', symbol: 'refrigerator' }] })) };
  };


  /** Collapse a page's large title into the centred inline title (what the system bar does on scroll): the title leaves the scroll content, the bar shows it. */
  SN.collapse = function (page, title) {
    var wrap = page.querySelector('.ui-title-wrap'); if (wrap) wrap.style.visibility = 'hidden';
    var bar = page.querySelector('.ui-bar'), t = h('div.inline-title', { style: { opacity: 1 } }, title); bar.appendChild(t);
    var sc = page.querySelector('.ui-scroll'); if (sc) requestAnimationFrame(function () { sc.style.setProperty('--ramp', '40px'); });
    return page;
  };


  /* In a component mockup (no device frame) Mock.mount hands play() the FIRST framed .screen, not the board: these reach the whole stage. */
  SN.stageRoot = function () { return document.querySelector('#stage .k-stage-inner'); };
  /** The board figure for a device key (.sn-fig) and its .screen. */
  SN.fig = function (key) { return SN.stageRoot().querySelector('.sn-fig[data-device="' + key + '"]'); };
  SN.screen = function (key) { var f = SN.fig(key); return f && f.querySelector('.screen'); };


  /* ------------------------------------------------------------------ a finger (touch indicator) for flow steps */
  /** Offset of el inside ancestor, in layout pixels (immune to CSS zoom). */
  function offsetIn(el, anc) { var x = 0, y = 0, n = el; while (n && n !== anc) { x += n.offsetLeft; y += n.offsetTop; n = n.offsetParent; } return { x: x, y: y }; }
  SN.offset = offsetIn;
  /**
   * Draw a touch dot on a page. target is a CSS selector (centre of that element, resolved once the page is attached) or {x, y} in screen points.
   * o: {label?, drag?:{x,y} (a dashed path with an arrow from the dot to this point), trail?:{x,y} (a dashed path from this point to the dot: where the finger came from)}
   */
  SN.finger = function (page, target, o) {
    o = o || {};
    var dot = h('div', { 'aria-hidden': 'true', style: { position: 'absolute', zIndex: 130, width: '40px', height: '40px', marginLeft: '-20px', marginTop: '-20px', borderRadius: '50%', background: 'rgba(255,255,255,.34)', border: '2px solid rgba(255,255,255,.85)', boxShadow: '0 2px 10px rgba(0,0,0,.45)', pointerEvents: 'none', left: '-99px', top: '-99px' } });
    if (o.label) dot.appendChild(h('span', { style: { position: 'absolute', left: '46px', top: '8px', font: '600 11px/1.2 var(--mono)', color: '#fff', background: 'rgba(0,0,0,.7)', padding: '2px 6px', borderRadius: '6px', whiteSpace: 'nowrap' } }, o.label));
    page.appendChild(dot);
    function place() {
      var x, y;
      if (typeof target === 'string') { var t = page.querySelector(target); if (!t) return; var p = offsetIn(t, page); x = p.x + t.offsetWidth / 2; y = p.y + t.offsetHeight / 2; }
      else { x = target.x; y = target.y; }
      dot.style.left = x + 'px'; dot.style.top = y + 'px';
      if (o.trail) {
        var tl = Math.hypot(x - o.trail.x, y - o.trail.y), ta = Math.atan2(y - o.trail.y, x - o.trail.x) * 180 / Math.PI;
        page.appendChild(h('div', { 'aria-hidden': 'true', style: { position: 'absolute', zIndex: 129, left: o.trail.x + 'px', top: o.trail.y + 'px', width: Math.max(0, tl - 22) + 'px', height: 0, borderTop: '3px dashed rgba(255,255,255,.8)', transformOrigin: '0 0', transform: 'rotate(' + ta + 'deg)', pointerEvents: 'none' } }));
      }
      if (o.drag) {
        var len = Math.hypot(o.drag.x - x, o.drag.y - y), ang = Math.atan2(o.drag.y - y, o.drag.x - x) * 180 / Math.PI;
        var line = h('div', { 'aria-hidden': 'true', style: { position: 'absolute', zIndex: 129, left: x + 'px', top: y + 'px', width: len + 'px', height: 0, borderTop: '3px dashed rgba(255,255,255,.8)', transformOrigin: '0 0', transform: 'rotate(' + ang + 'deg)', pointerEvents: 'none' } });
        var head = h('div', { 'aria-hidden': 'true', style: { position: 'absolute', zIndex: 129, left: o.drag.x + 'px', top: o.drag.y + 'px', width: '14px', height: '14px', marginLeft: '-9px', marginTop: '-7px', borderTop: '3px solid #fff', borderRight: '3px solid #fff', transform: 'rotate(' + (ang + 45) + 'deg)', pointerEvents: 'none' } });
        page.appendChild(line); page.appendChild(head);
      }
    }
    Mock.whenAttached(page, place);
    return dot;
  };

  /* ------------------------------------------------------------------ system surfaces drawn as stand-ins (notification, Spotlight, Shortcuts, Live Activity) */
  var SYS_BG = 'radial-gradient(120% 90% at 20% 0%, #5b6f95 0%, #2b3550 45%, #0f1420 100%)';
  /** A system screen (not an S+H page): wallpaper-like ground with content on it. Stand-ins for iOS UI that the app does not draw. */
  SN.systemScreen = function (ctx, label, kids) {
    return h('div.ui-page', { style: { background: SYS_BG } }, h('div', { style: { position: 'absolute', left: 0, right: 0, top: (ctx.device.barTop + 56) + 'px', padding: '0 16px', display: 'flex', flexDirection: 'column', gap: '12px' } }, kids),
      h('div', { style: { position: 'absolute', left: 0, right: 0, bottom: '90px', textAlign: 'center', font: '600 11px var(--mono)', color: 'rgba(255,255,255,.55)', letterSpacing: '.04em' } }, 'SYSTEM UI STAND-IN · ' + label));
  };
  var glassCard = { background: 'rgba(235,235,245,.22)', backdropFilter: 'blur(24px) saturate(1.5)', WebkitBackdropFilter: 'blur(24px) saturate(1.5)', borderRadius: '24px', color: '#fff', border: '.5px solid rgba(255,255,255,.18)' };
  var icon = function (px) { return h('div', { 'aria-hidden': 'true', style: { width: px + 'px', height: px + 'px', borderRadius: Math.round(px * .22) + 'px', background: 'linear-gradient(160deg,#2f6bd8,#11214a)', display: 'grid', placeItems: 'center', flex: 'none', font: '700 ' + Math.round(px * .34) + 'px var(--font)', color: '#fff' } }, 'S+H'); };
  /** A notification banner: app icon, "S+H", title, body, "now". */
  SN.notification = function (o) {
    return h('div', { role: 'group', 'aria-label': 'Notification from S+H: ' + o.title + '. ' + o.body, style: Object.assign({ padding: '14px', display: 'flex', gap: '12px', alignItems: 'flex-start' }, glassCard) },
      icon(38), h('div', { style: { flex: 1, minWidth: 0 } }, h('div', { style: { display: 'flex', justifyContent: 'space-between', font: '600 var(--fs-sub) var(--font)' } }, h('span', o.title), h('span', { style: { font: '400 var(--fs-foot) var(--font)', opacity: .7 } }, 'now')),
        h('div', { style: { font: 'var(--fs-sub)/1.3 var(--font)', opacity: .92, marginTop: '2px' } }, o.body)));
  };
  /** A Spotlight result row: page glyph, title, summary. */
  SN.spotlightRow = function (o) {
    return h('div', { style: Object.assign({ padding: '10px 14px', display: 'flex', gap: '12px', alignItems: 'center', borderRadius: '18px' }, glassCard) }, icon(40),
      h('div', h('div', { style: { font: '600 var(--fs-body) var(--font)' } }, o.title), h('div', { style: { font: 'var(--fs-foot) var(--font)', opacity: .75 } }, o.summary)));
  };
  /** An App Shortcut tile (Shortcuts, Siri, Spotlight). */
  SN.shortcutTile = function (o) {
    return h('div', { style: { borderRadius: '22px', padding: '14px', background: 'linear-gradient(160deg,#2f6bd8,#1b3a86)', color: '#fff', width: '168px', minHeight: '92px', display: 'flex', flexDirection: 'column', justifyContent: 'space-between' } }, h('span', { 'aria-hidden': 'true', html: I(o.symbol, { size: 26, fill: true }) }), h('span', { style: { font: '600 var(--fs-sub) var(--font)' } }, o.title));
  };
  /** The Home Live Activity as the lock screen draws it (stand-in): a status line and one job. */
  SN.liveActivity = function (o) {
    return h('div', { role: 'group', 'aria-label': o.title + ', ' + o.status, style: Object.assign({ padding: '14px 16px', display: 'flex', gap: '12px', alignItems: 'center' }, glassCard) }, h('span', { 'aria-hidden': 'true', html: I('robotic.vacuum', { size: 30 }) }),
      h('div', { style: { flex: 1 } }, h('div', { style: { font: '600 var(--fs-body) var(--font)' } }, o.title), h('div', { style: { font: 'var(--fs-sub) var(--font)', opacity: .8 } }, o.status)), h('span', { style: { font: '700 var(--fs-body) var(--font)' } }, o.value));
  };

  /** A line that labels a measurement on a component board. */
  SN.meas = function (px, label) { return h('span.sn-meas', h('i', { style: { width: px + 'px' } }), label); };
  /** A mono caption block used under a swatch or figure. */
  SN.cap = function (title, text) { return h('div.sn-mono', { style: { color: 'var(--k-fg2)', maxWidth: '420px', margin: '6px 0 0' } }, h('b', { style: { color: 'var(--k-fg)', font: '600 13px var(--font)', display: 'block' } }, title), text); };
})();
