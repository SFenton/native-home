#if os(iOS)
import HassDesign
import UIKit

/// A person's avatar (`AvatarView`, pattern: `.agents/patterns/avatar.md`): their photo on a disc, or their initials when there is none.
///
/// The initials disc is always underneath, so removing a photo fades onto it and adding one fades over it. A changed photo cross-fades with
/// ``MotionTokens/state`` (0.6 s, 0.2 s under Reduce Motion) through ``AvatarFade``: the new photo fades in over the old one and the old one
/// is then dropped, never through the initials. A view created with a photo draws it on its first frame with no animation; a fade plays only
/// when the photo changes while the view is on screen.
///
/// The view is decorative (hidden from accessibility): the name is read by the button or row that holds it. A 0.5 pt hairline outlines the
/// photo (white 28% in dark, black 18% in light; stronger and 1 pt with Increase Contrast) so a dark photo does not dissolve into a dark bar.
@MainActor
final class UKAvatarView: UIView {
    private var initials: String?
    private var fill: UIColor
    private var image: AvatarImage?
    private let diameter: CGFloat
    private let font: UIFont?
    private let placeholderSymbol: String
    private var fade: AvatarFade

    private let disc = UIView()
    private let initialsLabel = UILabel()
    private let placeholder = UIImageView()
    private let baseView = UIImageView()
    private let topView = UIImageView()
    private let hairline = UIView()

    /// - Parameters:
    ///   - initials: Up to two letters for the disc; nil or empty draws `placeholderSymbol`.
    ///   - fill: The initials disc's colour.
    ///   - image: The person's photo, nil for none.
    ///   - diameter: The disc's size in points.
    ///   - font: The initials' font; nil is semibold at 40% of the diameter.
    init(initials: String?, fill: UIColor, image: AvatarImage?, diameter: CGFloat, font: UIFont? = nil, placeholderSymbol: String = "person.fill") {
        self.initials = initials
        self.fill = fill
        self.image = image
        self.diameter = diameter
        self.font = font
        self.placeholderSymbol = placeholderSymbol
        fade = AvatarFade(image: image)
        super.init(frame: CGRect(x: 0, y: 0, width: diameter, height: diameter))
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        clipsToBounds = true
        layer.cornerRadius = diameter / 2
        layer.cornerCurve = .continuous
        initialsLabel.textColor = .white
        initialsLabel.textAlignment = .center
        initialsLabel.adjustsFontSizeToFitWidth = true
        initialsLabel.minimumScaleFactor = 0.5
        placeholder.contentMode = .center
        placeholder.tintColor = .white
        for photo in [baseView, topView] {
            photo.contentMode = .scaleAspectFill
            photo.clipsToBounds = true
        }
        hairline.isUserInteractionEnabled = false
        hairline.layer.cornerRadius = diameter / 2
        hairline.layer.cornerCurve = .continuous
        disc.addSubview(initialsLabel)
        disc.addSubview(placeholder)
        for view in [disc, baseView, topView, hairline] { addSubview(view) }
        registerForTraitChanges([UITraitUserInterfaceStyle.self, UITraitAccessibilityContrast.self]) { (view: UKAvatarView, _) in view.syncHairline() }
        configureDisc()
        syncLayers()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var intrinsicContentSize: CGSize { CGSize(width: diameter, height: diameter) }
    override func sizeThatFits(_ size: CGSize) -> CGSize { intrinsicContentSize }

    // MARK: Update

    /// Shows another person or photo. A changed photo fades while the view is on screen; a view not yet on screen takes it at once.
    func update(initials: String?, fill: UIColor, image: AvatarImage?) {
        self.initials = initials
        self.fill = fill
        configureDisc()
        let changed = image?.identity != self.image?.identity
        self.image = image
        if changed, window == nil {
            fade = AvatarFade(image: image)
            syncLayers()
        } else if changed {
            advance()
        }
    }

    private func configureDisc() {
        disc.backgroundColor = fill
        let hasInitials = !(initials ?? "").isEmpty
        initialsLabel.text = initials
        initialsLabel.font = font ?? UIFont.systemFont(ofSize: diameter * 0.4, weight: .semibold)
        initialsLabel.isHidden = !hasInitials
        placeholder.isHidden = hasInitials
        placeholder.image = UIImage(systemName: placeholderSymbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: diameter * 0.4))
    }

    // MARK: Fade

    private func advance() {
        guard fade.begin(to: image) else { return }
        syncLayers()
        reveal()
    }

    private func reveal() {
        let epoch = fade.epoch
        let duration = UKMotion.stateDuration
        // The incoming layer must exist at opacity 0 for one frame, or it would appear already at 1.
        NextFrame.perform { [weak self] in
            guard let self else { return }
            fade.reveal()
            UIView.animate(withDuration: duration, delay: 0, options: [.curveEaseInOut, .allowUserInteraction]) { [self] in
                topView.alpha = CGFloat(fade.topOpacity)
                hairline.alpha = CGFloat(fade.hairlineOpacity)
            } completion: { [weak self] _ in
                guard let self else { return }
                if fade.finish(epoch: epoch) {
                    syncLayers()
                    reveal()
                } else {
                    syncLayers()
                }
            }
        }
    }

    /// Places the layers for the fade's state, without animation.
    private func syncLayers() {
        UIView.performWithoutAnimation {
            disc.isHidden = fade.discHidden
            if let base = fade.base {
                baseView.image = UIImage(cgImage: base.cgImage)
                baseView.isHidden = false
            } else {
                baseView.image = nil
                baseView.isHidden = true
            }
            if let top = fade.top {
                topView.image = UIImage(cgImage: top.cgImage)
                topView.isHidden = false
            } else {
                topView.image = nil
                topView.isHidden = true
            }
            topView.alpha = CGFloat(fade.topOpacity)
            hairline.alpha = CGFloat(fade.hairlineOpacity)
            syncHairline()
        }
    }

    /// White 28% in dark, black 18% in light; Increase Contrast makes both stronger (and the line 1 pt).
    private func syncHairline() {
        let strong = traitCollection.accessibilityContrast == .high
        let dark = traitCollection.userInterfaceStyle != .light
        hairline.layer.borderWidth = strong ? 1 : 0.5
        hairline.layer.borderColor = (dark ? UIColor.white.withAlphaComponent(strong ? 0.6 : 0.28)
                                      : UIColor.black.withAlphaComponent(strong ? 0.45 : 0.18)).cgColor
    }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        for view in [disc, baseView, topView, hairline] { view.frame = bounds }
        initialsLabel.frame = bounds.insetBy(dx: diameter * 0.1, dy: 0)
        placeholder.frame = bounds
    }
}
#endif
