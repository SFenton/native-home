/* Bedroom helpers for the bedroom-motion batch (not part of the kit; "promote to kit" candidates are marked).
 *
 * Draws what apple/Sources/HassUI/Features/Bedroom/{BedSideSheet,BedSideTile,BedScheduleTab,BedSpecialModesTab,BedAlarmsTab,BedStatusTab,WakeLightSheet,WakeLightDefaultsTab,WakeLightEditor,WakeLightTile,BedroomComponents}.swift draw today, from the gallery fixtures
 * (HassUI/Features/Gallery/BedroomGallery.swift BedroomFixtures): Alex's Bed (left), Sam's Bed (right), the Wake-Light Alarms profile.
 * Exposes Mock.bedroom (B). Loaded after kit.js with a relative <script src>. Everything here uses kit tokens (var(--...)) and Dynamic Type
 * variables (var(--fs-*), var(--sc)); there is no raster and no network.
 *
 * Promote to kit: the missing SF Symbols below (lib/symbols.js), ActionSheet (a confirmationDialog), the Bedroom* controls (.bd-*), the
 * single-handle signed-level dial (B.dial; the kit ThermostatDial draws a temperature numeral and a range).
 */
(function () {
  'use strict';
  var h = Mock.h, I = Mock.icon, K = Mock.components;
  var B = Mock.bedroom = {};

  /* ------------------------------------------------------------------ symbols the kit lacks (SF Symbol look-alikes; promote to kit) */
  function p(d) { return '<path d="' + d + '"/>'; }
  function c(x, y, r) { return '<circle cx="' + x + '" cy="' + y + '" r="' + r + '"/>'; }
  function rc(x, y, w, hh, r) { return '<rect x="' + x + '" y="' + y + '" width="' + w + '" height="' + hh + '" rx="' + (r || 0) + '"/>'; }
  var ADD = {
    'alarm': [c(12, 13.4, 7) + p('M12 9.6v4l2.6 1.6M4.6 5.2 2.8 7.2M19.4 5.2l1.8 2'), '<path fill-rule="evenodd" d="M12 6.2a7.2 7.2 0 1 0 0 14.4 7.2 7.2 0 0 0 0-14.4zM11.2 9.4h1.6v3.9l2.3 1.4-.8 1.4-3.1-1.9z"/><path d="M4.1 4.7 2.4 6.8l1.1.9 1.7-2.1zM19.9 4.7l1.7 2.1-1.1.9-1.7-2.1z"/>'],
    'alarm.waves.left.and.right': c(12, 13, 5.2) + p('M12 10.2v3l2 1.2M4.4 8.6a8.4 8.4 0 0 0-1.4 4.6M19.6 8.6a8.4 8.4 0 0 1 1.4 4.6M6.4 18.4 5 20M17.6 18.4 19 20'),
    'sunrise': p('M6.5 17a5.5 5.5 0 0 1 11 0M12 6.2v2.4M4.8 9.8l1.7 1.7M19.2 9.8l-1.7 1.7M2.8 17h3.2M18 17h3.2M7.5 20.4h9'),
    'zzz': p('M4.5 5h5l-5 6.2h5M12 11.4h4.8L12 17.4h4.8M16.6 3.4h3.4l-3.4 4.1H20'),
    'stop.circle': c(12, 12, 8.6) + rc(9, 9, 6, 6, 1.4),
    'lungs': p('M12 4v8.4M9.6 9C7 10 5 14 4.5 18c-.1 1.4 1.2 2 2.4 1.5 1.4-.6 2.6-1.8 2.6-3.6V9zM14.4 9c2.6 1 4.6 5 5.1 9 .1 1.4-1.2 2-2.4 1.5-1.4-.6-2.6-1.8-2.6-3.6V9z'),
    'waveform.path.ecg': p('M2.5 12.2h4l2-5.2 3.6 11 2.4-8 1.6 2.2h5.4'),
    'arrow.triangle.2.circlepath': p('M19.2 9a8 8 0 0 0-14-1.6M5 3.8v4.4h4.4M4.8 15a8 8 0 0 0 14 1.6M19 20.2v-4.4h-4.4'),
    'arrow.up.forward.app': p('M13.4 3.8h6.8v6.8M20.2 3.8l-8.2 8.2M10 4.8H7.4A3.4 3.4 0 0 0 4 8.2v8.4A3.4 3.4 0 0 0 7.4 20h8.4a3.4 3.4 0 0 0 3.4-3.4V14'),
    'gauge.with.dots.needle.33percent': p('M4.4 17.4a8.6 8.6 0 1 1 15.2 0M12 14.2 8.8 9.8'),
    'info.circle.fill': c(12, 12, 8.8) + p('M12 11v5M12 8v.2'),
    'xmark.octagon.fill': p('M8.6 3.6h6.8l5 5v6.8l-5 5H8.6l-5-5V8.6zM9 9l6 6M15 9l-6 6'),
    'slider.vertical.3': p('M6 4v16M12 4v16M18 4v16') + c(6, 14, 2) + c(12, 8, 2) + c(18, 15, 2),
  };
  Object.keys(ADD).forEach(function (k) { if (!Mock.symbols[k]) Mock.symbols[k] = ADD[k]; });

  /* ------------------------------------------------------------------ styles (bedroom controls, dial, action sheet; promote to kit) */
  var CSS = [
    '.bd-col{width:100%;max-width:640px;margin:0 auto;display:flex;flex-direction:column;gap:24px}',
    '.bd-col.wide{max-width:720px}',
    '.bd-stack{display:flex;flex-direction:column;gap:12px;width:100%}',
    '.bd-stack.s{gap:8px}',
    '.bd-two{display:flex;align-items:flex-start;width:calc(100% + 32px);margin:0 -16px}.bd-two>div{width:50%;padding:0 16px;box-sizing:border-box;display:flex;flex-direction:column;gap:24px}',
    '.bd-sec{display:flex;flex-direction:column;gap:4px;width:100%}',
    '.bd-sec .t{font:700 var(--fs-t3)/1.25 var(--font-d);color:var(--ink);margin:0}',
    '.bd-sec .d{font-size:var(--fs-sub);color:var(--ink-sheet-2);margin:0}',
    '.bd-sub{font-size:var(--fs-sub);color:var(--ink-sheet-2);margin:0;text-align:inherit}',
    '.bd-foot{font-size:var(--fs-foot);color:var(--ink-sheet-2);margin:0}',
    '.bd-card{background:var(--sheet-cell);border-radius:var(--radius-tile);padding:16px;display:flex;flex-direction:column;gap:12px;width:100%;box-sizing:border-box;text-align:left;color:var(--ink)}',
    '.bd-row{display:flex;align-items:center;gap:12px;min-height:44px;padding:8px 12px;border-radius:var(--radius-tile);background:var(--sheet-cell);color:var(--ink);width:100%;text-align:left;border:0;font:inherit;box-sizing:border-box;cursor:pointer}',
    '.bd-row .gl{width:calc(28px*var(--sc));display:grid;place-items:center;font-size:var(--fs-t3);color:var(--ink);flex:none}',
    '.bd-row.muted .gl{color:var(--ink-sheet-2)}',
    '.bd-row .tx{flex:1;min-width:0;display:flex;flex-direction:column;gap:2px}',
    '.bd-row .ti{font:600 var(--fs-body)/1.25 var(--font)}',
    '.bd-row .ln{font-size:var(--fs-sub);color:var(--ink-sheet-2)}',
    '.bd-row .ac{flex:none;display:flex;align-items:center;gap:8px;color:var(--ink-sheet-2)}',
    '.bd-link{background:none;border:0;color:var(--ink);font:600 var(--fs-sub)/1.2 var(--font);min-height:44px;display:flex;align-items:center;gap:8px;text-align:left;padding:0 4px;cursor:pointer;width:100%}',
    '.bd-step{width:44px;height:44px;border-radius:50%;border:0;background:var(--sep);color:var(--ink);display:grid;place-items:center;cursor:pointer;font-size:var(--fs-body);padding:0;font-weight:600}',
    '.bd-step[disabled]{opacity:.4;cursor:default}',
    '.bd-cap{display:inline-flex;align-items:center;justify-content:center;gap:8px;min-height:50px;min-width:160px;padding:8px 20px;text-align:center;overflow-wrap:anywhere;border-radius:999px;background:color-mix(in srgb,var(--ink) 12%,transparent);color:var(--ink);font:600 var(--fs-body)/1.2 var(--font);border:0;cursor:pointer;box-sizing:border-box}',
    '.bd-cap[disabled]{opacity:.4;cursor:default}.bd-cap.stack{flex-direction:column;gap:2px;padding-top:6px;padding-bottom:6px}.bd-cap.flex{flex:1;min-width:0}.bd-cap.sq{min-width:44px;min-height:44px;padding:0;width:44px}',
    '.bd-cap small{font:400 var(--fs-foot)/1.2 var(--font);font-variant-numeric:tabular-nums}',
    '.bd-danger{display:flex;align-items:center;justify-content:center;width:100%;min-height:44px;padding:8px 20px;border-radius:999px;border:0;background:#C21F1F;color:#fff;font:600 var(--fs-body)/1.2 var(--font);cursor:pointer;box-sizing:border-box}',
    '.bd-danger[disabled]{opacity:.4;cursor:default}',
    '.bd-btns{display:flex;gap:12px;width:100%}.bd-btns>*{flex:1;min-width:0}',
    '.bd-notice{display:flex;gap:12px;align-items:flex-start;padding:12px;border-radius:12px;background:color-mix(in srgb,var(--tone) 14%,transparent);color:var(--ink);font-size:var(--fs-sub);text-align:left;width:100%;box-sizing:border-box}',
    '.bd-notice .ui-sym{color:var(--tone);flex:none;margin-top:.15em}.bd-notice b{display:block;font-weight:600}.bd-notice p{margin:0}',
    '.bd-notice.info{--tone:#0A84FF}.bd-notice.warning{--tone:#FF9F0A}.bd-notice.error{--tone:#FF453A}.bd-notice.success{--tone:#30D158}',
    '.g-light .bd-notice.info{--tone:#007AFF}.g-light .bd-notice.warning{--tone:#FF9500}.g-light .bd-notice.error{--tone:#FF3B30}.g-light .bd-notice.success{--tone:#34C759}',
    '.bd-lb{font:600 var(--fs-sub)/1.25 var(--font);color:var(--ink);margin:0}',
    '.bd-field{display:flex;flex-direction:column;gap:8px;width:100%}',
    '.bd-choice{width:100%;min-height:44px;border-radius:12px;border:0;background:var(--sheet-cell);color:var(--ink);font:400 var(--fs-sub)/1.2 var(--font);padding:4px 8px;cursor:pointer;transition:background-color var(--t-state) var(--ease-state),color var(--t-state) var(--ease-state)}',
    '.bd-choice.sel{background:#0071E3;color:#fff;font-weight:600}.bd-choice.cap{border-radius:999px;font-weight:600}',
    '.bd-field.off{opacity:.5;pointer-events:none}',
    '.bd-clock{display:flex;justify-content:space-between;align-items:center;gap:8px;min-height:44px;flex-wrap:wrap;font-size:var(--fs-body);color:var(--ink);width:100%}',
    '.bd-pill{background:var(--fill-tertiary);padding:6px 12px;border-radius:8px;font-size:var(--fs-body);color:var(--ink);font-variant-numeric:tabular-nums}',
    '.bd-text{width:100%;min-height:44px;padding:8px 12px;border-radius:8px;border:1px solid color-mix(in srgb,var(--ink-sheet-2) 40%,transparent);background:transparent;color:var(--ink);font:var(--fs-body)/1.25 var(--font);box-sizing:border-box}',
    '.bd-tgl{display:flex;align-items:center;justify-content:space-between;gap:12px;min-height:44px;font-size:var(--fs-body);color:var(--ink);width:100%}',
    '.bd-status{background:var(--sheet-cell);border-radius:var(--radius-tile);padding:16px;display:flex;flex-direction:column;gap:4px;color:var(--ink);min-width:0}',
    '.bd-status .lb{display:flex;align-items:center;gap:6px;font-size:var(--fs-sub);color:var(--ink-sheet-2)}',
    '.bd-status .vl{font:600 var(--fs-t3)/1.25 var(--font);font-variant-numeric:tabular-nums}',
    '.bd-dial{position:relative;margin:0 auto;width:var(--d);max-width:100%}',
    '.bd-dial svg{display:block;width:100%;overflow:visible;filter:drop-shadow(0 10px 14px rgba(0,0,0,.18))}',
    '.bd-dial.inactive svg{opacity:.45;filter:saturate(0) drop-shadow(0 10px 14px rgba(0,0,0,.18))}',
    '.bd-dial .mid{position:absolute;left:19%;right:19%;top:19%;bottom:19%;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:4px;text-align:center;overflow:hidden}',
    '.bd-dial .act{font:700 min(var(--fs-sub),calc(var(--d)*.058))/1.2 var(--font);color:var(--ink-sheet-2);white-space:nowrap}',
    '.bd-dial .big{font:300 min(calc(var(--fs-lt)*2.235),calc(var(--d)*.27))/1.05 var(--font-d);font-variant-numeric:tabular-nums;color:var(--ink);white-space:nowrap}',
    '.bd-dial .cap{display:flex;align-items:center;gap:4px;font:700 min(var(--fs-foot),calc(var(--d)*.05))/1.2 var(--font);color:var(--ink-sheet-2);white-space:nowrap}',
    '.bd-handle{transition:transform var(--t-quick) var(--ease-quick)}.bd-mark{transition:transform var(--t-quick) var(--ease-quick)}',
    '.k-reduce-motion .bd-handle,.k-reduce-motion .bd-mark{transition:none}',
    '.bd-as{width:calc(100% - 16px);max-width:560px;display:flex;flex-direction:column;gap:8px;margin:0 8px 8px}',
    '.bd-as.pop{width:300px;margin:0;gap:0}',
    '.bd-as .grp{border-radius:26px;background:rgba(44,44,46,.94);overflow:hidden;color:#fff;box-shadow:0 12px 40px rgba(0,0,0,.4)}.g-light .bd-as .grp{background:rgba(250,250,252,.96);color:#000}',
    '.bd-as .tt{padding:14px 16px;text-align:center;font:600 var(--fs-foot)/1.3 var(--font);color:rgba(235,235,245,.6)}.g-light .bd-as .tt{color:rgba(60,60,67,.76)}',
    '.bd-as button{display:block;width:100%;min-height:56px;border:0;border-top:.5px solid rgba(128,128,128,.4);background:none;font:400 var(--fs-body)/1.2 var(--font);color:#0A84FF;cursor:pointer;padding:8px 16px}',
    '.g-light .bd-as button{color:#0066CC}.bd-as button.destructive{color:#FF6961;font-weight:600}.g-light .bd-as button.destructive{color:#C21717}',
    '.bd-as .tt+button{border-top:.5px solid rgba(128,128,128,.4)}.bd-as .grp button:first-child{border-top:0}.bd-as .cancel button{border-top:0;font-weight:600}',
    '.bd-note{font-size:var(--fs-foot);color:var(--ink-sheet-2)}',
  ].join('\n');
  var st = document.createElement('style'); st.id = 'bedroom-motion-css'; st.textContent = CSS; document.head.appendChild(st);

  /* ------------------------------------------------------------------ vocabulary */
  var DAYS = ['sunday', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday'];
  B.DAYS = DAYS; B.WORKDAYS = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday']; B.WEEKEND = ['sunday', 'saturday'];
  B.dayLabel = function (d) { return d.charAt(0).toUpperCase() + d.slice(1); };
  B.dayShort = function (d) { return B.dayLabel(d).slice(0, 3); };
  /** ClockTime.display: 06:30 -> 6:30 AM */
  B.clock = function (v) { var q = v.split(':'), hr = +q[0] % 24; return (hr % 12 || 12) + ':' + q[1] + ' ' + (hr >= 12 ? 'PM' : 'AM'); };
  /** BedLevel.format: +3, 0, -2.5, -- */
  B.level = function (v) { if (v == null) return '--'; var t = v === Math.round(v) ? String(v) : v.toFixed(1); return v > 0 ? '+' + t : t; };
  B.temp = function (v) { return v == null ? '--°F' : (v === Math.round(v) ? v : v.toFixed(1)) + '°F'; };
  function cap(s) { return s.charAt(0).toUpperCase() + s.slice(1); }
  /** WakeLight.scheduleLabel for a weekly alarm. */
  B.scheduleLabel = function (a) {
    if (a.kind === 'once') return a.dateLabel || 'Oct 24, 2026';
    var d = DAYS.filter(function (x) { return a.days.indexOf(x) >= 0; });
    if (d.length === 7) return 'Every Day';
    if (d.join() === B.WORKDAYS.join()) return 'Weekdays';
    if (d.join() === B.WEEKEND.join()) return 'Weekends';
    return d.map(B.dayShort).join(', ');
  };

  /* ------------------------------------------------------------------ small controls */
  B.section = function (title, detail) { return h('div.bd-sec', h('h2.t', title), detail ? h('p.d', detail) : null); };
  B.card = function (kids) { return h('div.bd-card', kids); };
  B.notice = function (o) {
    var sym = { info: 'info.circle.fill', warning: 'exclamationmark.triangle.fill', error: 'xmark.octagon.fill', success: 'checkmark.circle.fill' }[o.tone || 'warning'];
    return h('div.bd-notice.' + (o.tone || 'warning'), { role: 'group', 'aria-label': (o.title ? o.title + '. ' : '') + o.message }, h('span', { html: I(sym, { fill: true }) }), h('div', o.title ? h('b', o.title) : null, h('p', o.message)));
  };
  /** BedroomRow. o: {symbol, title, lines[], muted, trailing:Node, button:boolean} */
  B.row = function (o) {
    var tag = o.button === false ? 'div' : 'button';
    var attrs = tag === 'button' ? { type: 'button' } : {};
    return h(tag + '.bd-row' + (o.muted ? '.muted' : ''), attrs, h('span.gl', { html: I(o.symbol, { fill: false }) }), h('span.tx', h('span.ti', o.title), (o.lines || []).map(function (l) { return h('span.ln', l); })), o.trailing ? h('span.ac', o.trailing) : null);
  };
  B.chev = function () { return h('span', { html: I('chevron.right', { weight: 2.4 }), 'aria-hidden': 'true' }); };
  B.toggle = function (on, label, disabled) { var t = K.Toggle({ on: on, label: label }); if (disabled) { t.disabled = true; t.style.opacity = .4; } return t; };
  B.primary = function (title, o) { o = o || {}; return K.PrimaryButton({ title: title, symbol: o.symbol, disabled: o.disabled }); };
  B.danger = function (title, disabled) { var b = h('button.bd-danger', { type: 'button' }, title); if (disabled) b.disabled = true; return b; };
  B.capsule = function (label, o) {
    o = o || {};
    var b = h('button.bd-cap' + (o.stack ? '.stack' : '') + (o.flex ? '.flex' : ''), { type: 'button', 'aria-label': o.aria }, o.symbol ? h('span', { html: I(o.symbol) }) : null, h('span', label), o.sub ? h('small', o.sub) : null);
    if (o.disabled) b.disabled = true; return b;
  };
  B.stepper = function (label, symbol, disabled) {
    var b = h('button.bd-step', { type: 'button', 'aria-label': label, title: label, html: I(symbol, { weight: 2.2 }) }); if (disabled) b.disabled = true; return b;
  };
  /** DynamicGridLayout with the column rule applied as the app does: floor((w + gap) / (min + gap)) columns, clamped to max, and one full-width column when a
   *  single minimum (scaled at AX5) is wider than the container. The kit's TileGrid keeps a track at its minimum even then and overflows; this wraps min in
   *  min(100%, ...). Pure CSS, so it needs no layout pass. Promote to kit. */
  B.grid = function (items, min, max, fill) {
    var g = K.TileGrid({ items: items, min: min, max: max, equal: false, fill: fill });
    g.style.gridTemplateColumns = 'repeat(auto-fill, minmax(max(min(100%, calc(var(--min) * var(--sc))), calc((100% - (var(--max) - 1) * var(--gap)) / var(--max))), 1fr))';
    return g;
  };
  B.field = function (label, node, o) { return h('div.bd-field' + (o && o.off ? '.off' : ''), { role: 'group', 'aria-label': label }, h('p.bd-lb', label), node); };
  /** ChoiceGrid: single-choice tiles in a DynamicGridLayout (min 120 pt scaled, max 5). */
  B.choiceGrid = function (title, options, selected, o) {
    o = o || {};
    var items = options.map(function (v) { return h('button.bd-choice' + (v === selected ? '.sel' : ''), { type: 'button', 'aria-pressed': v === selected ? 'true' : 'false', 'aria-label': v }, v === selected ? [h('span', { 'aria-hidden': 'true', style: { marginRight: '4px', fontWeight: 700 } }, '\u2713'), v] : v); });
    return B.field(title, B.grid(items, 120, 5, 'none'), { off: o.disabled });   // choice chips keep one size (duo-widths rule 4)
  };
  /** WeekdayPicker: capsules in a DynamicGridLayout (min 52 pt scaled, max 7). */
  B.weekdayPicker = function (title, days) {
    var items = DAYS.map(function (d) { var on = days.indexOf(d) >= 0; return h('button.bd-choice.cap' + (on ? '.sel' : ''), { type: 'button', 'aria-label': B.dayLabel(d), 'aria-pressed': on ? 'true' : 'false' }, on ? [h('span', { 'aria-hidden': 'true', style: { marginRight: '2px', fontWeight: 700 } }, '\u2713'), h('b', null, B.dayShort(d))] : B.dayShort(d)); });
    return B.field(title, B.grid(items, 52, 7));
  };
  B.clockField = function (title, value) { return h('div.bd-clock', { role: 'group', 'aria-label': title + ': ' + value }, h('span', title), h('span.bd-pill', value)); };
  B.textField = function (label, value) { return B.field(label, h('input.bd-text', { type: 'text', value: value, 'aria-label': label })); };
  B.tglRow = function (label, on, disabled) { return h('div.bd-tgl', h('span', label), B.toggle(on, label, disabled)); };
  B.statusCard = function (r) { return h('div.bd-status', { role: 'group', 'aria-label': r.title + ', ' + r.value }, h('div.lb', h('span', { html: I(r.symbol) }), r.title), h('div.vl', r.value)); };

  /* ------------------------------------------------------------------ bed model (BedSideController) */
  /** A bed side's state, derived like BedSideController. o overrides: available, on, target, current, phase, stages, hotFlash, hotFlashLeft, alarmState,
   *  snooze, alarmsAvailable, scope ('whole'|'traveler'), error, alarms, readings, pumpProblem, name... */
  B.bed = function (side, o) {
    var left = side === 'left';
    var m = {
      side: side, title: left ? "Alex's Bed" : "Sam's Bed", name: left ? 'Alex' : 'Sam', other: left ? 'Sam' : 'Alex',
      available: true, on: true, target: left ? 3 : -3, current: left ? 86.5 : 79, phase: left ? 'asleep' : 'outside',
      stages: { bedtime: left ? 4 : -2, asleep: left ? 3 : -3, dawn: left ? 1 : -1 },
      hotFlash: false, hotFlashLeft: '10:12', hotFlashAvailable: true, alarmState: 'idle', snooze: '4:12', alarmsAvailable: true, scope: null, error: null,
      alarms: left
        ? B.WORKDAYS.map(function (d) { return { day: d, time: '06:30', enabled: true }; }).concat([{ day: 'saturday', time: '08:00', enabled: false }, { day: 'saturday', time: '09:15', enabled: true }])
        : ['monday', 'wednesday', 'friday'].map(function (d) { return { day: d, time: '07:15', enabled: true }; }),
      readings: left ? { 'Current Temp': '86.5°F', 'Pump Status': 'OK', 'Loop Temp': '91.2°F', 'Pump RPM': '2140 rpm', 'Heart Rate': '58 bpm', 'Breathing': '14 br/min', 'HRV': '48 ms' }
                     : { 'Current Temp': '79°F', 'Pump Status': 'OK', 'Loop Temp': '73.8°F', 'Pump RPM': '1980 rpm', 'Heart Rate': '62 bpm', 'Breathing': '15 br/min', 'HRV': '52 ms' },
    };
    if (o) Object.keys(o).forEach(function (k) { m[k] = o[k]; });
    var interactive = m.scope !== 'traveler';
    m.interactive = interactive;
    m.isOn = m.available && m.on;
    var tgt = m.hotFlash ? -10 : m.target;
    m.shownTarget = tgt;
    m.action = !m.isOn ? 'off' : tgt > .5 ? 'heating' : tgt < -.5 ? 'cooling' : 'idle';
    m.currentLevel = m.current == null ? null : Math.max(-10, Math.min(10, ((m.current - 82.5) / 27.5) * 10));
    m.subtitle = m.hotFlash ? 'Hot Flash Mode' : !m.isOn ? 'Off' : cap(m.action) + ' • ' + B.level(tgt);
    m.sheetTitle = m.scope === 'whole' ? m.title + ' · Whole Bed' : m.title;
    m.hint = !m.available ? 'Bed controls are unavailable.' : !interactive ? 'Away · Read Only' : !m.isOn ? 'Use the power control to turn on the Pod.'
      : m.phase == null ? 'Schedule phase is unavailable.' : m.hotFlash ? 'Hot Flash Mode controls the target.' : 'Drag the dial to set the target.';
    m.powerTitle = !interactive ? 'Away · Read Only' : !m.available ? 'Unavailable' : m.isOn ? 'Turn Off' : 'Turn On';
    m.canTogglePower = m.available && interactive;
    m.canSetTarget = m.available && interactive && m.isOn && !m.hotFlash && tgt != null && m.phase != null;
    m.alarmActive = m.alarmState === 'ringing' || m.alarmState === 'snoozed';
    m.alarmsEditable = m.alarmsAvailable && interactive;
    var ts = m.subtitle;
    if (m.scope === 'traveler') ts = 'Away · Read Only';
    else { if (m.hotFlash) ts = 'Hot Flash Mode • Cooling'; if (m.scope === 'whole') ts = 'Whole Bed • ' + ts; }
    m.tileSubtitle = ts;
    /* ThermostatTileFace.bedSide */
    var levelFam = (tgt == null ? 0 : tgt) < 0 ? 'cooling' : 'heating';
    m.face = !m.available ? { family: 'neutral', active: false } : m.action === 'heating' ? { family: 'heating', active: true } : m.action === 'cooling' ? { family: 'cooling', active: true }
      : m.action === 'off' ? { family: levelFam, active: false } : { family: levelFam, active: true };
    m.notice = null;
    if (m.scope === 'whole') m.notice = { tone: 'success', title: m.other + ' Away', message: 'While ' + m.other + ' is away from home and the Solo Trip setting is enabled in settings, these controls and alarms control the entire bed.' };
    if (m.scope === 'traveler') m.notice = { tone: 'info', title: m.name + ' Away', message: 'This traveler bed side is view-only during an active Solo Trip. Make changes from ' + m.other + "'s bed side." };
    m.groups = DAYS.map(function (d) { return { day: d, alarms: m.alarms.filter(function (a) { return a.day === d; }) }; }).filter(function (g) { return g.alarms.length; });
    m.groups.forEach(function (g) {
      var en = g.alarms.filter(function (a) { return a.enabled; }).length, dis = g.alarms.length - en;
      g.enabled = en; g.title = B.dayLabel(g.day) + (g.alarms.length === 1 ? ' Alarm' : ' Alarms');
      g.summary = g.alarms.length === 1 ? (en ? 'Enabled' : 'Disabled') : [en ? en + ' Enabled' : null, dis ? dis + ' Disabled' : null].filter(Boolean).join(' • ');
    });
    return m;
  };

  /** The bed side's room tile (the room page's RoomCardView/RoomCardTile; BedSideTile is gone). Rollout R: a navigation tile with a toggle-styled Power disc (BedSidePowerActions);
      turning off asks "Turn off <bed>?" in a confirmation dialog; the traveler's side on a Solo Trip dims the disc. */
  B.bedTile = function (m) {
    var on = m.face.active && m.scope !== 'traveler';
    return K.GlassTile({ title: m.title, subtitle: m.tileSubtitle, symbol: 'bed.double', family: m.face.family === 'neutral' ? 'neutral' : m.face.family, isActive: on, kind: 'navigate',
      behavior: 'navigate', actions: [{ id: 'power', symbol: 'power', label: (on ? 'Turn Off ' : 'Turn On ') + m.title, on: on, dim: m.scope === 'traveler' || m.available === false }] });
  };

  /* ------------------------------------------------------------------ wake light model (WakeLightController, WakeLight.subtitle) */
  B.wake = function (o) {
    var w = {
      title: 'Wake-Light Alarms', available: true, compatible: true, canEdit: true, phase: 'scheduled', brightness: 0, nextWake: '10/24 6:45 AM', nextRamp: 30, vacation: 'off',
      blockers: [], defaults: { ramp: 30, hold: 10 }, holdSupported: true, contractVersion: 6, active: [], error: null, stopping: false,
      alarms: [
        { id: 'weekday', label: 'Weekday Wake', kind: 'weekly', days: B.WORKDAYS, time: '06:45', enabled: true, ramp: 30, native: true },
        { id: 'weekend', label: 'Weekend Sleep-In', kind: 'weekly', days: B.WEEKEND, time: '08:30', enabled: false, ramp: 15, native: true },
        { id: 'sleepypod-left', label: "Alex's Alarm", kind: 'weekly', days: B.WORKDAYS, time: '06:30', enabled: true, ramp: 30, native: false, linked: true, side: 'left' },
        { id: 'sleepypod-right', label: "Sam's Alarm", kind: 'weekly', days: ['monday', 'wednesday', 'friday'], time: '07:15', enabled: true, ramp: 30, native: false, linked: false, side: 'right' },
      ],
    };
    if (o) Object.keys(o).forEach(function (k) { w[k] = o[k]; });
    var any = w.alarms.some(function (a) { return a.enabled; });
    var phaseLabel = { recovering: 'Waiting to Resume', snoozed: 'Holding Brightness' };
    w.subtitle = function (modal) {
      if (!w.available) return 'Setup · Unavailable';
      if (w.phase === 'recovering' || w.phase === 'snoozed') return phaseLabel[w.phase];
      if (w.phase === 'ramping' || w.phase === 'holding') return 'Active • ' + Math.round(w.brightness) + '%';
      if (!any) return modal ? 'No Active Wake-Light Alarms' : 'Alarms · None Enabled';
      if (w.vacation !== 'off') return 'Vacation Mode · Runs Blocked';
      if (w.blockers.length) return 'Execution Blocked';
      if (w.nextWake) return 'Next Alarm: ' + w.nextWake + (w.nextRamp != null ? ' • ' + w.nextRamp + ' min ramp' : '');
      return 'Idle';
    };
    return w;
  };
  B.wakeTile = function (w) {
    return K.GlassTile({ title: w.title, subtitle: w.subtitle(false), symbol: 'sunrise', family: 'lights', isActive: w.available && w.alarms.some(function (a) { return a.enabled; }), kind: 'navigate' });
  };
  B.rampLabel = function (n) { return n === 0 ? 'None' : n + ' min'; };
  B.durationLabel = function (n) { return n === 0 ? 'None' : n + ' Minutes'; };
  B.RAMPS = [0, 5, 10, 15, 30]; B.HOLDS = [5, 10, 15, 30];

  /* ------------------------------------------------------------------ the dial (ThermostatDial with the signed-level scale) */
  function pt(deg, r) { var a = deg * Math.PI / 180; return [160 + r * Math.cos(a), 160 + r * Math.sin(a)]; }
  function arc(d0, d1) { var a = pt(d0, 145), b = pt(d1, 145); return 'M' + a[0].toFixed(2) + ' ' + a[1].toFixed(2) + ' A145 145 0 ' + (d1 - d0 > 180 ? 1 : 0) + ' 1 ' + b[0].toFixed(2) + ' ' + b[1].toFixed(2); }
  function degFor(v) { return 135 + Math.max(0, Math.min(1, (v + 10) / 20)) * 270; }
  var HEAT = '#CD5401', COOL = '#2C8E98';
  /** Dial for a bed model: 270-degree track, one handle (white disc, rim by status) at the target, the current-level marker, readout without a unit. */
  B.dial = function (m, o) {
    o = o || {};
    var size = o.size || 300, status = m.action, tint = status === 'heating' ? HEAT : status === 'cooling' ? COOL : 'var(--ink-sheet-2)';
    var inactive = !m.available || (!m.isOn && !m.hotFlash);
    var svg = '<svg viewBox="0 0 320 320" aria-hidden="true"><path d="' + arc(135, 405) + '" fill="none" stroke-width="24" stroke-linecap="round" style="stroke:color-mix(in srgb, var(--ink) 16%, transparent)"/>';
    if (m.available && m.currentLevel != null) { var q = pt(degFor(m.currentLevel), 145); svg += '<g class="bd-mark" style="transform:translate(' + q[0].toFixed(2) + 'px,' + q[1].toFixed(2) + 'px)"><circle r="9" fill="' + tint + '" stroke="#141414" stroke-width="3"/></g>'; }
    var handle = m.canSetTarget && m.shownTarget != null;
    if (handle) { var k = pt(degFor(m.shownTarget), 145); svg += '<g class="bd-handle" style="transform:translate(' + k[0].toFixed(2) + 'px,' + k[1].toFixed(2) + 'px)"><circle r="14" fill="#fff" stroke="' + tint + '" stroke-width="4" style="filter:drop-shadow(0 4px 6px rgba(0,0,0,.22))"/></g>'; }
    svg += '</svg>';
    var act = !m.available ? 'Unavailable' : m.hotFlash ? 'Hot Flash' : m.isOn ? cap(m.action) : 'Off';
    var big = !m.available ? '--' : m.isOn ? B.level(m.shownTarget) : 'OFF';
    var capt = m.available && m.current != null ? 'Currently ' + B.temp(m.current) : null;
    var label = m.title + ', ' + (!m.available ? 'Unavailable' : m.isOn ? cap(m.action) + ', target ' + B.level(m.shownTarget) : 'Off') + (m.available && m.current != null ? ', currently ' + B.temp(m.current) : '');
    var el = h('div.bd-dial' + (inactive ? '.inactive' : ''), { role: 'group', 'aria-label': label, style: { '--d': (size + 40) + 'px' }, dataset: { target: m.shownTarget, status: status } },
      h('div', { html: svg, style: { padding: '20px', boxSizing: 'border-box' } }),
      h('div.mid', { style: { left: '23%', right: '23%', top: '23%', bottom: '23%' } }, h('span.act', act), h('span.big', big), capt ? h('span.cap', h('span', { html: I('thermometer.medium', { size: '1em' }) }), capt) : null));
    if (handle) el.appendChild(h('div', { role: 'slider', tabindex: '0', 'aria-label': m.title + ' target level', 'aria-valuemin': -10, 'aria-valuemax': 10, 'aria-valuenow': m.shownTarget, 'aria-valuetext': B.level(m.shownTarget), style: { position: 'absolute', width: 0, height: 0, overflow: 'hidden' } }));
    return el;
  };
  /** Moves the dial's handle, marker colour and readout to a new target (a Play helper; the app animates this on `quick`, none under Reduce Motion). */
  B.dialTo = function (el, value, m) {
    var hd = el.querySelector('.bd-handle'); if (!hd) return;
    var k = pt(degFor(value), 145); hd.style.transform = 'translate(' + k[0].toFixed(2) + 'px,' + k[1].toFixed(2) + 'px)';
    var action = value > .5 ? 'heating' : value < -.5 ? 'cooling' : 'idle', tint = action === 'heating' ? HEAT : action === 'cooling' ? COOL : 'var(--ink-sheet-2)';
    hd.firstChild.setAttribute('stroke', tint); var mk = el.querySelector('.bd-mark circle'); if (mk) mk.setAttribute('fill', tint);
    el.querySelector('.act').textContent = cap(action); el.querySelector('.big').textContent = B.level(value);
  };

  /* ------------------------------------------------------------------ the bed sheet's content */
  B.activeAlarm = function (m) {
    if (!m.alarmActive) return null;
    var snoozed = m.alarmState === 'snoozed';
    return h('div.bd-card', { role: 'group', 'aria-label': 'Alarm Active, ' + (snoozed ? 'Snoozing' : 'Ringing') }, B.section('Alarm Active', snoozed ? 'Snoozing' : 'Ringing'),
      h('div.bd-btns', B.capsule('Snooze', { symbol: 'zzz', stack: snoozed, flex: true, sub: snoozed ? m.snooze + ' Remaining' : null, disabled: snoozed || !m.interactive }),
        K.PrimaryButton({ title: 'Stop Alarm', symbol: 'stop.circle', disabled: !m.interactive })));
  };
  B.hero = function (m) {
    return h('div.bd-stack', { style: { gap: '16px', alignItems: 'center', textAlign: 'center' } },
      h('p.bd-sub', m.subtitle),
      !m.available ? B.notice({ tone: 'warning', message: 'Bed controls are unavailable. No changes can be made until the active bed connection recovers.' }) : null,
      m.notice ? B.notice(m.notice) : null,
      m.error ? B.notice({ tone: 'error', message: m.error }) : null,
      B.dial(m),
      m.interactive ? B.capsule(m.powerTitle, { symbol: 'power', disabled: !m.canTogglePower }) : null,
      h('p.bd-foot', m.hint),
      B.activeAlarm(m));
  };
  B.temperatureTab = function (m) {
    var phases = [['bedtime', 'Bedtime', 'bed.double'], ['asleep', 'Asleep', 'moon'], ['dawn', 'Dawn', 'sun.max']];
    return h('div.bd-stack', B.section('Sleep Schedule', 'Recurring levels for each stage of the night.'), phases.map(function (ph) {
      var lvl = m.stages[ph[0]], on = m.available && m.interactive, now = m.phase === ph[0];
      var r = B.row({ symbol: ph[2], title: ph[1], lines: [now ? B.level(lvl) + ' · Now' : B.level(lvl)], button: false, trailing: [B.stepper('Lower ' + ph[1], 'minus', !on || lvl <= -10), B.stepper('Raise ' + ph[1], 'plus', !on || lvl >= 10)] });
      r.setAttribute('role', 'group'); r.setAttribute('aria-label', ph[1] + ' level, ' + B.level(lvl)); return r;
    }));
  };
  B.specialModesTab = function (m) {
    var unavailable = !m.hotFlashAvailable || m.scope === 'traveler';
    /* Rollout R (item 13): an action tile (text . disc, HotFlashActions): a snowflake disc starts it and becomes a stop disc while it runs; the body does what the disc shows, so a tap on
       the running tile cancels. The countdown is the tile's state line; the separate cancel button is gone. */
    var tile = K.GlassTile({ title: 'Hot Flash Mode', subtitle: !m.hotFlashAvailable ? 'Unavailable' : m.hotFlash ? (m.hotFlashLeft ? m.hotFlashLeft + ' Remaining' : 'Cooling Bed') : 'Inactive', symbol: 'snowflake', family: 'cooling', isActive: m.hotFlash, isUnavailable: unavailable, kind: 'command',
      behavior: 'perform', actions: [{ id: 'hot_flash', symbol: m.hotFlash ? 'stop.fill' : 'snowflake', label: m.hotFlash ? 'Cancel Hot Flash Mode' : 'Start Hot Flash Mode', dim: unavailable }] });
    tile.style.flex = '1'; tile.style.minWidth = 0;
    var row = h('div', { style: { display: 'flex', gap: '12px', alignItems: 'center', width: '100%' } }, tile);
    return h('div.bd-stack', B.section('Special Modes', 'Activating hot flash mode will set the bed to -10 for fifteen minutes.'), row);
  };
  B.alarmRows = function (m, o) {
    o = o || {};
    return m.groups.map(function (g) {
      var single = g.alarms.length === 1;
      return B.row({ symbol: g.enabled > 0 ? 'alarm' : 'alarm.waves.left.and.right', title: g.title, lines: [g.alarms.map(function (a) { return B.clock(a.time); }).join(', '), g.summary], muted: g.enabled === 0,
        trailing: single ? B.toggle(g.alarms[0].enabled, B.dayLabel(g.day) + ' ' + B.clock(g.alarms[0].time) + ' alarm', !m.alarmsEditable) : B.chev() });
    });
  };
  B.alarmsTab = function (m) {
    return h('div.bd-stack', B.section('Alarms'),
      !m.alarmsAvailable ? B.notice({ tone: 'warning', message: 'Home Assistant alarm schedule data is unavailable.' }) : (!m.alarms.length ? h('p.bd-sub', 'No alarms yet. Add one to choose days and a time.') : null),
      B.alarmRows(m), B.primary('Add Alarm', { symbol: 'plus', disabled: !m.alarmsEditable }));
  };
  B.statusTab = function (m) {
    var order = [['Current Temp', 'thermometer.medium'], ['Pump Status', 'drop'], ['Loop Temp', 'arrow.triangle.2.circlepath'], ['Pump RPM', 'gauge.with.dots.needle.33percent'], ['Heart Rate', 'heart'], ['Breathing', 'lungs'], ['HRV', 'waveform.path.ecg']];
    var items = order.map(function (r) { return B.statusCard({ title: r[0], symbol: r[1], value: !m.available ? 'Unavailable' : (r[0] === 'Pump Status' && m.pumpProblem ? 'Check pump' : m.readings[r[0]]) }); });
    return h('div.bd-stack', B.section('Status'), B.grid(items, 150, 3));
  };
  B.TABS = [{ id: 'temperature', title: 'Temperature', symbol: 'thermometer.medium' }, { id: 'special-modes', title: 'Special Modes', symbol: 'snowflake' }, { id: 'alarms', title: 'Alarms', symbol: 'alarm' }, { id: 'status', title: 'Status', symbol: 'info.circle' }];
  B.tabBody = function (tab, m) { return { temperature: B.temperatureTab, 'special-modes': B.specialModesTab, alarms: B.alarmsTab, status: B.statusTab }[tab](m); };
  /** Two columns only where the window may split (landscape, regular width) and the sheet is at least 640 pt (MediaRemoteLayout.usesTwoColumns). */
  B.twoColumns = function (ctx) { return ctx.regular && ctx.w > ctx.h; };
  B.bedContent = function (ctx, m, tab) {
    if (B.twoColumns(ctx)) return h('div.bd-two', { dataset: { layout: 'bed.layout.twoColumn' } }, h('div', B.hero(m)), h('div', B.tabBody(tab, m)));
    return h('div.bd-col', { dataset: { layout: 'bed.layout.singleColumn' } }, B.hero(m), B.tabBody(tab, m));
  };

  /* ------------------------------------------------------------------ wake light content */
  B.wakeRows = function (w) {
    return w.alarms.map(function (a) {
      var editable = w.canEdit && w.available;
      if (a.native) return B.row({ symbol: a.enabled ? 'alarm' : 'alarm.waves.left.and.right', title: a.label, lines: [B.scheduleLabel(a) + ' · ' + B.clock(a.time), 'Ramp: ' + B.rampLabel(a.ramp)], muted: !a.enabled, trailing: B.toggle(a.enabled, a.label, !editable) });
      var side = a.side === 'left' ? "Alex's" : "Sam's";
      return h('div.bd-stack.s', B.row({ symbol: 'bed.double', title: a.label, lines: [B.scheduleLabel(a) + ' · ' + B.clock(a.time)], muted: !a.enabled || !a.linked, trailing: B.toggle(a.linked, 'Use room wake lights for the ' + a.label + ' alarm', !editable), button: false }),
        h('button.bd-link', { type: 'button' }, h('span', { html: I('arrow.up.forward.app') }), 'Open Linked-Device Alarm Editor'));
    });
  };
  B.wakeAlarmsTab = function (w) {
    var kids = [];
    if (w.active.length) kids.push(h('div.bd-card', B.section('Active Wake-Light Controls', 'Stopping ends this wake for the room and leaves the lights as they are.'),
      w.active.map(function (a) { return h('p', { style: { margin: 0, fontSize: 'var(--fs-sub)', color: 'var(--ink)' } }, a.label + ' · ' + a.wakeAt); }), B.danger(w.stopping ? 'Stopping Wake Lights…' : 'Stop Wake-Light Episode', w.stopping || !w.available)));
    w.blockers.forEach(function (b) { kids.push(B.notice({ tone: 'warning', message: b })); });
    kids.push(h('div.bd-stack', B.section('Wake Alarm Schedule'), !w.alarms.length ? h('p.bd-sub', 'No wake alarms yet.') : null, B.wakeRows(w),
      w.canEdit ? B.primary('Add Wake Alarm', { symbol: 'plus', disabled: !w.available }) : h('p.bd-foot', 'Only Home Assistant administrators can edit wake alarms.')));
    return kids;
  };
  B.wakeDefaultsTab = function (w) {
    var editable = w.canEdit && w.available;
    return h('div.bd-stack', { style: { gap: '24px' } }, B.section('Wake-Light Defaults', 'New wake alarms start with this light ramp.'),
      B.choiceGrid('Light Ramp Duration', B.RAMPS.map(B.durationLabel), B.durationLabel(w.defaults.ramp), { disabled: !editable }),
      B.choiceGrid('Post-Wake Hold Time', B.HOLDS.map(B.durationLabel), B.durationLabel(w.defaults.hold), { disabled: !editable || !w.holdSupported }),
      h('p.bd-foot', w.holdSupported ? 'How long the lights stay at full brightness after the wake time before normal lighting resumes.' : 'Post-wake hold requires a wake light integration update.'));
  };
  B.WAKE_TABS = [{ id: 'alarms', title: 'Wake Alarms', symbol: 'alarm' }, { id: 'defaults', title: 'Defaults', symbol: 'slider.vertical.3' }];
  B.wakeContent = function (w, tab) {
    var alerts = [];
    if (!w.compatible) alerts.push(B.notice({ tone: 'warning', message: 'Editing wake light alarms requires an integration update. Saved alarms remain available to view.' }));
    else if (!w.available) alerts.push(B.notice({ tone: 'warning', message: 'Wake-light controls are unavailable. Check Home Assistant, then try again.' }));
    if (w.error) alerts.push(B.notice({ tone: 'error', message: w.error }));
    return h('div.bd-col.wide', h('p.bd-sub', w.subtitle(true)), alerts, tab === 'defaults' ? B.wakeDefaultsTab(w) : B.wakeAlarmsTab(w));
  };

  /* ------------------------------------------------------------------ pushed pages */
  B.dayPage = function (m, day) {
    var alarms = m.alarms.filter(function (a) { return a.day === day; }).sort(function (a, b) { return a.time < b.time ? -1 : 1; });
    return h('div.bd-col', B.activeAlarm(m), h('div.bd-stack', !alarms.length ? h('p.bd-sub', 'No alarms yet. Add one to choose days and a time.') : null,
      alarms.map(function (a) { return B.row({ symbol: a.enabled ? 'alarm' : 'alarm.waves.left.and.right', title: B.clock(a.time), lines: [a.enabled ? 'Enabled' : 'Disabled'], muted: !a.enabled, trailing: B.toggle(a.enabled, B.dayLabel(a.day) + ' ' + B.clock(a.time) + ' alarm', !m.alarmsEditable) }); }),
      B.primary('Add Alarm', { symbol: 'plus', disabled: !m.alarmsEditable })));
  };
  /** BedAlarmEditor. o: {m, day (locked day), days (draft days), time, editing:boolean, enabled, wake (Use Room Wake Lights), saving, problems[], wakeError} */
  B.bedEditor = function (o) {
    var m = o.m, editing = !!o.editing, locked = !!o.day, days = o.days || (locked ? [o.day] : B.WORKDAYS);
    var problems = o.problems || [];
    return h('div.bd-col', B.activeAlarm(m), o.wakeError ? B.notice({ tone: 'error', message: o.wakeError }) : null,
      locked ? null : B.weekdayPicker('Days', days), B.clockField('Time', B.clock(o.time || '07:00')),
      editing ? B.tglRow('Alarm Enabled', o.enabled !== false) : null, B.tglRow('Use Room Wake Lights', o.wake !== false),
      problems.map(function (t) { return B.notice({ tone: 'warning', message: t }); }),
      B.primary(o.saving ? 'Saving…' : 'Save', { disabled: o.saving || problems.length > 0 }), editing ? B.danger('Delete', o.saving || !m.alarmsEditable) : null);
  };
  B.bedEditorTitle = function (m, o) { return o.editing ? m.title + ' ' + B.dayLabel(o.day) + ' Alarm' : (o.day ? 'Add ' + m.title + ' ' + B.dayLabel(o.day) + ' Alarm' : 'Add ' + m.title + ' Alarm'); };
  /** WakeLightEditor. o: {w, alarm (existing alarm or null), kind, days, time, name, ramp, enabled, beds:{left,right}, saving, problems[], error, stale} */
  B.wakeEditor = function (o) {
    var w = o.w, isNew = !o.alarm, kind = o.kind || 'weekly', days = o.days || B.WORKDAYS;
    var kids = [];
    if (o.error) kids.push(B.notice({ tone: 'error', message: o.error }));
    if (o.stale) kids.push(h('button.bd-link', { type: 'button', style: { color: 'var(--ink-action)' } }, 'Open Latest Alarm, Replace Draft'));
    kids.push(B.field('Alarm Type', K.SegmentedChoice({ options: ['Scheduled', 'One-Time'], selected: kind === 'once' ? 'One-Time' : 'Scheduled', label: 'Alarm Type' })));
    kids.push(B.textField('Alarm Name', o.name != null ? o.name : (isNew ? 'Morning Alarm' : o.alarm.label)));
    if (kind === 'weekly') kids.push(B.weekdayPicker('Days', days));
    kids.push(B.clockField('Wake Time', B.clock(o.time || '07:00')));
    if (kind === 'once') kids.push(h('div.bd-clock', { role: 'group', 'aria-label': 'Alarm Date: Oct 24, 2026' }, h('span', 'Alarm Date'), h('span.bd-pill', 'Oct 24, 2026')));
    kids.push(B.choiceGrid('Light Ramp Duration', B.RAMPS.map(B.durationLabel), B.durationLabel(o.ramp != null ? o.ramp : 30)));
    kids.push(B.tglRow('Wake Alarm Enabled', o.enabled !== false));
    if (isNew) {
      var once = kind === 'once' && w.contractVersion < 5;
      [["Alex's Bed", true], ["Sam's Bed", true]].forEach(function (b) { kids.push(B.tglRow('Add to ' + b[0], !!(o.beds && o.beds[b[0]]), once || !b[1])); });
      if (once) kids.push(h('p.bd-foot', 'Adding one-time alarms to a bed requires a wake light integration update.'));
    }
    var problems = o.problems || [];
    if (problems.length) kids.push(h('div.bd-stack.s', problems.map(function (t) { return B.notice({ tone: 'warning', message: t }); })));
    kids.push(h('div.bd-stack', B.primary(o.saving ? 'Saving…' : 'Save', { disabled: o.saving || (!isNew && o.pristine) || problems.length > 0 }), isNew ? null : B.danger('Delete', o.saving)));
    return h('div.bd-col.wide', { style: o.saving ? { opacity: .98 } : null }, kids);
  };
  /** The tonight/all-nights sheet (BedTemperatureScopeSheet). */
  B.scopeContent = function (m, phase, target) {
    return h('div.bd-col', { style: { gap: '16px' } }, h('p', { style: { margin: 0, font: '600 var(--fs-sub)/1.3 var(--font)', color: 'var(--ink-sheet-2)' } }, m.title + ' • ' + phase + ' • ' + target),
      h('p', { style: { margin: 0, font: 'var(--fs-body)/1.3 var(--font)', color: 'var(--ink)' } }, 'Choose whether this target applies only to the current night or also becomes the ' + phase + ' setting for future nights.'),
      B.row({ symbol: 'moon.stars', title: 'Tonight', lines: ['Change the current Pod target only.'], trailing: B.chev() }),
      B.row({ symbol: 'calendar', title: 'All Nights', lines: ["Update this schedule stage and tonight's target."], trailing: B.chev() }));
  };

  /* ------------------------------------------------------------------ chrome: the room page behind, sheets, dialogs */
  B.presenter = function (ctx, connection, m) {
    var tiles = [B.wakeTile(B.wake()), B.bedTile(m || B.bed('left')), B.bedTile(B.bed('right'))];
    return Mock.page(ctx, { title: 'Bedroom 1', back: 'Rooms', section: 'home', connection: connection || 'live', body: [K.TileGrid({ items: tiles, min: 150, max: 3 })] });
  };
  /** A confirmationDialog: an action sheet on iPhone, a popover on iPad (anchored to its button; drawn centred here). */
  B.actionSheet = function (ctx, title, buttons) {
    var pop = ctx.regular;
    var grp = h('div.grp', h('div.tt', title), buttons.map(function (b) { return h('button' + (b.role === 'destructive' ? '.destructive' : ''), { type: 'button' }, b.title); }));
    if (pop) return h('div.bd-as.pop', { role: 'dialog', 'aria-label': title }, grp);
    return h('div.bd-as', { role: 'dialog', 'aria-label': title }, grp, h('div.grp.cancel', h('button', { type: 'button' }, 'Cancel')));
  };
  B.placeDialog = function (host, ctx) {
    var s = host.querySelector('.ui-alert-scrim'); if (s && !ctx.regular) { s.style.placeItems = 'end center'; } return host;
  };
  /** A presented sheet over the room page: always the large detent, page size (hassSheet(.page, height: .full)). */
  B.sheet = function (ctx, o) {
    var host = Mock.sheet(ctx, { title: o.title, subtitle: o.subtitle, detent: o.detent || 'large', size: o.size || 'page', leading: o.leading || 'none', trailing: o.trailing || 'close', content: o.content, tabs: o.tabs,
      presenter: o.presenter === null ? null : (o.presenter || B.presenter(ctx, o.connection, o.presenterBed)), alert: o.alert });
    return B.placeDialog(host, ctx);
  };
  B.bedTabs = function (ctx, tab) { return K.ModalTabBar({ tabs: B.TABS, selected: tab, ctx: ctx }); };
  B.wakeTabs = function (ctx, tab) { return K.ModalTabBar({ tabs: B.WAKE_TABS, selected: tab, ctx: ctx }); };
  B.bedSheet = function (ctx, o) {
    o = o || {}; var m = o.m || B.bed(o.side || 'left', o.bed), tab = o.tab || 'temperature';
    var alert = o.power ? B.actionSheet(ctx, 'Turn off ' + m.title + '?', [{ title: 'Turn Off', role: 'destructive' }]) : null;
    return B.sheet(ctx, { title: m.sheetTitle, content: B.bedContent(ctx, m, tab), tabs: B.bedTabs(ctx, tab), connection: o.connection, presenterBed: m, alert: alert, presenter: o.presenter });
  };
  B.wakeSheet = function (ctx, o) {
    o = o || {}; var w = o.w || B.wake(o.wake), tab = o.tab || 'alarms';
    return B.sheet(ctx, { title: w.title, content: B.wakeContent(w, tab), tabs: B.wakeTabs(ctx, tab), connection: o.connection, presenter: o.presenter });
  };
})();
