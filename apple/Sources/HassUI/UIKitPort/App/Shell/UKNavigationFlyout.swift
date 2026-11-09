#if os(iOS)
import HassCore
import HassDesign
import UIKit

/// The regular-width navigation panel: an overlay that slides in from the leading edge over a full-window scrim, like the web's
/// `drawer-only` layout. The UIKit counterpart of ``NavigationFlyout``: it never pushes or resizes the content
/// (`.agents/design/apple/ipados.md`).
///
/// Closes on a destination, a scrim tap, Escape or the VoiceOver escape gesture. Three layers, back to front: a touch shield over
/// the whole window (so nothing under the panel answers while it is open or still sliding away), the dimming scrim with its close
/// target beside the panel, and the panel with its heading and one row per section.
final class UKNavigationFlyoutView: UIView {
    private let navigator: ShellNavigator
    private weak var shell: UKShellEnvironment?
    private let shield = UIView()
    private let dim = UIView()
    private let closeTarget = UIButton(type: .custom)
    private let panel = UKFlyoutPanel()
    private let bag = UKObservationBag()
    private var isOpen = false
    private var isSettling = false
    private var settleToken = 0

    init(navigator: ShellNavigator, shell: UKShellEnvironment?) {
        self.navigator = navigator
        self.shell = shell
        super.init(frame: .zero)
        backgroundColor = .clear
        shield.backgroundColor = .clear
        shield.isAccessibilityElement = false
        shield.accessibilityElementsHidden = true
        shield.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(dismissTapped)))
        addSubview(shield)
        dim.backgroundColor = UIColor.black.withAlphaComponent(0.32)
        dim.isUserInteractionEnabled = false
        dim.accessibilityElementsHidden = true
        addSubview(dim)
        closeTarget.accessibilityLabel = "Close Navigation"
        closeTarget.accessibilityIdentifier = "nav.flyout.scrim"
        closeTarget.addAction(UIAction { [weak self] _ in self?.navigator.dismissFlyout() }, for: .touchUpInside)
        addSubview(closeTarget)
        panel.accessibilityIdentifier = "nav.flyout"
        panel.onEscape = { [weak self] in self?.navigator.dismissFlyout() }
        panel.onClose = { [weak self] in self?.navigator.dismissFlyout() }
        panel.onSelect = { [weak self] in self?.navigator.select($0) }
        addSubview(panel)
        // The panel's rows come first for VoiceOver; the close target is reachable after them.
        accessibilityElements = [panel, closeTarget]
        shield.isHidden = true
        dim.alpha = 0
        closeTarget.isHidden = true
        panel.isHidden = true
        bag.observe { [weak self] in
            guard let self else { return }
            self.setOpen(self.navigator.isFlyoutOpen)
        }
        bag.observe { [weak self] in
            guard let self else { return }
            let overdue = self.navigator.overdueChores
            let selection = self.navigator.selection
            self.panel.update(selection: selection, overdue: overdue)
        }
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: UKNavigationFlyoutView, _) in
            view.panel.contentSizeChanged()
            view.setNeedsLayout()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The overlay is invisible to touches except while the flyout is open or settling closed.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard isOpen || isSettling else { return nil }
        return super.hitTest(point, with: event)
    }

    @objc private func dismissTapped() { navigator.dismissFlyout() }

    // MARK: Layout

    private var panelWidth: CGFloat {
        let preferred = UKShellFont.scaled(NavigationFlyoutMetrics.panelWidth, relativeTo: .body, traits: traitCollection)
        return NavigationFlyoutMetrics.panelWidth(preferred: preferred, available: bounds.width)
    }

    private var isRightToLeft: Bool { effectiveUserInterfaceLayoutDirection == .rightToLeft }

    private func panelFrame(open: Bool) -> CGRect {
        let width = panelWidth
        let openX = isRightToLeft ? bounds.width - width : 0
        let closedX = isRightToLeft ? bounds.width : -width
        return CGRect(x: open ? openX : closedX, y: 0, width: width, height: bounds.height)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        shield.frame = bounds
        dim.frame = bounds
        let width = panelWidth
        // The strip beside the panel: the window less the panel, which has none left when the panel takes it all. It starts
        // below the status bar (the shield catches a tap up there).
        let strip = max(bounds.width - width, 0)
        let top = safeAreaInsets.top
        closeTarget.frame = CGRect(x: isRightToLeft ? 0 : width, y: top, width: strip, height: max(bounds.height - top, 0))
        if isOpen {
            panel.frame = panelFrame(open: true)
        } else if !isSettling {
            panel.frame = panelFrame(open: false)
        }
    }

    // MARK: Open and close

    private func setOpen(_ open: Bool) {
        guard open != isOpen else { return }
        isOpen = open
        let reduce = shell?.reduceMotion ?? UIAccessibility.isReduceMotionEnabled
        settleToken += 1
        let token = settleToken
        if open {
            isSettling = false
            shield.isHidden = false
            closeTarget.isHidden = false
            panel.isHidden = false
            layoutIfNeeded()
            if reduce {
                panel.frame = panelFrame(open: true)
                panel.alpha = 0
            } else {
                panel.frame = panelFrame(open: false)
                panel.alpha = 1
            }
            dim.alpha = 0
            // `MotionTokens.standard` (a smooth spring of 0.3 s); Reduce Motion fades in `quick` (0.2 s).
            let animations = {
                self.dim.alpha = 1
                self.panel.alpha = 1
                self.panel.frame = self.panelFrame(open: true)
            }
            if reduce {
                UIView.animate(withDuration: MotionTokens.quickDuration, delay: 0, options: [.curveEaseOut, .allowUserInteraction], animations: animations)
            } else {
                UIView.animate(springDuration: MotionTokens.standardDuration, bounce: 0, options: [.allowUserInteraction], animations: animations)
            }
            panel.moveAccessibilityFocusToHeading()
        } else {
            isSettling = true
            let animations = {
                self.dim.alpha = 0
                if reduce { self.panel.alpha = 0 } else { self.panel.frame = self.panelFrame(open: false) }
            }
            let finish: (Bool) -> Void = { [weak self] _ in
                guard let self, self.settleToken == token else { return }
                self.isSettling = false
                self.shield.isHidden = true
                self.closeTarget.isHidden = true
                self.panel.isHidden = true
                self.panel.alpha = 1
            }
            if reduce {
                UIView.animate(withDuration: MotionTokens.quickDuration, delay: 0, options: [.curveEaseOut], animations: animations, completion: finish)
            } else {
                UIView.animate(springDuration: MotionTokens.standardDuration, bounce: 0, options: [], animations: animations, completion: finish)
            }
        }
    }

    override var keyCommands: [UIKeyCommand]? {
        guard isOpen else { return nil }
        let escape = UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(escapePressed))
        escape.wantsPriorityOverSystemBehavior = true
        return [escape]
    }

    @objc private func escapePressed() { navigator.dismissFlyout() }
    override var canBecomeFirstResponder: Bool { isOpen }
}

/// The sliding panel: heading and one row per primary section, on a regular material that runs under the status bar and the home
/// indicator while the rows stay inside the safe area.
final class UKFlyoutPanel: UIView {
    private let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private let heading = UILabel()
    private let closeButton = UIButton(type: .system)
    private let headingRow = UIStackView()
    private var rows: [AppSection: UKFlyoutRow] = [:]
    var onEscape: () -> Void = {}
    var onClose: () -> Void = {}
    var onSelect: (AppSection) -> Void = { _ in } {
        didSet { rows.values.forEach { $0.onSelect = onSelect } }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        // Trailing corners round (22 pt, continuous).
        layer.cornerRadius = HassTokens.Radius.tile
        layer.cornerCurve = .continuous
        layer.maskedCorners = [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
        layer.masksToBounds = true
        blur.frame = bounds
        blur.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(blur)
        scroll.frame = bounds
        scroll.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scroll.alwaysBounceVertical = false
        scroll.contentInsetAdjustmentBehavior = .always
        scroll.showsVerticalScrollIndicator = false
        addSubview(scroll)

        stack.axis = .vertical
        stack.spacing = HassTokens.Spacing.xs
        stack.alignment = .fill
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: HassTokens.Spacing.m, leading: HassTokens.Spacing.m,
                                                                 bottom: HassTokens.Spacing.m, trailing: HassTokens.Spacing.m)
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
            stack.heightAnchor.constraint(greaterThanOrEqualTo: scroll.safeAreaLayoutGuide.heightAnchor),
        ])

        heading.text = "Navigation"
        heading.textColor = .label
        heading.numberOfLines = 0
        heading.accessibilityTraits = .header
        heading.accessibilityIdentifier = "nav.flyout.heading"
        heading.adjustsFontForContentSizeCategory = true
        heading.font = UKShellFont.preferred(.title2, weight: .bold)
        closeButton.accessibilityLabel = "Close Navigation"
        closeButton.accessibilityIdentifier = "nav.flyout.close"
        closeButton.addAction(UIAction { [weak self] _ in self?.onClose() }, for: .touchUpInside)
        headingRow.axis = .horizontal
        headingRow.alignment = .top
        headingRow.spacing = HassTokens.Spacing.s
        headingRow.isLayoutMarginsRelativeArrangement = true
        headingRow.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: HassTokens.Spacing.m, bottom: HassTokens.Spacing.s, trailing: HassTokens.Spacing.m)
        headingRow.addArrangedSubview(heading)
        stack.addArrangedSubview(headingRow)
        for section in NavigationMenu.primary {
            let row = UKFlyoutRow(section: section)
            rows[section] = row
            row.onSelect = { [weak self] in self?.onSelect($0) }
            stack.addArrangedSubview(row)
        }
        // SwiftUI's VStack is `.top`-aligned inside a `minHeight` frame: the rows keep their size and the room left over sits below
        // them. A stack stretched to the safe area would hand that room to the heading row (rows pushed to the bottom).
        let filler = UIView()
        filler.isAccessibilityElement = false
        filler.setContentHuggingPriority(UILayoutPriority(1), for: .vertical)
        filler.setContentCompressionResistancePriority(UILayoutPriority(1), for: .vertical)
        if let last = stack.arrangedSubviews.last { stack.setCustomSpacing(0, after: last) }
        stack.addArrangedSubview(filler)
        accessibilityViewIsModal = true
        isAccessibilityElement = false
        accessibilityElements = [heading, closeButton] + NavigationMenu.primary.compactMap { rows[$0] }
        contentSizeChanged()
        // The panel reads its own trait: the flyout's callback can run before the new size has reached this subview.
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: UKFlyoutPanel, _) in view.contentSizeChanged() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func accessibilityPerformEscape() -> Bool {
        onEscape()
        return true
    }

    func update(selection: AppSection, overdue: Int?) {
        for (section, row) in rows { row.update(isCurrent: section == selection, overdue: overdue) }
    }

    /// At accessibility sizes the panel can take the whole window, with no scrim strip to tap: a close button joins the heading.
    func contentSizeChanged() {
        let large = traitCollection.preferredContentSizeCategory.isAccessibilityCategory
        if large, closeButton.superview == nil {
            var configuration = UIButton.Configuration.plain()
            configuration.image = UIImage(systemName: "xmark.circle.fill")
            configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(font: UKShellFont.preferred(.title2))
                .applying(UIImage.SymbolConfiguration(hierarchicalColor: .secondaryLabel))
            configuration.baseForegroundColor = .secondaryLabel
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
            closeButton.configuration = configuration
            closeButton.setContentHuggingPriority(.required, for: .horizontal)
            closeButton.heightAnchor.constraint(greaterThanOrEqualToConstant: HassTokens.minTarget).isActive = true
            closeButton.widthAnchor.constraint(greaterThanOrEqualToConstant: HassTokens.minTarget).isActive = true
            headingRow.addArrangedSubview(closeButton)
        } else if !large, closeButton.superview != nil {
            closeButton.removeFromSuperview()
        }
        for row in rows.values { row.contentSizeChanged() }
    }

    func moveAccessibilityFocusToHeading() {
        UIAccessibility.post(notification: .screenChanged, argument: heading)
    }
}

/// One destination in the panel: the section's symbol, its name and, for Chores, the overdue count. The current section sits on an
/// accent tint, with the primary ink (white on the light accent measured 2.5:1 in the iPad audit).
final class UKFlyoutRow: UIControl {
    let section: AppSection
    private let icon = UIImageView()
    private let title = UILabel()
    private let badge = UKInsetLabel()
    private let highlight = UIView()
    private let content = UIStackView()
    private var iconWidth: NSLayoutConstraint?
    private var isCurrent = false
    private var overdue: Int?

    init(section: AppSection) {
        self.section = section
        super.init(frame: .zero)
        highlight.backgroundColor = tintColor.withAlphaComponent(0.18)
        highlight.layer.cornerRadius = HassTokens.Radius.chip
        highlight.layer.cornerCurve = .continuous
        highlight.isUserInteractionEnabled = false
        highlight.isHidden = true
        addSubview(highlight)

        icon.contentMode = .center
        icon.tintColor = .label
        icon.isAccessibilityElement = false
        title.textColor = .label
        title.adjustsFontForContentSizeCategory = true
        title.numberOfLines = 0
        title.text = section.title
        badge.textColor = .white
        badge.font = UKShellFont.preferred(.caption1, weight: .bold)
        badge.adjustsFontForContentSizeCategory = true
        badge.backgroundColor = UIColor(rgb: HassTokens.Palette.badge)
        badge.layer.masksToBounds = true
        badge.textAlignment = .center
        badge.insets = UIEdgeInsets(top: 2, left: HassTokens.Spacing.s, bottom: 2, right: HassTokens.Spacing.s)
        badge.isAccessibilityElement = false
        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        content.axis = .horizontal
        content.alignment = .center
        content.spacing = HassTokens.Spacing.m
        content.isUserInteractionEnabled = false
        content.isLayoutMarginsRelativeArrangement = true
        content.directionalLayoutMargins = NSDirectionalEdgeInsets(top: HassTokens.Spacing.s, leading: HassTokens.Spacing.m,
                                                                   bottom: HassTokens.Spacing.s, trailing: HassTokens.Spacing.m)
        content.translatesAutoresizingMaskIntoConstraints = false
        [icon, title, spacer, badge].forEach { content.addArrangedSubview($0) }
        addSubview(content)
        let width = icon.widthAnchor.constraint(equalToConstant: UKShellFont.scaled(28, relativeTo: .body))
        iconWidth = width
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
            width,
        ])
        isAccessibilityElement = true
        accessibilityIdentifier = section.navigationIdentifier
        accessibilityTraits = .button
        addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.onSelect(self.section)
        }, for: .touchUpInside)
        update(isCurrent: false, overdue: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// A tap on the row selects its section.
    var onSelect: (AppSection) -> Void = { _ in }

    func update(isCurrent: Bool, overdue: Int?) {
        self.isCurrent = isCurrent
        self.overdue = overdue
        highlight.isHidden = !isCurrent
        let text = NavigationMenu.badgeText(for: section, overdue: overdue)
        badge.isHidden = text == nil
        badge.text = text
        title.font = UKShellFont.preferred(.body, weight: isCurrent ? .semibold : .regular)
        icon.image = UIImage(systemName: section.symbol, withConfiguration: UIImage.SymbolConfiguration(font: UKShellFont.preferred(.body, weight: .semibold)))
        accessibilityLabel = NavigationMenu.accessibilityLabel(for: section, overdue: overdue)
        accessibilityTraits = isCurrent ? [.button, .selected] : .button
        setNeedsLayout()
    }

    func contentSizeChanged() {
        iconWidth?.constant = UKShellFont.scaled(28, relativeTo: .body, traits: traitCollection)
        update(isCurrent: isCurrent, overdue: overdue)
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        highlight.backgroundColor = tintColor.withAlphaComponent(0.18)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        highlight.frame = bounds
        badge.layer.cornerRadius = badge.bounds.height / 2
    }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.6 : 1 }
    }

    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: 48) }
}
#endif
