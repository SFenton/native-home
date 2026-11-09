/* HassModal: the sheet's inner frame, a NavigationStack with an inline title and the header circles. apple/Sources/HassDesign/HassModal.swift
 * (HassModal, modalChrome, hassSheet) and patterns/modal-sheet.md. Mock.sheet wraps this in the detent panel and the dimmed presenter; use it
 * directly in a component mockup to show a sheet's content without a device.
 *
 * Header: no translucent band, content fades out under it (header-edge-fade.md); centred title (17 semibold) with an optional one-line subtitle;
 * leading empty at the root or a glass Back circle on pushed levels (viewing and control sheets), or Cancel (create and edit sheets); trailing
 * Close, or the confirm check. A sheet with sections has a bottom ModalTabBar on glass.
 * props: {title, subtitle?, leading?:'none'|'back'|'cancel'|Node, trailing?:'close'|'confirm'|'none'|Node, confirm?:{title,enabled,busy},
 *   content:Node|Node[], tabs?:Node, fitted?:boolean}
 */
(function () {
  var h = Mock.h;
  Mock.register('HassModal', function (p) {
    var K = Mock.components, lead = p.leading, trail = p.trailing === undefined ? 'close' : p.trailing;
    function item(v, side) {
      if (v && v.nodeType) return v;
      if (v === 'back') return K.BackButton({ label: 'Back' });
      if (v === 'cancel') return K.SheetCancelItem();
      if (v === 'close') return K.SheetCloseItem();
      if (v === 'confirm') return K.SheetConfirmItem(p.confirm || {});
      return h('span.sl');
    }
    var head = h('div.ui-mhead', item(lead || 'none', 'l'), h('div.ct', h('span.ti', { role: 'heading', 'aria-level': '1' }, p.title), p.subtitle ? h('span.su', p.subtitle) : null), item(trail, 'r'));
    var body = h('div.ui-mscroll' + (p.fitted ? '.ui-mbody.fitted' : ''), p.content);
    return h('div.ui-modal', { style: { display: 'flex', flexDirection: 'column', minHeight: 0, flex: p.fitted ? '0 1 auto' : '1 1 auto' } }, head, body, p.tabs ? h('div.ui-mtabs', p.tabs) : null);
  }, { source: 'apple/Sources/HassDesign/HassModal.swift', props: '{title, subtitle, leading, trailing, confirm, content, tabs, fitted}',
    states: [{ id: 'viewing', label: 'Viewing (close trailing)', props: { title: 'Security System', subtitle: 'Armed Home', content: 'Sheet content goes here.' } },
      { id: 'edit', label: 'Edit (cancel + confirm)', props: { title: 'New Task', leading: 'cancel', trailing: 'confirm', confirm: { enabled: false }, content: 'Sheet content goes here.' } },
      { id: 'pushed', label: 'Pushed level (back)', props: { title: 'Kitchen Lights', leading: 'back', content: 'Sheet content goes here.' } }] });
})();
