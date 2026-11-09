/* FloatingActionBar: a page's bottom toolbar of floating glass buttons (Add Task, Add Groceries, Scan Item, Search, Sort, Filter).
 * apple/Sources/HassDesign/FloatingActionBar.swift; patterns/floating-actions.md. One bar per page, on the navigation layer: the page's ONE primary action is
 * a labelled 52 pt capsule of Liquid Glass tinted #0071E3 (`prominent`); a secondary labelled action is untinted glass; icon-only actions are 52 pt glass circles
 * that keep their title as the VoiceOver label; `active` (a sort or filter applied) tints the circle #F2F2F7 under a black glyph. Search is a glass capsule
 * filling the leading space. At ACCESSIBILITY sizes it reflows into two rows: labelled actions full width (title wraps by word), the magnifier and circles in a
 * trailing row (every target at least 44 pt). The bar adds its height to the scroll view's bottom safe area (rows peek through the glass).
 * props: {actions:[{id,title,symbol,showsTitle?:true,active?:boolean,prominent?:true}], search?:{prompt,text?}, ctx?}
 */
(function () {
  var h = Mock.h, I = Mock.icon;
  Mock.register('FloatingActionBar', function (p) {
    var ctx = p.ctx || Mock.current || {}, ax = !!ctx.axSize;
    function cap(a) { return h('button.cap.ui-glass' + (a.prominent === false ? '' : '.tint.prom'), { type: 'button', 'aria-label': a.title, style: { '--tint': '#0071E3' } }, h('span', { html: I(a.symbol) }), a.title); }
    function circ(a) { return h('button.circ.ui-glass' + (a.active ? '.active' : ''), { type: 'button', 'aria-label': a.title, 'aria-pressed': a.active ? 'true' : null, title: a.title, html: I(a.symbol) }); }
    var acts = (p.actions || []).map(function (a) { return a.showsTitle === false ? circ(a) : cap(a); });
    var search = p.search ? (ax ? circ({ title: p.search.prompt, symbol: 'magnifyingglass' }) : h('button.search.ui-glass', { type: 'button', 'aria-label': p.search.prompt }, h('span', { html: I('magnifyingglass') }), p.search.text || p.search.prompt)) : null;
    if (ax) {
      return h('div.ui-fab.ax', { role: 'toolbar' }, (p.actions || []).filter(function (a) { return a.showsTitle !== false; }).map(cap),
        h('div.circles', search, (p.actions || []).filter(function (a) { return a.showsTitle === false; }).map(circ)));
    }
    return h('div.ui-fab', { role: 'toolbar' }, search, acts);
  }, { source: 'apple/Sources/HassDesign/FloatingActionBar.swift', props: '{actions, search, ctx}',
    variants: [
      { id: 'primary', label: 'One primary action', props: { actions: [{ id: 'add', title: 'Add Task', symbol: 'plus' }] } },
      { id: 'secondary', label: 'Primary + secondary (untinted)', props: { actions: [{ id: 'add', title: 'Add Groceries', symbol: 'cart.badge.plus' }, { id: 'scan', title: 'Scan Item', symbol: 'magnifyingglass', prominent: false }] } },
      { id: 'search', label: 'Search, Sort, Filter', props: { search: { prompt: 'Search Recipes' }, actions: [{ id: 'sort', title: 'Sort', symbol: 'arrow.up.arrow.down', showsTitle: false }, { id: 'filter', title: 'Filter', symbol: 'line.3.horizontal.decrease', showsTitle: false, active: true }] } },
    ] });
})();
