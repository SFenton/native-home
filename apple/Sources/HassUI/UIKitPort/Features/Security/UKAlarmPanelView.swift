#if os(iOS)
import HassCore
import HassDesign
import UIKit

/// The security system card (direction G mockup n3; web `SecurityControls`; SwiftUI `AlarmPanel`): a badge filled with the mode's
/// colour, the mode as a fact with when it began, and the four mode buttons. On the Security page it sits on a module, in a sheet on
/// the sheet's cell colour. A triggered alarm reddens the card.
///
/// Arming sends at once; Disarm asks first. The tapped mode shows until Home Assistant reports a change (rolled back if the call
/// fails; `.agents/patterns/optimistic-actions.md`). Tapping the current mode does nothing.
///
/// ```swift
/// let card = UKAlarmPanelView(context: context, caller: caller) { [weak self] in self }   // the controller the disarm alert rises from
/// ```
@MainActor
final class UKAlarmPanelView: UIView, UKGridMeasuring {
    /// Space between the mode buttons: 12 pt around bezelled controls, so a mis-tap on Disarm beside Home is less likely.
    static let modeSpacing = AlarmPanel.modeSpacing
    /// What the card says for 4 s after Home Assistant rejects a mode change (the tapped mode rolls back).
    static let failureMessage = AlarmPanel.failureMessage
    /// The badge fill when the panel's state is unknown or hidden.
    private static let neutralBadge: UInt32 = 0x636366

    private let context: UKContext
    private let caller: any HassServiceCalling
    private let presenter: () -> UIViewController?
    private let surface: TileSurface

    private let module = UKModuleView(.thin)
    private let sheetGround = UIView()
    private let wash = UIView()
    private let header = UIView()
    private let badge = UIView()
    private let badgeIcon = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let grid = UKDynamicGridView(configuration: UKGridConfiguration(minCellWidth: 64, maxColumns: 4, spacing: HassTokens.Spacing.m, equalRowHeights: true))
    private var buttons: [UKAlarmModeButton] = []
    private var alert: UKInlineAlertView?
    private let bag = UKObservationBag()
    private var actions: OptimisticActions?
    private var wasFailed = false
    private var hasRendered = false

    var hinge: CGRect? {
        get { grid.hinge }
        set { grid.hinge = newValue }
    }

    /// - Parameters:
    ///   - presenter: The controller the disarm confirmation is presented from.
    init(context: UKContext, caller: any HassServiceCalling, presenter: @escaping () -> UIViewController?) {
        self.context = context
        self.caller = caller
        self.presenter = presenter
        surface = context.surface
        super.init(frame: .zero)
        layer.cornerRadius = HassTokens.Radius.module
        layer.cornerCurve = .continuous
        clipsToBounds = true
        switch surface {
        case .page:
            module.isUserInteractionEnabled = false
            addSubview(module)
        case .sheet:
            sheetGround.backgroundColor = UKInk.sheetCell
            sheetGround.isUserInteractionEnabled = false
            addSubview(sheetGround)
        }
        wash.backgroundColor = UIColor(rgb: ColorFamily.securityTriggered.spec.fill ?? 0xD70015)
        wash.alpha = 0
        wash.isUserInteractionEnabled = false
        addSubview(wash)

        header.isAccessibilityElement = true
        header.accessibilityLabel = "Security System"
        header.accessibilityIdentifier = "security.system.state"
        addSubview(header)
        badge.isUserInteractionEnabled = false
        badge.backgroundColor = UIColor(rgb: Self.neutralBadge)
        badgeIcon.contentMode = .center
        badgeIcon.tintColor = .white
        badge.addSubview(badgeIcon)
        header.addSubview(badge)
        titleLabel.numberOfLines = 0
        titleLabel.textColor = UKInk.primary
        subtitleLabel.numberOfLines = 0
        header.addSubview(titleLabel)
        header.addSubview(subtitleLabel)

        buttons = SecurityConfig.modeButtons.map { mode in
            let button = UKAlarmModeButton(mode: mode)
            button.onTap = { [weak self] in self?.select(mode) }
            return button
        }
        grid.setItems(buttons.map { UKGridItem($0) })
        addSubview(grid)

        ukOnContentSizeChange { [weak self] in
            guard let self else { return }
            titleLabel.font = UKFont.preferred(.title2, weight: .bold, traits: traitCollection)
            subtitleLabel.font = UKFont.preferred(.subheadline, traits: traitCollection)
            grid.configuration.minCellWidth = UKFont.scaled(64, relativeTo: .footnote, traits: traitCollection)
            invalidateLayout()
        }
        registerForTraitChanges([UITraitUserInterfaceStyle.self, UITraitAccessibilityContrast.self]) { (view: UKAlarmPanelView, _) in view.bindState() }
        NotificationCenter.default.addObserver(self, selector: #selector(transparencyChanged), name: UIAccessibility.reduceTransparencyStatusDidChangeNotification, object: nil)
        bindState()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func transparencyChanged() { bindState() }

    // MARK: State

    private var badgeSize: CGFloat { UKFont.scaled(44, relativeTo: .title2, traits: traitCollection) }

    private func invalidateLayout() {
        setNeedsLayout()
        var view: UIView? = superview
        while let current = view {
            current.setNeedsLayout()
            view = current.superview
        }
    }

    /// (Re)binds the card to the alarm entity and the optimistic path, which exists only after the first tap.
    private func bindState() {
        bag.removeAll()
        let box = context.store.entity(SecurityConfig.alarmEntityId)
        bag.observe { [weak self] in
            guard let self else { return }
            let live = box.state
            let shown = actions?.shown(SecurityConfig.alarmEntityId) ?? live?.state
            let unavailable = live?.isUnavailable ?? true
            let redacting = ScreenshotPrivacy.isRedacting
            let triggered = !redacting && shown == "triggered"
            let failed = actions?.isFailed(SecurityConfig.alarmEntityId) ?? false
            render(shown: shown, live: live, unavailable: unavailable, redacting: redacting, triggered: triggered, failed: failed)
        }
    }

    private func render(shown: String?, live: EntityState?, unavailable: Bool, redacting: Bool, triggered: Bool, failed: Bool) {
        let animated = hasRendered && window != nil
        hasRendered = true
        let isLight = traitCollection.userInterfaceStyle == .light
        // Header: the same facts as the SwiftUI header.
        let family = redacting || unavailable ? nil : ColorFamily.security(alarmState: shown)
        let title = redacting ? "Hidden" : (unavailable ? "Unavailable" : SecurityConfig.panelTitle(shown))
        let since = redacting || unavailable ? nil : live.flatMap { SecurityConfig.sinceText($0.lastChanged) }
        let subtitle = ["Security System", since].compactMap { $0 }.joined(separator: " · ")
        let symbol = SymbolMap.symbol(for: redacting ? "mdi:shield-outline" : SecurityConfig.alarmIcon(for: shown))
        titleLabel.text = title
        subtitleLabel.text = subtitle
        header.accessibilityValue = redacting ? "Hidden" : [title, since].compactMap { $0 }.joined(separator: ", ")
        badgeIcon.image = UKFont.symbol(symbol, style: .title3, weight: .bold, filled: true, traits: traitCollection)
        badgeIcon.alpha = unavailable ? 0.5 : 1

        // The subtitle's ink: the sheet's secondary ink, a stronger one over a light sheet's red alarm wash, or the module's on a page.
        let subtitleInk: UIColor
        if surface == .sheet {
            subtitleInk = triggered && isLight ? UKInk.secondary : UKInk.secondaryInSheet
        } else {
            subtitleInk = UIColor(HassTokens.RGB.Surface.secondaryOnModule)
        }
        let badgeFill = UIColor(rgb: family?.spec.fill ?? Self.neutralBadge)
        let washAlpha: CGFloat
        switch surface {
        case .sheet: washAlpha = triggered ? (isLight ? 0.16 : 0.42) : 0
        case .page: washAlpha = triggered ? (UIAccessibility.isReduceTransparencyEnabled ? 0.6 : 0.42) : 0
        }
        let colors = {
            self.badge.backgroundColor = badgeFill
            self.subtitleLabel.textColor = subtitleInk
            self.wash.alpha = washAlpha
            if self.surface == .page { self.module.density = triggered ? .dense : .thin }
        }
        if animated { UKMotion.stateColor(colors) } else { colors() }

        for button in buttons {
            button.configure(isSelected: !redacting && shown == button.mode.state, isUnavailable: unavailable, onAlarm: triggered, animated: animated)
        }

        // The failure line takes room for 4 s after a rejected change.
        if failed != (alert != nil) {
            if failed {
                let alert = UKInlineAlertView(Self.failureMessage, severity: .error)
                alert.accessibilityIdentifier = "security.alarm.failure"
                addSubview(alert)
                self.alert = alert
            } else {
                alert?.removeFromSuperview()
                alert = nil
            }
            updateAccessibilityElements()
            invalidateLayout()
        }
        if failed, !wasFailed {
            UKTapFeedback.failure()
            Announcer.announce(Self.failureMessage)
        }
        wasFailed = failed
        invalidateLayout()
    }

    private func updateAccessibilityElements() {
        accessibilityElements = [header] + buttons + (alert.map { [$0] } ?? [])
    }

    // MARK: Actions

    /// Sends the mode, asking first when it disarms.
    private func select(_ mode: SecurityConfig.AlarmMode) {
        let live = context.store.entity(SecurityConfig.alarmEntityId).state?.state
        let current = actions?.shown(SecurityConfig.alarmEntityId) ?? live
        guard current != mode.state else { return }
        if mode.needsConfirmation {
            guard let presenter = presenter() else { return }
            UKAlerts.alert(AlertCopy.disarm, from: presenter) { [weak self] in self?.send(SecurityConfig.disarmMode) }
        } else {
            send(mode)
        }
    }

    private func send(_ mode: SecurityConfig.AlarmMode) {
        let created = actions == nil
        let actions = actions ?? OptimisticActions(store: context.store, rules: [SecurityConfig.alarmEntityId: .liveChange], caller: caller)
        self.actions = actions
        if created { bindState() }
        // Live change clears it: the panel reports "arming" on the way, and the page should follow the truth.
        actions.perform(mode.call, showing: [OptimisticIntent(SecurityConfig.alarmEntityId, value: mode.state)])
    }

    // MARK: Layout

    private var insets: UIEdgeInsets {
        UIEdgeInsets(top: HassTokens.Spacing.l, left: HassTokens.Spacing.m, bottom: HassTokens.Spacing.m, right: HassTokens.Spacing.m)
    }

    private var rowGap: CGFloat { HassTokens.Spacing.m + 2 }

    private func headerHeight(width: CGFloat) -> CGFloat {
        let inner = max(1, width - 2 * HassTokens.Spacing.xs)
        let textWidth = max(1, inner - badgeSize - HassTokens.Spacing.m)
        let bound = CGSize(width: textWidth, height: CGFloat.greatestFiniteMagnitude)
        let text = ceil(titleLabel.sizeThatFits(bound).height) + 2 + ceil(subtitleLabel.sizeThatFits(bound).height)
        return max(badgeSize, text)
    }

    func gridHeight(forWidth width: CGFloat) -> CGFloat {
        let inner = max(0, width - insets.left - insets.right)
        var height = insets.top + headerHeight(width: inner) + rowGap + grid.gridHeight(forWidth: inner)
        if let alert { height += rowGap + alert.sizeThatFits(CGSize(width: inner, height: CGFloat.greatestFiniteMagnitude)).height }
        return ceil(height + insets.bottom)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: size.width, height: gridHeight(forWidth: size.width)) }

    override func layoutSubviews() {
        super.layoutSubviews()
        module.frame = bounds
        sheetGround.frame = bounds
        wash.frame = bounds
        let inner = max(0, bounds.width - insets.left - insets.right)
        let headerHeight = headerHeight(width: inner)
        let mirror = effectiveUserInterfaceLayoutDirection == .rightToLeft
        header.frame = CGRect(x: insets.left, y: insets.top, width: inner, height: headerHeight)
        let headerInner = max(1, inner - 2 * HassTokens.Spacing.xs)
        let diameter = badgeSize
        let textX = HassTokens.Spacing.xs + diameter + HassTokens.Spacing.m
        let textWidth = max(1, inner - textX - HassTokens.Spacing.xs)
        let bound = CGSize(width: textWidth, height: CGFloat.greatestFiniteMagnitude)
        let titleHeight = ceil(titleLabel.sizeThatFits(bound).height)
        let subtitleHeight = ceil(subtitleLabel.sizeThatFits(bound).height)
        let textTop = (headerHeight - (titleHeight + 2 + subtitleHeight)) / 2
        func place(_ view: UIView, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
            view.frame = CGRect(x: mirror ? inner - x - width : x, y: y, width: width, height: height)
        }
        _ = headerInner
        place(badge, x: HassTokens.Spacing.xs, y: (headerHeight - diameter) / 2, width: diameter, height: diameter)
        badge.layer.cornerRadius = diameter / 2
        badgeIcon.frame = badge.bounds
        place(titleLabel, x: textX, y: textTop, width: textWidth, height: titleHeight)
        place(subtitleLabel, x: textX, y: textTop + titleHeight + 2, width: textWidth, height: subtitleHeight)
        titleLabel.textAlignment = mirror ? .right : .left
        subtitleLabel.textAlignment = mirror ? .right : .left
        var y = insets.top + headerHeight + rowGap
        let gridHeight = grid.gridHeight(forWidth: inner)
        grid.frame = CGRect(x: insets.left, y: y, width: inner, height: gridHeight)
        y += gridHeight
        if let alert {
            let size = alert.sizeThatFits(CGSize(width: inner, height: CGFloat.greatestFiniteMagnitude))
            alert.frame = CGRect(x: insets.left, y: y + rowGap, width: inner, height: size.height)
        }
        updateAccessibilityElements()
    }
}

// MARK: - Mode button

/// One alarm mode: glyph over a short label, filled with the mode's colour family while selected (direction G mockup n3; web
/// `SecurityCard`). At least 64 pt tall, with equal heights across the row.
@MainActor
final class UKAlarmModeButton: UIControl {
    let mode: SecurityConfig.AlarmMode
    var onTap: (() -> Void)?

    private let fill = UIView()
    private let edge = UIImageView()
    private let icon = UIImageView()
    private let label = UILabel()
    private var isChosen = false
    private var isDimmed = false
    private var onAlarm = false
    private var configured = false

    init(mode: SecurityConfig.AlarmMode) {
        self.mode = mode
        super.init(frame: .zero)
        fill.isUserInteractionEnabled = false
        fill.layer.cornerRadius = HassTokens.Spacing.l
        fill.layer.cornerCurve = .continuous
        fill.clipsToBounds = true
        edge.isUserInteractionEnabled = false
        edge.contentMode = .scaleToFill
        icon.contentMode = .center
        icon.isUserInteractionEnabled = false
        label.numberOfLines = 0
        label.textAlignment = .center
        label.text = mode.buttonTitle
        label.isUserInteractionEnabled = false
        addSubview(fill)
        fill.addSubview(edge)
        addSubview(icon)
        addSubview(label)
        accessibilityLabel = mode.buttonTitle
        accessibilityIdentifier = "security.mode.\(mode.state)"
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
        ukOnContentSizeChange { [weak self] in
            guard let self else { return }
            label.font = UKFont.footnoteEmphasis(traitCollection)
            refreshIcon()
            setNeedsLayout()
            superview?.setNeedsLayout()
        }
        registerForTraitChanges([UITraitUserInterfaceStyle.self, UITraitAccessibilityContrast.self]) { (view: UKAlarmModeButton, _) in
            view.refreshColors(animated: false)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(transparencyChanged), name: UIAccessibility.reduceTransparencyStatusDidChangeNotification, object: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func transparencyChanged() { refreshColors(animated: false) }

    @objc private func tapped() {
        UKTapFeedback.tap()
        onTap?()
    }

    func configure(isSelected: Bool, isUnavailable: Bool, onAlarm: Bool, animated: Bool) {
        let colorsChanged = isChosen != isSelected || self.onAlarm != onAlarm
        isChosen = isSelected
        isDimmed = isUnavailable
        self.onAlarm = onAlarm
        isEnabled = !isUnavailable
        accessibilityTraits = isSelected ? [.button, .selected] : [.button]
        if isUnavailable { accessibilityTraits.insert(.notEnabled) }
        accessibilityHint = isSelected ? "" : (mode.needsConfirmation ? "Disarms the security system" : "Sets the security system to \(mode.title)")
        icon.alpha = isUnavailable ? 0.5 : 1
        refreshIcon()
        if colorsChanged, animated, configured {
            UKMotion.stateColor { self.refreshColors(animated: false) }
        } else {
            refreshColors(animated: false)
        }
        configured = true
    }

    private func refreshIcon() {
        // The button's glyph (mockup n3): what each mode means for the people inside.
        icon.image = UKFont.symbol(AlarmModeButton.symbol(for: mode), style: .title3, filled: isChosen, traits: traitCollection)
    }

    private func refreshColors(animated: Bool) {
        let ink: UIColor = isChosen ? .white : UKInk.primary
        icon.tintColor = ink
        label.textColor = ink
        let finish = UKDesign.effectiveFinish(.standard, traits: traitCollection)
        if isChosen, let rgb = ColorFamily.security(alarmState: mode.state)?.spec.fill {
            fill.backgroundColor = UIColor(rgb: rgb)
            // A chosen mode is a filled tile: the same edge and sheen as the tiles (`tintedGlassEdge`), nothing with the solid finish.
            edge.image = finish == .solid ? nil : Self.glassEdge(size: fill.bounds.size, scale: traitCollection.displayScale)
        } else if onAlarm {
            fill.backgroundColor = UKInk.primary.withAlphaComponent(0.14)
            edge.image = nil
        } else {
            fill.backgroundColor = .tertiarySystemFill
            edge.image = nil
        }
    }

    private static func glassEdge(size: CGSize, scale: CGFloat) -> UIImage? {
        let tokens = TileFinish.Tokens.tintedGlass(on: .sheet)
        let paint = UKTilePaint(ground: .flat(.clear), band: nil, shade: nil, sheen: .glass(top: tokens.sheenTop, bottom: tokens.sheenBottom),
                                rim: .lit(top: tokens.rimTop, bottom: tokens.rimBottom), stroke: nil)
        return UKTileFinishImage.image(size: size, scale: scale, radius: HassTokens.Spacing.l, paint: paint)
    }

    /// Dims while pressed and never fades a disabled label, which keeps 4.5:1 (as `GlassTileButtonStyle` does for tiles).
    override var isHighlighted: Bool {
        didSet { if isHighlighted != oldValue { alpha = isHighlighted ? 0.75 : 1 } }
    }

    private var iconHeight: CGFloat { UKFont.scaled(24, relativeTo: .title3, traits: traitCollection) }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let inner = max(1, size.width - 2 * HassTokens.Spacing.xs)
        let text = ceil(label.sizeThatFits(CGSize(width: inner, height: CGFloat.greatestFiniteMagnitude)).height)
        let height = HassTokens.Spacing.s * 2 + iconHeight + HassTokens.Spacing.xs + text
        return CGSize(width: size.width, height: max(64, height))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        fill.frame = bounds
        edge.frame = fill.bounds
        let inner = max(1, bounds.width - 2 * HassTokens.Spacing.xs)
        let text = ceil(label.sizeThatFits(CGSize(width: inner, height: CGFloat.greatestFiniteMagnitude)).height)
        let content = iconHeight + HassTokens.Spacing.xs + text
        let top = (bounds.height - content) / 2
        icon.frame = CGRect(x: 0, y: top, width: bounds.width, height: iconHeight)
        label.frame = CGRect(x: HassTokens.Spacing.xs, y: top + iconHeight + HassTokens.Spacing.xs, width: inner, height: text)
        refreshColors(animated: false)
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool { bounds.contains(point) }
}

// MARK: - Hosts

/// The alarm card's host. On the Security page (`avoidsHinge: true`) the card takes the whole content width (owner, 2026-10-30), on the
/// phone, the Duo in every pose and the iPad, so its four mode buttons share the Doors tiles' four columns, and divide 2 + 2 around the
/// fold through the band-aware grid (`SecurityPage`; `.agents/patterns/hinge-avoidance.md`). In a sheet it is capped at the readable
/// 560 pt and centred. The page's group is `security.alarm.card`.
@MainActor
final class UKAlarmCardHost: UIView, UKGridMeasuring {
    let card: UKAlarmPanelView
    private let avoidsHinge: Bool
    private var hinge: CGRect?

    /// The widest the alarm card runs on the page (HIG Layout: readable width).
    static let alarmWidth = SecurityPage.alarmWidth

    init(card: UKAlarmPanelView, avoidsHinge: Bool) {
        self.card = card
        self.avoidsHinge = avoidsHinge
        super.init(frame: .zero)
        addSubview(card)
        if avoidsHinge {
            accessibilityContainerType = .semanticGroup
            accessibilityIdentifier = "security.alarm.card"
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func setHinge(_ hinge: CGRect?) {
        guard hinge != self.hinge else { return }
        self.hinge = hinge
        card.hinge = hinge
        setNeedsLayout()
    }

    private func placement(width: CGFloat) -> (x: CGFloat, width: CGFloat) {
        if avoidsHinge { return (0, width) }
        return HingeAvoidance.placement(objectWidth: min(Self.alarmWidth, width), containerWidth: width, band: nil)
    }

    func gridHeight(forWidth width: CGFloat) -> CGFloat { card.gridHeight(forWidth: placement(width: width).width) }

    override func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: size.width, height: gridHeight(forWidth: size.width)) }

    override func layoutSubviews() {
        super.layoutSubviews()
        let place = placement(width: bounds.width)
        card.frame = CGRect(x: place.x, y: 0, width: place.width, height: card.gridHeight(forWidth: place.width))
    }
}
#endif
