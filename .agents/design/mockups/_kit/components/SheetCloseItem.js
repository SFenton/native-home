/* SheetCloseItem, SheetCancelItem, SheetConfirmItem: the circle buttons in a sheet header. apple/Sources/HassDesign/HassModal.swift (close) and
 * SheetEditToolbar.swift (cancel, confirm). Close dismisses a viewing or control sheet: a circle x trailing, never text "Done" or "Close"
 * (owner 2026-10-13). Create and edit sheets: circle x Cancel leading and a check on a filled #0071E3 circle trailing, as Calendar and
 * Reminders; the check is always visible and DISABLED until there is a change (owner 2026-10-16); while saving it shows an inline arc.
 * Pushed levels put a glass Back circle leading. Never "Done".
 */
(function () {
  var h = Mock.h, I = Mock.icon;
  function glass(sym, label, cls) { return h('button.ui-circle.ui-glass.x' + (cls ? '.' + cls : ''), { type: 'button', 'aria-label': label, title: label, html: I(sym) }); }
  /** props: none. identifier sheet.close */
  Mock.register('SheetCloseItem', function () { return glass('xmark', 'Close'); }, { source: 'apple/Sources/HassDesign/HassModal.swift' });
  /** props: none. identifier sheet.cancel */
  Mock.register('SheetCancelItem', function () { return glass('xmark', 'Cancel'); }, { source: 'apple/Sources/HassDesign/SheetEditToolbar.swift' });
  /** props: {title?:'Save', enabled?:boolean (default true), busy?:boolean}. identifier sheet.confirm */
  Mock.register('SheetConfirmItem', function (p) {
    p = p || {}; var title = p.title || 'Save', enabled = p.enabled !== false;
    if (p.busy) return h('span.ui-circle', { role: 'img', 'aria-label': (p.busyTitle || title), style: { width: '28px', height: '28px', margin: '8px', background: '#0071E3', borderRadius: '50%', color: '#fff' } }, Mock.components.ArcSpinner({ size: 'inline', label: title }));
    var b = h('button.ui-circle.ui-confirm', { type: 'button', 'aria-label': title, title: title, html: I('checkmark', { weight: 2.4 }) });
    if (!enabled) b.disabled = true;
    return b;
  }, { source: 'apple/Sources/HassDesign/SheetEditToolbar.swift', props: '{title, enabled, busy}',
    states: [{ id: 'enabled', label: 'Enabled', props: { enabled: true } }, { id: 'disabled', label: 'Disabled (no change yet)', props: { enabled: false } }, { id: 'busy', label: 'Saving (arc)', props: { busy: true } }] });
})();
