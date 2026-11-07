/* FullScreenCover: SwiftUI's `.fullScreenCover`, a presented page with no grabber, no detents and no scaling back of the presenter (Home Assistant settings and its web pages, the camera viewer).
 * Promoted from SA.cover. It inherits the shell's dark scheme (MainTabView `preferredColorScheme(.dark)`) and, as a base elevation level, its grouped ground is systemGroupedBackground dark
 * (#000) with cells secondarySystemGroupedBackground (#1C1C1E). The window's safe areas are applied (`safeTop` above, home-indicator room below). Header as HassModal: a glass Back or none
 * leading, Close (or your node: a Reload circle) trailing.
 * props: {title, leading?:'none'|'back'|Node, trailing?:'close'|'none'|Node, content:Node|Node[], presenter?:Node (kept under it, unscaled), ground?:css, cell?:css, overlay?:Node|Node[],
 *   scrollEnd?:boolean, bleed?:boolean (content fills the window, e.g. a web page), ctx?}
 * Also `Mock.cover(ctx, props)`.
 */
(function () {
  var h = Mock.h;
  function FullScreenCover(o) {
    var ctx = o.ctx || Mock.current, d = ctx.device, K = Mock.components;
    var host = h('div.ui-host', { dataset: { indicator: 'light' }, style: { background: '#000' } });
    if (o.presenter) host.appendChild(h('div.ui-under', o.presenter));
    var sheet = h('div.ui-sheet.in-sheet.g-dark.ui-cover', { role: 'dialog', aria: { modal: 'true', label: o.title }, style: { '--sheet-ground': o.ground || '#000', '--sheet-cell': o.cell || '#1C1C1E', paddingTop: d.safeTop + 'px', paddingBottom: Math.max(0, d.safeBottom - 10) + 'px' } });
    var modal = K.HassModal({ title: o.title, leading: o.leading || 'none', trailing: o.trailing === undefined ? 'close' : o.trailing, content: o.content });
    var scroll = modal.querySelector('.ui-mscroll');
    if (scroll && o.scrollEnd) requestAnimationFrame(function () { requestAnimationFrame(function () { scroll.scrollTop = scroll.scrollHeight; }); });
    if (scroll && o.bleed) { scroll.style.padding = '0'; scroll.style.overflow = 'hidden'; }
    sheet.appendChild(modal);
    host.appendChild(sheet);
    Mock.append(host, o.overlay || null);
    return host;
  }
  Mock.cover = function (ctx, o) { return FullScreenCover(Object.assign({}, o, { ctx: ctx })); };
  Mock.register('FullScreenCover', FullScreenCover, { source: 'SwiftUI .fullScreenCover (apple/Sources/HassUI/Features/Settings/SettingsScreen.swift)', props: '{title, leading, trailing, content, presenter, ground, cell, overlay, scrollEnd, bleed, ctx}' });
})();
