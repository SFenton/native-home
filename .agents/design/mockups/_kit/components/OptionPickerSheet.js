/* OptionPickerSheet: picking one value from a short list in a sheet (input_select modes, HVAC modes, Lighting Mode). apple/Sources/HassDesign/OptionPickerSheet.swift;
 * patterns/option-picker.md. Rows are 44 pt or taller: label, an optional GradientSwatch (44 x 20 capsule), a checkmark on the current value (selected). Opaque
 * grouped ground at every detent (the default glass let a page's tiles show through). Presented at medium and large; Close trailing. 2 to 4 short choices inline
 * use SegmentedChoice instead. props: {options:[{value,label?,swatch?:[css,css]}], selected}
 */
(function () {
  var h = Mock.h, I = Mock.icon;
  Mock.register('OptionPickerSheet', function (p) {
    return h('div.ui-optlist', { role: 'listbox' }, (p.options || []).map(function (o) {
      var sel = o.value === p.selected;
      return h('button.ui-optrow' + (sel ? '.sel' : ''), { type: 'button', role: 'option', 'aria-selected': sel ? 'true' : 'false' }, h('span.tx', o.label || o.value),
        o.swatch ? h('span.ui-swatch', { 'aria-hidden': 'true', style: { background: 'linear-gradient(90deg,' + o.swatch.join(',') + ')' } }) : null, h('span.ck', { html: I('checkmark', { weight: 2.4 }) }));
    }));
  }, { source: 'apple/Sources/HassDesign/OptionPickerSheet.swift', props: '{options, selected}',
    variants: [{ id: 'plain', label: 'Labels', props: { options: [{ value: 'heat', label: 'Heat' }, { value: 'cool', label: 'Cool' }, { value: 'auto', label: 'Auto' }, { value: 'off', label: 'Off' }], selected: 'heat' } },
      { id: 'swatch', label: 'With gradient swatches (Lighting Mode)', props: { options: [{ value: 'warm', label: 'Warm White', swatch: ['#FFB347', '#FFE0A3'] }, { value: 'cool', label: 'Cool White', swatch: ['#BFE3FF', '#FFFFFF'] }, { value: 'rainbow', label: 'Rainbow', swatch: ['#FF5E5E', '#FFD35E', '#5EFF9A', '#5E9AFF'] }], selected: 'warm' } }] });
})();
