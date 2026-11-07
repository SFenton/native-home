#if os(iOS)
import HassCore
import HassDesign
import UIKit

/// The shell's trailing header items, Quick Links then Profile, with the reconnecting arc before them while the connection
/// is retrying: the UIKit counterpart of ``ShellHeaderItems`` (owner, 2026-10-18, option A; HIG Toolbars "Item groupings").
///
/// On iOS 26 the bar draws each item's glass circle itself and a fixed space separates the circles, so the bar never merges
/// them into one capsule; in the Duo's vertical bar (owner, 2026-10-20) both share one glass group and no space is added
/// (``ShellHeaderGrouping``). Before iOS 26 the bar draws no glass, so each button draws its own material circle.
@MainActor
final class UKShellHeaderItems {
    /// Quick Links, then Profile; the arc before them while present.
    private(set) var quickLinks: UIBarButtonItem
    /// The bar item's count badge: caption1 bold at the person's text size, capped at xLarge
    /// (``ProfileButton/badgeTypeRange``), the rule the drawn badge of the earlier bars follows (`UKProfileButtonView`).
    @available(iOS 26.0, *)
    static func badge(_ text: String?, category: UIContentSizeCategory) -> UIBarButtonItem.Badge? {
        guard let text else { return nil }
        var badge = UIBarButtonItem.Badge.string(text)
        badge.font = badgeFont(category: category)
        return badge
    }

    /// Caption1 bold for `category`, held at ``ProfileButton/badgeTypeRange``'s upper bound (xLarge).
    static func badgeFont(category: UIContentSizeCategory) -> UIFont {
        UKShellFont.preferred(.caption1, weight: .bold, traits: UITraitCollection(preferredContentSizeCategory: ProfileButton.badgeContentSize(category)))
    }

    private let profileView = UKProfileButtonView()
    private let profileItem: UIBarButtonItem
    /// Profile in the Duo's vertical bar: a plain symbol item, since the system moves only standard items into the rail and a
    /// custom view stays in the horizontal header (`ProfileButton.grouped`).
    private let railProfileItem: UIBarButtonItem
    private let arcView = UKReconnectingArcView()
    private let arcItem: UIBarButtonItem
    private let openQuickLinks: () -> Void
    private let openAccount: () -> Void
    private var last: State?
    private let railBag = UKObservationBag()
    private var railPhoto: AvatarImage?
    private var railRendered: (name: String?, photo: AvatarImage.Identity?)?

    /// What the items show.
    struct State: Equatable {
        var profileName: String?
        var attentionCount = 0
        var isOffline = false
        var reconnectingPresent = false
        var reconnectingLit = false
        var isFirstConnect = false
        var inVerticalBar = false
        /// The person's text size, which the count badge follows (``badgeFont(category:)``).
        var contentSize: UIContentSizeCategory = .large
    }

    init(openQuickLinks: @escaping () -> Void, openAccount: @escaping () -> Void) {
        self.openQuickLinks = openQuickLinks
        self.openAccount = openAccount
        quickLinks = UKShellHeaderItems.makeQuickLinks(action: openQuickLinks)
        profileItem = UIBarButtonItem(customView: profileView)
        arcItem = UIBarButtonItem(customView: arcView)
        profileView.onTap = openAccount
        railProfileItem = UIBarButtonItem(primaryAction: UIAction(title: Self.profileMenuTitle,
                                                                  image: UIImage(systemName: "person.crop.circle",
                                                                                 withConfiguration: UIImage.SymbolConfiguration(font: UKShellFont.preferred(.title3)))) { _ in openAccount() })
        // The bar shows the glyph; the title names the item when the bar folds it into its "…" menu (and in Large Content).
        railProfileItem.title = Self.profileMenuTitle
        // The title carries the count (below) for the Large Content Viewer, so the "…" menu has its own text: the sheet's name, as the header item's.
        railProfileItem.menuRepresentation = UIAction(title: Self.profileMenuTitle, image: UIImage(systemName: "person.crop.circle")) { _ in openAccount() }
        railProfileItem.accessibilityLabel = "Profile"
        railProfileItem.accessibilityHint = "Opens your summary and account"
        railProfileItem.accessibilityIdentifier = "nav.profile"
        railProfileItem.largeContentSizeImage = UIImage(systemName: "person.crop.circle")
        // A custom view has no title of its own for the bar's "…" menu: these stand in for it there.
        profileItem.title = Self.profileMenuTitle
        profileItem.menuRepresentation = UIAction(title: Self.profileMenuTitle, image: UIImage(systemName: "person.crop.circle")) { _ in openAccount() }
        arcItem.title = ReconnectingArc.label
        arcItem.menuRepresentation = UIAction(title: ReconnectingArc.label, image: UIImage(systemName: "arrow.triangle.2.circlepath"),
                                              attributes: .disabled) { _ in }
        if #available(iOS 26.0, *) {
            profileItem.hidesSharedBackground = true
            arcItem.hidesSharedBackground = true
        }
    }

    /// What the Profile button is called in the bar's "…" menu: the sheet it opens (owner, 2026-11-01). VoiceOver keeps "Profile".
    static let profileMenuTitle = "Your Summary"

    private static func makeQuickLinks(action: @escaping () -> Void) -> UIBarButtonItem {
        // A plain image: on iOS 26 the bar draws the 44 pt glass circle. Before iOS 26 the circle is a material one.
        let symbol = UIImage(systemName: "square.grid.2x2", withConfiguration: UIImage.SymbolConfiguration(font: UKShellFont.preferred(.body, weight: .medium)))
        let item: UIBarButtonItem
        if UKGlassEra.hasGlass, #available(iOS 26.0, *) {
            item = UIBarButtonItem(primaryAction: UIAction(title: QuickLinks.title, image: symbol) { _ in action() })
        } else {
            let view = UKMaterialCircleButton(image: symbol)
            view.onTap = action
            item = UIBarButtonItem(customView: view)
            item.menuRepresentation = UIAction(title: QuickLinks.title, image: UIImage(systemName: "square.grid.2x2")) { _ in action() }
        }
        // The bar shows the glyph; the title names it in the bar's "…" menu.
        item.title = QuickLinks.title
        item.accessibilityLabel = QuickLinks.title
        item.accessibilityIdentifier = "quickLinks.open"
        item.largeContentSizeImage = UIImage(systemName: "square.grid.2x2")
        return item
    }

    /// Draws the signed-in person's photo on the Profile button (nil: initials); `box` is read inside an observation.
    func bindAvatar(_ box: @escaping @MainActor () -> AvatarBox?) {
        profileView.bindAvatar(box)
        // The rail's item shows the same photo, drawn into an image (below).
        railBag.removeAll()
        railBag.observe { [weak self] in
            guard let self else { return }
            let photo = box()?.avatarImage
            self.railPhoto = photo
            self.refreshRailImage(name: self.last?.profileName)
        }
    }

    /// The rail's Profile image: the person's photo or monogram as a template-free image, since the bar tints a template image to
    /// one colour and draws a custom view through its foreground treatment. The person symbol stays until a name or photo is known.
    private func refreshRailImage(name: String?) {
        let key = (name: name, photo: railPhoto?.identity)
        if let rendered = railRendered, rendered.name == key.name, rendered.photo == key.photo { return }
        railRendered = key
        let diameter: CGFloat = 30
        if let photo = railPhoto {
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: diameter, height: diameter))
            let image = renderer.image { _ in
                let rect = CGRect(x: 0, y: 0, width: diameter, height: diameter)
                UIBezierPath(ovalIn: rect).addClip()
                let source = UIImage(cgImage: photo.cgImage)
                // Aspect fill.
                let scale = max(diameter / source.size.width, diameter / source.size.height)
                let size = CGSize(width: source.size.width * scale, height: source.size.height * scale)
                source.draw(in: CGRect(x: (diameter - size.width) / 2, y: (diameter - size.height) / 2, width: size.width, height: size.height))
            }
            railProfileItem.image = image.withRenderingMode(.alwaysOriginal)
        } else if case let .monogram(initials) = ProfileButton.Presentation.resolve(name: name) {
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: diameter, height: diameter))
            let image = renderer.image { _ in
                UIColor(red: 0.0, green: 0.40, blue: 0.80, alpha: 1).setFill()
                UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: diameter, height: diameter)).fill()
                let text = NSAttributedString(string: initials, attributes: [
                    .font: UIFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: UIColor.white])
                let size = text.size()
                text.draw(at: CGPoint(x: (diameter - size.width) / 2, y: (diameter - size.height) / 2))
            }
            railProfileItem.image = image.withRenderingMode(.alwaysOriginal)
        } else {
            railProfileItem.image = UIImage(systemName: "person.crop.circle",
                                            withConfiguration: UIImage.SymbolConfiguration(font: UKShellFont.preferred(.title3)))
        }
    }

    /// The state the items were last built for, so a text-size change can rebuild them.
    var lastState: State? { last }

    /// The items for `state`, trailing-most first (`UINavigationItem.rightBarButtonItems`' order).
    func items(for state: State) -> [UIBarButtonItem] {
        let animated = last != nil
        last = state
        let oneGroup = ShellHeaderGrouping.resolve(inVerticalBar: state.inVerticalBar) == .oneGroup
        profileView.configure(name: state.profileName, attentionCount: state.attentionCount, isOffline: state.isOffline,
                              grouped: oneGroup, animated: animated)
        arcView.configure(lit: state.reconnectingLit, isFirstConnect: state.isFirstConnect, besideQuickLinks: !oneGroup, animated: animated)
        if UKGlassEra.hasGlass, #available(iOS 26.0, *), oneGroup {
            // One glass group in the rail: Profile then Quick Links with no spacer; the arc stays in the horizontal header.
            railProfileItem.accessibilityValue = ProfileButton.accessibilityValue(name: state.profileName, attentionCount: state.attentionCount,
                                                                                 isOffline: state.isOffline)
            refreshRailImage(name: state.profileName)
            // The bar's Large Content Viewer shows an item's title, so the count rides on it (the "…" menu reads the same).
            railProfileItem.title = ProfileSummary.badgeText(state.attentionCount).map { "\(Self.profileMenuTitle), \($0)" } ?? Self.profileMenuTitle
            railProfileItem.badge = Self.badge(ProfileSummary.badgeText(state.attentionCount), category: state.contentSize)
            var result = [railProfileItem, quickLinks]
            if state.reconnectingPresent { result.append(arcItem) }
            return result
        }
        var result = [profileItem]
        if UKGlassEra.hasGlass, #available(iOS 26.0, *) {
            // The header's count is the view's own drawn badge (an original-rendering image on the disc's corner, `UKProfileButtonView`),
            // not the system badge: the bar tints a custom view's subviews, but not an `.alwaysOriginal` image, and it anchors its own
            // badge to the item's layout cell, which landed inside the photo.
            profileItem.badge = nil
        }
        if UKGlassEra.hasGlass, #available(iOS 26.0, *) {
            // The monogram has no ring of the bar's glass around it; the person symbol keeps the system glass like every other glyph
            // (`ProfileButton.Presentation.sharedBackground`).
            let isMonogram: Bool = { if case .monogram = ProfileButton.Presentation.resolve(name: state.profileName) { true } else { false } }()
            profileItem.hidesSharedBackground = isMonogram && !oneGroup
            profileView.side = !isMonogram && !oneGroup ? HassTokens.minTarget - 8 : HassTokens.minTarget
            if !oneGroup { result.append(UIBarButtonItem.fixedSpace(12)) }
            result.append(quickLinks)
            // The arc is a custom view: like the monogram it stays in the horizontal page header and never joins the rail.
            if state.reconnectingPresent {
                if !oneGroup { result.append(UIBarButtonItem.fixedSpace(12)) }
                result.append(arcItem)
            }
        } else {
            result.append(quickLinks)
            if state.reconnectingPresent { result.append(arcItem) }
        }
        return result
    }
}

/// The reconnecting arc as a bar item: a white arc that fades in and out (`crossFade`), shifted toward Quick Links so the
/// 12 pt gap matches the one between Quick Links and Profile (``ReconnectingArc/Metrics``).
final class UKReconnectingArcView: UIView {
    private let spinner = UKArcSpinnerView(.compact, label: ReconnectingArc.label, maxScale: ReconnectingArc.Metrics.maxScale)
    private var besideQuickLinks = true

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: ReconnectingArc.Metrics.cellWidth, height: HassTokens.minTarget))
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: ReconnectingArc.Metrics.cellWidth),
            heightAnchor.constraint(equalToConstant: HassTokens.minTarget),
        ])
        isAccessibilityElement = false
        spinner.color = .white
        spinner.accessibilityIdentifier = "reconnecting.arc"
        spinner.alpha = 0
        addSubview(spinner)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(lit: Bool, isFirstConnect: Bool, besideQuickLinks: Bool, animated: Bool) {
        self.besideQuickLinks = besideQuickLinks
        spinner.accessibilityLabel = isFirstConnect ? ReconnectingArc.connectingLabel : ReconnectingArc.label
        setNeedsLayout()
        let change = { self.spinner.alpha = lit ? 1 : 0 }
        if animated, window != nil {
            UIView.animate(withDuration: MotionTokens.crossFadeDuration, delay: 0, options: [.curveEaseInOut, .allowUserInteraction], animations: change)
        } else {
            change()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = spinner.intrinsicContentSize
        var x = (bounds.width - size.width) / 2
        if besideQuickLinks, UKGlassEra.hasGlass, #available(iOS 26.0, *) {
            x += ReconnectingArc.Metrics.trailingShift(scale: spinner.scale)
        }
        spinner.frame = CGRect(x: x, y: (bounds.height - size.height) / 2, width: size.width, height: size.height)
    }
}

/// A 44 pt material circle holding a glyph, for bars that draw no glass (before iOS 26): the neighbouring Quick Links and
/// Profile circles are the same size (``SwiftUICore/View/headerCircle()``).
final class UKMaterialCircleButton: UIControl {
    private let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
    private let glyph = UIImageView()
    var onTap: () -> Void = {}

    init(image: UIImage?) {
        super.init(frame: CGRect(x: 0, y: 0, width: HassTokens.minTarget, height: HassTokens.minTarget))
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: HassTokens.minTarget),
            heightAnchor.constraint(equalToConstant: HassTokens.minTarget),
        ])
        blur.frame = bounds
        blur.layer.cornerRadius = bounds.width / 2
        blur.clipsToBounds = true
        blur.isUserInteractionEnabled = false
        addSubview(blur)
        glyph.image = image
        glyph.tintColor = .label
        glyph.contentMode = .center
        glyph.frame = bounds
        glyph.isUserInteractionEnabled = false
        addSubview(glyph)
        addAction(UIAction { [weak self] _ in self?.onTap() }, for: .touchUpInside)
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}
#endif
