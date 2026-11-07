/* Helpers shared by the security-climate batch (Security, Climate, their sheets, alerts and components). Loaded by a <script src> after kit.js.
 *
 * Everything here is LOCAL to this batch. Nothing is added to Mock.COMPONENTS; the pieces the kit does not have are listed as "promote to kit" in each mockup's notes:
 *   - dial()            the real ThermostatDial (single target, off, unavailable, dragging, caption glyph, readout fitting). The kit's ThermostatDial draws the
 *                       range look only (apple/Sources/HassDesign/ThermostatDial/ThermostatDial.swift is the truth here).
 *   - notice(), hub()   ClimateNotice and ThermostatHubPill (apple/Sources/HassUI/Features/Climate/ClimateNotice.swift, ClimateHubPill.swift).
 *   - doorTile()        LockTile and GarageDoorTile (apple/Sources/HassUI/Features/Security/SecurityDoorTile.swift, SecurityTiles.swift) over the kit's GlassTile.
 *   - the page, sheet and detail builders for Security and Climate (securityBody/securityPage, climatePage, climateSheet, details).
 *   - missing SF Symbol look-alikes are added to Mock.symbols at load (only when absent).
 * Fixtures follow the debug galleries (HassUI/Features/Gallery/ClimateGallery.swift, SecurityGallery.swift): no real names or data.
 */
(function () {
  var h = Mock.h, I = Mock.icon, K = Mock.components;
  var SC = window.SecClimate = window.SecClimate || {};

  /* ------------------------------------------------------------------ missing symbols */
  function p(d) { return '<path d="' + d + '"/>'; }
  function c(x, y, r) { return '<circle cx="' + x + '" cy="' + y + '" r="' + r + '"/>'; }
  function rc(x, y, w, hh, r) { return '<rect x="' + x + '" y="' + y + '" width="' + w + '" height="' + hh + '" rx="' + (r || 0) + '"/>'; }
  var therm = 'M10 14.4V5.2a2 2 0 0 1 4 0v9.2a4 4 0 1 1-4 0z';
  var add = {
    'thermometer.variable': p(therm) + p('M12 8.6v7') + p('M17.2 6.5h3M17.2 10h2M17.2 13.5h3'),
    'thermometer.and.liquid.waves': p(therm) + p('M12 8.6v7') + p('M16 12c.9-.9 1.7-.9 2.5 0s1.7.9 2.5 0M16 15.5c.9-.9 1.7-.9 2.5 0s1.7.9 2.5 0'),
    'thermometer.medium.slash': p(therm) + p('M12 8.6v7') + p('M4.5 3.5l15 17'),
    'thermometer.high': p(therm) + p('M12 6.2v9.5'),
    'dial.medium': c(12, 12, 8.5) + p('M12 12l3.4-3.4M7.5 16.5h9'),
    'leaf.circle': c(12, 12, 9) + p('M8 15.5c0-4 2.6-6.6 7.6-7-.2 4.8-2.8 7.4-6.4 7.4M8 16.3c1.2-2.8 3-4.4 5-5.5'),
    'window.vertical.open': rc(4.5, 3.5, 15, 17, 1.5) + p('M12 3.5v17M7 8h2M7 12h2'),
    'air.conditioner.horizontal': rc(3, 6, 18, 8, 2) + p('M6.5 10h11M7 17.5c0 1.3-.8 1.8-.8 2.8M12 17.5c0 1.3-.8 1.8-.8 2.8M17 17.5c0 1.3-.8 1.8-.8 2.8'),
    'sun.snow': c(9, 9, 3.2) + p('M9 2.8v1.4M9 13.8v1.4M2.8 9h1.4M13.8 9h1.4M17.5 13v8M14 15l7 4M21 15l-7 4'),
    'arrow.triangle.2.circlepath': p('M5 12a7 7 0 0 1 12-4.9l2 1.9M19 5v4h-4M19 12a7 7 0 0 1-12 4.9l-2-1.9M5 19v-4h4'),
    'desktopcomputer': rc(3.5, 4, 17, 11, 1.5) + p('M9 20h6M12 15v5'),
    'bathtub': p('M3.5 12h17v2.5a4 4 0 0 1-4 4h-9a4 4 0 0 1-4-4zM6.5 12V6.5a2 2 0 0 1 3.7-1M6 18.5l-1 2M18 18.5l1 2'),
    'stove': [rc(4, 3.5, 16, 17, 2) + p('M4 9h16') + c(8.5, 6.2, .8) + c(12, 6.2, .8) + c(15.5, 6.2, .8) + rc(7, 12, 10, 5, 1),
      '<path fill-rule="evenodd" d="M6 3.5h12a2 2 0 0 1 2 2v13a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2v-13a2 2 0 0 1 2-2zM7 12.5v5h10v-5zM8.5 5.1a.9.9 0 1 0 0 1.8.9.9 0 0 0 0-1.8zm3.5 0a.9.9 0 1 0 0 1.8.9.9 0 0 0 0-1.8zm3.5 0a.9.9 0 1 0 0 1.8.9.9 0 0 0 0-1.8z"/>'],
    'chevron.up.chevron.down': p('M8 9.5l4-4 4 4M8 14.5l4 4 4-4'),
    'circle': c(12, 12, 8.5),
    'car': p('M4.5 15.5V12l1.7-4.3A2 2 0 0 1 8 6.5h8a2 2 0 0 1 1.8 1.2L19.5 12v3.5zM4.5 15.5v2.5M19.5 15.5v2.5M7.5 12h9') + c(8, 14.2, .6) + c(16, 14.2, .6),
  };
  Object.keys(add).forEach(function (k) { if (!Mock.symbols[k]) Mock.symbols[k] = add[k]; });
  /** The SF Symbol the app's SymbolMap picks for the MDI names Climate and Security use. */
  var MDI = { 'mdi:thermostat': 'thermometer.medium', 'mdi:cog': 'gearshape', 'mdi:motion-sensor': 'figure.walk.motion', 'mdi:home-thermometer': 'thermometer.variable',
    'mdi:home-thermometer-outline': 'thermometer.and.liquid.waves', 'mdi:thermometer-check': 'thermometer.medium', 'mdi:thermometer-off': 'thermometer.medium.slash', 'mdi:thermometer-alert': 'thermometer.high',
    'mdi:thermostat-auto': 'dial.medium', 'mdi:leaf': 'leaf', 'mdi:leaf-circle': 'leaf.circle', 'mdi:home-export-outline': 'figure.walk.departure', 'mdi:home-check': 'checkmark.circle',
    'mdi:hvac': 'air.conditioner.horizontal', 'mdi:fan': 'fan', 'mdi:power': 'power', 'mdi:autorenew': 'arrow.triangle.2.circlepath', 'mdi:snowflake': 'snowflake', 'mdi:fire': 'flame',
    'mdi:sun-snowflake-variant': 'sun.snow', 'mdi:water-percent': 'humidity', 'mdi:door-open': 'door.left.hand.open', 'mdi:window-open': 'window.vertical.open' };
  SC.sym = function (mdi) { return MDI[mdi] || mdi; };

  /* ------------------------------------------------------------------ local styles (tokens only; nothing the kit already has) */
  var css = [
    '.cdial { position: relative; width: 100%; max-width: calc(var(--maxside, 316px) + 40px); aspect-ratio: 1; padding: 20px; box-sizing: border-box; margin: 0 auto; touch-action: pan-y; }',
    '.cdial.page { --cd-ink: #fff; --cd-ink2: rgba(255, 255, 255, .92); }',
    '.cdial.sheet { --cd-ink: var(--ink, #fff); --cd-ink2: var(--ink-2, rgba(255, 255, 255, .72)); }',
    '.cd-ring { position: relative; width: 100%; height: 100%; }',
    '.cd-grp { position: absolute; inset: 0; filter: drop-shadow(0 10px 7px rgba(0, 0, 0, .18)); transition: opacity var(--t-state) var(--ease-state); }',
    '.cd-grp.inactive { opacity: .45; filter: saturate(0) drop-shadow(0 10px 7px rgba(0, 0, 0, .18)); }',
    '.cd-svg { position: absolute; inset: 0; width: 100%; height: 100%; overflow: visible; }',
    '.cd-svg path { transition: stroke var(--t-state) var(--ease-state); }',
    '.cd-track { stroke: color-mix(in srgb, var(--cd-ink) 16%, transparent); }',
    '.cd-mark { position: absolute; width: 18px; height: 18px; margin: -9px 0 0 -9px; border-radius: 50%; background: var(--hc); border: 3px solid #141414; box-sizing: border-box; transition: left .2s var(--ease-quick), top .2s var(--ease-quick), background-color var(--t-state) var(--ease-state); }',
    '.cd-h { position: absolute; width: 24px; height: 24px; margin: -12px 0 0 -12px; border-radius: 50%; background: #fff; border: 4px solid var(--hc); box-sizing: border-box; box-shadow: 0 4px 6px rgba(0, 0, 0, .2); transition: left .2s var(--ease-quick), top .2s var(--ease-quick), border-color var(--t-state) var(--ease-state); outline-offset: 6px; touch-action: none; }',
    '.cd-h::after { content: ""; position: absolute; inset: -20px; border-radius: 50%; }',
    '.cd-h.drag { box-shadow: 0 10px 12px rgba(0, 0, 0, .3); transition: border-color var(--t-state) var(--ease-state); }',
    '.cd-h.drag::before { content: ""; position: absolute; inset: -10px; border-radius: 50%; background: rgba(255, 255, 255, .12); }',
    '.cd-svg.nomove path { transition: stroke var(--t-state) var(--ease-state); }',
    '.cd-read { position: absolute; left: 50%; top: 50%; width: max-content; transform: translate(-50%, -50%) scale(var(--k, 1)); display: flex; flex-direction: column; align-items: center; gap: 4px; white-space: nowrap; pointer-events: none; }',
    '.cd-act { font: 700 var(--fs-sub)/1.2 var(--font); color: var(--cd-ink2); }',
    '.cd-big { font-size: calc(76px * var(--sc, 1)); font-weight: 300; line-height: 1.05; font-variant-numeric: tabular-nums; color: var(--cd-ink); font-family: var(--font-d); }',
    '.cd-u { font-size: calc(76px * var(--sc, 1) * .32); font-weight: 700; position: relative; top: -1.31em; margin-left: 2px; }',
    '.cd-cap { font: 700 var(--fs-foot)/1.2 var(--font); color: var(--cd-ink2); display: inline-flex; align-items: center; gap: 4px; font-variant-numeric: tabular-nums; }',
    '.sc-module { background: var(--g-module-thin); border-radius: var(--radius-module); color: #fff; } .sc-module.dense { background: var(--g-module-dense); }',
    '.k-reduce-transparency .sc-module { background: #1C1C1E; } .k-reduce-transparency .sc-module.dense { background: #141416; }',
    '.sc-notice { display: flex; align-items: baseline; gap: 12px; padding: 14px 16px; font-size: var(--fs-sub); }',
    '.sc-notice .g { color: var(--ink-action, #409CFF); font-size: var(--fs-body); font-weight: 600; flex: none; transition: color var(--t-state) var(--ease-state); } .sc-notice.warn .g { color: var(--ink-warning, #FFB340); }',
    '.sc-notice .t { flex: 1; min-width: 0; color: #fff; }',
    '.sc-hub { display: flex; align-items: center; gap: 12px; padding: 8px 12px; } .sc-hub.stacked { flex-direction: column; align-items: stretch; gap: 8px; }',
    '.sc-hub .l { display: flex; align-items: center; gap: 12px; flex: 1; min-width: 0; }',
    '.sc-hub .gl { font-size: var(--fs-t2); min-width: 28px; display: grid; place-items: center; color: var(--g-secondary-on-module); transition: color var(--t-state) var(--ease-state); }',
    '.sc-hub .gl.heat { color: var(--fam-heating-glyph); } .sc-hub .gl.cool { color: var(--fam-cooling-glyph); }',
    '.sc-hub .tx { display: flex; flex-direction: column; gap: 2px; min-width: 0; } .sc-hub .ti { font: 600 var(--fs-sub)/1.25 var(--font); color: #fff; } .sc-hub .su { font: var(--fs-foot)/1.25 var(--font); color: var(--g-secondary-on-module); }',
    '.sc-hub .pk { display: flex; gap: 4px; position: relative; }',
    '.sc-pick { display: inline-flex; align-items: center; justify-content: center; gap: 4px; min-width: 44px; min-height: 44px; padding: 0 6px; border: 0; background: none; color: var(--ink-action, #409CFF); font: var(--fs-body)/1.2 var(--font); cursor: pointer; border-radius: 12px; }',
    '.sc-pick[disabled] { opacity: .4; cursor: default; } .sc-pick .ui-sym { width: 1.1em; height: 1.1em; } .sc-pick .ch .ui-sym { width: .85em; height: .85em; }',
    '.sc-menu { position: absolute; right: 0; top: 100%; margin-top: 6px; z-index: 40; min-width: 190px; border-radius: 16px; background: rgba(44, 44, 46, .94); backdrop-filter: blur(30px); box-shadow: 0 10px 30px rgba(0, 0, 0, .45); padding: 6px; color: #fff; }',
    '.sc-menu .it { display: flex; align-items: center; gap: 10px; min-height: 44px; padding: 0 10px; border-radius: 10px; font: var(--fs-body)/1.2 var(--font); } .sc-menu .it .ck { width: 20px; display: grid; place-items: center; color: #fff; } .sc-menu .it .lb { flex: 1; } .sc-menu .it .ui-sym { width: 1.1em; height: 1.1em; }',
    '.sc-col { width: 100%; max-width: 752px; margin-left: auto !important; margin-right: auto !important; padding: 0 16px; box-sizing: border-box; display: flex; flex-direction: column; gap: var(--sp-xl); }',
    '.sc-whole { width: 100%; max-width: 640px; margin: 0 auto; display: flex; flex-direction: column; gap: 12px; align-items: stretch; }',
    '.sc-form { display: flex; flex-direction: column; gap: 26px; width: 100%; max-width: 720px; margin: 0 auto; }',
    '.sc-fsec .ui-mlist { background: var(--sheet-cell); color: var(--ink); } .sc-fsec .ui-mrow .su { font-variant-numeric: tabular-nums; }',
    '.sc-fsec .ui-mrow[data-disabled="1"] { opacity: .4; }',
    '.sc-cell { background: var(--sheet-cell); border-radius: var(--radius-module); padding: 14px 16px; color: var(--ink); font-size: var(--fs-body); display: flex; flex-direction: column; gap: 8px; }',
    '.sc-cell.warn { display: flex; flex-direction: row; gap: 12px; align-items: baseline; }',
    '.sc-vspace > .ui-grid { width: 100%; }',
    '.sc-acc-val { color: var(--ink-sheet-2); font-size: var(--fs-body); font-variant-numeric: tabular-nums; text-align: right; }',
    '.sc-chk { color: var(--ink-action, #409CFF); display: inline-grid; place-items: center; font-size: var(--fs-body); transition: opacity var(--t-quick) var(--ease-quick); }',
    '.sc-fsec .ui-mrow .tx, .sc-hub .tx, .sc-notice .t, .sc-cell, .sc-fsec .ui-formfoot { overflow-wrap: anywhere; }',
    '.ts-ax5 .sc-fsec .ui-mrow .rg { width: auto; }',
    '.sc-status { font: 600 11px var(--mono); }',
    /* kit gap: `.k-wrap h2` (atlas furniture) leaks into the app header and adds a 44 pt top margin; restore PageSectionHeader */
    '.screen .ui-hdr h2, .k-swatch .ui-hdr h2 { margin: 0; font: 700 var(--fs-t3)/1.2 var(--font-d); letter-spacing: 0; }',
  ].join('\n');
  document.head.appendChild(h('style', { id: 'sc-style' }, css));

  /* ------------------------------------------------------------------ small helpers */
  function titleCase(s) { return String(s || 'unknown').split('_').map(function (w) { return w.charAt(0).toUpperCase() + w.slice(1); }).join(' '); }
  function compact(v) { if (v == null || isNaN(v)) return '--'; var r = Math.round(v * 10) / 10; return r % 1 === 0 ? String(Math.round(r)) : String(r); }
  function one(v) { return Number(v).toFixed(1); }
  SC.titleCase = titleCase; SC.compact = compact;
  function section(title, kids, cls) { return h('div.ui-section' + (cls ? '.' + cls : ''), title ? K.PageSectionHeader({ title: title }) : null, kids); }
  SC.section = section;

  /** Trims a Mock.page body into the column the Climate page uses (720 pt, centred). */
  SC.col = function (kids) { return h('div.sc-col', kids); };

  /* ------------------------------------------------------------------ ThermostatDial (the real one) */
  var HEAT = '#CD5401', COOL = '#2C8E98';
  function pt(deg) { var a = deg * Math.PI / 180; return [160 + 145 * Math.cos(a), 160 + 145 * Math.sin(a)]; }
  function arcPath(d0, d1) { var a = pt(d0), b = pt(d1); return 'M' + a[0].toFixed(2) + ' ' + a[1].toFixed(2) + ' A145 145 0 ' + (d1 - d0 > 180 ? 1 : 0) + ' 1 ' + b[0].toFixed(2) + ' ' + b[1].toFixed(2); }
  /**
   * The ThermostatDial as the app draws it (ThermostatDial.swift): a 270 degree track open at the bottom (min at 7:30, max at 4:30, radius 145/320, line 24/320 of the side),
   * heat arc from the minimum to the heat-to handle and cool arc from the cool-to handle to the maximum in range mode (none for a single target), an 18 pt current-temperature
   * marker with a near-black rim in the status colour, white 24 pt handles with a 4 pt status-coloured border (64 pt hit target), and the readout (action line, the current
   * temperature in Light 76 pt with a raised unit, a caption with a thermometer glyph) fitted inside 62% of the side (minimumScaleFactor 0.4).
   * o: {title, size:'page'|'modal'|'compact', surface:'page'|'sheet', min, max, step, current, low, high, target, action, unit, off, unavailable, readOnly, dragging, caption, interactive, ctx}
   * The returned node has .setTargets({low, high, target}) and .update(o) for the motion demos.
   */
  SC.dial = function (o) {
    o = Object.assign({ title: 'Whole Home', size: 'page', surface: 'page', min: 45, max: 95, step: .5, current: 72, action: 'idle', unit: '°F' }, o);
    var side = { page: 316, modal: 300, compact: 250 }[o.size];
    var el = h('div.cdial.' + o.surface, { style: { '--maxside': side + 'px' } });
    var S = { low: o.low, high: o.high, target: o.target, dragging: o.dragging || null };
    function deg(v) { return 135 + Math.min(Math.max((v - o.min) / (o.max - o.min), 0), 1) * 270; }
    function status() { return /^heat/.test(o.action) ? 'heat' : (/^cool/.test(o.action) ? 'cool' : 'idle'); }
    function colorFor(handle) { if (handle === 'low') return HEAT; if (handle === 'high') return COOL; var s = status(); return s === 'heat' ? HEAT : (s === 'cool' ? COOL : 'var(--ink-2, rgba(255,255,255,.72))'); }
    function pos(node, v) { var q = pt(deg(v)); node.style.left = (q[0] / 320 * 100) + '%'; node.style.top = (q[1] / 320 * 100) + '%'; }
    var range = S.low != null && S.high != null, single = !range && S.target != null, has = !o.unavailable && (range || single);
    var inactive = o.unavailable || (!range && o.off && status() === 'idle');
    var svg = h('div', { html: '<svg class="cd-svg" viewBox="0 0 320 320" aria-hidden="true"><path class="cd-track" d="' + arcPath(135, 405) + '" fill="none" stroke-width="24" stroke-linecap="round"/><path class="cd-heat" fill="none" stroke="' + HEAT + '" stroke-width="24" stroke-linecap="round"/><path class="cd-cool" fill="none" stroke="' + COOL + '" stroke-width="24" stroke-linecap="round"/></svg>' });
    var grp = h('div.cd-grp' + (inactive ? '.inactive' : ''), svg.firstChild);
    var heat = grp.querySelector('.cd-heat'), cool = grp.querySelector('.cd-cool');
    var mark = null;
    if (!o.unavailable && o.current != null) { mark = h('span.cd-mark', { 'aria-hidden': 'true', style: { '--hc': colorFor('target') } }); pos(mark, o.current); grp.appendChild(mark); }
    var big = h('span.cd-big', o.unavailable ? '--' : compact(o.current)), unit = o.unit === '' ? null : h('span.cd-u', o.unit);
    var capNode = h('span.cd-cap'), act = h('span.cd-act');
    var read = h('div.cd-read', { role: 'group' }, act, h('span', big, unit), capNode);
    var ring = h('div.cd-ring', grp, read);
    el.appendChild(ring);
    var handles = {};
    function mk(handle) {
      var label = handle === 'low' ? o.title + ' heat to' : (handle === 'high' ? o.title + ' cool to' : o.title + ' target temperature');
      var n = h('span.cd-h', { role: 'slider', tabindex: o.readOnly ? null : '0', 'aria-label': label, 'aria-valuemin': o.min, 'aria-valuemax': o.max, style: { '--hc': colorFor(handle) } });
      handles[handle] = n; ring.appendChild(n); return n;
    }
    if (has && !o.readOnly) { (range ? ['low', 'high'] : ['target']).forEach(mk); }
    function caption() {
      if (o.caption === false) return null;
      if (typeof o.caption === 'string') return o.caption;
      if (range) return one(S.low) + ' · ' + one(S.high);
      if (single) return one(S.target) + o.unit;
      return null;
    }
    function draw() {
      heat.setAttribute('d', range && S.low > o.min && !o.unavailable ? arcPath(135, deg(S.low)) : '');
      cool.setAttribute('d', range && S.high < o.max && !o.unavailable ? arcPath(deg(S.high), 405) : '');
      if (handles.low) { pos(handles.low, S.low); handles.low.setAttribute('aria-valuenow', S.low); handles.low.setAttribute('aria-valuetext', compact(S.low) + ' degrees'); handles.low.classList.toggle('drag', S.dragging === 'low'); }
      if (handles.high) { pos(handles.high, S.high); handles.high.setAttribute('aria-valuenow', S.high); handles.high.setAttribute('aria-valuetext', compact(S.high) + ' degrees'); handles.high.classList.toggle('drag', S.dragging === 'high'); }
      if (handles.target) { pos(handles.target, S.target); handles.target.setAttribute('aria-valuenow', S.target); handles.target.setAttribute('aria-valuetext', compact(S.target) + ' degrees'); handles.target.classList.toggle('drag', S.dragging === 'target'); }
      var cap = caption();
      capNode.innerHTML = cap ? I('thermometer.medium', { size: '1em' }) : ''; if (cap) capNode.appendChild(document.createTextNode(cap)); capNode.hidden = !cap;
      act.textContent = o.unavailable ? 'Unavailable' : titleCase(o.action);
      read.setAttribute('aria-label', o.title + ' thermostat, ' + act.textContent + (o.unavailable ? '' : ', currently ' + compact(o.current) + o.unit));
      if (cap && !o.unavailable) read.setAttribute('aria-description', 'set to ' + cap); else read.removeAttribute('aria-description');
    }
    draw();
    function fit() {
      var s = ring.clientWidth; if (!s) return; read.style.setProperty('--k', 1);
      var w = read.offsetWidth, hh = read.offsetHeight, avail = .62 * s;
      read.style.setProperty('--k', Math.max(.4, Math.min(1, avail / w, avail / hh)).toFixed(3));
    }
    if (window.ResizeObserver) new ResizeObserver(fit).observe(ring);
    requestAnimationFrame(fit);

    el.setTargets = function (t, opts) {
      if (t.low != null) S.low = t.low; if (t.high != null) S.high = t.high; if (t.target != null) S.target = t.target;
      if (opts && opts.dragging !== undefined) S.dragging = opts.dragging;
      draw();
    };
    el.update = function (patch) { Object.assign(o, patch); if (mark && patch.action) { mark.style.setProperty('--hc', colorFor('target')); if (handles.target) handles.target.style.setProperty('--hc', colorFor('target')); } if (patch.current != null) { pos(mark, o.current); big.textContent = compact(o.current); } if (patch.action) draw(); fit(); };
    el.roll = function (next) { return Mock.anim.roll(big, compact(next)).then(function () { o.current = next; if (mark) pos(mark, next); fit(); }); };
    // Drag a handle (component mockup): the value follows the pointer, snaps to the step, heat-to never passes cool-to; release commits.
    if (o.interactive && has && !o.readOnly) {
      Object.keys(handles).forEach(function (hk) {
        handles[hk].addEventListener('pointerdown', function (e) {
          e.preventDefault(); handles[hk].setPointerCapture(e.pointerId); S.dragging = hk; draw();
          function move(ev) {
            var r = ring.getBoundingClientRect(), x = ev.clientX - (r.left + r.width / 2), y = ev.clientY - (r.top + r.height / 2);
            var a = Math.atan2(y, x) * 180 / Math.PI; if (a < 0) a += 360; var f;
            if (a >= 135) f = (a - 135) / 270; else if (a <= 45) f = (a + 225) / 270; else f = a < 90 ? 1 : 0;
            var v = Math.round((o.min + f * (o.max - o.min)) / o.step) * o.step;
            if (hk === 'low') S.low = Math.min(v, S.high); else if (hk === 'high') S.high = Math.max(v, S.low); else S.target = v;
            draw();
          }
          function up() { handles[hk].removeEventListener('pointermove', move); handles[hk].removeEventListener('pointerup', up); S.dragging = null; draw(); el.dispatchEvent(new CustomEvent('commit', { detail: Object.assign({}, S) })); }
          handles[hk].addEventListener('pointermove', move); handles[hk].addEventListener('pointerup', up);
        });
        handles[hk].addEventListener('keydown', function (e) {
          var d = e.key === 'ArrowUp' || e.key === 'ArrowRight' ? 1 : (e.key === 'ArrowDown' || e.key === 'ArrowLeft' ? -1 : 0); if (!d) return; e.preventDefault();
          if (hk === 'low') S.low = Math.min(S.low + d * o.step, S.high); else if (hk === 'high') S.high = Math.max(S.high + d * o.step, S.low); else S.target += d * o.step; draw();
        });
      });
    }
    return el;
  };

  /* ------------------------------------------------------------------ ClimateNotice */
  /** A notice on the wallpaper: a glyph and the text on a module (dense with an orange glyph for a warning), read as one element. */
  SC.notice = function (o) {
    return h('div.sc-notice.sc-module' + (o.warning ? '.dense.warn' : ''), { role: 'group', 'aria-label': o.text, dataset: { warning: o.warning ? '1' : '0' } },
      h('span.g', { html: I(o.symbol || 'info.circle', { fill: false }), 'aria-hidden': 'true' }), h('span.t', o.text));
  };
  SC.copy = {
    away: 'Away Mode Active. The room may be cooler or warmer than your heat/cool targets to save energy while away.',
    vacation: 'Vacation Mode Active. The room may be cooler or warmer than your heat/cool targets to save energy while away.',
    unavailable: 'Unavailable Mode. Home Assistant has not provided an effective-mode reason.',
    warning: 'Automatic Thermostat is off. Open Advanced Configuration to turn Home Assistant\'s thermostat control back on.',
    integration: 'Turn Home Assistant\'s automatic thermostat control on or off.',
    ecoMode: 'Eco Mode reduces heating and cooling in inactive rooms. Use the options above to choose critical-temperature protection and what happens when everyone is away.',
    predictive: 'Predictive Comfort uses forecast and indoor conditions to recommend earlier changes. Open it to review the recommendation and choose which automatic changes are allowed.',
    trackSelected: 'Track only the rooms that should participate in normal automatic heating and cooling.',
    selectedOpener: 'Choose the rooms used for normal automatic heating and cooling when selected-room tracking is on.',
    forceCritical: 'Choose unselected rooms that should still be monitored for unsafe temperatures.',
    occupiedOnly: 'Choose rooms that should stop contributing demand while empty and rejoin when occupied.',
    selectedDisabled: 'Enable Track Selected Rooms before choosing participating rooms.',
    criticalDisabled: 'Set Eco Mode Critical Tracking to Track Select Critical before choosing protected unselected rooms.',
    enableFirst: 'Enable Track Selected Rooms first',
    tabs: {
      rooms: 'View each room\'s temperature and occupancy, then open a room to adjust its target and check vent position.',
      automation: 'Manage Automatic Thermostat, Eco Mode, and Predictive Comfort settings.',
      tracking: 'Choose which rooms participate in normal comfort, critical protection, or occupancy-only tracking.',
    },
    autoAdjust: 'Allow Predictive Comfort to adjust the thermostat target before the house leaves the comfort range.',
    hvacChanges: 'Allow Predictive Comfort to switch between heating and cooling when the recommendation requires it.',
    allowAway: 'Allow predictive thermostat changes while everyone is away. Leave this off to act only while someone is home.',
  };

  /* ------------------------------------------------------------------ Thermostat Hub pill */
  var HUB_MODES = [['off', 'Off', 'power'], ['heat', 'Heat', 'flame'], ['cool', 'Cool', 'snowflake'], ['heat_cool', 'Heat/Cool', 'sun.snow']];
  var HUB_FANS = [['auto', 'Auto', 'fan'], ['on', 'On', 'fan']];
  /**
   * ThermostatHubPill: one thin module row: the hub's glyph tinted by hvac_action, "Thermostat Hub" and its state, then the mode and fan pop-up menus (44 pt). At accessibility
   * sizes the menus drop under the text and show their value instead of a glyph.
   * o: {mode:'heat', action:'heating'|'cooling'|'idle', fan:'auto', noFan, unavailable, menu:'mode'|'fan'|null, stacked}
   */
  SC.hub = function (o) {
    o = Object.assign({ mode: 'heat', action: 'heating', fan: 'auto' }, o);
    var ctx = o.ctx || Mock.current || {}, stacked = o.stacked != null ? o.stacked : !!ctx.axSize;
    var state = o.unavailable ? 'Unavailable' : titleCase(o.mode);
    var tint = /^heat/.test(o.action) ? 'heat' : (/^cool/.test(o.action) ? 'cool' : '');
    function pick(kind, opts, cur, glyph, label) {
      var curLabel = (opts.filter(function (x) { return x[0] === cur; })[0] || [0, titleCase(cur)])[1];
      var disabled = o.unavailable;
      var b = h('button.sc-pick', { type: 'button', 'aria-haspopup': 'menu', 'aria-label': label, 'aria-description': curLabel, title: label, dataset: { pick: kind } },
        stacked ? h('span', disabled ? '' : curLabel) : h('span', { html: I(glyph) }), h('span.ch', { html: I('chevron.up.chevron.down'), 'aria-hidden': 'true' }));
      if (disabled) b.disabled = true;
      return b;
    }
    var mode = pick('mode', HUB_MODES, o.mode, 'power', 'Thermostat Hub Mode'), fan = o.noFan || o.unavailable ? null : pick('fan', HUB_FANS, o.fan, 'fan', 'Thermostat Hub Fan');
    var pk = h('div.pk', mode, fan);
    var menu = null;
    if (o.menu) {
      var opts = o.menu === 'mode' ? HUB_MODES : HUB_FANS, cur = o.menu === 'mode' ? o.mode : o.fan;
      menu = h('div.sc-menu', { role: 'menu', 'aria-label': o.menu === 'mode' ? 'Thermostat Hub Mode' : 'Thermostat Hub Fan', style: o.menu === 'fan' ? { right: 0 } : { right: fan ? '52px' : 0 } },
        opts.map(function (x) { return h('div.it', { role: 'menuitemradio', 'aria-checked': x[0] === cur ? 'true' : 'false' }, h('span.ck', { html: x[0] === cur ? I('checkmark', { weight: 2.4 }) : '' }), h('span.lb', x[1]), h('span', { html: I(x[2]) })); }));
      pk.appendChild(menu);
    }
    return h('div.sc-hub.sc-module' + (stacked ? '.stacked' : ''), { role: 'group', 'aria-label': 'Thermostat Hub, ' + state },
      h('div.l', { role: 'group', 'aria-label': 'Thermostat Hub, ' + state }, h('span.gl' + (tint ? '.' + tint : ''), { html: I('thermometer.medium'), 'aria-hidden': 'true' }), h('span.tx', h('span.ti', 'Thermostat Hub'), h('span.su', state))), pk);
  };
  SC.hubOptions = { modes: HUB_MODES, fans: HUB_FANS };

  /* ------------------------------------------------------------------ Climate fixtures */
  var R = [['Living Room', 'sofa', 70.9, 'Occupied', 1, [100, 50]], ['Office', 'desktopcomputer', 76.1, 'Active', 1, [0]], ['Bedroom 1', 'bed.double', 72.3, 'Active', 1, [100, 100]],
    ['Bathroom 1', 'bathtub', 73.3, 'Inactive', 0, [100]], ['Kitchen', 'stove', 69.9, 'Inactive', 0, [100]], ['Guest Room', 'bed.double', 71.4, 'Inactive', 0, [100]],
    ['Dining Room', 'fork.knife', 68.8, 'Inactive', 0, [100]], ['Gym', 'dumbbell', 71.6, 'Inactive', 0, [100]], ['Guest Bathroom', 'shower', 75.4, 'Inactive', 0, [100]],
    ['Studio', 'music.note', 71.7, 'Inactive', 0, [100]], ['Media Room', 'film', 72.1, 'Inactive', 0, [100, 100]]];
  SC.rooms = R.map(function (r, i) {
    var key = r[0].toLowerCase().replace(/ /g, '-'), many = r[5].length > 1;
    return { title: r[0], key: key, icon: r[1], temp: r[2], occ: r[3], occupied: !!r[4], section: r[0] + (many ? ' Vents' : ' Vent'),
      vents: r[5].map(function (pos, n) { return { title: many ? 'Vent ' + (n + 1) : 'Vent', pos: pos, open: pos > 0 }; }),
      track: ['living-room', 'office', 'master-bedroom'].indexOf(key) >= 0, force: key === 'guest-room', occOnly: ['master-bathroom', 'guest-bathroom'].indexOf(key) >= 0 };
  });
  SC.room = function (key) { return SC.rooms.filter(function (r) { return r.key === key; })[0]; };
  SC.ecoOptions = {
    critical: { id: 'eco-critical', title: 'Eco Mode Critical Tracking', icon: 'mdi:thermometer-alert', value: 'Track Select Critical', opener: 'Choose how Eco Mode protects rooms from unsafe temperatures.', page: 'Choose how Eco Mode protects rooms that are not participating in normal heating and cooling.',
      options: [['Do Not Track Critical', 'Do not add temperature-only protection for unselected rooms.', 'mdi:thermometer-off'], ['Track Select Critical', 'Protect only the unselected rooms chosen in Critical Protection.', 'mdi:thermometer-check'], ['Track All Critical', 'Protect every room from unsafe temperatures, even when it is not selected.', 'mdi:thermometer-alert']] },
    away: { id: 'eco-away', title: 'Eco Behavior When Away', icon: 'mdi:leaf-circle', value: 'Keep Eco Active', opener: 'Choose whether Eco Mode turns off, uses away targets, or stays active when everyone leaves.', page: 'Choose what Eco Mode should do when everyone is away.',
      options: [['Disable Eco When Away', 'Turn Eco Mode off while everyone is away.', 'mdi:home-export-outline'], ['Use Eco Away Targets', 'Use the wider away temperature range while everyone is away.', 'mdi:home-thermometer'], ['Keep Eco Active', 'Keep normal Eco Mode behavior active while everyone is away.', 'mdi:leaf']] },
  };
  SC.contactSensors = [['Front Door', 0], ['Computer Window', 1], ['Office Window', 1], ['Living Room Window', 1], ['Garage Door', 0], ['Bedroom 1 Windows', 1], ['Dining Room Door', 0], ['Kitchen Door', 0], ['Studio Door', 0], ['Media Room Door', 0], ['Guest Room Window', 1], ['Gym Window', 1]];
  SC.contactTile = function (title) {
    var win = /window/i.test(title);
    return K.GlassTile({ title: title, subtitle: 'Open', symbol: win ? 'window.vertical.open' : 'door.left.hand.open', family: 'contact', isActive: true, kind: 'state' });
  };
  SC.hubDefaults = function (scn) { scn = scn || 'home'; return scn === 'away' ? { mode: 'off', action: 'idle' } : { mode: 'heat', action: 'heating' }; };

  /* ------------------------------------------------------------------ Climate page */
  /**
   * The Climate page body (ClimatePage): Whole Home (the dial straight on the wallpaper, the hub pill tucked into its open bottom, notices), Open Contact Sensors while any
   * is open, Advanced Controls rows. The column is 720 pt, Whole Home 640 pt.
   * o: {dial:{...}, hub:{...}, notices:[nodes], contacts:[titles], unavailable}
   */
  SC.climateBody = function (ctx, o) {
    o = o || {};
    var dialOpts = Object.assign({ title: 'Whole Home', size: 'page', surface: 'page', current: 72, low: 71, high: 74, action: 'heating' }, o.dial);
    var dial = SC.dial(dialOpts);
    dial.style.marginBottom = '-36px'; dial.style.position = 'relative';
    var whole = h('div.sc-whole', dial, SC.hub(Object.assign({ ctx: ctx }, o.hub)), o.notices || []);
    var wholeSec = section('Whole Home', whole);
    var contacts = o.contacts || [];
    var contactSec = contacts.length ? section('Open Contact Sensors', K.TileGrid({ min: 160, max: 4, items: contacts.map(SC.contactTile) })) : null;
    var tabs = [['rooms', 'Room Thermostats', 'mdi:home-thermometer'], ['automation', 'Advanced Configuration', 'mdi:cog'], ['tracking', 'Room Tracking', 'mdi:motion-sensor']];
    var advSec = section('Advanced Controls', K.ModuleList({ rows: tabs.map(function (t) { return { title: t[1], subtitle: SC.copy.tabs[t[0]], symbol: SC.sym(t[2]) }; }) }));
    /* Partly folded Duo (section-sides.md, claude/section-sides): Whole Home leads; Open Contact Sensors (while any is open) and Advanced Controls trail. */
    var fold = Mock.foldColumns(ctx, { leading: [wholeSec], trailing: [contactSec, advSec] });
    if (fold) return fold;
    return [SC.col([wholeSec, contactSec, advSec].filter(Boolean))];
  };
  SC.climatePage = function (ctx, o) {
    o = o || {};
    return Mock.page(ctx, Object.assign({ title: 'Climate', section: 'climate', badge: 3, choresBadge: 2, body: SC.climateBody(ctx, o) }, o.page));
  };
  /** Scenario presets for the page: 'home' (heating, a window open), 'closed', 'cooling', 'idle', 'away', 'unavailable'. */
  SC.climateScenario = function (ctx, name) {
    var contacts = ['Office Window'];
    switch (name) {
      case 'closed': return { contacts: [], dial: { action: 'idle' }, hub: { mode: 'heat', action: 'idle' } };
      case 'cooling': return { contacts: [], dial: { current: 75, low: 68, high: 72, action: 'cooling' }, hub: { mode: 'cool', action: 'cooling' } };
      case 'idle': return { contacts: [], dial: { action: 'idle', current: 72 }, hub: { mode: 'heat_cool', action: 'idle' } };
      case 'off': return { contacts: [], dial: { action: 'off', current: 72, low: 71, high: 74 }, hub: { mode: 'off', action: 'off' } };
      case 'away': return { contacts: [], dial: { low: 62, high: 78, current: 72, action: 'idle' }, hub: { mode: 'off', action: 'idle' }, notices: [SC.notice({ text: SC.copy.vacation, symbol: 'house' }), SC.notice({ text: SC.copy.warning, symbol: 'exclamationmark.triangle', warning: true })] };
      case 'integration-off': return { contacts: contacts, notices: [SC.notice({ text: SC.copy.warning, symbol: 'exclamationmark.triangle', warning: true })] };
      case 'unavailable': return { contacts: [], dial: { unavailable: true, low: null, high: null, current: null, action: 'unavailable' }, hub: { unavailable: true, mode: 'unavailable', action: 'idle' }, notices: [SC.notice({ text: SC.copy.unavailable, symbol: 'house' })] };
      default: return { contacts: contacts };
    }
  };

  /* ------------------------------------------------------------------ Climate sheet pieces (Form-style rows on the sheet's cell colour) */
  function ico(sym) { return { symbol: SC.sym(sym) }; }
  /** A Form section: a 15 semibold header, one grouped card of rows, a 13 pt footer. rows are ModuleRow props. */
  function fsec(o) {
    var rows = (o.rows || []).map(function (r) {
      var n = K.ModuleRow(r);
      if (r.disabled) n.dataset.disabled = '1';
      return n;
    });
    return h('section.sc-fsec', o.header ? h('p.ui-formhead', { role: 'heading', 'aria-level': '2' }, o.header) : null, K.ModuleList({ rows: rows, hasGlyphs: o.hasGlyphs !== false }), o.footer ? h('p.ui-formfoot', o.footer) : null);
  }
  SC.fsec = fsec;
  function toggleRow(title, sym, on, sub, disabled) { return Object.assign({ title: title, subtitle: sub, accessory: K.Toggle({ on: on, label: title }), disabled: disabled }, ico(sym)); }
  SC.toggleRow = toggleRow;
  function form(kids) { return h('div.sc-form', kids); }
  SC.form = form;

  /** The state the sheet's tabs read (ClimateGallery fixtures). */
  SC.sheetData = function (o) {
    o = Object.assign({ integration: true, eco: true, predictive: true, autoAdjust: true, hvacChanges: true, allowAway: false, trackSelected: true, ecoCritical: 'Track Select Critical', ecoAway: 'Keep Eco Active', unavailable: false }, o);
    return o;
  };
  SC.roomsTab = function (ctx, d) {
    var tiles = SC.rooms.map(function (r) {
      var t = K.GlassTile({ title: r.title, subtitle: d.unavailable ? '--°F\nUnknown' : one(r.temp) + '°F\n' + r.occ, symbol: r.icon, room: r.key, layout: 'stack', titleLines: 2, kind: 'navigate' });
      t.querySelectorAll('.st').forEach(function (s) { s.style.whiteSpace = 'pre-line'; });
      t.dataset.room = r.key; return t;
    });
    return h('div.sc-vspace', { style: { display: 'flex', flexDirection: 'column', gap: '16px', maxWidth: '720px', margin: '0 auto', width: '100%' } }, K.TileGrid({ min: 150, max: 4, items: tiles }), h('p.ui-formfoot', { style: { margin: 0, fontSize: 'var(--fs-foot)' } }, SC.copy.tabs.rooms));
  };
  SC.automationTab = function (ctx, d) {
    var eco = SC.ecoOptions, un = d.unavailable;
    var ecoRows = [toggleRow('Eco Mode', 'mdi:leaf', !un && d.eco, null, un)].concat(['critical', 'away'].map(function (k) {
      var e = eco[k], v = k === 'critical' ? d.ecoCritical : d.ecoAway;
      return Object.assign({ title: e.title, accessory: h('span.sc-acc-val', un ? 'Unknown' : v), chevron: true, disabled: un }, ico(e.icon));
    }));
    var rec = d.recommendation || 'Pre-Cool', sub = !d.predictive ? 'Off' : 'On · ' + rec;
    var pred = [toggleRow('Predictive Comfort', 'mdi:home-thermometer-outline', !un && d.predictive, un ? 'Unavailable' : sub, un)];
    if (d.predictive && !un) pred.push({ title: 'Current Prediction', chevron: true });
    return form([
      fsec({ rows: [toggleRow('Automatic Thermostat', 'mdi:thermostat', !un && d.integration, null, un)], footer: SC.copy.integration }),
      fsec({ header: 'Eco Mode', rows: ecoRows, footer: SC.copy.ecoMode }),
      fsec({ header: 'Predictive Comfort', rows: pred, footer: SC.copy.predictive }),
    ]);
  };
  SC.trackingSummary = function (d) {
    var un = d.unavailable, rooms = SC.rooms;
    var selectedOn = !un && d.trackSelected, critOn = selectedOn && d.ecoCritical === 'Track Select Critical';
    return { selectedOn: selectedOn, critOn: critOn,
      selected: selectedOn ? rooms.filter(function (r) { return r.track; }).length + ' of 11 selected' : SC.copy.enableFirst,
      critical: critOn ? (function (n) { return n + (n === 1 ? ' room forced' : ' rooms forced'); })(rooms.filter(function (r) { return !r.track && r.force; }).length) : (selectedOn ? d.ecoCritical : SC.copy.enableFirst),
      occupied: (un ? 0 : rooms.filter(function (r) { return r.occOnly; }).length) + ' of 11 occupied only' };
  };
  SC.trackingTab = function (ctx, d) {
    var s = SC.trackingSummary(d), un = d.unavailable;
    var pages = [['Selected Rooms', 'mdi:home-check', s.selected, SC.copy.selectedOpener, s.selectedOn], ['Critical Protection', 'mdi:thermometer-alert', s.critical, SC.copy.forceCritical, s.critOn], ['Occupied Only', 'mdi:motion-sensor', s.occupied, SC.copy.occupiedOnly, true]];
    return form([fsec({ header: 'Room Tracking', rows: [toggleRow('Track Selected Rooms', 'mdi:home-thermometer', !un && d.trackSelected, null, un)], footer: SC.copy.trackSelected })].concat(pages.map(function (pg, i) {
      return fsec({ header: i === 0 ? 'Room Rules' : null, rows: [Object.assign({ title: pg[0], subtitle: pg[2], chevron: true, disabled: !pg[4] }, ico(pg[1]))], footer: pg[3] });
    })));
  };
  SC.roomDetail = function (ctx, r, o) {
    o = o || {};
    var dialOpts = Object.assign({ title: r.title, size: 'modal', surface: 'sheet', current: Math.round(r.temp), low: 71, high: 74, action: 'idle' }, o.dial);
    var kids = [h('div', { style: { padding: '8px 0' } }, SC.dial(dialOpts))];
    if (o.away) kids.push(h('div.sc-cell.warn', { role: 'group', 'aria-label': SC.copy.away }, h('span', { html: I('house'), style: { color: 'var(--ink)' } }), h('span', SC.copy.away)));
    var vents = r.vents.map(function (v, i) { var st = o.ventStates && o.ventStates[i] || (v.open ? 'open' : 'closed');
      return K.GlassTile({ title: v.title, subtitle: o.unavailable ? 'Unavailable' : (st === 'open' ? 'Open · ' + v.pos + '%' : 'Closed'), symbol: 'fan', family: 'vents', isActive: !o.unavailable && st === 'open', isUnavailable: !!o.unavailable, kind: 'state' }); });
    kids.push(h('section.sc-fsec', h('p.ui-formhead', { role: 'heading', 'aria-level': '2' }, r.section), K.TileGrid({ min: 150, max: 4, items: vents })));
    return form(kids);
  };
  SC.predictiveDetail = function (ctx, o) {
    o = o || {};
    var un = !!o.unavailable, rec = un ? 'Unknown' : (o.recommendation || 'Pre-Cool');
    var metrics = un ? [['Indoor', '--°F'], ['Predicted', '--°F'], ['Comfort Band', '--°F - --°F'], ['Forecast', 'Unknown'], ['Weather', 'Unknown'], ['Adjustment', 'Unknown']]
      : [['Indoor', '72.4°F'], ['Predicted', '75.1°F'], ['Comfort Band', '71.0°F - 74.0°F'], ['Forecast', '64.0°F - 88.0°F'], ['Weather', 'weather.demo_weather_1'], ['Adjustment', 'Applied']];
    var bullets = un ? ['No configured heat-load devices are active right now.']
      : ['Predicted indoor temperature rises above comfort band.', 'Predicted indoor temperature is 75.1°F, above your 71.0°F - 74.0°F comfort band.',
        'Today\'s forecast range is 64.0°F - 88.0°F, which Predictive Comfort uses to estimate where the house is heading.', 'Office PC Power is active, so the model is accounting for extra heat from configured devices.', 'Predictive Comfort has already applied the safe thermostat change.'];
    return form([
      h('div.sc-cell', { role: 'group', 'aria-label': 'Recommendation: ' + rec }, h('span', { style: { font: '600 var(--fs-hd)/1.25 var(--font)' } }, 'Recommendation: ' + rec)),
      fsec({ header: 'Controls', rows: [toggleRow('Auto Setpoint Adjustments', 'mdi:thermostat-auto', !un, null, un), toggleRow('HVAC Mode Changes', 'mdi:hvac', !un, null, un), toggleRow('Predictive Comfort While Away', 'mdi:home-export-outline', false, null, un)] }),
      fsec({ header: 'Current Prediction', hasGlyphs: false, rows: metrics.map(function (m) { return { title: m[0], accessory: h('span', { style: { fontVariantNumeric: 'tabular-nums', color: 'var(--ink)', textAlign: 'right' } }, m[1]) }; }) }),
      h('section.sc-fsec', h('p.ui-formhead', { role: 'heading', 'aria-level': '2' }, 'Why This Prediction'), h('div.sc-cell', { role: 'group' }, bullets.map(function (b) { return h('span', b); }))),
    ]);
  };
  SC.ecoDetail = function (ctx, k, o) {
    o = o || {};
    var e = SC.ecoOptions[k], cur = o.value || e.value;
    if (o.unavailable) return form([h('div', { style: { padding: '0 4px' } }, K.InlineAlert({ message: e.title + ' is unavailable until Home Assistant supplies supported options.' }))]);
    return form([fsec({ hasGlyphs: false, footer: e.page, rows: e.options.map(function (op) {
      var sel = op[0] === cur;
      return { title: op[0], subtitle: op[1], press: true, accessory: h('span.sc-chk', { style: { opacity: sel ? 1 : 0 }, html: I('checkmark', { weight: 2.4 }), 'aria-hidden': 'true' }) };
    }) })]);
  };
  SC.trackingDetail = function (ctx, k, o) {
    o = o || {};
    var cfg = { selected: { title: 'Selected Rooms', desc: SC.copy.trackSelected, on: function (r) { return r.track; }, list: SC.rooms, off: SC.copy.selectedDisabled },
      critical: { title: 'Critical Protection', desc: SC.copy.forceCritical, on: function (r) { return r.force; }, list: SC.rooms.filter(function (r) { return !r.track; }), off: SC.copy.criticalDisabled },
      occupied: { title: 'Occupied Only', desc: SC.copy.occupiedOnly, on: function (r) { return r.occOnly; }, list: SC.rooms, off: null } }[k];
    if (o.disabled && cfg.off) return form([h('div', { style: { padding: '0 4px' } }, K.InlineAlert({ message: cfg.off }))]);
    return form([fsec({ hasGlyphs: false, footer: cfg.desc, rows: cfg.list.map(function (r) {
      var on = cfg.on(r);
      return { title: r.title, press: true, accessory: h('span', { style: { fontSize: 'var(--fs-t3)', color: on ? 'var(--ink-action)' : 'var(--ink-sheet-2)', display: 'inline-grid', opacity: o.unavailable ? .5 : 1 }, html: I(on ? 'checkmark.circle.fill' : 'circle', { fill: on }), 'aria-hidden': 'true' }) };
    }) })]);
  };

  var TABS = [{ id: 'rooms', title: 'Rooms', symbol: 'thermometer.variable' }, { id: 'automation', title: 'Automation', symbol: 'gearshape' }, { id: 'tracking', title: 'Tracking', symbol: 'figure.walk.motion' }];
  SC.tabs = TABS;
  /**
   * The Advanced Controls sheet (ClimateSheet): NavigationStack in hassSheet(.page, .full), the section tab bar at the bottom, details pushed with Back.
   * o: {tab:'rooms'|'automation'|'tracking', content:Node (a pushed page), title (pushed page title), data (sheetData), presenter (scenario), noPresenter, detent}
   */
  SC.climateSheetOpts = function (ctx, o) {
    o = o || {};
    var d = SC.sheetData(o.data), tab = o.tab || 'rooms', content, title = 'Advanced Controls', tabs = null, leading = 'none';
    if (o.content) { content = o.content; title = o.title; leading = 'back'; }
    else {
      content = { rooms: SC.roomsTab, automation: SC.automationTab, tracking: SC.trackingTab }[tab](ctx, d);
      tabs = K.ModalTabBar({ tabs: TABS, selected: tab, ctx: ctx });
    }
    return { title: title, detent: o.detent || 'large', size: 'page', leading: leading, trailing: 'close', content: content, tabs: tabs };
  };
  SC.climateSheet = function (ctx, o) {
    o = o || {};
    var pres = o.noPresenter ? null : SC.climatePage(ctx, Object.assign(SC.climateScenario(ctx, o.scenario || 'home'), { page: { connection: o.connection } }));
    return Mock.sheet(ctx, Object.assign(SC.climateSheetOpts(ctx, o), { presenter: pres }));
  };

  /* ------------------------------------------------------------------ Security */
  var CHIP_SEC = { armed_home: 'armed_home', armed_away: 'armed_away', armed_night: 'armed_night', disarmed: 'disarmed', triggered: 'triggered', arming: 'arming', unavailable: 'unknown' };
  /** A lock or garage door tile (LockTile, GarageDoorTile) on the kit's GlassTile, contact family. spec: {kind:'lock'|'garage'|'car', title, state, phase, opens, unavailable} */
  SC.doorTile = function (s) {
    var un = s.unavailable || s.state === 'unavailable', st = s.state;
    if (s.kind === 'garage') {
      var phase = s.phase || 'idle', closed = st === 'closed';
      var sub = un ? 'Unavailable' : (phase === 'sending' ? (s.opens ? 'Sending Open…' : 'Sending Close…') : (phase === 'error' ? 'Error' : titleCase(st)));
      /* action-tiles.md: text . disc; the morphing garage disc carries the state glyph, the body does what it shows (no Stop: our doors do not support it) */
      var gsym = closed || un ? 'door.garage.closed' : 'door.garage.open', gverb = closed ? 'Open' : 'Close';
      return K.GlassTile({ title: s.title, subtitle: sub, symbol: gsym, family: 'contact', isActive: !un && !closed, isUnavailable: un, isError: phase === 'error', kind: 'command', pending: s.pending,
        behavior: 'perform', actions: [{ id: 'door', symbol: gsym, label: gverb + ' ' + s.title, on: !un && !closed, dim: un, busy: phase === 'sending' }] });
    }
    var active = !un && st !== 'locked';
    /* action-tiles.md: text . disc; the disc is the lock (the car tile drops its car glyph for it). isOn = unlocked: white disc on the filled tile. Jammed offers Lock. */
    var lsym = st === 'locked' || un ? 'lock.fill' : 'lock.open', lverb = (st === 'locked' || st === 'locking') ? 'Unlock' : 'Lock';
    return K.GlassTile({ title: s.title, subtitle: un ? 'Unavailable' : titleCase(st), symbol: lsym, family: 'contact', isActive: active, isUnavailable: un, isError: st === 'jammed', kind: 'command', pending: s.pending,
      behavior: 'perform', actions: [{ id: 'lock', symbol: lsym, label: lverb + ' ' + s.title, on: active && st !== 'jammed', dim: un }] });
  };
  SC.doors = { front: { kind: 'lock', title: 'Front Door' }, left: { kind: 'garage', title: 'Left Door' }, right: { kind: 'garage', title: 'Right Door' } };
  function appMin(n) { var c = Mock.current; return n / ((c && c.scale) || 1); } /* the app's ControlTileGrid (110) and CameraGrid (160) pass a plain number: not @ScaledMetric, so they do not follow Dynamic Type; the kit TileGrid scales min, so divide it out */
  function guests() {
    return section('Guests Staying Over', [h('p', 'Guest mode skips some away automations. Review security, climate, and auto-clean controls before leaving.'),
      K.TileGrid({ min: appMin(110), max: 6, equal: false, items: [
        { title: 'Guest Room', subtitle: 'Guests staying', symbol: 'bed.double', family: 'occupancy', isActive: true },
        { title: 'Studio', subtitle: 'No guests', symbol: 'guitars', family: 'occupancy', isActive: false },
        { title: 'Media Room', subtitle: 'Guests staying', symbol: 'videoprojector', family: 'occupancy', isActive: true }] })]);
  }
  /**
   * The Security page body (SecurityPage): status rail (Security and Contact Sensors), the alarm card on a module, "Doors" tiles, guests (while a toggle is on), cameras, car (hidden:
   * showsVehicleSection is false; the debug gallery shows it). One column, except a partly folded Duo, where the sections sit wholly in the leading or trailing region (fold columns).
   * o: {alarm, since, chips, front, left, right, guests, cams:[states], mach, pending, unavailable, contacts:['closed',0]}
   */
  SC.securityBody = function (ctx, o) {
    var p = SC.securityParts(ctx, o);
    /* Partly folded Duo (section-sides.md, claude/section-sides): the rail spans the top; the alarm card, Doors and car lead; Cameras then Guests trail, as on Home. */
    var fold = Mock.foldColumns(ctx, { top: [p.rail], leading: [p.alarmCard, p.doors, p.mach], trailing: [p.cams, p.guests] });
    if (fold) return fold;
    var top = h('div.ui-bleed', { style: { display: 'flex', flexDirection: 'column', gap: '16px' } }, p.rail, h('div', { style: { margin: '0 16px' } }, p.alarmCard));
    return [top, p.doors, p.guests, p.cams, p.mach].filter(Boolean);
  };
  /** The Security page's pieces, unplaced: {rail, alarmCard, doors, guests, cams, mach} (guests and mach are null unless asked for). The proposal section-sides lays them out its own ways. */
  SC.securityParts = function (ctx, o) {
    o = o || {};
    var alarm = o.alarm || 'armed_home', un = !!o.unavailable;
    var chips = o.chips || [Mock.chips.security(CHIP_SEC[alarm] || 'armed_home'), Mock.chips.contacts.apply(null, o.contacts || ['closed', 0])];
    var rail = K.ChipRail({ chips: chips }), alarmCard = K.AlarmPanel({ state: alarm, since: o.since, surface: 'page' });
    var t = function (base, over) { return SC.doorTile(Object.assign({ unavailable: un, pending: o.pending }, base, over)); };
    var tiles = [t(SC.doors.front, Object.assign({ state: un ? 'unavailable' : 'locked' }, o.front)), t(SC.doors.left, Object.assign({ state: un ? 'unavailable' : 'closed' }, o.left)), t(SC.doors.right, Object.assign({ state: un ? 'unavailable' : 'closed' }, o.right))];
    var doors = section('Doors', K.TileGrid({ min: 140, max: 4, items: tiles }));
    var g = o.guests ? guests() : null;
    var cs = o.cams || ['live', 'live', 'live', 'live'], names = [['Front Door', 'front-door'], ['Driveway', 'driveway'], ['Upper Deck', 'upper-deck'], ['Lower Deck', 'lower-deck']];
    var cams = section('Cameras', K.TileGrid({ min: appMin(160), max: 4, equal: false, items: names.map(function (n, i) { return K.CameraTile({ title: n[0], scene: n[1], state: cs[i] }); }) }));
    var mach = o.mach ? section('Car', K.TileGrid({ min: 140, max: 4, items: [t({ kind: 'car', title: 'Doors' }, { state: 'locked' })] })) : null;
    return { rail: rail, alarmCard: alarmCard, doors: doors, guests: g, cams: cams, mach: mach };
  };
  SC.securityPage = function (ctx, o) {
    o = o || {};
    return Mock.page(ctx, Object.assign({ title: 'Security', section: 'security', badge: 3, choresBadge: 2, body: SC.securityBody(ctx, o) }, o.page));
  };

  /* ------------------------------------------------------------------ component mockup swatches */
  /**
   * Swatches on the page surface (always dark, over the gradient) and the sheet surface (follows the Sheet appearance control), as Mock.componentConfig draws them.
   * spec: {surfaces?:['page','sheet'], min?:300, items:[{label, note?, width?, build(surface, ctx)}]}
   */
  SC.swatches = function (ctx, spec) {
    var out = h('div', { style: { display: 'flex', flexDirection: 'column', gap: '18px' } });
    (spec.surfaces || ['page', 'sheet']).forEach(function (surface) {
      var wrap = h('div.k-swatch-grid');
      spec.items.forEach(function (it) {
        if (it.surfaces && it.surfaces.indexOf(surface) < 0) return;
        var box = h('div.k-swatch.' + (surface === 'page' ? 'page.g-dark' : 'sheet.in-sheet.' + (ctx.appearance === 'dark' ? 'g-dark' : 'g-light')),
          { style: { flex: it.width ? 'none' : '1 1 ' + (spec.min || 300) + 'px', width: it.width || '', maxWidth: '100%' } },
          h('div.k-cap', surface + ' · ' + it.label), h('div.in', it.build(surface, ctx)), it.note ? h('div', { style: { font: '12px var(--font)', opacity: .7, marginTop: '8px' } }, it.note) : null);
        wrap.appendChild(box);
      });
      out.appendChild(wrap);
    });
    return out;
  };
  /** Render a state through swatches. */
  SC.swatchState = function (title, spec) { return { title: title, render: function (ctx) { return SC.swatches(ctx, spec); } }; };
})();
