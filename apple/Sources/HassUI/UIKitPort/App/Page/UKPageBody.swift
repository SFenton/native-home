#if os(iOS)
import HassDesign
import UIKit

// MARK: - Metrics

/// The page base's spacing, in one place (`.agents/patterns/page-base.md`). The SwiftUI pages repeat `padding(.horizontal, .l)`,
/// `padding(.vertical, .m)` and `VStack(spacing: .xl)` by hand; the port names them once so a page can neither forget nor invent them.
/// Every value is a ``HassTokens/Spacing`` token.
enum UKPageMetrics {
    /// The page's side padding (`padding(.horizontal, HassTokens.Spacing.l)`).
    static let side = HassTokens.Spacing.l
    /// The gap between the header (or the large title) and the first row.
    static let top = HassTokens.Spacing.m
    /// The gap under the last row, above the pinned bar's inset or the safe area.
    static let bottom = HassTokens.Spacing.m
    /// The gap between two sections of a page (`VStack(spacing: .xl)`).
    static let section = HassTokens.Spacing.xl
    /// The gap between a section header and its content (`VStack(spacing: .s + 2)`).
    static let sectionHeader = HassTokens.Spacing.s + 2
    /// A pane's own padding inside a split or a sheet (the same as a page's).
    static let pane = side

    /// The body padding: sides, top and bottom.
    static let padding = UIEdgeInsets(top: top, left: side, bottom: bottom, right: side)
    /// Top and bottom only: for a body whose sections inset their own sides (a full-bleed rail or grid beside padded rows).
    static let verticalPadding = UIEdgeInsets(top: top, left: 0, bottom: bottom, right: 0)
    /// The pinned bar's padding around its content: the top gap above the controls, and the sides.
    static let barInsets = UIEdgeInsets(top: HassTokens.Spacing.xs, left: side, bottom: HassTokens.Spacing.xs, right: side)
}

// MARK: - Scrolling body

/// The page body: a `ScrollView` around one measurable column up to `maxWidth` wide, centred, inside the standard padding. The one
/// scroll view of every page whose content is hand-laid (a column, a grid, a stack of sections). Install it with
/// ``UKPageViewController/install(scrollView:)``: the page base then adds the bar's inset (`contentInsetAdjustmentBehavior =
/// .automatic`, which also carries the pinned bar's inset through ``UKPagePinnedBar``), the header fade, the large title and the rule
/// that it scrolls only when its content outgrows it. A page never sets `contentInset`, `contentInsetAdjustmentBehavior` or a top
/// constant of its own. Call ``contentChanged(animated:)`` after the content changes height.
@MainActor
class UKPageScrollView: UIScrollView {
    let content: UIView & UKGridMeasuring
    var maxWidth: CGFloat
    var padding: UIEdgeInsets

    /// - Parameters:
    ///   - padding: ``UKPageMetrics/padding`` unless the content insets its own sides (``UKPageMetrics/verticalPadding``).
    init(content: UIView & UKGridMeasuring, maxWidth: CGFloat = .greatestFiniteMagnitude, padding: UIEdgeInsets = UKPageMetrics.padding) {
        self.content = content
        self.maxWidth = maxWidth
        self.padding = padding
        super.init(frame: .zero)
        addSubview(content)
        contentInsetAdjustmentBehavior = .automatic
        alwaysBounceVertical = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Lays the content out again, gliding with the standard spring (`motionSafeAnimation(MotionTokens.standard, …)`) when asked.
    func contentChanged(animated: Bool) {
        if animated, window != nil {
            UKMotion.animate(.standard) {
                self.setNeedsLayout()
                self.layoutIfNeeded()
            }
        } else {
            setNeedsLayout()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let available = max(0, bounds.width - adjustedContentInset.left - adjustedContentInset.right)
        let inner = min(maxWidth, max(0, available - padding.left - padding.right))
        let height = content.gridHeight(forWidth: inner)
        let x = padding.left + max(0, (available - padding.left - padding.right - inner) / 2)
        content.frame = CGRect(x: x, y: padding.top, width: inner, height: height)
        let size = CGSize(width: available, height: padding.top + height + padding.bottom)
        if contentSize != size { contentSize = size }
    }
}

/// A ``UKPageScrollView`` whose content pads itself (Home, Security, the rooms overview): no body padding unless asked.
@MainActor
final class UKColumnScrollView: UKPageScrollView {
    init(content: UIView & UKGridMeasuring, padding: UIEdgeInsets = .zero) {
        super.init(content: content, padding: padding)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

// MARK: - Pinned accessory

extension UKPagePinnedBar {
    /// A bar for a page's bottom accessory (a gallery's debug line, a status strip): `accessory` in ``UKPageMetrics/barInsets`` on the
    /// bar material, pinned to the bottom safe area. The page's inset for it is the bar's height, added to the safe area once, here.
    static func accessory(_ accessory: UIView) -> UKPagePinnedBar {
        let holder = UIView()
        accessory.translatesAutoresizingMaskIntoConstraints = false
        holder.addSubview(accessory)
        let insets = UKPageMetrics.barInsets
        NSLayoutConstraint.activate([
            accessory.topAnchor.constraint(equalTo: holder.topAnchor, constant: insets.top),
            accessory.bottomAnchor.constraint(equalTo: holder.bottomAnchor, constant: -insets.bottom),
            accessory.leadingAnchor.constraint(equalTo: holder.leadingAnchor, constant: insets.left),
            accessory.trailingAnchor.constraint(equalTo: holder.trailingAnchor, constant: -insets.right),
        ])
        return UKPagePinnedBar(bar: holder, alwaysMaterial: true)
    }
}

// MARK: - Pane base

/// A pane or tab shown inside a page, a split or a sheet: it never paints a ground. The page, the sheet or the split host draws the
/// ground (the wallpaper, the system grouped ground, the Settings pane's clear), so a pane on the wallpaper cannot come out black and
/// a pane in a sheet cannot differ from its neighbour. A subclass puts its content on `view`, keeps the standard spacing
/// (``UKPageMetrics``) and adds no background. Debug builds log any pane that painted one (`PANEGROUND`).
class UKPaneViewController: UIViewController {
    override func loadView() {
        view = UIView()
        view.backgroundColor = .clear
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        #if DEBUG
        if let color = view.backgroundColor, color != .clear, color.cgColor.alpha > 0.01 {
            NSLog("PANEGROUND %@ painted %@", String(describing: type(of: self)), String(describing: color))
        }
        #endif
    }
}

// MARK: - Empty split pane

/// The empty trailing pane of a split ("Select a setting to see more options", "Select an item to see its details", "Select an item
/// to edit it."): a large symbol and a headline in the secondary ink, centred (`VStack(spacing: .m)`, `padding(.xl)`, one combined
/// accessibility element: the todo page's own placeholder, which the others now share). The one empty-state placeholder for split panes.
/// Never paints a ground (``UKPaneViewController``): the split's host does.
final class UKPanePlaceholderViewController: UKPaneViewController {
    private let symbol: String
    private let text: String
    private let identifier: String

    /// - Parameter identifier: The message's accessibility identifier.
    init(symbol: String, text: String, identifier: String) {
        self.symbol = symbol
        self.text = text
        self.identifier = identifier
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        let icon = UIImageView(image: UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(textStyle: .largeTitle)))
        icon.tintColor = UKDesignInk.secondary
        icon.isAccessibilityElement = false
        let label = UILabel.uk(.headline, ink: UKDesignInk.secondary, alignment: .center)
        label.text = text
        let stack = UIStackView(arrangedSubviews: [icon, label])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = HassTokens.Spacing.m
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isAccessibilityElement = true
        stack.accessibilityLabel = text
        stack.accessibilityIdentifier = identifier
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: UKPageMetrics.section),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -UKPageMetrics.section),
        ])
    }
}
#endif
