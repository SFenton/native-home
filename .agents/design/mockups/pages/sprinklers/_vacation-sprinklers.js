/* Local helper for the sprinklers mockups (batch vacation-sprinklers): fixtures, SprinklerFormat, the controller card, the Sprinklers page,
 * the controller sheet and its two pushed pages, built from kit components. Loaded with a relative <script src> by every sprinklers item.
 * Promote to kit: the extra symbols below (battery.100percent, battery.25percent, calendar.badge.clock, clock.arrow.circlepath,
 * antenna.radiowaves.left.and.right, stop.circle, cloud.heavyrain, wand.and.stars, calendar.badge.checkmark, minus.circle.fill) belong in
 * _kit/lib/symbols.js; the day picker, stepper row and pinned bar belong with the kit's form rows.
 *
 * Source of truth: apple/Sources/HassUI/Features/Sprinklers/{SprinklersScreen,SprinklerControllerSheet}.swift, HassCore/Sprinklers/SprinklerFormat.swift,
 * HassCore/Config/SprinklersConfig.swift. Fixtures follow the gallery: the front yard ready, the backyard low on battery with House watering.
 */
(function () {
  var h = Mock.h, I = Mock.icon, K = Mock.components;
  var VS = Mock.VS = Mock.VS || {};
  var S = VS.S = {};

  /* ---------------------------------------------------------------- extra symbols (stand-ins) */
  function c(x, y, r) { return '<circle cx="' + x + '" cy="' + y + '" r="' + r + '"/>'; }
  function p(d) { return '<path d="' + d + '"/>'; }
  function rc(x, y, w, hh, r) { return '<rect x="' + x + '" y="' + y + '" width="' + w + '" height="' + hh + '" rx="' + (r || 0) + '"/>'; }
  var cloud = 'M7.5 14.5h9.2a4 4 0 0 0 .6-7.95A5.6 5.6 0 0 0 6.5 8 3.3 3.3 0 0 0 7.5 14.5z';
  function batt(w) { return [rc(2.5, 7.5, 17, 9, 2.5) + p('M21.5 10.5v3') + '<rect x="4.5" y="9.5" width="' + w + '" height="5" rx="1" fill="currentColor" stroke="none"/>']; }
  var extra = {
    'battery.100percent': batt(13), 'battery.25percent': batt(3.5),
    'calendar.badge.clock': [rc(3.5, 5, 15, 14.5, 3) + p('M3.5 10h15M8 3v4M14 3v4') + c(17.5, 17.5, 4.2) + p('M17.5 15.4v2.3l1.4.9')],
    'calendar.badge.checkmark': [rc(3.5, 5, 17, 15.5, 3) + p('M3.5 10h17M8 3v4M16 3v4M9 15l2.2 2.2L15.4 13')],
    'clock.arrow.circlepath': [p('M20 12a8 8 0 1 1-2.5-5.8M20 4v4.5h-4.5M12 8v4.2l2.6 1.6')],
    'antenna.radiowaves.left.and.right': [p('M12 12.5V20') + c(12, 10.5, 1.6) + p('M8.2 6.8a5.4 5.4 0 0 0 0 7.4M15.8 6.8a5.4 5.4 0 0 1 0 7.4M5.4 4.2a9.4 9.4 0 0 0 0 12.6M18.6 4.2a9.4 9.4 0 0 1 0 12.6')],
    'stop.circle': [c(12, 12, 8.8) + rc(9, 9, 6, 6, 1.2), c(12, 12, 8.8) + rc(9, 9, 6, 6, 1.2)],
    'cloud.heavyrain': [p(cloud) + p('M7.5 17.5l-1 2.5M12 17.5l-1 2.5M16.5 17.5l-1 2.5')],
    'wand.and.stars': [p('M4 20 14 10M12.5 8.5l3 3') + p('M18 3v4M16 5h4M20 11v2.4M18.8 12.2h2.4M8 3.5v2.4M6.8 4.7h2.4')],
    'minus.circle.fill': [c(12, 12, 8.8) + p('M8 12h8'), '<path fill-rule="evenodd" d="M12 2.8a9.2 9.2 0 1 0 0 18.4 9.2 9.2 0 0 0 0-18.4zM7.6 11h8.8v2H7.6z"/>'],
  };
  Object.keys(extra).forEach(function (k) { if (!Mock.symbols[k]) Mock.symbols[k] = extra[k]; });

  /** DynamicGridLayout with a scaled minimum: the track is never wider than the container (the kit's CSS grid would overflow at AX5). min in pt, avail = container width in pt. */
  VS.fit = function (min, avail) { var sc = (Mock.current && Mock.current.scale) || 1; return Math.max(60, Math.min(min, Math.floor(avail / sc))); };
  /** The page body width (window minus the rail minus two 16 pt margins). */
  VS.pageW = function () { var c = Mock.current; return c ? c.contentW - 32 : 370; };
  /** The sheet content width (a page sheet is 704 pt on iPad, else the window; minus the 16 pt padding). */
  VS.sheetW = function () { var c = Mock.current; if (!c) return 370; return (c.compact ? c.w : Math.min(704, c.w - 64)) - 32; };

  /* ---------------------------------------------------------------- local styles (kit tokens only) */
  var css = [
    '.vs-water { color: var(--fam-water-glyph); } .g-light .vs-water { color: var(--fam-water-glyph-light); }',
    '.vs-list { display: flex; flex-direction: column; gap: 22px; min-height: 100%; }',
    '.vs-list > section > .ui-formhead { margin-top: 0; }',
    '.vs-row { display: flex; align-items: baseline; gap: 12px; flex: 1; min-width: 0; }',
    '.vs-row .vs-ico { width: calc(24px * var(--sc)); flex: none; display: grid; place-items: center; font-size: var(--fs-body); color: var(--ink-sheet-2); transform: translateY(2px); }',
    '.vs-row.on .vs-ico, .vs-row.on .vs-ln { color: var(--fam-water-glyph); } .g-light .vs-row.on .vs-ico, .g-light .vs-row.on .vs-ln { color: var(--fam-water-glyph-light); }',
    '.vs-row .vs-tx { display: flex; flex-direction: column; gap: 2px; min-width: 0; }',
    '.vs-row .vs-ti { color: var(--ink); font-size: var(--fs-body); }',
    '.vs-row .vs-ln { color: var(--ink-sheet-2); font-size: var(--fs-sub); transition: color var(--t-state) var(--ease-state); }',
    '.vs-field { display: flex; align-items: center; gap: 12px; padding: 4px 16px; min-height: 52px; background: var(--sheet-cell); font-size: var(--fs-body); color: var(--ink); width: 100%; border: 0; text-align: left; font-family: inherit; }',
    '.vs-form > * + * { border-top: .5px solid var(--sep); }',
    '.vs-form { border-radius: var(--radius-chip); overflow: hidden; display: flex; flex-direction: column; background: var(--sheet-cell); }',
    'button.vs-field { cursor: pointer; } .vs-field[disabled], .vs-field.dim { opacity: .4; cursor: default; }',
    '.vs-field .vs-ico2 { width: calc(24px * var(--sc)); flex: none; display: grid; place-items: center; color: var(--ink-sheet-2); }',
    '.vs-field .vs-lab { flex: 1; min-width: 0; }',
    '.vs-field .vs-val { font-variant-numeric: tabular-nums; }',
    '.vs-field.danger { color: var(--ink-danger); } .vs-field.muted { color: var(--ink-sheet-2); }',
    '.vs-chev { color: var(--ink-sheet-2); opacity: .7; font-size: var(--fs-foot); flex: none; }',
    '.vs-step { display: inline-flex; gap: 0; border-radius: 9px; background: var(--fill-tertiary); overflow: hidden; flex: none; }',
    '.vs-step button { width: 47px; min-height: 32px; border: 0; background: none; color: var(--ink); cursor: pointer; display: grid; place-items: center; } .vs-step button + button { border-left: .5px solid var(--sep); }',
    '.vs-step[aria-disabled="true"] { opacity: .4; }',
    '.vs-days { display: flex; gap: 4px; padding: 4px 8px; background: var(--sheet-cell); } .vs-days.grid { display: grid; grid-template-columns: repeat(4, 1fr); gap: 8px 4px; }',
    '.vs-day { flex: 1; min-width: 44px; min-height: 44px; border: 0; border-radius: 50%; background: rgba(128,128,128,.15); color: var(--ink); font: 600 var(--fs-sub)/1 var(--font); cursor: pointer; transition: background-color var(--t-state) var(--ease-state), color var(--t-state) var(--ease-state); }',
    '.vs-day.sel { background: var(--fam-water-glyph); color: var(--sheet-ground); } .g-light .vs-day.sel { background: var(--fam-water-glyph-light); }',
    '.vs-days[aria-disabled="true"] { opacity: .4; }',
    '.vs-time { display: inline-flex; padding: 6px 12px; border-radius: 8px; background: var(--fill-tertiary); font-size: var(--fs-body); font-variant-numeric: tabular-nums; }',
    '.vs-rm { width: 44px; height: 44px; display: grid; place-items: center; border: 0; background: none; color: var(--ink-danger); font-size: var(--fs-t3); cursor: pointer; flex: none; } .vs-rm[disabled] { opacity: .4; }',
    '.vs-bar { margin: auto -16px -24px; padding: 16px; position: sticky; bottom: 0; z-index: 3; background: color-mix(in srgb, var(--sheet-ground) 88%, transparent); backdrop-filter: blur(20px); }',
    '.vs-bar .ui-primary { width: 100%; }',
    '.vs-foot { font-size: var(--fs-foot); color: var(--ink-sheet-2); margin: 8px 16px 0; }',
    '.vs-hair { position: relative; } .vs-hair::before { content: ""; position: absolute; top: 0; right: 0; left: var(--sep-inset, 56px); height: .5px; background: var(--sep, rgba(255,255,255,.14)); z-index: 1; }',
    '.vs-cardwrap { display: flex; flex-direction: column; gap: 12px; min-width: 0; }',
    '.vs-pills .ui-pill { background: transparent; }',
    '.ts-ax5 .vs-field { flex-wrap: wrap; }',
  ].join('\n');
  if (!document.getElementById('vs-sprinklers-css')) { var st = document.createElement('style'); st.id = 'vs-sprinklers-css'; st.textContent = css; document.head.appendChild(st); }

  /* ---------------------------------------------------------------- fixtures */
  var ALL_DAYS = [0, 1, 2, 3, 4, 5, 6];
  function program(o) { return Object.assign({ available: true, enabled: true, days: ALL_DAYS, times: ['7:00 AM'], run: 15, budget: 100 }, o); }
  function zone(name, o) { o = o || {}; return Object.assign({ name: name, available: true, last: '6:00 AM', program: program(o.program) }, o, { program: program(o.program) }); }
  var BASE = {
    frontYard: { id: 'frontYard', title: 'Front Yard', available: true, fault: false, mode: 'auto', battery: 82, hub: true, nextUnknown: false, next: '7:00 AM', lastRun: { time: '6:00 AM', run: 15 }, rain: false, smart: true, active: null,
      zones: [zone('Front Yard', { program: { days: ALL_DAYS, times: ['7:00 AM'], run: 15, budget: 100 } })] },
    backyard: { id: 'backyard', title: 'Garden Faucet', available: true, fault: false, mode: 'auto', battery: 15, hub: true, nextUnknown: false, next: '6:30 AM', lastRun: { time: '6:30 AM', run: 10 }, rain: false, smart: true, active: 1,
      zones: [zone('Bushes', { last: '6:30 AM', program: { days: [1, 3, 5], times: ['6:30 AM'], run: 10, budget: 80 } }), zone('House', { last: '6:40 AM', program: { days: [2, 4, 6], times: ['6:30 AM', '7:30 PM'], run: 5, budget: 100 } }),
        zone('Backyard', { last: 'No history', program: { enabled: false, days: ALL_DAYS, times: ['8:00 PM'], run: 20, budget: 120 } }), zone('Sidewalk', { last: '6:50 AM', program: { days: [1, 4], times: ['6:50 AM'], run: 8, budget: 100 } })] },
  };
  /** A controller snapshot: S.snap('frontYard', {mode:'off'}). Derived: status, batteryLow, watering. A patch with available:false takes everything offline. */
  S.snap = function (id, patch) {
    var s = JSON.parse(JSON.stringify(BASE[id])); patch = patch || {};
    Object.keys(patch).forEach(function (k) { s[k] = patch[k]; });
    if (patch.zones) s.zones = patch.zones;
    if (!s.available) { s.active = null; s.rain = false; s.smart = false; s.fault = false; s.next = null; s.zones.forEach(function (z) { z.available = false; z.program.available = false; }); }
    s.status = !s.available ? 'unavailable' : s.fault ? 'fault' : s.active != null ? 'watering' : 'ready';
    s.batteryLow = s.battery != null && s.battery <= 20;
    return s;
  };
  /** The default Sprinklers page pair. */
  S.pair = function (a, b) { return [S.snap('frontYard', a), S.snap('backyard', b)]; };

  /* ---------------------------------------------------------------- SprinklerFormat (HassCore/Sprinklers/SprinklerFormat.swift) */
  var DAYS = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
  function list(a) { return a.length <= 1 ? (a[0] || '') : a.length === 2 ? a[0] + ' and ' + a[1] : a.slice(0, -1).join(', ') + ', and ' + a[a.length - 1]; }
  var F = S.fmt = {
    dayLetters: ['S', 'M', 'T', 'W', 'T', 'F', 'S'], dayNames: DAYS,
    status: function (s) { return { unavailable: 'Unavailable', watering: 'Watering', fault: 'Fault' }[s.status] || s.mode.charAt(0).toUpperCase() + s.mode.slice(1); },
    nextStart: function (s) { return s.nextUnknown ? 'Unknown' : s.next ? s.next : (s.available ? 'Not scheduled' : 'Unavailable'); },
    lastStart: function (t) { return t || 'No history'; },
    subtitle: function (s) { return s.available ? F.status(s) + ' · Next ' + F.nextStart(s) : 'Unavailable'; },
    battery: function (s) { return s.battery == null ? 'Unavailable' : s.battery + '%'; },
    days: function (d) { return d.length === 7 ? 'Every day' : list(d.map(function (i) { return DAYS[i]; })); },
    summary: function (pr) { var d = F.days(pr.days), t = list(pr.times); return (d || 'Unavailable') + ' · ' + (t || 'Unavailable'); },
    details: function (pr, zone) { return zone + ' · ' + (pr.run || 0) + ' min · ' + pr.budget + '%'; },
    programName: function (zone) { return zone + ' schedule'; },
  };

  /* ---------------------------------------------------------------- the card (SprinklerControllerCard) */
  function pill(label, value, symbol, tone, detail) { return K.StatusPill({ label: label, value: value, symbol: symbol, tone: tone || 'neutral', detail: detail }); }
  /** One controller's card (rollout M, 2026-10-28): a low battery alert, then the controller as a NAVIGATION tile (glyph, name and status, a Stop Watering disc, chevron; opens the sheet),
   *  then one module holding the four status pills. Water family, filled while watering; the disc dims in place while idle so the tile never changes shape. */
  S.card = function (s, o) {
    o = o || {};
    var watering = s.status === 'watering', un = s.status === 'unavailable';
    var row = K.GlassTile({ title: s.title, subtitle: F.subtitle(s), symbol: 'sprinkler.and.droplets', family: 'water', isActive: watering, isUnavailable: un, behavior: 'navigate',
      actions: [{ id: 'stop', symbol: 'stop.fill', label: 'Stop Watering', dim: !watering }] });
    row.setAttribute('aria-label', s.title + ', ' + F.subtitle(s) + '. Opens the controller.');
    var pw = VS.pageW(), cardW = (pw < 700 || ((Mock.current && Mock.current.scale) || 1) > 1.5) ? pw : (pw - 24) / 2;
    var pills = h('div.vs-pills.vs-hair', K.TileGrid({ min: VS.fit(150, cardW), max: 2, gap: 0, equal: false, items: [
      pill('Battery', F.battery(s), 'battery.100percent', s.batteryLow ? 'warning' : 'neutral'),
      pill('Next Watering', F.nextStart(s), 'calendar.badge.clock'),
      pill('Last Watering', F.lastStart(s.lastRun.time), 'clock.arrow.circlepath'),
      pill('Hub', s.hub ? 'Connected' : 'Unavailable', 'antenna.radiowaves.left.and.right', s.hub ? 'ok' : 'unavailable')] }));
    var kids = [];
    if (s.batteryLow) kids.push(h('div.ui-inline-alert', { role: 'group', 'aria-label': 'Warning: ' + s.title + ' battery is low (' + s.battery + '%). Replace the batteries soon.' }, h('span', { html: I('battery.25percent', { fill: true }) }), h('span', s.title + ' battery is low (' + s.battery + '%). Replace the batteries soon.')));
    kids.push(row);
    kids.push(K.ModuleList({ density: s.batteryLow ? 'dense' : 'thin', rows: [pills] }));
    return h('div.vs-cardwrap', { role: 'group', 'aria-label': s.title, style: { gap: '8px' } }, kids);
  };

  /* ---------------------------------------------------------------- the page */
  S.pageBody = function (ctx, snaps) {
    var ctx0 = Mock.current;
    /* Partly folded Duo (section-sides.md, claude/section-sides): the one section divides at its blocks; each controller card is whole on one side,
       by configured order (Front Yard leads, Garden Faucet trails), at every text size (no 340 pt fall-back across the band). The header leads. */
    if (ctx0 && ctx0.splitAtHinge && ctx0.splitGeometry) {
      var lead = [K.PageSectionHeader({ title: 'Controllers' })], trail = [];
      snaps.forEach(function (s, i) { (i % 2 ? trail : lead).push(S.card(s)); });
      if (trail.length) trail.unshift(h('div', { style: { height: 'calc(var(--fs-t3) * 1.2)' }, 'aria-hidden': 'true' }));
      return Mock.foldColumns(ctx0, { leading: [h('div.ui-section', { style: { gap: '12px' } }, lead)], trailing: [h('div.ui-section', { style: { gap: '12px' } }, trail)] });
    }
    var grid = K.TileGrid({ min: VS.fit(340, VS.pageW()), max: 2, gap: 24, equal: false, items: snaps.map(function (s) { return S.card(s); }) });
    return [h('div.ui-section', { style: { gap: '12px' } }, K.PageSectionHeader({ title: 'Controllers' }), grid)];
  };
  /** The Sprinklers page pushed from a Quick Links tile (the sheet closes and the page pushes onto the tab's stack). */
  S.page = function (ctx, o) {
    o = o || {};
    return Mock.page(ctx, { title: 'Sprinklers', back: o.back || 'Home', section: o.section || 'home', badge: 3, choresBadge: 2, connection: o.connection || 'live', body: S.pageBody(ctx, o.snaps || S.pair()) });
  };

  /* ---------------------------------------------------------------- controller sheet pieces */
  function head(t) { return h('p.ui-formhead', { role: 'heading', 'aria-level': '2' }, t); }
  function form(rows) { return h('div.vs-form', rows); }
  function sec(header, rows, footer) { return h('section', header ? head(header) : null, form(rows), footer ? h('p.vs-foot', footer) : null); }
  S.head = head; S.form = form; S.sec = sec;
  /** An icon, a title and secondary lines joined with a middle dot (SprinklerRow). active = the water colour. */
  function srow(symbol, active, title, lines, chev) {
    return h('div.vs-row' + (active ? '.on' : ''), h('span.vs-ico', { html: I(symbol) }), h('span.vs-tx', h('span.vs-ti', title), h('span.vs-ln', lines.join(' · '))));
  }
  function inline(msg) { return h('div.ui-inline-alert.error', { role: 'group', 'aria-label': 'Error: ' + msg }, h('span', { html: I('exclamationmark.circle', { fill: true }) }), h('span', msg)); }
  S.inlineError = inline;
  function toggleRow(label, symbol, on, disabled) {
    var r = h('div.vs-field' + (disabled ? '.dim' : ''), h('span.vs-ico2', { html: I(symbol) }), h('span.vs-lab', label), K.Toggle({ on: on, label: label }));
    if (disabled) r.querySelector('button').disabled = true;
    return r;
  }
  function controllerTone(s) { return { unavailable: 'unavailable', fault: 'danger', watering: 'active' }[s.status] || (s.mode === 'off' ? 'warning' : 'ok'); }

  /** The overview List: Status, Zones, Controls, Settings, Schedule. o.error shows the inline alert. */
  S.overview = function (s, o) {
    o = o || {};
    var kids = [];
    if (o.error) kids.push(inline(o.error));
    kids.push(h('section', head('Status'), K.TileGrid({ min: VS.fit(150, VS.sheetW()), max: 4, gap: 8, equal: false, items: [
      pill('Controller', F.status(s), s.status === 'watering' ? 'sprinkler.and.droplets' : 'info.circle', controllerTone(s)),
      pill('Battery', F.battery(s), 'battery.100percent', s.batteryLow ? 'warning' : 'neutral'),
      pill('Next Watering', F.nextStart(s), 'calendar.badge.clock'),
      pill('Last Watering', F.lastStart(s.lastRun.time), 'clock.arrow.circlepath', 'neutral', s.lastRun.run ? s.lastRun.run + ' min' : undefined)] })));
    kids.push(sec('Zones', s.zones.map(function (z, i) {
      var active = s.active === i;
      var row = h('button.vs-field', { type: 'button', 'aria-label': z.name + ', ' + [!z.available ? 'Unavailable' : active ? 'Watering' : 'Closed', F.lastStart(z.last)].join(', ') + '. Water now' },
        srow('sprinkler.and.droplets', active, z.name, [!z.available ? 'Unavailable' : active ? 'Watering' : 'Closed', F.lastStart(z.last)]), h('span.vs-chev', { html: I('chevron.right', { weight: 2.4 }) }));
      if (!z.available) row.classList.add('dim');
      return row;
    })));
    var stop = h('button.vs-field.' + (s.active != null && s.available ? 'danger' : 'muted'), { type: 'button', 'aria-label': 'Stop Watering' }, h('span.vs-ico2', { html: I('stop.circle') }), h('span.vs-lab', 'Stop Watering'));
    if (!(s.active != null && s.available)) { stop.disabled = true; stop.classList.add('dim'); stop.style.opacity = '.6'; }
    kids.push(sec('Controls', [stop]));
    kids.push(sec('Settings', [toggleRow('Rain Delay · 24 Hours', 'cloud.heavyrain', s.rain, !s.available), toggleRow('Smart Watering', 'wand.and.stars', s.smart, !s.available)]));
    kids.push(sec('Schedule', s.zones.map(function (z, i) {
      var pr = z.program, name = F.programName(z.name);
      var link = h('button.vs-field', { type: 'button', style: { flex: 1, background: 'none', padding: 0, minHeight: '44px' }, 'aria-label': name + ', ' + F.summary(pr) + ', ' + F.details(pr, z.name), disabled: !pr.available },
        srow('calendar.badge.clock', pr.enabled, name, [F.summary(pr), F.details(pr, z.name)]));
      var r = h('div.vs-field' + (!pr.available ? '.dim' : ''), link, K.Toggle({ on: pr.enabled, label: name }));
      if (!pr.available) r.querySelector('.ui-toggle').disabled = true;
      return r;
    })));
    return h('div.vs-list', kids);
  };

  function stepperRow(label, symbol, value, disabled) {
    var r = h('div.vs-field' + (disabled ? '.dim' : ''), h('span.vs-ico2', { html: I(symbol) }), h('span.vs-lab', label), h('span.vs-val', value),
      h('span.vs-step', { role: 'group', 'aria-label': label + ' stepper', 'aria-disabled': String(!!disabled) }, h('button', { type: 'button', 'aria-label': 'Decrease', html: I('minus') }), h('button', { type: 'button', 'aria-label': 'Increase', html: I('plus') })));
    return r;
  }
  function bar(btn) { return h('div.vs-bar', btn); }

  /** Water now (pushed). */
  S.waterPage = function (s, zi, o) {
    o = o || {};
    var z = s.zones[zi], range = '1 to 60', canStart = s.available && s.mode !== 'off' && s.active == null, enabled = canStart && z.available && !o.sending;
    var footer = s.active != null ? 'Another zone is watering. Stop it to water this one.' : 'Waters ' + z.name + ' once, for ' + range + ' minutes. The schedule is not changed.';
    var kids = [];
    if (o.error) kids.push(inline(o.error));
    var mins = o.minutes || 15, off = !canStart || !z.available;
    // Presets beside the stepper (owner, 2026-10-24): 5, 10, 15, 30, 60 minutes, a menu at accessibility sizes.
    var presets = h('div.vs-field' + (off ? '.dim' : ''), { role: 'radiogroup', 'aria-label': 'Run time presets' }, [5, 10, 15, 30, 60].map(function (m) {
      return h('button.vs-day' + (m === mins ? '.sel' : ''), { type: 'button', role: 'radio', 'aria-checked': String(m === mins), 'aria-label': m + ' min', disabled: off }, m + '');
    }));
    kids.push(sec('Water Now', [stepperRow('Run Time', 'timer', mins + ' min', off), presets], footer));
    var btn = K.PrimaryButton({ title: 'Start Watering', symbol: 'sprinkler.and.droplets', family: 'water', disabled: !enabled });
    kids.push(bar(btn));
    return h('div.vs-list', kids);
  };

  /** Days, seven 44 pt circles Sunday first; two rows (4 + 3) when seven do not fit (the folded Duo). */
  function dayPicker(days, disabled, narrow) {
    var el = h('div.vs-days' + (narrow ? '.grid' : ''), { role: 'group', 'aria-label': 'Days', 'aria-disabled': String(!!disabled) });
    F.dayLetters.forEach(function (l, i) {
      var on = days.indexOf(i) >= 0;
      el.appendChild(h('button.vs-day' + (on ? '.sel' : ''), { type: 'button', 'aria-label': DAYS[i], 'aria-pressed': String(on), disabled: !!disabled }, l));
    });
    return el;
  }
  /** Edit a zone's program (pushed). o.times overrides the start times; o.days the chosen days; o.error an inline alert. */
  S.schedulePage = function (s, zi, o) {
    o = o || {};
    var z = s.zones[zi], pr = Object.assign({}, z.program, o.program), avail = pr.available, enabled = pr.enabled;
    var days = o.days || pr.days, times = o.times || pr.times, budget = o.budget == null ? pr.budget : o.budget;
    var canStart = s.available && s.mode !== 'off' && s.active == null;
    var kids = [];
    if (o.error) kids.push(inline(o.error));
    kids.push(sec('Right now', [toggleRow('Program Enabled', 'calendar.badge.checkmark', enabled, !avail),
      (function () { var b = h('button.vs-field' + (!(canStart && enabled) ? '.dim' : ''), { type: 'button', 'aria-label': 'Start Program Now', disabled: !(canStart && enabled) }, h('span.vs-ico2', { html: I('play.fill') }), h('span.vs-lab', 'Start Program Now')); return b; })()], 'These apply immediately, without Apply.'));
    var narrow = !!(Mock.current && (Mock.current.folded || Mock.current.axSize));   // ViewThatFits: seven 44 pt buttons do not fit the folded Duo sheet or AX text
    kids.push(h('section', head('Schedule'), h('div.vs-form', h('span.vs-lab', { style: { padding: '0 16px' } }, 'Days'), dayPicker(days, !avail, narrow)),
      h('p.vs-foot', 'Days, start times and the watering budget are saved with Apply.')));
    var timeRows = times.map(function (t, i) {
      var r = h('div.vs-field' + (!avail ? '.dim' : ''), h('span.vs-lab', 'Start ' + (i + 1)), h('span.vs-time', t),
        h('button.vs-rm', { type: 'button', 'aria-label': 'Remove Start Time ' + (i + 1), disabled: times.length <= 1 || !avail, html: I('minus.circle.fill') }));
      return r;
    });
    timeRows.push(h('button.vs-field' + (!avail ? '.dim' : ''), { type: 'button', 'aria-label': 'Add Another Start Time', disabled: !avail, style: { color: 'var(--ink)' } }, h('span.vs-ico2', { html: I('plus') }), h('span.vs-lab', 'Add Another Start Time')));
    kids.push(sec('Start Times', timeRows));
    kids.push(sec(null, [stepperRow('Watering Budget', 'percent', budget + '%', !avail)], 'Run Time · ' + (pr.run || 0) + ' min'));
    var applyOn = avail && days.length > 0 && times.length > 0 && !o.sending;
    kids.push(bar(K.PrimaryButton({ title: 'Apply', symbol: 'checkmark', family: 'water', disabled: !applyOn })));
    return h('div.vs-list', kids);
  };

  /* ---------------------------------------------------------------- the sheet */
  /** The controller sheet over the Sprinklers page. o: {snap, detail:{kind:'water'|'schedule', zone}, error, alert, connection, detent, minutes, days, times, budget, program}.
   *  hassSheet(.page, height: .full): large on iPhone and Duo folded, a 704 pt page sheet on iPad and unfolded Duo. */
  S.sheet = function (ctx, o) {
    o = o || {};
    var s = o.snap || S.snap('frontYard'), d = o.detail, title = s.title, subtitle = F.subtitle(s), content, leading = 'none';
    if (d && d.kind === 'water') { title = s.zones[d.zone].name; subtitle = null; leading = 'back'; content = S.waterPage(s, d.zone, o); }
    else if (d && d.kind === 'schedule') { var z = s.zones[d.zone]; title = F.programName(z.name); subtitle = F.summary(Object.assign({}, z.program, o.program)); leading = 'back'; content = S.schedulePage(s, d.zone, o); }
    else content = S.overview(s, o);
    var snaps = s.id === 'frontYard' ? [s, S.snap('backyard')] : [S.snap('frontYard'), s];
    return Mock.sheet(ctx, { title: title, subtitle: subtitle || undefined, detent: o.detent || 'large', size: 'page', leading: leading, trailing: 'close', content: content,
      presenter: o.noPresenter ? null : S.page(ctx, { snaps: snaps, connection: o.connection }), alert: o.alert || null });
  };
})();

/* The card as a registered component, so a component mockup can render its variants (Mock.componentConfig). Not added to Mock.COMPONENTS. */
(function () {
  var S = Mock.VS.S;
  var DOWN = { available: false, battery: null, hub: false, lastRun: { time: null, run: null } };
  function v(id, label, ctrl, patch) { return { id: id, label: label, props: { ctrl: ctrl, patch: patch } }; }
  Mock.register('SprinklerControllerCard', function (p) { return S.card(S.snap(p.ctrl || 'frontYard', p.patch)); }, {
    source: 'apple/Sources/HassUI/Features/Sprinklers/SprinklersScreen.swift', props: '{ctrl: "frontYard"|"backyard", patch: snapshot overrides}',
    variants: [v('idle', 'Idle (thin module)', 'frontYard', {}), v('watering', 'Watering (water glyph and status)', 'frontYard', { active: 0 }),
      v('battery-low', 'Battery low (alert above, dense module, orange pill icon)', 'backyard', { active: null, battery: 15 }),
      v('hub-unavailable', 'Hub unavailable (grey icon)', 'frontYard', { hub: false }), v('unavailable', 'Controller unavailable', 'backyard', DOWN),
      v('fault', 'Fault', 'frontYard', { fault: true })],
    states: [v('next-unknown', 'Next watering unknown', 'frontYard', { nextUnknown: true, next: null }), v('not-scheduled', 'Not scheduled', 'frontYard', { next: null }), v('no-history', 'No history', 'frontYard', { lastRun: { time: null, run: null } })] });
})();
