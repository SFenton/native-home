/* Alert: the iOS 26 alert, for destructive or hard-to-undo actions (direction-g.md Sheets: Alerts): Disarm the Security System, Turn Off Vacation Mode, Sign Out. The destructive button is red
 * (#FF6961 on dark, #C21717 on light); Cancel always stays (also on iPad, where an action sheet would be a popover). Two buttons sit side by side; three or more (or long titles) stack, and every alert stacks at accessibility sizes (AX5 reads ctx.axSize).
 * `field: {label?, value?, placeholder?, keyboard?}` adds the system text field under the message (or use the AlertField component). Pass the node as Mock.sheet's `alert` option (it draws the scrim) or place it in a `.ui-alert-scrim`. props: {title, message?, buttons:[{title, role?:'destructive'|'cancel'}], stacked?, ctx?}
 */
(function () {
  var h = Mock.h;
  function field(f) {
    // The system alert's text field (alert(_:isPresented:) with a TextField): a rounded inset box under the message; the keyboard is the caller's (a decimal pad is drawn by the mockup).
    return h('div.fld', { role: 'textbox', 'aria-label': f.label || 'Text field', 'aria-description': f.keyboard ? f.keyboard + ' keyboard' : null }, f.value == null || f.value === '' ? h('span.ph', f.placeholder || '') : String(f.value));
  }
  function Alert(p) {
    var bs = p.buttons || [{ title: 'OK' }], ctx = p.ctx || Mock.current || {};
    // Three or more buttons stack, and at accessibility sizes UIKit stacks every alert (two buttons too).
    return h('div.ui-alert' + (p.stacked || bs.length > 2 || ctx.axSize ? '.stacked' : '') + (p.field ? '.has-field' : ''), { role: 'alertdialog', 'aria-label': p.title, 'aria-modal': 'true' }, h('div.bd', h('div.ti', p.title), p.message ? h('div.ms', p.message) : null, p.field ? field(p.field) : null),
      h('div.btns', bs.map(function (b) { return h('button' + (b.role === 'destructive' ? '.destructive' : ''), { type: 'button', style: b.role === 'cancel' ? { fontWeight: 600 } : null }, b.title); })));
  }
  Mock.register('Alert', Alert, { source: 'apple/Sources/HassUI/Features/Security/SecuritySystemSheet.swift', props: '{title, message, buttons, stacked, field, ctx}',
    variants: [{ id: 'destructive', label: 'Destructive + Cancel', props: { title: 'Disarm the Security System?', message: 'Doors and motion stop triggering the alarm.', buttons: [{ title: 'Cancel', role: 'cancel' }, { title: 'Disarm' }] } },
      { id: 'single', label: 'One button (a failure notice)', props: { title: 'Sign Out couldn\u2019t complete. Try again.', buttons: [{ title: 'OK', role: 'cancel' }] } },
      { id: 'stacked', label: 'Three buttons stack', props: { title: 'Switch Vacuum?', message: 'The robot is cleaning.', buttons: [{ title: 'Switch Now', role: 'destructive' }, { title: 'Finish Cleaning First' }, { title: 'Cancel', role: 'cancel' }] } }] });
  /** AlertField: the same alert with a text field under the message (the quantity prompts: Add to Groceries, Delete how many). props: Alert props + {field:{label?, value?, placeholder?, keyboard?}} */
  Mock.register('AlertField', function (p) { return Alert(Object.assign({ field: { label: 'Quantity', value: '1', keyboard: 'Decimal pad' } }, p)); }, { source: 'SwiftUI alert(_:isPresented:) with a TextField (apple/Sources/HassUI/Features/Inventory)', props: 'Alert props + {field}',
    variants: [{ id: 'prefilled', label: 'Field prefilled 1: Cancel and Add', props: { title: 'Add Black Beans to Groceries', message: 'How many do you want to buy?', buttons: [{ title: 'Cancel', role: 'cancel' }, { title: 'Add' }] } },
      { id: 'empty', label: 'Empty field with a placeholder', props: { title: 'Rename Space', field: { label: 'Name', value: '', placeholder: 'Pantry' }, buttons: [{ title: 'Cancel', role: 'cancel' }, { title: 'Rename' }] } }] });
})();
