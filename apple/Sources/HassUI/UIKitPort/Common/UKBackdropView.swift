#if os(iOS)
import HassCore
import HassDesign
import UIKit

/// The wallpaper behind a page, the UIKit counterpart of ``HouseBackdrop``: the blurred house photo (rendered once for the
/// window by ``HouseBackdropStore``) under a dark scrim, over the base colour. Full-bleed, never hit-testable, hidden from
/// assistive technologies.
///
/// - The window has exactly one (the shell's, or the gallery host's), behind the tab controller, filling the window: pages are
///   transparent, so it does not move while a page slides in or out of a push, a pop or a split. Nothing tracks a page's position
///   (`.agents/design/single-page-motion.md` S1; this view used to be per page, with a display link holding the photo still).
/// - After a sign-in the photo fades in from 1.06 to 1 as the sign-in layer lifts away (``HomeArrival``); Reduce Motion
///   cross-fades without the scale.
/// - Reduce Transparency and the `backdrop` perf switch draw the plain base.
final class UKBackdropView: UIView {
    private let store: HouseBackdropStore?
    private let shell: UKShellEnvironment?
    /// Everything that is drawn, so the arrival's scale never touches this view's own frame (laying out a transformed view
    /// by `frame`, which autoresizing does, would shrink its bounds by the scale).
    private let inner = UIView()
    private let imageView = UIImageView()
    private let scrim = CAGradientLayer()
    private let scrimHost = UIView()
    private let bag = UKObservationBag()
    private var shownImage: CGImage?
    private var lastArrived: Bool?

    /// The base colour under the photo (`HouseBackdropStyle.base`).
    static let base = UIColor(red: 17 / 255, green: 23 / 255, blue: 35 / 255, alpha: 1)

    init(store: HouseBackdropStore?, shell: UKShellEnvironment?) {
        self.store = store
        self.shell = shell
        super.init(frame: .zero)
        backgroundColor = Self.base
        clipsToBounds = true
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.minificationFilter = .trilinear
        addSubview(inner)
        inner.addSubview(imageView)
        scrimHost.isUserInteractionEnabled = false
        scrimHost.layer.addSublayer(scrim)
        scrim.startPoint = CGPoint(x: 0.5, y: 0)
        scrim.endPoint = CGPoint(x: 0.5, y: 1)
        inner.addSubview(scrimHost)
        imageView.isHidden = true
        scrimHost.isHidden = true
        bind()
        registerForTraitChanges([UITraitAccessibilityContrast.self]) { (view: UKBackdropView, _) in view.applyScrim() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: Binding

    private func bind() {
        bag.observe { [weak self] in
            guard let self else { return }
            let image = self.store?.image
            let reduceTransparency = self.shell?.reduceTransparency ?? UIAccessibility.isReduceTransparencyEnabled
            let canvas = self.shell?.canvas ?? .zero
            self.showsPhoto(image, drawn: !reduceTransparency && !PerfSwitches.isOff(.backdrop), canvas: canvas)
        }
        bag.observe { [weak self] in
            guard let self else { return }
            let arrived = self.shell?.arrival?.isRevealed ?? true
            let reduceMotion = self.shell?.reduceMotion ?? UIAccessibility.isReduceMotionEnabled
            self.arrive(arrived, reduceMotion: reduceMotion)
        }
    }

    private var canvasSize: CGSize = .zero

    private func showsPhoto(_ image: CGImage?, drawn: Bool, canvas: CGSize) {
        canvasSize = canvas
        let visible = image != nil && drawn
        if visible, let image {
            let isNew = shownImage !== image
            if isNew {
                let uiImage = UIImage(cgImage: image, scale: 1, orientation: .up)
                // The photo cross-fades in when it first arrives or is re-rendered (`motionSafeAnimation(standard / quick)`).
                if shownImage != nil || !imageView.isHidden, window != nil {
                    let duration = (shell?.reduceMotion ?? UIAccessibility.isReduceMotionEnabled) ? MotionTokens.quickDuration : MotionTokens.standardDuration
                    UIView.transition(with: imageView, duration: duration, options: [.transitionCrossDissolve, .allowUserInteraction]) {
                        self.imageView.image = uiImage
                    }
                } else {
                    imageView.image = uiImage
                }
                shownImage = image
            }
        } else {
            shownImage = nil
            imageView.image = nil
        }
        imageView.isHidden = !visible
        scrimHost.isHidden = !visible
        applyScrim()
        setNeedsLayout()
    }

    /// The scrim's stops, one colour per ``HouseBackdropStyle/scrimOpacities``, with the Increase Contrast boost.
    private func applyScrim() {
        let boost = traitCollection.accessibilityContrast == .high ? HouseBackdropStyle.increasedContrastBoost : 0
        scrim.colors = HouseBackdropStyle.scrimOpacities.map { UIColor.black.withAlphaComponent($0.value + boost).cgColor }
        scrim.locations = HouseBackdropStyle.scrimOpacities.map { NSNumber(value: $0.location) }
    }

    private func arrive(_ arrived: Bool, reduceMotion: Bool) {
        defer { lastArrived = arrived }
        let hiddenScale = reduceMotion ? 1 : MotionTokens.Arrival.backdropScale
        guard let last = lastArrived else {
            inner.alpha = arrived ? 1 : 0
            inner.transform = arrived ? .identity : CGAffineTransform(scaleX: hiddenScale, y: hiddenScale)
            return
        }
        guard last != arrived else { return }
        if arrived {
            // `MotionTokens.Arrival.backdrop` (easeOut 0.6 s) or the cross-fade (easeInOut 0.35 s).
            let options: UIView.AnimationOptions = reduceMotion ? .curveEaseInOut : .curveEaseOut
            UIView.animate(withDuration: reduceMotion ? MotionTokens.crossFadeDuration : 0.6, delay: 0, options: [options, .allowUserInteraction]) {
                self.inner.alpha = 1
                self.inner.transform = .identity
            }
        } else {
            inner.alpha = 0
            inner.transform = CGAffineTransform(scaleX: hiddenScale, y: hiddenScale)
        }
    }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutPhoto()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        layoutPhoto()
    }

    private func layoutPhoto() {
        inner.bounds = CGRect(origin: .zero, size: bounds.size)
        inner.center = CGPoint(x: bounds.midX, y: bounds.midY)
        let canvas = canvasSize == .zero ? bounds.size : canvasSize
        imageView.frame = CGRect(origin: .zero, size: canvas)
        scrimHost.frame = CGRect(origin: .zero, size: canvas)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        scrim.frame = scrimHost.bounds
        CATransaction.commit()
    }
}
#endif
