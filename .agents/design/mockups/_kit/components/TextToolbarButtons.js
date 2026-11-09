/* TextToolbarButtons (TextToolbarButton, one button): the text Cancel and Submit buttons of a form sheet that sends something (Report an Issue, Request a Feature). Most sheets use the circle x and
 * check (SheetCancelItem, SheetConfirmItem, owner 2026-10-13/16: never "Done"); a sheet whose action is a named verb with weight (Submit) keeps the system's text buttons on glass instead, the
 * confirmation in the iOS 26 prominent style (blue #0071E3 fill, white semibold) and disabled at 40% until the form is valid. 44 pt tall targets, the title capped at 23 pt.
 * `TextToolbarButtons({cancel, submit, canSubmit})` returns a node previewing both and carries `.leading` and `.trailing`: pass them to Mock.sheet(ctx, {leading: tb.leading, trailing: tb.trailing}).
 * TextToolbarButton props: {title, prominent?, disabled?}. TextToolbarButtons props: {cancel?:'Cancel', submit?:'Submit', canSubmit?:boolean (default true)}
 */
(function () {
  var h = Mock.h;
  function TextToolbarButton(p) {
    var b = h('button.ui-tbtn' + (p.prominent ? '.prom' : '.ui-glass'), { type: 'button' }, p.title);
    if (p.disabled) b.disabled = true;
    return b;
  }
  function TextToolbarButtons(p) {
    p = p || {};
    var lead = TextToolbarButton({ title: p.cancel || 'Cancel' }), trail = TextToolbarButton({ title: p.submit || 'Submit', prominent: true, disabled: p.canSubmit === false });
    var row = h('div.ui-tbtns', lead, h('span.sp'), trail);
    row.leading = lead; row.trailing = trail;
    return row;
  }
  Mock.register('TextToolbarButton', TextToolbarButton, { source: 'apple/Sources/HassUI/Features/Settings/Feedback/FeedbackFormSheet.swift', props: '{title, prominent, disabled}',
    variants: [{ id: 'plain', label: 'Cancel (glass)', props: { title: 'Cancel' } }, { id: 'prominent', label: 'Submit (prominent)', props: { title: 'Submit', prominent: true } }, { id: 'disabled', label: 'Submit, disabled', props: { title: 'Submit', prominent: true, disabled: true } }] });
  Mock.register('TextToolbarButtons', TextToolbarButtons, { source: 'apple/Sources/HassUI/Features/Settings/Feedback/FeedbackFormSheet.swift', props: '{cancel, submit, canSubmit}',
    variants: [{ id: 'ready', label: 'Cancel and Submit', props: {} }, { id: 'invalid', label: 'Submit disabled until valid', props: { canSubmit: false } }] });
})();
