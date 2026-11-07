#if os(iOS)
import HassDesign
import UIKit

/// Anything whose ink follows where it sits: a page (fixed white inks) or a sheet (the sheet's adaptive inks). The UIKit
/// counterpart of the `tileSurface` environment value; a container passes its surface down to the rows it holds.
@MainActor
protocol UKSurfaceStyled: AnyObject {
    var surface: TileSurface { get set }
}

// MARK: - Module

/// A direction G module (``ModuleBackground``): the page material for cards, inset lists and tiles on the wallpaper. A
/// translucent dark tint with 26 pt continuous corners, no rim and no live blur; opaque with Reduce Transparency. In a
/// sheet (``surface`` is `.sheet`) it is the sheet's cell colour instead, as ``ModuleList`` draws it.
///
/// ```swift
/// let card = UKModuleView(.thin)
/// card.addSubview(content)            // pin it yourself, or use `UKModuleView.wrapping(_:)`
/// ```
final class UKModuleView: UIView, UKSurfaceStyled {
    /// ``ModuleDensity/thin`` by default, ``ModuleDensity/dense`` when the content carries red or orange text.
    var density: ModuleDensity { didSet { updateFill() } }
    var surface: TileSurface { didSet { updateFill() } }
    var moduleCornerRadius: CGFloat { didSet { layer.cornerRadius = moduleCornerRadius } }

    /// - Parameters:
    ///   - density: ``ModuleDensity/thin`` (default) or ``ModuleDensity/dense``.
    ///   - cornerRadius: 26 pt for modules (default); tiles pass ``HassTokens/Radius/tile``.
    ///   - surface: `.page` (default) or `.sheet`.
    init(_ density: ModuleDensity = .thin, cornerRadius: CGFloat = HassTokens.Radius.module, surface: TileSurface = .page) {
        self.density = density
        self.surface = surface
        moduleCornerRadius = cornerRadius
        super.init(frame: .zero)
        layer.cornerRadius = cornerRadius
        layer.cornerCurve = .continuous
        updateFill()
        NotificationCenter.default.addObserver(self, selector: #selector(transparencyChanged),
                                               name: UIAccessibility.reduceTransparencyStatusDidChangeNotification, object: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func transparencyChanged() { updateFill() }

    private func updateFill() {
        backgroundColor = surface == .sheet
            ? UKDesignSurface.sheetCell
            : UKDesignSurface.moduleTint(density, reduceTransparency: UIAccessibility.isReduceTransparencyEnabled)
    }

    /// A module that holds `content`, pinned to its edges with `insets`.
    static func wrapping(_ content: UIView, density: ModuleDensity = .thin, insets: UIEdgeInsets = .zero) -> UKModuleView {
        let module = UKModuleView(density)
        content.translatesAutoresizingMaskIntoConstraints = false
        module.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: module.topAnchor, constant: insets.top),
            content.bottomAnchor.constraint(equalTo: module.bottomAnchor, constant: -insets.bottom),
            content.leadingAnchor.constraint(equalTo: module.leadingAnchor, constant: insets.left),
            content.trailingAnchor.constraint(equalTo: module.trailingAnchor, constant: -insets.right),
        ])
        return module
    }
}

// MARK: - List

/// An inset list on the wallpaper (``ModuleList``): rows on one module card with hairlines inset to the text, 26 pt corners.
/// In a sheet (`surface: .sheet`) the card is the sheet's cell colour with the sheet's hairlines. For short lists inside a
/// scrolling page; a long or live list is its own collection view.
///
/// ```swift
/// let list = UKModuleListView(rows: [
///     UKRowView(.init("Warm", symbol: "sun.max")),
///     UKRowView(.init("Cool", symbol: "snowflake")),
/// ])
/// ```
final class UKModuleListView: UIView, UKSurfaceStyled {
    var surface: TileSurface { didSet { module.surface = surface; rows.forEach(apply); restyleSeparators() } }
    private(set) var rows: [UIView] = []
    private let module: UKModuleView
    private let stack = UIStackView()
    private let hasGlyphs: Bool
    private var separators: [UKHairline] = []

    /// - Parameters:
    ///   - density: ``ModuleDensity/thin`` (default), or ``ModuleDensity/dense`` when a row carries red or orange text.
    ///   - hasGlyphs: Whether rows lead with a glyph. Hairlines start at the text, past the glyph column (default), or at the
    ///     row's 16 pt margin for rows of text alone.
    ///   - surface: `.page` or `.sheet`.
    ///   - rows: The rows, usually ``UKRowView``s or ``UKRowButton``s.
    init(_ density: ModuleDensity = .thin, hasGlyphs: Bool = true, surface: TileSurface = .page, rows: [UIView] = []) {
        self.surface = surface
        self.hasGlyphs = hasGlyphs
        module = UKModuleView(density, surface: surface)
        super.init(frame: .zero)
        module.clipsToBounds = true
        module.translatesAutoresizingMaskIntoConstraints = false
        addSubview(module)
        stack.axis = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        module.addSubview(stack)
        NSLayoutConstraint.activate([
            module.topAnchor.constraint(equalTo: topAnchor), module.bottomAnchor.constraint(equalTo: bottomAnchor),
            module.leadingAnchor.constraint(equalTo: leadingAnchor), module.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: module.topAnchor), stack.bottomAnchor.constraint(equalTo: module.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: module.leadingAnchor), stack.trailingAnchor.constraint(equalTo: module.trailingAnchor),
        ])
        setRows(rows)
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: Self, _) in self.separators.forEach { $0.rescale() } }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Replaces the rows.
    func setRows(_ newRows: [UIView]) {
        for view in stack.arrangedSubviews { stack.removeArrangedSubview(view); view.removeFromSuperview() }
        separators = []
        rows = newRows
        for (index, row) in newRows.enumerated() {
            if index > 0 {
                let hairline = UKHairline(inset: hasGlyphs ? .scaledTextInset : .fixed(HassTokens.Spacing.l), surface: surface)
                separators.append(hairline)
                stack.addArrangedSubview(hairline)
            }
            apply(row)
            stack.addArrangedSubview(row)
        }
    }

    private func apply(_ row: UIView) { (row as? UKSurfaceStyled)?.surface = surface }
    private func restyleSeparators() { separators.forEach { $0.surface = surface } }
}

/// A 0.5 pt hairline inset from the leading edge (``HassTokens/Surface/separator``), hidden from accessibility.
final class UKHairline: UIView {
    enum Inset {
        /// Where the row's text starts, scaled with the body text (``ModuleRowMetrics/textInset``).
        case scaledTextInset
        case fixed(CGFloat)
    }

    var surface: TileSurface { didSet { line.backgroundColor = UKDesignSurface.separator } }
    private let inset: Inset
    private let line = UIView()
    private var leading: NSLayoutConstraint!

    init(inset: Inset, surface: TileSurface = .page) {
        self.inset = inset
        self.surface = surface
        super.init(frame: .zero)
        isAccessibilityElement = false
        line.backgroundColor = UKDesignSurface.separator
        line.translatesAutoresizingMaskIntoConstraints = false
        addSubview(line)
        leading = line.leadingAnchor.constraint(equalTo: leadingAnchor)
        NSLayoutConstraint.activate([
            leading, line.trailingAnchor.constraint(equalTo: trailingAnchor),
            line.topAnchor.constraint(equalTo: topAnchor), line.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: 0.5),
        ])
        rescale()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func rescale() {
        switch inset {
        case .scaledTextInset:
            leading.constant = UIFontMetrics(forTextStyle: .body).scaledValue(for: ModuleRowMetrics.textInset, compatibleWith: traitCollection)
        case let .fixed(value):
            leading.constant = value
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        rescale()
    }
}
#endif
