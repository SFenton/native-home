#if os(iOS)
import HassCore
import HassDesign
import UIKit

// MARK: - Specs

/// One row of a ``UKGroupedFormController``: a view the row builds when its cell is made, what a tap does, and how the cell
/// is dressed (a `Form` row; `.listRowBackground(Color.clear)` and `.listRowInsets(EdgeInsets())` are ``isClear`` and ``fullBleed``).
struct UKFormRowSpec {
    var id: String
    /// Makes the row's content (called each time the cell is configured, so a row view owns its own bindings).
    var build: () -> UIView
    /// Runs when the row is tapped; nil for a row that is not selectable.
    var action: (() -> Void)?
    var accessories: [UICellAccessory] = []
    /// No cell background and no separators.
    var isClear = false
    /// The content takes the cell's whole width, with no margin.
    var fullBleed = false
}

/// A titled form section (`Section { } header: { FormHeader } footer: { FormFooter }`).
struct UKFormSectionSpec {
    var id: String
    var header: String?
    var footer: String?
    var rows: [UKFormRowSpec]
}

// MARK: - Controller

/// A form row that is one element (a navigation link, a checklist row): the canonical row (``UKRowView``, form metrics, on the sheet's
/// inks) with a glyph, a title, an optional second line, an optional value at the trailing edge (under the title when both do not fit on one
/// line, like `LabeledContent`), and the accessibility an explicit label, value, hint and identifier give it.
@MainActor
class UKFormLinkRow: UKRowView {
    private let bag = UKObservationBag()

    init(title: String, subtitle: String? = nil, symbol: String? = nil, identifier: String?, surface: TileSurface = .sheet) {
        super.init(.init(title, subtitle: subtitle, symbol: symbol, style: .form), surface: surface)
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityIdentifier = identifier
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Binds the row to state: `apply` reads observable state and calls `show`/`setEnabled`.
    func bind(_ apply: @escaping @MainActor (UKFormLinkRow) -> Void) {
        bag.observe { [weak self] in
            guard let self else { return }
            apply(self)
        }
    }

    func show(value: String?) {
        var content = rowContent
        content.value = value
        update(content, accessory: accessory)
    }

    func setSubtitle(_ text: String?) {
        var content = rowContent
        content.subtitle = text
        update(content, accessory: accessory)
    }

    func setEnabled(_ enabled: Bool) {
        alpha = enabled ? 1 : 0.4
        accessibilityTraits = enabled ? .button : [.button, .notEnabled]
    }
}

// MARK: - Value-owned option selection

/// The canonical eco option face, shared by the feature's form and configured controls.
@MainActor
final class UKClimateOptionRow: UKFormLinkRow {
    private let check = UIImageView(image: UIImage(systemName: "checkmark", withConfiguration: UIImage.SymbolConfiguration(font: UKFont.bodyEmphasis())))

    init(title: String, detail: String?, symbol: String? = nil, identifier: String, surface: TileSurface = .sheet) {
        super.init(title: title, subtitle: detail, symbol: symbol, identifier: identifier, surface: surface)
        check.tintColor = UKInk.action
        check.setContentHuggingPriority(.required, for: .horizontal)
        check.isAccessibilityElement = false
        setAccessory(check)
        accessibilityLabel = [title, detail].compactMap { $0 }.joined(separator: ", ")
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func showSelection(_ selected: Bool) {
        UKMotion.quick { self.check.alpha = selected ? 1 : 0 }
        accessibilityTraits = selected ? [.button, .selected] : .button
    }
}

/// Gives an independently composed option the same native row hit target and selected semantics.
@MainActor
final class UKClimateOptionButton: UKRowButton {
    override var accessibilityTraits: UIAccessibilityTraits {
        get { isSelected ? super.accessibilityTraits.union(.selected) : super.accessibilityTraits }
        set {}
    }
}
#endif
