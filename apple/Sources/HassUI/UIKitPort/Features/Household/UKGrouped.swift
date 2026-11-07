#if os(iOS)
import HassCore
import HassDesign
import UIKit

// MARK: - Grouped section

/// A `List` section in the inset grouped style, on a sheet: an optional header above, rows on one card with hairlines between
/// them, an optional footer below. The Profile tab is built of these.
@MainActor
final class UKGroupedSection: UIView {
    /// The card's corner radius: the system's inset grouped corners (26 pt from iOS 26, 10 pt before).
    static var cornerRadius: CGFloat { if #available(iOS 26.0, *) { 26 } else { 10 } }

    /// - Parameters:
    ///   - header: Drawn above the card, inset to the row text.
    ///   - rows: The rows, full width.
    ///   - footer: Drawn under the card, inset to the row text.
    init(header: UIView?, rows: [UIView], footer: UIView?) {
        super.init(frame: .zero)
        let column = UIStackView.ukColumn(spacing: HassTokens.Spacing.s)
        let inset = UIEdgeInsets(top: 0, left: HassTokens.Spacing.l, bottom: 0, right: HassTokens.Spacing.l)
        if let header { column.addArrangedSubview(UKHouseholdPaddedView(header, insets: inset)) }

        let card = UIView()
        card.backgroundColor = .secondarySystemGroupedBackground
        card.layer.cornerRadius = Self.cornerRadius
        card.layer.cornerCurve = .continuous
        card.clipsToBounds = true
        let list = UIStackView.ukColumn(spacing: 0)
        for (index, row) in rows.enumerated() {
            if index > 0 { list.addArrangedSubview(UKGroupedHairline()) }
            list.addArrangedSubview(row)
        }
        card.addSubview(list)
        list.ukPin(to: card)
        column.addArrangedSubview(card)

        if let footer { column.addArrangedSubview(UKHouseholdPaddedView(footer, insets: inset)) }
        addSubview(column)
        column.ukPin(to: self)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

/// The hairline between two rows of a grouped card, inset 16 pt from the leading edge.
@MainActor
final class UKGroupedHairline: UIView {
    init() {
        super.init(frame: .zero)
        let line = UIView()
        line.backgroundColor = .separator
        line.translatesAutoresizingMaskIntoConstraints = false
        addSubview(line)
        NSLayoutConstraint.activate([
            line.leadingAnchor.constraint(equalTo: leadingAnchor, constant: HassTokens.Spacing.l),
            line.trailingAnchor.constraint(equalTo: trailingAnchor),
            line.topAnchor.constraint(equalTo: topAnchor), line.bottomAnchor.constraint(equalTo: bottomAnchor),
            line.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
        ])
        isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

// MARK: - Row button

/// A tappable row of a grouped card: a leading symbol and title, a value in secondary ink and a chevron
/// (`LocationAccountSection`'s Share Location row). One button to VoiceOver: the title, with the value as its value. A ``UKRowButton``
/// around the canonical row.
@MainActor
final class UKGroupedRowButton: UKRowButton {
    var value: String = "" { didSet { refresh() } }
    var hint: String? { didSet { accessibilityHint = hint } }

    init(title: String, symbol: String, identifier: String) {
        var content = UKRowContent(title, symbol: symbol, glyph: UKDesignInk.primary, showsChevron: true)
        content.minHeight = HassTokens.minTarget
        super.init(UKRowView(content, surface: .sheet))
        accessibilityIdentifier = identifier
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func refresh() {
        var content = row.rowContent
        content.value = value.isEmpty ? nil : value
        row.update(content, accessory: row.accessory)
    }
}

// MARK: - Sign Out row

/// The Sign Out row (`SignOutRow`): asks first; once confirmed it waits on the server, and the row itself answers with an inline
/// arc and "Signing Out" in the label's place, at full strength. A ``UKRowButton`` around the canonical row's centred action.
@MainActor
final class UKSignOutRow: UKRowButton {
    /// What the row says and VoiceOver reads while busy.
    static let busyTitle = SignOutRow.busyTitle
    private var isBusy = false

    init(identifier: String) {
        super.init(UKRowView(Self.content(isBusy: false)))
        accessibilityIdentifier = identifier
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The row sits on the module's card with a 16 pt inset.
    private static func content(isBusy: Bool) -> UKRowContent {
        var content = UKRowContent.centeredAction("Sign Out", ink: UKDesignInk.danger, busyTitle: busyTitle, isBusy: isBusy)
        content.horizontalPadding = HassTokens.Spacing.l
        return content
    }

    func update(isSigningOut: Bool) {
        guard isBusy != isSigningOut else { return }
        isBusy = isSigningOut
        // A busy row ignores taps; VoiceOver's double tap lands on it and does nothing.
        isUserInteractionEnabled = !isSigningOut
        row.update(Self.content(isBusy: isSigningOut))
    }

    override var accessibilityValue: String? {
        get { isBusy ? "Busy" : "" }
        set {}
    }

    override func accessibilityActivate() -> Bool { isBusy ? true : super.accessibilityActivate() }
}
#endif
