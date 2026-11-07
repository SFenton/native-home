/* InfoBox: a tinted notice with a title and optional message (a confirmed state, an informational banner). apple/Sources/HassDesign/InfoBox.swift; patterns/info-box.md.
 * Tones: success (green, only for a state Home Assistant has confirmed) and neutral (grey). Text stays the primary label colour on a 16% wash of the tone so it keeps
 * 4.5:1 in light and dark; the icon carries the tint. One accessibility element. props: {title, message?, tone?:'success'|'neutral'}
 */
(function () {
  var h = Mock.h, I = Mock.icon;
  Mock.register('InfoBox', function (p) {
    var ok = p.tone === 'success';
    return h('div.ui-info', { role: 'group', 'aria-label': p.title + (p.message ? '. ' + p.message : ''), style: { '--tone': ok ? '#42A147' : '#8E8E93' } }, h('div.h', h('span', { html: I(ok ? 'checkmark.circle' : 'info.circle', { fill: true }) }), p.title), p.message ? h('p', p.message) : null);
  }, { source: 'apple/Sources/HassDesign/InfoBox.swift', props: '{title, message, tone}',
    variants: [{ id: 'success', label: 'Success (confirmed)', props: { tone: 'success', title: 'Alex Away', message: 'Solo Trip is active until Oct 28.' } }, { id: 'neutral', label: 'Neutral', props: { tone: 'neutral', title: 'Reporting isn\'t set up yet', message: 'Ask the owner to finish setup.' } }] });
})();
