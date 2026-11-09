/* ThermostatDial (a signature control): main's ThermostatDial. apple/Sources/HassDesign/ThermostatDial/ThermostatDial.swift, ThermostatDialGeometry.swift, ThermostatDialModel.swift. A 24/320-of-the-side
 * round-capped 270-degree track opening at the bottom (min at 7:30, max at 4:30, clockwise), a drop shadow under the ring; ONLY a heat+cool range draws arcs (heat `#CD5401` from the minimum to the low
 * setpoint, cool `#2C8E98` from the high setpoint to the maximum); a single target draws no arc, just its handle. Handles are 24 pt white circles with a 4 pt border (heat orange, cool teal, or for a
 * single target the thermal status's colour) inside a 64 pt hit target; dragging lifts the handle (a bigger shadow and a faint 40 pt halo) and the caption follows it. The current temperature is an
 * 18 pt dot in the thermal status's colour (idle: the secondary ink) with a 3 pt near-black rim, so it never reads as a handle. The middle reads the action (Heating, Idle, Off, Unavailable) in
 * bold, a Light numeral (the current temperature; "--" when unavailable) with a raised bold unit, and the setpoint caption with a thermometer: "72.0°F" for a target, "68.0 · 74.0" for a range.
 * Inactive (unavailable, or off with no range and nothing running) dims the ring to 45% and drops its colour; unavailable also removes the marker, trails, handles and caption.
 * The bed and humidifier dials reuse its geometry.
 * props: {value:71 (current), target?:70 (single setpoint), heat?:68, cool?:74 (range; alone, a legacy arc to that one setpoint), min?:50, max?:90, mode?:'Heating'|'Cooling'|'Idle'|'Off', off?:boolean,
 *   unavailable?:boolean, dragging?:'target'|'low'|'high'|true (the handle being dragged), caption?:string|false (override or hide), range?:string (legacy caption line), unit?:'°F', size?:280}
 */
(function () {
  var h = Mock.h;
  function pt(cx, cy, r, deg) { var a = deg * Math.PI / 180; return [cx + r * Math.cos(a), cy + r * Math.sin(a)]; }
  function arc(cx, cy, r, d0, d1) { var a = pt(cx, cy, r, d0), b = pt(cx, cy, r, d1); return 'M' + a[0].toFixed(2) + ' ' + a[1].toFixed(2) + ' A' + r + ' ' + r + ' 0 ' + (d1 - d0 > 180 ? 1 : 0) + ' 1 ' + b[0].toFixed(2) + ' ' + b[1].toFixed(2); }
  var KNOB = { heat: 'var(--dial-heat)', cool: 'var(--dial-cool)', idle: 'var(--ink-2, rgba(255,255,255,.72))' };
  Mock.register('ThermostatDial', function (p) {
    var min = p.min == null ? 50 : p.min, max = p.max == null ? 90 : p.max, size = p.size || 280, k = 320 / size, unit = p.unit == null ? '\u00b0F' : p.unit;
    var unavailable = !!p.unavailable, mode = unavailable ? 'Unavailable' : (p.mode || (p.off ? 'Off' : 'Idle'));
    var status = /heat/i.test(mode) ? 'heat' : (/cool/i.test(mode) ? 'cool' : 'idle');
    var range = p.heat != null && p.cool != null;
    var inactive = unavailable || (!!p.off && !range && status === 'idle');
    function deg(v) { return 135 + Math.min(Math.max((v - min) / (max - min), 0), 1) * 270; }
    function f1(v) { return Number(v).toFixed(1); }
    var cx = 160, cy = 160, r = 145, lw = 24, ring = '<svg viewBox="0 0 320 320" aria-hidden="true">';
    ring += '<path d="' + arc(cx, cy, r, 135, 405) + '" fill="none" stroke="var(--fill-tertiary)" stroke-width="' + lw + '" stroke-linecap="round" style="stroke:color-mix(in srgb, var(--ink) 16%, transparent)"/>';
    if (!unavailable) {
      if (p.heat != null) ring += '<path d="' + arc(cx, cy, r, 135, Math.max(deg(p.heat), 136)) + '" fill="none" stroke="var(--dial-heat)" stroke-width="' + lw + '" stroke-linecap="round"/>';
      if (p.cool != null) ring += '<path d="' + arc(cx, cy, r, Math.min(deg(p.cool), 404), 405) + '" fill="none" stroke="var(--dial-cool)" stroke-width="' + lw + '" stroke-linecap="round"/>';
      if (p.value != null) { var d = pt(cx, cy, r, deg(p.value)); ring += '<circle cx="' + d[0].toFixed(2) + '" cy="' + d[1].toFixed(2) + '" r="' + ((9 - 1.5) * k).toFixed(2) + '" fill="' + KNOB[status] + '" stroke="#141414" stroke-width="' + (3 * k).toFixed(2) + '"/>'; }
    }
    ring += '</svg>';
    // handles: a 24 pt white disc with a 4 pt coloured border; the one being dragged lifts (halo and a bigger shadow)
    var knobs = '';
    if (!unavailable) {
      var hs = [];
      if (p.target != null) hs.push(['target', p.target, KNOB[status]]);
      else { if (p.heat != null) hs.push(['low', p.heat, KNOB.heat]); if (p.cool != null) hs.push(['high', p.cool, KNOB.cool]); }
      knobs = '<svg viewBox="0 0 320 320" aria-hidden="true">' + hs.map(function (x) {
        var c = pt(cx, cy, r, deg(x[1])), drag = p.dragging === true || p.dragging === x[0], cls = 'knob' + (drag ? ' drag' : '');
        return '<g class="' + cls + '">' + (drag ? '<circle cx="' + c[0].toFixed(2) + '" cy="' + c[1].toFixed(2) + '" r="' + (20 * k).toFixed(2) + '" fill="#fff" fill-opacity=".12"/>' : '') +
          '<circle cx="' + c[0].toFixed(2) + '" cy="' + c[1].toFixed(2) + '" r="' + ((12 - 2) * k).toFixed(2) + '" fill="#fff" stroke="' + x[2] + '" stroke-width="' + (4 * k).toFixed(2) + '"/></g>';
      }).join('') + '</svg>';
    }
    // the caption under the numeral: the setpoint(s) the dial shows (CaptionAutomatic); `range` is the legacy free-text line
    var cap = p.caption === false || unavailable ? null : (p.caption || (p.target != null ? f1(p.target) + unit : (range ? f1(p.heat) + ' \u00b7 ' + f1(p.cool) : null)));
    var value = unavailable || p.value == null ? '--' : String(p.value);
    var spoken = unavailable ? 'unavailable' : mode + ', ' + p.value + ' degrees' + (cap ? ', set to ' + cap : '') + (p.range ? ', ' + p.range : '');
    return h('div.ui-dial' + (inactive ? '.inactive' : ''), { role: 'slider', 'aria-label': 'Thermostat', 'aria-valuetext': spoken, 'aria-disabled': unavailable ? 'true' : null, style: { width: size + 'px', height: size + 'px', '--d': size + 'px', '--k': k.toFixed(4) } },
      h('div.ring', { html: ring, style: { position: 'absolute', inset: 0 } }),
      h('div.mid', h('span.mode', mode), h('span.big', value, h('sup', unit)),
        cap ? h('span.range.cap', h('span', { html: Mock.icon('thermometer.medium'), 'aria-hidden': 'true' }), cap) : (p.range ? h('span.range', p.range) : null)),
      knobs ? h('div.knobs', { html: knobs, style: { position: 'absolute', inset: 0 } }) : null);
  }, { source: 'apple/Sources/HassDesign/ThermostatDial/ThermostatDial.swift', props: '{value, target, heat, cool, min, max, mode, off, unavailable, dragging, caption, range, unit, size}',
    variants: [{ id: 'target', label: 'Single target (heating to 70): one handle, no arc', props: { value: 66, target: 70, mode: 'Heating', size: 240 } },
      { id: 'cool-target', label: 'Single target (cooling to 72)', props: { value: 75, target: 72, mode: 'Cooling', size: 240 } },
      { id: 'both', label: 'Heat and cool range: arcs and two handles', props: { value: 71, heat: 68, cool: 74, mode: 'Idle', size: 240 } },
      { id: 'heat', label: 'Legacy: heating arc to 68 (the app draws arcs only for a range)', props: { value: 66, heat: 68, mode: 'Heating', range: 'Range 66–74°F', size: 240 } },
      { id: 'cool', label: 'Legacy: cooling arc to 72', props: { value: 75, cool: 72, mode: 'Cooling', range: 'Range 72–80°F', size: 240 } }],
    states: [{ id: 'dragging', label: 'Dragging the target (lifted handle, caption follows)', props: { value: 66, target: 73, mode: 'Heating', dragging: 'target', size: 240 } },
      { id: 'off', label: 'Off (ring dimmed to 45%, grey; the handle stays)', props: { value: 68, target: 70, off: true, mode: 'Off', size: 240 } },
      { id: 'unavailable', label: 'Unavailable (dimmed; no marker, trails, handles or caption)', props: { unavailable: true, size: 240 } }] });
})();
