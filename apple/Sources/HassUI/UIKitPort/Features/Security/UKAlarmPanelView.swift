#if os(iOS)
import HassCore
import HassDesign
import UIKit

/// Canonical alarm presentation over values and closures. Uses the existing native grid, button,
/// motion and inline-alert primitives; no entity reads, service calls or confirmation live here.
@MainActor
class UKAlarmPanelControl: UIView, UKGridMeasuring {
    /// Presentation-only values; the host owns observation, formatting, commands and confirmation.
    struct Value {
        let title: String
        let subtitle: String
        let accessibilityLabel: String
        let accessibilityValue: String
        let symbol: String
        let badgeFill: UInt32
        let washFill: UInt32
        let selectedState: String?
        let unavailable: Bool
        let pending: Bool
        let triggered: Bool
        let failure: String?
    }

    var onSelect: ((String) -> Void)?
    /// Space between the mode buttons: 12 pt around bezelled controls, so a mis-tap on Disarm beside Home is less likely.
    static let modeSpacing = AlarmPanel.modeSpacing
    /// What the card says for 4 s after Home Assistant rejects a mode change (the tapped mode rolls back).
    static let failureMessage = AlarmPanel.failureMessage
    private let surface: TileSurface
    private let modeIdentifierPrefix: String
    private let failureIdentifier: String

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
    private var wasFailed = false
    private var hasRendered = false
    private var value: Value?
    private var failureText: String?

    var hinge: CGRect? {
        get { grid.hinge }
        set { grid.hinge = newValue }
    }
    var followsFold: Bool {
        get { grid.followsFold }
        set { grid.followsFold = newValue }
    }

    /// The surface chooses the existing page/sheet material; hosts supply every state-dependent value.
    init(surface: TileSurface, modes: [UKAlarmModeButton.Value], headerIdentifier: String = "security.system.state",
         modeIdentifierPrefix: String = "security.mode", failureIdentifier: String = "security.alarm.failure") {
        self.surface = surface
        self.modeIdentifierPrefix = modeIdentifierPrefix
        self.failureIdentifier = failureIdentifier
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
        wash.alpha = 0
        wash.isUserInteractionEnabled = false
        addSubview(wash)

        header.isAccessibilityElement = true
        header.accessibilityIdentifier = headerIdentifier
        addSubview(header)
        badge.isUserInteractionEnabled = false
        badgeIcon.contentMode = .center
        badgeIcon.tintColor = .white
        badge.addSubview(badgeIcon)
        header.addSubview(badge)
        titleLabel.numberOfLines = 0
        titleLabel.textColor = UKInk.primary
        subtitleLabel.numberOfLines = 0
        header.addSubview(titleLabel)
        header.addSubview(subtitleLabel)

        buttons = modes.map { mode in
            let button = UKAlarmModeButton(value: mode)
            button.accessibilityIdentifier = modeIdentifierPrefix + "." + mode.state
            button.onTap = { [weak self] in self?.onSelect?(mode.state) }
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
        registerForTraitChanges([UITraitUserInterfaceStyle.self, UITraitAccessibilityContrast.self]) { (view: UKAlarmPanelControl, _) in view.refresh() }
        NotificationCenter.default.addObserver(self, selector: #selector(transparencyChanged), name: UIAccessibility.reduceTransparencyStatusDidChangeNotification, object: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func transparencyChanged() { refresh() }

    private func refresh() { if let value { configure(value) } }

    /// Keeps button identities stable when copy, symbols, colors or ordering are republished.
    func setModes(_ modes: [UKAlarmModeButton.Value]) {
        let existing = Dictionary(buttons.map { ($0.value.state, $0) }, uniquingKeysWith: { first, _ in first })
        buttons = modes.map { mode in
            let button = existing[mode.state] ?? UKAlarmModeButton(value: mode)
            button.setValue(mode)
            button.accessibilityIdentifier = modeIdentifierPrefix + "." + mode.state
            button.onTap = { [weak self] in self?.onSelect?(mode.state) }
            return button
        }
        if grid.items.map(\.view) != buttons { grid.setItems(buttons.map { UKGridItem($0) }) }
        refresh()
    }

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

    func configure(_ value: Value, animated: Bool = true) {
        self.value = value
        let triggered = value.triggered, unavailable = value.unavailable
        let failed = value.failure != nil
        let animated = animated && hasRendered && window != nil
        hasRendered = true
        let isLight = traitCollection.userInterfaceStyle == .light
        // Header: the same facts as the SwiftUI header.
        titleLabel.text = value.title
        subtitleLabel.text = value.subtitle
        header.accessibilityLabel = value.accessibilityLabel
        header.accessibilityValue = value.accessibilityValue
        badgeIcon.image = UKFont.symbol(value.symbol, style: .title3, weight: .bold, filled: true, traits: traitCollection)
        badgeIcon.alpha = unavailable ? 0.5 : 1

        // The subtitle's ink: the sheet's secondary ink, a stronger one over a light sheet's red alarm wash, or the module's on a page.
        let subtitleInk: UIColor
        if surface == .sheet {
            subtitleInk = triggered && isLight ? UKInk.secondary : UKInk.secondaryInSheet
        } else {
            subtitleInk = UIColor(HassTokens.RGB.Surface.secondaryOnModule)
        }
        let badgeFill = UIColor(rgb: value.badgeFill)
        wash.backgroundColor = UIColor(rgb: value.washFill)
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
            button.configure(isSelected: value.selectedState == button.value.state,
                             isUnavailable: unavailable || value.pending, onAlarm: triggered, animated: animated)
        }

        // The failure line takes room for 4 s after a rejected change.
        if value.failure != failureText {
            alert?.removeFromSuperview()
            alert = nil
            if failed {
                let alert = UKInlineAlertView(value.failure ?? Self.failureMessage, severity: .error)
                alert.accessibilityIdentifier = failureIdentifier
                addSubview(alert)
                self.alert = alert
            } else {
                alert?.removeFromSuperview()
                alert = nil
            }
            failureText = value.failure
            updateAccessibilityElements()
            invalidateLayout()
        }
        if failed, !wasFailed {
            UKTapFeedback.failure()
            Announcer.announce(value.failure ?? Self.failureMessage)
        }
        wasFailed = failed
        invalidateLayout()
    }

    private func updateAccessibilityElements() {
        accessibilityElements = [header] + buttons + (alert.map { [$0] } ?? [])
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
    struct Value {
        let state: String
        let label: String
        let symbol: String
        let fill: UInt32
        let hint: String
    }

    private(set) var value: Value
    var onTap: (() -> Void)?

    private let fill = UIView()
    private let edge = UIImageView()
    private let icon = UIImageView()
    private let label = UILabel()
    private var isChosen = false
    private var isDimmed = false
    private var onAlarm = false
    private var configured = false

    convenience init(mode: SecurityConfig.AlarmMode) {
        self.init(value: Self.legacy(mode))
    }

    static func legacy(_ mode: SecurityConfig.AlarmMode) -> Value {
        .init(state: mode.state, label: mode.buttonTitle, symbol: AlarmModeButton.symbol(for: mode),
              fill: ColorFamily.security(alarmState: mode.state)?.spec.fill ?? 0x636366,
              hint: mode.needsConfirmation ? "Disarms the security system" : "Sets the security system to \(mode.title)")
    }

    init(value: Value) {
        self.value = value
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
        label.text = value.label
        label.isUserInteractionEnabled = false
        addSubview(fill)
        fill.addSubview(edge)
        addSubview(icon)
        addSubview(label)
        accessibilityLabel = value.label
        accessibilityIdentifier = "security.mode.\(value.state)"
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

    func setValue(_ value: Value) {
        self.value = value
        label.text = value.label
        accessibilityLabel = value.label
        refreshIcon()
        refreshColors(animated: false)
        setNeedsLayout()
    }

    func configure(isSelected: Bool, isUnavailable: Bool, onAlarm: Bool, animated: Bool) {
        let colorsChanged = isChosen != isSelected || self.onAlarm != onAlarm
        isChosen = isSelected
        isDimmed = isUnavailable
        self.onAlarm = onAlarm
        isEnabled = !isUnavailable
        accessibilityTraits = isSelected ? [.button, .selected] : [.button]
        if isUnavailable { accessibilityTraits.insert(.notEnabled) }
        accessibilityHint = isSelected ? "" : value.hint
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
        icon.image = UKFont.symbol(value.symbol, style: .title3, filled: isChosen, traits: traitCollection)
    }

    private func refreshColors(animated: Bool) {
        let ink: UIColor = isChosen ? .white : UKInk.primary
        icon.tintColor = ink
        label.textColor = ink
        let finish = UKDesign.effectiveFinish(.standard, traits: traitCollection)
        if isChosen {
            fill.backgroundColor = UIColor(rgb: value.fill)
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

#endif
