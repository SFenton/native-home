/* Toggle and ToggleRow. Switches appear ONLY in list rows (direction-g.md Controls: Switches). A 51 x 31 system switch, green #30D158 when on; the knob slides on `standard`
 * (0.3 s) and the track colour cross-fades on `state` (0.6 s). Toggle props: {on?, label?}; ToggleRow props: {title, subtitle?, symbol?, glyph?, on?}
 */
(function () {
  var h = Mock.h;
  function Toggle(p) { return h('button.ui-toggle' + (p.on ? '.on' : ''), { type: 'button', role: 'switch', 'aria-checked': p.on ? 'true' : 'false', 'aria-label': p.label || 'Toggle' }); }
  Mock.register('Toggle', Toggle, { source: 'SwiftUI Toggle (system), as a ModuleRow accessory: apple/Sources/HassDesign/ModuleList.swift', props: '{on, label}', states: [{ id: 'off', label: 'Off', props: { on: false } }, { id: 'on', label: 'On', props: { on: true } }] });
  Mock.register('ToggleRow', function (p) {
    return Mock.components.ModuleRow(Object.assign({}, p, { accessory: Toggle({ on: p.on, label: p.title }) }));
  }, { source: 'apple/Sources/HassDesign/ModuleList.swift', props: '{title, subtitle, symbol, glyph, on}',
    variants: [{ id: 'on', label: 'On', props: { title: 'Guests Staying Over', symbol: 'person.2', glyph: 'var(--fam-occupancy-glyph)', on: true } }, { id: 'off', label: 'Off', props: { title: 'Vacation Mode', subtitle: 'Pauses chores', symbol: 'airplane', on: false } }] });
})();
