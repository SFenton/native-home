/* TabBar: the five-tab bar, Home, Security, Climate, Chores, Settings (Settings last, owner 2026-10-16). On iPhone it is the floating glass
 * capsule (iOS 26); on the folded Duo the system moves it into the trailing vertical bar. A tab switch is a CUT (motion.md section 4.1).
 * Chores carries the overdue badge: the system's `.badge(Int)` prints the number itself (MainTabView; the flyout's `Text(badge, format: .number)` does too); only the Profile
 * button says "9+" past nine (ProfileSummary.badgeText). The app never hides this bar for style. On iPad (regular width, no hinge; global chrome pick 3, 2026-11-18) the system draws it at the top, in the navigation bar's row, with no menu button; the unfolded Duo keeps it (owner 2026-10-26): in the trailing vertical bar in landscape, and as the iPhone's floating bar along the bottom in portrait.
 * design/apple/iphone.md, apple/Sources/HassUI/App/Shell/AppSection.swift, MainTabView.swift.
 */
(function () {
  var h = Mock.h, I = Mock.icon;
  var TABS = [['home', 'Home', 'house'], ['security', 'Security', 'shield'], ['climate', 'Climate', 'thermometer.medium'], ['chores', 'Chores', 'checklist'], ['settings', 'Settings', 'gearshape']];
  Mock.tabs = TABS;
  /** props: {selected:'home'|..., badges?:{chores?:number}, orientation?:'horizontal'|'vertical'} */
  Mock.register('TabBar', function (p) {
    p = p || {};
    var vertical = p.orientation === 'vertical', top = p.orientation === 'top', sel = p.selected || 'home';
    var btns = TABS.map(function (t) {
      var n = (p.badges || {})[t[0]];
      var label = n ? t[1] + ', ' + n + ' overdue' : t[1];
      return h('button' + (t[0] === sel ? '.sel' : ''), { type: 'button', 'aria-label': label, 'aria-current': t[0] === sel ? 'page' : null, dataset: { tab: t[0] } },
        top ? null : h('span', { html: I(t[2], { fill: t[0] === sel }) }), vertical ? null : h('span', t[1]), n ? h('span.ui-badge', { 'aria-hidden': 'true' }, n) : null);
    });
    return vertical ? h('div.tabs.ui-glass', { role: 'tablist' }, btns) : h(top ? 'nav.ui-tabbar.top.ui-glass' : 'nav.ui-tabbar.ui-glass', { 'aria-label': 'Sections' }, btns);
  }, { source: 'apple/Sources/HassUI/App/MainTabView.swift', props: '{selected, badges, orientation}',
    variants: TABS.map(function (t) { return { id: t[0], label: t[1] + ' selected', props: { selected: t[0] } }; }),
    states: [{ id: 'badge', label: 'Chores badge 3', props: { selected: 'home', badges: { chores: 3 } } }, { id: 'vertical', label: 'Vertical (Duo rail)', props: { selected: 'security', orientation: 'vertical' } }, { id: 'top', label: 'Top (iPad, regular width)', props: { selected: 'chores', badges: { chores: 3 }, orientation: 'top' } }] });
})();
