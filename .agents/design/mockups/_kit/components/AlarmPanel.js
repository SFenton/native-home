/* AlarmPanel and AlarmModeButton: the Security System card (the sheet's body, the Security page's first tile, the Quick Links detail).
 * apple/Sources/HassUI/Features/Security/SecuritySystemSheet.swift (AlarmPanel, AlarmModeButton), HassCore/Config/SecurityConfig.swift. Direction G mockup n3.
 * A header (a 44 pt badge in the mode's family fill with a filled white glyph, the mode as a fact in 22 bold, "Security System · Since 6:12 PM" under it), then four mode buttons in
 * this order: Disarm, Home, Away, Night (a grid of 64 pt scaled minimum, 4 columns, equal heights; one column cannot happen before AX sizes). The chosen mode is a filled tile in its colour
 * (Home #1565C0, Away #C62828, Night #7B1FA2, Disarmed #2A732E) with tinted glass's sheen and rim; the others are the tertiary fill. Triggered tints the card #D70015 at 42% dark / 16% light and
 * the unselected modes go to the label colour at 14%. Colour fades on `state` (0.6 s); it holds steady and never pulses. Disarm ALWAYS confirms with an alert ("Disarm the Security System?");
 * arming sends at once. Unavailable dims the glyphs only and keeps the text. `surface:'page'` draws the page module instead of the sheet cell.
 * Hidden (the screenshot-privacy redaction, ScreenshotPrivacy.isRedacting): the title says Hidden, the glyph is the plain shield on the neutral #636366 badge, the subtitle is just
 * "Security System" (no time) and no mode is selected; the buttons stay enabled, unlike Unavailable (glyph dimmed to 50%, buttons disabled).
 * props: {state:'armed_home'|'armed_away'|'armed_night'|'disarmed'|'triggered'|'arming'|'unavailable'|'hidden', since?:'6:12 PM', surface?:'sheet'|'page'}
 */
(function () {
  var h = Mock.h, I = Mock.icon;
  var MODES = [['disarmed', 'Disarm', 'shield.slash', 'sec-disarmed'], ['armed_home', 'Home', 'house', 'sec-home'], ['armed_away', 'Away', 'figure.walk', 'sec-away'], ['armed_night', 'Night', 'moon', 'sec-night']];
  var TITLES = { armed_home: 'Armed Home', armed_away: 'Armed Away', armed_night: 'Armed Night', disarmed: 'Disarmed', triggered: 'Alarm Triggered', arming: 'Arming', unavailable: 'Unavailable', hidden: 'Hidden' };
  var BADGE = { armed_home: ['sec-home', 'shield'], armed_away: ['sec-away', 'shield'], armed_night: ['sec-night', 'moon.zzz'], disarmed: ['sec-disarmed', 'shield.slash'], triggered: ['sec-triggered', 'exclamationmark.shield'], arming: [null, 'shield'], unavailable: [null, 'shield'], hidden: [null, 'shield'] };
  Mock.securityModes = MODES;
  function AlarmModeButton(p) {
    var fillVar = 'var(--fam-' + p.fam + '-fill)';
    var b = h('button.ui-mode' + (p.selected ? '.sel' : '') + (p.onAlarm ? '.on-alarm' : ''), { type: 'button', 'aria-pressed': p.selected ? 'true' : 'false', style: { '--fill': fillVar }, dataset: { mode: p.state } },
      h('span.ico', { html: I(p.symbol, { fill: p.selected }) }), h('span.lb', p.label));
    if (p.disabled) b.disabled = true;
    return b;
  }
  function AlarmPanel(p) {
    var st = p.state || 'armed_home', unavailable = st === 'unavailable', hidden = st === 'hidden', badge = BADGE[st] || BADGE.unavailable;
    var since = unavailable || hidden ? null : (p.since === undefined ? '6:12 PM' : p.since);
    var el = h('div.ui-alarm' + (p.surface === 'page' ? '.on-page' : '') + (st === 'triggered' ? '.triggered' : ''), { role: 'group', 'aria-label': 'Security System, ' + TITLES[st] + (since ? ', Since ' + since : ''), dataset: { state: st } },
      h('div.hd', h('span.badge' + (unavailable ? '.unavail' : ''), { style: badge[0] ? { '--bfill': 'var(--fam-' + badge[0] + '-fill)' } : null, html: I(badge[1], { fill: true }) }),
        h('span.tx', h('span.ti', TITLES[st] || 'Unknown'), h('span.su', 'Security System' + (since ? ' · Since ' + since : '')))),
      h('div.modes', MODES.map(function (m) { return AlarmModeButton({ state: m[0], label: m[1], symbol: m[2], fam: m[3], selected: st === m[0], onAlarm: st === 'triggered', disabled: unavailable }); })));
    return el;
  }
  Mock.register('AlarmModeButton', AlarmModeButton, { source: 'apple/Sources/HassUI/Features/Security/SecuritySystemSheet.swift', props: '{state, label, symbol, fam, selected, onAlarm, disabled}',
    variants: MODES.map(function (m) { return { id: m[0], label: m[1] + ' selected', props: { state: m[0], label: m[1], symbol: m[2], fam: m[3], selected: true } }; }), states: [{ id: 'idle', label: 'Unselected', props: { state: 'armed_home', label: 'Home', symbol: 'house', fam: 'sec-home' } }] });
  Mock.register('AlarmPanel', AlarmPanel, { source: 'apple/Sources/HassUI/Features/Security/SecuritySystemSheet.swift', props: '{state, since, surface}',
    variants: ['armed_home', 'armed_away', 'armed_night', 'disarmed', 'triggered', 'arming', 'unavailable', 'hidden'].map(function (s) { return { id: s, label: s, props: { state: s } }; }) });
})();
