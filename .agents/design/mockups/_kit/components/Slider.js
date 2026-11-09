/* Slider and SliderRow: the system slider and the app's one slider-with-value row (PercentSliderRow, Settings > Appearance > Background Blur: label, value "50%",
 * one adjustable element, Reset under it). Track 6 pt, 28 pt white knob. A light's brightness uses BrightnessTile, not this. Slider props: {value:0..1, icons?:[leading,trailing]};
 * SliderRow props: {label, valueText, value}
 */
(function () {
  var h = Mock.h, I = Mock.icon;
  function Slider(p) {
    var v = Math.round((p.value == null ? .5 : p.value) * 100);
    var s = h('div.ui-slider', { role: 'slider', 'aria-valuemin': 0, 'aria-valuemax': 100, 'aria-valuenow': v, 'aria-label': p.label || 'Value', tabindex: 0 }, h('span.tr'), h('span.fi', { style: { width: v + '%' } }), h('span.kn', { style: { left: v + '%' } }));
    if (!p.icons) return s;
    return h('div.ui-sliderrow', h('span.ico', { html: I(p.icons[0]) }), s, h('span.ico', { html: I(p.icons[1]) }));
  }
  Mock.register('Slider', Slider, { source: 'SwiftUI Slider (system)', props: '{value, icons, label}', variants: [{ id: 'plain', label: 'Plain', props: { value: .5 } }, { id: 'volume', label: 'Volume (speaker − and +)', props: { value: .35, icons: ['speaker.slash', 'speaker.wave.2'], label: 'Volume' } }] });
  Mock.register('SliderRow', function (p) {
    return h('div', { style: { display: 'flex', flexDirection: 'column', gap: '6px', padding: '8px 16px', background: 'var(--sheet-cell, rgba(28,28,30,.66))', borderRadius: '16px', color: 'var(--ink, #fff)' } }, h('div', { style: { display: 'flex', justifyContent: 'space-between', fontSize: 'var(--fs-body)' } }, h('span', p.label), h('span', { style: { color: 'var(--ink-sheet-2, rgba(255,255,255,.7))' } }, p.valueText)), Slider({ value: p.value, label: p.label }));
  }, { source: 'apple/Sources/HassUI/Features/Settings/Appearance/AppearanceSettingsSection.swift (PercentSliderRow)', props: '{label, valueText, value}', variants: [{ id: 'default', label: 'Background Blur 50%', props: { label: 'Background Blur', valueText: '50%', value: .5 } }] });
})();
