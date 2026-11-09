#if os(iOS)
import HassDesign
import UIKit

/// What a tile face shows: the inputs of `GlassTileFace`.
struct UKTileFaceContent: Equatable {
    var title: String
    var subtitle: String?
    var symbol: String
    /// The glyph and rim colour of a tinted face; defaults to the family's glyph colour.
    var tint: UIColor
    var family: ColorFamily?
    /// A solid fill the caller owns (a room's colour); wins over the family.
    var fillRGB: UInt32?
    var isActive: Bool
    var isUnavailable: Bool
    /// The red error face.
    var isError = false
    var showsChevron = false
    /// 0...1 fill from the leading edge, or nil.
    var level: Double?
    /// The level fill's colour on a tinted face, or a light's colour washed over the lit band.
    var levelTint: UIColor?
    /// A state wash over a dark face.
    var wash: UIColor?
    /// Room kept free at the trailing edge for an accessory.
    var trailingInset: CGFloat = 0
    /// Room kept free at the bottom for an accessory rail under the text.
    var bottomInset: CGFloat = 0
    /// Draws no leading glyph: the tile's first action disc carries the state glyph (`TileActionPlacement.carriesGlyph`).
    var hidesGlyph = false
    /// The read-only face: flat, with no sheen, no rim and no tinted stroke.
    var isFlat = false
    /// How the text sits in the room the grid gave the tile (`TileTextFit`).
    var textFit: TileTextFit = .natural
    /// Names the ticker probes for UI tests (the tile's identifier).
    var probeIdentifier: String?

    init(title: String, subtitle: String? = nil, symbol: String, tint: UIColor? = nil, family: ColorFamily? = nil, fillRGB: UInt32? = nil,
         isActive: Bool, isUnavailable: Bool = false, isError: Bool = false, showsChevron: Bool = false, level: Double? = nil,
         levelTint: UIColor? = nil, wash: UIColor? = nil, trailingInset: CGFloat = 0, bottomInset: CGFloat = 0, hidesGlyph: Bool = false,
         isFlat: Bool = false, textFit: TileTextFit = .natural, probeIdentifier: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.tint = tint ?? family.map { UIColor($0.glyphToken) } ?? UIColor.tintColor
        self.family = family
        self.fillRGB = fillRGB
        self.isActive = isActive
        self.isUnavailable = isUnavailable
        self.isError = isError
        self.showsChevron = showsChevron
        self.level = level
        self.levelTint = levelTint
        self.wash = wash
        self.trailingInset = trailingInset
        self.bottomInset = bottomInset
        self.hidesGlyph = hidesGlyph
        self.isFlat = isFlat
        self.textFit = textFit
        self.probeIdentifier = probeIdentifier
    }

    /// What decides the tile's colours (`GlassTileFace.TileColorKey`): a change cross-fades the ground, rim, ink and glyph together.
    /// The level is in it only as whether a band is drawn: its width is progress, not state colour.
    struct ColorKey: Equatable {
        var isActive: Bool
        var isError: Bool
        var isUnavailable: Bool
        var family: ColorFamily?
        var fillRGB: UInt32?
        var wash: UIColor?
        var tint: UIColor
        var levelTint: UIColor?
        var hasLevel: Bool
    }

    var colorKey: ColorKey {
        ColorKey(isActive: isActive, isError: isError, isUnavailable: isUnavailable, family: family, fillRGB: fillRGB, wash: wash,
                 tint: tint, levelTint: levelTint, hasLevel: (level ?? 0) > 0)
    }
}

/// The tile's drawing, shared by ``UKGlassTileView`` and ``UKBrightnessTileView`` so every entity tile looks the same: the UIKit
/// counterpart of `GlassTileFace`.
///
/// **Cost.** A face is a flat ground layer, an optional level band, and one finish layer whose image (sheen, hairline and tint stroke)
/// is drawn once per tile size and shared (``UKTileFinishImage``), so scrolling a grid redraws nothing. Layout is by hand
/// (`layoutSubviews`/`sizeThatFits`), so measuring 300 tiles is text measurement only.
@MainActor
final class UKGlassTileFaceView: UIView {
    // MARK: Inputs

    private(set) var content: UKTileFaceContent
    private(set) var environment = UKTileEnvironment()
    /// The control is enabled (SwiftUI `isEnabled`): a disabled control draws its neutral glyph in grey and its tint stroke fainter.
    var isEnabled = true { didSet { if isEnabled != oldValue { refresh(animated: false) } } }

    // MARK: Parts

    private let groundLayer = CALayer()
    private let groundGradient = CAGradientLayer()
    private let ornamentClip = CALayer()
    private let bandLayer = CAGradientLayer()
    private let shadeLayer = CALayer()
    private let finishLayer = CALayer()
    private let glyphView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let pendingBar = UKPendingValueBar()
    private let chevronView = UIImageView()
    /// The scrolling text of a tile the grid could not widen any more (`TileTextFit.ticker`); made on first use.
    private var titleTicker: UKTickerLabel?
    private var subtitleTicker: UKTickerLabel?

    private var paint: UKTilePaint?
    private var observers: UKObserverTokens?
    private var hasConfigured = false
    private var lastFinishSize: CGSize = .zero

    // MARK: Init

    init(content: UKTileFaceContent) {
        self.content = content
        super.init(frame: .zero)
        clipsToBounds = false
        isAccessibilityElement = false
        for layer in [groundLayer, groundGradient, ornamentClip, finishLayer] {
            layer.cornerRadius = HassTokens.Radius.tile
            layer.cornerCurve = .continuous
        }
        groundGradient.isHidden = true
        groundGradient.startPoint = CGPoint(x: 0.5, y: 0)
        groundGradient.endPoint = CGPoint(x: 0.5, y: 1)
        bandLayer.startPoint = CGPoint(x: 0.5, y: 0)
        bandLayer.endPoint = CGPoint(x: 0.5, y: 1)
        ornamentClip.addSublayer(bandLayer)
        ornamentClip.addSublayer(shadeLayer)
        bandLayer.isHidden = true
        shadeLayer.isHidden = true
        finishLayer.contentsGravity = .resize
        finishLayer.contentsScale = UIScreen.main.scale
        for layer in [groundLayer, groundGradient, ornamentClip, finishLayer] { self.layer.addSublayer(layer) }

        glyphView.contentMode = .center
        titleLabel.numberOfLines = 0
        subtitleLabel.numberOfLines = 0
        chevronView.contentMode = .center
        for label in [titleLabel, subtitleLabel] { label.isAccessibilityElement = false; label.lineBreakMode = .byWordWrapping }
        for view in [glyphView, chevronView, pendingBar] { view.isAccessibilityElement = false }
        for view in [glyphView, titleLabel, subtitleLabel, pendingBar, chevronView] as [UIView] { addSubview(view) }
        pendingBar.isHidden = true

        registerForTraitChanges([UITraitPreferredContentSizeCategory.self, UITraitUserInterfaceStyle.self, UITraitAccessibilityContrast.self]) {
            (view: UKGlassTileFaceView, _) in view.refresh(animated: false)
        }
        observers = NotificationCenter.default.ukObserveAccessibility { [weak self] in self?.refresh(animated: false) }
        refresh(animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: Configure

    /// Shows `content`. A change of state colour cross-fades (0.6 s) once the face is on screen; the first call never animates.
    func apply(_ content: UKTileFaceContent, environment: UKTileEnvironment, animated: Bool = true) {
        let colorChanged = content.colorKey != self.content.colorKey || environment != self.environment
        let levelChanged = content.level != self.content.level
        let symbolChanged = content.symbol != self.content.symbol
        let old = self.content
        self.content = content
        self.environment = environment
        refresh(animated: animated && hasConfigured && colorChanged, levelOnly: levelChanged && !colorChanged && hasConfigured && animated,
                symbolTransition: symbolChanged && hasConfigured && animated && old.symbol != content.symbol)
        hasConfigured = true
    }

    // MARK: Resolved style

    /// The traits the face draws for: its own, or the ones a grid measuring with this face as a prototype supplies.
    private var measureTraits: UITraitCollection?
    private var traits: UITraitCollection { measureTraits ?? traitCollection }

    private var appearance: TileAppearance { UKDesign.tileAppearance(surface: environment.surface, traits: traits) }
    private var finish: TileFinish { UKDesign.effectiveFinish(environment.finish, traits: traits) }
    private var style: TileFaceStyle {
        .resolve(family: content.family, isActive: content.isActive, isError: content.isError, isUnavailable: content.isUnavailable,
                 solidFill: content.fillRGB)
    }
    private var layoutKind: TileLayout { environment.layout.resolved(accessibilitySize: traits.ukIsAccessibilitySize) }

    /// The caller's tint as a glyph on the face: unchanged on dark, darkened to 3:1 on a light cell.
    private func tintGlyph(_ tint: UIColor) -> UIColor {
        guard appearance == .light else { return tint }
        let rgba = tint.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)).ukRGBA
        let shaded = TileFaceStyle.lightGlyph(forTint: (Double(rgba.r), Double(rgba.g), Double(rgba.b)))
        return UIColor(red: shaded.red, green: shaded.green, blue: shaded.blue, alpha: rgba.a)
    }

    // MARK: Refresh

    private func refresh(animated: Bool, levelOnly: Bool = false, symbolTransition: Bool = false) {
        let style = style
        let appearance = appearance
        let finish = finish
        let content = content
        let tintGlyph = tintGlyph(content.tint)

        updateTextAndGlyph(symbolTransition: symbolTransition)

        // Inks.
        // A tinted face draws the caller's tint (a UIColor made legible above); every other face is a raw token.
        let glyphColor: UIColor
        if case .tinted = style, isEnabled { glyphColor = tintGlyph }
        else {
            glyphColor = UIColor(TileFaceInk.glyphToken(style: style, appearance: appearance, finish: finish, isEnabled: isEnabled,
                                                        family: content.family, tintGlyph: .white))
        }
        let primary = UIColor(TileFaceInk.primaryToken(style: style, appearance: appearance))
        let secondary = UIColor(TileFaceInk.secondaryToken(style: style, appearance: appearance, finish: finish, surface: environment.surface,
                                                             hasWash: content.wash != nil))
        let chevronColor = secondary.ukOpacity(0.8)
        let glyphAlpha: CGFloat = content.isUnavailable ? 0.5 : 1

        let paint = UKTilePaint.make(UKTilePaintInput(
            style: style, surface: environment.surface, appearance: appearance, finish: finish, tint: content.tint, tintGlyph: tintGlyph,
            wash: content.wash, level: content.level, levelTint: content.levelTint, isEnabled: isEnabled, isUnavailable: content.isUnavailable,
            reduceTransparency: UIAccessibility.isReduceTransparencyEnabled, traits: traits, isFlat: content.isFlat))

        let animate = animated && window != nil
        let work = { [self] in
            titleLabel.textColor = primary
            subtitleLabel.textColor = secondary
            titleTicker?.textColor = primary
            subtitleTicker?.textColor = secondary
            glyphView.tintColor = glyphColor
            chevronView.tintColor = chevronColor
            glyphView.alpha = glyphAlpha
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            applyPaint(paint)
            CATransaction.commit()
        }
        if animate && !levelOnly {
            // Ground, rim, ink and glyph cross-fade together (0.6 s, 0.2 s with Reduce Motion).
            UKMotion.stateFade("GlassTile", view: self, animated: true, work)
        } else if levelOnly && window != nil {
            // Only the band's width moved: it glides on the quick ease-out and nothing else changes.
            let before = (bandLayer.frame, shadeLayer.frame)
            work()
            let after = (bandLayer.frame, shadeLayer.frame)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            bandLayer.frame = before.0
            shadeLayer.frame = before.1
            CATransaction.commit()
            UKMotion.quick {
                bandLayer.frame = after.0
                shadeLayer.frame = after.1
            }
        } else {
            work()
        }
        setNeedsLayout()
        invalidateIntrinsicContentSize()
    }

    /// Sets the labels' fonts and text, the glyph and the pending bar: everything that decides the face's size.
    private func updateTextAndGlyph(symbolTransition: Bool = false) {
        let content = content
        let style = style
        let fit = content.textFit
        titleLabel.font = UKFont.tileTitle(traits)
        subtitleLabel.font = UKFont.preferred(.footnote, monospacedDigit: true, traits: traits)
        titleLabel.text = content.title
        let showsPending = content.subtitle != nil && environment.valuesPending
        subtitleLabel.text = showsPending ? nil : content.subtitle
        pendingBar.isHidden = !showsPending
        switch fit {
        case .natural:
            // Wraps to as many lines as it needs; a single-line subtitle shrinks a little before it truncates.
            titleLabel.numberOfLines = 0
            titleLabel.lineBreakMode = .byWordWrapping
            subtitleLabel.numberOfLines = environment.singleLineSubtitle ? 1 : 0
            subtitleLabel.adjustsFontSizeToFitWidth = environment.singleLineSubtitle
            subtitleLabel.minimumScaleFactor = environment.singleLineSubtitle ? 0.85 : 0
            subtitleLabel.lineBreakMode = .byWordWrapping
        case .oneLine, .ticker:
            // One line: the grid widened the tile to fit it.
            titleLabel.numberOfLines = 1
            titleLabel.lineBreakMode = .byTruncatingTail
            subtitleLabel.numberOfLines = 1
            subtitleLabel.adjustsFontSizeToFitWidth = false
            subtitleLabel.minimumScaleFactor = 0
            subtitleLabel.lineBreakMode = .byTruncatingTail
        }
        subtitleLabel.baselineAdjustment = .alignCenters
        titleLabel.isHidden = fit == .ticker
        subtitleLabel.isHidden = content.subtitle == nil || showsPending || fit == .ticker
        updateTickers(showsPending: showsPending)

        let isRow = layoutKind == .row
        glyphView.isHidden = content.hidesGlyph
        let image = UKFont.symbol(content.symbol, style: isRow ? .title2 : .title3, filled: content.isActive || style.isColored, traits: traits)
        if symbolTransition, !UKDesign.reduceMotion, let image {
            glyphView.setSymbolImage(image, contentTransition: .replace)
        } else {
            glyphView.image = image
        }
        chevronView.image = UKFont.symbol("chevron.right", style: .footnote, weight: .semibold, traits: traits)
        chevronView.isHidden = !content.showsChevron
    }

    /// Makes, feeds and hides the scrolling text: the title and state line of a tile the grid could not widen (`TileTextFit.ticker`),
    /// which wrap instead at accessibility sizes and under Reduce Motion (the ticker's own rule).
    private func updateTickers(showsPending: Bool) {
        guard content.textFit == .ticker else {
            titleTicker?.isHidden = true
            subtitleTicker?.isHidden = true
            return
        }
        let wraps = traits.ukIsAccessibilitySize
        if titleTicker == nil {
            let ticker = UKTickerLabel(content.title, textStyle: .subheadline, weight: .bold, wraps: wraps)
            ticker.textColor = titleLabel.textColor
            addSubview(ticker)
            titleTicker = ticker
        }
        if subtitleTicker == nil {
            let ticker = UKTickerLabel(content.subtitle ?? "", textStyle: .footnote, wraps: wraps)
            ticker.monospacedDigit = true
            ticker.textColor = subtitleLabel.textColor
            addSubview(ticker)
            subtitleTicker = ticker
        }
        titleTicker?.text = content.title
        titleTicker?.wraps = wraps
        titleTicker?.probe = content.probeIdentifier.map { "\($0).title.ticker" }
        titleTicker?.isHidden = false
        subtitleTicker?.text = content.subtitle ?? ""
        subtitleTicker?.wraps = wraps
        subtitleTicker?.probe = content.probeIdentifier.map { "\($0).subtitle.ticker" }
        subtitleTicker?.isHidden = content.subtitle == nil || showsPending
    }

    /// The height a face with `content` takes `width` wide, for a grid that measures every tile with one prototype. Touches only
    /// text and glyph, never the layers.
    func measuredHeight(content: UKTileFaceContent, environment: UKTileEnvironment, width: CGFloat, traits: UITraitCollection) -> CGFloat {
        measureTraits = traits
        self.content = content
        self.environment = environment
        updateTextAndGlyph()
        return frames(width: width, height: nil).size.height
    }

    private func applyPaint(_ new: UKTilePaint) {
        paint = new
        func cg(_ color: UIColor) -> CGColor { color.resolvedColor(with: traits).cgColor }
        if let bottom = new.ground.bottom {
            groundGradient.colors = [cg(new.ground.top), cg(bottom)]
            groundGradient.isHidden = false
            groundLayer.isHidden = true
        } else {
            groundLayer.backgroundColor = cg(new.ground.top)
            groundLayer.isHidden = false
            groundGradient.isHidden = true
        }
        if let band = new.band {
            bandLayer.colors = [cg(band.fill.top), cg(band.fill.bottom ?? band.fill.top)]
            bandLayer.isHidden = false
        } else {
            bandLayer.isHidden = true
        }
        if let shade = new.shade {
            shadeLayer.backgroundColor = cg(shade.color)
            shadeLayer.isHidden = false
        } else {
            shadeLayer.isHidden = true
        }
        layoutBand()
        updateFinishImage(force: true)
    }

    /// Places the band and shade for the current level. The ornaments clip to the tile's rounded shape only when partial: a full
    /// band takes the tile's corners itself, which costs no offscreen pass.
    private func layoutBand() {
        let size = bounds.size
        ornamentClip.frame = CGRect(origin: .zero, size: size)
        let partial = (paint?.band.map { $0.fraction < 1 } ?? false) || paint?.shade != nil
        ornamentClip.masksToBounds = partial
        if let band = paint?.band, !bandLayer.isHidden {
            bandLayer.frame = CGRect(x: 0, y: 0, width: size.width * band.fraction, height: size.height)
            bandLayer.cornerRadius = partial ? 0 : HassTokens.Radius.tile
            bandLayer.cornerCurve = .continuous
        }
        if let shade = paint?.shade, !shadeLayer.isHidden {
            let width = size.width * shade.fraction
            shadeLayer.frame = CGRect(x: size.width - width, y: 0, width: width, height: size.height)
        }
    }

    private func updateFinishImage(force: Bool = false) {
        guard let paint else { return }
        let size = bounds.size
        guard force || size != lastFinishSize else { return }
        lastFinishSize = size
        let scale = window?.screen.scale ?? traits.displayScale
        finishLayer.contentsScale = scale
        if UKPerfSwitches.isOff(.ukTileFinish) { finishLayer.contents = nil; return }
        finishLayer.contents = UKTileFinishImage.image(size: size, scale: scale > 0 ? scale : UIScreen.main.scale,
                                                       radius: HassTokens.Radius.tile, paint: paint)?.cgImage
    }

    /// Where the state line is drawn, in the face's coordinates (the tile exposes it as a static text, as SwiftUI's text children are).
    var subtitleFrame: CGRect { subtitleLabel.isHidden ? (subtitleTicker?.frame ?? .zero) : subtitleLabel.frame }

    // MARK: Layout

    private struct Frames {
        var size: CGSize
        var glyph: CGRect
        var title: CGRect
        var subtitle: CGRect
        var pending: CGRect
        var chevron: CGRect
    }

    private func measure(_ label: UILabel, width: CGFloat) -> CGFloat {
        guard label.text?.isEmpty == false else { return 0 }
        if label.numberOfLines == 1 { return ceil(label.font.lineHeight) }
        return ceil(label.sizeThatFits(CGSize(width: max(width, 1), height: CGFloat.greatestFiniteMagnitude)).height)
    }

    private func measure(_ ticker: UKTickerLabel?, width: CGFloat) -> CGFloat {
        guard let ticker, !ticker.isHidden else { return 0 }
        return ceil(ticker.sizeThatFits(CGSize(width: max(width, 1), height: 0)).height)
    }

    /// All the frames for a face `width` wide; its height is the natural one, or `height` (a cell stretching it) when larger.
    private func frames(width: CGFloat, height: CGFloat?) -> Frames {
        let pad = HassTokens.Spacing.m
        let layout = layoutKind
        let content = content
        let chevronReserve = content.showsChevron ? GlassTileFace.chevronReserve : 0
        let contentWidth = max(0, width - 2 * pad - chevronReserve - content.trailingInset)
        let hidesGlyph = content.hidesGlyph
        let glyphSize = glyphView.image?.size ?? .zero
        let glyphHeight = hidesGlyph ? 0 : glyphSize.height
        let rowGlyphWidth = GlassTileFace.rowGlyphWidth
        let isRow = layout == .row
        let glyphColumn = isRow && !hidesGlyph ? rowGlyphWidth + HassTokens.Spacing.m : 0
        let textWidth = max(0, contentWidth - glyphColumn)
        let textSpacing: CGFloat = layout == .stackedTop ? HassTokens.Spacing.s : 2

        let ticks = content.textFit == .ticker
        let titleHeight = ticks ? measure(titleTicker, width: textWidth) : measure(titleLabel, width: textWidth)
        let hasSubtitle = content.subtitle != nil
        let pendingSize = pendingBar.isHidden ? CGSize.zero : pendingBar.sizeThatFits(.zero)
        let subtitleHeight = !pendingBar.isHidden ? pendingSize.height : (ticks ? measure(subtitleTicker, width: textWidth) : measure(subtitleLabel, width: textWidth))
        let textHeight = titleHeight + (hasSubtitle ? textSpacing + subtitleHeight : 0)

        // With no glyph the stack has only the text (the spacer of an anchored-bottom tile still keeps its minimum gap).
        let natural: CGFloat
        switch layout {
        case .row: natural = max(glyphHeight, textHeight)
        case .anchoredBottom: natural = glyphHeight + TileMetrics.glyphGap + textHeight
        case .centeredStack: natural = hidesGlyph ? textHeight : glyphHeight + HassTokens.Spacing.xs + textHeight
        case .stackedTop: natural = hidesGlyph ? textHeight : glyphHeight + HassTokens.Spacing.s + textHeight
        }
        let minContent = TileMetrics.minContentHeight(
            layout: layout, titleLines: environment.titleLines,
            glyphHeight: UKFont.scaled(TileMetrics.glyphHeight, relativeTo: .title3, traits: traits),
            titleLineHeight: UKFont.scaled(TileMetrics.titleLineHeight, relativeTo: .subheadline, traits: traits))
        let naturalFrame = max(natural + content.bottomInset, minContent)
        let totalHeight = max(naturalFrame + 2 * pad, height ?? 0)
        let frameHeight = totalHeight - 2 * pad

        // Where the block of glyph and text starts, for the arrangements that centre it.
        let centred = pad + (frameHeight - natural - content.bottomInset) / 2
        var glyphY = pad, textY = pad
        switch layout {
        case .row:
            glyphY = centred + (natural - glyphHeight) / 2
            textY = centred + (natural - textHeight) / 2
        case .anchoredBottom:
            glyphY = pad
            textY = pad + (frameHeight - content.bottomInset) - textHeight
        case .centeredStack:
            glyphY = centred
            textY = centred + (hidesGlyph ? 0 : glyphHeight + HassTokens.Spacing.xs)
        case .stackedTop:
            glyphY = pad
            textY = pad + (hidesGlyph ? 0 : glyphHeight + HassTokens.Spacing.s)
        }
        let glyphX = pad
        let textX = pad + glyphColumn
        let glyphWidth = isRow ? rowGlyphWidth : max(glyphSize.width, 1)
        let chevronSize = chevronView.image?.size ?? .zero
        return Frames(
            size: CGSize(width: width, height: totalHeight),
            glyph: CGRect(x: glyphX, y: glyphY, width: isRow ? glyphWidth : glyphSize.width, height: glyphHeight),
            title: CGRect(x: textX, y: textY, width: textWidth, height: titleHeight),
            subtitle: CGRect(x: textX, y: textY + titleHeight + textSpacing, width: textWidth, height: subtitleHeight),
            pending: CGRect(x: textX, y: textY + titleHeight + textSpacing, width: pendingSize.width, height: pendingSize.height),
            chevron: CGRect(x: width - pad - chevronSize.width, y: (totalHeight - chevronSize.height) / 2, width: chevronSize.width, height: chevronSize.height))
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        frames(width: size.width, height: nil).size
    }

    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: frames(width: bounds.width > 0 ? bounds.width : 170, height: nil).size.height) }

    /// The natural height at `width` (a grid measures with this).
    func height(forWidth width: CGFloat) -> CGFloat { frames(width: width, height: nil).size.height }

    override func layoutSubviews() {
        super.layoutSubviews()
        let frames = frames(width: bounds.width, height: bounds.height)
        let mirror = effectiveUserInterfaceLayoutDirection == .rightToLeft
        func place(_ view: UIView, _ rect: CGRect) {
            view.frame = mirror ? CGRect(x: bounds.width - rect.maxX, y: rect.minY, width: rect.width, height: rect.height) : rect
        }
        place(glyphView, frames.glyph)
        place(titleLabel, frames.title)
        place(subtitleLabel, frames.subtitle)
        if let titleTicker { place(titleTicker, frames.title) }
        if let subtitleTicker { place(subtitleTicker, frames.subtitle) }
        place(pendingBar, frames.pending)
        place(chevronView, frames.chevron)
        let isRTL = mirror
        titleLabel.textAlignment = isRTL ? .right : .left
        subtitleLabel.textAlignment = isRTL ? .right : .left
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in [groundLayer, groundGradient, finishLayer] { layer.frame = bounds }
        layoutBand()
        updateFinishImage()
        CATransaction.commit()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { updateFinishImage(force: true) }
    }
}
#endif
