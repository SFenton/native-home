#if os(iOS)
import HassCore
import HassDesign
import UIKit

/// A person's photo on a disc, drawn over their initials disc (`AvatarView`'s photo layer), with the 0.5 pt hairline that keeps a
/// dark photo from dissolving into a dark ground. Bound to an ``AvatarBox``: a photo present at the first frame is simply there; a
/// changed one cross-fades (`MotionTokens.state`, 0.2 s under Reduce Motion). Decorative: hidden from VoiceOver.
///
/// TODO(uikit-port): a stand-in until the tiles lane's `UKAvatarView` (the `HassDesign/Avatar` port) lands; swap the callers then.
@MainActor
final class UKProfilePhotoView: UIView {
    private let photo = UIImageView()
    private let ring = UIView()
    private var shown: AvatarImage.Identity?
    private var hasRun = false
    private let bag = UKObservationBag()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        photo.contentMode = .scaleAspectFill
        photo.clipsToBounds = true
        photo.alpha = 0
        ring.layer.borderColor = UIColor.white.withAlphaComponent(0.28).cgColor
        ring.alpha = 0
        for view in [photo, ring] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
            view.ukPin(to: self)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Draws `box`'s photo while it has one; `box` is read inside an observation.
    func bind(_ box: @escaping @MainActor () -> AvatarBox?) {
        bag.removeAll()
        bag.observe { [weak self] in
            guard let self else { return }
            let image = box()?.avatarImage
            self.show(image, animated: self.hasRun && self.window != nil)
            self.hasRun = true
        }
    }

    private func show(_ image: AvatarImage?, animated: Bool) {
        guard image?.identity != shown else { return }
        shown = image?.identity
        let apply = {
            self.photo.image = image.map { UIImage(cgImage: $0.cgImage) }
            self.photo.alpha = image == nil ? 0 : 1
            self.ring.alpha = image == nil ? 0 : 1
        }
        guard animated else { return apply() }
        let duration = UIAccessibility.isReduceMotionEnabled ? 0.2 : MotionTokens.stateDuration
        UIView.transition(with: self, duration: duration, options: [.transitionCrossDissolve, .allowUserInteraction], animations: apply)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let radius = min(bounds.width, bounds.height) / 2
        photo.layer.cornerRadius = radius
        ring.layer.cornerRadius = radius
        ring.layer.borderWidth = traitCollection.accessibilityContrast == .high ? 1 : 0.5
    }
}
#endif
