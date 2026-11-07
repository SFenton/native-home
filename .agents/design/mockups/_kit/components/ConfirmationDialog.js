/* ConfirmationDialog (alias ActionSheet): SwiftUI's `.confirmationDialog`, the choice sheet for an action that is hard to undo or has several outcomes (Delete Task, Switch Vacuum,
 * Sign Out options, a recipe's Delete). Promoted from six author helpers (Chores.actionSheet, SA.actionSheet / SA.popover, dv.actionSheet, B.actionSheet, LL.confirmationDialog, Inv.askSheet).
 * Compact width (iPhone, folded Duo): the iOS action sheet rising from the bottom edge, an optional grey title and message over the actions (destructive red), then a SEPARATE Cancel
 * card (semibold) 8 pt below. Regular width (iPad, unfolded Duo): a popover anchored to its source with NO Cancel (an outside tap cancels). Use the Alert for a short yes/no that must
 * interrupt (Disarm, Sign Out); a confirmationDialog is for choosing among actions. Colours follow the sheet appearance (`ctx.appearance`), `dark: true` forces dark.
 * It returns a full-window scrim (`.ui-confirm-scrim`, dims at 40%): append it to a `.screen` or a Mock.page/Mock.sheet host, or pass it as Mock.sheet's `alert` (the sheet then
 * uses it as the scrim itself). Actions are buttons; a `role: 'cancel'` entry is the Cancel card (default title "Cancel").
 * props: {title?, message?, buttons:[{title, role?:'destructive'|'cancel'}], variant?:'auto'|'sheet'|'popover', anchor?:{top?,left?,right?,bottom?} (popover, in px), dark?:boolean, ctx?}
 */
(function () {
  var h = Mock.h;
  function ConfirmationDialog(p) {
    var ctx = p.ctx || Mock.current || {}, bs = p.buttons || [], variant = p.variant && p.variant !== 'auto' ? p.variant : (ctx.regular ? 'popover' : 'sheet');
    var cancel = bs.filter(function (b) { return b.role === 'cancel'; })[0], acts = bs.filter(function (b) { return b.role !== 'cancel'; });
    var theme = (p.dark || ctx.appearance === 'dark') ? 'g-dark' : 'g-light';
    var head = (p.title || p.message) ? h('div.hd', p.title ? h('div.ti', p.title) : null, p.message ? h('div.ms', p.message) : null) : null;
    var card = h('div.card', head, acts.map(function (b) { return h('button' + (b.role === 'destructive' ? '.destructive' : ''), { type: 'button' }, b.title); }));
    var label = p.title || (acts[0] && acts[0].title) || 'Choose an action';
    if (variant === 'popover') {
      var pop = h('div.ui-pop', { role: 'dialog', 'aria-label': label }, card);
      if (p.anchor) { pop.style.position = 'absolute'; Object.keys(p.anchor).forEach(function (k) { pop.style[k] = typeof p.anchor[k] === 'number' ? p.anchor[k] + 'px' : p.anchor[k]; }); }
      return h('div.ui-confirm-scrim.pop.' + theme, pop);
    }
    return h('div.ui-confirm-scrim.' + theme, h('div.ui-asheet', { role: 'dialog', 'aria-label': label }, card, h('div.card.cancel', h('button', { type: 'button' }, (cancel && cancel.title) || 'Cancel'))));
  }
  var DEMO = { title: 'Delete this task?', message: 'This can’t be undone.', buttons: [{ title: 'Delete Task', role: 'destructive' }, { title: 'Cancel', role: 'cancel' }] };
  Mock.register('ConfirmationDialog', ConfirmationDialog, { source: 'SwiftUI .confirmationDialog (apple/Sources/HassUI/Features/Chores/DonetickTaskSheet.swift, Inventory, Login flows)', props: '{title, message, buttons, variant, anchor, dark, ctx}',
    variants: [{ id: 'sheet', label: 'Action sheet (compact): grouped actions, separate Cancel', props: Object.assign({ variant: 'sheet' }, DEMO) },
      { id: 'popover', label: 'Popover (regular): anchored, no Cancel', props: Object.assign({ variant: 'popover' }, DEMO) },
      { id: 'multi', label: 'Several actions, no title', props: { variant: 'sheet', buttons: [{ title: 'Take Photo' }, { title: 'Choose from Library' }, { title: 'Remove Photo', role: 'destructive' }, { title: 'Cancel', role: 'cancel' }] } }] });
  Mock.components.ActionSheet = ConfirmationDialog;
})();
