/* SegmentedChoice: choosing one of 2 to 4 short options inline. apple/Sources/HassUI/Common/SegmentedChoice.swift; patterns/option-picker.md; direction-g.md Controls
 * "Choosing one option": a system segmented control, which becomes a pop-up menu at accessibility sizes (a segmented control cannot hold AX text). A sheet's section tabs use
 * ModalTabBar instead; options with swatches or descriptions use OptionPickerSheet. props: {options:string[], selected, label?, style?:'segmented'|'menu', large?}
 */
(function () {
  var h = Mock.h, I = Mock.icon;
  Mock.register('SegmentedChoice', function (p) {
    var ctx = p.ctx || Mock.current || {}, menu = p.style === 'menu' || (ctx.axSize && p.style !== 'segmented');
    if (menu) return h('button.ui-glass.ui-menu-tabs', { type: 'button', 'aria-haspopup': 'menu', 'aria-label': (p.label || 'Choice') + ', ' + p.selected, style: { color: 'var(--ink)', justifyContent: 'space-between', width: '100%', background: 'var(--fill-tertiary)', boxShadow: 'none', border: 0, borderRadius: '12px' } }, h('span', p.label ? p.label + ': ' + p.selected : p.selected), h('span', { html: I('chevron.down', { size: '.9em' }) }));
    return h('div.ui-seg' + (p.large ? '.large' : ''), { role: 'radiogroup', 'aria-label': p.label || 'Choice' }, (p.options || []).map(function (o) { return h('button' + (o === p.selected ? '.sel' : ''), { type: 'button', role: 'radio', 'aria-checked': o === p.selected ? 'true' : 'false' }, o); }));
  }, { source: 'apple/Sources/HassUI/Common/SegmentedChoice.swift', props: '{options, selected, label, style, large}',
    variants: [{ id: 'three', label: 'Three options', props: { options: ['7 Days', '30 Days', '90 Days'], selected: '30 Days', label: 'Added In The Last' } }, { id: 'two', label: 'Two options', props: { options: ['White', 'Color'], selected: 'White', label: 'Mode', large: true } }, { id: 'menu', label: 'Menu form (accessibility sizes)', props: { options: ['7 Days', '30 Days', '90 Days'], selected: '30 Days', label: 'Added In The Last', style: 'menu' } }] });
})();
