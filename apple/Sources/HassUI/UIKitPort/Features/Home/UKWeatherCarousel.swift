#if os(iOS)
import HassCore
import HassDesign
import UIKit

// MARK: - Hour cells

/// One hour in the Home card's carousel (`WeatherCardHour`): time, glyph and temperature.
@MainActor
final class UKWeatherCardHourCell: UKMeasuredCell {
    private let time = UILabel.uk(.footnote, weight: .semibold, ink: UKWeatherInk.onDark, alignment: .center)
    private let glyph: UKWeatherGlyphView
    private let degree = UILabel.uk(.body, weight: .medium, monospacedDigit: true, ink: UKWeatherInk.onDark, lines: 1, alignment: .center)

    init(forecast: WeatherForecast, index: Int, current: WeatherCurrent) {
        glyph = UKWeatherGlyphView(condition: forecast.condition, size: 22)
        super.init(frame: .zero)
        time.text = WeatherFormat.hourLabel(forecast.datetime, index: index)
        degree.text = WeatherFormat.degree(forecast.temperature)
        [time, glyph, degree].forEach(addSubview)
        isAccessibilityElement = true
        accessibilityLabel = "\(WeatherFormat.hourLabel(forecast.datetime, index: index)) \(WeatherConditionInfo(forecast.condition).label) "
            + WeatherFormat.temperature(forecast.temperature, unit: current.temperatureUnit)
        accessibilityIdentifier = "home.weather.hour.\(index)"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func metrics(width: CGFloat) -> (time: CGSize, glyph: CGSize, degree: CGSize, content: CGFloat) {
        let timeSize = time.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        let glyphSize = glyph.sizeThatFits(.zero)
        let degreeSize = degree.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        let content = ceil(timeSize.height) + HassTokens.Spacing.xs + glyphSize.height + HassTokens.Spacing.xs + ceil(degreeSize.height)
        return (timeSize, glyphSize, degreeSize, content)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        CGSize(width: size.width, height: max(72, metrics(width: size.width).content) + 2 * HassTokens.Spacing.xs)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let m = metrics(width: bounds.width)
        let region = bounds.height - 2 * HassTokens.Spacing.xs
        var y = HassTokens.Spacing.xs + (region - m.content) / 2
        time.frame = CGRect(x: 0, y: y, width: bounds.width, height: ceil(m.time.height))
        y += ceil(m.time.height) + HassTokens.Spacing.xs
        glyph.frame = CGRect(x: (bounds.width - m.glyph.width) / 2, y: y, width: m.glyph.width, height: m.glyph.height)
        y += m.glyph.height + HassTokens.Spacing.xs
        degree.frame = CGRect(x: 0, y: y, width: bounds.width, height: ceil(m.degree.height))
    }
}

/// The skeleton of an hour while the forecast loads (`WeatherCardHourPlaceholder`): the same height, so nothing jumps.
@MainActor
final class UKWeatherCardHourPlaceholder: UKMeasuredCell {
    private let shapes = [UIView(), UIView(), UIView()]

    override init(frame: CGRect) {
        super.init(frame: frame)
        for shape in shapes {
            shape.backgroundColor = UKWeatherInk.onDark.withAlphaComponent(0.18)
            addSubview(shape)
        }
        isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: size.width, height: 72 + 2 * HassTokens.Spacing.xs) }

    override func layoutSubviews() {
        super.layoutSubviews()
        let sizes = [CGSize(width: 28, height: 8), CGSize(width: 22, height: 22), CGSize(width: 24, height: 8)]
        let total = sizes.reduce(0) { $0 + $1.height } + 2 * HassTokens.Spacing.s
        var y = (bounds.height - total) / 2
        for (shape, size) in zip(shapes, sizes) {
            shape.frame = CGRect(x: (bounds.width - size.width) / 2, y: y, width: size.width, height: size.height)
            shape.layer.cornerRadius = min(size.width, size.height) / 2
            y += size.height + HassTokens.Spacing.s
        }
    }
}

/// One hour in the sheet's carousel, in the active mode (`WeatherModalHour`).
@MainActor
final class UKWeatherModalHourCell: UKMeasuredCell {
    private let time = UILabel.uk(.subheadline, ink: UKWeatherInk.onDarkSecondary, alignment: .center)
    private let visual = UIView()
    private let glyph: UKWeatherGlyphView?
    private let symbolView = UIImageView()
    private let primary = UILabel.uk(.subheadline, weight: .bold, monospacedDigit: true, ink: UKWeatherInk.onDark, lines: 1, alignment: .center)
    private let secondary = UILabel.uk(.subheadline, monospacedDigit: true, ink: UKWeatherInk.onDarkSecondary, lines: 1, alignment: .center)
    private let mode: WeatherHourlyMode
    private let bearing: Double?
    private let hasBearing: Bool

    init(forecast: WeatherForecast, index: Int, mode: WeatherHourlyMode, current: WeatherCurrent) {
        self.mode = mode
        let reading = WeatherPresentation.windBearing(forecast.windBearing)
        bearing = reading?.destinationDegrees
        hasBearing = reading != nil
        glyph = mode == .condition ? UKWeatherGlyphView(condition: forecast.condition, size: 30) : nil
        super.init(frame: .zero)
        let label = WeatherFormat.hourLabel(forecast.datetime, index: index)
        time.text = label
        let chance = WeatherFormat.percent(forecast.precipitationProbability) ?? WeatherCopy.text("unavailable")
        let amount = WeatherFormat.measure(forecast.precipitation, unit: current.precipitationUnit, digits: 2)
        let windSpeed = WeatherFormat.windMeasure(forecast.windSpeed, unit: current.windSpeedUnit)?.value ?? "--"
        let gust = WeatherFormat.windMeasure(forecast.windGustSpeed, unit: current.windSpeedUnit)?.value
        symbolView.contentMode = .center
        symbolView.tintColor = UKWeatherInk.onDark
        switch mode {
        case .condition:
            primary.text = WeatherFormat.temperature(forecast.temperature, unit: current.temperatureUnit)
            accessibilityLabel = "\(label) \(WeatherConditionInfo(forecast.condition).label) \(primary.text ?? "")"
        case .precipitation:
            primary.text = chance
            secondary.text = amount
            accessibilityLabel = "\(label) precipitation \(chance)"
            symbolView.tintColor = UKWeatherInk.drop
        case .wind:
            primary.text = windSpeed
            secondary.text = gust
            accessibilityLabel = "\(label) wind \(windSpeed)\(gust.map { " gusts \($0)" } ?? "")"
        }
        secondary.isHidden = secondary.text == nil
        visual.addSubview(symbolView)
        if let glyph { visual.addSubview(glyph) }
        [time, visual, primary, secondary].forEach(addSubview)
        isAccessibilityElement = true
        accessibilityIdentifier = "weather.hour.\(index)"
        ukOnContentSizeChange { [weak self] in self?.redrawSymbol() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func redrawSymbol() {
        switch mode {
        case .condition: break
        case .precipitation:
            let size = UIFontMetrics(forTextStyle: .title3).scaledValue(for: 26, compatibleWith: traitCollection)
            let configuration = UIImage.SymbolConfiguration(pointSize: size).applying(UIImage.SymbolConfiguration.preferringMulticolor())
            symbolView.image = UIImage(systemName: WeatherSymbols.drop, withConfiguration: configuration)
        case .wind:
            let size = UIFontMetrics(forTextStyle: .title3).scaledValue(for: 24, compatibleWith: traitCollection)
            let configuration = UIImage.SymbolConfiguration(pointSize: size, weight: .semibold)
            symbolView.image = UIImage(systemName: hasBearing ? WeatherSymbols.windArrow : WeatherSymbols.windFlag, withConfiguration: configuration)
            symbolView.transform = CGAffineTransform(rotationAngle: CGFloat((bearing ?? 0) * .pi / 180))
        }
        setNeedsLayout()
    }

    private var visualSize: CGSize {
        if let glyph { return glyph.sizeThatFits(.zero) }
        return symbolView.image?.size ?? .zero
    }

    private func metrics(width: CGFloat) -> (time: CGFloat, visual: CGSize, primary: CGFloat, secondary: CGFloat, content: CGFloat) {
        let timeHeight = ceil(time.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height)
        let primaryHeight = ceil(primary.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height)
        let secondaryHeight = secondary.isHidden ? 0 : ceil(secondary.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height)
        let values = primaryHeight + (secondaryHeight > 0 ? 2 + secondaryHeight : 0)
        let content = timeHeight + HassTokens.Spacing.s + visualSize.height + HassTokens.Spacing.s + values
        return (timeHeight, visualSize, primaryHeight, secondaryHeight, content)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        CGSize(width: size.width, height: max(112, metrics(width: size.width).content) + 2 * HassTokens.Spacing.xs)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let m = metrics(width: bounds.width)
        var y = HassTokens.Spacing.xs
        time.frame = CGRect(x: 0, y: y, width: bounds.width, height: m.time)
        y += m.time + HassTokens.Spacing.s
        visual.frame = CGRect(x: (bounds.width - m.visual.width) / 2, y: y, width: m.visual.width, height: m.visual.height)
        if let glyph {
            glyph.frame = visual.bounds
        } else {
            let transform = symbolView.transform
            symbolView.transform = .identity
            symbolView.frame = visual.bounds
            symbolView.transform = transform
        }
        y += m.visual.height + HassTokens.Spacing.s
        primary.frame = CGRect(x: 0, y: y, width: bounds.width, height: m.primary)
        secondary.frame = CGRect(x: 0, y: y + m.primary + 2, width: bounds.width, height: m.secondary)
    }
}

/// The skeleton of a sheet hour while the forecast loads (`WeatherModalHourPlaceholder`).
@MainActor
final class UKWeatherModalHourPlaceholder: UKMeasuredCell {
    private let shapes = [UIView(), UIView(), UIView()]

    override init(frame: CGRect) {
        super.init(frame: frame)
        for shape in shapes {
            shape.backgroundColor = UKWeatherInk.onDark.withAlphaComponent(0.16)
            addSubview(shape)
        }
        isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: size.width, height: 112 + 2 * HassTokens.Spacing.xs) }

    override func layoutSubviews() {
        super.layoutSubviews()
        let sizes = [CGSize(width: 36, height: 10), CGSize(width: 30, height: 30), CGSize(width: 32, height: 10)]
        var y = HassTokens.Spacing.xs
        for (shape, size) in zip(shapes, sizes) {
            shape.frame = CGRect(x: (bounds.width - size.width) / 2, y: y, width: size.width, height: size.height)
            shape.layer.cornerRadius = min(size.width, size.height) / 2
            y += size.height + HassTokens.Spacing.m
        }
    }
}

// MARK: - Carousel

/// A horizontally paging row of equal-width hours with a page indicator and, on wide layouts, previous and next buttons
/// (`WeatherPagedCarousel`). Each page holds ``WeatherCarouselPaging/perPage`` whole cells; scrolling snaps to pages in a paging
/// scroll view (``UKPagedRowView``). VoiceOver reads the hours on the page on screen and pages with a three-finger swipe, the page
/// indicator, or on wide layouts the previous and next buttons.
@MainActor
final class UKWeatherCarouselView: UIView, UKGridMeasuring {
    private let compactPerPage: Int
    private let regularPerPage: Int
    private let label: String
    private let identifier: String
    private var cells: [UIView]
    private var strip: UKPagedRowView!
    private var indicator: UKPageIndicator!
    private let previous = UIButton(type: .custom)
    private let nextButton = UIButton(type: .custom)
    private var paging: WeatherCarouselPaging
    private var firstVisible: Int? = 0

    /// Space reserved at each end for the previous and next buttons.
    private let controlInset = HassTokens.minTarget + HassTokens.Spacing.s

    /// - Parameters:
    ///   - cells: One view per hour (`UKMeasuredCell`s).
    ///   - compactPerPage: Hours per page in a compact layout at the default text size.
    ///   - regularPerPage: Hours per page in a regular layout.
    ///   - label: Spoken name of the row.
    ///   - identifier: The row is `<identifier>.carousel`, its indicator `<identifier>.pages`.
    init(cells: [UIView], compactPerPage: Int, regularPerPage: Int, label: String, identifier: String) {
        self.cells = cells
        self.compactPerPage = compactPerPage
        self.regularPerPage = regularPerPage
        self.label = label
        self.identifier = identifier
        paging = WeatherCarouselPaging(count: cells.count, perPage: compactPerPage)
        super.init(frame: .zero)
        paging = currentPaging()
        strip = UKPagedRowView(itemCount: cells.count, perPage: paging.perPage, animatesPaging: !UIAccessibility.isReduceMotionEnabled) { [weak self] index in
            self?.cells[index] ?? UIView()
        }
        strip.accessibilityIdentifier = "\(identifier).carousel"
        strip.onFirstVisibleChange = { [weak self] in self?.pageChanged() }
        addSubview(strip)
        indicator = UKPageIndicator(page: 0, pageCount: paging.pageCount, label: "\(label) pages", identifier: "\(identifier).pages") { [weak self] page in
            self?.go(to: page)
        }
        addSubview(indicator)
        configureButton(previous, symbol: WeatherSymbols.previous, label: "Previous \(label)", id: "previous") { [weak self] in
            guard let self else { return }
            go(to: paging.page(containing: firstVisible) - 1)
        }
        configureButton(nextButton, symbol: WeatherSymbols.next, label: "Next \(label)", id: "next") { [weak self] in
            guard let self else { return }
            go(to: paging.page(containing: firstVisible) + 1)
        }
        registerForTraitChanges([UITraitHorizontalSizeClass.self, UITraitPreferredContentSizeCategory.self]) { (view: UKWeatherCarouselView, _) in
            view.relayoutForTraits()
        }
        updateControls()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func configureButton(_ button: UIButton, symbol: String, label: String, id: String, action: @escaping () -> Void) {
        button.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        button.layer.borderWidth = 1
        button.layer.borderColor = UKWeatherInk.onDark.withAlphaComponent(0.25).cgColor
        button.tintColor = UKWeatherInk.onDark
        button.accessibilityLabel = label
        button.accessibilityIdentifier = "\(identifier).\(id)"
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        addSubview(button)
        ukOnContentSizeChange { [weak button, weak self] in
            button?.setImage(UKFont.symbol(symbol, style: .body, weight: .semibold, traits: self?.traitCollection), for: .normal)
        }
    }

    private func currentPaging() -> WeatherCarouselPaging {
        WeatherCarouselPaging(
            count: cells.count,
            perPage: WeatherCarouselPaging.hoursPerPage(
                compact: compactPerPage, regular: regularPerPage,
                sizeClass: traitCollection.horizontalSizeClass == .regular ? .regular : .compact,
                typeSize: WeatherCarouselPaging.dynamicTypeSize(traitCollection.preferredContentSizeCategory))
        )
    }

    private var showsControls: Bool { traitCollection.horizontalSizeClass == .regular && paging.overflows }

    /// Replaces the hours (a mode change, a new forecast) and keeps the page.
    func setCells(_ new: [UIView]) {
        cells = new
        paging = currentPaging()
        strip.reload(itemCount: new.count, perPage: paging.perPage)
        indicator.pageCount = paging.pageCount
        pageChanged()
        ukSetNeedsLayoutUpward()
    }

    private func relayoutForTraits() {
        let updated = currentPaging()
        if updated != paging {
            paging = updated
            strip.reload(itemCount: cells.count, perPage: paging.perPage)
            indicator.pageCount = paging.pageCount
            pageChanged()
        }
        ukSetNeedsLayoutUpward()
    }

    private func pageChanged() {
        firstVisible = strip.firstVisible
        indicator.page = paging.page(containing: firstVisible)
        updateControls()
    }

    private func go(to target: Int) {
        // The row scrolls across to the page itself (or jumps with Reduce Motion).
        strip.animatesPaging = !UIAccessibility.isReduceMotionEnabled
        strip.firstVisible = paging.firstIndex(ofPage: paging.clamped(target))
        pageChanged()
    }

    private func updateControls() {
        let current = paging.page(containing: firstVisible)
        previous.isHidden = !showsControls
        nextButton.isHidden = !showsControls
        UKMotion.quick(animated: window != nil) {
            previous.isEnabled = current > 0
            nextButton.isEnabled = current < paging.pageCount - 1
            previous.alpha = previous.isEnabled ? 1 : 0.4
            nextButton.alpha = nextButton.isEnabled ? 1 : 0.4
        }
    }

    /// Strip, previous and next, then the indicator: the order VoiceOver reads them in.
    override var accessibilityElements: [Any]? {
        get {
            var elements: [Any] = [strip as Any]
            if showsControls { elements += [previous, nextButton] }
            if paging.overflows { elements.append(indicator as Any) }
            return elements
        }
        set {}
    }

    // MARK: Layout

    private func stripHeight(width: CGFloat) -> CGFloat {
        let inset = showsControls ? controlInset : 0
        let cellWidth = max(1, (width - 2 * inset) / CGFloat(paging.perPage))
        return ceil(cells.map { $0.sizeThatFits(CGSize(width: cellWidth, height: .greatestFiniteMagnitude)).height }.max() ?? 0)
    }

    func gridHeight(forWidth width: CGFloat) -> CGFloat {
        stripHeight(width: width) + (paging.overflows ? HassTokens.Spacing.xs + HassTokens.minTarget : 0)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: size.width, height: gridHeight(forWidth: size.width)) }

    override func layoutSubviews() {
        super.layoutSubviews()
        let inset = showsControls ? controlInset : 0
        let height = stripHeight(width: bounds.width)
        strip.frame = CGRect(x: inset, y: 0, width: max(0, bounds.width - 2 * inset), height: height)
        indicator.isHidden = !paging.overflows
        indicator.frame = CGRect(x: 0, y: height + HassTokens.Spacing.xs, width: bounds.width, height: HassTokens.minTarget)
        let side = HassTokens.minTarget
        let y = (height - side) / 2
        previous.frame = CGRect(x: 0, y: y, width: side, height: side)
        nextButton.frame = CGRect(x: bounds.width - side, y: y, width: side, height: side)
        for button in [previous, nextButton] { button.layer.cornerRadius = side / 2 }
        updateControls()
    }
}
#endif
