/* ContentUnavailableView: SwiftUI's empty or failed state, a large secondary symbol, a bold title, a secondary description and optional actions (Chores empty lists, Unable to Load Task, Not
 * Signed In, a recipe search with no match, Coming in a later update). Promoted from four author helpers (SA, HF, SN, Chores.unavailableView). On a page it reads white on the wallpaper; in a sheet
 * the sheet ink. The symbol scales with Dynamic Type (about 1.45 x the title), the description wraps at 34 characters. An action is a prominent button (`PrimaryButton`) or, with
 * `plain: true`, a plain text button. Not a list row: in a list use plain wrapping text (InventoryEmptyState).
 * props: {symbol, title, description?, action?:string|{title, plain?}, stack?:boolean (more top space, as the page-level empty state), label?}
 */
(function () {
  var h = Mock.h, I = Mock.icon;
  function ContentUnavailableView(p) {
    var act = typeof p.action === 'string' ? { title: p.action } : p.action;
    return h('div.ui-cuv' + (p.stack ? '.stack' : ''), { role: 'group', 'aria-label': p.label || (p.title + (p.description ? '. ' + p.description : '')) },
      h('div.sym', { html: I(p.symbol || 'tray'), 'aria-hidden': 'true' }), h('h3.ti', { role: 'heading', 'aria-level': '2' }, p.title), p.description ? h('p.ds', p.description) : null,
      act ? h('div.act', act.plain ? h('button.plain', { type: 'button' }, act.title) : Mock.components.PrimaryButton({ title: act.title, inline: true })) : null);
  }
  Mock.register('ContentUnavailableView', ContentUnavailableView, { source: 'SwiftUI ContentUnavailableView (apple/Sources/HassUI/Features/Chores/TodoPageView.swift, Placeholders/PlaceholderScreen.swift)', props: '{symbol, title, description, action, stack, label}',
    variants: [{ id: 'plain', label: 'Title and description', props: { symbol: 'checklist', title: 'No Tasks', description: 'Tasks you add show up here.' } },
      { id: 'action', label: 'With a prominent action', props: { symbol: 'tray', title: 'Nothing Here Yet', description: 'Add the first one to get started.', action: 'Add Item' } },
      { id: 'plain-action', label: 'With a plain text action', props: { symbol: 'exclamationmark.triangle', title: 'Unable to Load Task', description: 'The task server did not answer.', action: { title: 'Try Again', plain: true } } },
      { id: 'stack', label: 'Page-level (more space above)', props: { symbol: 'person.crop.circle.badge.exclamationmark', title: 'Not Signed In', stack: true } }] });
})();
