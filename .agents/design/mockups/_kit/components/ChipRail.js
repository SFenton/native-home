/* ChipRail and StatusChip: the status rail under a page title. apple/Sources/HassDesign/ChipRail.swift, ChipRailLayout.swift, ChipTint.swift and
 * apple/Sources/HassUI/Features/Home/StatusRail.swift (StatusChipButton, StatusChipStyle, StatusChipAppearance). patterns/status-rail.md.
 *
 * Chips are capsules at least 48 pt tall: glyph, title, one-line state; a filled chip draws its fill with a 12% top highlight and full white state text;
 * an idle chip is the neutral thin module. EVERY width scrolls them in one row across the whole page, over a hinge too (owner, 2026-10-26); only an accessibility
 * Dynamic Type size wraps them so every chip is in view; chips start at the leading margin always; a WRAPPED rail with a hinge stops 24 pt short of the fold (ChipRailMetrics.hingeGap).
 * Colours follow the web (direction-g.md "Status chips follow the web"): Lights amber with an orange glyph; Security the mode fill; Climate follows the
 * temperature (the web gradient at the mean of the range, scaled to 73% and darkened until white reads 4.5:1); Air Quality the AQI colour (web teal while
 * unset: #006E63); Occupancy a person glyph, outline when clear, filled with the green only while detected; Contact Sensors read the house (ContactChipState).
 * A fill or glyph colour change cross-fades in 0.6 s (0.2 s reduced), scoped to colour so the capsule never slides.
 *
 * StatusChip props: {title, summary, symbol, family?, isActive?, tint?:{fill,glyph}, dim?, pending?}
 * ChipRail props: {chips:Array<StatusChip props|Node>, ctx?, frame?:{x,w} (the rail's frame in window x; default the whole content), mode?:'auto'|'scroll'|'wrap'}
 * Presets (Mock.chips.*) return StatusChip props with the app's rules applied; see below.
 */
(function () {
  var h = Mock.h, I = Mock.icon, M = Mock.color;
  var STOPS = [[50, [0, 110, 255]], [60, [128, 0, 255]], [68, [0, 200, 120]], [74, [255, 215, 0]], [80, [255, 165, 0]], [85, [255, 0, 0]]];
  /** The web's temperature gradient (RoomOverview.colorFromTemperature): blue 50 F, purple 60, green 68, yellow 74, orange 80, red 85, clamped. */
  function gradient(t) {
    t = Math.min(Math.max(t, 50), 85);
    for (var i = 0; i < STOPS.length - 1; i++) {
      var a = STOPS[i], b = STOPS[i + 1];
      if (t >= a[0] && t <= b[0]) { var r = (t - a[0]) / (b[0] - a[0]); return a[1].map(function (v, k) { return Math.round(v + (b[1][k] - v) * r); }); }
    }
    return STOPS[STOPS.length - 1][1];
  }
  /** ChipTint.fromWeb: fill = colour at 73% darkened until white reads 4.5:1 (also under the 12% highlight); glyph the colour, lifted to 3:1. */
  function fromWeb(rgb, preferred) {
    var fill = M.mix(rgb, [0, 0, 0], .73), white = [255, 255, 255];
    function lifted(f) { return M.mix(white, f, .12); }
    var guard = 0;
    while (M.contrast(white, lifted(fill)) < 4.5 && guard++ < 60) fill = M.mix(fill, [0, 0, 0], .95);
    function reads(g) { return M.contrast(g, fill) >= 3 && M.contrast(g, lifted(fill)) >= 3; }
    var glyph = rgb, amt = 0;
    if (preferred && reads(preferred)) glyph = preferred; else while (!reads(glyph) && amt < 1) { amt += .05; glyph = M.mix(white, rgb, amt); }
    return { fill: M.css(fill), glyph: M.css(glyph) };
  }
  var tintVars = { closed: ['--chip-contact-closed-fill', '--chip-contact-closed-glyph'], home: ['--chip-contact-home-fill', '--chip-contact-home-glyph'], away: ['--chip-contact-away-fill', '--chip-contact-away-glyph'], armed: ['--chip-contact-armed-fill', '--chip-contact-armed-glyph'] };

  /** StatusChipAppearance + HomeConfig.summary, as data. Each returns StatusChip props. */
  var secNames = { armed_home: ['Armed Home', 'sec-home'], armed_away: ['Armed Away', 'sec-away'], armed_night: ['Armed Night', 'sec-night'], disarmed: ['Disarmed', 'sec-disarmed'], triggered: ['Alarm Triggered', 'sec-triggered'], arming: ['Arming', null], unknown: ['Unknown', null] };
  Mock.chips = {
    lights: function (on) { return { title: 'Lights', summary: on ? on + ' On' : 'All Off', symbol: 'lightbulb.2', family: 'lights', isActive: on > 0 }; },
    security: function (state) { var s = secNames[state] || secNames.unknown; return { title: 'Security', summary: s[0], symbol: 'shield', family: s[1], isActive: !!s[1] }; },
    /** range text like "68–72°F"; mean is the number the gradient is read at; colour overrides it (the helper input_text.demo_color_4). */
    climate: function (range, mean, color) { var rgb = color || gradient(mean); return { title: 'Climate', summary: range, symbol: 'thermometer.medium', family: 'climate', isActive: true, tint: fromWeb(rgb, [255, 204, 0]) }; },
    occupancy: function (detected) { return { title: 'Occupancy', summary: detected ? 'Detected' : 'Clear', symbol: 'person', family: 'occupancy', isActive: !!detected }; },
    /** state: 'closed' | 'home' | 'away' | 'armed' (ContactChipState); n = number open. */
    contacts: function (state, n) { var t = tintVars[state] || tintVars.closed; return { title: 'Contact Sensors', summary: state === 'closed' ? 'All Closed' : n + ' Open', symbol: state === 'closed' ? 'door.left.hand.closed' : (state === 'armed' ? 'exclamationmark.triangle' : 'door.left.hand.open'), family: 'contact', isActive: true, tint: { fill: 'var(' + t[0] + ')', glyph: 'var(' + t[1] + ')' } }; },
    /** aqi: "AQI 18–42 · PM2.5 4–9" is the web's summary; color is the AQI helper's rgb array (default web teal -> #006E63 chip). */
    airQuality: function (summary, color) { return { title: 'Air Quality', summary: summary, symbol: 'aqi.medium', family: 'air', isActive: true, tint: color ? fromWeb(color) : { fill: 'var(--chip-air-default)', glyph: 'var(--fam-air-glyph)' } }; },
    unavailable: function (title, symbol) { return { title: title, summary: 'Unavailable', symbol: symbol, isActive: false, dim: true }; },
    /** The Home rail in web order. opts: {lights, security, climate:[range,mean], occupied, contacts:[state,n], aqi:[summary]} */
    home: function (o) {
      o = o || {};
      return [Mock.chips.lights(o.lights == null ? 3 : o.lights), Mock.chips.security(o.security || 'armed_home'), Mock.chips.climate.apply(null, o.climate || ['68–72°F', 70]),
        Mock.chips.occupancy(o.occupied == null ? true : o.occupied), Mock.chips.contacts.apply(null, o.contacts || ['closed', 0]), Mock.chips.airQuality.apply(null, o.aqi || ['AQI 18–42 · PM2.5 4–9'])];
    },
    gradient: gradient, fromWeb: fromWeb,
  };

  function StatusChip(p) {
    var style = {}, filled = false, glyph = 'var(--g-secondary-on-module)', fill = null;
    if (p.tint) { filled = true; fill = p.tint.fill; glyph = p.tint.glyph; }
    else if (p.isActive && p.family && p.family !== 'neutral') {
      filled = true;
      fill = p.family === 'lights' ? 'var(--fam-lights-chip)' : 'var(--fam-' + p.family + '-fill)';
      glyph = { lights: 1, climate: 1, contact: 1, air: 1 }[p.family] ? 'var(--fam-' + p.family + '-glyph)' : '#fff';
    }
    if (filled) { style['--cf'] = fill; style['--cg'] = glyph; }
    var label = p.title + ', ' + p.summary;
    var b = h('button.ui-chip' + (filled ? '.filled' : '') + (p.dim ? '.dim' : '') + (p.pending ? '.pending' : ''), { type: 'button', style: style, 'aria-label': p.pending ? p.title + ', Loading' : label, title: 'Opens ' + p.title, dataset: { chip: p.title } },
      h('span.g', { html: I(p.symbol, { fill: filled }) }), h('span.tx', h('span.ti', p.title), h('span.su', p.summary), p.pending ? h('span.ui-pending', { 'aria-hidden': 'true' }) : null));
    return b;
  }
  var CHIP_VARIANTS = [];
  [['lights', Mock.chips.lights(3)], ['lights-off', Mock.chips.lights(0)]].forEach(function (x) { CHIP_VARIANTS.push({ id: x[0], label: 'Lights · ' + x[1].summary, props: x[1] }); });
  ['armed_home', 'armed_away', 'armed_night', 'disarmed', 'triggered', 'arming'].forEach(function (s) { CHIP_VARIANTS.push({ id: 'sec-' + s, label: 'Security · ' + s, props: Mock.chips.security(s) }); });
  [[50, '48–52°F'], [60, '58–62°F'], [68, '66–70°F'], [74, '72–76°F'], [80, '78–82°F'], [85, '83–87°F']].forEach(function (x) { CHIP_VARIANTS.push({ id: 'climate-' + x[0], label: 'Climate · gradient at ' + x[0] + '°F', props: Mock.chips.climate(x[1], x[0]) }); });
  CHIP_VARIANTS.push({ id: 'aqi', label: 'Air Quality (web teal)', props: Mock.chips.airQuality('AQI 18–42 · PM2.5 4–9') });
  CHIP_VARIANTS.push({ id: 'occ-clear', label: 'Occupancy · clear', props: Mock.chips.occupancy(false) }, { id: 'occ-det', label: 'Occupancy · detected', props: Mock.chips.occupancy(true) });
  CHIP_VARIANTS.push({ id: 'contact-closed', label: 'Contact · all closed', props: Mock.chips.contacts('closed', 0) }, { id: 'contact-home', label: 'Contact · open, home', props: Mock.chips.contacts('home', 2) },
    { id: 'contact-away', label: 'Contact · open, away', props: Mock.chips.contacts('away', 2) }, { id: 'contact-armed', label: 'Contact · open, armed (triangle)', props: Mock.chips.contacts('armed', 1) });
  Mock.register('StatusChip', StatusChip, { source: 'apple/Sources/HassUI/Features/Home/StatusRail.swift', props: '{title, summary, symbol, family, isActive, tint, dim, pending}', variants: CHIP_VARIANTS,
    states: [{ id: 'unavailable', label: 'Unavailable (dimmed, still opens its sheet)', props: Mock.chips.unavailable('Occupancy', 'person') }, { id: 'pending', label: 'Pending (first sign-in)', props: Object.assign(Mock.chips.occupancy(true), { pending: true }) }] });

  function ChipRail(p) {
    var ctx = p.ctx || Mock.current || Mock.ctx('iphone');
    var mode = p.mode && p.mode !== 'auto' ? p.mode : (ctx.axSize ? 'wrap' : 'scroll');
    var rail = h('div.ui-rail-chips.' + mode, { role: 'group', 'aria-label': 'Status', dataset: { mode: mode } },
      (p.chips || []).map(function (c) { return c && c.nodeType ? c : StatusChip(c); }));
    if (ctx.hinge && mode === 'wrap') {
      var f = p.frame || { x: 0, w: ctx.contentW };
      rail.style.paddingRight = Math.max(0, f.x + f.w - (ctx.hinge.x - 24)) + 'px';   // ChipRailMetrics.trailingInset
      rail.dataset.hingeGap = '24';
    }
    return h('div.ui-bleed', rail);
  }
  var six = Mock.chips.home();
  Mock.register('ChipRail', ChipRail, { source: 'apple/Sources/HassDesign/ChipRail.swift', props: '{chips, ctx, frame, mode}',
    variants: [{ id: 'scroll', label: 'Every width: one scrolling row', props: { chips: six, mode: 'scroll' } }, { id: 'wrap', label: 'Accessibility sizes: wraps, nothing hidden', props: { chips: six, mode: 'wrap' } },
      { id: 'left', label: 'Two chips still start at the leading margin', props: { chips: six.slice(1, 5).filter(function (c, i) { return i === 0 || i === 3; }), mode: 'scroll' } }],
    states: [{ id: 'hinge', label: 'Unfolded Duo: the scrolling rail crosses the fold', props: { chips: six, mode: 'scroll', ctx: Mock.ctx('duo-unfolded-landscape') } }, { id: 'hinge-wrap', label: 'Unfolded Duo at an accessibility size: a wrapped rail stops 24 pt short of the fold', props: { chips: six, mode: 'wrap', ctx: Mock.ctx('duo-unfolded-landscape') } }] });
})();
