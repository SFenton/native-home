/* NavigationFlyout: the overlay glass drawer of regular width (iPad, unfolded Duo), listing the same five sections as the tab bar. It slides
 * over the content with a scrim and never resizes it; a full-height drawer, its blur runs under the status bar and the dimming covers the whole
 * window (owner 2026-10-22). 300 pt wide; selected row = primary ink on an accent tint at 18%. design/apple/ipados.md,
 * apple/Sources/HassUI/App/Shell/NavigationFlyout.swift. Opening is `standard` (0.3 s smooth); Reduce Motion cross-fades (Mock.anim.flyout).
 * props: {selected, badges?:{chores?:number}}
 */
(function () {
  var h = Mock.h, I = Mock.icon;
  Mock.register('NavigationFlyout', function (p) {
    p = p || {}; var sel = p.selected || 'home';
    var rows = Mock.tabs.map(function (t) {
      var n = (p.badges || {})[t[0]];
      return h('button' + (t[0] === sel ? '.sel' : ''), { type: 'button', 'aria-current': t[0] === sel ? 'page' : null, 'aria-label': n ? t[1] + ', ' + n + ' overdue' : t[1] },
        h('span.ico', { html: I(t[2]) }), h('span.lb', t[1]), n ? h('span.cnt', { 'aria-hidden': 'true' }, n) : null);
    });
    return h('div', { style: { display: 'contents' } }, h('div.ui-flyout-scrim'), h('nav.ui-flyout', { 'aria-label': 'Navigation' }, h('h2', 'Navigation'), rows));
  }, { source: 'apple/Sources/HassUI/App/Shell/NavigationFlyout.swift', props: '{selected, badges}' });
})();
