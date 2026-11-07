/* Shared helper for the widgets-liveactivity batch (Live Activity cards, Dynamic Island, small family, notification surfaces, Watch stub).
 *
 * The kit has no Live Activity components (they are not in-app chrome), so this file draws them from the SwiftUI in
 * apple/Sources/FentonActivityViews and FentonActivityModel, using only kit tokens (--fam-*, --font, --fs-*, .ui-wall, Mock.icon).
 * Promote to kit: LA.card (the ActivityCard rules), LA.jobCard / LA.problemCard / LA.island* / LA.small, the 11 glyph drawings below
 * (dishwasher.fill, washer.fill, dryer.fill, thermometer.snowflake, arrow.down.to.line, scribble, battery.25percent, water.waves,
 * bag.fill, bolt.horizontal.fill, circle.dashed), LA.mark (house and heart) and the Watch device.
 *
 * Rules ported from the app (each cites its file):
 *   - ActivityCard.swift: title, headerLine, bigLine, figure, ring, bar, compactTrailing, buttons, speech.
 *   - ActivityStyle.swift: colours, 24 pt corner radius, 44 pt hit area, 36 pt pill, 5 pt bar, 160 pt Lock Screen limit.
 *   - JobCardView / ProblemCardView / HomeActivityIslandViews / HomeActivitySmallView: layouts.
 * Dynamic Type: the Lock Screen and the small family scale with the kit's --fs table; the island is capped at xxxLarge
 * (HomeActivityIslandPreview `.dynamicTypeSize(...xxxLarge)`).
 */
(function () {
  'use strict';
  var h = Mock.h;
  var LA = window.LA = {};

  /* ------------------------------------------------------------------ styles */
  var css = [
    '.la-card{box-sizing:border-box;width:370px;max-width:100%;border-radius:24px;overflow:hidden;position:relative;color:#fff;font-family:var(--font);text-align:left;flex:none;--la-knock:#17181e}',
    '.la-card.job{background:rgba(23,24,30,.78);-webkit-backdrop-filter:blur(30px) saturate(1.5);backdrop-filter:blur(30px) saturate(1.5)}',
    '.k-reduce-transparency .la-card.job{background:#17181e;-webkit-backdrop-filter:none;backdrop-filter:none}',
    '.la-in{padding:12px 16px;display:flex;flex-direction:column;gap:6px;box-sizing:border-box}',
    '.la-row{display:flex;gap:10px;align-items:flex-start}',
    '.la-g{display:inline-grid;place-items:center;flex:none;line-height:0}',
    '.la-g svg{width:100%;height:100%;display:block;overflow:visible}',
    '.la-clamp{overflow:hidden;display:-webkit-box;-webkit-box-orient:vertical;min-width:0;overflow-wrap:anywhere;line-height:1.18}',
    '.la-title{flex:1;min-width:0;font-weight:600;line-height:1.18}',
    '.la-valrow{display:flex;gap:8px;align-items:center}',
    '.la-valrow.ax{flex-direction:column;align-items:stretch;gap:8px}',
    '.la-val{flex:1;min-width:0;font-weight:600;font-variant-numeric:tabular-nums;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}',
    '.la-val.wrap{white-space:normal}',
    '.la-btns{display:flex;gap:8px;align-items:center}',
    '.la-btns.ax{flex-direction:column;align-items:flex-end;gap:4px}',
    '.la-btns.fill{flex:1}.la-btns .sp{flex:1}',
    '.la-btn{min-width:44px;min-height:44px;border:0;background:none;padding:0;display:inline-grid;place-items:center;cursor:pointer;color:inherit;font:inherit;flex:none}',
    '.la-btn .pill{display:grid;place-items:center;min-height:36px;padding:8px 16px;border-radius:999px;font-weight:600;white-space:nowrap;background:rgba(255,255,255,.14);color:#fff}',
    '.la-btn.primary .pill{background:#fff;color:#000}',
    '.la-btn .rnd{width:44px;height:44px;border-radius:50%;display:grid;place-items:center;background:rgba(255,255,255,.14);color:#fff}',
    '.la-btn.primary .rnd{background:#fff;color:#000}',
    '.la-btn .rnd svg{width:18px;height:18px}',
    '.la-btn:focus-visible{outline:3px solid #409cff;outline-offset:1px;border-radius:22px}',
    '.la-pending{font-weight:600;color:rgba(255,255,255,.78);min-height:44px;display:flex;align-items:center;white-space:nowrap}',
    '.la-chip{font-weight:600;padding:4px 10px;border-radius:999px;background:rgba(255,255,255,.14);white-space:nowrap;color:#fff}',
    '.la-unconf{font-weight:600;color:rgba(255,255,255,.78);white-space:nowrap}',
    '.la-bar{height:5px;border-radius:3px;background:rgba(235,235,245,.22);overflow:hidden;flex:none}',
    '.la-bar i{display:block;height:100%;border-radius:3px;background:var(--la-accent,#fff)}',
    '.la-mark{flex:none;line-height:0}',
    '.la-island-x{box-sizing:border-box;background:#000;color:#fff;font-family:var(--font);text-align:left;--la-knock:#000;position:relative;flex:none}',
    '.la-island-x .top{display:flex;height:36px;align-items:center}',
    '.la-island-x .reg{display:flex;align-items:center;flex:none;box-sizing:border-box}',
    '.la-cam{height:36px;border-radius:18px;background:#0c0c0e;flex:none;box-shadow:0 0 0 1px rgba(255,255,255,.06) inset}',
    '.la-island-c{display:flex;align-items:center;background:#000;color:#fff;font-family:var(--font);border-radius:999px;height:36px;position:relative;flex:none;--la-knock:#000;box-sizing:border-box;padding:0 10px}',
    '.la-island-c .gap{flex:1}',
    '.la-ct{position:relative;display:inline-block;font-variant-numeric:tabular-nums;font-weight:600;white-space:nowrap}',
    '.la-ct .tpl{visibility:hidden}.la-ct .live{position:absolute;right:0;top:0;white-space:nowrap}',
    '.la-island-m{display:grid;place-items:center;border-radius:50%;background:#000;--la-knock:#000;flex:none}',
    '.la-small{display:flex;gap:8px;align-items:center;font-family:var(--font);color:#fff;text-align:left;--la-knock:#17181e}',
    '.la-small .tx{display:flex;flex-direction:column;min-width:0}',
    '.la-small .ln{white-space:nowrap;overflow:hidden;text-overflow:ellipsis}',
    '.la-stage{position:relative;border-radius:18px;overflow:hidden;padding:18px;box-sizing:border-box;isolation:isolate}',
    '.la-in-stage>.la-note{flex:0 0 100%;max-width:640px}',
    '.la-stage .la-in-stage{position:relative;z-index:1;display:flex;flex-wrap:wrap;gap:18px;align-items:flex-start}',
    '.la-fig{display:flex;flex-direction:column;gap:6px;align-items:flex-start;min-width:0;max-width:100%}',
    '.la-fig .cap{font:600 11px/1.3 var(--mono);letter-spacing:.03em;color:rgba(255,255,255,.62);max-width:380px}',
    '.la-grid{display:flex;flex-wrap:wrap;gap:22px 24px;align-items:flex-start}',
    '.la-lock{position:absolute;inset:0;color:#fff;overflow:hidden}',
    '.la-lock .date{position:absolute;left:0;right:0;top:78px;text-align:center;font:600 20px/1 var(--font-d);opacity:.9}',
    '.la-lock .time{position:absolute;left:0;right:0;top:100px;text-align:center;font:600 92px/1.05 var(--font-d);letter-spacing:-.01em}',
    '.la-lock .stack{position:absolute;left:16px;right:16px;bottom:120px;display:flex;flex-direction:column;gap:8px;align-items:center;z-index:2}',
    '.la-lock .fl{position:absolute;bottom:46px;width:50px;height:50px;border-radius:50%;display:grid;place-items:center;z-index:2}',
    '.la-lock .fl svg{width:22px;height:22px}',
    '.la-banner{position:absolute;left:0;right:0;z-index:30;display:flex;justify-content:center;filter:drop-shadow(0 8px 20px rgba(0,0,0,.45))}',
    '.la-watch{position:relative;flex:none;background:#000;box-shadow:0 0 0 2px #3a3a3e inset,0 0 0 1px #000,0 14px 30px rgba(0,0,0,.35);box-sizing:border-box}',
    '.la-watch .scr{position:absolute;inset:0;overflow:hidden;color:#fff;font-family:var(--font);background:#000}',
    '.la-note{margin:0;font:12px/1.45 var(--font);color:rgba(255,255,255,.7);max-width:560px}',
    '.la-tbl{border-collapse:collapse;font:12px/1.4 var(--font);color:#fff;width:100%}',
    '.la-tbl th,.la-tbl td{border-bottom:1px solid rgba(255,255,255,.14);padding:6px 8px;text-align:left;vertical-align:top}',
    '.la-tbl th{font-weight:600;color:rgba(255,255,255,.7);font-size:11px;letter-spacing:.04em;text-transform:uppercase}',
    '.la-tbl code{font:11px var(--mono)}',
    '.la-notif{box-sizing:border-box;width:370px;max-width:100%;border-radius:24px;padding:12px 14px;color:#fff;font-family:var(--font);text-align:left;background:rgba(44,44,48,.8);-webkit-backdrop-filter:blur(30px) saturate(1.6);backdrop-filter:blur(30px) saturate(1.6);box-shadow:inset 0 0 0 .5px rgba(255,255,255,.14);flex:none}',
    '.k-reduce-transparency .la-notif{background:#2c2c30;-webkit-backdrop-filter:none;backdrop-filter:none}',
    '.la-notif .hd{display:flex;gap:10px;align-items:flex-start}',
    '.la-notif .tx{flex:1;min-width:0;display:flex;flex-direction:column;gap:1px}',
    '.la-notif .t{font-weight:600;line-height:1.25}.la-notif .s{font-weight:600;line-height:1.25;color:rgba(255,255,255,.92)}.la-notif .b{line-height:1.3;color:rgba(255,255,255,.92)}',
    '.la-notif .tm{color:rgba(255,255,255,.55);white-space:nowrap}',
    '.la-notif .th{flex:none;width:48px;height:48px;border-radius:9px;overflow:hidden}',
    '.la-actions{box-sizing:border-box;width:370px;max-width:100%;border-radius:24px;background:rgba(44,44,48,.8);overflow:hidden;color:#fff;font-family:var(--font);margin-top:8px;-webkit-backdrop-filter:blur(30px);backdrop-filter:blur(30px)}',
    '.la-actions .ac{display:flex;align-items:center;gap:12px;min-height:50px;padding:0 16px;border-top:.5px solid rgba(255,255,255,.14);box-sizing:border-box}',
    '.la-actions .ac:first-child{border-top:0}',
    '.la-actions .ac svg{width:20px;height:20px;flex:none}',
    '.la-actions .ac.destr{color:#ff6961}',
    '.la-actions .in{flex:1;min-width:0;height:34px;border-radius:17px;background:rgba(255,255,255,.12);padding:0 14px;display:flex;align-items:center;color:rgba(255,255,255,.5)}',
    '.la-cam16{position:relative;box-sizing:border-box;width:370px;max-width:100%;aspect-ratio:16/9;background:#000;overflow:hidden;color:#fff;font-family:var(--font);flex:none}',
    '.la-cam16 .snap{position:absolute;inset:0}',
    '.la-cam16 .badge{position:absolute;left:10px;top:10px;display:inline-flex;align-items:center;gap:5px;padding:4px 8px;border-radius:999px;background:#ff3b30;font-weight:600;font-size:12px;line-height:1.2}',
    '.la-cam16 .badge svg{width:8px;height:8px}',
    '.la-cam16 .spin{position:absolute;left:10px;top:10px;width:20px;height:20px;border-radius:50%;border:2.5px solid rgba(255,255,255,.3);border-top-color:#fff;animation:la-spin .82s linear infinite}',
    '.k-reduce-motion .la-cam16 .spin{animation-duration:1.64s}',
    '@keyframes la-spin{to{transform:rotate(360deg)}}',
    '.la-sw{display:flex;align-items:center;gap:6px}.la-sw i{width:14px;height:14px;border-radius:4px;display:inline-block;border:1px solid rgba(255,255,255,.3)}',
  ].join('\n');
  var styleEl = document.createElement('style'); styleEl.textContent = css; document.head.appendChild(styleEl);

  /* ------------------------------------------------------------------ Dynamic Type (the kit's --fs table) */
  var FS = { lt: [34, 40, 44], t1: [28, 34, 52], hd: [17, 23, 53], sub: [15, 21, 49], foot: [13, 19, 47], c1: [12, 18, 46] };
  function idx(ctx, cap) { var i = { 'default': 0, xxxl: 1, ax5: 2 }[(ctx && ctx.ts) || 'default'] || 0; return cap ? Math.min(i, 1) : i; }
  /** The size of a text style at the context's Dynamic Type setting (cap = true: the island, capped at xxxLarge). */
  LA.size = function (ctx, style, cap) { return FS[style][idx(ctx || Mock.current, cap)]; };
  /** A design size (17, 24, 32 pt) that scales like a text style (ActivityFont.swift: ScaledMetric relativeTo). */
  LA.scaled = function (ctx, base, style, cap) { var f = FS[style]; return Math.round(base * f[idx(ctx || Mock.current, cap)] / f[0] * 10) / 10; };
  /** isAccessibilitySize in the app's views (the island is capped, so never). */
  LA.isAX = function (ctx, cap) { ctx = ctx || Mock.current; return !cap && !!ctx && ctx.ts === 'ax5'; };
  function px(n) { return n + 'px'; }

  /* ------------------------------------------------------------------ colours (ActivityStyle.swift) */
  var KNOWN_TINTS = ['lights', 'heating', 'cooling', 'vents', 'air', 'water', 'occupancy', 'contact', 'media', 'cleaning', 'power', 'cooking', 'climate', 'neutral'];
  LA.accent = function (tint) { return 'var(--fam-' + (KNOWN_TINTS.indexOf(tint) >= 0 ? tint : 'neutral') + '-glyph)'; };
  LA.SEV = {
    critical: { circle: '#FF453A', light: '#FFB4AE', g0: 'rgba(255,69,58,.30)', g1: 'rgba(120,20,20,.55)', hair: 'rgba(255,120,110,.45)', ground: 'rgba(62,22,20,.92)', label: 'critical (red): it stopped and needs you', word: 'Needs help' },
    warning: { circle: '#FF9F0A', light: '#FFD59A', g0: 'rgba(255,159,10,.26)', g1: 'rgba(110,62,0,.50)', hair: 'rgba(255,190,90,.45)', ground: 'rgba(58,40,8,.92)', label: 'warning (amber): it carries on', word: 'Attention' },
  };
  LA.NOTICE = '#FFD59A';
  LA.ICON_CHOICES = [
    ['navySky', 'Navy + Sky', 0x7CC4FF, 0x0E1E46], ['tealMint', 'Teal + Mint', 0x6EE7C8, 0x063A3E], ['plumLilac', 'Plum + Lilac', 0xD3A8FF, 0x3A1648],
    ['forestGreen', 'Forest + Green', 0x9BE29B, 0x10301E], ['burgundyRose', 'Burgundy + Rose', 0xFF9EB0, 0x48101E], ['indigoPeriwinkle', 'Indigo + Periwinkle', 0xA8B4FF, 0x221C5A],
    ['espressoAmber', 'Espresso + Amber', 0xFFB35C, 0x342014], ['midnightGold', 'Midnight + Gold', 0xFFD36B, 0x101630],
  ];
  function hex(n) { return '#' + ('000000' + n.toString(16)).slice(-6).toUpperCase(); }

  /* ------------------------------------------------------------------ the house and heart (HouseHeartShape.swift, AppIconArtwork geometry) */
  var HOUSE = 'M50 12 L90 44 Q92 46 89 47 L82 47 L82 84 Q82 88 78 88 L22 88 Q18 88 18 84 L18 47 L11 47 Q8 46 10 44 Z M25 59h9.5v9.5H25z M37 59h9.5v9.5H37z M25 71h9.5v9.5H25z M37 71h9.5v9.5H37z';
  var HEART = 'M50 88 C20 66 8 50 8 34 C8 20 19 10 32 10 C40 10 46 14 50 21 C54 14 60 10 68 10 C81 10 92 20 92 34 C92 50 80 66 50 88 Z';
  var markId = 0;
  /** The corner mark: house and heart, no tile; the heart sits in a ring cut out of the house (real transparency). choice = AppIconChoice raw value. */
  LA.mark = function (size, choice) {
    var color = hex((LA.ICON_CHOICES.filter(function (c) { return c[0] === (choice || 'navySky'); })[0] || LA.ICON_CHOICES[0])[2]), id = 'la-m' + (++markId);
    return h('span.la-mark', { 'aria-hidden': 'true', style: { width: px(size), height: px(size), display: 'inline-block' }, html:
      '<svg viewBox="0 0 100 100" width="' + size + '" height="' + size + '"><defs><mask id="' + id + '" maskUnits="userSpaceOnUse" x="0" y="0" width="100" height="100"><rect width="100" height="100" fill="#fff"/>' +
      '<g transform="translate(55 60) scale(.4)"><path d="' + HEART + '" fill="#000" stroke="#000" stroke-width="16" stroke-linejoin="round"/></g></mask></defs>' +
      '<path d="' + HOUSE + '" fill="' + color + '" fill-rule="evenodd" mask="url(#' + id + ')"/><g transform="translate(55 60) scale(.4)"><path d="' + HEART + '" fill="' + color + '"/></g></svg>' });
  };
  /** The app icon as a tile (full-bleed tinted glass, stand-in): used by the notification banners. */
  LA.appIcon = function (size, choice) {
    var c = LA.ICON_CHOICES.filter(function (x) { return x[0] === (choice || 'navySky'); })[0] || LA.ICON_CHOICES[0];
    return h('span', { 'aria-hidden': 'true', style: { width: px(size), height: px(size), borderRadius: px(size * .224), flex: 'none', display: 'inline-grid', placeItems: 'center', overflow: 'hidden',
      background: 'radial-gradient(circle at 80% 85%, rgba(255,170,90,.35), transparent 55%), linear-gradient(165deg, #3a4a78, #1a2038), ' + hex(c[3]), boxShadow: 'inset 0 0 0 .5px rgba(255,255,255,.18)' } },
      h('span', { style: { width: '80%', height: '80%', display: 'block' } }, LA.mark(size * .8, c[0])));
  };

  /* ------------------------------------------------------------------ glyphs (ActivityGlyphImage.swift symbolName; stand-in drawings) */
  var G = {
    dishwasher: '<rect x="4" y="3" width="16" height="18" rx="2.6"/><path d="M4 8h16M7.5 5.5h.01M10.5 5.5h.01"/><circle cx="12" cy="14.6" r="3.3"/>',
    washer: '<rect x="4" y="3" width="16" height="18" rx="2.6"/><path d="M7.5 5.9h.01M10.5 5.9h.01"/><circle cx="12" cy="13.4" r="4.7"/><path d="M9.3 13.4q1.35-1.3 2.7 0t2.7 0"/>',
    dryer: '<rect x="4" y="3" width="16" height="18" rx="2.6"/><path d="M7.5 5.9h.01M10.5 5.9h.01"/><circle cx="12" cy="13.4" r="4.7"/><path d="M12 10.4v6" opacity=".6"/>',
    hot_flash: '<path d="M8.4 14.6V5.6a2 2 0 0 1 4 0v9a3.6 3.6 0 1 1-4 0z"/><path d="M17.6 5.5v9M14.2 7.4l6.8 5.2M21 7.4l-6.8 5.2"/>',
    generic: '<circle cx="12" cy="12" r="8" stroke-dasharray="2.7 2.7"/>',
    alert: '<path d="M12 5.5v8.5M12 18.4v.01" stroke-width="3"/>',
    dock: '<path d="M13.2 3.5 6 13.6h5.2l-1 6.9 7.6-10.4h-5.4z" transform="rotate(90 12 12)"/>',
    edge: '<path d="M12 4v10.5M7.4 10.2 12 14.8l4.6-4.6M5 19.6h14"/>',
    brush: '<path d="M3.5 15.5c2.2-7 3.4-9 5-7s-1.2 8.4 1.8 6.2 3.8-9.2 5.5-7-1.6 8.2.6 6.8 2.7-3.2 4.1-2.4"/>',
    battery: '<rect x="2.5" y="8" width="17" height="8.4" rx="2.4"/><path d="M21.6 11.2v2"/><rect x="4.7" y="10.2" width="3.8" height="4" rx=".9" fill="currentColor" stroke="none"/>',
    mop: '<path d="M3 8.4q2.25-2.2 4.5 0t4.5 0 4.5 0 4.5 0M3 13q2.25-2.2 4.5 0t4.5 0 4.5 0 4.5 0M3 17.6q2.25-2.2 4.5 0t4.5 0 4.5 0 4.5 0"/>',
    bag: '<path d="M5.4 8.2h13.2l-1 12.2H6.4z" fill="currentColor" fill-opacity=".9"/><path d="M9 8.2V6.6a3 3 0 0 1 6 0v1.6"/>',
  };
  var G_ICON = { fan: ['fan', 1], vacuum: ['robotic.vacuum', 0], water: ['drop.fill', 1], waste: ['trash.fill', 1], door: ['door.left.hand.closed', 0], door_dish: ['door.left.hand.open', 0], question: ['questionmark', 0] };
  /** SF Symbol names the app draws for each glyph id (ActivityGlyphImage.swift). */
  LA.SYMBOL = { fan: 'fan.fill', dishwasher: 'dishwasher.fill', dryer: 'dryer.fill', washer: 'washer.fill', vacuum: 'robotic.vacuum', hot_flash: 'thermometer.snowflake', generic: 'circle.dashed',
    alert: 'exclamationmark', door: 'door.left.hand.closed', dock: 'bolt.horizontal.fill', edge: 'arrow.down.to.line', brush: 'scribble', battery: 'battery.25percent', water: 'drop.fill',
    waste: 'trash.fill', mop: 'water.waves', bag: 'bag.fill', question: 'questionmark', door_dish: 'door.left.hand.open' };
  LA.JOB_GLYPHS = ['fan', 'dishwasher', 'dryer', 'washer', 'vacuum', 'hot_flash', 'generic'];
  LA.PROBLEM_GLYPHS = ['alert', 'door', 'dock', 'edge', 'brush', 'battery', 'water', 'waste', 'mop', 'bag', 'question', 'door_dish'];
  /** A glyph at `size` pt in `color`, hidden from VoiceOver (the card's own label says what it is). */
  LA.glyph = function (id, size, color, weight) {
    var inner;
    if (G_ICON[id]) inner = Mock.icon(G_ICON[id][0], { fill: !!G_ICON[id][1], weight: weight || 2.1 });
    else if (G[id]) inner = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="' + (weight || 2.1) + '" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + G[id] + '</svg>';
    else inner = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-dasharray="3 3" aria-hidden="true"><circle cx="12" cy="12" r="8"/></svg>';
    return h('span.la-g', { 'aria-hidden': 'true', style: { width: px(size), height: px(size), color: color || '#fff' }, html: inner });
  };
  function check(size, color) { return h('span.la-g', { 'aria-hidden': 'true', style: { width: px(size), height: px(size), color: color }, html: Mock.icon('checkmark', { weight: 3.4 }) }); }

  /* ------------------------------------------------------------------ the card model (ActivityCard.swift) */
  function clock(sec) {
    sec = Math.max(0, Math.floor(sec)); var hr = Math.floor(sec / 3600), mi = Math.floor(sec % 3600 / 60), s = sec % 60;
    function p(v) { return v < 10 ? '0' + v : '' + v; }
    return hr > 0 ? hr + ':' + p(mi) + ':' + p(s) : mi + ':' + p(s);
  }
  LA.clock = clock;
  function dur(sec, up) {
    var t = Math.floor(up ? Math.ceil(sec) : sec); if (t < 60) return 'less than a minute';
    var m = up ? Math.floor((t + 59) / 60) : Math.floor(t / 60), hr = Math.floor(m / 60), r = m % 60;
    function u(v, w) { return v + ' ' + w + (v === 1 ? '' : 's'); }
    return hr === 0 ? u(m, 'minute') : (r === 0 ? u(hr, 'hour') : u(hr, 'hour') + ' ' + u(r, 'minute'));
  }
  var KNOWN_GLYPHS = ['fan', 'dishwasher', 'dryer', 'washer', 'vacuum', 'hot_flash', 'generic', 'alert', 'door', 'dock', 'edge', 'brush', 'battery', 'water', 'waste', 'mop', 'bag', 'question', 'door_dish'];
  function glyphFor(a) {
    if (KNOWN_GLYPHS.indexOf(a.symbol) >= 0) return a.symbol;
    if (KNOWN_GLYPHS.indexOf(a.kind) >= 0) return a.kind;
    return a.kind === 'bathroom_fan' ? 'fan' : (a.kind === 'problem' ? 'alert' : 'generic');
  }
  var PEND = { stop: 'Stopping…', cancel: 'Stopping…', cancel_timer: 'Stopping…', pause: 'Pausing…', resume: 'Resuming…', dock: 'Docking…', done: 'Completing…', try_again: 'Trying again…' };
  var COMPACT_LABEL = { 'navigation.stuck': 'Stuck', 'navigation.target_unreachable': 'Blocked', 'navigation.dock_unreachable': 'No dock', 'navigation.ramp_hazard': 'Edge',
    'maintenance.main_brush_jammed': 'Brush', 'maintenance.side_brush_jammed': 'Brush', 'power.critical_battery': 'Battery', 'power.low_battery': 'Battery', 'mop.clean_water_empty': 'Refill water',
    'mop.dirty_water_unavailable': 'Empty tank', 'mop.attachment_missing': 'No mop', 'dock.cover_open': 'Cover open', 'dock.dustbag_blocked': 'Dust bag' };

  /** The card for a fixture {attrs, state, isStale}. Mirrors ActivityCard: the views only translate this into pixels. */
  LA.card = function (fx) {
    var a = fx.attrs, s = fx.state, c = { fx: fx, a: a, s: s, isStale: !!fx.isStale };
    c.paused = s.phase === 'paused'; c.complete = s.phase === 'done';
    c.problem = s.phase === 'problem' && s.problem ? s.problem : null;
    c.glyph = glyphFor(a);
    // figure
    var v = s.value, f = { k: 'none' };
    if (c.complete) f = { k: 'complete' };
    else if (v) {
      if (v.kind === 'countdown') f = { k: 'countdown', left: v.left, hours: v.left >= 3600, estimated: !!v.estimated };
      else if (v.kind === 'countup') f = c.paused ? { k: 'frozen', sec: v.pausedElapsed != null ? v.pausedElapsed : v.elapsed } : { k: 'countup', elapsed: v.elapsed };
      else if (v.kind === 'percent') f = s.progress == null ? { k: 'none' } : { k: 'percent', v: Math.round(Math.min(Math.max(s.progress, 0), 1) * 100) };
      else if (v.kind === 'text') f = v.text ? { k: 'text', text: v.text } : { k: 'none' };
    }
    c.figure = f;
    c.title = (s.headline && f.k !== 'none') ? s.headline : a.title;
    c.bigLine = (f.k === 'none' && s.headline) ? s.headline : null;
    c.detail = s.detail || null;
    c.headerLine = c.detail ? c.title + ' · ' + c.detail : c.title;
    c.short = s.short || null;
    // ring and bar
    var ring = { k: 'track' };
    if (c.complete) ring = { k: 'complete' };
    else if (!c.paused && v && v.kind === 'countdown' && v.total > v.left) ring = { k: 'timer', f: 1 - v.left / v.total };
    else if (v && v.kind === 'countup') ring = { k: 'steady' };
    else if (s.progress != null) ring = { k: 'fraction', f: Math.min(Math.max(s.progress, 0), 1) };
    c.ring = ring;
    c.bar = ring.k === 'timer' || ring.k === 'fraction' ? { k: ring.k, f: ring.f } : (ring.k === 'complete' ? { k: 'full', f: 1 } : null);
    c.showsRing = ring.k !== 'track';
    c.styleKind = c.problem ? c.problem.severity : 'job';
    // pending, notice
    c.pendingLabel = s.pending && !c.isStale ? s.pending.label : null;
    c.isUnconfirmed = !!s.pending && c.isStale;
    c.notice = s.notice || null;
    // buttons
    var limit = c.problem ? 3 : 2;
    c.buttons = (c.pendingLabel || c.complete) ? [] : s.controls.slice(0, limit).map(function (ct, i) {
      var icon = null;
      if (!c.problem && c.glyph === 'vacuum') icon = { pause: 'pause', resume: 'play', dock: 'dock' }[ct.id] || null;
      return { id: ct.id, title: ct.title, primary: i === 0 || ct.role === 'primary', label: ct.title + ' ' + a.title, icon: icon };
    });
    c.islandButtons = c.buttons.slice(0, 2);
    // compact trailing
    var ct;
    if (c.problem) ct = { k: 'problem', word: COMPACT_LABEL[c.problem.code] || (c.problem.severity === 'critical' ? 'Help' : 'Check') };
    else if (f.k === 'complete') ct = { k: 'complete' };
    else if (f.k === 'countdown') ct = { k: 'timer', tpl: f.hours ? '0:00:00' : '00:00' };
    else if (f.k === 'countup') ct = { k: 'timer', tpl: '0:00:00' };
    else if (f.k === 'frozen') ct = { k: 'timer', tpl: f.sec >= 3600 ? '0:00:00' : '00:00' };
    else if (f.k === 'percent') ct = { k: 'label', text: c.short || f.v + '%' };
    else if (f.k === 'text') ct = { k: 'label', text: c.short || f.text };
    else ct = c.short ? { k: 'label', text: c.short } : { k: 'none' };
    c.compactTrailing = ct;
    // text of the figure
    c.figureText = f.k === 'countdown' ? clock(f.left) : f.k === 'countup' ? clock(f.elapsed) : f.k === 'frozen' ? clock(f.sec) : f.k === 'percent' ? f.v + '%' : f.k === 'text' ? f.text : f.k === 'complete' ? 'Complete' : '';
    // speech
    c.spokenFigure = f.k === 'countdown' ? ((f.estimated ? 'about ' : '') + (f.left <= 0 ? 'done' : dur(f.left, true) + ' left')) : f.k === 'countup' ? 'running for ' + dur(f.elapsed)
      : f.k === 'frozen' ? 'paused at ' + dur(f.sec) : f.k === 'percent' ? f.v + ' percent' : f.k === 'text' ? f.text : f.k === 'complete' ? 'complete' : null;
    c.spokenTitle = f.k === 'countup' ? c.headerLine + ', running for' : f.k === 'frozen' ? c.headerLine + ', paused at' : f.k === 'countdown' ? c.headerLine + (f.estimated ? ', about' : ', time left') : c.headerLine;
    if (c.problem) {
      var parts = [a.title + ', ' + (c.problem.severity === 'critical' ? 'needs help' : 'needs attention') + ': ' + c.problem.problem + '. ' + c.problem.message];
      c.spokenSummary = parts.concat(c.problem.chips || []).join(', ');
    } else {
      var pp = [c.title]; if (c.detail) pp.push(c.detail); if (c.bigLine) pp.push(c.bigLine); if (c.spokenFigure) pp.push(c.spokenFigure);
      c.spokenSummary = pp.join(', ');
    }
    return c;
  };

  /* ------------------------------------------------------------------ fixtures (HomeActivityFixtures.swift) */
  function A(tag, title, kind, symbol, tint) { return { tag: tag, title: title, kind: kind, symbol: symbol, tint: tint }; }
  function ct(id, title, role) { return { id: id, title: title, role: role || 'secondary' }; }
  function down(left, past) { return { kind: 'countdown', left: left, total: left + past }; }
  function up(elapsed) { return { kind: 'countup', elapsed: elapsed }; }
  function S(o) { return Object.assign({ phase: 'running', controls: [] }, o); }
  function clone(x) { return JSON.parse(JSON.stringify(x)); }
  function fan(left, title) { return { attrs: A('job.fan.guest', title || 'Guest Bath Fan', 'fan', 'fan', 'air'), state: S({ value: down(left, 300), controls: [ct('stop', 'Stop')], url: '/sfenton-react-dash/home?path=guest-bathroom' }) }; }
  function dish() { return { attrs: A('job.dishwasher', 'Dishwasher', 'dishwasher', 'dishwasher', 'cleaning'), state: S({ value: down(2520, 8000), controls: [ct('stop', 'Stop')], url: '/sfenton-react-dash/home?path=kitchen' }) }; }
  function laundry(kind, title, elapsed) { return { attrs: A('job.' + kind, title, kind, kind, 'cleaning'), state: S({ value: up(elapsed), url: '/sfenton-react-dash/home?path=laundry' }) }; }
  function vac(headline, short, tint) { return { attrs: A('job.vacuum.main_floor', 'Main Floor Vacuum', 'vacuum', 'vacuum', tint), state: S({ headline: headline, short: short, controls: [ct('pause', 'Pause'), ct('dock', 'Dock', 'secondary')], url: '/sfenton-react-dash/home?path=vacuums' }) }; }
  function flash(line, remaining) { return { attrs: A('job.hot_flash', 'Hot Flash', 'hot_flash', 'hot_flash', 'cooling'), state: S({ detail: line, value: down(remaining || 760, 140), controls: [ct('stop', 'Stop')], url: '/sfenton-react-dash/home?path=master-bedroom' }) }; }
  function done(b) { b = clone(b); b.state.phase = 'done'; b.state.value = { kind: 'text', text: 'Complete' }; b.state.progress = 1; b.state.controls = []; return b; }
  function awaiting(b, control) { b = clone(b); b.state.notice = null; b.state.pending = { control: control, label: PEND[control] || 'Working…' }; return b; }

  /** Problem rows of the spec's section 5 table (HomeActivityFixtures.problemRows). */
  LA.PROBLEMS = [
    { code: 'navigation.stuck', sev: 'critical', icon: 'alert', problem: 'Stuck in Kitchen', message: 'Move it somewhere flat, then tap Resume.', buttons: [['resume', 'Resume'], ['dock', 'Dock']], task: true },
    { code: 'navigation.target_unreachable', sev: 'critical', icon: 'door', problem: "Can't reach Office", message: 'A door may be closed. Open it, then tap Resume.', buttons: [['resume', 'Resume'], ['dock', 'Dock']], task: true },
    { code: 'navigation.dock_unreachable', sev: 'critical', icon: 'dock', problem: "Can't get back to the dock", message: 'Clear the way to the dock or carry it there.', buttons: [['try_again', 'Try Again']], task: true },
    { code: 'navigation.ramp_hazard', sev: 'critical', icon: 'edge', problem: 'Stopped at a drop or ramp', message: 'Move it away from the edge, then tap Resume.', buttons: [['resume', 'Resume'], ['dock', 'Dock']], task: true },
    { code: 'maintenance.main_brush_jammed', sev: 'critical', icon: 'brush', problem: 'Main brush jammed', message: 'Turn it over, clear the brush, then tap Resume.', buttons: [['resume', 'Resume'], ['dock', 'Dock']], task: true },
    { code: 'maintenance.side_brush_jammed', sev: 'critical', icon: 'brush', problem: 'Side brush jammed', message: 'Untangle the side brush, then tap Resume.', buttons: [['resume', 'Resume'], ['dock', 'Dock']], task: true },
    { code: 'power.critical_battery', sev: 'critical', icon: 'battery', problem: 'Battery critically low', message: 'Carry it to the dock to charge.', buttons: [], task: false },
    { code: 'power.low_battery', sev: 'warning', icon: 'battery', problem: 'Battery low', message: 'Heading to the dock. It finishes Kitchen after charging.', buttons: [], task: false },
    { code: 'mop.clean_water_empty', sev: 'warning', icon: 'water', problem: 'Clean water tank empty', message: 'Refill the clean water tank on the dock, then tap Resume.', buttons: [['resume', 'Resume']], task: true },
    { code: 'mop.dirty_water_unavailable', sev: 'warning', icon: 'waste', problem: 'Wastewater tank full or missing', message: 'Empty the wastewater tank and seat it firmly.', buttons: [['resume', 'Resume']], task: true },
    { code: 'mop.attachment_missing', sev: 'warning', icon: 'mop', problem: 'Mop pads missing', message: 'Attach the mop pads, or it vacuums only.', buttons: [['vacuum_only', 'Vacuum Only']], task: true },
    { code: 'mop.vacuum_only_fallback', sev: 'warning', icon: 'mop', problem: 'Vacuuming only', message: "Mopping isn't available. Check the mop attachment, water tanks and pads.", buttons: [], task: false, device: 'Studio Vacuum', tag: 'job.vacuum.music_room' },
    { code: 'dock.cover_open', sev: 'warning', icon: 'bag', problem: 'Dock cover open', message: 'Check the dust bag is in, then close the cover.', buttons: [], task: true },
    { code: 'dock.dustbag_blocked', sev: 'warning', icon: 'bag', problem: 'Dust bag full', message: 'Replace the dust bag in the dock.', buttons: [], task: true },
    { code: 'vendor.unknown_error_88', sev: 'critical', icon: 'question', problem: 'Stopped with an error', message: 'Check the robot, then tap Resume.', buttons: [['resume', 'Resume'], ['dock', 'Dock']], task: false, chips: ['Error 88'] },
    { code: 'unmapped.wheel_suspended', sev: 'critical', icon: 'question', problem: 'Stopped with an error', message: 'The robot says “Wheel suspended”. Check it, then tap Resume.', buttons: [['resume', 'Resume'], ['dock', 'Dock']], task: false },
    { code: 'dishwasher.actionrequired', sev: 'warning', icon: 'door_dish', problem: 'Needs attention', message: "Check the dishwasher's display.", buttons: [], task: false, device: 'Dishwasher', tag: 'job.dishwasher', kind: 'dishwasher', symbol: 'dishwasher' },
    { code: 'dishwasher.error', sev: 'critical', icon: 'question', problem: 'Stopped with an error', message: "Check the dishwasher's display.", buttons: [], task: false, device: 'Dishwasher', tag: 'job.dishwasher', kind: 'dishwasher', symbol: 'dishwasher' },
    { code: 'dishwasher.rinse_aid', sev: 'warning', icon: 'water', problem: 'Rinse aid low', message: 'Refill the rinse aid.', buttons: [], task: true, device: 'Dishwasher', tag: 'job.dishwasher', kind: 'dishwasher', symbol: 'dishwasher' },
  ];
  function problemFx(row, hasTask) {
    var controls = row.buttons.map(function (b) { return ct(b[0], b[1]); });
    if (hasTask) controls.push(ct('done', 'Done'));
    return { attrs: A(row.tag || 'job.vacuum.main_floor', row.device || 'Main Floor Vacuum', row.kind || 'vacuum', row.symbol || 'vacuum', 'cleaning'),
      state: S({ phase: 'problem', value: { kind: 'text', text: row.sev === 'critical' ? 'Needs help' : 'Attention' }, controls: controls,
        problem: { severity: row.sev, code: row.code, icon: row.icon, problem: row.problem, message: row.message, chips: row.chips || [], taskId: hasTask ? 'task-1042' : null }, url: '/sfenton-react-dash/home?path=vacuums' }) };
  }
  LA.problemSlug = function (row) { return 'problem-' + row.code.replace(/\./g, '-'); };

  /** A fixture by the app's name (HomeActivityFixtures.fixture). Times are fixed: a fan with 4:42 left, the dishwasher with 42:00, and so on. */
  LA.fx = function (name) {
    var r, i;
    switch (name) {
      case 'fan': r = fan(282); break;
      case 'fan-long': r = fan(3882, 'Bedroom 1 Closet Fan'); r.attrs.tag = 'job.fan.master'; break;
      case 'fan-xlong': r = fan(282, 'Bedroom 1 Closet Exhaust Fan'); r.attrs.tag = 'job.fan.master'; break;
      case 'fan-pending': r = awaiting(fan(282), 'stop'); break;
      case 'fan-pending-stale': r = awaiting(fan(282), 'stop'); r.isStale = true; break;
      case 'fan-notice': r = fan(282); r.state.notice = "Couldn't reach Home"; break;
      case 'dishwasher': r = dish(); break;
      case 'dishwasher-long': r = dish(); r.state.value = down(3882, 600); break;
      case 'dishwasher-percent': r = dish(); r.state.value = { kind: 'percent' }; r.state.progress = 0.62; break;
      case 'dishwasher-paused': r = dish(); r.state.phase = 'paused'; r.state.value = { kind: 'text', text: 'Paused' }; r.state.controls = [ct('resume', 'Resume'), ct('stop', 'Stop')]; break;
      case 'dishwasher-waiting': r = dish(); r.state.phase = 'waiting'; r.state.value = { kind: 'text', text: 'Starts 5:10 PM' }; r.state.controls = []; break;
      case 'dishwasher-complete': r = done(dish()); break;
      case 'dryer': r = laundry('dryer', 'Dryer', 1930); break;
      case 'dryer-estimated': r = laundry('dryer', 'Dryer', 600); r.state.value = { kind: 'countdown', left: 1200, total: 1800, estimated: true }; break;
      case 'dryer-complete': r = done(laundry('dryer', 'Dryer', 1930)); break;
      case 'washer': r = laundry('washer', 'Washing Machine', 372); break;
      case 'washer-complete': r = done(laundry('washer', 'Washing Machine', 372)); break;
      case 'vacuum': r = vac('Vacuuming Kitchen', 'Kitchen', 'cleaning'); break;
      case 'vacuum-mopping': r = vac('Mopping Kitchen', 'Kitchen', 'water'); break;
      case 'vacuum-cleaning': r = vac('Cleaning Living Room', 'Living Rm', 'cleaning'); break;
      case 'vacuum-drawn': r = vac('Cleaning Main Floor area', 'Area', 'cleaning'); break;
      case 'vacuum-long': r = vac('Vacuuming Bedroom 1 Closet', 'Closet', 'cleaning'); break;
      case 'vacuum-paused': r = vac('Paused in Kitchen', 'Paused', 'cleaning'); r.state.phase = 'paused'; r.state.controls = [ct('resume', 'Resume'), ct('dock', 'Dock', 'secondary')]; break;
      case 'hotflash-cooling': r = flash('Your side'); r.state.value = { kind: 'text', text: 'Cooling' }; r.state.progress = 0.45; break;
      case 'hotflash-holding': r = flash('Your side'); break;
      case 'hotflash-alex-bysam': r = flash("Alex's side · by Sam"); break;
      case 'hotflash-bysam': r = flash('Your side · by Sam'); break;
      case 'hotflash-byhome': r = flash('Your side · by Home'); break;
      case 'hotflash-wholebed': r = flash('Whole bed', 845); break;
      case 'hotflash-complete': r = done(flash('Your side')); break;
      case 'problem-completing': r = problemFx(LA.PROBLEMS[0], true); r = awaiting(r, 'done'); break;
      default:
        if (name.indexOf('problem-') === 0) {
          for (i = 0; i < LA.PROBLEMS.length; i++) {
            var row = LA.PROBLEMS[i], base = LA.problemSlug(row);
            if (name === base) { r = problemFx(row, row.task); break; }
            if (name === base + (row.task ? '-nodone' : '-done')) { r = problemFx(row, !row.task); break; }
          }
        }
    }
    if (!r) throw new Error('unknown fixture ' + name);
    r.name = name; return r;
  };
  /** Advance every timer by `sec` (a countdown loses time, a count-up gains it): what the system's live Text does on its own. */
  LA.advance = function (fx, sec) {
    var r = clone(fx), v = r.state.value;
    if (v && v.kind === 'countdown') v.left = Math.max(0, v.left - sec);
    if (v && v.kind === 'countup') v.elapsed += sec;
    return r;
  };
  /** Re-render every node in `root` that was built by a LA builder after `sec` seconds (the system's timers count with no pushes). */
  LA.tick = function (root, sec) {
    Array.prototype.slice.call(root.querySelectorAll('[data-la]')).forEach(function (n) {
      if (!n.__la) return;
      var next = n.__la.build(LA.advance(n.__la.fx, sec)); n.parentNode.replaceChild(next, n);
    });
  };
  function tag(node, fx, build) { node.dataset.la = '1'; node.__la = { fx: fx, build: build }; return node; }

  /* ------------------------------------------------------------------ fit-to-width text (minimumScaleFactor) */
  /** Shrink a one-line element's font until it fits, down to `floor` of its size, then clip with an ellipsis. */
  function fit(el, floor) {
    Mock.whenAttached(el, function () {
      var base = parseFloat(el.style.fontSize) || parseFloat(getComputedStyle(el).fontSize), size = base, guard = 0;
      while (el.scrollWidth > el.clientWidth + 1 && size > base * floor && guard++ < 60) { size -= .5; el.style.fontSize = size + 'px'; }
    });
    return el;
  }
  LA.fit = fit;

  /* ------------------------------------------------------------------ parts */
  /** The ring around a glyph (ActivityRing.swift): timer or fraction fills, steady is full, track is empty, complete is a filled ring with a check. */
  LA.ring = function (c, d) {
    var lw = Math.max(3, d * 6 / 64), r = (d - lw) / 2, circ = 2 * Math.PI * r, acc = LA.accent(c.a.tint), k = c.ring, svg = '';
    function track() { return '<circle cx="' + d / 2 + '" cy="' + d / 2 + '" r="' + r + '" fill="none" stroke="rgba(255,255,255,.14)" stroke-width="' + lw + '"/>'; }
    function arc(f) { return '<circle cx="' + d / 2 + '" cy="' + d / 2 + '" r="' + r + '" fill="none" stroke="' + acc + '" stroke-width="' + lw + '" stroke-linecap="round" stroke-dasharray="' + (circ * f) + ' ' + circ + '" transform="rotate(-90 ' + d / 2 + ' ' + d / 2 + ')"/>'; }
    if (k.k === 'timer' || k.k === 'fraction') svg = track() + arc(k.f);
    else if (k.k === 'steady') svg = '<circle cx="' + d / 2 + '" cy="' + d / 2 + '" r="' + r + '" fill="none" stroke="' + acc + '" stroke-width="' + lw + '"/>';
    else if (k.k === 'complete') svg = '<circle cx="' + d / 2 + '" cy="' + d / 2 + '" r="' + r + '" fill="' + acc + '" fill-opacity=".18" stroke="' + acc + '" stroke-width="' + lw + '"/>';
    else svg = track();
    return h('span', { 'aria-hidden': 'true', style: { position: 'relative', width: px(d), height: px(d), display: 'inline-grid', placeItems: 'center', flex: 'none' } },
      h('span', { style: { position: 'absolute', inset: 0, lineHeight: 0 }, html: '<svg width="' + d + '" height="' + d + '" viewBox="0 0 ' + d + ' ' + d + '">' + svg + '</svg>' }),
      c.complete ? check(d * .4, acc) : LA.glyph(c.glyph, d * .4, acc));
  };
  /** The solid severity shape with its glyph (SeverityCircle.swift): an octagon when it stopped, a triangle when it carries on. */
  LA.sev = function (glyph, severity, d) {
    var crit = severity === 'critical';
    return h('span', { 'aria-hidden': 'true', style: { width: px(d), height: px(d), clipPath: crit ? 'polygon(30% 0,70% 0,100% 30%,100% 70%,70% 100%,30% 100%,0 70%,0 30%)' : 'polygon(50% 6%,98% 90%,2% 90%)', background: LA.SEV[severity].circle, display: 'inline-grid', placeItems: 'center', flex: 'none' } },
      h('span', { style: { display: 'grid', placeItems: 'center', transform: crit ? null : 'translateY(' + px(d * .09) + ')' } }, LA.glyph(glyph, d * (crit ? .46 : .38), '#fff', 2.8)));
  };
  /** The header glyph in the job's tint (a check once Complete). */
  LA.headerGlyph = function (c, size) {
    var acc = LA.accent(c.a.tint);
    return h('span', { 'aria-hidden': 'true', style: { width: px(size), height: px(size), display: 'inline-grid', placeItems: 'center', flex: 'none' } }, c.complete ? check(size * .9, acc) : LA.glyph(c.glyph, size, acc));
  };
  LA.bar = function (c) {
    return h('div.la-bar', { 'aria-hidden': 'true', style: { '--la-accent': LA.accent(c.a.tint) } }, h('i', { style: { width: (c.bar.f * 100).toFixed(1) + '%' } }));
  };
  /** The buttons of a card (ActivityButtons.swift): pills, the vacuum's round icons, "Stopping…" while pending, "Not confirmed" beside restored buttons. */
  LA.buttons = function (c, list, o) {
    o = o || {}; var ctx = o.ctx || Mock.current, cap = o.cap, ax = LA.isAX(ctx, cap), fills = o.fills !== false, chips = o.chips || [];
    var sub = LA.size(ctx, 'sub', cap), c1 = LA.size(ctx, 'c1', cap);
    function chipEls() { return chips.map(function (t) { return h('span.la-chip', { 'aria-hidden': 'true', style: { fontSize: px(LA.size(ctx, 'c1', cap)) } }, t); }); }
    if (c.pendingLabel) return h('div.la-btns' + (fills ? '.fill' : ''), chipEls(), fills ? h('span.sp') : null, h('span.la-pending', { style: { fontSize: px(sub) } }, c.pendingLabel));
    if (!list.length && !chips.length && !c.isUnconfirmed) return null;
    var status = c.isUnconfirmed ? h('span.la-unconf', { style: { fontSize: px(c1) } }, 'Not confirmed') : null;
    var pills = list.map(function (b) {
      var inner;
      if (b.icon) inner = h('span.rnd', { html: Mock.icon({ pause: 'pause.fill', play: 'play.fill', dock: 'house.fill' }[b.icon], { fill: true }) });
      else inner = h('span.pill', { style: { fontSize: px(sub) } }, b.title);
      return h('button.la-btn' + (b.primary ? '.primary' : ''), { type: 'button', 'aria-label': b.label, title: b.label }, inner);
    });
    if (ax) return h('div.la-btns.ax', { style: { width: '100%' } }, status, pills);
    return h('div.la-btns' + (fills ? '.fill' : ''), chipEls(), status, fills ? h('span.sp') : null, pills);
  };

  /* ------------------------------------------------------------------ the value line (ActivityValueLine.swift) */
  function valueLine(c, ctx, size, rel, cap) {
    var ax = LA.isAX(ctx, cap);
    if (c.notice) return h('div.la-val.wrap', { style: { fontSize: px(LA.size(ctx, 'sub', cap)), color: LA.NOTICE, display: '-webkit-box', WebkitLineClamp: 2, WebkitBoxOrient: 'vertical', overflow: 'hidden' } }, c.notice);
    if (c.bigLine) return h('div.la-val.wrap', { style: { fontSize: px(LA.scaled(ctx, 24, 't1', cap)), lineHeight: 1.15, display: '-webkit-box', WebkitLineClamp: ax ? 4 : 2, WebkitBoxOrient: 'vertical', overflow: 'hidden' } }, c.bigLine);
    var fz = LA.scaled(ctx, size || 32, rel || 'lt', cap);
    var el = h('div.la-val', { style: { fontSize: px(fz), color: c.complete ? LA.accent(c.a.tint) : '#fff', lineHeight: 1.1 } }, c.figureText);
    return fit(el, c.figure.k === 'text' ? .5 : .8);
  }

  /* ------------------------------------------------------------------ Lock Screen, banner and StandBy card */
  /** The job card, layout L4 (JobCardView.swift). o: ctx, mark (default true), width, choice. */
  LA.jobCard = function (fx, o) {
    o = o || {}; var ctx = o.ctx || Mock.current, c = LA.card(fx), ax = LA.isAX(ctx), marks = o.mark !== false;
    var titleEl = h('div.la-title.la-clamp', { style: { fontSize: px(LA.size(ctx, 'hd')), WebkitLineClamp: ax ? 4 : 2 } }, c.headerLine);
    var header = h('div.la-row', LA.headerGlyph(c, 22), titleEl, marks ? LA.mark(24, o.choice) : null);
    var btns = LA.buttons(c, c.buttons, { ctx: ctx, fills: false });
    var vrow = h('div.la-valrow' + (ax ? '.ax' : ''), { style: ax ? null : { minHeight: c.buttons.length ? '44px' : '' } }, valueLine(c, ctx), btns);
    var card = h('div.la-card.job', { role: 'group', 'aria-label': c.spokenSummary, style: o.width ? { width: px(o.width) } : null },
      h('div.la-in', header, vrow, c.bar ? LA.bar(c) : null));
    return tag(card, fx, function (f) { return LA.jobCard(f, o); });
  };
  /** The problem card (ProblemCardView.swift): severity circle, device, problem, instruction, chip, buttons, 40 pt mark. */
  LA.problemCard = function (fx, o) {
    o = o || {}; var ctx = o.ctx || Mock.current, c = LA.card(fx), p = c.problem, sev = LA.SEV[p.severity], ax = LA.isAX(ctx), marks = o.mark !== false;
    var first = h('div', { style: { paddingRight: marks ? '48px' : '0' } },
      h('div.la-clamp', { style: { fontSize: px(LA.size(ctx, 'hd')), fontWeight: 600, WebkitLineClamp: ax ? 3 : 1 } }, c.a.title),
      h('div.la-clamp', { style: { fontSize: px(LA.size(ctx, 'sub')), fontWeight: 600, color: sev.light, WebkitLineClamp: ax ? 4 : 1, marginTop: '2px' } }, h('b', null, p.severity === 'critical' ? 'Needs help' : 'Needs attention'), ' \u00b7 ' + p.problem));
    var msg = h('div', { style: { fontSize: px(LA.size(ctx, 'sub')), color: 'rgba(255,255,255,.82)', marginTop: '2px', lineHeight: 1.25, display: ax ? 'block' : '-webkit-box', WebkitLineClamp: 2, WebkitBoxOrient: 'vertical', overflow: 'hidden' } }, p.message);
    var top = h('div.la-row', { style: { gap: '14px' } }, LA.sev(glyphForProblem(p), p.severity, 44), h('div', { style: { minWidth: 0, flex: 1 } }, first, msg));
    var btns = LA.buttons(c, c.buttons, { ctx: ctx, fills: true, chips: p.chips });
    var card = h('div.la-card.problem', { role: 'group', 'aria-label': c.spokenSummary, style: { backgroundColor: sev.ground, backgroundImage: 'linear-gradient(180deg,' + sev.g0 + ',' + sev.g1 + ')', boxShadow: 'inset 0 0 0 1px ' + sev.hair, width: o.width ? px(o.width) : '' } },
      h('div.la-in', { style: { gap: '4px' } }, top, btns),
      marks ? h('span', { style: { position: 'absolute', top: '12px', right: '14px' } }, LA.mark(40, o.choice)) : null);
    return tag(card, fx, function (f) { return LA.problemCard(f, o); });
  };
  function glyphForProblem(p) { return KNOWN_GLYPHS.indexOf(p.icon) >= 0 ? p.icon : 'generic'; }
  /** The card the Lock Screen, banner and StandBy draw for an activity (HomeActivityLockScreenView.swift). o.fullscreen drops the corner mark (StandBy). */
  LA.lockCard = function (fx, o) {
    o = Object.assign({}, o); if (o.fullscreen) o.mark = false;
    return LA.card(fx).problem ? LA.problemCard(fx, o) : LA.jobCard(fx, o);
  };

  /* ------------------------------------------------------------------ Dynamic Island */
  function tplWidth(tpl, ctx) {
    var digits = (tpl.match(/\d/g) || []).length, colons = (tpl.match(/:/g) || []).length, k = LA.size(ctx, 'sub', true) / 15;
    return (digits * 9.2 + colons * 4.6) * k;
  }
  function compactLeading(c) {
    if (c.problem) return LA.sev(glyphForProblem(c.problem), c.problem.severity, 24);
    if (c.showsRing) return LA.ring(c, 24);
    return LA.headerGlyph(c, 20);
  }
  function compactTrailing(c, ctx, limited) {
    if (limited) return null;
    var t = c.compactTrailing, acc = LA.accent(c.a.tint), sub = LA.size(ctx, 'sub', true), foot = LA.size(ctx, 'foot', true);
    if (t.k === 'timer') {
      return h('span.la-ct', { style: { fontSize: px(sub), color: acc }, 'aria-label': c.spokenFigure || '' }, h('span.tpl', t.tpl), h('span.live', c.figureText));
    }
    if (t.k === 'label') return h('span', { style: { fontSize: px(foot), fontWeight: 600, color: acc, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', maxWidth: '56px', textAlign: 'right', display: 'inline-block' } }, t.text);
    if (t.k === 'problem') {
      var el = h('span', { style: { fontSize: px(sub), fontWeight: 600, color: LA.SEV[c.problem.severity].light, whiteSpace: 'nowrap', display: 'inline-block' } }, t.word); return el;
    }
    if (t.k === 'complete') return h('span.la-g', { role: 'img', 'aria-label': 'Complete', style: { width: px(sub), height: px(sub), color: acc }, html: Mock.icon('checkmark.circle', { fill: true }) });
    return null;
  }
  function trailingWidth(c, ctx, limited) {
    if (limited) return 0;
    var t = c.compactTrailing;
    if (t.k === 'timer') return tplWidth(t.tpl, ctx);
    if (t.k === 'label') return Math.min(56, t.text.length * LA.size(ctx, 'foot', true) * .54);
    if (t.k === 'problem') return Math.max(40, t.word.length * LA.size(ctx, 'sub', true) * .52 * .85);
    if (t.k === 'complete') return 18;
    return 0;
  }
  /** The compact island: leading ring, camera gap, trailing time with a rigid width (HomeActivityIslandViews.CompactLeading / CompactTrailing). o: limited (iOS 27), ctx, minWidth (250, the app's stand-in). */
  LA.islandCompact = function (fx, o) {
    o = o || {}; var ctx = o.ctx || Mock.current, c = LA.card(fx), limited = !!o.limited, cam = 126;
    var side = 10 + Math.max(24, trailingWidth(c, ctx, limited)) + 6;
    var width = limited ? cam + 2 * (10 + 24 + 6) : Math.max(o.minWidth == null ? 250 : o.minWidth, cam + 2 * side);
    var node = h('div.la-island-c', { role: 'group', 'aria-label': (c.problem ? c.spokenSummary : c.title) + (limited ? ', compact, limited width' : ', compact'), style: { width: px(width) } },
      h('span', { 'aria-label': c.problem ? c.spokenSummary : c.title, role: 'img' }, compactLeading(c)), h('span.gap'), compactTrailing(c, ctx, limited));
    return tag(node, fx, function (f) { return LA.islandCompact(f, o); });
  };
  /** The minimal island: the ring alone in a 44 pt stand-in circle (the system draws about 36 pt). */
  LA.islandMinimal = function (fx, o) {
    o = o || {}; var c = LA.card(fx);
    var node = h('div.la-island-m', { role: 'img', 'aria-label': c.problem ? c.spokenSummary : c.title, style: { width: '44px', height: '44px' } }, compactLeading(c));
    return tag(node, fx, function (f) { return LA.islandMinimal(f, o); });
  };
  /** The expanded island (E2c): glyph and corner mark beside the camera, title over value with up to two buttons below, a bar when there is progress.
   *  o: screen (402), camera (126), ctx (the island text is capped at xxxLarge). */
  LA.islandExpanded = function (fx, o) {
    o = o || {}; var ctx = o.ctx || Mock.current, c = LA.card(fx), screen = o.screen || 402, cam = o.camera || 126, cap = true;
    var region = ((screen - 22) - 36 - cam) / 2;
    var lead = c.problem ? LA.sev(glyphForProblem(c.problem), c.problem.severity, 28) : LA.headerGlyph(c, 24);
    var top = h('div.top', h('div.reg', { style: { width: px(region), justifyContent: 'flex-start' } }, lead), h('div.la-cam', { style: { width: px(cam) }, 'aria-hidden': 'true', title: 'Camera ' + cam + ' pt' }),
      h('div.reg', { style: { width: px(region), justifyContent: 'flex-end' } }, LA.mark(24, o.choice)));
    var bottom;
    if (c.problem) {
      var p = c.problem, btns = LA.buttons(c, c.islandButtons, { ctx: ctx, cap: cap, fills: true });
      bottom = h('div', { style: { display: 'flex', gap: '8px', alignItems: 'center' } },
        h('div', { style: { flex: 1, minWidth: 0 } },
          h('div.la-clamp', { style: { fontSize: px(LA.size(ctx, 'hd', cap)), fontWeight: 600, WebkitLineClamp: 1 } }, c.a.title),
          h('div.la-clamp', { style: { fontSize: px(LA.size(ctx, 'foot', cap)), color: LA.SEV[p.severity].light, WebkitLineClamp: 1 } }, p.problem)), btns);
    } else {
      var title = h('div.la-clamp', { style: { fontSize: '16px', fontWeight: 600, WebkitLineClamp: 2, lineHeight: 1.18 } }, c.headerLine);
      bottom = h('div', { style: { display: 'flex', flexDirection: 'column', gap: '8px' } },
        h('div', { style: { display: 'flex', gap: '8px', alignItems: 'center' } },
          h('div', { style: { flex: 1, minWidth: 0 } }, title, valueLine(c, ctx, 32, 'lt', cap)), LA.buttons(c, c.islandButtons, { ctx: ctx, cap: cap, fills: false })),
        c.bar ? LA.bar(c) : null);
    }
    var node = h('div.la-island-x', { role: 'group', 'aria-label': c.spokenSummary, style: { width: px(screen - 22), borderRadius: '42px', padding: '10px 18px 14px', display: 'flex', flexDirection: 'column', gap: '8px' } }, top, bottom);
    return tag(node, fx, function (f) { return LA.islandExpanded(f, o); });
  };

  /* ------------------------------------------------------------------ small family (Watch Smart Stack, CarPlay) */
  LA.small = function (fx, o) {
    o = o || {}; var ctx = o.ctx || Mock.current, c = LA.card(fx), lead;
    if (c.problem) lead = LA.sev(glyphForProblem(c.problem), c.problem.severity, 30);
    else if (c.showsRing) lead = LA.ring(c, 32);
    else lead = LA.headerGlyph(c, 26);
    var capSz = LA.size(ctx, 'c1'), sec;
    if (c.problem) sec = h('div.ln', { style: { fontSize: px(capSz), color: LA.SEV[c.problem.severity].light } }, c.problem.problem);
    else if (c.bigLine) sec = h('div.ln', { style: { fontSize: px(LA.size(ctx, 'hd')), fontWeight: 600 } }, c.bigLine);
    else sec = h('div.ln', { style: { fontSize: px(LA.scaled(ctx, 17, 'hd')), fontWeight: 600, fontVariantNumeric: 'tabular-nums', color: c.complete ? LA.accent(c.a.tint) : '#fff' } }, c.figureText);
    var node = h('div.la-small', { role: 'group', 'aria-label': c.spokenSummary }, lead,
      h('div.tx', h('div.ln', { style: { fontSize: px(capSz), fontWeight: 600 } }, c.problem ? c.a.title : c.title), sec));
    return tag(node, fx, function (f) { return LA.small(f, o); });
  };

  /* ------------------------------------------------------------------ stages and figures */
  /** A dark stand-in stage (the kit wallpaper) holding figures. */
  LA.stage = function (kids, o) {
    o = o || {};
    return h('div.la-stage', { style: o.style || null }, h('div.ui-wall'), h('div.la-in-stage', kids));
  };
  /** A captioned figure. */
  LA.fig = function (node, caption, note) {
    return h('figure.la-fig', { style: { margin: 0 } }, node, caption ? h('figcaption.cap', caption + (note ? ' · ' + note : '')) : null);
  };
  LA.grid = function (kids) { return h('div.la-grid', kids); };
  LA.note = function (text) { return h('p.la-note', text); };
  /** A lock screen inside a device (Mock.frame): wallpaper, clock, a stack of Live Activity cards, flashlight and camera. Pass cards as nodes. */
  LA.lockScreen = function (ctx, cards, o) {
    o = o || {};
    var wall = h('div.ui-wall');
    var root = h('div.la-lock', wall,
      h('div.date', { 'aria-hidden': 'true' }, ctx.w > 500 ? 'Friday, October 23' : 'Fri Oct 23'), h('div.time', { 'aria-hidden': 'true' }, '9:41'),
      h('div.stack', cards),
      h('div.fl.ui-glass', { style: { left: '46px' }, 'aria-hidden': 'true', html: Mock.icon('bolt.fill', { fill: true }) }),
      h('div.fl.ui-glass', { style: { right: '46px' }, 'aria-hidden': 'true', html: Mock.icon('camera.fill', { fill: true }) }));
    return Mock.frame(ctx, root);
  };
  /** A home screen (wallpaper only) inside a device, with an optional overlay element (a banner or an island). */
  LA.homeScreen = function (ctx, overlays, o) {
    o = o || {};
    var root = h('div.la-lock', h('div.ui-wall'),
      h('div', { style: { position: 'absolute', left: '24px', right: '24px', top: '120px', display: 'grid', gridTemplateColumns: 'repeat(4,1fr)', gap: '26px 18px', opacity: .55 }, 'aria-hidden': 'true' },
        Array.apply(null, Array(12)).map(function () { return h('i', { style: { aspectRatio: '1', borderRadius: '22%', background: 'rgba(255,255,255,.22)' } }); })),
      overlays);
    return Mock.frame(ctx, root);
  };
  /** A banner at the top of a screen (Live Activity banner or notification). */
  LA.bannerAt = function (ctx, node, top) { return h('div.la-banner', { style: { top: px(top == null ? 62 : top) } }, node); };
  /** The island positioned over a device screen, centred on the camera. */
  LA.islandAt = function (node, o) { return h('div', { style: { position: 'absolute', left: 0, right: 0, top: '11px', display: 'flex', justifyContent: 'center', zIndex: 62, pointerEvents: 'none' } }, h('div', { style: { pointerEvents: 'auto' } }, node)); };


  /** StandBy: landscape, black, the card scaled by the system with the corner mark dropped (isActivityFullscreen). The scale here is illustrative. */
  LA.standby = function (ctx, fx, o) {
    o = o || {};
    return h('div', { role: 'group', 'aria-label': 'StandBy, landscape', style: { width: '640px', height: '300px', borderRadius: '34px', background: '#000', boxShadow: '0 0 0 2px #3a3a3e inset, 0 0 0 8px #000, 0 14px 30px rgba(0,0,0,.35)', display: 'grid', placeItems: 'center', overflow: 'hidden', position: 'relative', flex: 'none', margin: '8px' } },
      h('div', { style: { transform: 'scale(' + (o.scale || 1.5) + ')', transformOrigin: 'center' } }, LA.lockCard(fx, { ctx: ctx, fullscreen: true })));
  };
  /** Replace the first LA node under root with the node for another fixture (a content update). */
  LA.swapFirst = function (root, fx) {
    var n = root.querySelector('[data-la]'); if (!n || !n.__la) return null;
    var next = n.__la.build(fx); n.parentNode.replaceChild(next, n); return next;
  };

  /* ------------------------------------------------------------------ notification surfaces (system UI: the app supplies the content) */
  /** A notification banner or Notification Center entry. o: title, subtitle, body, time ('now'), thumb (CSS background), ctx. */
  LA.notif = function (o) {
    var ctx = o.ctx || Mock.current, sub = LA.size(ctx, 'sub'), foot = LA.size(ctx, 'foot');
    var node = h('div.la-notif', { role: 'group', 'aria-label': [o.title, o.subtitle, o.body].filter(Boolean).join(', '), style: { fontSize: px(sub) } },
      h('div.hd', LA.appIcon(38), h('div.tx', h('div.t', o.title), o.subtitle ? h('div.s', o.subtitle) : null, h('div.b', o.body)),
        h('div', { style: { display: 'flex', flexDirection: 'column', alignItems: 'flex-end', gap: '6px' } }, h('span.tm', { style: { fontSize: px(foot) } }, o.time || 'now'),
          o.thumb ? h('div.th', { 'aria-hidden': 'true', style: { background: o.thumb } }) : null)));
    return node;
  };
  /** The notification's action list, as shown after a long press: each {title, icon, destructive, input, placeholder}. */
  LA.notifActions = function (list, o) {
    var ctx = (o && o.ctx) || Mock.current, sub = LA.size(ctx, 'sub');
    return h('div.la-actions', { role: 'group', 'aria-label': 'Notification actions', style: { fontSize: px(sub) } }, list.map(function (a) {
      if (a.input) return h('div.ac', h('div.in', a.placeholder), h('span', { style: { color: '#409cff', fontWeight: 600 } }, a.send || 'Send'));
      return h('button.ac' + (a.destructive ? '.destr' : ''), { type: 'button', style: { background: 'none', border: 0, borderTop: '.5px solid rgba(255,255,255,.14)', width: '100%', color: a.destructive ? '#ff6961' : 'inherit', font: 'inherit', textAlign: 'left', cursor: 'pointer' } },
        a.icon ? h('span', { html: Mock.icon(a.icon), 'aria-hidden': 'true' }) : null, h('span', { style: { flex: 1 } }, a.title), a.lock ? h('span', { 'aria-label': 'requires unlock', style: { opacity: .6 }, html: Mock.icon('lock') }) : null);
    }));
  };
  /** The camera notification content view (NotificationViewController): black 16:9, the snapshot, a spinner or a red Live badge. state: loading | snapshot | live | failed. */
  LA.cameraView = function (o) {
    o = o || {}; var st = o.state || 'snapshot', title = o.title || 'Doorbell';
    var showSnap = st !== 'loading';
    var node = h('div.la-cam16', { role: 'img', 'aria-label': title + (st === 'live' ? ', live camera' : ', camera snapshot') },
      showSnap ? h('div.snap', { style: { background: Mock.scene(o.scene || 'front-door') } }) : null,
      st === 'live' ? h('span.badge', { html: '<svg viewBox="0 0 8 8" aria-hidden="true"><circle cx="4" cy="4" r="4" fill="#fff"/></svg>Live' }) : (st === 'failed' ? null : h('span.spin', { 'aria-hidden': 'true' })));
    return node;
  };

  /** The Apple Watch stand-in device (Series 10, 46 mm: 208 x 248 pt). */
  Mock.devices.watch = Mock.devices.watch || { key: 'watch', label: 'Apple Watch 46 mm (208 × 248)', short: 'Watch', w: 208, h: 248, r: 44, bezel: 8, family: 'watch', regular: false,
    safeTop: 0, safeBottom: 0, barTop: 0, rail: 0, menu: false, tabs: 'none', titleInHeader: false, sheetTop: 0, hinge: null };
  LA.watch = function (content, o) {
    o = o || {};
    return h('div.la-watch', { style: { width: '208px', height: '248px', borderRadius: '52px', padding: '0' } }, h('div.scr', { style: { borderRadius: '44px', inset: '8px' } }, content));
  };
  /** Draw a figure of one card in each of the given sets, as a captioned row. */
  LA.names = {
    jobs: ['fan', 'fan-long', 'fan-xlong', 'dishwasher', 'dishwasher-long', 'dishwasher-percent', 'dishwasher-paused', 'dishwasher-waiting'],
    laundry: ['dryer', 'dryer-estimated', 'washer', 'dishwasher-complete', 'dryer-complete', 'washer-complete'],
    vacuums: ['vacuum', 'vacuum-mopping', 'vacuum-cleaning', 'vacuum-drawn', 'vacuum-paused', 'vacuum-long'],
    hotflash: ['hotflash-cooling', 'hotflash-holding', 'hotflash-bysam', 'hotflash-alex-bysam', 'hotflash-wholebed', 'hotflash-byhome', 'hotflash-complete'],
    states: ['fan-pending', 'fan-pending-stale', 'fan-notice', 'problem-completing'],
    stack: ['fan', 'dishwasher-percent', 'washer', 'dryer'],
  };
  /** Shared motion item: the system's live timers count and the bar fills with no pushes (JobCardView / ActivityFigure: Text(timerInterval:)). */
  LA.motionTick = function (source) {
    return { id: 'timers-count', what: 'Timers count and the bar fills by themselves', token: 'system live Text and ProgressView(timerInterval:), no pushes, no app animation',
      source: source, reduce: 'Not an animation, so Reduce Motion does not change it: the digits keep updating once a second.',
      note: 'The mockup steps the clocks once a second for 6 s. The system fills the bar continuously; the app adds no animation or transition of its own.',
      play: function (stage) { var n = 0; return new Promise(function (res) { var t = setInterval(function () { LA.tick(stage, 1); if (++n >= 6) { clearInterval(t); res(); } }, 1000); }); } };
  };
})();
