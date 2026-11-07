#if os(iOS)
import HassCore
import HassDesign
import UIKit

/// The profile button at the top trailing edge of every page: the signed-in user's initials on a 44 pt disc that is the whole
/// button, or a person symbol until the name is known; badged with the attention count ("9+" past nine) and, with no network
/// path, a small `icloud.slash`. The UIKit counterpart of ``ProfileButton`` and its ``ProfileButton/Metrics``.
///
/// A custom bar-item view: the container is not an accessibility element so the button and the offline badge are reachable
/// separately (`nav.profile`, `nav.offline`).
final class UKProfileButtonView: UIView {
    private let button = UIControl()
    private let ring = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
    private let disc = UIView()
    private let initialsLabel = UILabel()
    private let symbol = UIImageView()
    // TODO(uikit-port): replace the photo layer below with UKAvatarView when the tiles lane's `HassDesign/Avatar` port lands.
    private let photo = UIImageView()
    private let photoRing = UIView()
    private var shownPhoto: AvatarImage.Identity?
    private let avatarBag = UKObservationBag()
    private let badge = UILabel()
    /// On iOS 26 the bar tints a custom view's subviews, so the count badge is drawn once into an `.alwaysOriginal` image and shown here.
    private let badgeImage = UIImageView()
    private var renderedBadge: (text: String?, size: CGSize, fontSize: CGFloat)?
    private let offline = UIImageView()
    private let offlineDisc = UIView()
    var onTap: () -> Void = {}
    private lazy var widthConstraint = widthAnchor.constraint(equalToConstant: HassTokens.minTarget)
    private lazy var heightConstraint = heightAnchor.constraint(equalToConstant: HassTokens.minTarget)

    /// The view's side: 44 pt, or 36 pt where the bar draws its own glass around it (iOS 26, the person symbol), since the bar adds
    /// 4 pt of padding each side and the circle must come out 44 pt (`ProfileButton`'s symbol on the system glass).
    var side: CGFloat = HassTokens.minTarget {
        didSet {
            guard side != oldValue else { return }
            widthConstraint.constant = side
            heightConstraint.constant = side
            setNeedsLayout()
        }
    }

    private(set) var name: String?
    private(set) var attentionCount = 0
    private(set) var isOffline = false
    private(set) var grouped = false
    private let metrics = ProfileButton.Metrics.resolve(liquidGlassBar: UKGlassEra.hasGlass)

    /// The monogram's fill (the light-mode action blue, 5.6:1 under white).
    private static let fill = UIColor(red: 0.0, green: 0.40, blue: 0.80, alpha: 1)

    override init(frame: CGRect) {
        super.init(frame: CGRect(x: 0, y: 0, width: HassTokens.minTarget, height: HassTokens.minTarget))
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([widthConstraint, heightConstraint])
        isAccessibilityElement = false
        button.frame = bounds
        button.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        button.addAction(UIAction { [weak self] _ in self?.onTap() }, for: .touchUpInside)
        button.isAccessibilityElement = true
        button.accessibilityTraits = .button
        button.accessibilityLabel = "Profile"
        button.accessibilityHint = "Opens your summary and account"
        button.accessibilityIdentifier = "nav.profile"
        button.showsLargeContentViewer = true
        button.largeContentTitle = "Profile"
        button.largeContentImage = UIImage(systemName: "person.crop.circle")
        button.addInteraction(UILargeContentViewerInteraction())
        addSubview(button)

        if metrics.ringed {
            // Before iOS 26 the bar draws no glass: a 44 pt material circle shows behind the disc.
            ring.frame = bounds
            ring.layer.cornerRadius = bounds.width / 2
            ring.clipsToBounds = true
            ring.isUserInteractionEnabled = false
            addSubview(ring)
        }
        disc.isUserInteractionEnabled = false
        disc.backgroundColor = Self.fill
        addSubview(disc)
        initialsLabel.textColor = .white
        initialsLabel.textAlignment = .center
        initialsLabel.adjustsFontSizeToFitWidth = false
        disc.addSubview(initialsLabel)
        photo.contentMode = .scaleAspectFill
        photo.clipsToBounds = true
        photo.isUserInteractionEnabled = false
        photo.isAccessibilityElement = false
        photo.alpha = 0
        addSubview(photo)
        photoRing.isUserInteractionEnabled = false
        photoRing.layer.borderColor = UIColor.white.withAlphaComponent(0.28).cgColor
        photoRing.layer.borderWidth = 0.5
        photoRing.alpha = 0
        addSubview(photoRing)
        symbol.tintColor = .label
        symbol.contentMode = .center
        symbol.isUserInteractionEnabled = false
        addSubview(symbol)

        badge.textColor = .white
        badge.textAlignment = .center
        badge.backgroundColor = UIColor(rgb: HassTokens.Palette.badge)
        badge.layer.masksToBounds = true
        badge.isAccessibilityElement = false
        badge.isUserInteractionEnabled = false
        addSubview(badge)
        badgeImage.isAccessibilityElement = false
        badgeImage.isUserInteractionEnabled = false
        badgeImage.contentMode = .center
        addSubview(badgeImage)

        offlineDisc.backgroundColor = UIColor(white: 0.28, alpha: 1)
        offlineDisc.layer.borderColor = UIColor.white.withAlphaComponent(0.35).cgColor
        offlineDisc.layer.borderWidth = 0.5
        offlineDisc.isUserInteractionEnabled = false
        offlineDisc.isAccessibilityElement = false  // folded into the button value ("..., Offline"); an 18 pt disc alone fails the hit-area audit
        offlineDisc.accessibilityLabel = "Offline"
        offlineDisc.accessibilityIdentifier = "nav.offline"
        offline.tintColor = .white
        offline.contentMode = .center
        offlineDisc.addSubview(offline)
        addSubview(offlineDisc)
        accessibilityElements = [button]
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: UKProfileButtonView, _) in
            view.restyle()
            view.setNeedsLayout()
        }
        restyle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Draws the signed-in person's photo on the monogram's disc while they have one; it never changes the presentation, which
    /// follows the name (`ProfileButton.avatar`). A changed photo cross-fades (`MotionTokens.state`, 0.2 s under Reduce Motion); one
    /// present at the first frame is simply there.
    /// - Parameter box: Reads the box (and so tracks it); nil for none.
    func bindAvatar(_ box: @escaping @MainActor () -> AvatarBox?) {
        avatarBag.removeAll()
        avatarBag.observe { [weak self] in
            guard let self else { return }
            let box = box()
            let image = box?.avatarImage
            self.showPhoto(image, animated: self.window != nil && self.shownPhotoSet)
            self.shownPhotoSet = true
        }
    }

    private var shownPhotoSet = false

    private func showPhoto(_ image: AvatarImage?, animated: Bool) {
        guard image?.identity != shownPhoto else { return }
        shownPhoto = image?.identity
        let apply = {
            self.photo.image = image.map { UIImage(cgImage: $0.cgImage) }
            self.photo.alpha = image == nil ? 0 : 1
            self.photoRing.alpha = image == nil ? 0 : 1
            // The initials disc is hidden once a photo is settled, so a transparent photo shows the bar, not the monogram.
            self.disc.alpha = image == nil ? 1 : 0
        }
        guard animated else { return apply() }
        let duration = UIAccessibility.isReduceMotionEnabled ? 0.2 : MotionTokens.stateDuration
        if image != nil { disc.alpha = 1 }
        UIView.transition(with: self, duration: duration, options: [.transitionCrossDissolve, .allowUserInteraction], animations: apply)
    }

    /// Shows a state; the badge changes fade (`quick`).
    func configure(name: String?, attentionCount: Int, isOffline: Bool, grouped: Bool, animated: Bool) {
        let badgeChanged = ProfileSummary.badgeText(attentionCount) != ProfileSummary.badgeText(self.attentionCount)
        self.name = name
        self.attentionCount = attentionCount
        self.isOffline = isOffline
        self.grouped = grouped
        button.accessibilityValue = ProfileButton.accessibilityValue(name: name, attentionCount: attentionCount, isOffline: isOffline)
        let update = {
            self.restyle()
            self.setNeedsLayout()
            self.layoutIfNeeded()
        }
        if animated, badgeChanged {
            UIView.transition(with: self, duration: MotionTokens.quickDuration, options: [.transitionCrossDissolve, .allowUserInteraction], animations: update)
        } else {
            update()
        }
    }

    /// The text of both badges grows with Dynamic Type up to xLarge (``ProfileButton/badgeTypeRange``), the cap the initials follow.
    private func cappedTraits() -> UITraitCollection {
        UITraitCollection(preferredContentSizeCategory: ProfileButton.badgeContentSize(traitCollection.preferredContentSizeCategory))
    }

    private func restyle() {
        let presentation = grouped ? ProfileButton.Presentation.symbol : ProfileButton.Presentation.resolve(name: name)
        switch presentation {
        case let .monogram(initials):
            disc.isHidden = false
            photo.isHidden = false
            photoRing.isHidden = false
            symbol.isHidden = true
            initialsLabel.text = initials
            // 16 pt semibold at the default size; a bar item keeps its size past xLarge (the Large Content Viewer shows it bigger).
            let category = traitCollection.preferredContentSizeCategory
            let capped = category > .extraLarge ? UIContentSizeCategory.extraLarge : category
            initialsLabel.font = UKShellFont.preferred(.callout, weight: .semibold, traits: UITraitCollection(preferredContentSizeCategory: capped))
        case .symbol:
            disc.isHidden = true
            photo.isHidden = true
            photoRing.isHidden = true
            symbol.isHidden = false
            symbol.image = UIImage(systemName: "person.crop.circle", withConfiguration: UIImage.SymbolConfiguration(font: UKShellFont.preferred(.title3)))
        }
        let text = ProfileSummary.badgeText(attentionCount)
        // On iOS 26 the bar draws a custom view through its foreground treatment, so the badge is drawn into an image (below); the
        // label itself stays hidden and only styles it. Earlier bars show the label.
        badge.isHidden = UKGlassEra.hasGlass || text == nil
        badgeImage.isHidden = !UKGlassEra.hasGlass || text == nil
        button.largeContentTitle = text.map { "Profile, \($0)" } ?? "Profile"
        badge.text = text
        badge.font = UKShellFont.preferred(.caption1, weight: .bold, traits: cappedTraits())
        offlineDisc.isHidden = !isOffline
        offline.image = UIImage(systemName: "icloud.slash", withConfiguration: UIImage.SymbolConfiguration(font: UKShellFont.preferred(.caption2, weight: .bold, traits: cappedTraits())))
    }

    /// The disc's frame in this view's coordinates, once laid out (tests compare the badge against it).
    var discFrame: CGRect { disc.frame }

    /// The frame of the badge the person sees: the image on iOS 26, the label before; empty with no count.
    var shownBadgeFrame: CGRect {
        if !badgeImage.isHidden { return badgeImage.frame }
        return badge.isHidden ? .zero : badge.frame
    }

    /// Whether VoiceOver can reach the badge (it must not: the count is in the button's value).
    var badgeIsAccessible: Bool { badge.isAccessibilityElement || badgeImage.isAccessibilityElement }

    /// Draws the badge label into an original-rendering image so the bar's tint cannot turn it white.
    private func renderBadgeImage() {
        badgeImage.frame = badge.frame
        let key = (text: badge.text, size: badge.frame.size, fontSize: badge.font.pointSize)
        if let rendered = renderedBadge, rendered == key { return }
        renderedBadge = key
        guard badge.text != nil, badge.frame.width > 0 else { badgeImage.image = nil; return }
        let size = badge.frame.size
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            let bounds = CGRect(origin: .zero, size: size)
            UIColor(rgb: HassTokens.Palette.badge).setFill()
            UIBezierPath(roundedRect: bounds, cornerRadius: bounds.height / 2).fill()
            let text = NSAttributedString(string: badge.text ?? "", attributes: [.font: badge.font as Any, .foregroundColor: UIColor.white])
            let textSize = text.size()
            text.draw(at: CGPoint(x: (bounds.width - textSize.width) / 2, y: (bounds.height - textSize.height) / 2))
        }
        badgeImage.image = image.withRenderingMode(.alwaysOriginal)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let diameter = metrics.diameter
        disc.frame = CGRect(x: (bounds.width - diameter) / 2, y: (bounds.height - diameter) / 2, width: diameter, height: diameter)
        disc.layer.cornerRadius = diameter / 2
        initialsLabel.frame = disc.bounds
        photo.frame = disc.frame
        photo.layer.cornerRadius = diameter / 2
        photoRing.frame = disc.frame
        photoRing.layer.cornerRadius = diameter / 2
        photoRing.layer.borderWidth = traitCollection.accessibilityContrast == .high ? 1 : 0.5
        symbol.frame = bounds
        // The attention badge: top trailing, its trailing edge 4 pt past the disc, 2 pt above it.
        // Sized like the system badge: 4 pt taller than the line, 18 pt at least, 7 pt wider than the text, never narrower than tall.
        let textWidth = badge.sizeThatFits(.zero).width
        let height = max(18, (badge.font.lineHeight + 4).rounded())
        let width = max(height, ceil(textWidth) + 7)
        badge.frame = CGRect(x: disc.frame.maxX + 4 - width, y: disc.frame.minY - 2, width: width, height: height)
        badge.layer.cornerRadius = height / 2
        if UKGlassEra.hasGlass { renderBadgeImage() }
        // The offline badge: bottom trailing, scaled with its glyph (`.caption2`) so the glyph stays inside it.
        let offlineDiameter = UKShellFont.scaled(18, relativeTo: .caption2, traits: cappedTraits())
        offlineDisc.frame = CGRect(x: disc.frame.maxX - 2 - offlineDiameter, y: disc.frame.maxY + 1 - offlineDiameter,
                                   width: offlineDiameter, height: offlineDiameter)
        offlineDisc.layer.cornerRadius = offlineDiameter / 2
        offline.frame = offlineDisc.bounds
    }
}
#endif
