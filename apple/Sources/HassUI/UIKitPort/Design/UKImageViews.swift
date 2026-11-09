#if os(iOS)
import HassDesign
import ImageIO
import UIKit

/// A remote image drawn from ``ImagePipeline`` (`CachedImage`, pattern: `.agents/patterns/image-cache.md`).
///
/// - An image already in memory draws on the first frame, so cells scrolling back into view never flash.
/// - When the URL changes (a rotated camera token, new artwork), the current image stays up until the next one decodes, then
///   cross-fades (0.2 s ease out).
/// - ``onReadyChange`` reports when it has drawn or failed, for a content gate to hold until then.
///
/// Decorative: callers label the element that contains it.
@MainActor
final class UKCachedImageView: UIView {
    var url: URL? { didSet { if url != oldValue { urlChanged() } } }
    var pipeline: ImagePipeline = .shared
    /// Called once when nothing loads (callers switch to a fallback URL).
    var onFailure: (() -> Void)?
    /// Whether the view has drawn an image or has nothing to wait for (`contentReadiness`).
    var onReadyChange: ((Bool) -> Void)?
    /// Drawn when there is no URL or nothing loads. While loading the frame stays empty.
    var placeholder: UIView? {
        didSet {
            oldValue?.removeFromSuperview()
            if let placeholder { addSubview(placeholder) }
            updatePlaceholder()
            setNeedsLayout()
        }
    }

    private let imageView = UIImageView()
    private var loadTask: Task<Void, Never>?
    private var shownKey: String?
    private var failed = false
    private var pixelSize = 0
    private var isReady = false { didSet { if isReady != oldValue { onReadyChange?(isReady) } } }

    init(url: URL? = nil, contentMode: UIView.ContentMode = .scaleAspectFill) {
        self.url = url
        super.init(frame: .zero)
        imageView.contentMode = contentMode
        imageView.clipsToBounds = true
        imageView.isAccessibilityElement = false
        isAccessibilityElement = false
        clipsToBounds = true
        addSubview(imageView)
        showMemoryImage()
        updateReady()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit { MainActor.assumeIsolated { loadTask?.cancel() } }

    private func showMemoryImage() {
        if let url, let cached = pipeline.memoryImage(for: url) {
            imageView.image = UIImage(cgImage: cached, scale: traitCollection.displayScale, orientation: .up)
            shownKey = ImagePipeline.key(for: url)
        }
    }

    private func urlChanged() {
        failed = false
        if url == nil {
            imageView.image = nil
            shownKey = nil
        } else if shownKey == nil || shownKey != url.map(ImagePipeline.key(for:)) {
            // A different URL: the previous image stays until the next decodes.
            if let url, let cached = pipeline.memoryImage(for: url) {
                imageView.image = UIImage(cgImage: cached, scale: traitCollection.displayScale, orientation: .up)
                shownKey = ImagePipeline.key(for: url)
            }
        }
        updatePlaceholder()
        startLoading()
        updateReady()
    }

    private func updatePlaceholder() {
        placeholder?.isHidden = !(url == nil || failed) || imageView.image != nil
    }

    private func updateReady() {
        isReady = url == nil || imageView.image != nil || failed
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = bounds
        placeholder?.frame = bounds
        let scale = traitCollection.displayScale
        let bucket = ImagePipeline.bucket(Int(max(bounds.width, bounds.height) * scale))
        if bucket != pixelSize {
            pixelSize = bucket
            startLoading()
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { startLoading() } else { loadTask?.cancel(); loadTask = nil }
    }

    private func startLoading() {
        loadTask?.cancel()
        loadTask = nil
        guard window != nil, pixelSize > 0, let url else { return }
        let pixels = pixelSize
        loadTask = Task { @MainActor [weak self, pipeline] in
            var yielded = false
            for await next in pipeline.images(for: url, maxPixel: pixels) {
                guard let self, !Task.isCancelled else { return }
                yielded = true
                show(UIImage(cgImage: next, scale: traitCollection.displayScale, orientation: .up), key: ImagePipeline.key(for: url))
            }
            guard let self, !Task.isCancelled else { return }
            if !yielded {
                failed = true
                updatePlaceholder()
                updateReady()
                onFailure?()
            }
        }
    }

    /// A first image fades in; a replacement for a different URL cross-fades; a same-size refresh of the image already shown swaps
    /// without animation.
    private func show(_ image: UIImage, key: String) {
        let fades = key != shownKey && window != nil
        failed = false
        shownKey = key
        if fades {
            UIView.transition(with: imageView, duration: UKMotion.quickDuration, options: [.transitionCrossDissolve, .curveEaseOut, .allowUserInteraction]) {
                self.imageView.image = image
            }
        } else {
            imageView.image = image
        }
        updatePlaceholder()
        updateReady()
    }
}

/// A cached remote image that tries a fallback URL, then a symbol, and never shows a broken image (`RemoteImage`). No fill of its
/// own: the card's surface shows through behind the placeholder. Decorative and never a touch target.
@MainActor
final class UKRemoteImageView: UIView {
    private let cached = UKCachedImageView()
    private let placeholderView = UIImageView()
    private var useFallback = false
    private(set) var url: URL?
    private(set) var fallbackURL: URL?
    private(set) var placeholderSymbol: String

    /// Whether the picture has drawn or failed, for a content gate.
    var onReadyChange: ((Bool) -> Void)? {
        get { cached.onReadyChange }
        set { cached.onReadyChange = newValue }
    }

    init(url: URL?, fallbackURL: URL? = nil, placeholderSymbol: String = "photo") {
        self.url = url
        self.fallbackURL = fallbackURL
        self.placeholderSymbol = placeholderSymbol
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        clipsToBounds = true
        placeholderView.contentMode = .center
        placeholderView.tintColor = UKInk.secondary
        cached.placeholder = placeholderView
        cached.onFailure = { [weak self] in
            guard let self, !useFallback, fallbackURL != nil else { return }
            useFallback = true
            apply()
        }
        addSubview(cached)
        ukOnContentSizeChange { [weak self] in
            guard let self else { return }
            placeholderView.image = UKFont.symbol(placeholderSymbol, style: .largeTitle, traits: traitCollection)
        }
        apply()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Shows another picture.
    func configure(url: URL?, fallbackURL: URL? = nil, placeholderSymbol: String = "photo") {
        guard url != self.url || fallbackURL != self.fallbackURL || placeholderSymbol != self.placeholderSymbol else { return }
        self.url = url
        self.fallbackURL = fallbackURL
        self.placeholderSymbol = placeholderSymbol
        useFallback = false
        placeholderView.image = UKFont.symbol(placeholderSymbol, style: .largeTitle, traits: traitCollection)
        apply()
    }

    private var current: URL? {
        if useFallback || url == nil { return fallbackURL == url ? nil : fallbackURL }
        return url
    }

    private func apply() { cached.url = current }

    override func layoutSubviews() {
        super.layoutSubviews()
        cached.frame = bounds
    }
}

/// A tappable card with a remote image, a title and an optional subtitle (`ImageCard`, pattern: `.agents/patterns/image-card.md`):
/// recipes on the Food hub carousel and the Recipes grid.
///
/// Direction G (mockups n6): the photo fills a 22 pt card and the caption sits on it in white over a bottom scrim, as in Photos and
/// Music. At accessibility text sizes the card is a row with a small thumbnail on a module instead.
///
/// The card is one accessibility element, framed to the whole card (the tap target).
@MainActor
final class UKImageCardView: UIControl, UKGridMeasuring {
    // MARK: Inputs

    private(set) var title: String
    private(set) var subtitle: String?
    private let hint: String
    private let image: UKRemoteImageView
    var action: (() -> Void)?
    /// The card is the one open beside a split (the Recipes grid): a 3 pt outline in the action ink and the selected trait.
    var isSelectionShown = false {
        didSet {
            guard isSelectionShown != oldValue else { return }
            layer.borderWidth = isSelectionShown ? 3 : 0
            layer.borderColor = UKDesignInk.action.resolvedColor(with: traitCollection).cgColor
            refresh()
        }
    }

    // MARK: Parts

    private let module = UIView()
    private let scrim = CAGradientLayer()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private var observers: UKObserverTokens?

    /// The card's corner radius (direction G, Controls: 22 pt, as tiles). Callers drawing a selection outline use it.
    static let cornerRadius = ImageCard.cornerRadius
    /// Width over height of the photo card.
    static let aspectRatio = ImageCard.aspectRatio

    init(title: String, subtitle: String? = nil, imageURL: URL?, fallbackImageURL: URL? = nil, placeholderSymbol: String = "photo",
         accessibilityHint: String = "", action: (() -> Void)? = nil) {
        self.title = title
        self.subtitle = subtitle
        hint = accessibilityHint
        self.action = action
        image = UKRemoteImageView(url: imageURL, fallbackURL: fallbackImageURL, placeholderSymbol: placeholderSymbol)
        super.init(frame: .zero)
        layer.cornerRadius = Self.cornerRadius
        layer.cornerCurve = .continuous
        layer.masksToBounds = !UKPerfSwitches.isOff(.ukCardClip)
        module.backgroundColor = UKInk.moduleThin
        module.isUserInteractionEnabled = false
        scrim.colors = ImageCard.scrimStops.map { UIColor.black.withAlphaComponent($0.opacity).cgColor }
        scrim.locations = ImageCard.scrimStops.map { NSNumber(value: $0.location) }
        scrim.startPoint = CGPoint(x: 0.5, y: 0)
        scrim.endPoint = CGPoint(x: 0.5, y: 1)
        titleLabel.numberOfLines = 3
        subtitleLabel.numberOfLines = 0
        for label in [titleLabel, subtitleLabel] { label.isAccessibilityElement = false }
        addSubview(module)
        addSubview(image)
        layer.addSublayer(scrim)
        addSubview(titleLabel)
        addSubview(subtitleLabel)
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
        ukOnContentSizeChange { [weak self] in self?.refresh() }
        observers = NotificationCenter.default.ukObserveAccessibility { [weak self] in self?.refresh() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Shows another recipe.
    func configure(title: String, subtitle: String?, imageURL: URL?, fallbackImageURL: URL? = nil, placeholderSymbol: String = "photo") {
        self.title = title
        self.subtitle = subtitle
        image.configure(url: imageURL, fallbackURL: fallbackImageURL, placeholderSymbol: placeholderSymbol)
        refresh()
    }

    @objc private func tapped() { action?() }

    private var isRow: Bool { traitCollection.ukIsAccessibilitySize }

    private static let captionShadow: NSShadow = {
        let shadow = NSShadow()
        shadow.shadowColor = UIColor.black.withAlphaComponent(0.6)
        shadow.shadowBlurRadius = 3
        shadow.shadowOffset = CGSize(width: 0, height: 1)
        return shadow
    }()

    private static func setText(_ label: UILabel, _ text: String?, shadowed: Bool) {
        guard let text else { label.attributedText = nil; label.text = nil; return }
        if shadowed, !UKPerfSwitches.isOff(.ukLabelShadow) {
            label.attributedText = NSAttributedString(string: text, attributes: [
                .font: label.font as Any, .foregroundColor: label.textColor as Any, .shadow: captionShadow])
        } else {
            label.attributedText = nil
            label.text = text
        }
    }

    private func refresh() {
        let onPhoto = !isRow
        titleLabel.font = UKFont.rowTitle(traitCollection)
        titleLabel.textColor = onPhoto ? .white : UKInk.primary
        titleLabel.numberOfLines = ImageCard.titleLineLimit(accessibilitySize: isRow)
        subtitleLabel.font = UKFont.preferred(.footnote, monospacedDigit: true, traits: traitCollection)
        subtitleLabel.isHidden = subtitle == nil
        subtitleLabel.textColor = onPhoto ? UIColor.white.withAlphaComponent(0.86) : UIColor(HassTokens.RGB.Surface.secondaryOnModule)
        // The caption's shadow is drawn into the text (`NSShadow`), not a layer shadow: a layer shadow of a label has no path, so the
        // render server blurred every caption offscreen on every scrolled frame (3185 against 1982 ms over an 8 s Recipes scroll).
        Self.setText(titleLabel, title, shadowed: onPhoto)
        Self.setText(subtitleLabel, subtitle, shadowed: onPhoto)
        scrim.isHidden = !onPhoto
        module.isHidden = false
        // A card with no size yet (an off-screen carousel page) offers no target; layout switches it on.
        isAccessibilityElement = bounds.width > 1 && bounds.height > 1
        accessibilityLabel = title
        accessibilityValue = subtitle ?? ""
        accessibilityHint = hint
        accessibilityTraits = isSelectionShown ? [.button, .selected] : .button
        setNeedsLayout()
        invalidateIntrinsicContentSize()
    }

    // MARK: Layout

    private struct Frames {
        var height: CGFloat
        var image: CGRect
        var title: CGRect
        var subtitle: CGRect
        var caption: CGRect
    }

    private func frames(width: CGFloat, height fixed: CGFloat? = nil) -> Frames {
        func size(_ label: UILabel, _ width: CGFloat) -> CGSize {
            guard label.text?.isEmpty == false else { return .zero }
            return label.sizeThatFits(CGSize(width: max(width, 1), height: CGFloat.greatestFiniteMagnitude))
        }
        if isRow {
            let pad = HassTokens.Spacing.m
            let side = ImageCard.thumbnailSide
            let textWidth = max(1, width - 2 * pad - side - HassTokens.Spacing.m)
            let titleSize = size(titleLabel, textWidth)
            let subtitleSize = size(subtitleLabel, textWidth)
            let textHeight = ceil(titleSize.height) + (subtitle == nil ? 0 : 1 + ceil(subtitleSize.height))
            let height = pad * 2 + max(side, textHeight)
            let x = pad + side + HassTokens.Spacing.m
            return Frames(height: height, image: CGRect(x: pad, y: pad, width: side, height: side),
                          title: CGRect(x: x, y: pad, width: textWidth, height: ceil(titleSize.height)),
                          subtitle: CGRect(x: x, y: pad + ceil(titleSize.height) + 1, width: textWidth, height: ceil(subtitleSize.height)),
                          caption: CGRect(x: 0, y: 0, width: width, height: height))
        }
        let height = fixed ?? width / Self.aspectRatio
        let textWidth = max(1, width - 24)
        let titleSize = size(titleLabel, textWidth)
        let subtitleSize = size(subtitleLabel, textWidth)
        let subtitleHeight = subtitle == nil ? 0 : ceil(subtitleSize.height)
        // The caption stands 10 pt above the foot and 12 pt in from the sides.
        let captionHeight = ceil(titleSize.height) + (subtitle == nil ? 0 : 1 + subtitleHeight)
        let captionTop = height - 10 - captionHeight
        let titleFrame = CGRect(x: 12, y: captionTop, width: textWidth, height: ceil(titleSize.height))
        let subtitleFrame = CGRect(x: 12, y: titleFrame.maxY + 1, width: textWidth, height: subtitleHeight)
        return Frames(height: height, image: CGRect(x: 0, y: 0, width: width, height: height), title: titleFrame, subtitle: subtitleFrame,
                      caption: CGRect(x: 12, y: captionTop, width: textWidth, height: captionHeight))
    }

    func gridHeight(forWidth width: CGFloat) -> CGFloat { frames(width: width).height }
    override func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: size.width, height: frames(width: size.width).height) }
    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: frames(width: max(bounds.width, 1)).height) }

    override func layoutSubviews() {
        super.layoutSubviews()
        // A card that has no size yet (not laid out, or clipped to nothing) offers no target to assistive technologies.
        isAccessibilityElement = bounds.width > 1 && bounds.height > 1
        let frames = frames(width: bounds.width, height: isRow ? nil : bounds.height)
        module.frame = bounds
        image.frame = frames.image
        image.layer.cornerRadius = isRow ? HassTokens.Radius.chip : 0
        image.layer.cornerCurve = .continuous
        titleLabel.frame = frames.title
        subtitleLabel.frame = frames.subtitle
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        scrim.frame = bounds
        CATransaction.commit()
        // The module under a row card is its own card.
        module.isHidden = false
    }

    override var isHighlighted: Bool {
        didSet { if isHighlighted != oldValue { alpha = isHighlighted ? 0.8 : 1 } }
    }

    // The card's accessibility frame is the whole card, as in the SwiftUI card (the Food hub audit read the text of two cards as
    // inaccessible when the element covered only the estimated caption frame: round 6 bisect, whole card = 0 issues).
}
#endif
