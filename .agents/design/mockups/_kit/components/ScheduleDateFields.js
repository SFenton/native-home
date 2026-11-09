/* ScheduleDateFields: date and time pickers laid out in a grid of 320 pt (scaled) minimum cells, two columns at most. apple/Sources/HassDesign/ScheduleDateFields.swift.
 * Each field is a label and a system picker on a regular-material cell, side by side when the label fits one line and stacked when it does not (narrow iPad sheet columns, accessibility
 * sizes); the label never truncates. A picker edits a local draft and commits after the delay, so a stale echo from Home Assistant never fights the wheel.
 * props: {fields:[{label, value:string, part?:'date'|'time'|'dateAndTime'}]}
 */
(function () {
  var h = Mock.h, I = Mock.icon;
  Mock.register('ScheduleDateFields', function (p) {
    return h('div.ui-datefields', (p.fields || []).map(function (f) {
      var parts = String(f.value).split(' · ');
      return h('div.ui-datefield', { role: 'group', 'aria-label': f.label + ': ' + f.value }, h('span', f.label), h('span', { style: { display: 'inline-flex', gap: '8px' } }, parts.map(function (t) { return h('span.ui-date', t); })));
    }));
  }, { source: 'apple/Sources/HassDesign/ScheduleDateFields.swift', props: '{fields}',
    variants: [{ id: 'range', label: 'Start and end', props: { fields: [{ label: 'Starts', value: 'Oct 24, 2026 · 9:00 AM' }, { label: 'Ends', value: 'Oct 28, 2026 · 6:00 PM' }] } }, { id: 'long', label: 'Long label stacks', props: { fields: [{ label: 'Resume Normal Heating and Cooling', value: 'Oct 28, 2026' }] } }] });
})();
