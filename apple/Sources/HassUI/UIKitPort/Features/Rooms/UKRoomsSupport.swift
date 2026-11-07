#if os(iOS)
import HassCore
import HassDesign
import UIKit

// Shared pieces of the Rooms lane's Custom Lights and Sprinklers screens: hand-laid containers that can be measured at a width
// (the page columns are hand-laid, like `UKColumnView`), the list-button row, and alerts that carry the SwiftUI identifiers.

// MARK: - Measuring

/// The height `view` wants at `width`: a ``UKGridMeasuring`` view says so itself, any other is asked.
@MainActor
func ukRoomsHeight(_ view: UIView, width: CGFloat) -> CGFloat {
    if let measuring = view as? UKGridMeasuring { return measuring.gridHeight(forWidth: width) }
    return ceil(view.sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)).height)
}

/// An Auto Layout view (a module row, a button row) measured at a width, so a hand-laid column (``UKColumnView``,
/// ``UKRoomsModuleStack``) can place it. The content is pinned to the edges; the host's frame comes from the column.
@MainActor
final class UKRoomsFittedView: UIView, UKGridMeasuring {
    let content: UIView

    init(_ content: UIView) {
        self.content = content
        super.init(frame: .zero)
        addSubview(content)
        content.ukPin(to: self)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func gridHeight(forWidth width: CGFloat) -> CGFloat {
        ceil(content.systemLayoutSizeFitting(CGSize(width: max(width, 1), height: UIView.layoutFittingCompressedSize.height),
                                             withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: size.width, height: gridHeight(forWidth: size.width)) }
}

/// A view with fixed padding around one measurable view, optionally on a rounded fill (the Copy Color From cell).
@MainActor
final class UKRoomsInsetBox: UIView, UKGridMeasuring {
    private let content: UIView
    private let insets: UIEdgeInsets

    init(_ content: UIView, insets: UIEdgeInsets, fill: UIColor? = nil, cornerRadius: CGFloat = 0) {
        self.content = content
        self.insets = insets
        super.init(frame: .zero)
        backgroundColor = fill
        layer.cornerRadius = cornerRadius
        layer.cornerCurve = .continuous
        addSubview(content)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func gridHeight(forWidth width: CGFloat) -> CGFloat {
        insets.top + insets.bottom + ukRoomsHeight(content, width: max(0, width - insets.left - insets.right))
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: size.width, height: gridHeight(forWidth: size.width)) }

    override func layoutSubviews() {
        super.layoutSubviews()
        content.frame = CGRect(x: insets.left, y: insets.top, width: max(0, bounds.width - insets.left - insets.right),
                               height: max(0, bounds.height - insets.top - insets.bottom))
    }
}

// MARK: - Module stack

/// A hairline inset to the row text, laid out by hand (`moduleRowSeparator`).
@MainActor
private final class UKRoomsHairline: UIView {
    enum Inset { case scaledTextInset, fixed(CGFloat) }
    private let inset: Inset

    init(inset: Inset) {
        self.inset = inset
        super.init(frame: .zero)
        isAccessibilityElement = false
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The 0.5 pt line is drawn by a child so the view itself can be inset.
    private let line = UIView()

    var surface: TileSurface = .page {
        didSet { line.backgroundColor = UKDesignSurface.separator }
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        if line.superview == nil {
            line.backgroundColor = UKDesignSurface.separator
            addSubview(line)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let leading: CGFloat
        switch inset {
        case .scaledTextInset:
            leading = UIFontMetrics(forTextStyle: .body).scaledValue(for: ModuleRowMetrics.textInset, compatibleWith: traitCollection)
        case let .fixed(value):
            leading = value
        }
        let mirror = effectiveUserInterfaceLayoutDirection == .rightToLeft
        line.frame = mirror
            ? CGRect(x: 0, y: 0, width: max(0, bounds.width - leading), height: bounds.height)
            : CGRect(x: leading, y: 0, width: max(0, bounds.width - leading), height: bounds.height)
    }
}

/// A module card (``ModuleList``) whose rows are laid out by hand, so a row can be a frame-laid view (a status pill grid) as well as
/// an Auto Layout row: the rows are stacked on one ``UKModuleView`` with a hairline between them, inset to the text. A
/// ``UKModuleListView`` cannot hold a row whose height depends on its width without Auto Layout, which the Sprinklers cards need.
@MainActor
final class UKRoomsModuleStack: UIView, UKGridMeasuring, UKSurfaceStyled {
    var surface: TileSurface {
        didSet {
            module.surface = surface
            hairlines.forEach { $0.surface = surface }
            rows.forEach { ($0 as? UKSurfaceStyled)?.surface = surface }
        }
    }

    /// ``ModuleDensity/dense`` while a row carries warm text.
    var density: ModuleDensity {
        get { module.density }
        set { module.density = newValue }
    }

    private(set) var rows: [UIView] = []
    private let module: UKModuleView
    private var hairlines: [UKRoomsHairline] = []
    private let hasGlyphs: Bool

    /// - Parameters:
    ///   - hasGlyphs: Whether rows lead with a glyph, so hairlines start at the text (default) or at the 16 pt margin.
    ///   - rows: Each a ``UKGridMeasuring`` view, or one ``sizeThatFits(_:)`` can measure (wrap Auto Layout rows in
    ///     ``UKRoomsFittedView``).
    init(_ density: ModuleDensity = .thin, hasGlyphs: Bool = true, surface: TileSurface = .page, rows: [UIView] = []) {
        self.surface = surface
        self.hasGlyphs = hasGlyphs
        module = UKModuleView(density, surface: surface)
        super.init(frame: .zero)
        module.clipsToBounds = true
        addSubview(module)
        setRows(rows)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Replaces the rows.
    func setRows(_ newRows: [UIView]) {
        rows.forEach { $0.removeFromSuperview() }
        hairlines.forEach { $0.removeFromSuperview() }
        hairlines = []
        rows = newRows
        for (index, row) in newRows.enumerated() {
            if index > 0 {
                let hairline = UKRoomsHairline(inset: hasGlyphs ? .scaledTextInset : .fixed(HassTokens.Spacing.l))
                hairline.surface = surface
                hairlines.append(hairline)
                module.addSubview(hairline)
            }
            (row as? UKSurfaceStyled)?.surface = surface
            module.addSubview(row)
        }
        setNeedsLayout()
    }

    private func visibleRows() -> [UIView] { rows.filter { !$0.isHidden } }

    func gridHeight(forWidth width: CGFloat) -> CGFloat {
        let visible = visibleRows()
        return visible.reduce(0) { $0 + ukRoomsHeight($1, width: width) } + 0.5 * CGFloat(max(visible.count - 1, 0))
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: size.width, height: gridHeight(forWidth: size.width)) }

    override func layoutSubviews() {
        super.layoutSubviews()
        module.frame = bounds
        var y: CGFloat = 0
        var hairlineIndex = 0
        var first = true
        for row in rows {
            guard !row.isHidden else { continue }
            if !first, hairlineIndex < hairlines.count {
                let hairline = hairlines[hairlineIndex]
                hairline.isHidden = false
                hairline.frame = CGRect(x: 0, y: y, width: bounds.width, height: 0.5)
                y += 0.5
                hairlineIndex += 1
            }
            first = false
            let height = ukRoomsHeight(row, width: bounds.width)
            row.frame = CGRect(x: 0, y: y, width: bounds.width, height: height)
            y += height
        }
        for index in hairlineIndex..<hairlines.count { hairlines[index].isHidden = true }
    }
}

// MARK: - List-button row

/// A list button's icon and title in a tint (`WrappingRowLabel` in a `Button`): the title wraps and the row grows with it, 52 pt at
/// least. Used for Reset All Lights, Reset to Warm White and Apply to All Lights. Disabled, its ink becomes the surface's secondary ink
/// (`ActionRowStyle`); pressed, it fades to 60%.
@MainActor
final class UKRoomsActionRow: UKRowButton {
    private let enabledInk: UIColor
    private let disabledInk: UIColor
    private let symbol: String

    /// - Parameters:
    ///   - enabledInk: The ink while enabled (the action tint).
    ///   - disabledInk: The ink while disabled; defaults to the enabled ink (a page row never disables).
    init(title: String, symbol: String, identifier: String, enabledInk: UIColor = UKInk.action, disabledInk: UIColor? = nil, action: @escaping () -> Void) {
        self.enabledInk = enabledInk
        self.disabledInk = disabledInk ?? enabledInk
        self.symbol = symbol
        var content = UKRowContent(title, symbol: symbol, glyph: enabledInk)
        content.titleInk = enabledInk
        super.init(UKRowView(content), onTap: action)
        accessibilityIdentifier = identifier
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isEnabled: Bool {
        didSet { if isEnabled != oldValue { restyle() } }
    }

    private func restyle() {
        var content = row.rowContent
        let ink = isEnabled ? enabledInk : disabledInk
        content.glyph = ink
        content.titleInk = ink
        row.update(content, accessory: nil)
    }
}

// MARK: - Alerts

/// ``UKAlerts/alert(_:from:onConfirm:)`` with the SwiftUI buttons' accessibility identifiers (`alert(_:isPresented:confirmID:)`):
/// UIKit has no identifier on an alert action, so after it is up the action's view is found by its title and named, which is what the
/// journeys (`customLights.resetAll.confirm`, `customLight.applyAll.confirm`) tap.
@MainActor
enum UKRoomsAlert {
    static func present(_ spec: AlertCopy.Spec, from controller: UIViewController, confirmID: String, cancelID: String = "alert.cancel",
                        onConfirm: @escaping () -> Void) {
        let alert = UIAlertController(title: spec.title, message: spec.message, preferredStyle: .alert)
        let confirm = UIAlertAction(title: spec.confirm.title, style: spec.confirm.role == .destructive ? .destructive : .default) { _ in onConfirm() }
        let cancel = UIAlertAction(title: spec.cancel.title, style: .cancel)
        // Cancel first, as the system orders a two-button alert; the confirming button is the bold default unless it is destructive.
        alert.addAction(cancel)
        alert.addAction(confirm)
        if spec.confirm.role != .destructive { alert.preferredAction = confirm }
        (controller.presentedViewController ?? controller).present(alert, animated: true) { [weak alert] in
            MainActor.assumeIsolated {
                guard let alert else { return }
                UKRoomsAlert.name(spec.confirm.title, as: confirmID, in: alert.view)
                UKRoomsAlert.name(spec.cancel.title, as: cancelID, in: alert.view)
            }
        }
    }

    /// Gives the action view that shows `title` the identifier (its label if no action view is found around it).
    private static func name(_ title: String, as identifier: String, in root: UIView) {
        func visit(_ view: UIView) -> Bool {
            if let label = view as? UILabel, label.text == title {
                var ancestor: UIView? = label
                while let current = ancestor, current !== root {
                    if String(describing: type(of: current)).contains("ActionView") {
                        current.accessibilityIdentifier = identifier
                        return true
                    }
                    ancestor = current.superview
                }
                label.accessibilityIdentifier = identifier
                return true
            }
            return view.subviews.contains(where: visit)
        }
        _ = visit(root)
    }
}

/// Where service calls go when a screen is created without a caller (never in the app: the shell and the galleries always give one).
@MainActor
final class UKRoomsNullCaller: HassServiceCalling {
    func callService(_ domain: String, _ service: String, data: [String: any Sendable]) async throws {}
}

extension UKContext {
    /// The caller, or one that drops calls.
    @MainActor
    var roomsCaller: any HassServiceCalling { caller ?? UKRoomsNullCaller() }
}
#endif
