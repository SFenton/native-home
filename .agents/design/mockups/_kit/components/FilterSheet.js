/* FilterSheet, FilterSection, FilterOptionRow: the sort and filter sheet's content. apple/Sources/HassDesign/FilterSheet.swift; patterns/floating-actions.md.
 * An edit sheet in direction G's form: Mock.sheet({leading:'cancel', trailing:'confirm', confirm:{title:'Apply', enabled:canApply}}) puts the circle x Cancel
 * leading (drops the draft) and the filled check trailing (disabled until the draft changes). "Reset to Defaults" is a list row in the action tint (blue, never
 * red: resetting filters is not destructive), shown only while canReset. Titled sections are FilterSection (15 Semibold secondary, not the system header which
 * measured 3.1:1); single-choice options are FilterOptionRow (title, secondary subtitle, action-tint check, selected); two to four short options are a
 * segmented control with the chosen option's explanation as the section footer, and a menu at accessibility sizes. Medium and large detents; large only at AX.
 * FilterSheet props: {sections:Array<{title, options?:[{title,subtitle?,selected?}], segmented?:{options:string[],selected:string}, footer?, content?:Node}>, canReset?:boolean}
 */
(function () {
  var h = Mock.h, I = Mock.icon;
  function FilterOptionRow(p) {
    return h('button.ui-optrow' + (p.selected ? '.sel' : ''), { type: 'button', 'aria-pressed': p.selected ? 'true' : 'false' },
      h('span.tx', h('span', p.title), p.subtitle ? h('span.su', p.subtitle) : null), h('span.ck', { html: I('checkmark', { weight: 2.4 }) }));
  }
  function FilterSection(p) {
    var body = p.content || (p.segmented ? Mock.components.SegmentedChoice({ options: p.segmented.options, selected: p.segmented.selected, label: p.title }) : h('div.ui-optlist', (p.options || []).map(FilterOptionRow)));
    return h('section', h('p.ui-formhead', { role: 'heading', 'aria-level': '2' }, p.title), body, p.footer ? h('p.ui-formfoot', p.footer) : null);
  }
  function FilterSheet(p) {
    var el = h('div', { style: { display: 'flex', flexDirection: 'column', gap: '24px' } }, (p.sections || []).map(FilterSection));
    if (p.canReset) el.appendChild(h('button.ui-reset', { type: 'button' }, 'Reset to Defaults'));
    return el;
  }
  var secs = [{ title: 'Sort By', options: [{ title: 'Name', selected: true }, { title: 'Date Added' }, { title: 'Expires Soonest', subtitle: 'Items closest to their date first' }] },
    { title: 'Added In The Last', segmented: { options: ['7 Days', '30 Days', '90 Days'], selected: '30 Days' }, footer: 'Shows items added within the last 30 days.' }];
  Mock.register('FilterSheet', FilterSheet, { source: 'apple/Sources/HassDesign/FilterSheet.swift', props: '{sections, canReset}',
    states: [{ id: 'default', label: 'Defaults (Reset hidden, Apply disabled)', props: { sections: secs } }, { id: 'changed', label: 'Changed (Reset shown, Apply enabled)', props: { sections: secs, canReset: true } }] });
  Mock.register('FilterSection', FilterSection, { source: 'apple/Sources/HassDesign/FilterSheet.swift', props: '{title, options|segmented|content, footer}', variants: [{ id: 'options', label: 'Options', props: secs[0] }, { id: 'segmented', label: 'Segmented + footer', props: secs[1] }] });
  Mock.register('FilterOptionRow', FilterOptionRow, { source: 'apple/Sources/HassDesign/FilterSheet.swift', props: '{title, subtitle, selected}', variants: [{ id: 'sel', label: 'Selected', props: { title: 'Name', selected: true } }, { id: 'sub', label: 'With subtitle', props: { title: 'Expires Soonest', subtitle: 'Items closest to their date first' } }] });
})();
