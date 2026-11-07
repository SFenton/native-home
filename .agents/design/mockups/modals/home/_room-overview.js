/* Room overview helpers: shared by the five overview sheets, the pushed room detail and the two tile component mockups (batch room-overview).
 * Loaded with <script src="../_room-overview-data.js"> then this file, after kit.js. Not part of the kit: "promote to kit" items are listed in each mockup's notes.
 *
 * It ports, as data and small functions, what HassCore does for these sheets so the mockups show what the code draws today:
 *   HassCore/Rooms/RoomOverview.swift  (titles, sections, card subtitles, detail sections, climate range text, sheet subtitle)
 *   HassCore/Rooms/RoomFormat.swift    (Detected / Clear, Open / Closed, "Door Open", "2 Windows Open", AQI summary)
 *   HassUI/Common/RoomOverview/*.swift (RoomOverviewSheet, Grid, Tile, AirQualityRoomTile, RoomGroupDetail(+Page), LightGroupTile, Style)
 *
 * RO.world(name)                      fixture house: 'mixed' | 'quiet' | 'unavailable' | 'empty' (store with nothing in it)
 * RO.sheet(ctx, {kind, W, room, ...}) the presented sheet (overview, or a room pushed inside it) over Home
 * RO.overviewStates / RO.overviewMotion / RO.transitions / RO.detailStates: the mechanics the mockup files share
 * RO.overviewTile, RO.airTile, RO.lightTile, RO.sensorTile: the tiles; RO.swatches: component-mockup surfaces
 * Fixture data only: room names and entity ids are the app's, values are invented. */
(function () {
  var h = Mock.h, K = Mock.components, D = window.RO_DATA, A = Mock.anim;
  var RO = window.RO = { data: D };

  /* ---- symbols the kit lacks (SymbolMap returns these SF names). Promote to kit: window.vertical.open|closed, figure.stand, desktopcomputer, stove, stairs, bathtub. */
  (function () {
    var S = Mock.symbols;
    function add(n, d) { if (!S[n]) S[n] = d; }
    add('window.vertical.closed', '<path d="M5.5 3.5h13v17h-13zM12 3.5v17M5.5 12h13"/>');
    add('window.vertical.open', '<path d="M5.5 3.5h6.5v17H5.5zM14.5 6l4.4 1.3v9.4L14.5 18z"/>');
    add('figure.stand', '<circle cx="12" cy="4.6" r="1.9"/><path d="M8 9.2h8M12 9.2v6.3M12 15.5l-2.6 5.9M12 15.5l2.6 5.9"/>');
    add('desktopcomputer', '<rect x="3" y="4.5" width="18" height="12" rx="2"/><path d="M9 20h6M12 16.5V20"/>');
    add('stove', '<rect x="4" y="3.5" width="16" height="17" rx="2"/><circle cx="8.6" cy="8" r="1.5"/><circle cx="15.4" cy="8" r="1.5"/><path d="M7 13.5h10M7 17h10"/>');
    add('stairs', '<path d="M4 20h4.5v-4.2H13V11.5h4.5V7.5H20"/>');
    add('bathtub', '<path d="M3.5 12h17v2.4a4 4 0 0 1-4 4h-9a4 4 0 0 1-4-4zM6 12V6.8a2.2 2.2 0 0 1 2.2-2.3h.3M7 18.5l-1 2M17 18.5l1 2"/>');
  })();

  var KINDS = ['lights', 'climate', 'occupancy', 'contacts', 'airQuality'];
  RO.kinds = {
    lights: { name: 'Lights', family: 'lights', chip: 'Lights', slug: 'lights' },
    climate: { name: 'Climate', family: 'climate', chip: 'Climate', slug: 'climate' },
    occupancy: { name: 'Occupancy', family: 'occupancy', chip: 'Occupancy', slug: 'occupancy' },
    contacts: { name: 'Contact Sensors', family: 'contact', chip: 'Contact Sensors', slug: 'contacts' },
    airQuality: { name: 'Air Quality', family: 'air', chip: 'Air Quality', slug: 'air-quality' },
  };
  var GROUPS = { lights: D.lights, climate: D.climate, occupancy: D.occupancy, contacts: D.contacts };
  function groupOf(kind, room) { return GROUPS[kind].filter(function (g) { return g[0] === room; })[0]; }
  RO.group = groupOf;

  /* ---- the fixture house -------------------------------------------------------------------------------------------------------------------------------- */
  function uniq(a) { var s = {}; return a.filter(function (x) { if (s[x]) return false; s[x] = 1; return true; }); }
  var LIGHT_IDS = uniq([].concat.apply([], D.lights.map(function (g) { return g[2].map(function (i) { return i[1]; }); })));
  var CONTACT_IDS = uniq([].concat.apply([], D.contacts.map(function (g) { return g[2].map(function (i) { return i[1]; }); })));
  RO.lightTotal = LIGHT_IDS.length;
  var BASE = { 'Living Room': 71, 'Guest Room': 69, 'Bedroom 1': 68, 'Gym': 70, 'Hallway': 69, 'Office': 72, 'Kitchen': 71, 'Dining Room': 70, 'Studio': 70, 'Media Room': 68, 'Downstairs Hallway': 68, 'Guest Bathroom': 70, 'Bathroom 1': 71, 'Entryway': 66 };
  var AIR = { 'Living Room': [12, 3.1, '#33cc66'], 'Guest Room': [18, 4.0, '#33cc66'], 'Office': [58, 16.2, '#ffd60a'], 'Bedroom 1': [9, 2.4, '#33cc66'], 'Studio': [74, 22.5, '#ff9f0a'], 'Media Room': [27, 7.2, '#33cc66'] };
  var VENTS = { 'cover.demo_living_room_1': 50, 'cover.demo_bedroom_1_1': 60, 'cover.demo_office_vent_1': 100, 'cover.demo_kitchen_vent_1': 30, 'cover.demo_media_room_vent_2': 75 };

  function fixed1(v) { return (Math.trunc(v * 10) / 10).toFixed(1); }
  /** A fixture house. Entities are {st, pct, rgb, dim, pos, unit}; RO.read returns null for an entity the store does not have. */
  RO.world = function (name) {
    var W = { name: name, e: {} }, E = W.e;
    if (name === 'empty') return W;
    var quiet = name === 'quiet', un = name === 'unavailable';
    // lights: the web's LIGHT_GROUPS, each light once
    LIGHT_IDS.forEach(function (id) { E[id] = { st: 'off', pct: 0, dim: !(id.indexOf('switch.') === 0 || id === 'light.demo_garage_camera_1') }; });
    var ON = quiet ? {} : { 'light.demo_living_room_light_4': 60, 'light.demo_living_room_light_2': 30, 'light.demo_kitchen_light_3': 70, 'light.demo_kitchen_light_2': 40, 'light.demo_hallway_light_3': 50,
      'light.demo_bedroom_1_light_2': 80, 'light.demo_light_6': 20, 'switch.demo_entryway_light_1': 1, 'light.demo_garage_camera_1': 1, 'light.demo_media_room_light_6': 40, 'light.demo_color_7': 80 };
    Object.keys(ON).forEach(function (id) { E[id].st = 'on'; E[id].pct = ON[id]; });
    E['light.demo_media_room_light_6'].rgb = [255, 170, 80]; E['light.demo_color_7'].rgb = [180, 90, 255];
    if (un) ['light.demo_light_7', 'light.demo_media_room_light_5', 'light.demo_garage_camera_1'].forEach(function (id) { E[id].st = 'unavailable'; E[id].pct = 0; });
    D.lights.forEach(function (g) {   // a group light is on while any member is, at the brightest member's level
      if (!g[1] || E[g[1]]) return;
      var on = g[2].filter(function (i) { return E[i[1]].st === 'on'; });
      E[g[1]] = { st: on.length ? 'on' : 'off', pct: on.reduce(function (m, i) { return Math.max(m, E[i[1]].pct); }, 0), dim: true };
    });
    // climate: sensors, range helpers, vents
    D.climate.forEach(function (g) {
      var vals = [];
      g[2].forEach(function (i, n) {
        if (i[1].indexOf('cover.') === 0) { var p = VENTS[i[1]]; E[i[1]] = p ? { st: 'open', pos: p } : { st: 'closed' }; }
        else { var v = BASE[g[0]] + ((n * 7) % 5 - 2) * 0.4 + 0.13; vals.push(v); E[i[1]] = { st: v.toFixed(2), unit: '°F' }; }
      });
      var lo = Math.min.apply(null, vals), hi = Math.max.apply(null, vals);
      E[g[1]] = { st: fixed1(lo) + ' - ' + fixed1(hi) + '°F' };
    });
    if (un) {
      E['input_text.demo_hallway_1'].st = 'unavailable';
      E['sensor.demo_front_door_temperature_1'].st = 'unavailable'; E['input_text.demo_front_door_door_1'].st = 'unavailable';
      E['sensor.demo_downstairs_hallway_temperature_1'].st = 'unavailable'; E['input_text.demo_downstairs_hallway_1'].st = 'unavailable';
      E['cover.demo_gym_vent_1'] = { st: 'unavailable' };
    }
    // occupancy and contacts
    var OCC = quiet ? [] : ['binary_sensor.demo_living_room_presence_4', 'binary_sensor.demo_living_room_presence_3', 'binary_sensor.demo_kitchen_presence_1', 'binary_sensor.demo_bedroom_1_presence_4'];
    D.occupancy.forEach(function (g) { g[2].forEach(function (i) { E[i[1]] = { st: OCC.indexOf(i[1]) >= 0 ? 'on' : 'off' }; }); });
    if (un) { E['binary_sensor.demo_gym_presence_1'].st = 'unavailable'; E['binary_sensor.demo_office_presence_2'].st = 'unavailable'; }
    var OPEN = quiet ? [] : ['binary_sensor.demo_office_contact_2', 'binary_sensor.demo_garage_contact_1', 'binary_sensor.demo_bedroom_1_contact_1'];
    CONTACT_IDS.forEach(function (id) { E[id] = { st: OPEN.indexOf(id) >= 0 ? 'on' : 'off' }; });
    if (un) E['binary_sensor.demo_dining_room_contact_1'].st = 'unavailable';
    // air quality
    D.air.forEach(function (r) {
      var a = AIR[r[0]];
      if (un && (r[0] === 'Guest Room' || r[0] === 'Media Room')) a = null;
      if (!a) return;
      E[r[1]] = { st: String(a[0]) }; E[r[2]] = { st: String(a[1]), unit: 'µg/m³' }; E['color:' + r[0]] = { st: a[2] };
    });
    return W;
  };
  RO.read = function (W, id) { return W.e[id] || null; };
  function rd(W, id) { return W.e[id] || null; }
  function st(W, id) { var e = rd(W, id); return e ? e.st : null; }
  function isUn(W, id) { var s = st(W, id); return s === null || s === 'unavailable' || s === 'unknown'; }

  /* ---- HassCore ports ----------------------------------------------------------------------------------------------------------------------------------- */
  function lightActiveCount(W, g) { return g[2].filter(function (i) { return st(W, i[1]) === 'on'; }).length; }
  function activeLightCount(W) { return LIGHT_IDS.filter(function (id) { return st(W, id) === 'on'; }).length; }
  function occupiedCount(W, g) { return g[2].filter(function (i) { return ['on', 'active', 'occupied'].indexOf(st(W, i[1])) >= 0; }).length; }
  function isOpen(W, id) { return ['on', 'open'].indexOf(st(W, id)) >= 0; }
  function openCount(W, g) { return g[2].filter(function (i) { return isOpen(W, i[1]); }).length; }
  function openContactCount(W) { return CONTACT_IDS.filter(function (id) { return isOpen(W, id); }).length; }
  function isWindowItem(i) { return (i[0] + ' ' + i[1]).toLowerCase().indexOf('window') >= 0; }
  function isWindowGroup(g) { return g[2].length > 0 && g[2].every(isWindowItem); }
  RO.openContactCount = openContactCount; RO.activeLightCount = activeLightCount;
  RO.occupiedRooms = function (W) { return D.occupancy.filter(function (g) { return occupiedCount(W, g) > 0; }).length; };

  function isActive(kind, g, W) {
    if (kind === 'lights') { var gs = g[1] ? st(W, g[1]) === 'on' : false; return gs || lightActiveCount(W, g) > 0; }
    if (kind === 'occupancy') return occupiedCount(W, g) > 0;
    if (kind === 'contacts') return openCount(W, g) > 0;
    return true;
  }
  RO.isActive = isActive;
  function isFilled(kind, active) { return (kind === 'lights' || kind === 'occupancy' || kind === 'contacts') ? active : false; }

  function normalizedRange(t) {
    if (t === null || t === undefined || t === '' || t === 'unavailable' || t === 'unknown') return null;
    return String(t).replace(/-?\d+(?:\.\d+)?/g, function (m) { return fixed1(parseFloat(m)); });
  }
  function climateSubtitle(W, g) {
    var r = normalizedRange(g[1] ? st(W, g[1]) : null); if (r) return r;
    var rs = g[2].map(function (i) { var e = rd(W, i[1]); return e && e.unit && !isNaN(parseFloat(e.st)) ? { v: parseFloat(e.st), u: e.unit } : null; }).filter(Boolean);
    if (!rs.length) return g[2].length + (g[2].length === 1 ? ' sensor' : ' sensors');
    var lo = Math.min.apply(null, rs.map(function (x) { return x.v; })), hi = Math.max.apply(null, rs.map(function (x) { return x.v; }));
    return Math.abs(lo - hi) < 0.05 ? fixed1(lo) + rs[0].u : fixed1(lo) + rs[0].u + ' - ' + fixed1(hi) + rs[0].u;
  }
  function contactSummary(W, g) {
    var open = { 0: 0, 1: 0 }, total = { 0: 0, 1: 0 };
    g[2].forEach(function (i) { var w = isWindowItem(i) ? 1 : 0; total[w] += (i[2] && i[2].cc) || 1; if (isOpen(W, i[1])) open[w] += 1; });
    function sum(w) {
      var noun = w ? 'Window' : 'Door', o = open[w], t = total[w];
      if (t === 1) return o === 1 ? noun + ' Open' : noun + ' Closed';
      if (o === 0) return 'All ' + noun + 's Closed';
      if (o === t) return 'All ' + noun + 's Open';
      return o + ' ' + noun + (o === 1 ? '' : 's') + ' Open';
    }
    var kinds = [1, 0].filter(function (w) { return total[w] > 0; });
    if (kinds.length === 1) return sum(kinds[0]);
    var parts = kinds.filter(function (w) { return open[w] > 0; }).map(sum);
    return parts.length ? parts.join(', ') : 'All Closed';
  }
  function lightSubtitle(W, g) {
    var n = lightActiveCount(W, g);
    if (n > 0) return g[2].length === 1 ? 'On' : n + ' On';
    var e = g[1] ? rd(W, g[1]) : null;
    if (!e) return 'Off';
    return e.st === 'unavailable' ? 'Unavailable' : (e.st === 'on' ? 'On' : 'Off');
  }
  function cardSubtitle(kind, g, W) {
    if (kind === 'lights') return lightSubtitle(W, g);
    if (kind === 'climate') return climateSubtitle(W, g);
    if (kind === 'occupancy') return occupiedCount(W, g) > 0 ? 'Occupied' : 'Not Occupied';
    if (kind === 'contacts') return contactSummary(W, g);
    return '';
  }
  RO.cardSubtitle = cardSubtitle;
  function airMetric(e) {
    if (!e) return 'Unavailable';
    var raw = String(e.st).trim();
    if (!raw || raw === 'unavailable' || raw === 'unknown') return 'Unavailable';
    var unit = e.unit || '', v = (!unit && /\.0$/.test(raw)) ? raw.slice(0, -2) : raw;
    return unit && v.indexOf(unit) < 0 ? v + ' ' + unit : v;
  }
  function airColor(W, r) { var c = rd(W, 'color:' + r[0]); return c ? c.st : '#009688'; }   // web teal while the helper is missing
  function sheetName(kind) { return RO.kinds[kind].name; }
  function sheetTitle(kind, W) { return kind === 'lights' ? 'Lights (' + (activeLightCount(W) === 0 ? 'All Off' : activeLightCount(W) + ' On') + ')' : sheetName(kind); }
  function sheetSubtitle(kind, W) {
    if (kind === 'lights') { var on = activeLightCount(W); return on === 0 ? 'All Off' : on + ' of ' + LIGHT_IDS.length + ' On'; }
    if (kind === 'occupancy') { var n = RO.occupiedRooms(W); return n === 0 ? 'All Clear' : n + (n === 1 ? ' Room' : ' Rooms') + ' Occupied'; }
    if (kind === 'contacts') { var o = openContactCount(W); return o > 0 ? o + ' Open' : 'All Closed'; }
    return null;
  }
  RO.sheetTitle = sheetTitle; RO.sheetName = sheetName; RO.sheetSubtitle = sheetSubtitle;
  function sections(kind, W, redact) {
    var all = GROUPS[kind];
    if (kind === 'occupancy' && redact) return [{ title: 'Rooms', groups: all }];
    var t = kind === 'lights' ? ['Lights On', 'Lights Off'] : (kind === 'occupancy' ? ['Occupied', 'Clear'] : null);
    if (!t) return [{ title: 'Rooms', groups: all }];
    return [{ title: t[0], groups: all.filter(function (g) { return isActive(kind, g, W); }) }, { title: t[1], groups: all.filter(function (g) { return !isActive(kind, g, W); }) }].filter(function (s) { return s.groups.length; });
  }
  function detailTitle(kind, g) {
    if (kind === 'lights') return g[0] + (g[2].length === 1 ? ' Light' : ' Lights');
    if (kind === 'climate') return g[0] + ' Climate';
    if (kind === 'occupancy') return g[0] + ' Occupancy';
    return g[0] + ' Contact Sensors';
  }
  RO.detailTitle = detailTitle;
  function detailSubtitle(kind, g, W, redact) {
    if (kind === 'occupancy') { if (redact) return 'Hidden'; var c = occupiedCount(W, g); return c + ' sensor' + (c === 1 ? '' : 's') + ' occupied'; }
    return cardSubtitle(kind, g, W);
  }
  function groupLightId(g) { return g[2].length > 1 && g[1] && g[1].indexOf('light.') === 0 ? g[1] : null; }
  function detailSections(kind, g, showHeadings) {
    var n = g[2].length;
    if (kind === 'lights') return [{ title: n === 1 ? 'Light' : 'Lights', items: g[2] }];
    if (kind === 'climate') {
      var sensors = g[2].filter(function (i) { return i[1].indexOf('cover.') !== 0; }), vents = g[2].filter(function (i) { return i[1].indexOf('cover.') === 0; });
      var vt = vents.length === 1 && vents[0][0] !== 'Vents' ? 'Vent' : 'Vents';
      return [{ title: sensors.length === 1 ? 'Temperature Sensor' : 'Temperature Sensors', items: sensors }, { title: vt, items: vents }].filter(function (s) { return s.items.length; });
    }
    if (kind === 'occupancy') return [{ title: showHeadings !== false ? (n === 1 ? 'Occupancy Sensor' : 'Occupancy Sensors') : null, items: g[2] }];
    return [{ title: showHeadings !== false ? (n === 1 ? 'Contact Sensor' : 'Contact Sensors') : null, items: g[2] }];
  }

  /* ---- tiles -------------------------------------------------------------------------------------------------------------------------------------------- */
  var ROOM_SYM = { 'Living Room': 'sofa', 'Guest Room': 'bed.double', 'Gym': 'dumbbell', 'Bedroom 1': 'bed.double', 'Office': 'desktopcomputer', 'Hallway': 'door.left.hand.open', 'Kitchen': 'stove', 'Studio': 'music.note',
    'Garage': 'door.garage.closed', 'Media Room': 'film', 'Back Deck': 'flame', 'Downstairs Hallway': 'stairs', 'Guest Bathroom': 'shower', 'Bathroom 1': 'bathtub', 'Dining Room': 'fork.knife', 'Entryway': 'door.left.hand.closed' };
  function contactSymbol(win, open) { return win ? (open ? 'window.vertical.open' : 'window.vertical.closed') : (open ? 'door.left.hand.open' : 'door.left.hand.closed'); }
  function overviewSymbol(kind, g, active) {
    if (kind === 'lights') return g[2].length > 1 ? 'lightbulb.2' : 'lightbulb';
    if (kind === 'climate') return ROOM_SYM[g[0]] || 'thermometer.medium';
    if (kind === 'occupancy') return active ? 'figure.walk.motion' : 'figure.stand';
    if (kind === 'contacts') return contactSymbol(isWindowGroup(g), active);
    return 'aqi.medium';
  }
  function tag(tile, id, hint) { tile.dataset.id = id; if (hint) tile.setAttribute('aria-description', hint); return tile; }

  /** RoomOverviewTile: a room card; direction G faces (lit lights, filled occupied or open, dark otherwise); a chevron, because it pushes. */
  RO.overviewTile = function (kind, g, W, o) {
    var active = isActive(kind, g, W), redact = o && o.redact && kind === 'occupancy';
    /* Rollout L (owner 2026-10-27, item 12): a Lights room card carries a room power disc left of the chevron. On means any light in the room is on; a tap turns the whole room off when it is, else on
       (one turn_on / turn_off on the room's group light). The card is two tracks wide, so a phone shows one per row. */
    var disc = kind === 'lights' ? [{ id: 'power', symbol: 'power', label: (active ? 'Turn Off ' : 'Turn On ') + g[0] + ' lights', on: active, dim: false }] : null;
    var t = Mock.tile({ title: g[0], subtitle: redact ? 'Hidden' : cardSubtitle(kind, g, W), symbol: overviewSymbol(kind, g, active && !redact), family: RO.kinds[kind].family, isActive: isFilled(kind, active && !redact), kind: 'navigate',
      behavior: disc ? 'navigate' : undefined, actions: disc });
    if (disc) t.dataset.wide = '1';
    t.dataset.room = g[0];
    return tag(t, 'overview.' + (kind === 'airQuality' ? 'airQuality' : kind) + '.room.' + g[0], 'Opens ' + detailTitle(kind, g));
  };
  /** AirQualityRoomTile: read-only; the glyph and rim take the room's AQI colour. */
  RO.airTile = function (r, W) {
    var t = Mock.tile({ title: r[0], subtitle: airMetric(rd(W, r[1])) + ' • ' + airMetric(rd(W, r[2])), symbol: 'aqi.medium', tint: airColor(W, r), isActive: true, kind: 'state' });
    t.dataset.room = r[0];
    return tag(t, 'overview.airQuality.room.' + r[0]);
  };
  function rgbCss(rgb) { return 'rgb(' + rgb.join(',') + ')'; }
  /** LightGroupTile: a brightness tile when the light dims, else a power tile; the title personalises nightstands. */
  RO.lightTile = function (title, id, W, o) {
    o = o || {};
    var e = rd(W, id), un = !e || e.st === 'unavailable' || e.st === 'unknown', on = e && e.st === 'on', t;
    if (e && e.dim) {
      var pct = o.dragging != null ? o.dragging : (on ? e.pct : 0);
      t = K.BrightnessTile({ title: title, percent: un ? 0 : pct, unavailable: un, tint: e.rgb && !un ? rgbCss(e.rgb) : undefined, dragging: o.dragging != null });
      var s = t.querySelector('.st'); if (s) s.textContent = un ? 'Unavailable' : (pct > 0 ? pct + '%' : 'Off');   // BrightnessTile.status: "Off", "45%", "Unavailable"
      t.setAttribute('aria-valuetext', s ? s.textContent : '');
      var bub = t.querySelector('.ui-bubble'); if (bub) { bub.style.top = '-40px'; bub.style.width = '60px'; bub.style.height = '32px'; bub.style.lineHeight = '24px'; bub.style.textAlign = 'center'; bub.style.left = 'calc(' + pct + '% - 30px)'; }   // the app centres a 60 x 32 pt bubble 24 pt above the tile
    } else {
      /* Rollout L: a light or switch that does not dim is an action tile (text . power disc, no leading glyph); unavailable dims the disc in place. */
      t = Mock.tile({ title: title, subtitle: !e ? undefined : (un ? 'Unavailable' : (on ? 'On' : 'Off')), symbol: 'lightbulb', family: 'lights', isActive: !!on, isUnavailable: un, kind: 'toggle', behavior: 'perform',
        actions: [{ id: 'power', symbol: 'power', label: (on ? 'Turn Off ' : 'Turn On ') + title, on: !!on, dim: un }] });
    }
    t.dataset.light = id;
    return tag(t, o.group ? 'room.lightGroup.' + id : 'room.light.' + id);
  };
  /** A read-only sensor tile of RoomGroupDetail: filled with its family while active, else dark with the family glyph. */
  RO.sensorTile = function (kind, item, W, o) {
    o = o || {};
    var id = item[1], e = rd(W, id), unv = isUn(W, id), active = false, sub, sym, fam;
    if (kind === 'climate') {
      var vent = id.indexOf('cover.') === 0; fam = vent ? 'vents' : 'climate'; sym = vent ? 'fan' : 'thermometer.medium';
      if (vent) { active = e && (e.st === 'open' || e.st === 'opening'); sub = !e ? 'Unavailable' : (e.st === 'unavailable' ? 'Unavailable' : (active && e.pos != null ? 'Open · ' + e.pos + '%' : cap(e.st))); }
      else sub = !e ? 'Unavailable' : (e.st === 'unavailable' ? 'Unavailable' : fixed1(parseFloat(e.st)) + (e.unit || ''));
    } else if (kind === 'occupancy') {
      fam = 'occupancy'; active = !!e && ['on', 'active', 'occupied'].indexOf(e.st) >= 0; sym = active ? 'figure.walk.motion' : 'figure.stand';
      sub = !e || e.st === 'unavailable' ? 'Unavailable' : (active ? 'Detected' : 'Clear');
    } else {
      fam = 'contact'; active = isOpen(W, id); sym = contactSymbol(isWindowItem(item), active);
      sub = !e || e.st === 'unavailable' ? 'Unavailable' : (active ? 'Open' : 'Closed');
    }
    var redact = o.redact && kind === 'occupancy';
    var t = Mock.tile({ title: item[0], subtitle: redact ? 'Hidden' : sub, symbol: sym, family: fam, isActive: active && !redact, isUnavailable: unv, kind: 'state' });
    return tag(t, 'room.entity.' + id);
  };
  function cap(s) { return String(s).replace(/\b\w/g, function (c) { return c.toUpperCase(); }); }

  /* ---- grids: equal tile heights across every row of a grid (DynamicGridLayout equalRowHeights + .equalHeightTiles) ------------------------------------- */
  function equalize(g) {
    if (!window.ResizeObserver) return g;
    new ResizeObserver(function () {
      if (!g.clientWidth) return;
      var tiles = [].slice.call(g.querySelectorAll('.ui-tile')), m = 0;
      tiles.forEach(function (t) { t.style.minHeight = ''; });
      tiles.forEach(function (t) { m = Math.max(m, t.offsetHeight); });
      tiles.forEach(function (t) { t.style.minHeight = m + 'px'; });
    }).observe(g);
    return g;
  }
  function header(title) { var n = K.PageSectionHeader({ title: title }); n.classList.add('gridheader'); n.dataset.id = 'section.' + title; return n; }
  /** DynamicGridLayout: the kit's TileGrid with the track minimum capped at the container (at AX5 the scaled 140 pt exceeds a phone sheet and the kit's track overflows: promote to kit). */
  function grid(items, max) {
    var g = K.TileGrid({ items: items, min: 140, max: max, equal: false });
    g.style.gridTemplateColumns = 'repeat(auto-fill, minmax(min(100%, max(calc(var(--min, 150px) * var(--sc)), calc((100% - (var(--max, 6) - 1) * var(--gap, 12px)) / var(--max, 6)))), 1fr))';
    return equalize(g);
  }

  /** RoomOverviewGrid: sections headed inside one grid so every card shares one height. */
  RO.overviewGrid = function (kind, W, o) {
    o = o || {}; var items = [];
    if (kind === 'airQuality') { items.push(header('Rooms')); D.air.forEach(function (r) { items.push(RO.airTile(r, W)); }); }
    else sections(kind, W, o.redact).forEach(function (s) { items.push(header(s.title)); s.groups.forEach(function (g) { items.push(RO.overviewTile(kind, g, W, o)); }); });
    return grid(items, 6);
  };
  /** RoomGroupDetail: the tiles of one pushed room. viewer: the signed-in household member ('alex'), for "Your Nightstand". */
  RO.detailBody = function (kind, g, W, o) {
    o = o || {};
    var secs = detailSections(kind, g, o.showHeadings), body = h('div', { style: { display: 'flex', flexDirection: 'column', gap: '12px' } });
    var items = [];
    function ttl(i) { return i[2] && i[2].res ? (i[2].res === (o.viewer || 'alex') ? 'Your Nightstand' : i[0]) : i[0]; }
    if (kind === 'lights') {
      body.appendChild(K.PageSectionHeader({ title: secs[0].title }));
      var gl = groupLightId(g);
      if (gl) body.appendChild(RO.lightTile(detailTitle(kind, g), gl, W, { group: true, dragging: o.dragGroup }));
      secs[0].items.forEach(function (i) { items.push(RO.lightTile(ttl(i), i[1], W, { dragging: o.drag && o.drag === i[1] ? 40 : undefined })); });
    } else secs.forEach(function (s) { if (s.title) items.push(header(s.title)); s.items.forEach(function (i) { items.push(RO.sensorTile(kind, i, W, o)); }); });
    body.appendChild(grid(items, 4));
    return body;
  };
  /** The sheet's scrolling content for the overview. */
  function overviewContent(kind, W, o) {
    return h('div', { style: { maxWidth: '960px', margin: '0 auto', paddingTop: '8px' } }, RO.overviewGrid(kind, W, o));
  }
  /** RoomGroupDetailPage content: the live subtitle first, then the tiles. */
  function detailContent(kind, g, W, o) {
    o = o || {};
    return h('div', { style: { maxWidth: '960px', margin: '0 auto', display: 'flex', flexDirection: 'column', gap: '16px', paddingTop: '4px' } },
      h('p', { dataset: { id: 'overview.detail.subtitle' }, style: { margin: 0, font: '400 var(--fs-sub)/1.3 var(--font)', color: 'var(--ink-sheet-2)' } }, detailSubtitle(kind, g, W, o.redact)), RO.detailBody(kind, g, W, o));
  }

  /* ---- the page behind the sheet ----------------------------------------------------------------------------------------------------------------------- */
  RO.presenter = function (ctx, kind, W, connection) {
    var open = openContactCount(W), lights = activeLightCount(W);
    var chips = Mock.chips.home({ lights: lights, security: 'armed_home', climate: ['68–72°F', 70], occupied: RO.occupiedRooms(W) > 0, contacts: open ? ['home', open] : ['closed', 0], aqi: ['AQI 9–74 · PM2.5 2–23'] });
    return Mock.page(ctx, { title: 'Home', section: 'home', badge: 3, choresBadge: 2, connection: connection || 'live',
      body: [K.ChipRail({ chips: chips }), K.WeatherCard({ condition: 'Partly Cloudy', temp: 48, hi: 58, lo: 38 })] });
  };

  /** The Security page behind the Contact Sensors overview (SecurityPage: the Security and Contact Sensors chips, the alarm card, the Doors tiles). */
  RO.presenterSecurity = function (ctx, W, connection) {
    var open = openContactCount(W);
    var chips = [Mock.chips.security('armed_home'), open ? Mock.chips.contacts('home', open) : Mock.chips.contacts('closed', 0)];
    var doors = K.TileGrid({ items: [{ title: 'Front Door', subtitle: 'Locked', symbol: 'lock', family: 'contact', isActive: false }, { title: 'Left Garage Door', subtitle: 'Closed', symbol: 'door.garage.closed', family: 'contact', isActive: false },
      { title: 'Right Garage Door', subtitle: 'Open', symbol: 'door.garage.open', family: 'contact', isActive: true }], min: 140, max: 4 });
    return Mock.page(ctx, { title: 'Security', section: 'security', badge: 3, choresBadge: 2, connection: connection || 'live',
      body: [K.ChipRail({ chips: chips }), K.AlarmPanel({ state: 'armed_home' }), K.PageSectionHeader({ title: 'Doors' }), doors] });
  };

  /* ---- the sheet ---------------------------------------------------------------------------------------------------------------------------------------- */
  /** RoomOverviewSheet = NavigationStack { ScrollView { RoomOverviewGrid } } with .hassSheet(.page, height: .full); o.room pushes that room's detail.
   *  o: {kind, W, room?, connection?, noPresenter?, ios26 (default true), redact?, detent?, dragGroup?, drag?, viewer?, alert?} */
  RO.sheet = function (ctx, o) {
    var kind = o.kind, W = o.W || RO.world('mixed'), ios26 = o.ios26 !== false, g = o.room ? groupOf(kind, o.room) : null, title, sub, content;
    if (g) { title = detailTitle(kind, g); sub = undefined; content = detailContent(kind, g, W, o); }
    else { title = ios26 ? sheetName(kind) : sheetTitle(kind, W); sub = ios26 ? sheetSubtitle(kind, W) : undefined; content = overviewContent(kind, W, o); }
    return Mock.sheet(ctx, { title: title, subtitle: sub || undefined, detent: o.detent || 'large', size: 'page', leading: g ? 'back' : 'none', trailing: 'close', content: content,
      presenter: o.noPresenter ? null : (o.from === 'security' ? RO.presenterSecurity(ctx, W, o.connection) : RO.presenter(ctx, kind, W, o.connection)) });
  };

  /* ---- shared motion mechanics ------------------------------------------------------------------------------------------------------------------------- */
  /** Flip a tile between its lit/filled and dark faces: the registered colour slots cross-fade for `state` (0.6 s, 0.2 s reduced). */
  RO.flipTile = function (tile, on, o) {
    o = o || {};
    var face = tile.dataset.face, fam = tile.dataset.family, glyph = tile.querySelector('.glyph');
    var onFace = fam === 'lights' ? 'lit' : 'on';
    ['lit', 'on', 'off'].forEach(function (c) { tile.classList.remove(c); });
    tile.classList.add(on ? onFace : 'off'); tile.dataset.face = on ? onFace : 'off';
    var band = tile.querySelector('.band');
    if (fam === 'lights') {
      if (on && !band) { band = h('span.band', { style: { width: (o.pct == null ? 100 : o.pct) + '%' }, 'aria-hidden': 'true' }); tile.insertBefore(band, tile.firstChild); }
      else if (on && band && o.pct != null) band.style.width = o.pct + '%';
      else if (!on && band) band.remove();
    }
    if (o.symbol && glyph) glyph.innerHTML = Mock.icon(o.symbol, { fill: on });
    else if (glyph) glyph.innerHTML = Mock.icon(o.symbolName || glyph.dataset.sym || 'lightbulb', { fill: on });
    if (o.subtitle != null) { var s = tile.querySelector('.st'); if (s) s.textContent = o.subtitle; var ti = tile.querySelector('.ti'); tile.setAttribute('aria-label', (ti ? ti.textContent : '') + ', ' + o.subtitle); }
    if (tile.hasAttribute('aria-pressed')) tile.setAttribute('aria-pressed', on ? 'true' : 'false');
    return Mock.sleep(A.ms.state() + 40);
  };
  /** Push a detail page over the sheet's overview (system push; plain, never a zoom inside a sheet: owner 2026-10-22, motion.md 4.3), hold, then pop it. */
  RO.pushDemo = function (stage, kind, room, W) {
    var ctx = Mock.current, sheet = stage.querySelector('.ui-sheet'), old = sheet && sheet.querySelector('.ui-modal'); if (!old) return Promise.resolve();
    var g = groupOf(kind, room);
    var page = K.HassModal({ title: detailTitle(kind, g), leading: 'back', trailing: 'close', content: detailContent(kind, g, W, {}) });
    page.style.cssText += ';position:absolute;left:0;right:0;bottom:0;top:' + old.offsetTop + 'px;background:var(--sheet-ground);z-index:6';
    sheet.appendChild(page);
    return A.push(old, page).then(function () { return Mock.sleep(900); }).then(function () { return A.push(page, old, { back: true }); }).then(function () { page.remove(); A.reset(sheet); });
  };
  /** Back: the page pops, the overview slides back in from 30% left. */
  RO.popDemo = function (stage, kind, W) {
    var sheet = stage.querySelector('.ui-sheet'), cur = sheet && sheet.querySelector('.ui-modal'); if (!cur) return Promise.resolve();
    var back = K.HassModal({ title: sheetName(kind), subtitle: sheetSubtitle(kind, W) || undefined, leading: 'none', trailing: 'close', content: overviewContent(kind, W) });
    back.style.cssText += ';position:absolute;left:0;right:0;bottom:0;top:' + cur.offsetTop + 'px;background:var(--sheet-ground);z-index:5';
    sheet.insertBefore(back, cur);
    return Mock.sleep(500).then(function () { return A.push(cur, back, { back: true }); }).then(function () { return Mock.sleep(600); });
  };
  RO.dismissDemo = function (stage) { var host = stage.querySelector('.ui-host'); return A.sheet(host, 'out').then(function () { return Mock.sleep(500); }); };
  /** Drag a brightness tile: it lifts 3%, a "30%" bubble follows the band's edge, the band follows the finger on `quick`, a haptic ticks every 10%. Reduce Motion: shadow only. */
  RO.dragDemo = function (tile, from, to) {
    var rm = Mock.settings.reduceMotion, band = tile.querySelector('.band'), s = tile.querySelector('.st');
    var bubble = h('span', { 'aria-hidden': 'true', style: { position: 'absolute', top: '-40px', zIndex: 6, background: 'var(--sheet-cell-dark, #2C2C2E)', color: '#fff', font: '600 15px var(--font)', width: '60px', height: '32px', lineHeight: '32px', textAlign: 'center', borderRadius: '99px', boxShadow: '0 2px 6px rgba(0,0,0,.3)', fontVariantNumeric: 'tabular-nums', pointerEvents: 'none' } });
    function place(p) { var w = tile.clientWidth; bubble.style.left = Math.min(w - 30, Math.max(30, w * p / 100)) - 30 + 'px'; bubble.textContent = Math.round(p) + '%'; if (band) band.style.width = p + '%'; if (s) s.textContent = Math.round(p) + '%'; }
    tile.style.overflow = 'visible'; tile.style.zIndex = 5; tile.appendChild(bubble); place(from);
    tile.animate([{ transform: 'none', boxShadow: '0 0 0 rgba(0,0,0,0)' }, { transform: rm ? 'none' : 'scale(1.03)', boxShadow: '0 6px 12px rgba(0,0,0,.35)' }], { duration: A.ms.quick(), fill: 'forwards', easing: A.easing.quick });
    bubble.animate([{ opacity: 0 }, { opacity: 1 }], { duration: A.ms.quick(), fill: 'both' });
    return Mock.sleep(300).then(function () {
      return new Promise(function (res) {
        var t0 = performance.now(), dur = 1300;   // a timer, not requestAnimationFrame: a background tab never fires rAF and Play would hang
        var iv = setInterval(function () { var k = Math.min(1, (performance.now() - t0) / dur), e = k < .5 ? 2 * k * k : 1 - Math.pow(-2 * k + 2, 2) / 2; place(from + (to - from) * e); if (k >= 1) { clearInterval(iv); res(); } }, 16);
      });
    }).then(function () { return Mock.sleep(250); }).then(function () {
      return Promise.all([bubble.animate([{ opacity: 1 }, { opacity: 0 }], { duration: A.ms.quick(), fill: 'forwards' }).finished, tile.animate([{ transform: rm ? 'none' : 'scale(1.03)', boxShadow: '0 6px 12px rgba(0,0,0,.35)' }, { transform: 'none', boxShadow: '0 0 0 rgba(0,0,0,0)' }], { duration: A.ms.quick(), fill: 'forwards', easing: A.easing.quick }).finished]);
    }).then(function () { return Mock.sleep(300); }).then(function () { bubble.remove(); });
  };

  /** Motion list shared by every overview sheet. */
  RO.overviewMotion = function (kind) {
    var W = RO.world('mixed'), out = [];
    var src = 'HassUI/Common/RoomOverview/RoomOverviewTile.swift via GlassTileFace .stateColorTransition("GlassTile"); motion.md section 6, motion-components.md';
    if (kind === 'lights') out.push({ id: 'room-lights-on', what: 'A room\'s lights come on (or go off): the card turns into the lit tile and back', token: 'state 0.6 s ease-in-out, colour only (0.2 s reduced)', state: 'default', source: src,
      reduce: 'still cross-fades, at 0.2 s (colour is not motion)', note: 'Rows never re-sort live: Gym stays under Lights Off until the sheet is reopened (motion.md 6 "live updates never move layout"; the sections follow the state at the time the grid is built).',
      play: function (stage) { var t = stage.querySelector('[data-room="Gym"]'); return RO.flipTile(t, true, { symbolName: 'lightbulb', subtitle: 'On' }).then(function () { return Mock.sleep(500); }).then(function () { return RO.flipTile(t, false, { symbolName: 'lightbulb', subtitle: 'Off' }); }); } });
    if (kind === 'occupancy') out.push({ id: 'room-occupied', what: 'Someone walks into a clear room: the card fills green, the glyph swaps and the state reads Occupied', token: 'state 0.6 s ease-in-out, colour only (0.2 s reduced); glyph swaps with .symbolEffect(.replace), not under Reduce Motion', state: 'default', source: src,
      reduce: 'colour still cross-fades at 0.2 s; the glyph swaps without the replace effect',
      play: function (stage) { var t = stage.querySelector('[data-room="Gym"]'); return RO.flipTile(t, true, { symbol: 'figure.walk.motion', subtitle: 'Occupied' }).then(function () { return Mock.sleep(500); }).then(function () { return RO.flipTile(t, false, { symbol: 'figure.stand', subtitle: 'Not Occupied' }); }); } });
    if (kind === 'contacts') out.push({ id: 'room-door-opens', what: 'A door opens: the card fills soft green, the door glyph opens and the state reads Door Open', token: 'state 0.6 s ease-in-out, colour only (0.2 s reduced); glyph swaps with .symbolEffect(.replace), not under Reduce Motion', state: 'default', source: src,
      reduce: 'colour still cross-fades at 0.2 s; the glyph swaps without the replace effect',
      play: function (stage) { var t = stage.querySelector('[data-room="Dining Room"]'); return RO.flipTile(t, true, { symbol: 'door.left.hand.open', subtitle: 'Door Open' }).then(function () { return Mock.sleep(500); }).then(function () { return RO.flipTile(t, false, { symbol: 'door.left.hand.closed', subtitle: 'Door Closed' }); }); } });
    if (kind === 'airQuality') out.push({ id: 'aqi-band', what: 'A room\'s air changes band (green to yellow): the glyph and rim cross-fade to the new AQI colour; the card never fills', token: 'state 0.6 s ease-in-out, colour only (0.2 s reduced)', state: 'default', source: 'AirQualityRoomTile via GlassTileFace; motion.md section 6; motion-components.md',
      reduce: 'still cross-fades, at 0.2 s',
      play: function (stage) {
        var t = stage.querySelector('[data-room="Living Room"]'), from = '#33cc66', to = '#ffd60a', ms = A.ms.state();
        function rim(c, o) { return 'inset 0 0 0 1px color-mix(in srgb, ' + c + ' ' + (o || 50) + '%, transparent)'; }
        t.style.setProperty('--glyph', to); t.style.setProperty('--glyph-light', to); t.querySelector('.st').textContent = '66 • 18.4 µg/m³';
        return t.animate([{ boxShadow: rim(from) }, { boxShadow: rim(to) }], { duration: ms, easing: A.easing.state, fill: 'both' }).finished.then(function () { return Mock.sleep(500); }).then(function () {
          t.style.setProperty('--glyph', from); t.style.setProperty('--glyph-light', from); t.querySelector('.st').textContent = '12 • 3.1 µg/m³';
          return t.animate([{ boxShadow: rim(to) }, { boxShadow: rim(from) }], { duration: ms, easing: A.easing.state, fill: 'both' }).finished; });
      } });
    return out;
  };

  /** Transitions shared by the overview sheets. */
  RO.transitions = function (kind, room) {
    var W = RO.world('mixed'), T = [], name = sheetName(kind);
    T.push({ from: 'Home', to: name + ' sheet', kind: 'sheet', state: 'closed', note: 'The ' + RO.kinds[kind].chip + ' chip presents the sheet at its full height (hassSheet .full: it pushes pages, so its height must not change). The system slides it up; Home scales back and dims. Content is present on arrival: no tiles rising inside the sheet (motion.md 4.4).',
      play: function (stage) { var ctx = Mock.current; return Mock.presentDemo(stage, { title: sheetName(kind), subtitle: sheetSubtitle(kind, W) || undefined, detent: 'large', size: 'page', trailing: 'close', content: overviewContent(kind, W) }, { hold: 1200 }); } });
    if (room) {
      T.push({ from: name + ' overview', to: room + ' room', kind: 'push', state: 'default', note: 'A plain system push inside the sheet\'s own NavigationStack: the page slides in from the trailing edge, the grid shifts left and dims, Back appears. No zoom: a zoom inside a sheet hides the sheet\'s content while the backdrop stays blurred (owner 2026-10-22, motion.md 4.3). The destination renders its first frame with live data.',
        play: function (stage) { return RO.pushDemo(stage, kind, room, W); } });
      T.push({ from: room + ' room', to: name + ' overview', kind: 'push', state: 'room', note: 'Back (the glass circle, or an edge swipe, which is interactive and system-owned) pops the page; the grid returns exactly as it was, scroll position kept. Close from the pushed page dismisses the whole sheet.',
        play: function (stage) { return RO.popDemo(stage, kind, W); } });
    }
    T.push({ from: name + ' sheet', to: 'Home', kind: 'sheet', state: 'default', note: 'Close (circle x), or swipe down (interactive, system-owned). The sheet slides away, Home returns to full size. Closing keeps no state: the next open starts at the overview.', play: RO.dismissDemo });
    return T;
  };

  /* ---- states shared by the overview sheets ------------------------------------------------------------------------------------------------------------ */
  RO.overviewStates = function (kind, o) {
    o = o || {}; var name = sheetName(kind), room = o.room;
    function S(w, x) { return function (ctx) { return RO.sheet(ctx, Object.assign({ kind: kind, W: RO.world(w) }, x)); }; }
    var st = {};
    st['default'] = { title: name + ' overview, large (the one detent)', note: 'hassSheet(.page, height: .full): opens at large and never changes height; a page sheet (704 pt) on iPad and the unfolded Duo', render: S('mixed') };
    if (kind === 'lights' || kind === 'occupancy' || kind === 'contacts') st.quiet = { title: kind === 'lights' ? 'All lights off' : (kind === 'occupancy' ? 'All clear' : 'All closed'), note: kind === 'contacts' ? 'no filled card; every room reads closed' : 'the active section is dropped; the one section left keeps its heading', render: S('quiet') };
    st.loading = { title: 'Store empty (first sign-in, before any state)', note: 'there is no spinner, pulse or skeleton: the sheet reads EntityStore, so a missing entity reads as off, clear, closed or unavailable', render: S('empty') };
    st.error = { title: 'Entities unavailable', note: kind === 'airQuality' ? 'a room whose sensors are unavailable reads "Unavailable • Unavailable" on the teal fallback; there is no dimmed face' : 'the overview cards carry no unavailable face (only the pushed tiles dim); unavailable members read as off, clear, closed or fall back to their sensors', render: S('unavailable') };
    st.offline = { title: 'Over an offline Home', note: 'the sheet has no offline UI of its own: it keeps the last known state; the page behind carries the offline chip', render: S('mixed', { connection: 'offline' }) };
    st.reconnecting = { title: 'Over a reconnecting Home', note: 'the header arc sits on the page behind; the sheet is unchanged', render: S('mixed', { connection: 'reconnecting' }) };
    st['long-text'] = { title: 'xxxLarge text: names wrap, every card takes the tallest height', override: { ts: 'xxxl' }, render: S('mixed') };
    st.ax5 = { title: 'Accessibility 5 text size', override: { ts: 'ax5' }, note: 'one column of stacked tiles (glyph above, name and state below); the grid scrolls', render: S('mixed') };
    if (kind === 'lights') st['pre-ios26'] = { title: 'Before iOS 26: the title keeps the count', note: 'no navigation subtitle exists: "Lights (' + activeLightCount(RO.world('mixed')) + ' On)", centred, no second line (SheetSubtitle.isShown is false)', render: S('mixed', { ios26: false }) };
    if (room) st.room = { title: room + ' pushed inside the sheet', note: 'a plain push with Back; Close stays in the bar at every depth', render: S('mixed', { room: room }) };
    st.closed = { title: 'Before presenting / after dismissing', note: 'the Home page the sheet scales back', render: function (ctx) { return RO.presenter(ctx, kind, RO.world('mixed')); } };
    return st;
  };

  /* ---- component mockup surfaces ----------------------------------------------------------------------------------------------------------------------- */
  /** Swatches of tiles on the sheet surface (and the page surface when asked): list items are {label, build(ctx) -> Node, note?, wide?}. */
  RO.swatches = function (ctx, list, o) {
    o = o || {};
    var out = h('div', { style: { display: 'flex', flexDirection: 'column', gap: '18px' } });
    (o.surfaces || ['sheet']).forEach(function (surface) {
      var wrap = h('div.k-swatch-grid');
      list.forEach(function (v) {
        var cls = 'div.k-swatch.' + (surface === 'page' ? 'page.g-dark' : 'sheet.in-sheet.' + (ctx.appearance === 'dark' ? 'g-dark' : 'g-light'));
        wrap.appendChild(h(cls, { style: { flex: v.wide ? '1 1 100%' : '1 1 ' + (v.w || 260) + 'px', maxWidth: '100%', minWidth: 0 } }, h('div.k-cap', surface + ' · ' + v.label), h('div.in', v.build(ctx)), v.note ? h('div', { style: { font: '12px var(--font)', opacity: .7, marginTop: '8px' } }, v.note) : null));
      });
      out.appendChild(wrap);
    });
    return out;
  };
})();
