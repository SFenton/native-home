#if os(iOS)
import HassCore
import HassDesign
import UIKit

// MARK: - Status value presentation

@MainActor
enum UKServerUIHomeViews {
    typealias D = ServerUICompositionDocument

    static func rgb(_ fill: D.TileFill) -> UInt32? {
        if case .solidRGB(let red, let green, let blue) = fill { return UInt32(red) << 16 | UInt32(green) << 8 | UInt32(blue) }
        return nil
    }

    /// The look and text a status chip draws for `value`: the authored look of its state, after any rule or entity color in it has
    /// answered (`sh.rules@1`). `previous` is what the chip showed, kept for a slot whose value is still loading.
    static func appearance(_ chip: D.StatusChip, value: ServerUIHomeStatus.Value, in environment: some ServerUIReading,
                           keeping previous: ServerUIResolvedAppearance? = nil) -> (ServerUIResolvedAppearance, String) {
        let state = chip.states.first { $0.state == value.state }
        let look = (state?.appearance ?? chip.fallback).resolve(in: environment, keeping: previous)
        return (look, value.state == "hidden" ? value.text : state?.text ?? value.text)
    }

    static func configure(_ view: UKStatusChipView, chip: D.StatusChip, value: ServerUIHomeStatus.Value,
                          appearance: ServerUIResolvedAppearance, text: String, action: (() -> Void)?) {
        let computed = value.color.map { ChipTint.fromWeb($0.rgb, preferredGlyph: rgb(appearance.glyph ?? .standard)) }
        let fill = computed?.fill ?? rgb(appearance.fill)
        let glyph = computed?.glyph ?? appearance.glyph.flatMap { rgb($0) }
        let previous = view.accessibilityLabel
        let previousValue = view.accessibilityValue
        view.configure(title: chip.node.title, summary: text, symbol: appearance.icon.drawn, family: nil, isActive: fill != nil,
                       tint: fill.map { ChipTint(fill: $0, glyph: glyph ?? 0xFFFFFF) },
                       idleGlyph: glyph.map { UIColor.ukRGB($0) }, action: action)
        view.accessibilityValue = value.spoken == value.text ? nil : value.spoken
        announce(view, policy: chip.announcement, previousLabel: previous, previousValue: previousValue)
    }

    static func announce(_ view: UIView, policy: D.Announcement, previousLabel: String?, previousValue: String?) {
        if policy == .valueChange, previousLabel != nil,
           previousLabel != view.accessibilityLabel || previousValue != view.accessibilityValue,
           view.window != nil, UIAccessibility.isVoiceOverRunning {
            UIAccessibility.post(notification: .announcement, argument: [view.accessibilityLabel, view.accessibilityValue].compactMap { $0 }.joined(separator: ", "))
        }
    }
}

// MARK: - Independently composed weather panels

/// Adapts the canonical value-only panels; it neither embeds a Weather controller nor owns a connection.
@MainActor
final class UKServerUIWeatherPanel: UIView, UKGridMeasuring {
    typealias D = ServerUICompositionDocument
    private(set) var definition: D.WeatherPanel
    private var source: UKServerUIWeatherSource?
    private let bag = UKObservationBag()
    private let column = UKColumnView(spacing: HassTokens.Spacing.m)
    private let notice = UILabel.uk(.subheadline, ink: UKWeatherInk.onDarkSecondary)
    private let child: UIView
    private let fitting: UIView & UKGridMeasuring
    private var action: (() -> Void)?
    private struct Snapshot: Equatable {
        let definition: D.WeatherPanel
        let current: WeatherCurrent
        let sun: WeatherSunInput?
        let hourly: WeatherForecastFeed
        let daily: WeatherForecastFeed
        let briefing: WeatherDayBriefing?
        let airQuality: EntityState?
        let selected: WeatherHourlyMode
        let stale: Bool
    }
    private var last: Snapshot?

    init(_ definition: D.WeatherPanel) {
        self.definition = definition
        switch definition.panel {
        case .summary:
            let content = UKWeatherCardContentView(isNarrow: false, onOpen: nil)
            child = content
            fitting = content
        case .hourly:
            let panel = UKWeatherHourlyPanel()
            child = panel; fitting = UKFittingBox(panel)
        case .daily:
            let panel = UKWeatherDailyPanel()
            child = panel; fitting = UKFittingBox(panel)
        case .highlights:
            let panel = UKWeatherHighlightsPanel()
            child = panel; fitting = UKFittingBox(panel)
        case .briefing:
            let panel = UKWeatherBriefingPanel()
            child = panel; fitting = UKFittingBox(panel)
        case .hero:
            let panel = UKWeatherHeroView()
            child = panel; fitting = UKFittingBox(panel)
        }
        super.init(frame: .zero)
        addSubview(column)
        notice.isHidden = true
        column.setViews([fitting, UKLabelBox(notice)])
        ukOnContentSizeChange { [weak self] in
            (self?.child as? UKWeatherHourlyPanel)?.restyle()
            self?.ukRemeasureContainers(includingSelf: true)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func bind(_ definition: D.WeatherPanel, source: UKServerUIWeatherSource, action: (() -> Void)?) {
        if self.source !== source {
            self.source?.setVisible(self, false)
            self.source = source
            last = nil
            source.setVisible(self, window != nil)
        }
        self.definition = definition
        self.action = action
        bag.removeAll()
        bag.observe { [weak self] in self?.reload() }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        source?.setVisible(self, window != nil)
        (child as? UKWeatherCardContentView)?.setSectionOnScreen(window != nil)
    }

    private func reload() {
        guard let source else { return }
        let definition = definition
        source.driver.refresh()
        let current = source.current, sun = source.sun
        var hourly = source.hourly, daily = source.daily
        if hourly.error != nil { hourly.error = definition.labels.error }
        if daily.error != nil { daily.error = definition.labels.error }
        let initial = WeatherHourlyMode(rawValue: definition.initialMode.rawValue) ?? .condition
        let modes = definition.modes.compactMap { WeatherHourlyMode(rawValue: $0.rawValue) }
        let selected = source.selectedMode.flatMap { modes.contains($0) ? $0 : nil } ?? initial
        let briefing = source.briefing, airQuality = source.airQuality
        let snapshot = Snapshot(definition: definition, current: current, sun: sun, hourly: hourly, daily: daily,
                                briefing: briefing, airQuality: airQuality, selected: selected,
                                stale: source.isStale(hourly) || source.isStale(daily))
        // An ordinary publication must not rebuild unchanged hourly cells or highlight controls.
        guard last != snapshot else { return }
        last = snapshot
        if let card = child as? UKWeatherCardContentView {
            card.onOpen = action
            card.openLabel = definition.labels.open
            card.loadingLabel = definition.labels.loading
            card.emptyLabel = definition.labels.empty
            card.compactHours = definition.compactHours
            card.regularHours = definition.regularHours
            card.apply(current: current, night: sun?.isNight ?? false, feed: hourly, today: daily.forecasts.first, briefing: briefing)
        } else if let panel = child as? UKWeatherHourlyPanel {
            panel.configure(title: definition.node.title, modes: modes, compactHours: definition.compactHours,
                            regularHours: definition.regularHours, loading: definition.labels.loading, empty: definition.labels.empty)
            panel.onModeChange = { [weak source] in source?.selectedMode = $0 }
            panel.update(feed: hourly, current: current, mode: selected)
        } else if let panel = child as? UKWeatherDailyPanel {
            panel.titleText = definition.node.title
            panel.loadingLabel = definition.labels.loading
            panel.emptyLabel = definition.labels.empty
            panel.update(feed: daily, current: current, mode: selected)
        } else if let panel = child as? UKWeatherHighlightsPanel {
            panel.titleText = definition.node.title
            panel.order = definition.highlights
            panel.update(hourly: hourly.forecasts, daily: daily.forecasts.first, current: current, sun: sun, aqiState: airQuality)
        } else if let panel = child as? UKWeatherBriefingPanel {
            panel.captionText = definition.node.title
            panel.update(briefing: briefing, current: current, night: sun?.isNight ?? false)
        } else if let hero = child as? UKWeatherHeroView {
            hero.update(current: current, today: daily.forecasts.first)
        }
        let panel = definition.panel
        let feeds = panel == .daily ? [daily] : panel == .hourly ? [hourly] : [hourly, daily]
        let childShowsLoading = panel == .summary || panel == .hourly || panel == .daily
        let childShowsError = panel == .hourly || panel == .daily && daily.forecasts.isEmpty
            || panel == .summary && hourly.forecasts.isEmpty && hourly.error != nil
        if feeds.contains(where: { $0.error != nil }) {
            notice.text = childShowsError ? nil : definition.labels.error
        } else if feeds.contains(where: { source.isStale($0) }) {
            notice.text = definition.labels.stale
        } else if feeds.allSatisfy(\.forecasts.isEmpty), !childShowsLoading {
            notice.text = feeds.contains(where: { $0.isPending || $0.refreshing }) ? definition.labels.loading : definition.labels.empty
        } else { notice.text = nil }
        notice.isHidden = notice.text == nil
        column.views.last?.isHidden = notice.isHidden
        ukRemeasureContainers(includingSelf: true)
    }

    func gridHeight(forWidth width: CGFloat) -> CGFloat { column.gridHeight(forWidth: width) }
    override func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: size.width, height: gridHeight(forWidth: size.width)) }
    override func layoutSubviews() { super.layoutSubviews(); column.frame = bounds }
}
#endif
