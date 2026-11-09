/* FormField and FormSection: rows of an edit form in a sheet (Add Item, todo editors, Vacation and Solo Trip). Cells are `Surface.sheetCell` (#2C2C2E dark, white light), 52 pt min, 17 pt text,
 * hairlines inset 16 pt; a header is 15 Semibold in the secondary ink (FormHeader) and a footer 13 pt carries the explanation. SwiftUI `Form` supplies the grouped look. FormSection groups fields.
 * FormField props: {label, value?, placeholder?, kind?:'text'|'value'|'toggle'|'picker'|'stepper', on?}; FormSection props: {header?, footer?, fields:FormField props[]}
 */
(function () {
  var h = Mock.h, I = Mock.icon;
  function FormField(p) {
    var k = p.kind || 'text', right;
    if (k === 'toggle') right = Mock.components.Toggle({ on: p.on, label: p.label });
    else if (k === 'picker') right = h('span.va', { style: { display: 'inline-flex', gap: '6px', alignItems: 'center' } }, p.value, h('span', { html: I('chevron.down', { size: '.8em' }) }));
    else if (k === 'stepper') right = h('span.va', { style: { display: 'inline-flex', gap: '10px', alignItems: 'center' } }, p.value, h('span.ui-seg', { style: { width: '94px' } }, h('button', { type: 'button', 'aria-label': 'Decrease', html: I('minus') }), h('button', { type: 'button', 'aria-label': 'Increase', html: I('plus') })));
    else if (k === 'value') right = h('span.va', p.value);
    else right = h('span.va', { style: { flex: 1, textAlign: 'right' } }, p.value || p.placeholder);
    if (k === 'text' && !p.value) right.style.opacity = .6;
    return h('div.ui-field', h('span.lb', p.label), right);
  }
  function FormSection(p) {
    return h('section', p.header ? h('p.ui-formhead', { role: 'heading', 'aria-level': '2' }, p.header) : null, h('div.ui-form', (p.fields || []).map(FormField)), p.footer ? h('p.ui-formfoot', p.footer) : null);
  }
  Mock.register('FormField', FormField, { source: 'apple/Sources/HassDesign/FormSectionText.swift', props: '{label, value, placeholder, kind, on}',
    variants: [{ id: 'text', label: 'Text (placeholder)', props: { label: 'Task Name', placeholder: 'Required' } }, { id: 'value', label: 'Value', props: { label: 'Assignee', value: 'Alex', kind: 'picker' } }, { id: 'toggle', label: 'Toggle', props: { label: 'Repeats', kind: 'toggle', on: true } }, { id: 'stepper', label: 'Stepper', props: { label: 'Every', value: '2 weeks', kind: 'stepper' } }] });
  Mock.register('FormSection', FormSection, { source: 'apple/Sources/HassDesign/FormSectionText.swift', props: '{header, footer, fields}',
    states: [{ id: 'default', label: 'Header, rows, footer', props: { header: 'Details', footer: 'Overdue tasks appear on the Chores tab.', fields: [{ label: 'Task Name', value: 'Replace the furnace filter' }, { label: 'Assignee', value: 'Alex', kind: 'picker' }, { label: 'Repeats', kind: 'toggle', on: true }] } }] });
})();
