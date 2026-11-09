/* PrimaryButton: the one primary action of a screen. apple/Sources/HassDesign/PrimaryButton.swift, PrimaryButtonStyle.swift. At most one per screen: a 50 pt capsule filled
 * #0071E3 with a white semibold label (4.6:1 under white in both appearances). A sheet about one owner's thing may use that owner's family hue with dark text
 * (Sprinklers water cyan). There are no white or grey primary buttons. Disabled is 40% opacity; pressed 80%. Takes the height a wrapped label needs.
 * props: {title, symbol?, family?:'water'|..., disabled?, inline?}
 */
(function () {
  var h = Mock.h, I = Mock.icon;
  Mock.register('PrimaryButton', function (p) {
    var b = h('button.ui-primary' + (p.family ? '.family' : '') + (p.inline ? '.inline' : ''), { type: 'button', style: p.family ? { '--fam': 'var(--fam-' + p.family + '-glyph)' } : null }, p.symbol ? h('span', { html: I(p.symbol) }) : null, p.title);
    if (p.disabled) b.disabled = true;
    return b;
  }, { source: 'apple/Sources/HassDesign/PrimaryButton.swift', props: '{title, symbol, family, disabled, inline}',
    variants: [{ id: 'default', label: 'Default #0071E3', props: { title: 'Add to Groceries', symbol: 'cart.badge.plus' } }, { id: 'family', label: 'Owner hue (Sprinklers)', props: { title: 'Start Watering', family: 'water' } }, { id: 'long', label: 'Long label wraps', props: { title: 'Open in Cookidoo to Continue Cooking This Recipe' } }],
    states: [{ id: 'disabled', label: 'Disabled', props: { title: 'Save', disabled: true } }] });
})();
