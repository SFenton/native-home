/* ModalTabBar: a sheet's section switcher, pinned to the bottom on Liquid Glass. apple/Sources/HassUI/Common/ModalTabBar.swift, BadgedTabSegments.swift; patterns/modal-sheet.md.
 * A segmented control, not a tab bar (HIG Segmented controls: closely related subviews of one device), never at the top. COMPACT width (iPhone, folded Duo) shows the web's ICONS, each named
 * for VoiceOver by its title; REGULAR width (iPad, unfolded Duo) shows the TITLES; accessibility sizes show a MENU. Count badges (Your Summary: Overdue, Expired) draw their own segments on the
 * same glass capsule ("9+" past nine; spoken "Overdue Chores, 3 items"). Only sections with content appear. Switching a tab is a CUT, like the app's tab bar (motion.md section 4.4).
 * props: {tabs:[{id,title,symbol,badge?}], selected, ctx?}
 */
(function () {
  var h = Mock.h, I = Mock.icon;
  Mock.register('ModalTabBar', function (p) {
    var ctx = p.ctx || Mock.current || {}, tabs = p.tabs || [];
    if (ctx.axSize) {
      var cur = tabs.filter(function (t) { return t.id === p.selected; })[0] || tabs[0];
      return h('button.ui-glass.ui-menu-tabs', { type: 'button', 'aria-haspopup': 'menu', style: { width: '100%', justifyContent: 'space-between' } }, h('span', cur.title), h('span', { html: I('chevron.down', { size: '.9em' }) }));
    }
    var titled = !ctx.compact;
    var el = h('div.ui-modaltabs.ui-glass' + (titled ? '.titled' : ''), { role: 'tablist' }, tabs.map(function (t) {
      var sel = t.id === p.selected, label = t.badge ? t.title + ', ' + t.badge + (t.badge === 1 ? ' item' : ' items') : t.title;
      return h('button' + (sel ? '.sel' : ''), { type: 'button', role: 'tab', 'aria-selected': sel ? 'true' : 'false', 'aria-label': label, title: t.title },
        t.symbol && !(titled && !t.symbol) ? h('span', { html: I(t.symbol, { fill: sel }) }) : null, titled || !t.symbol ? h('span', t.title) : null, t.badge ? h('span.ui-badge', { 'aria-hidden': 'true' }, t.badge > 9 ? '9+' : t.badge) : null);
    }));
    el.style.borderRadius = '999px'; return el;
  }, { source: 'apple/Sources/HassUI/Common/ModalTabBar.swift', props: '{tabs, selected, ctx}',
    variants: [{ id: 'three', label: 'Thermostat: Control, Schedule, Settings', props: { tabs: [{ id: 'c', title: 'Control', symbol: 'thermometer.medium' }, { id: 's', title: 'Schedule', symbol: 'calendar' }, { id: 'x', title: 'Settings', symbol: 'gearshape' }], selected: 'c' } },
      { id: 'badged', label: 'Your Summary: badges', props: { tabs: [{ id: 'p', title: 'Profile', symbol: 'person' }, { id: 'o', title: 'Overdue Chores', symbol: 'exclamationmark.circle', badge: 3 }, { id: 'u', title: 'Upcoming Chores', symbol: 'calendar' }, { id: 'f', title: 'Expired Food', symbol: 'refrigerator', badge: 12 }], selected: 'o' } }] });
})();
