/* SettingsSection, InlineAlert, SelectableOptionRow. apple/Sources/HassDesign/SettingsSection.swift; patterns/settings-section.md.
 * SettingsSection: a .title3 semibold header, each description paragraph as its own .subheadline in the secondary ink (white on a page), then the content;
 * pages stack sections with 24 pt between. InlineAlert: a warning under the control it concerns (orange triangle on a 14% wash; VoiceOver "Warning: ...");
 * severity 'error' is red text with a circle glyph. SelectableOptionRow: one choice in a single-choice set (icon, label, description, checkmark, selected).
 * SettingsSection props: {title, paragraphs?:string[], content?:Node|Node[]}; InlineAlert: {message, severity?:'warning'|'error'};
 * SelectableOptionRow: {icon?, label, description?, selected?}
 */
(function () {
  var h = Mock.h, I = Mock.icon;
  Mock.register('SettingsSection', function (p) {
    return h('section.ui-settings', h('h3', { role: 'heading', 'aria-level': '2' }, p.title), (p.paragraphs || []).map(function (t) { return h('p', t); }), p.content ? h('div.content', p.content) : null);
  }, { source: 'apple/Sources/HassDesign/SettingsSection.swift', props: '{title, paragraphs, content}',
    states: [{ id: 'default', label: 'Header, two paragraphs, content', props: { title: 'Vacation Mode', paragraphs: ['Pauses chores and lowers the thermostat while you are away.', 'Guests staying over skip some away automations.'], content: 'Controls go here.' } }] });
  Mock.register('InlineAlert', function (p) {
    var err = p.severity === 'error';
    return h('div.ui-inline-alert' + (err ? '.error' : ''), { role: 'group', 'aria-label': (err ? 'Error: ' : 'Warning: ') + p.message }, h('span', { html: I(err ? 'exclamationmark.circle' : 'exclamationmark.triangle', { fill: true }) }), h('span', p.message));
  }, { source: 'apple/Sources/HassDesign/SettingsSection.swift', props: '{message, severity}',
    variants: [{ id: 'warning', label: 'Warning', props: { message: 'Away automations stay paused while guests are staying.' } }, { id: 'error', label: 'Error', props: { message: 'Could not reach Home Assistant.', severity: 'error' } }] });
  Mock.register('SelectableOptionRow', function (p) {
    return h('button.ui-opt' + (p.selected ? '.sel' : ''), { type: 'button', 'aria-pressed': p.selected ? 'true' : 'false' }, p.icon ? h('span', { html: I(p.icon, { size: '1.3em' }) }) : null,
      h('span.tx', h('span.ti', p.label), p.description ? h('span.su', { style: { display: 'block' } }, p.description) : null), h('span.ck', { html: I('checkmark', { weight: 2.4 }) }));
  }, { source: 'apple/Sources/HassDesign/SettingsSection.swift', props: '{icon, label, description, selected}',
    variants: [{ id: 'on', label: 'Selected', props: { icon: 'house', label: 'Home', description: 'Someone is home.', selected: true } }, { id: 'off', label: 'Not selected', props: { icon: 'airplane', label: 'Away', description: 'Nobody is home.' } }] });
})();
