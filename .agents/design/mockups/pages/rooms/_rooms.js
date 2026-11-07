/* _rooms.js: helper shared by the rooms batch (room-page, room-kitchen, room-master-bedroom, room-card-sheet, quick-links and its pushes, the
 * quick-link / room-card / room-chip / room-section-header components). It is a LOCAL helper, not part of the kit: the kit's COMPONENTS list is untouched.
 *
 * Mirrors apple/Sources/HassCore/Rooms (RoomsConfig, RoomController, RoomFormat, RoomNavigation, RoomGroups, RoomOverview) and
 * apple/Sources/HassUI/Features/Rooms (RoomScreen, RoomTiles, RoomSupport, RoomSheets, QuickLinksSheet) as data plus builders, so every mockup of the
 * batch draws one implementation. Fixture values follow HassUI/Features/Gallery/RoomsGallery.swift (RoomsFixtures) and BedroomGallery.swift.
 *
 * Promote to kit: the symbols added below (Mock.symbols), Mock.rooms.tile (a room card as a GlassTile), Mock.rooms.section / sections (RoomSectionView and
 * the two-column section grid), the ContentUnavailableView stand-in (Mock.rooms.cu), the app launcher tile and the bathroom fan accessory rail.
 *
 * API (Mock.rooms = R): R.tile(spec) R.chip.* R.rail(ctx, title, chips) R.section(ctx, sec) R.sections(ctx, secs) R.body(ctx, room) R.build(id, st)
 *   R.page(ctx, id, st, pageOpts) R.placeholder(ctx, title) R.rooms R.ranked(counters) R.QL R.qlTile(link, o) R.qlGrid(o) R.roomsGrid(o) R.cu(o) R.apps(list)
 *   R.sheet.* (group details for the room card sheet) R.pushInSheet(stage, opts) R.sheetThenPush(stage, ...) R.fan(o) R.toggle(el, on)
 */
(function () {
  'use strict';
  var h = Mock.h, K = Mock.components, I = Mock.icon;
  var R = Mock.rooms = {};

  /* ------------------------------------------------------------------ 1. symbols the kit lacks (SymbolMap.swift names) */
  (function () {
    function c(x, y, r) { return '<circle cx="' + x + '" cy="' + y + '" r="' + r + '"/>'; }
    function p(d) { return '<path d="' + d + '"/>'; }
    function rc(x, y, w, hh, r) { return '<rect x="' + x + '" y="' + y + '" width="' + w + '" height="' + hh + '" rx="' + (r || 0) + '"/>'; }
    var appliance = rc(4, 3.5, 16, 17, 2) + p('M4 8h16M7 5.8h.01M10 5.8h.01');
    var add = {
      'stove': rc(4, 3.5, 16, 17, 2) + p('M4 9h16M8 6.3h.01M12 6.3h.01M16 6.3h.01') + rc(7.5, 12, 9, 5.5, 1.2),
      'stairs': p('M3.5 20.5h4.5v-4.5h4.5v-4.5h4.5V7h3'),
      'bathtub': p('M3 12h18v1.6A5.4 5.4 0 0 1 15.6 19H8.4A5.4 5.4 0 0 1 3 13.6zM6 12V6.8a2.2 2.2 0 0 1 4.1-1.1M7.5 19l-.8 1.8M16.5 19l.8 1.8'),
      'desktopcomputer': rc(3.5, 4, 17, 11.5, 1.8) + p('M9 20h6M12 15.5V20M3.5 12h17'),
      'window.vertical.closed': rc(5, 3.5, 14, 17, 1.5) + p('M12 3.5v17M5 12h14'),
      'window.vertical.open': rc(5, 3.5, 14, 17, 1.5) + p('M12 3.5v17M5 12h7M12 6.2l5.5 2.2v7.2L12 17.8'),
      'air.purifier': rc(6, 3.5, 12, 17, 2.4) + p('M9 7.5h6') + c(12, 13.5, 3.4) + p('M12 10.1v6.8M8.6 13.5h6.8'),
      'heat.waves': p('M4.5 6.5c1.5-1.5 1.5 1.5 3 0s1.5 1.5 3 0 1.5 1.5 3 0 1.5 1.5 3 0M4.5 12c1.5-1.5 1.5 1.5 3 0s1.5 1.5 3 0 1.5 1.5 3 0 1.5 1.5 3 0M4.5 17.5c1.5-1.5 1.5 1.5 3 0s1.5 1.5 3 0 1.5 1.5 3 0 1.5 1.5 3 0'),
      'dishwasher': appliance + c(12, 14.2, 3.8) + p('M9.7 14.8c1 1 3 1 4.3-.4'),
      'washer': appliance + c(12, 14.2, 4) + p('M9 14.5c1.5-1.5 4.5 1.5 6 0'),
      'dryer': appliance + c(12, 14.2, 4) + p('M10 12.2a2.5 2.5 0 0 1 4 .1'),
      'sunrise': p('M3 18.5h18M6.8 18.5a5.2 5.2 0 0 1 10.4 0M12 6.5v4M5.2 10.8l1.8 1.8M18.8 10.8l-1.8 1.8M9.8 5.2 12 3l2.2 2.2'),
      'apple.logo': p('M12 8.4c-1.4-1.3-4.7-1-5.9 1.7-1.2 2.8.4 7.3 2.4 8.9 1.1.9 2.1.4 3.5.4s2.4.5 3.5-.4c1.1-.9 2.1-2.5 2.4-3.8-1.8-.8-2.5-3.6-.4-5.1-1.2-1.4-3.4-1.1-4.4-.2zM13 7c.2-1.5 1-2.6 2.3-3.2'),
      'appletvremote.gen4': rc(8, 2.5, 8, 19, 3.5) + c(12, 8.5, 2.4) + p('M10.2 15h3.6M10.2 18h3.6'),
      'figure.stand': c(12, 4.5, 1.9) + p('M12 8.5V15M8.3 10.3h7.4M12 15l-2.6 6M12 15l2.6 6'),
      'server.rack': rc(4, 4, 16, 5, 1.5) + rc(4, 10, 16, 5, 1.5) + rc(4, 16, 16, 4, 1.5) + p('M7 6.5h.01M7 12.5h.01M7 18h.01'),
    };
    Object.keys(add).forEach(function (k) { if (!Mock.symbols[k]) Mock.symbols[k] = add[k]; });
  })();

  /* ------------------------------------------------------------------ 2. local CSS (rm-* classes; every size is a Dynamic Type token) */
  var css = [
    '.k-wrap .ui-hdr h2,.k-wrap .rm-cu h2{margin:0;letter-spacing:0;scroll-margin-top:0}', /* kit gap: page furniture .k-wrap h2 (44 px margin, 22 px) wins over .ui-hdr h2 inside a stage; promote the fix to kit.css */
    '.k-wrap .ui-hdr h2{font:700 var(--fs-t3)/1.2 var(--font-d)}',
    '.k-wrap .rm-cu h2{font:700 var(--fs-t2)/1.2 var(--font-d)}',
    '.in-sheet .ui-tile.power{--ul:var(--fam-power-fill);--tile-ink:var(--lit-ink);--tile-ink-2:var(--power-ink-2);--tile-glyph:var(--lit-ink)}', /* kit gap: a power tile in a sheet takes the sheet ink (white) on yellow; the app keeps dark ink. Promote to kit.css */
    '.rm-sections{display:grid;gap:24px;align-items:start;grid-template-columns:repeat(auto-fill,minmax(min(100%,max(calc(340px * max(1, var(--sc, 1))),calc((100% - 24px)/2))),1fr))}', /* DynamicGridLayout(minCellWidth 340, maxColumns 2, spacing 24); the minimum scales with text up only (duo-widths rule 5): two columns need 704 pt at every size, so the unfolded Duo in portrait (637 pt) is always one */
    '.rm-section{display:flex;flex-direction:column;gap:12px;min-width:0}',
    '.rm-insheet{padding-top:8px}',
    '.rm-stack{display:flex;flex-direction:column;gap:12px}',
    '.rm-sheetbody{max-width:720px;margin:0 auto;display:flex;flex-direction:column;gap:16px}',
    '.rm-sub{margin:0;font-size:var(--fs-sub);color:var(--ink-sheet-2)}',
    '.rm-foot{margin:0;font-size:var(--fs-foot);color:var(--ink-sheet-2)}',
    '.rm-cu{display:flex;flex-direction:column;align-items:center;justify-content:center;text-align:center;gap:8px;padding:40px 16px;color:var(--ink,#fff)}',
    '.rm-cu .sym{font-size:var(--fs-lt);color:var(--ink-sheet-2,rgba(235,235,245,.6))} .rm-cu .sym svg{width:1.4em;height:1.4em}',
    '.rm-cu h2{margin:0;font:700 var(--fs-t2)/1.2 var(--font-d)}',
    '.rm-cu p{margin:0;font-size:var(--fs-co);color:var(--ink-sheet-2,rgba(235,235,245,.6));max-width:34ch}',
    '.rm-apps{display:grid;gap:12px;align-items:start;grid-template-columns:repeat(auto-fill,minmax(max(calc(110px*var(--sc)),calc((100% - 5*12px)/6)),1fr))}',
    '.rm-app{background:none;border:0;padding:0;color:#fff;font:inherit;display:flex;flex-direction:column;align-items:center;gap:4px;cursor:pointer;min-width:0}',
    '.rm-app .art{width:100%;max-width:168px;aspect-ratio:1;border-radius:16px;background:var(--g-module-thin);border:1px solid var(--sep);display:grid;place-items:center;font-size:var(--fs-lt);color:color-mix(in srgb,var(--fam-media-glyph) 88%,var(--off-grey-dark));box-sizing:border-box}',
    '.rm-app .art svg{width:1em;height:1em}',
    '.rm-app.white .art{background:#fff;color:#000}',
    '.rm-app.on .art{border:3px solid var(--fam-media-glyph)}',
    '.rm-app .ti{font-size:var(--fs-sub);text-align:center}',
    '.rm-app .st{font-size:var(--fs-foot);color:var(--g-secondary-on-module)}',
    '.rm-app[disabled]{opacity:.4;cursor:default}',
    '.rm-fanrail{display:flex;gap:8px;margin-right:20px}',
    '.rm-fanbtn{width:min(calc(44px*var(--sc)),66px);height:min(calc(44px*var(--sc)),66px);border-radius:50%;border:0;padding:0;display:grid;place-items:center;background:rgba(255,255,255,.12);color:#fff;cursor:pointer;flex:none;transition:background var(--t-state) var(--ease-state),color var(--t-state) var(--ease-state)}',
    '.rm-fanbtn svg{width:min(calc(18px*var(--sc)),calc(min(calc(44px*var(--sc)),66px)*.45));height:min(calc(18px*var(--sc)),calc(min(calc(44px*var(--sc)),66px)*.45))}',
    '.rm-fanbtn.tilelit{background:rgba(0,0,0,.18)}',
    '.rm-fanbtn.on{background:#fff;color:var(--fam-air-fill)}',
    '.rm-grid-note{font-size:var(--fs-foot);color:var(--g-secondary-on-wallpaper);margin:0}',
    '.rm-qlwrap{max-width:560px;margin:0 auto}',
    '.rm-cap{margin:6px 0 0;font:600 11px var(--mono);opacity:.65;letter-spacing:.04em}',
    '.rm-lbl{font:600 11px var(--mono);letter-spacing:.04em;opacity:.65;margin:0 0 6px}',
    '.rm-redact-note{font-size:var(--fs-foot)}',
  ].join('\n');
  var st = document.createElement('style'); st.id = 'rm-style'; st.textContent = css; document.head.appendChild(st);

  /* ------------------------------------------------------------------ 3. rooms (RoomNavigation.items) and the visit counters (fixture) */
  var ROOM_DEFS = [['Living Room', 'living-room', 'sofa'], ['Guest Room', 'guest-room', 'bed.double'], ['Gym', 'gym', 'dumbbell'], ['Bedroom 1', 'master-bedroom', 'bed.double'],
    ['Office', 'office', 'desktopcomputer'], ['Hallway', 'hallway', 'door.left.hand.open'], ['Kitchen', 'kitchen', 'stove'], ['Studio', 'music-room', 'music.note'],
    ['Garage', 'garage', 'door.garage.closed'], ['Media Room', 'theater-room', 'film'], ['Back Deck', 'back-deck', 'flame'], ['Downstairs Hallway', 'downstairs-hallway', 'stairs'],
    ['Guest Bathroom', 'guest-bathroom', 'shower'], ['Bathroom 1', 'master-bathroom', 'bathtub'], ['Dining Room', 'dining-room', 'fork.knife'], ['Entryway', 'entryway', 'door.left.hand.closed']];
  R.rooms = ROOM_DEFS.map(function (d, i) { return { title: d[0], path: d[1], sym: d[2], fill: 'var(--room-' + d[1] + ')', index: i }; });
  R.byPath = {}; R.rooms.forEach(function (r) { R.byPath[r.path] = r; });
  /** RoomsFixtures: counter.demo_media_room_<room> = [4,1,2,9,7,0,12,5,1,3][index % 10]. */
  R.counters = {}; R.rooms.forEach(function (r) { R.counters[r.path] = [4, 1, 2, 9, 7, 0, 12, 5, 1, 3][r.index % 10]; });
  /** RoomNavigation.ranked: most visited first, ties keep configured order. */
  R.ranked = function (counters) {
    counters = counters || R.counters;
    return R.rooms.slice().sort(function (a, b) { var d = (counters[b.path] || 0) - (counters[a.path] || 0); return d || a.index - b.index; });
  };

  /* ------------------------------------------------------------------ 4. tiles (RoomCardTile -> GlassTile) */
  var KIND = { modal: 'navigate', toggle: 'toggle', command: 'command', selection: 'selection', state: 'state' };
  /**
   * A room card (or any tile) from a short spec.
   * spec: {t title, s subtitle, sym, fam, on, u unavailable (dimmed, not tappable), err, k:'modal'|'toggle'|'command'|'selection'|'state', full (spans the row),
   *   acc (accessory node), accW, fill (css colour), layout:'stack', lines:2, sel, progress, id}
   */
  R.tile = function (s, o) {
    o = o || {};
    var n = Mock.tile({ title: s.t, subtitle: s.s, symbol: s.sym, family: s.fam, isActive: !!s.on, isUnavailable: !!s.u, isError: !!s.err, kind: KIND[s.k || 'modal'], progress: s.progress,
      accessory: s.acc, accessoryWidth: s.accW, fill: s.fill, layout: s.layout, titleLines: s.lines, selected: s.sel, pending: s.pending,
      behavior: s.beh, actions: s.acts, below: s.below, under: s.under });
    if (s.full && o.span !== false) n.style.gridColumn = '1 / -1';
    if (s.id) n.setAttribute('data-ident', s.id);
    return n;
  };
  /** A grid of tiles (DynamicGridLayout, equal heights). min is the scaled minimum cell width. */
  R.grid = function (cards, max, min, o) {
    return K.TileGrid(Object.assign({ items: cards.map(function (c) { return c.nodeType ? c : R.tile(c); }), min: min || 140, max: max || 4 }, o));
  };

  /**
   * A grid whose tiles share the tallest tile's height while section headings (class gridheader) keep their own row, as DynamicGridLayout does with
   * `gridHeader()` and `equalRowHeights` (the kit's equal grid sizes a heading row like a tile row). Promote to kit: TileGrid support for headings.
   */
  R.eqGrid = function (nodes, min, max) {
    var g = K.TileGrid({ items: nodes, min: min || 140, max: max || 4, equal: false }), busy = false;
    function tiles() { return [].filter.call(g.children, function (c) { return c.classList.contains('ui-tile'); }); }
    function fit() {
      if (busy || !g.isConnected) return; busy = true;
      var t = tiles(); t.forEach(function (n) { n.style.minHeight = ''; });
      var m = 0; t.forEach(function (n) { m = Math.max(m, n.offsetHeight); });
      if (m) t.forEach(function (n) { n.style.minHeight = m + 'px'; });
      requestAnimationFrame(function () { busy = false; });
    }
    if (window.ResizeObserver) new ResizeObserver(function () { fit(); }).observe(g);
    Mock.whenAttached(g, fit);
    return g;
  };

  /* Card builders: one per RoomCard shape in RoomsConfig, with the face rules of RoomTileFace.resolve. `st.u` = every entity unavailable. */
  var C = R.card = {};
  C.vents = function (title, st) { st = st || {}; return { t: title, s: st.u ? 'Unavailable' : (st.closed ? 'Closed' : 'Open'), sym: 'aqi.medium', fam: 'vents', on: !st.u && !st.closed, u: !!st.u, k: 'modal', id: 'room.card.' + title }; };
  /* Tile rollout R (claude/tile-rollout): the purifier and the humidifier are navigation tiles (glyph . text . chevron) with a toggle-styled Power disc left of the chevron; the disc runs
     explicit turn_on / turn_off on fan.<room>_levoit_purifier or switch.demo_power_1 (optimistic). Vents stay a navigation tile with no disc. */
  C.purifier = function (st) { st = st || {}; var on = !st.u && st.purifierOff !== true;
    return { t: 'Air Purifier', s: st.u ? 'Unavailable • Unavailable' : 'Auto • ' + (on ? 'On' : 'Off'), sym: 'fan', fam: 'air', on: on, u: !!st.u, k: 'modal', id: 'room.card.Air Purifier', beh: 'navigate',
      acts: [{ id: 'power', symbol: 'power', label: (on ? 'Turn Off ' : 'Turn On ') + 'Air Purifier', on: on, dim: !!st.u }] }; };
  C.humidifier = function (st) { st = st || {}; var u = !!st.u, on = !u && st.humidifier === 'on';
    return { t: 'Humidifier', s: u ? 'Unavailable • Unavailable' : (on ? 'On • 44%' : 'Off • 44%'), sym: 'humidifier', fam: 'water', on: on, u: u, k: 'modal', id: 'room.card.Humidifier', beh: 'navigate',
      acts: [{ id: 'power', symbol: 'power', label: (on ? 'Turn Off ' : 'Turn On ') + 'Humidifier', on: on, dim: u }] }; };
  /* A Studio source chooses (selection-tiles option C): filled with a white check disc while chosen, dark with an empty ring otherwise; the state line is "On the TV" while chosen and
     nothing otherwise. The chosen disc's label is "Turn Off TV" (a tap turns the TV off; Game relaunches). With Game active, Game Console and Game both read chosen. */
  C.source = function (title, sym, chosen, st) { st = st || {}; var u = !!st.u, on = !u && !!chosen;
    return { t: title, s: u ? 'Unavailable' : (on ? 'On the TV' : null), sym: sym, fam: 'media', on: on, u: u, k: 'selection', sel: on, id: 'room.card.' + title, beh: 'perform',
      acts: [{ id: 'source', symbol: on ? 'checkmark' : 'circle', label: on && title !== 'Game' ? 'Turn Off TV' : 'Select ' + title, on: on, dim: u }] }; };
  /* Nintendo Switch and Media Room Streaming Box: an action tile (text . disc, no leading glyph) with a toggle-styled power disc, tracked through the tile's own script: the disc shows the arc
     spinner until the input_boolean.demo_input_boolean_*_active reports, then settles on the final glyph and fill. "Turning On…" is the in-flight line; a failure reads "Didn't Respond". */
  C.scripted = function (title, sym, st, on, flight) { st = st || {}; var u = !!st.u; on = !u && !!on;
    return { t: title, s: u ? 'Unavailable' : (flight ? (on ? 'Turning Off…' : 'Turning On…') : (on ? 'On' : 'Off')), sym: sym, fam: 'media', on: on, u: false, k: 'toggle', id: 'room.card.' + title, beh: 'perform',
      acts: [{ id: 'power', symbol: 'power', label: (on ? 'Turn Off ' : 'Turn On ') + title, on: on, dim: u, busy: !!flight }] }; };
  /* action-tiles.md: navigation tile (glyph . text . chevron) with start/pause and dock discs left of the chevron; dock is momentary house.fill */
  C.vacuum = function (title, st) { st = st || {}; return { t: title, sym: 'robotic.vacuum', fam: 'cleaning', on: !st.u && !!st.cleaning, u: !!st.u, k: 'modal', full: true, id: 'room.card.' + title,
    beh: 'navigate', acts: [{ id: 'start_pause', symbol: st.cleaning ? 'pause.fill' : 'play.fill', label: (st.cleaning ? 'Pause ' : 'Start ') + title, on: !!st.cleaning, dim: !!st.u }, { id: 'dock', symbol: 'house.fill', label: 'Dock ' + title, dim: !!st.u }] }; };
  /* action-tiles.md: off = Power beside the chevron; playing/paused = prev, play/pause, next below the text and the volume slider (TileVolumeSlider) */
  C.remote = function (title, sym, st) { st = st || {}; var playing = !!st.playing, paused = !!st.paused, transport = !st.u && (playing || paused);
    var c = { t: title, s: st.u ? 'Unavailable' : (playing ? 'Playing' : (paused ? 'Paused' : 'Off')), sym: sym || 'appletvremote.gen4', fam: 'media', on: !st.u && (playing || paused), u: false, k: 'modal', id: 'room.card.' + title, beh: 'navigate' };
    if (transport) { c.full = true; c.acts = [{ id: 'previous', symbol: 'backward.fill', label: 'Previous ' + title }, { id: 'play_pause', symbol: playing ? 'pause.fill' : 'play.fill', label: (playing ? 'Pause ' : 'Play ') + title, on: true }, { id: 'next', symbol: 'forward.fill', label: 'Next ' + title }]; c.below = true; }
    else c.acts = [{ id: 'power', symbol: 'power', label: 'Turn On ' + title, dim: !!st.u }];
    if (transport && st.volume != null) c.under = Mock.tileVolume(st.volume, title + ' volume');
    return c; };
  C.pc = function (title, sym, st, on) { return { t: title, s: st && st.u ? 'Unavailable' : (on ? 'On' : 'Off'), sym: sym || 'gamecontroller', fam: 'power', on: !!on && !(st && st.u), u: false, k: 'command', id: 'room.card.' + title,
    beh: 'perform', acts: [{ id: 'power', symbol: 'power', label: (on ? 'Turn Off ' : 'Turn On ') + title, on: !!on && !(st && st.u), dim: !!(st && st.u) }] }; };
  C.towel = function (st, on) { return { t: 'Towel Rack', s: st && st.u ? 'Unavailable' : (on ? 'On' : 'Off'), sym: 'heat.waves', fam: 'power', on: !!on && !(st && st.u), u: false, k: 'toggle', id: 'room.card.Towel Rack',
    beh: 'perform', acts: [{ id: 'power', symbol: 'power', label: (on ? 'Turn Off ' : 'Turn On ') + 'Towel Rack', on: !!on && !(st && st.u), dim: !!(st && st.u) }] }; };
  C.laundry = function (title, sym, st) { return { t: title, s: st && st.u ? 'Unavailable' : 'Off', sym: sym, fam: 'cleaning', on: false, k: 'state', id: 'room.card.' + title }; };
  C.garage = function (title, state, st) {
    var u = st && st.u, open = state && state !== 'closed';
    return { t: title, s: u ? 'Unavailable' : (state === 'error' ? 'Error' : (state === 'sending' ? 'Sending Open…' : R.title(state))), sym: open || state === 'sending' ? 'door.garage.open' : 'door.garage.closed', fam: 'contact',
      on: !u && state !== 'closed' && state !== 'error', u: false, err: state === 'error', k: 'command', id: 'room.card.' + title,
      beh: 'perform', acts: [{ id: 'door', symbol: open || state === 'sending' ? 'door.garage.open' : 'door.garage.closed', label: (open ? 'Close ' : 'Open ') + title, on: !u && state !== 'closed' && state !== 'error', dim: !!u, busy: state === 'sending' }] };
  };
  R.title = function (s) { return String(s).split('_').map(function (w) { return w.charAt(0).toUpperCase() + w.slice(1); }).join(' '); };
  /** The bathroom fan (BathroomFanRoomTile): a navigation tile whose Lock and Power are action discs left of the chevron (ids room.card.Fan.action.lock|power). */
  R.fan = function (o) {
    o = o || {};
    var lit = !!o.on;
    if (o.u) return { t: 'Fan', s: 'Unavailable', sym: 'fan', fam: 'air', on: false, k: 'modal', full: true, id: 'room.card.Fan' };
    return { t: 'Fan', s: o.status || (lit ? 'On' : 'Off'), sym: 'fan', fam: 'air', on: lit, k: 'modal', full: true, id: 'room.card.Fan', isFan: true, beh: 'navigate',
      acts: [{ id: 'lock', symbol: o.locked ? 'lock.fill' : 'lock.open', label: (o.locked ? 'Unlock' : 'Lock') + ' Fan', on: !!o.locked, dim: o.lockAvail === false }, { id: 'power', symbol: 'power', label: (lit ? 'Turn Off' : 'Turn On') + ' Fan', on: lit }] };
  };

  /* ------------------------------------------------------------------ 5. chips (RoomChip, StatusChipAppearance.room) */
  var CSYM = { closed: 'door.left.hand.closed', home: 'door.left.hand.open', away: 'door.left.hand.open', armed: 'exclamationmark.triangle' };
  var Ch = R.chip = {
    lights: function (title, on, sym, u) { return { title: title, summary: u ? 'Unavailable' : (on ? 'On' : 'Off'), symbol: sym || 'lightbulb.2', family: 'lights', isActive: !!on && !u }; },
    climate: function (range, mean, u) { var c = Mock.chips.climate(range || '68–72°F', mean || 70); c.title = 'Climate'; if (u) { c.summary = 'Unavailable'; delete c.tint; } return c; },
    occupancy: function (det, u, inert) { var c = Mock.chips.occupancy(!!det); if (u) { c.summary = 'Unavailable'; c.isActive = false; } if (inert) c.inert = true; return c; },
    /** state: 'closed' | 'home' | 'away' | 'armed'; title ends in "s" reads "All Closed" while closed; u = unavailable. */
    contact: function (title, state, u, symFallback) {
      if (u) return { title: title, summary: 'Unavailable', symbol: symFallback || 'window.vertical.closed', family: 'contact', isActive: false };
      var c = Mock.chips.contacts(state || 'closed', 1);
      return { title: title, summary: state && state !== 'closed' ? 'Open' : (/s$/.test(title) ? 'All Closed' : 'Closed'), symbol: CSYM[state || 'closed'], family: 'contact', isActive: true, tint: c.tint };
    },
    air: function (summary, u) { var c = Mock.chips.airQuality(u ? 'Unavailable' : (summary || '38 • 6 µg/m³')); c.title = 'Air Quality'; c.symbol = 'air.purifier'; return c; },
  };
  /** An inert chip (no sheet: not a button, still read as "<title>, <summary>"). */
  R.inert = function (n) {
    var d = h('div'); d.className = n.className; d.style.cssText = n.style.cssText; d.style.cursor = 'default';
    while (n.firstChild) d.appendChild(n.firstChild);
    d.setAttribute('role', 'group'); d.setAttribute('aria-label', n.getAttribute('aria-label')); d.removeAttribute('title'); d.dataset.chip = n.dataset.chip || '';
    return d;
  };
  /** The room's status rail (RoomStatusRail): a ChipRail labelled "<room> status". */
  R.rail = function (ctx, title, chips) {
    var nodes = chips.map(function (p) { var n = K.StatusChip(p); return p.inert ? R.inert(n) : n; });
    var rail = K.ChipRail({ chips: nodes, ctx: ctx });
    var g = rail.querySelector('[role=group]'); if (g) g.setAttribute('aria-label', title + ' status');
    return rail;
  };

  /* ------------------------------------------------------------------ 6. sections (RoomSectionView) and the section grid */
  R.hdr = function (title, inSheet) { var n = K.PageSectionHeader({ title: title }); if (inSheet) n.classList.add('rm-insheet'); return n; };
  /** App launcher: square tiles of the remote's apps (artwork is a remote image; the mockup draws the placeholder glyph the app shows while it loads). */
  R.APPS = [{ t: 'Plex' }, { t: 'Streaming B', white: true }, { t: 'Streaming C' }, { t: 'Prime Video' }, { t: 'Streaming E' }, { t: 'Streaming F' }];
  R.apps = function (list, o) {
    o = o || {};
    return h('div.rm-apps', (list || R.APPS).map(function (a) {
      var on = o.active && o.active === a.t;
      var b = h('button.rm-app' + (a.white ? '.white' : '') + (on ? '.on' : ''), { type: 'button', 'aria-label': a.t, dataset: { ident: 'room.app.' + a.t } }, h('span.art', { html: I('play.rectangle', { fill: true }) }), h('span.ti', a.t), on ? h('span.st', 'Playing') : null);
      if (o.u) b.disabled = true;
      return b;
    }));
  };
  /**
   * One titled section. sec: {title, layout:'grid'|'leadRow'|'twoColumnFill'|'appLaunch', cards:[spec], apps?, active?, u?}
   * leadRow: the lead card alone, then the rest (two filling columns when more than two follow; at regular width a bathroom fan lead joins the grid).
   */
  R.section = function (ctx, sec) {
    var lay = sec.layout || 'grid', kids = [K.PageSectionHeader({ title: sec.title })], cards = sec.cards || [];
    if (lay === 'grid') kids.push(R.grid(cards, 4));
    else if (lay === 'twoColumnFill') kids.push(R.grid(cards, 2));
    else if (lay === 'leadRow') {
      if (ctx.regular && cards[0] && cards[0].isFan) kids.push(K.TileGrid({ items: cards.map(function (c) { return R.tile(c, { span: false }); }), min: 140, max: 2 }));
      else {
        if (cards[0]) kids.push(R.tile(cards[0], { span: false }));
        var rest = cards.slice(1);
        if (rest.length) kids.push(R.grid(rest, rest.length > 2 ? 2 : 4));
      }
    } else if (lay === 'appLaunch') kids.push(R.apps(sec.apps, { active: sec.active, u: sec.u }));
    return h('div.rm-section', { role: 'group', 'aria-label': sec.title, dataset: { section: sec.title } }, kids);
  };
  /** The sections in the page's responsive section grid (two columns from 704 pt; an app launcher spans both, and a section with nothing beside it in its row
   *  spans both: duo-widths rules 1 and 6, the short-row fill applied to the section grid; one column is unchanged by it). */
  R.sections = function (ctx, secs, head) {
    /* Partly folded Duo (section-sides.md, claude/section-sides): fold columns. A section's side is the parity of its configured index (even leads, odd trails),
       which is the side today's two-track grid gave it; an app launcher or a page's only section no longer spans, so a one-section room leads and its trailing
       side is empty. Column-major: each side stacks, so no row holes. */
    if (ctx.splitAtHinge && ctx.splitGeometry) {
      var lead = [], trail = [];
      secs.forEach(function (s, i) { (i % 2 ? trail : lead).push(s.node || R.section(ctx, s)); });
      if (head) lead.unshift(head); /* a wrapped rail (accessibility sizes) heads the leading column, outside the parity count (section-sides.md rule 11) */
      var cols = Mock.foldColumns(ctx, { leading: lead, trailing: trail });
      return h('div.ui-bleed', { style: { margin: 0 }, dataset: { fold: 'columns' } }, cols);
    }
    var n = secs.length, g = h('div.rm-sections'), pending = null;
    secs.forEach(function (s) {
      var node = s.node || R.section(ctx, s), full = s.layout === 'appLaunch' || n === 1 || s.span2;
      if (full) { if (pending) pending.style.gridColumn = '1 / -1'; pending = null; node.style.gridColumn = '1 / -1'; }
      else if (pending) pending = null;   // the second of a pair: the row is full
      else pending = node;                 // first in its row: spans both if nothing joins it
      g.appendChild(node);
    });
    if (pending) pending.style.gridColumn = '1 / -1';
    return g;
  };
  /** ContentUnavailableView stand-in: symbol, title, description. */
  R.cu = function (o) {
    return h('div.rm-cu' + (o.cls ? '.' + o.cls : ''), { role: 'group', 'aria-label': o.title + (o.desc ? ', ' + o.desc : '') }, h('span.sym', { html: I(o.sym || 'house') }), h('h2', o.title), o.desc ? h('p', o.desc) : null);
  };

  /* ------------------------------------------------------------------ 7. room page specs (RoomsConfig) as functions of a state */
  var B = R.pages = {};
  /** st: {u: every entity unavailable, window: 'closed'|'home'|'armed', lightsOn, occ, playing, cleaning, ...}. */
  B['living-room'] = function (st) {
    var u = st.u;
    return {
      chips: [Ch.lights('Lights', st.lightsOn !== false, 'lightbulb.2', u), Ch.climate('68–72°F', 70, u), Ch.occupancy(st.occ !== false, u), Ch.contact('Window', st.window || 'closed', u), Ch.air('38 • 6 µg/m³', u)],
      sections: [
        { title: 'Climate', cards: [C.vents('Vents', st), C.purifier(st)] },
        { title: 'Devices', cards: [C.vacuum('Main Floor', st)] },
        { title: 'Remote', cards: [C.remote('Living Room Remote', 'appletvremote.gen4', st)] },
        { title: 'Quick App Launch', layout: 'appLaunch', active: st.playing ? 'Streaming C' : null, u: u },
      ],
    };
  };
  B['kitchen'] = function (st) {
    var u = st.u, running = st.dishwasher === 'run';
    var dish = { t: 'Dishwasher', s: u ? 'Unavailable • Unavailable' : (running ? 'Eco 50°C • 42%' : 'Ready • Eco 50°C'), sym: 'dishwasher', fam: 'cleaning', on: !u && running, u: !!u, k: 'modal', full: true, id: 'room.card.Dishwasher' };
    return {
      kitchen: true, groceries: st.groceries == null ? 5 : st.groceries, food: st.food || [42, 3],
      chips: [Ch.lights('Lights', st.lightsOn === true, 'lightbulb.2', u), Ch.climate('68–72°F', 70, u), Ch.occupancy(st.occ !== false, u), Ch.contact('Door', st.door || 'closed', u, 'door.left.hand.closed')],
      sections: [{ title: 'Appliances', cards: [dish] }, { title: 'Climate', cards: [C.vents('Vent', st)] }],
    };
  };
  /** Bedroom 1: beds are BedSideController tiles (face from ThermostatTileFace.bedSide); the wake light is the generic tile reading the status sensor. */
  R.bedTile = function (title, b, st, ident) {
    b = b || { action: 'heating', level: 3 };
    var lvl = b.level == null ? 0 : b.level, fmt = lvl === 0 ? '0' : (lvl > 0 ? '+' + lvl : String(lvl)), fam = lvl < 0 ? 'cooling' : 'heating';
    var s, on = true, u = false;
    if (st && st.u) { u = true; s = 'Unavailable'; on = false; fam = 'neutral'; }
    else if (b.readOnly) { s = 'Away · Read Only'; on = false; }
    else if (b.action === 'off') { s = 'Off'; on = false; }
    else if (b.hot) { s = b.hold ? b.hold + ' Remaining' : 'Hot Flash Mode • Cooling'; fam = 'cooling'; }
    else { fam = b.action === 'cooling' ? 'cooling' : (b.action === 'heating' ? 'heating' : fam); s = R.title(b.action) + ' • ' + fmt; }
    if (b.whole && !u) s = 'Whole Bed • ' + s;
    /* Rollout R: a navigation tile with a toggle-styled Power disc (BedSidePowerActions); turning off asks "Turn off <bed>?" in a dialog, a Solo Trip traveler's side dims the disc. */
    return { t: title, s: s, sym: 'bed.double', fam: fam, on: on, u: u, k: 'modal', id: 'room.card.' + (ident || title), beh: 'navigate',
      acts: [{ id: 'power', symbol: 'power', label: (on ? 'Turn Off ' : 'Turn On ') + (ident || title), on: on, dim: u || !!b.readOnly }] };
  };
  B['master-bedroom'] = function (st) {
    var u = st.u, beds = st.beds || {};
    var wake = { t: 'Wake-Light Alarms', s: u ? 'Unavailable' : (st.wake || 'Scheduled'), sym: 'sunrise', fam: 'lights', on: false, u: !!u, k: 'modal', id: 'room.card.Wake-Light Alarms' };
    var tv = { t: 'Streamer', s: u ? 'Unavailable' : (st.tv || 'Off'), sym: 'apple.logo', fam: 'media', on: !u && /^(Idle|Paused|Playing)$/.test(st.tv || ''), u: !!u, k: 'modal', full: true, id: 'room.card.Apple TV' };
    var hum = C.humidifier(st);
    return {
      chips: [Ch.lights('Lights', st.lightsOn === true, 'lightbulb.2', u), Ch.climate('68–72°F', 70, u), Ch.occupancy(st.occ === true, u), Ch.contact('Window', st.window || 'closed', u), Ch.air('38 • 6 µg/m³', u)],
      sections: [
        { title: 'Sleep & Wake', layout: 'twoColumnFill', cards: [wake] },
        { title: 'Bed', layout: 'twoColumnFill', cards: [R.bedTile(st.viewer === 'sam' ? 'Alex\'s Side' : 'Your Side', beds.left || { action: 'heating', level: 3 }, st, 'Alex\'s Bed'), R.bedTile(st.viewer === 'sam' ? 'Your Side' : 'Sam\'s Side', beds.right || { action: 'cooling', level: -3 }, st, 'Sam\'s Bed')] },
        { title: 'Media', cards: [tv] },
        { title: 'Climate', layout: 'twoColumnFill', cards: [C.vents('Vents', st), C.purifier(st), hum] },
      ],
    };
  };
  B['guest-bathroom'] = function (st) {
    var u = st.u;
    return {
      chips: [Ch.lights('Light', st.lightsOn === true, 'lightbulb', u), Ch.climate('68–72°F', 70, u), Ch.occupancy(st.occ === true, u)],
      sections: [{ title: 'Climate', layout: 'leadRow', cards: [R.fan({ on: st.fanOn, locked: st.locked, status: st.fanStatus, u: st.fanU || u }), C.vents('Vent', st), C.towel(st, st.towel)] }],
    };
  };
  B['master-bathroom'] = function (st) { var p = B['guest-bathroom'](Object.assign({ fanOn: true, locked: true, fanStatus: 'Off in 12:34' }, st)); return p; };
  B['garage'] = function (st) {
    var u = st.u;
    return {
      chips: [Ch.contact('Doors', st.doors || 'closed', u, 'door.left.hand.closed')],
      sections: [{ title: 'Appliances', cards: [C.laundry('Washing Machine', 'washer', st), C.laundry('Dryer', 'dryer', st)] },
        { title: 'Garage Doors', cards: [C.garage('Left Door', st.left || 'closed', st), C.garage('Right Door', st.right || 'closed', st)] }],
    };
  };
  B['music-room'] = function (st) {
    var u = st.u;
    function src(t, sym, on) { return C.source(t, sym, on, st); }
    return {
      chips: [Ch.lights('Lights', st.lightsOn === true, 'lightbulb.2', u), Ch.climate('68–72°F', 70, u), Ch.occupancy(st.occ === true, u), Ch.contact('Door', 'closed', u, 'door.left.hand.closed'), Ch.air('38 • 6 µg/m³', u)],
      sections: [
        { title: 'Climate', cards: [C.vents('Vents', st), C.purifier(st)] },
        { title: 'Remote', layout: 'leadRow', cards: [C.remote('Studio Remote', 'appletvremote.gen4', st), src('Game Console', 'gamecontroller', st.source === 'Game Console'), src('Server', 'server.rack', st.source === 'server'), src('Computer', 'pc', st.source === 'pc')] },
        { title: 'Devices', cards: [C.vacuum('Studio', st)] },
      ],
    };
  };
  B['theater-room'] = function (st) {
    var u = st.u;
    function cmd(t, sym, on, flight) { return C.scripted(t, sym, st, on, flight); }
    return {
      chips: [Ch.lights('Lights', st.lightsOn === true, 'lightbulb.2', u), Ch.climate('68–72°F', 70, u), Ch.occupancy(st.occ === true, u), Ch.contact('Door', 'closed', u, 'door.left.hand.closed'), Ch.air('38 • 6 µg/m³', u)],
      sections: [
        { title: 'Climate', cards: [C.vents('Vents', st), C.purifier(st)] },
        { title: 'Remote', layout: 'leadRow', cards: [C.remote('Media Room Remote', 'videoprojector', st), cmd('Handheld Console', 'gamecontroller', st.switchOn, st.switchFlight), cmd('Media Room Streaming Box', 'tv', st.shieldOn, st.shieldFlight)] },
        { title: 'Quick App Launch', layout: 'appLaunch', u: u },
        { title: 'Media Room Computers', cards: [C.pc('Media Room Computer', 'videoprojector', st, false)] },
        { title: 'Devices', cards: [C.vacuum('Media Room', st)] },
      ],
    };
  };
  B['office'] = function (st) {
    var u = st.u;
    return {
      chips: [Ch.lights('Light', st.lightsOn === true, 'lightbulb', u), Ch.climate('68–72°F', 70, u), Ch.occupancy(st.occ !== false, u), Ch.contact('Windows', 'closed', u), Ch.air('38 • 6 µg/m³', u)],
      sections: [{ title: 'Climate', cards: [C.vents('Vent', st), C.purifier(st)] }, { title: 'Computers', cards: [C.pc('Your PC', 'gamecontroller', st, true), C.pc('Sam\'s PC', 'gamecontroller', st, false)] }],
    };
  };
  B['back-deck'] = function (st) {
    var u = st.u;
    var grill = { t: 'Grill Probe', s: u ? 'Unavailable' : 'Off', sym: 'flame', fam: 'cooking', on: false, u: true, k: 'modal', id: 'room.card.Patio Grill' };
    return {
      chips: [Ch.lights('Lights', st.lightsOn === true, 'lightbulb.2', u), Ch.occupancy(st.occ === true, u, true), Ch.contact('Doors', 'closed', u, 'door.left.hand.closed')],
      sections: [{ title: 'Grill', cards: [grill] }],
    };
  };
  B['hallway'] = function (st) {
    var u = st.u;
    return { chips: [Ch.lights('Lights', st.lightsOn === true, 'lightbulb.2', u), Ch.climate('68–72°F', 70, u), Ch.occupancy(st.occ === true, u)], sections: [], emptyIcon: 'door.left.hand.open' };
  };
  B['entryway'] = function (st) {
    var u = st.u;
    return { chips: [Ch.lights('Light', false, 'lightbulb', u), Ch.occupancy(false, u), Ch.climate('68–72°F', 70, u), Ch.contact('Door', 'closed', u, 'door.left.hand.closed')], sections: [], emptyIcon: 'door.left.hand.closed' };
  };
  R.build = function (id, st) { var f = B[id]; return f ? f(st || {}) : { chips: [], sections: [] }; };

  /** The Kitchen's Groceries section (KitchenGroceriesSection): pages, not devices, so dark neutral navigate tiles. */
  R.groceries = function (room) {
    var items = room.groceries, grocery = items > 0 ? items + (items === 1 ? ' item' : ' items') : 'No groceries listed';
    var food = room.food, n = food[0], fs = n + ' ' + (n === 1 ? 'Item' : 'Items') + ' • ' + food[1] + ' Expiring Soon';
    var secs = h('div.rm-section', { role: 'group', 'aria-label': 'Groceries', dataset: { section: 'Groceries' } }, K.PageSectionHeader({ title: 'Groceries' }),
      R.grid([{ t: 'Grocery List', s: grocery, sym: 'checklist', fam: 'neutral', on: false, k: 'modal', id: 'room.groceries.list' }, { t: 'Food', s: fs, sym: 'fork.knife', fam: 'neutral', on: false, k: 'modal', id: 'room.groceries.food' }], 4));
    return secs;
  };

  /** The page body: status rail, then the section grid (or "Nothing Here Yet!"). */
  R.body = function (ctx, id, st) {
    var room = R.build(id, st), meta = R.byPath[id], out = [];
    var rail = room.chips && room.chips.length ? R.rail(ctx, meta.title, room.chips) : null;
    var secs = room.sections.slice();
    if (room.kitchen) secs.unshift({ node: R.groceries(room), span2: secs.length === 0 });
    /* Partly folded at an accessibility size the rail wraps and stops short of the fold, so it heads the leading column instead of spanning (section-sides.md rule 11). */
    var railLeads = !!(rail && secs.length && ctx.splitAtHinge && ctx.splitGeometry && ctx.axSize);
    if (rail && !railLeads) out.push(rail);
    if (!secs.length) out.push(h('div', R.cu({ sym: room.emptyIcon || meta.sym, title: 'Nothing Here Yet!', desc: 'Once some devices are added to this room, we can display them here.' })));
    else out.push(R.sections(ctx, secs, railLeads ? rail : null));
    return out;
  };
  /** A pushed room page on the shell: Back, Quick Links and Profile in the header (shell chrome per device). */
  R.page = function (ctx, id, st, o) {
    var meta = R.byPath[id];
    return Mock.page(ctx, Object.assign({ title: meta.title, section: 'home', back: 'Home', badge: 3, choresBadge: 2, body: R.body(ctx, id, st) }, o));
  };
  /** RoomScreen without a connection: PlaceholderScreen (ContentUnavailableView + navigation title). */
  R.placeholder = function (ctx, title) {
    return Mock.page(ctx, { title: title, section: 'home', back: 'Home', badge: 3, choresBadge: 2,
      body: [h('div', { style: { minHeight: 'calc(var(--h) - 300px)', display: 'flex', alignItems: 'center', justifyContent: 'center' } }, R.cu({ sym: 'house', title: 'Not Available Yet', desc: 'Can’t open this page right now. Check your connection and try again.' }))] });
  };

  /* ------------------------------------------------------------------ 8. Quick Links (QuickLinks.items, QuickLinkPalette) */
  var SEC = { armed_away: ['shield', 'var(--fam-sec-away-fill)', 'Armed Away'], armed_home: ['shield.lefthalf.filled', 'var(--fam-sec-home-fill)', 'Armed Home'], armed_night: ['moon.zzz', 'var(--fam-sec-night-fill)', 'Armed Night'],
    disarmed: ['shield.slash', 'var(--fam-sec-disarmed-fill)', 'Disarmed'], triggered: ['exclamationmark.shield', 'var(--fam-sec-triggered-fill)', 'Triggered'], unknown: ['shield', 'var(--ql-security-unknown)', 'Unavailable'] };
  R.SEC = SEC;
  R.QL = [
    { id: 'rooms', title: 'Rooms', sym: 'square.split.2x2', fill: 'var(--ql-rooms)', detail: true },
    { id: 'security-system', title: 'Security System', sym: 'shield', fill: 'var(--ql-security-unknown)', detail: true, status: 'entityState' },
    { id: 'food', title: 'Food & Recipes', sym: 'fork.knife', fill: 'var(--fam-food-fill)', status: 'allFood' },
    { id: 'vacuums', title: 'Vacuums', sym: 'robotic.vacuum', fill: 'var(--fam-cleaning-fill)' },
    { id: 'media', title: 'Media', sym: 'appletvremote.gen4', fill: 'var(--fam-media-fill)' },
    { id: 'custom-lights', title: 'Custom Lights', sym: 'lightbulb.2', fill: 'var(--ql-custom-lights)' },
    { id: 'sprinklers', title: 'Sprinklers', sym: 'sprinkler.and.droplets', fill: 'var(--fam-water-fill)', vis: true },
  ];
  /** One Quick Links tile as a spec. o: {alarm:'armed_home'|..., redacted, food:[42,3], u (store empty)} */
  R.qlSpec = function (link, o) {
    o = o || {};
    var s = { t: link.title, sym: link.sym, fill: link.fill, k: 'modal', layout: 'stack', lines: 2, id: 'quickLinks.' + link.id };
    if (link.id === 'security-system') {
      var key = o.u ? 'unknown' : (o.alarm || 'armed_home'), sec = SEC[key] || SEC.unknown;
      if (o.redacted) { s.s = 'Hidden'; s.sym = 'shield'; s.fill = 'var(--ql-security-unknown)'; }
      else { s.s = sec[2]; s.sym = sec[0]; s.fill = sec[1]; }
      /* Rollout L (item 17): a navigation tile with one disc left of the chevron, two tracks wide. Disarmed offers Arm Home; armed (any mode, and triggered) offers Disarm, which asks "Disarm the
         Security System?" first; arming, pending and disarming show the arc. Redacted builds draw no disc, because its verb and glyph would give the mode away. */
      if (!o.redacted) {
        var armed = !o.u && key !== 'disarmed', flight = key === 'arming' || key === 'pending';
        s.beh = 'navigate'; s.wide = true;
        s.acts = [{ id: 'alarm', symbol: armed ? 'shield.slash' : 'shield.lefthalf.filled', label: armed ? 'Disarm Security System' : 'Arm Home Security System', dim: !!o.u, busy: flight }];
      }
    }
    if (link.status === 'allFood') { var f = o.u ? [0, 0] : (o.food || [42, 3]); s.s = f[0] + ' ' + (f[0] === 1 ? 'Item' : 'Items') + ' • ' + f[1] + ' Expiring Soon'; }
    return s;
  };
  /** The Quick Links tile (QuickLinkTile): link = an R.QL entry or its id. */
  R.qlTile = function (link, o) { if (typeof link === 'string') link = R.QL.filter(function (l) { return l.id === link; })[0]; var spec = R.qlSpec(link, o), n = R.tile(spec); if (spec.wide) n.dataset.wide = '1'; return n; };
  /** The Quick Links grid (QuickLinksGrid): two columns, one height, glyph top-leading and name on the bottom line. o: {sprinklers:false hides the last tile} */
  R.qlGrid = function (o) {
    o = o || {};
    var links = R.QL.filter(function (l) { return !l.vis || o.sprinklers !== false; });
    return K.TileGrid({ items: links.map(function (l) { return R.qlTile(l, o); }), min: 140, max: 2 });
  };
  /** The Rooms grid pushed inside Quick Links (RoomNavigationGrid). counters ranks the tiles. */
  R.roomsGrid = function (o) {
    o = o || {};
    var items = R.ranked(o.counters).map(function (r) { return R.tile({ t: r.title, sym: r.sym, fill: r.fill, k: 'modal', layout: 'stack', lines: 2, id: 'rooms.' + r.path }); });
    var g = K.TileGrid({ items: items, min: 140, max: 4 });
    g.setAttribute('role', 'group'); g.setAttribute('aria-label', 'Rooms');
    return g;
  };

  /* ------------------------------------------------------------------ 9. room card sheet bodies (RoomSheetBody) */
  var SH = R.sheet = {};
  SH.state = function (title, sub, sym, fam, on, u) { return R.tile({ t: title, s: sub, sym: sym, fam: fam, on: on, u: u, k: 'state' }); };
  /** A light: BrightnessTile when it dims, else a power tile (LightGroupTile). */
  SH.light = function (title, pct, o) {
    o = o || {};
    /* Rollout L: a light or switch that does not dim is an action tile with a power disc. */
    if (o.power) return R.tile({ t: title, s: o.u ? 'Unavailable' : (pct ? 'On' : 'Off'), sym: 'lightbulb', fam: 'lights', on: !!pct && !o.u, u: o.u, k: 'toggle', beh: 'perform',
      acts: [{ id: 'power', symbol: 'power', label: (pct && !o.u ? 'Turn Off ' : 'Turn On ') + title, on: !!pct && !o.u, dim: !!o.u }] });
    return K.BrightnessTile({ title: title, percent: pct || 0, unavailable: !!o.u });
  };
  /** Lights group: heading, the room's group light as one slab (when several lights), then each light. */
  SH.lights = function (g) {
    var items = g.items, kids = [R.hdr(items.length === 1 ? 'Light' : 'Lights', true)];
    if (items.length > 1 && g.group) kids.push(SH.light(g.title, g.group.pct, { u: g.u }));
    kids.push(K.TileGrid({ items: items.map(function (i) { return SH.light(i.t, i.pct, { power: i.power, u: g.u }); }), min: 140, max: 4 }));
    return h('div.rm-stack', kids);
  };
  /** Climate group: "Temperature Sensor(s)" and "Vent(s)" runs in one equal-height grid, headings inside it. */
  SH.climate = function (g) {
    var u = g.u, nodes = [], sens = g.sensors, vents = g.vents;
    nodes.push(R.hdr(sens.length === 1 ? 'Temperature Sensor' : 'Temperature Sensors', true)); nodes[0].classList.add('gridheader');
    sens.forEach(function (s) { nodes.push(SH.state(s.t, u ? 'Unavailable' : s.v, 'thermometer.medium', 'climate', false, u)); });
    if (vents.length) {
      var hd = R.hdr(vents.length === 1 && vents[0].t !== 'Vents' ? 'Vent' : 'Vents', true); hd.classList.add('gridheader'); nodes.push(hd);
      vents.forEach(function (v) { nodes.push(SH.state(v.t, u ? 'Unavailable' : v.v, 'fan', 'vents', !u && /^Open/.test(v.v), u)); });
    }
    return R.eqGrid(nodes, 140, 4);
  };
  SH.occupancy = function (g) {
    return K.TileGrid({ items: g.items.map(function (i) { var on = !g.u && i.on; return SH.state(i.t, g.u ? 'Unavailable' : (i.on ? 'Detected' : 'Clear'), on ? 'figure.walk.motion' : 'figure.stand', 'occupancy', on, g.u); }), min: 140, max: 4 });
  };
  SH.contacts = function (g) {
    return K.TileGrid({ items: g.items.map(function (i) {
      var open = !g.u && i.open, win = !!i.window;
      return SH.state(i.t, g.u ? 'Unavailable' : (open ? 'Open' : 'Closed'), win ? (open ? 'window.vertical.open' : 'window.vertical.closed') : (open ? 'door.left.hand.open' : 'door.left.hand.closed'), 'contact', open, g.u); }), min: 140, max: 4 });
  };
  /** Vent items (RoomEntityGrid, vents face): "Open · 60%". */
  SH.items = function (g) {
    return K.TileGrid({ items: g.items.map(function (i) { return SH.state(i.t, g.u ? 'Unavailable' : i.v, 'aqi.medium', 'vents', !g.u && /^Open/.test(i.v), g.u); }), min: 140, max: 4 });
  };
  /** RoomAllContacts: every room's doors and windows; each room pushes its sensors. */
  SH.allContacts = function (o) {
    o = o || {};
    var rooms = [['Entryway', 'Door Closed', 'door.left.hand.closed', false], ['Office', 'All Windows Closed', 'window.vertical.closed', false], ['Living Room', 'Window Open', 'window.vertical.open', true], ['Garage', 'Door Closed', 'door.left.hand.closed', false],
      ['Bedroom 1', 'All Windows Closed', 'window.vertical.closed', false], ['Dining Room', 'Door Closed', 'door.left.hand.closed', false], ['Kitchen', 'Door Closed', 'door.left.hand.closed', false], ['Studio', 'Door Closed', 'door.left.hand.closed', false],
      ['Media Room', 'Door Closed', 'door.left.hand.closed', false], ['Guest Room', 'Window Closed', 'window.vertical.closed', false], ['Gym', 'Window Closed', 'window.vertical.closed', false]];
    var nodes = [R.hdr('Rooms', true)]; nodes[0].classList.add('gridheader');
    rooms.forEach(function (r) { nodes.push(R.tile({ t: r[0], s: r[1], sym: r[2], fam: 'contact', on: r[3], k: 'modal' })); });
    return R.eqGrid(nodes, 140, 6);
  };
  /** RoomDeviceFallback: the card's entities read-only, "More controls for this device are coming." */
  SH.deviceFallback = function (g) {
    return h('div.rm-stack', K.TileGrid({ items: g.items.map(function (i) { return SH.state(i.t, i.v, i.sym, g.fam, true, false); }), min: 140, max: 4 }), h('p.rm-foot', 'More controls for this device are coming.'));
  };
  /** RoomSheetFallback: no interactive controls (ContentUnavailableView). */
  SH.none = function (title, sym) { return R.cu({ sym: sym, title: title, desc: 'This source does not have interactive controls available from this view.' }); };
  /** The sheet body: optional subtitle (subheadline, secondary), then the content, in the 720 pt column of RoomCardSheet. */
  SH.body = function (sub, content) { return h('div.rm-sheetbody', sub ? h('p.rm-sub', { 'data-ident': 'room.sheet.subtitle' }, sub) : null, content); };

  /** Fixture groups for the room card sheet (RoomGroups + RoomsFixtures; a lived-in evening). title is RoomOverview.detailTitle. */
  SH.data = {
    'lights-living-room': { sheetTitle: 'Living Room Lights', title: 'Living Room Lights', group: { pct: 71 }, items: [{ t: 'Front Left', pct: 71 }, { t: 'Front Right', pct: 71 }, { t: 'Back Left', pct: 0 }, { t: 'Back Right', pct: 40 }] },
    'lights-kitchen': { sheetTitle: 'Kitchen Lights', title: 'Kitchen Lights', group: { pct: 0 }, items: [{ t: 'Table Light', pct: 0 }, { t: 'Door Light', pct: 0 }, { t: 'Counter Light', pct: 0 }, { t: 'Sink Light', pct: 0 }] },
    'lights-master-bedroom': { sheetTitle: 'Bedroom 1 Lights', title: 'Bedroom 1 Lights', group: { pct: 55 }, items: [{ t: 'Window Light', pct: 0 }, { t: 'Bathroom Light', pct: 0 }, { t: 'Door Light', pct: 0 }, { t: 'Your Nightstand', pct: 55 }, { t: 'Sam Nightstand', pct: 0 }, { t: 'Closet Light', pct: 0 }] },
    'lights-gym': { sheetTitle: 'Gym Light', title: 'Gym Light', items: [{ t: 'Gym Light', pct: 0 }] },
    'lights-entryway': { sheetTitle: 'Entryway Light', title: 'Entryway Light', items: [{ t: 'Entryway Light', pct: 100, power: true }] },
  };
  /** A room card's sheet as {title, sub, content, note}: key names the sheet (the web hash the card opens). o: {u: every entity unavailable}. */
  R.cardSheet = function (key, o) {
    o = o || {}; var u = !!o.u, d = SH.data[key];
    if (d) return { title: d.sheetTitle, sub: null, content: SH.body(null, SH.lights({ title: d.title, group: d.group, items: d.items, u: u })) };
    if (key === 'climate-kitchen') return { title: 'Kitchen Climate', sub: u ? 'Unavailable' : '68–72°F', content: SH.body(u ? 'Unavailable' : '68–72°F', SH.climate({ u: u, sensors: [{ t: 'Kitchen', v: '70.4°F' }], vents: [{ t: 'Vent', v: 'Open · 60%' }] })) };
    if (key === 'climate-living-room') return { title: 'Living Room Climate', sub: u ? 'Unavailable' : '68–72°F', content: SH.body(u ? 'Unavailable' : '68–72°F', SH.climate({ u: u, sensors: [{ t: 'Back Wall', v: '70.4°F' }, { t: 'Bar', v: '70.9°F' }, { t: 'Kitchen Wall', v: '71.2°F' }, { t: 'Fireplace', v: '72.0°F' }], vents: [{ t: 'Vents', v: 'Open · 60%' }] })) };
    if (key === 'occupancy-living-room') return { title: 'Living Room Occupancy', sub: u ? 'Unavailable' : 'Occupied', content: SH.body(u ? 'Unavailable' : 'Occupied', SH.occupancy({ u: u, items: [{ t: 'Back Wall', on: true }, { t: 'Bar', on: false }, { t: 'Kitchen Wall', on: false }, { t: 'Fireplace', on: false }] })) };
    if (key === 'window-living-room') return { title: 'Living Room Window', sub: null, content: SH.body(null, SH.contacts({ u: u, items: [{ t: 'Window', open: o.open !== false, window: true }] })) };
    if (key === 'window-master-bedroom') return { title: 'Bedroom 1 Window', sub: null, content: SH.body(null, SH.contacts({ u: u, items: [{ t: 'Side Windows', open: false, window: true }] })) };
    if (key === 'doors-garage') return { title: 'Garage Doors', sub: null, content: SH.body(null, SH.allContacts()) };
    if (key === 'vents-living-room') return { title: 'Living Room: Vents', sub: null, content: SH.body(null, SH.items({ u: u, items: [{ t: 'Vent 1', v: 'Open · 60%' }, { t: 'Vent 2', v: 'Open · 60%' }] })) };
    if (key === 'vent-kitchen') return { title: 'Kitchen: Vent', sub: null, content: SH.body(null, SH.items({ u: u, items: [{ t: 'Vent', v: 'Open · 60%' }] })) };
    if (key === 'dishwasher') return { title: 'Dishwasher', sub: null, content: SH.body(null, SH.deviceFallback({ fam: 'cleaning', items: [{ t: 'Dishwasher Door', v: u ? 'Unavailable' : 'Closed', sym: 'dishwasher' }, { t: 'Selected Program', v: u ? 'Unavailable' : 'Eco 50°C', sym: 'dishwasher' }] })) };
    if (key === 'remote-none') return { title: 'Living Room: Living Room Remote', sub: null, content: SH.body(null, SH.none('Living Room Remote', 'appletvremote.gen4')) };
    return { title: 'Room', sub: null, content: SH.body(null, null) };
  };

  /* ------------------------------------------------------------------ 10. motion helpers */
  /** Toggle a tile between its off and on faces (the 0.6 s state cross-fade is the kit's CSS) and swap its state line. */
  R.toggle = function (tile, on, text) {
    var fam = tile.dataset.family, face = on ? (fam === 'power' ? 'power' : (fam === 'lights' ? 'lit' : 'on')) : 'off';
    ['off', 'on', 'power', 'on-power', 'lit', 'tinted'].forEach(function (c) { tile.classList.remove(c); });
    tile.classList.add(face); if (face === 'power') tile.classList.add('on-power');
    var st = tile.querySelector('.st'); if (st && text) st.textContent = text;
    if (tile.hasAttribute('aria-pressed')) tile.setAttribute('aria-pressed', on ? 'true' : 'false');
    return Mock.sleep(Mock.anim.ms.state() + 60);
  };
  /** A page pushed inside a sheet (Quick Links: Rooms, Security System; room overview): the detail slides in over the root, then Back. */
  R.pushInSheet = function (stage, detailOpts, hold) {
    var panel = stage.querySelector('.ui-sheet'), root = panel && panel.querySelector('.ui-modal');
    if (!root) return Promise.resolve();
    var detail = K.HassModal(detailOpts);
    var wrap = h('div', { style: { position: 'absolute', left: 0, right: 0, top: 0, bottom: 0, zIndex: 4, background: 'var(--sheet-ground)', display: 'flex', flexDirection: 'column', paddingBottom: panel.style.paddingBottom || '0' } }, detail);
    panel.appendChild(wrap);
    return Mock.anim.push(root, wrap).then(function () { return Mock.sleep(hold || 900); }).then(function () { return Mock.anim.push(wrap, root, { back: true }); }).then(function () { wrap.remove(); root.style.transform = ''; root.style.filter = ''; });
  };
  /** A sheet closes, then the page pushes the destination (Quick Links page links: "page links close the sheet and push their page"). */
  R.sheetThenPush = function (stage, sheetOpts, nextPage) {
    var ctx = Mock.current, page = stage.querySelector('.ui-page');
    if (!page) return Promise.resolve();
    var parent = page.parentNode, next = page.nextSibling;
    var host = Mock.sheet(ctx, Object.assign({}, sheetOpts, { presenter: page }));
    parent.insertBefore(host, next);
    return Mock.sleep(500).then(function () { return Mock.anim.sheet(host, 'out'); }).then(function () {
      page.style.transform = ''; parent.insertBefore(page, host); host.remove();
      var np = nextPage(); parent.appendChild(np);
      return Mock.anim.push(page, np).then(function () { return Mock.sleep(800); }).then(function () { np.remove(); page.style.transform = ''; page.style.filter = ''; });
    });
  };

  /* ------------------------------------------------------------------ 11. presenter pages (what a sheet scales back) */
  /** Home trimmed (chips and weather): the page Quick Links is opened from. */
  R.homePresenter = function (ctx, connection) {
    var chips = K.ChipRail({ chips: Mock.chips.home({ security: 'armed_home' }), ctx: ctx });
    return Mock.page(ctx, { title: 'Home', section: 'home', badge: 3, choresBadge: 2, connection: connection || 'live', body: [chips, K.WeatherCard({ condition: 'Partly Cloudy', temp: 48, hi: 58, lo: 38 })] });
  };
  R.roomPresenter = function (ctx, id, st, connection) { return R.page(ctx, id, st, { connection: connection || 'live' }); };

  /* ------------------------------------------------------------------ 12. component registrations (local; the kit's COMPONENTS list is untouched) */
  var qlVariants = R.QL.map(function (l) { return { id: l.id, label: l.title + (l.vis ? ' (while its visibility entity is on)' : ''), props: { link: l.id } }; });
  Object.keys(SEC).forEach(function (k) { if (k !== 'unknown') qlVariants.push({ id: 'sec-' + k, label: 'Security System · ' + k, props: { link: 'security-system', alarm: k } }); });
  Mock.register('QuickLinkTile', function (p) { var n = R.qlTile(p.link || 'rooms', p); if (p.u) n.dataset.empty = 'true'; return n; }, {
    source: 'apple/Sources/HassUI/Features/Rooms/QuickLinksSheet.swift', props: '{link, alarm?, redacted?, food?, u?}',
    variants: qlVariants,
    states: [{ id: 'subtitle', label: 'With a state line (Food & Recipes)', props: { link: 'food' } }, { id: 'security-unknown', label: 'Security System, mode unknown (slate)', props: { link: 'security-system', u: true } },
      { id: 'redacted', label: 'Redacted screenshot (plain shield, "Hidden")', props: { link: 'security-system', redacted: true } }, { id: 'one-item', label: 'Singular count', props: { link: 'food', food: [1, 0] } }] });
  /** RoomCardTile: props {spec}. Variants are the cards of RoomsConfig by face. */
  var cardVariants = [
    { id: 'light-off', label: 'Light card off (dark, lights glyph)', props: { spec: { t: 'Towel Rack', s: 'Off', sym: 'heat.waves', fam: 'power', on: false, k: 'toggle' } } },
    { id: 'toggle-on', label: 'Toggle on (power: bright yellow, dark ink)', props: { spec: { t: 'Towel Rack', s: 'On', sym: 'heat.waves', fam: 'power', on: true, k: 'toggle' } } },
    { id: 'modal', label: 'Modal (chevron): vents open', props: { spec: C.vents('Vents', {}) } },
    { id: 'modal-off', label: 'Modal, off face: robot vacuum docked', props: { spec: C.vacuum('Main Floor', {}) } },
    { id: 'command', label: 'Command: PC power', props: { spec: C.pc('Your PC', 'gamecontroller', {}, true) } },
    { id: 'selection', label: 'Selection: Studio Game Console source on', props: { spec: { t: 'Game Console', s: 'On', sym: 'gamecontroller', fam: 'media', on: true, k: 'selection', sel: true } } },
    { id: 'state', label: 'State only (not a button): Washing Machine', props: { spec: C.laundry('Washing Machine', 'washer', {}) } },
    { id: 'wake', label: 'Wake-Light Alarms (never fills)', props: { spec: { t: 'Wake-Light Alarms', s: 'Scheduled', sym: 'sunrise', fam: 'lights', on: false, k: 'modal' } } },
  ];
  var cardStates = [
    { id: 'unavailable', label: 'Unavailable (dimmed, not tappable)', props: { spec: C.vents('Vents', { u: true }) } },
    { id: 'error', label: 'Didn\'t respond / Error (red): garage door', props: { spec: C.garage('Left Door', 'error', {}) } },
    { id: 'garage-open', label: 'Garage door open (contact family)', props: { spec: C.garage('Right Door', 'open', {}) } },
    { id: 'fan', label: 'Bathroom fan: Lock and Power rail, timer running', props: { spec: R.fan({ on: true, locked: true, status: 'Off in 12:34' }) } },
    { id: 'fan-off', label: 'Bathroom fan off, unlocked', props: { spec: R.fan({ on: false, locked: false }) } },
    { id: 'fan-unavailable', label: 'Bathroom fan unavailable (no rail)', props: { spec: R.fan({ u: true }) } },
    { id: 'bed-heating', label: 'Bed side heating', props: { spec: R.bedTile('Your Side', { action: 'heating', level: 3 }) } },
    { id: 'bed-off', label: 'Bed side off (keeps its level\'s glyph)', props: { spec: R.bedTile('Sam\'s Side', { action: 'off', level: -3 }) } },
  ];
  Mock.register('RoomCardTile', function (p) { return R.tile(p.spec); }, { source: 'apple/Sources/HassUI/Features/Rooms/RoomTiles.swift', props: '{spec}', variants: cardVariants, states: cardStates });
  var chipVariants = [
    { id: 'lights-on', label: 'Lights · On (amber)', props: Ch.lights('Lights', true) }, { id: 'lights-off', label: 'Lights · Off (neutral)', props: Ch.lights('Lights', false) },
    { id: 'climate', label: 'Climate (web gradient, 70°F)', props: Ch.climate('68–72°F', 70) }, { id: 'climate-hot', label: 'Climate (gradient, 84°F)', props: Ch.climate('82–86°F', 84) },
    { id: 'occ-det', label: 'Occupancy · Detected (filled)', props: Ch.occupancy(true) }, { id: 'occ-clear', label: 'Occupancy · Clear (outline)', props: Ch.occupancy(false) },
    { id: 'win-closed', label: 'Window · Closed', props: Ch.contact('Window', 'closed') }, { id: 'win-home', label: 'Window · Open, someone home (amber)', props: Ch.contact('Window', 'home') },
    { id: 'win-away', label: 'Window · Open, household away', props: Ch.contact('Window', 'away') }, { id: 'win-armed', label: 'Window · Open while armed (red, triangle)', props: Ch.contact('Window', 'armed') },
    { id: 'doors-closed', label: 'Doors (plural) · All Closed', props: Ch.contact('Doors', 'closed') }, { id: 'air', label: 'Air Quality (AQI colour, web teal)', props: Ch.air() },
  ];
  Mock.register('RoomChip', function (p) { var n = K.StatusChip(p); return p.inert ? R.inert(n) : n; }, { source: 'apple/Sources/HassUI/Features/Rooms/RoomTiles.swift', props: '{title, summary, symbol, family, isActive, tint, inert}', variants: chipVariants,
    states: [{ id: 'inert', label: 'Inert chip: no sheet (Back Deck Occupancy), not a button', props: Ch.occupancy(false, false, true) }, { id: 'unavailable-lights', label: 'Unavailable (Lights, neutral)', props: Ch.lights('Lights', false, null, true) },
      { id: 'unavailable-climate', label: 'Unavailable (Climate stays filled)', props: Ch.climate('', 70, true) }, { id: 'unavailable-window', label: 'Unavailable (Window neutral)', props: Ch.contact('Window', 'closed', true) }] });
  Mock.register('RoomSectionHeader', function (p) { return R.hdr(p.title, p.inSheet); }, { source: 'apple/Sources/HassUI/Features/Rooms/RoomSupport.swift', props: '{title, inSheet?}',
    variants: [{ id: 'page', label: 'On the wallpaper (Climate)', props: { title: 'Climate' } }, { id: 'sheet', label: 'In a sheet (inSheet: 8 pt above)', props: { title: 'Lights', inSheet: true } }],
    states: [{ id: 'long', label: 'Long section title', props: { title: 'Media Room Computers' } }] });
})();
