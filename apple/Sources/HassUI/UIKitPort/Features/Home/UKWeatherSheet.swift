#if os(iOS)
import HassCore
import HassDesign
import UIKit

/// The Weather modal (`WeatherSheet`, web `WeatherForecastSheet`): hero, the Today briefing, hourly conditions in three modes, the
/// next seven days and the highlight tiles. Dark appearance throughout: the condition gradient is always dark. It reads the same
/// ``WeatherForecastStore`` as the Home card, so opening it never reloads.
@MainActor
enum UKWeatherSheet {
    /// The sheet as a modal: full height, dark, with Close.
    static func controller(context: UKContext, forecasts: WeatherForecastStore) -> UKHassModalController {
        var options = UKHassModalOptions(title: "Weather")
        options.appearance = .dark
        options.height = .full
        options.width = .page
        return UKHassModalController(root: UKWeatherSheetViewController(context: context, forecasts: forecasts), options: options)
    }
}

@MainActor
final class UKWeatherSheetViewController: UKPageViewController {
    private let forecasts: WeatherForecastStore
    private let sky = UKWeatherBackdropView(scene: .neutral)
    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private let heroTemperature = UILabel()
    private let heroCondition = UILabel.uk(.title3, weight: .bold, ink: UKWeatherInk.onDark, alignment: .center)
    private let heroHighLow = UILabel.uk(.subheadline, weight: .semibold, ink: UKWeatherInk.onDarkSecondary, alignment: .center)
    private let briefing = UKWeatherBriefingPanel()
    private let hourly = UKWeatherHourlyPanel()
    private let daily = UKWeatherDailyPanel()
    private let highlights = UKWeatherHighlightsPanel()
    private var mode: WeatherHourlyMode = .condition

    init(context: UKContext, forecasts: WeatherForecastStore) {
        self.forecasts = forecasts
        super.init(context: context.with { $0.surface = .sheet }, title: "Weather")
        overrideUserInterfaceStyle = .dark
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.accessibilityIdentifier = "weather.sheet"
        // The gradient runs edge to edge under the rail; the scroller is the page's content, inside the side safe areas.
        setSheetBackdrop(sky, ground: sky.baseColor)
        scroll.showsVerticalScrollIndicator = false
        install(scrollView: scroll)
        // The forecast stretches and springs back even when it fits (the page's scroll-fit rule would stop it).
        scroll.alwaysBounceVertical = true
        stack.axis = .vertical
        stack.spacing = HassTokens.Spacing.l
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -HassTokens.Spacing.xl),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: HassTokens.Spacing.l),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -HassTokens.Spacing.l),
        ])
        stack.addArrangedSubview(makeHero())
        for panel in [briefing, hourly, daily, highlights] as [UIView] { stack.addArrangedSubview(panel) }
        hourly.onModeChange = { [weak self] mode in
            guard let self else { return }
            self.mode = mode
            reload()
        }
        bag.observe { [weak self] in self?.reload() }
        view.ukOnContentSizeChange { [weak self] in
            guard let self else { return }
            let scaled = UIFontMetrics(forTextStyle: .largeTitle).scaledValue(for: 76, compatibleWith: traitCollection)
            heroTemperature.font = UIFont.systemFont(ofSize: scaled, weight: .thin).ukMonospacedDigit()
            hourly.restyle()
        }
    }

    private func makeHero() -> UIView {
        heroTemperature.textColor = UKWeatherInk.onDark
        heroTemperature.textAlignment = .center
        heroTemperature.numberOfLines = 0
        heroTemperature.accessibilityIdentifier = "weather.hero.temperature"
        heroCondition.accessibilityIdentifier = "weather.hero.condition"
        heroHighLow.accessibilityIdentifier = "weather.hero.highLow"
        let hero = UIStackView(arrangedSubviews: [heroTemperature, heroCondition, heroHighLow])
        hero.axis = .vertical
        hero.spacing = HassTokens.Spacing.xs
        hero.isLayoutMarginsRelativeArrangement = true
        hero.directionalLayoutMargins = NSDirectionalEdgeInsets(top: HassTokens.Spacing.m, leading: 0, bottom: HassTokens.Spacing.m, trailing: 0)
        return hero
    }

    /// Reads the entities and the store and writes every section.
    private func reload() {
        let entities = context.store
        let current = WeatherCurrent(entity: entities.entity(WeatherEntities.weather).state)
        let sun = WeatherSunInput(entity: entities.entity(WeatherEntities.sun).state)
        let night = sun?.isNight ?? false
        let aqi = entities.entity(WeatherEntities.airQuality).state
        let hourlyFeed = forecasts.hourly
        let dailyFeed = forecasts.daily
        let scene = WeatherScene(condition: current.drawnCondition, isNight: night)
        sky.configure(scene: scene)
        view.backgroundColor = sky.baseColor
        heroTemperature.text = current.degreeText
        heroCondition.text = current.conditionLabel
        if let today = dailyFeed.forecasts.first {
            let text = WeatherFormat.modalHighLow(today)
            heroHighLow.text = text
            heroHighLow.isHidden = text.isEmpty
        } else {
            heroHighLow.isHidden = true
        }
        briefing.update(briefing: forecasts.briefing, current: current, night: night)
        hourly.update(feed: hourlyFeed, current: current, mode: mode)
        daily.update(feed: dailyFeed, current: current, mode: mode)
        highlights.update(hourly: hourlyFeed.forecasts, daily: dailyFeed.forecasts.first, current: current, sun: sun, aqiState: aqi)
    }
}

extension UIFont {
    /// This font with monospaced digits (`.monospacedDigit()`).
    func ukMonospacedDigit() -> UIFont {
        let descriptor = fontDescriptor.addingAttributes([
            .featureSettings: [[
                UIFontDescriptor.FeatureKey.type: kNumberSpacingType,
                UIFontDescriptor.FeatureKey.selector: kMonospacedNumbersSelector,
            ]],
        ])
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}

// MARK: - Today

/// The "Today" panel: a headline with an icon, then a few narrative sentences (`WeatherBriefingPanel`).
@MainActor
final class UKWeatherBriefingPanel: UIView {
    private let surface = UKWeatherSurfaceView(spacing: HassTokens.Spacing.m)
    private let header = UIStackView()
    private let iconHost = UIView()
    private let caption = UILabel.uk(.footnote, weight: .semibold, ink: UKWeatherInk.onDarkSecondary)
    private let headline = UILabel.uk(.title3, weight: .bold, ink: UKWeatherInk.onDark)
    private let sentences = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        surface.translatesAutoresizingMaskIntoConstraints = false
        addSubview(surface)
        NSLayoutConstraint.activate([
            surface.topAnchor.constraint(equalTo: topAnchor), surface.bottomAnchor.constraint(equalTo: bottomAnchor),
            surface.leadingAnchor.constraint(equalTo: leadingAnchor), surface.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        caption.text = WeatherCopy.text("headline.label")
        headline.accessibilityTraits = .header
        headline.accessibilityIdentifier = "weather.today.headline"
        let text = UIStackView(arrangedSubviews: [caption, headline])
        text.axis = .vertical
        text.spacing = 2
        text.setContentHuggingPriority(.defaultLow, for: .horizontal)
        header.axis = .horizontal
        header.alignment = .center
        header.spacing = HassTokens.Spacing.m
        header.addArrangedSubview(iconHost)
        header.addArrangedSubview(text)
        sentences.axis = .vertical
        sentences.spacing = HassTokens.Spacing.s
        sentences.accessibilityIdentifier = "weather.today.narrative"
        surface.stack.addArrangedSubview(header)
        surface.stack.addArrangedSubview(sentences)
        accessibilityIdentifier = "weather.today"
        accessibilityElements = [caption, headline, sentences]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func update(briefing: WeatherDayBriefing?, current: WeatherCurrent, night: Bool) {
        headline.text = briefing.map(WeatherBriefingRenderer.headline) ?? WeatherCopy.text("headline.weather", ["condition": current.conditionLabel])
        iconHost.subviews.forEach { $0.removeFromSuperview() }
        let icon: UIView
        if let hazard = briefing?.hazard {
            let image = UIImageView()
            image.tintColor = severityColor(briefing?.severity ?? .calm)
            image.isAccessibilityElement = false
            image.image = UKFont.symbol(WeatherSymbols.hazard(hazard), style: .title1, traits: traitCollection)
            icon = image
        } else {
            icon = UKWeatherGlyphView(condition: briefing?.condition ?? current.drawnCondition, night: night, size: 32)
        }
        icon.translatesAutoresizingMaskIntoConstraints = false
        iconHost.addSubview(icon)
        NSLayoutConstraint.activate([
            icon.topAnchor.constraint(equalTo: iconHost.topAnchor), icon.bottomAnchor.constraint(equalTo: iconHost.bottomAnchor),
            icon.leadingAnchor.constraint(equalTo: iconHost.leadingAnchor), icon.trailingAnchor.constraint(equalTo: iconHost.trailingAnchor),
        ])
        iconHost.setContentHuggingPriority(.required, for: .horizontal)
        icon.setContentHuggingPriority(.required, for: .horizontal)
        icon.setContentCompressionResistancePriority(.required, for: .horizontal)
        sentences.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let texts = briefing.map { $0.sentences.map(WeatherBriefingRenderer.render) } ?? [WeatherCopy.text("briefing.unavailable")]
        for text in texts {
            let bullet = UILabel.uk(.subheadline, ink: UKWeatherInk.onDark, lines: 1)
            bullet.text = "•"
            bullet.setContentHuggingPriority(.required, for: .horizontal)
            bullet.isAccessibilityElement = false
            let label = UILabel.uk(.subheadline, ink: UKWeatherInk.onDark)
            label.text = text
            label.isAccessibilityElement = false
            let row = UIStackView(arrangedSubviews: [bullet, label])
            row.axis = .horizontal
            row.alignment = .firstBaseline
            row.spacing = HassTokens.Spacing.s
            row.isAccessibilityElement = true
            row.accessibilityLabel = text
            row.accessibilityTraits = .staticText // read-only text, so the audit does not hold it to a control's hit area
            sentences.addArrangedSubview(row)
        }
    }

    private func severityColor(_ severity: WeatherBriefingSeverity) -> UIColor {
        switch severity {
        case .alert: UIColor(red: 1.0, green: 0.60, blue: 0.24, alpha: 1)
        case .caution: UIColor(red: 1.0, green: 0.82, blue: 0.30, alpha: 1)
        case .notable, .calm: UKWeatherInk.onDark
        }
    }
}

// MARK: - Conditions

/// The "Conditions" panel: a 24-hour carousel in three modes (conditions, precipitation, wind), switched with a segmented control of
/// icons (`WeatherHourlyPanel`).
@MainActor
final class UKWeatherHourlyPanel: UIView {
    var onModeChange: (WeatherHourlyMode) -> Void = { _ in }

    private let surface = UKWeatherSurfaceView(spacing: HassTokens.Spacing.m)
    private let title = UILabel.uk(.headline, weight: .semibold, ink: UKWeatherInk.onDark)
    private let picker: UISegmentedControl
    private let headerStack = UIStackView()
    private let subhead = UILabel.uk(.footnote, ink: UKWeatherInk.onDarkSecondary)
    private let content = UIStackView()
    private var carousel: UKWeatherCarouselView?
    private var carouselHost: UKAutoSizingHost?
    private var carouselKind = ""
    private var lastKey = 0
    private var mode: WeatherHourlyMode = .condition
    /// The segmented control's width beside the title at standard sizes: three icon segments.
    static let pickerWidth: CGFloat = 168

    override init(frame: CGRect) {
        let images = WeatherHourlyMode.allCases.map { mode -> UIImage in
            let image = UIImage(systemName: WeatherSymbols.mode(mode)) ?? UIImage()
            image.accessibilityLabel = mode.label
            return image
        }
        picker = UISegmentedControl(items: images)
        super.init(frame: frame)
        surface.translatesAutoresizingMaskIntoConstraints = false
        addSubview(surface)
        NSLayoutConstraint.activate([
            surface.topAnchor.constraint(equalTo: topAnchor), surface.bottomAnchor.constraint(equalTo: bottomAnchor),
            surface.leadingAnchor.constraint(equalTo: leadingAnchor), surface.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        title.text = "Conditions"
        title.accessibilityTraits = .header
        picker.selectedSegmentIndex = 0
        picker.accessibilityIdentifier = "weather.mode"
        picker.heightAnchor.constraint(greaterThanOrEqualToConstant: HassTokens.minTarget).isActive = true
        picker.addAction(UIAction { [weak self] _ in
            guard let self, let mode = WeatherHourlyMode.allCases[safe: picker.selectedSegmentIndex] else { return }
            self.mode = mode
            onModeChange(mode)
        }, for: .valueChanged)
        subhead.accessibilityIdentifier = "weather.hourly.subhead"
        headerStack.spacing = HassTokens.Spacing.s
        content.axis = .vertical
        content.spacing = HassTokens.Spacing.m
        surface.stack.addArrangedSubview(headerStack)
        surface.stack.addArrangedSubview(subhead)
        surface.stack.addArrangedSubview(content)
        accessibilityIdentifier = "weather.hourly"
        accessibilityLabel = WeatherCopy.text("carousel.section")
        restyle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Lays the header out for the current text size: title and picker side by side, or stacked at accessibility sizes.
    func restyle() {
        let stacked = traitCollection.ukIsAccessibilitySize
        headerStack.arrangedSubviews.forEach { headerStack.removeArrangedSubview($0); $0.removeFromSuperview() }
        headerStack.axis = stacked ? .vertical : .horizontal
        headerStack.alignment = stacked ? .fill : .center
        picker.constraints.filter { $0.firstAttribute == .width }.forEach { $0.isActive = false }
        if !stacked { picker.widthAnchor.constraint(equalToConstant: Self.pickerWidth).isActive = true }
        title.setContentHuggingPriority(.defaultLow, for: .horizontal)
        headerStack.addArrangedSubview(title)
        headerStack.addArrangedSubview(picker)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // The system segmented control names each segment through its image; the hint rides on the segment view.
        let segments = picker.subviews.sorted { $0.frame.minX < $1.frame.minX }
        if segments.count == WeatherHourlyMode.allCases.count {
            for (segment, mode) in zip(segments, WeatherHourlyMode.allCases) {
                segment.accessibilityLabel = mode.label
                segment.accessibilityHint = mode.hint
            }
        }
    }

    func update(feed: WeatherForecastFeed, current: WeatherCurrent, mode: WeatherHourlyMode) {
        let previousMode = self.mode
        self.mode = mode
        picker.selectedSegmentIndex = WeatherHourlyMode.allCases.firstIndex(of: mode) ?? 0
        subhead.text = switch mode {
        case .condition: "Temperature (\(WeatherFormat.unitWithoutDegree(current.temperatureUnit, fallback: "F")))"
        case .precipitation: "Precipitation chance (%)"
        case .wind: "Speed (\(current.windSpeedUnit ?? WeatherUnits.defaultWindSpeedUnit)) · Gusts"
        }
        let label = WeatherCopy.text("carousel.conditions")
        if feed.showsPlaceholders {
            guard carouselKind != "placeholder" else { return }
            install(UKWeatherCarouselView(cells: (0..<24).map { _ in UKWeatherModalHourPlaceholder() }, compactPerPage: 5, regularPerPage: 7, label: label,
                                          identifier: "weather.hour"), kind: "placeholder")
            carousel?.isAccessibilityElement = true
            carousel?.accessibilityLabel = "Loading 24-hour conditions"
        } else if feed.forecasts.isEmpty {
            content.arrangedSubviews.forEach { $0.removeFromSuperview() }
            carousel = nil
            carouselHost = nil
            carouselKind = "message"
            lastKey = 0
            content.addArrangedSubview(messageLabel(feed.error ?? WeatherCopy.text("forecast.hourlyEmpty")))
        } else {
            var hasher = Hasher()
            hasher.combine(feed.forecasts)
            hasher.combine(mode)
            hasher.combine(current.temperatureUnit)
            hasher.combine(current.precipitationUnit)
            hasher.combine(current.windSpeedUnit)
            hasher.combine(feed.error)
            let key = hasher.finalize()
            guard key != lastKey || carouselKind != "hours" else { return }
            lastKey = key
            if carouselKind != "hours" || carousel == nil {
                install(UKWeatherCarouselView(cells: [], compactPerPage: 5, regularPerPage: 7, label: label, identifier: "weather.hour"), kind: "hours")
            }
            carousel?.isAccessibilityElement = false
            carousel?.accessibilityLabel = nil
            let cells = feed.forecasts.enumerated().map { UKWeatherModalHourCell(forecast: $1, index: $0, mode: mode, current: current) }
            let replace = { [self] in
                carousel?.setCells(cells)
                carouselHost?.contentChanged()
            }
            if previousMode != mode, let host = carouselHost, window != nil, !UIAccessibility.isReduceMotionEnabled {
                UIView.transition(with: host, duration: MotionTokens.quickDuration, options: [.transitionCrossDissolve, .allowUserInteraction], animations: replace)
            } else {
                replace()
            }
            while content.arrangedSubviews.count > 1 { content.arrangedSubviews.last?.removeFromSuperview() }
            if let error = feed.error { content.addArrangedSubview(messageLabel(error)) }
        }
    }

    private func install(_ new: UKWeatherCarouselView, kind: String) {
        content.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let host = UKAutoSizingHost(new)
        carousel = new
        carouselHost = host
        carouselKind = kind
        lastKey = 0
        content.addArrangedSubview(host)
    }

    private func messageLabel(_ text: String) -> UILabel {
        let label = UILabel.uk(.subheadline, ink: UKWeatherInk.onDarkSecondary)
        label.text = text
        label.accessibilityIdentifier = "weather.hourly.message"
        label.heightAnchor.constraint(greaterThanOrEqualToConstant: HassTokens.minTarget).isActive = true
        return label
    }
}


// MARK: - Seven days

/// The "Next Seven Days" panel: one row per day, in the mode picked in the Conditions panel (`WeatherDailyPanel`).
@MainActor
final class UKWeatherDailyPanel: UIView {
    private let surface = UKWeatherSurfaceView(spacing: HassTokens.Spacing.m)
    private let title = UILabel.uk(.headline, weight: .semibold, ink: UKWeatherInk.onDark)
    private let list = UIStackView()
    private var last: (WeatherForecastFeed, WeatherCurrent, WeatherHourlyMode)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        surface.translatesAutoresizingMaskIntoConstraints = false
        addSubview(surface)
        NSLayoutConstraint.activate([
            surface.topAnchor.constraint(equalTo: topAnchor), surface.bottomAnchor.constraint(equalTo: bottomAnchor),
            surface.leadingAnchor.constraint(equalTo: leadingAnchor), surface.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        title.text = "Next Seven Days"
        title.accessibilityTraits = .header
        list.axis = .vertical
        surface.stack.addArrangedSubview(title)
        surface.stack.addArrangedSubview(list)
        accessibilityIdentifier = "weather.daily"
        accessibilityLabel = "Seven-day weather forecast"
        accessibilityElements = [title, list]
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: UKWeatherDailyPanel, _) in
            if let last = view.last { view.update(feed: last.0, current: last.1, mode: last.2) }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func update(feed: WeatherForecastFeed, current: WeatherCurrent, mode: WeatherHourlyMode) {
        last = (feed, current, mode)
        list.arrangedSubviews.forEach { $0.removeFromSuperview() }
        list.isAccessibilityElement = false
        list.accessibilityLabel = nil
        if feed.showsPlaceholders {
            list.spacing = HassTokens.Spacing.s
            for _ in 0..<7 {
                let bar = UIView()
                bar.backgroundColor = UKWeatherInk.onDark.withAlphaComponent(0.1)
                bar.layer.cornerRadius = HassTokens.Radius.chip
                bar.layer.cornerCurve = .continuous
                bar.heightAnchor.constraint(equalToConstant: 44).isActive = true
                list.addArrangedSubview(bar)
            }
            list.isAccessibilityElement = true
            list.accessibilityLabel = "Loading seven-day weather forecast"
        } else if feed.forecasts.isEmpty {
            list.spacing = 0
            let label = UILabel.uk(.subheadline, ink: UKWeatherInk.onDarkSecondary)
            label.text = feed.error ?? WeatherCopy.text("forecast.dailyEmpty")
            label.accessibilityIdentifier = "weather.daily.message"
            label.heightAnchor.constraint(greaterThanOrEqualToConstant: HassTokens.minTarget).isActive = true
            list.addArrangedSubview(label)
        } else {
            list.spacing = 0
            for (index, forecast) in feed.forecasts.enumerated() {
                if index > 0 { list.addArrangedSubview(UKLineView(color: UKWeatherInk.onDark.withAlphaComponent(0.14))) }
                list.addArrangedSubview(UKWeatherDayRow(forecast: forecast, index: index, all: feed.forecasts, current: current, mode: mode, traits: traitCollection))
            }
        }
    }
}

/// One day of the seven-day list, in the active mode (`WeatherDayRow`).
@MainActor
final class UKWeatherDayRow: UIView {
    private let accessibilityText: String

    init(forecast: WeatherForecast, index: Int, all: [WeatherForecast], current: WeatherCurrent, mode: WeatherHourlyMode, traits: UITraitCollection) {
        let day = WeatherFormat.dayLabel(forecast.datetime, index: index)
        let amount = WeatherFormat.measure(forecast.precipitation, unit: current.precipitationUnit, digits: 2) ?? WeatherCopy.text("unavailable")
        let chance = WeatherFormat.percent(forecast.precipitationProbability) ?? WeatherCopy.text("unavailable")
        let windRange = WeatherFormat.windRange(speed: forecast.windSpeed, gust: forecast.windGustSpeed, unit: current.windSpeedUnit)
        accessibilityText = switch mode {
        case .condition: "\(day) \(WeatherConditionInfo(forecast.condition).label) \(WeatherFormat.compactHighLow(forecast))"
        case .precipitation: "\(day) precipitation \(amount) \(chance)"
        case .wind: "\(day) wind \(windRange)"
        }
        super.init(frame: .zero)
        let scale = { (value: CGFloat) in UIFontMetrics(forTextStyle: .subheadline).scaledValue(for: value, compatibleWith: traits) }
        let dayLabel = UILabel.uk(.subheadline, weight: .bold, ink: UKWeatherInk.onDark, lines: 1)
        dayLabel.text = day
        func value(_ text: String, bold: Bool, minWidth: CGFloat) -> UILabel {
            let label = UILabel.uk(.subheadline, weight: bold ? .bold : .regular, monospacedDigit: true, ink: UKWeatherInk.onDark, lines: 1, alignment: .right)
            label.text = text
            label.widthAnchor.constraint(greaterThanOrEqualToConstant: minWidth).isActive = true
            label.setContentHuggingPriority(.required, for: .horizontal)
            return label
        }
        func iconBox(_ view: UIView) -> UIView {
            let box = UIView()
            view.translatesAutoresizingMaskIntoConstraints = false
            box.addSubview(view)
            NSLayoutConstraint.activate([
                box.widthAnchor.constraint(equalToConstant: 32),
                view.centerXAnchor.constraint(equalTo: box.centerXAnchor),
                view.topAnchor.constraint(equalTo: box.topAnchor), view.bottomAnchor.constraint(equalTo: box.bottomAnchor),
            ])
            return box
        }
        let detail = UIStackView()
        detail.axis = .horizontal
        detail.alignment = .center
        detail.spacing = HassTokens.Spacing.s
        let valueWidth = scale(40)
        switch mode {
        case .condition:
            let rail = WeatherRails.week(forecast: forecast, all: all, currentTemperature: current.temperature, index: index) ?? WeatherRailRange()
            let shown = WeatherRailRange(markerPercent: index == 0 ? rail.markerPercent : nil, rangeSizePercent: rail.rangeSizePercent,
                                         rangeStartPercent: rail.rangeStartPercent)
            let railView = UKWeatherRailView(tone: .temperature, range: shown)
            railView.setContentHuggingPriority(.defaultLow, for: .horizontal)
            railView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            detail.addArrangedSubview(iconBox(UKWeatherGlyphView(condition: forecast.condition, size: 26)))
            detail.addArrangedSubview(value(WeatherFormat.degree(forecast.templow), bold: true, minWidth: valueWidth))
            detail.addArrangedSubview(railView)
            detail.addArrangedSubview(value(WeatherFormat.degree(forecast.temperature), bold: true, minWidth: valueWidth))
        case .precipitation:
            let probability = forecast.precipitationProbability
            let drop = UIImageView(image: UIImage(systemName: WeatherSymbols.drop, withConfiguration: UIImage.SymbolConfiguration.preferringMulticolor()))
            drop.tintColor = UKWeatherInk.drop
            let railView = UKWeatherRailView(tone: .precipitation, range: WeatherRailRange(
                markerPercent: (probability ?? 0) > 0 ? probability : nil, rangeSizePercent: probability, rangeStartPercent: 0))
            railView.setContentHuggingPriority(.defaultLow, for: .horizontal)
            railView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            detail.addArrangedSubview(iconBox(drop))
            detail.addArrangedSubview(railView)
            detail.addArrangedSubview(value(amount, bold: false, minWidth: valueWidth + 14))
            detail.addArrangedSubview(value(chance, bold: true, minWidth: valueWidth))
        case .wind:
            let bearing = WeatherPresentation.windBearing(forecast.windBearing)
            let arrow = UIImageView(image: UIImage(systemName: bearing == nil ? WeatherSymbols.windFlag : WeatherSymbols.windArrow,
                                                   withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)))
            arrow.tintColor = UKWeatherInk.onDark
            arrow.transform = CGAffineTransform(rotationAngle: CGFloat((bearing?.destinationDegrees ?? 0) * .pi / 180))
            let range = UILabel.uk(.subheadline, weight: .bold, monospacedDigit: true, ink: UKWeatherInk.onDark, lines: 1)
            range.text = windRange
            detail.addArrangedSubview(iconBox(arrow))
            detail.addArrangedSubview(range)
            detail.addArrangedSubview(UIView())
        }
        let content: UIStackView
        if traits.ukIsAccessibilitySize {
            content = UIStackView(arrangedSubviews: [dayLabel, detail])
            content.axis = .vertical
            content.alignment = .fill
            content.spacing = HassTokens.Spacing.xs
        } else {
            dayLabel.widthAnchor.constraint(equalToConstant: scale(48)).isActive = true
            content = UIStackView(arrangedSubviews: [dayLabel, detail])
            content.axis = .horizontal
            content.alignment = .center
            content.spacing = HassTokens.Spacing.s
        }
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: topAnchor, constant: HassTokens.Spacing.xs),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -HassTokens.Spacing.xs),
            content.leadingAnchor.constraint(equalTo: leadingAnchor), content.trailingAnchor.constraint(equalTo: trailingAnchor),
            heightAnchor.constraint(greaterThanOrEqualToConstant: HassTokens.minTarget + 2 * HassTokens.Spacing.xs),
        ])
        isAccessibilityElement = true
        accessibilityLabel = accessibilityText
        accessibilityIdentifier = "weather.day.\(index)"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

// MARK: - Highlights

/// The "Highlights" grid: air quality, precipitation and accumulation, humidity and cloud cover, then feels like, UV, wind, sun,
/// visibility and pressure (`WeatherHighlightsPanel`). Wide tiles take two tracks, and at larger text sizes the grid drops to
/// fewer columns instead of clipping.
@MainActor
final class UKWeatherHighlightsPanel: UIView {
    private let title = UILabel.uk(.headline, weight: .semibold, ink: UKWeatherInk.onDark)
    private let grid = UKDynamicGridView(configuration: UKGridConfiguration(minCellWidth: DynamicGridMetrics.tileMinWidth, maxColumns: 4))
    private var host: UKAutoSizingHost!
    private var last: (hourly: [WeatherForecast], daily: WeatherForecast?, current: WeatherCurrent, sun: WeatherSunInput?, aqiState: EntityState?)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        title.text = "Highlights"
        title.accessibilityTraits = .header
        host = UKAutoSizingHost(grid)
        let stack = UIStackView(arrangedSubviews: [title, host])
        stack.axis = .vertical
        stack.spacing = HassTokens.Spacing.m
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        accessibilityIdentifier = "weather.highlights"
        accessibilityLabel = "Weather highlights"
        accessibilityElements = [title, grid]
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: UKWeatherHighlightsPanel, _) in
            view.grid.configuration.minCellWidth = UIFontMetrics(forTextStyle: .footnote).scaledValue(for: 150, compatibleWith: view.traitCollection)
            if let last = view.last { view.update(hourly: last.hourly, daily: last.daily, current: last.current, sun: last.sun, aqiState: last.aqiState) }
            view.host.contentChanged()
        }
        grid.configuration.minCellWidth = UIFontMetrics(forTextStyle: .footnote).scaledValue(for: 150, compatibleWith: traitCollection)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func update(hourly: [WeatherForecast], daily: WeatherForecast?, current: WeatherCurrent, sun: WeatherSunInput?, aqiState: EntityState?) {
        last = (hourly, daily, current, sun, aqiState)
        var items: [UKGridItem] = []
        if let aqiState { items.append(UKGridItem(UKWeatherTiles.aqi(WeatherHighlights.airQuality(state: aqiState.state)), span: 2)) }
        items.append(UKGridItem(UKWeatherTiles.chance(hourly), span: 2))
        items.append(UKGridItem(UKWeatherTiles.accumulation(hourly, unit: current.precipitationUnit ?? WeatherUnits.defaultPrecipitationUnit), span: 2))
        items.append(UKGridItem(UKWeatherTiles.metric(hourly, humidity: true), span: 2))
        items.append(UKGridItem(UKWeatherTiles.metric(hourly, humidity: false), span: 2))
        for tile in WeatherHighlights.tiles(current: current, today: daily, sun: sun) {
            items.append(UKGridItem(UKWeatherTiles.highlight(tile, sun: sun, traits: traitCollection), span: tile.kind == .wind ? 2 : 1))
        }
        grid.setItems(items)
        host.contentChanged()
    }
}

/// The highlight tiles' contents (`WeatherAqiTile`, `WeatherChanceTile`, `WeatherAccumulationTile`, `WeatherMetricTile`,
/// `WeatherHighlightTile`, `WeatherWindTile`).
@MainActor
enum UKWeatherTiles {
    private static func column(_ views: [UIView], spacing: CGFloat = HassTokens.Spacing.s) -> UIStackView {
        let stack = UIStackView(arrangedSubviews: views)
        stack.axis = .vertical
        stack.spacing = spacing
        return stack
    }

    private static func unavailableLabel() -> UILabel {
        let label = UILabel.uk(.subheadline, ink: UKWeatherInk.onDarkSecondary)
        label.text = WeatherCopy.text("unavailable")
        return label
    }

    private static func chart(_ values: [Double?], domain: Double, axis: (String, String, String), labels: [String], tint: UIColor) -> UIView {
        UKAutoSizingHost(UKWeatherBarChartView(values: values, domain: domain, axisLabels: axis, hourLabels: labels, tint: tint))
    }

    static func aqi(_ tile: WeatherHighlight) -> UIView {
        let value = UILabel.uk(.title1, weight: .bold, monospacedDigit: true, ink: UKWeatherInk.onDark, lines: 1)
        value.text = tile.value
        value.setContentHuggingPriority(.required, for: .horizontal)
        let status = UILabel.uk(.subheadline, ink: UKWeatherInk.onDarkSecondary)
        status.text = tile.status ?? ""
        let row = UIStackView(arrangedSubviews: [value, status])
        row.axis = .horizontal
        row.alignment = .firstBaseline
        row.spacing = HassTokens.Spacing.s
        let rail = UKWeatherRailView(tone: .aqi, range: WeatherRailRange(markerPercent: tile.percent))
        return UKWeatherTileView(title: tile.title, symbol: WeatherSymbols.highlight(.aqi), label: tile.accessibilityLabel,
                                 identifier: "weather.highlight.aqi", value: nil, content: column([row, rail]))
    }

    static func chance(_ forecasts: [WeatherForecast]) -> UIView {
        let points = WeatherPrecipitationTimeline.points(forecasts, limit: 6)
        let peak = WeatherPrecipitationTimeline.peakChance(points)
        let domain = WeatherPrecipitationTimeline.chanceDomain(peak: peak)
        let labels = WeatherChartText.hourLabels(points)
        let series = zip(labels, points).map { "\($0) \(WeatherChartText.percent($1.probability))" }.joined(separator: ", ")
        let content: UIView = peak != nil
            ? chart(points.map(\.probability), domain: domain, axis: (WeatherChartText.percent(domain), WeatherChartText.percent(domain / 2), WeatherChartText.percent(0)),
                    labels: labels, tint: UKWeatherInk.drop)
            : unavailableLabel()
        return UKWeatherTileView(
            title: WeatherCopy.text("precipitation.title"), symbol: WeatherSymbols.precipitation,
            label: WeatherCopy.text("precipitation.chanceChartAriaLabel", ["chance": WeatherChartText.percent(peak), "hours": String(points.count)]),
            identifier: "weather.highlight.precipitation", value: series, content: content)
    }

    static func accumulation(_ forecasts: [WeatherForecast], unit: String) -> UIView {
        let points = WeatherPrecipitationTimeline.points(forecasts, limit: 6)
        let total = WeatherPrecipitationTimeline.total(points)
        let axis = WeatherPrecipitationTimeline.amountAxis(total: total, unit: unit)
        let labels = WeatherChartText.hourLabels(points)
        let series = zip(labels, points).map { "\($0) \(WeatherChartText.amount($1.cumulative, unit: unit))" }.joined(separator: ", ")
        func axisText(_ value: Double) -> String {
            let normalized = unit.trimmingCharacters(in: .whitespaces).isEmpty ? "in" : unit
            let text = WeatherFormat.number(value, digits: axis.maximumFractionDigits) ?? "--"
            return "\(text) \(normalized)"
        }
        let content: UIView = total != nil
            ? chart(points.map(\.cumulative), domain: axis.domain, axis: (axisText(axis.domain), axisText(axis.step), axisText(0)), labels: labels,
                    tint: UIColor(red: 0.55, green: 0.85, blue: 1.0, alpha: 1))
            : unavailableLabel()
        return UKWeatherTileView(
            title: WeatherCopy.text("precipitation.cumulativeHeading"), symbol: WeatherSymbols.precipitation,
            label: WeatherCopy.text("precipitation.cumulativeChartAriaLabel", ["hours": String(points.count), "total": WeatherChartText.amount(total, unit: unit)]),
            identifier: "weather.highlight.accumulation", value: series, content: content)
    }

    static func metric(_ forecasts: [WeatherForecast], humidity: Bool) -> UIView {
        let points = WeatherHourlyMetrics.points(forecasts)
        let values: [Double?] = points.map { humidity ? $0.humidity : $0.cloudCover }
        let known = values.compactMap { $0 }
        let domain = WeatherPrecipitationTimeline.chanceDomain(peak: known.max())
        let title = WeatherCopy.text(humidity ? "hourlyMetrics.humidity" : "hourlyMetrics.cloudCover")
        let labels = points.enumerated().map { index, point in
            index == 0 ? WeatherCopy.text("precipitation.now") : point.time.map { WeatherDates.hour($0) } ?? "--"
        }
        let series = zip(labels, values).map { "\($0) \(WeatherChartText.percent($1))" }.joined(separator: ", ")
        let tint = humidity ? UIColor(red: 0.40, green: 0.85, blue: 0.80, alpha: 1) : UIColor(red: 0.80, green: 0.86, blue: 0.95, alpha: 1)
        let content: UIView = known.isEmpty
            ? unavailableLabel()
            : chart(values, domain: domain, axis: (WeatherChartText.percent(domain), WeatherChartText.percent(domain / 2), WeatherChartText.percent(0)),
                    labels: labels, tint: tint)
        return UKWeatherTileView(
            title: title, symbol: humidity ? WeatherSymbols.humidity : WeatherSymbols.cloudCover,
            label: WeatherCopy.text("hourlyMetrics.ariaLabel", [
                "hours": String(points.count), "maximum": WeatherChartText.percent(known.max()), "minimum": WeatherChartText.percent(known.min()), "title": title,
            ]),
            identifier: humidity ? "weather.highlight.humidity" : "weather.highlight.cloud", value: series, content: content)
    }

    static func highlight(_ tile: WeatherHighlight, sun: WeatherSunInput?, traits: UITraitCollection) -> UIView {
        if tile.kind == .wind, let wind = tile.wind { return windTile(tile, wind, traits: traits) }
        let sunEvent = sun.flatMap { WeatherPresentation.sun(state: $0.state, nextRising: $0.nextRising, nextSetting: $0.nextSetting)?.primary }
        return UKWeatherTileView(
            title: tile.title, symbol: WeatherSymbols.highlight(tile.kind, sun: sunEvent), label: tile.accessibilityLabel,
            identifier: "weather.highlight.\(tile.kind.rawValue)", value: nil, content: highlightContent(tile))
    }

    private static func highlightContent(_ tile: WeatherHighlight) -> UIView {
        if !tile.available {
            let value = UILabel.uk(.title2, weight: .bold, ink: UKWeatherInk.onDark)
            value.text = tile.value
            let glyph = UIImageView()
            glyph.tintColor = UKWeatherInk.onDark.withAlphaComponent(0.35)
            glyph.contentMode = .left
            glyph.image = UKFont.symbol(WeatherSymbols.highlight(tile.kind), style: .title1)
            return column([value, glyph])
        }
        if tile.kind == .pressure {
            let parts = tile.value.split(separator: " ", maxSplits: 1).map(String.init)
            return UKAutoSizingHost(UKWeatherPressureGaugeView(percent: tile.percent ?? 50, value: parts.first ?? tile.value, unit: parts.count > 1 ? parts[1] : nil))
        }
        let value = UILabel.uk(.title2, weight: .bold, monospacedDigit: true, ink: UKWeatherInk.onDark, lines: 1)
        value.text = tile.value
        value.setContentHuggingPriority(.required, for: .horizontal)
        var row: [UIView] = [value]
        if let status = tile.status {
            let label = UILabel.uk(.footnote, ink: UKWeatherInk.onDarkSecondary)
            label.text = status
            row.append(label)
        }
        let line = UIStackView(arrangedSubviews: row)
        line.axis = .horizontal
        line.alignment = .firstBaseline
        line.spacing = HassTokens.Spacing.s
        var parts: [UIView] = [line]
        switch tile.kind {
        case .feels: parts.append(UKWeatherRailView(tone: .feels, range: WeatherRailRange(markerPercent: tile.percent)))
        case .uv: parts.append(UKWeatherRailView(tone: .uv, range: WeatherRailRange(markerPercent: tile.percent)))
        case .visibility:
            parts.append(UKWeatherRailView(tone: .visibility, range: WeatherRailRange(
                markerPercent: (tile.percent ?? 0) > 0 ? tile.percent : nil, rangeSizePercent: tile.percent, rangeStartPercent: 0)))
        case .sun: parts.append(UKAutoSizingHost(UKWeatherSunArcView(percent: tile.percent)))
        default: break
        }
        return column(parts)
    }

    private static func windTile(_ tile: WeatherHighlight, _ wind: WeatherHighlight.Wind, traits: UITraitCollection) -> UIView {
        func row(_ label: String, _ value: String) -> UIView {
            let name = UILabel.uk(.footnote, ink: UKWeatherInk.onDarkSecondary)
            name.text = label
            let text = UILabel.uk(.headline, monospacedDigit: true, ink: UKWeatherInk.onDark)
            text.text = value
            return column([name, text], spacing: 0)
        }
        let readout = column([row(wind.speedLabel, wind.speedValue), row(wind.gustLabel, wind.gustValue), row(wind.directionLabel, wind.directionValue)])
        let side = min(UIFontMetrics(forTextStyle: .footnote).scaledValue(for: 104, compatibleWith: traits), 160)
        let compass = UKWeatherCompassView(sourceDegrees: wind.showVector ? wind.bearingDegrees : nil)
        compass.translatesAutoresizingMaskIntoConstraints = false
        compass.widthAnchor.constraint(equalToConstant: side).isActive = true
        compass.heightAnchor.constraint(equalToConstant: side).isActive = true
        let compassBox = UIView()
        compassBox.addSubview(compass)
        compass.topAnchor.constraint(equalTo: compassBox.topAnchor).isActive = true
        compass.bottomAnchor.constraint(equalTo: compassBox.bottomAnchor).isActive = true
        compass.trailingAnchor.constraint(equalTo: compassBox.trailingAnchor).isActive = true
        compassBox.widthAnchor.constraint(equalToConstant: side).isActive = true
        let content: UIStackView
        if traits.ukIsAccessibilitySize {
            let box = UIView()
            compass.removeFromSuperview()
            box.addSubview(compass)
            compass.topAnchor.constraint(equalTo: box.topAnchor).isActive = true
            compass.bottomAnchor.constraint(equalTo: box.bottomAnchor).isActive = true
            compass.leadingAnchor.constraint(equalTo: box.leadingAnchor).isActive = true
            content = column([readout, box], spacing: HassTokens.Spacing.m)
        } else {
            content = UIStackView(arrangedSubviews: [readout, UIView(), compassBox])
            content.axis = .horizontal
            content.alignment = .center
            content.spacing = HassTokens.Spacing.m
        }
        return UKWeatherTileView(title: tile.title, symbol: WeatherSymbols.highlight(.wind), label: tile.accessibilityLabel,
                                 identifier: "weather.highlight.wind", value: nil, content: content)
    }
}
#endif
