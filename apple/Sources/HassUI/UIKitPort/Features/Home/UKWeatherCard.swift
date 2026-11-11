#if os(iOS)
import HassCore
import HassDesign
import UIKit

/// The shared forecast store's wiring for the Home card (`WeatherSummaryCard`): it starts fetching when the card appears, refetches
/// when the weather entity updates, pauses in the background, tells the store when the websocket is ready, and keeps the day's
/// briefing current.
@MainActor
final class UKWeatherForecastDriver {
    let forecasts: WeatherForecastStore
    private let context: UKContext
    private let caller: (any WeatherForecastCalling)?
    private var lastRevision: String??
    private var lastEntityId: String?
    private var lastConnected: Bool?
    private var briefingKey: [Date?] = []
    private var briefingTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var isActive = false

    /// - Parameters:
    ///   - store: A fixture store (the gallery); nil creates the card's own from the connection.
    ///   - caller: Overrides the connection that answers `weather.get_forecasts` (the gallery's fixture service).
    init(context: UKContext, store: WeatherForecastStore?, caller: (any WeatherForecastCalling)?) {
        self.context = context
        self.caller = caller
        let server = context.connection?.server
        forecasts = store ?? WeatherForecastStore(server: server, cache: server == nil ? nil : WeatherForecastDiskCache())
    }

    /// Whether the websocket is ready. Without a connection (the gallery) forecasts come from the injected service.
    private var isConnected: Bool {
        guard let connection = context.connection else { return true }
        if case .connected = connection.status { return true }
        return false
    }

    /// The card appeared.
    func activate() {
        guard !isActive else { return }
        isActive = true
        let revision = WeatherForecastStore.revision(of: context.store.entity(WeatherEntities.weather).state)
        lastRevision = .some(revision)
        lastEntityId = WeatherEntities.weather
        lastConnected = isConnected
        if let target: any WeatherForecastCalling = caller ?? context.connection {
            forecasts.activate(caller: target, revision: revision, connected: isConnected)
        }
        observers = [
            NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.forecasts.setForeground(true) }
            },
            NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.forecasts.setForeground(false) }
            },
        ]
        restartBriefing()
    }

    /// The card left the screen.
    func deactivate() {
        guard isActive else { return }
        isActive = false
        forecasts.deactivate()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        briefingTask?.cancel()
        briefingTask = nil
        briefingKey = []
    }

    /// Reads what the store depends on; call it inside an observation so a change reaches it.
    func refresh() {
        let entityId = WeatherEntities.weather
        let revision = WeatherForecastStore.revision(of: context.store.entity(entityId).state)
        let connected = isConnected
        let key = [forecasts.daily.updatedAt, forecasts.hourly.updatedAt]
        guard isActive else { return }
        // The id is read here, inside the observation, so the house document arriving re-runs this. A first sign-in builds
        // the card with no document; the store holds still until the id is known, and this is what starts its first fetch.
        if lastRevision != .some(revision) || lastEntityId != entityId {
            lastRevision = .some(revision)
            lastEntityId = entityId
            forecasts.update(revision: revision)
        }
        if lastConnected != connected {
            lastConnected = connected
            forecasts.setConnected(connected)
        }
        if key != briefingKey { restartBriefing() }
    }

    private func restartBriefing() {
        briefingKey = [forecasts.daily.updatedAt, forecasts.hourly.updatedAt]
        briefingTask?.cancel()
        let store = context.store
        let forecasts = forecasts
        briefingTask = Task { @MainActor in
            await forecasts.keepBriefingCurrent {
                WeatherBriefingContext(
                    current: WeatherCurrent(entity: store.entity(WeatherEntities.weather).state),
                    aqiState: store.entity(WeatherEntities.airQuality).state?.state,
                    sun: WeatherSunInput(entity: store.entity(WeatherEntities.sun).state)
                )
            }
        }
    }
}

/// The Home weather card (`WeatherSummaryCard` + `WeatherCardContent`, web `WeatherSummary`): condition, temperature, today's range and a
/// 24-hour carousel. Opens the Weather sheet.
///
/// Direction G: a thin module on the wallpaper with the glyph, the condition and today's high and low on the left, the screen's one
/// display numeral on the right (header: option D, `.agents/design/weather-card-header.md`), then the day's first briefing sentence,
/// then the hours. Hand-laid; the hours are the only moving part.
@MainActor
final class UKWeatherCardView: UIView, UKGridMeasuring {
    /// The numeral's largest size at accessibility text sizes.
    static let maxNumeralSize: CGFloat = 96

    private let context: UKContext
    private let driver: UKWeatherForecastDriver
    private let present: (UKHassModalController) -> Void
    private let module = UKModuleView(.thin)
    /// The card sits in half of a split window, so its hourly row holds the compact number of hours per page.
    var isNarrow: Bool {
        didSet {
            guard isNarrow != oldValue else { return }
            carouselKind = ""
            if let lastFeed { updateHourly(feed: lastFeed, current: current) }
        }
    }
    private var lastFeed: WeatherForecastFeed?
    private let bag = UKObservationBag()

    private var current = WeatherCurrent(entity: nil)
    private var night = false
    private let glyph = UKWeatherGlyphView(condition: nil, size: 40)
    private let condition: UKTickerLabel
    private let todayLabel = UILabel.uk(.body, monospacedDigit: true, ink: UIColor(HassTokens.RGB.Surface.secondaryOnModule), lines: 1)
    private let rangeMeasure = UILabel.uk(.body, monospacedDigit: true, ink: .clear, lines: 1)
    private let numeral = UILabel()
    private let cardButton = UIControl()
    private let briefingLabel = UILabel.uk(.body, ink: UKWeatherInk.onDark)
    private let separators = [UKLineView(color: UKInk.separator), UKLineView(color: UKInk.separator)]
    private let message = UILabel.uk(.footnote, ink: UKWeatherInk.onDarkSecondary)
    private var carousel: UKWeatherCarouselView?
    private var carouselKind = ""
    private var hasToday = false
    private var briefingText: String?
    private var hourlyMessage: String?
    private var didAutoOpen = false
    private let startsOpen: Bool

    /// - Parameters:
    ///   - isNarrow: The card sits in half of a split window, so its hourly row holds the compact number of hours per page.
    ///   - present: Presents a view controller from the page.
    init(context: UKContext, store: WeatherForecastStore?, caller: (any WeatherForecastCalling)?, isNarrow: Bool, startsOpen: Bool,
         present: @escaping (UKHassModalController) -> Void) {
        self.context = context
        self.isNarrow = isNarrow
        self.startsOpen = startsOpen
        self.present = present
        driver = UKWeatherForecastDriver(context: context, store: store, caller: caller)
        condition = UKTickerLabel("", textStyle: .headline, wraps: false, probe: "home.weather.condition")
        super.init(frame: .zero)
        addSubview(module)
        condition.textColor = UKWeatherInk.onDark
        numeral.textColor = UKWeatherInk.onDark
        numeral.numberOfLines = 1
        numeral.adjustsFontForContentSizeCategory = false
        todayLabel.accessibilityIdentifier = "home.weather.today"
        briefingLabel.accessibilityIdentifier = "home.weather.briefing"
        message.accessibilityIdentifier = "home.weather.hourlyMessage"
        cardButton.accessibilityIdentifier = "home.weather.card"
        // The card's one button for assistive technology, behind the header so its frame covers the glyph, condition and reading it names.
        cardButton.isAccessibilityElement = true
        cardButton.accessibilityTraits = .button
        cardButton.addAction(UIAction { [weak self] _ in self?.open() }, for: .touchUpInside)
        accessibilityIdentifier = "home.weather"
        numeral.isAccessibilityElement = UKTickerLabel.probeEnabled
        numeral.accessibilityLabel = "numeral"
        numeral.accessibilityIdentifier = "home.weather.numeral"
        glyph.accessibilityElementsHidden = true
        numeral.accessibilityElementsHidden = !UKTickerLabel.probeEnabled
        for view in [cardButton, glyph, condition, todayLabel, numeral, briefingLabel, message, separators[0], separators[1]] as [UIView] { addSubview(view) }
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
        ukOnContentSizeChange { [weak self] in
            guard let self else { return }
            let scaled = UIFontMetrics(forTextStyle: .largeTitle).scaledValue(for: 64, compatibleWith: traitCollection)
            numeral.font = UIFont.systemFont(ofSize: min(scaled, Self.maxNumeralSize), weight: .thin).monospacedDigitVariant()
            condition.wraps = traitCollection.ukIsAccessibilitySize
            ukSetNeedsLayoutUpward()
        }
        bind()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The forecast store the card and its sheet share.
    var forecasts: WeatherForecastStore { driver.forecasts }

    /// Whether Home is on screen; a ticker holds still behind another tab.
    func setSectionOnScreen(_ onScreen: Bool) { condition.isSectionOnScreen = onScreen }

    @objc private func tapped() { open() }

    private func open() { present(makeSheet()) }

    private func makeSheet() -> UKHassModalController {
        UKWeatherSheet.controller(context: context, forecasts: driver.forecasts)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            driver.activate()
            if startsOpen, !didAutoOpen {
                didAutoOpen = true
                DispatchQueue.main.async { [weak self] in self?.open() }
            }
        } else {
            driver.deactivate()
        }
    }

    // MARK: Binding

    private func bind() {
        bag.observe { [weak self] in
            guard let self else { return }
            let entities = context.store
            let current = WeatherCurrent(entity: entities.entity(WeatherEntities.weather).state)
            let night = WeatherSunInput(entity: entities.entity(WeatherEntities.sun).state)?.isNight ?? false
            let feed = driver.forecasts.hourly
            let today = driver.forecasts.daily.forecasts.first
            let briefing = driver.forecasts.briefing
            driver.refresh()
            apply(current: current, night: night, feed: feed, today: today, briefing: briefing)
        }
    }

    private func apply(current: WeatherCurrent, night: Bool, feed: WeatherForecastFeed, today: WeatherForecast?, briefing: WeatherDayBriefing?) {
        let reading = current.degreeText
        let label = current.conditionLabel
        var changedHeight = false
        if numeral.text != reading { numeral.text = reading; changedHeight = true }
        if condition.text != label { condition.text = label; changedHeight = true }
        glyph.configure(condition: current.drawnCondition, night: night)
        cardButton.accessibilityLabel = "Open seven-day weather forecast. \(current.conditionLabel), \(current.temperatureText)"
        self.current = current
        self.night = night
        let hasToday = today != nil
        if let today {
            let text = WeatherFormat.compactHighLow(today)
            if todayLabel.text != text { changedHeight = true }
            todayLabel.text = text
            rangeMeasure.text = text
            todayLabel.accessibilityLabel = "Today \(WeatherConditionInfo(today.condition).label) \(text)"
            todayLabel.isAccessibilityElement = true
        } else {
            todayLabel.text = " "
            rangeMeasure.text = nil
            todayLabel.accessibilityLabel = nil
            todayLabel.isAccessibilityElement = false
        }
        if hasToday != self.hasToday { self.hasToday = hasToday; changedHeight = true }
        let line = UKWeatherCardLogic.briefingLine(briefing)
        if line != briefingText { briefingText = line; briefingLabel.text = line; changedHeight = true }
        lastFeed = feed
        updateHourly(feed: feed, current: current)
        if changedHeight { ukSetNeedsLayoutUpward() }
        setNeedsLayout()
    }

    private func updateHourly(feed: WeatherForecastFeed, current: WeatherCurrent) {
        let regular = isNarrow ? 6 : 9
        if feed.showsPlaceholders {
            hourlyMessage = nil
            let kind = "placeholder"
            if carouselKind != kind {
                install(UKWeatherCarouselView(cells: (0..<24).map { _ in UKWeatherCardHourPlaceholder() }, compactPerPage: 6, regularPerPage: regular,
                                              label: WeatherCopy.text("carousel.forecast"), identifier: "home.weather"), kind: kind)
            }
            carousel?.isAccessibilityElement = true
            carousel?.accessibilityLabel = "Loading 24-hour weather forecast"
        } else if feed.forecasts.isEmpty {
            carousel?.removeFromSuperview()
            carousel = nil
            carouselKind = ""
            let text = feed.error ?? WeatherCopy.text("forecast.hourlyEmpty")
            if hourlyMessage != text { hourlyMessage = text; message.text = text; ukSetNeedsLayoutUpward() }
        } else {
            hourlyMessage = nil
            let cells = feed.forecasts.enumerated().map { UKWeatherCardHourCell(forecast: $1, index: $0, current: current) }
            let kind = "hours"
            if carouselKind == kind, let carousel {
                carousel.setCells(cells)
            } else {
                install(UKWeatherCarouselView(cells: cells, compactPerPage: 6, regularPerPage: regular, label: WeatherCopy.text("carousel.forecast"),
                                              identifier: "home.weather"), kind: kind)
            }
            carousel?.isAccessibilityElement = false
            carousel?.accessibilityLabel = nil
        }
        message.isHidden = hourlyMessage == nil
    }

    private func install(_ new: UKWeatherCarouselView, kind: String) {
        carousel?.removeFromSuperview()
        carousel = new
        carouselKind = kind
        addSubview(new)
        ukSetNeedsLayoutUpward()
    }

    // MARK: Layout

    private struct Layout {
        var stacked = false
        var glyph = CGRect.zero
        var condition = CGRect.zero
        var today = CGRect.zero
        var numeral = CGRect.zero
        var header = CGRect.zero
        var separatorY: [CGFloat] = []
        var briefing = CGRect.zero
        var hourly = CGRect.zero
        var height: CGFloat = 0
    }

    private func layout(width: CGFloat) -> Layout {
        let pad = HassTokens.Spacing.l
        let inner = max(1, width - 2 * pad)
        var out = Layout()
        let accessibilitySize = traitCollection.ukIsAccessibilitySize
        let glyphSize = glyph.sizeThatFits(.zero)
        let numeralNatural = numeral.sizeThatFits(CGSize(width: 10_000, height: 1000))
        let readingWidth = ceil(numeralNatural.width)
        let readingHeight = max(HassTokens.minTarget, ceil(numeralNatural.height))
        let rangeWidth = rangeMeasure.text == nil ? 0 : ceil(rangeMeasure.sizeThatFits(CGSize(width: 10_000, height: 1000)).width)
        // Measured from the header's width, the reading's width and the range's natural width, none of which depends on the layout chosen.
        let overflows = rangeWidth > 0 && rangeWidth > inner - readingWidth - HassTokens.Spacing.m + 0.5
        out.stacked = accessibilitySize || overflows
        let todayHeight = ceil(todayLabel.sizeThatFits(CGSize(width: inner, height: .greatestFiniteMagnitude)).height)
        var y = pad
        let top = y
        if out.stacked {
            let rowHeight = max(glyphSize.height, readingHeight)
            out.glyph = CGRect(x: pad, y: y + (rowHeight - glyphSize.height) / 2, width: glyphSize.width, height: glyphSize.height)
            out.numeral = CGRect(x: pad + inner - readingWidth, y: y + (rowHeight - readingHeight) / 2, width: readingWidth, height: readingHeight)
            y += rowHeight + HassTokens.Spacing.s
            let conditionHeight = condition.sizeThatFits(CGSize(width: inner, height: 0)).height
            out.condition = CGRect(x: pad, y: y, width: inner, height: conditionHeight)
            y += conditionHeight + HassTokens.Spacing.s
            out.today = CGRect(x: pad, y: y, width: inner, height: todayHeight)
            y += todayHeight
        } else {
            let column = max(1, inner - readingWidth - HassTokens.Spacing.m)
            let conditionHeight = condition.sizeThatFits(CGSize(width: column, height: 0)).height
            let leftHeight = glyphSize.height + HassTokens.Spacing.xs + conditionHeight + HassTokens.Spacing.xs + todayHeight
            let rowHeight = max(leftHeight, readingHeight)
            let leftTop = y + (rowHeight - leftHeight) / 2
            out.glyph = CGRect(x: pad, y: leftTop, width: glyphSize.width, height: glyphSize.height)
            out.condition = CGRect(x: pad, y: leftTop + glyphSize.height + HassTokens.Spacing.xs, width: column, height: conditionHeight)
            out.today = CGRect(x: pad, y: out.condition.maxY + HassTokens.Spacing.xs, width: column, height: todayHeight)
            out.numeral = CGRect(x: pad + inner - readingWidth, y: y + (rowHeight - readingHeight) / 2, width: readingWidth, height: readingHeight)
            y += rowHeight
        }
        out.header = CGRect(x: pad, y: top, width: inner, height: y - top)
        y += HassTokens.Spacing.m
        out.separatorY.append(y)
        y += 1 + HassTokens.Spacing.m
        if briefingText != nil {
            let height = ceil(briefingLabel.sizeThatFits(CGSize(width: inner, height: .greatestFiniteMagnitude)).height)
            out.briefing = CGRect(x: pad, y: y, width: inner, height: height)
            y += height + HassTokens.Spacing.m
            out.separatorY.append(y)
            y += 1 + HassTokens.Spacing.m
        }
        var hourlyHeight: CGFloat = 0
        if let carousel, hourlyMessage == nil {
            hourlyHeight = carousel.gridHeight(forWidth: inner)
        } else if hourlyMessage != nil {
            hourlyHeight = max(72, ceil(message.sizeThatFits(CGSize(width: inner, height: .greatestFiniteMagnitude)).height))
        }
        out.hourly = CGRect(x: pad, y: y, width: inner, height: hourlyHeight)
        y += hourlyHeight + pad
        out.height = y
        return out
    }

    func gridHeight(forWidth width: CGFloat) -> CGFloat { layout(width: width).height }
    override func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: size.width, height: gridHeight(forWidth: size.width)) }

    override func layoutSubviews() {
        super.layoutSubviews()
        let l = layout(width: bounds.width)
        let mirror = effectiveUserInterfaceLayoutDirection == .rightToLeft
        func place(_ view: UIView, _ rect: CGRect) {
            view.frame = mirror ? CGRect(x: bounds.width - rect.maxX, y: rect.minY, width: rect.width, height: rect.height) : rect
        }
        place(glyph, l.glyph)
        place(condition, l.condition)
        place(todayLabel, l.today)
        place(numeral, l.numeral)
        place(cardButton, l.header)
        module.frame = bounds
        for (index, line) in separators.enumerated() {
            line.isHidden = index >= l.separatorY.count
            if index < l.separatorY.count { line.frame = CGRect(x: HassTokens.Spacing.l, y: l.separatorY[index], width: bounds.width - 2 * HassTokens.Spacing.l, height: 1) }
        }
        briefingLabel.isHidden = briefingText == nil
        place(briefingLabel, l.briefing)
        place(message, l.hourly)
        carousel?.frame = l.hourly
        var elements: [UIView] = [cardButton]
        // The ticker's probe (`FENTON_TICKER_PROBE=1`) is an element of its own.
        if UKTickerLabel.probeEnabled { elements.append(condition) }
        if todayLabel.isAccessibilityElement { elements.append(todayLabel) }
        if briefingText != nil { elements.append(briefingLabel) }
        if hourlyMessage != nil { elements.append(message) } else if let carousel { elements.append(carousel) }
        if numeral.isAccessibilityElement { elements.append(numeral) }
        accessibilityElements = elements
    }
}

private extension UIFont {
    /// This font with monospaced digits (`.monospacedDigit()`).
    func monospacedDigitVariant() -> UIFont {
        let descriptor = fontDescriptor.addingAttributes([
            .featureSettings: [[
                UIFontDescriptor.FeatureKey.type: kNumberSpacingType,
                UIFontDescriptor.FeatureKey.selector: kMonospacedNumbersSelector,
            ]],
        ])
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}

/// Logic the card shares with its SwiftUI twin.
enum UKWeatherCardLogic {
    /// The card's one-line outlook (``WeatherCardContent/briefingLine(_:)``).
    static func briefingLine(_ briefing: WeatherDayBriefing?) -> String? { WeatherCardContent.briefingLine(briefing) }
}
#endif
