/* SettingsLinkRow: one row of the Settings list (and the Vacation chooser): a grey title3 glyph (or an app-icon preview) in a 34 pt column, a 17 pt title, a 15 pt wrapping secondary
 * subtitle and a trailing chevron. apple/Sources/HassUI/Features/Settings/SettingsScreen.swift (SettingsLinkRow). At accessibility sizes the icon sits ABOVE the text so the text keeps the
 * row's width. Put rows in a `ModuleList` (it takes nodes); inside a NavigationLink the row draws no chevron of its own (`chevron: false`).
 * props: {title, subtitle, symbol, appIcon?:Node (an AppIconPreview replacing the glyph), chevron?:boolean (default true), ctx?}
 */
(function () {
  var h = Mock.h, I = Mock.icon;
  function SettingsLinkRow(p) {
    var ctx = p.ctx || Mock.current || {}, ax = !!ctx.axSize;
    var icon = p.appIcon ? h('span.ico.app', p.appIcon) : h('span.ico', { html: I(p.symbol || 'gearshape'), 'aria-hidden': 'true' });
    var chev = p.chevron === false ? null : h('span.chev', { html: I('chevron.forward', { weight: 2.4 }), 'aria-hidden': 'true' });
    return h('button.ui-mrow.sub.press.ui-link', { type: 'button', 'aria-label': p.title + '. ' + p.subtitle, style: { '--sep-inset': 'calc(16px + 34px + 12px)' } },
      ax ? null : icon, h('span.tx', ax ? icon : null, h('span.ti', p.title), h('span.su', p.subtitle)), chev);
  }
  Mock.register('SettingsLinkRow', SettingsLinkRow, { source: 'apple/Sources/HassUI/Features/Settings/SettingsScreen.swift', props: '{title, subtitle, symbol, appIcon, chevron, ctx}',
    variants: [{ id: 'default', label: 'Glyph, title, subtitle, chevron', props: { title: 'Vacation', subtitle: 'Away-mode schedules and the Solo Trip.', symbol: 'airplane' } },
      { id: 'long', label: 'Long subtitle wraps', props: { title: 'Home Assistant Settings', subtitle: 'Open the Home Assistant configuration pages for devices, automations and integrations.', symbol: 'gearshape' } },
      { id: 'nochevron', label: 'Inside a NavigationLink (no chevron)', props: { title: 'Performance', subtitle: 'Scrolling, loading and image cache measurements.', symbol: 'gauge', chevron: false } }] });
})();
