#if os(iOS)
import HassCore
import HassDesign
import UIKit

// MARK: - Account header

/// The signed-in person at the top of the Profile tab, centred as in Apple's account sheets: a large monogram, their name and
/// the server they are signed in to (`AccountHeader`).
@MainActor
final class UKAccountHeaderView: UIView, UKGridMeasuring {
    private let avatar = UILabel()
    private let avatarFallback = UIImageView()
    private let avatarHolder = UIView()
    private let photo = UKProfilePhotoView()
    private let nameLabel = UILabel.uk(.title2, weight: .bold, ink: UKDesignInk.primary, alignment: .center)
    private let serverLabel = UILabel.uk(.subheadline, ink: UKDesignInk.secondary, alignment: .center)
    private var avatarSize: NSLayoutConstraint!
    private var initialsText: String?

    init() {
        super.init(frame: .zero)
        avatarHolder.backgroundColor = UKDesignInk.actionFill
        avatarHolder.translatesAutoresizingMaskIntoConstraints = false
        avatar.textColor = .white
        avatar.textAlignment = .center
        avatar.adjustsFontSizeToFitWidth = true
        avatar.minimumScaleFactor = 0.5
        avatar.translatesAutoresizingMaskIntoConstraints = false
        avatarFallback.tintColor = .white
        avatarFallback.contentMode = .center
        avatarFallback.translatesAutoresizingMaskIntoConstraints = false
        avatarHolder.addSubview(avatar)
        avatarHolder.addSubview(avatarFallback)
        avatarHolder.isAccessibilityElement = false
        photo.translatesAutoresizingMaskIntoConstraints = false
        avatarHolder.addSubview(photo)
        photo.ukPin(to: avatarHolder)
        avatarSize = avatarHolder.widthAnchor.constraint(equalToConstant: 84)
        NSLayoutConstraint.activate([
            avatarSize, avatarHolder.heightAnchor.constraint(equalTo: avatarHolder.widthAnchor),
            avatar.centerXAnchor.constraint(equalTo: avatarHolder.centerXAnchor), avatar.centerYAnchor.constraint(equalTo: avatarHolder.centerYAnchor),
            avatar.leadingAnchor.constraint(greaterThanOrEqualTo: avatarHolder.leadingAnchor, constant: 4),
            avatarFallback.centerXAnchor.constraint(equalTo: avatarHolder.centerXAnchor), avatarFallback.centerYAnchor.constraint(equalTo: avatarHolder.centerYAnchor),
        ])
        let column = UIStackView(arrangedSubviews: [avatarHolder, nameLabel, serverLabel])
        column.axis = .vertical
        column.alignment = .center
        column.spacing = HassTokens.Spacing.s
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)
        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: topAnchor, constant: HassTokens.Spacing.s),
            column.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -HassTokens.Spacing.s),
            column.leadingAnchor.constraint(equalTo: leadingAnchor), column.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        nameLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        serverLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        isAccessibilityElement = true
        accessibilityIdentifier = "account.header"
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: UKAccountHeaderView, _) in view.rescale() }
        rescale()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func rescale() {
        let size = UKScaled.value(84, relativeTo: .largeTitle, traits: traitCollection)
        avatarSize.constant = size
        avatarHolder.layer.cornerRadius = size / 2
        avatar.font = .systemFont(ofSize: size * 0.4, weight: .semibold)
        avatarFallback.image = UIImage(systemName: "person.fill", withConfiguration: UIImage.SymbolConfiguration(font: .ukFont(.largeTitle)))
        ukRemeasureContainers()
    }

    func gridHeight(forWidth width: CGFloat) -> CGFloat {
        ceil(systemLayoutSizeFitting(CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
                                     withHorizontalFittingPriority: .required,
                                     verticalFittingPriority: .fittingSizeLevel).height)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        CGSize(width: size.width, height: gridHeight(forWidth: size.width))
    }

    /// Draws the signed-in person's photo on the disc while they have one (`AccountHeader.avatar`).
    func bindAvatar(_ box: @escaping @MainActor () -> AvatarBox?) { photo.bind(box) }

    func update(name: String?, server: String, fallbackName: String = "Signed In") {
        let initials = ProfileButton.initials(name)
        avatar.text = initials
        avatar.isHidden = initials == nil
        avatarFallback.isHidden = initials != nil
        nameLabel.text = name ?? fallbackName
        serverLabel.text = server
        accessibilityLabel = [name ?? fallbackName, server].filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

// MARK: - Person row

/// One person: a monogram in their colour, their name and Home, Away or the zone (`PersonRow`).
@MainActor
final class UKPersonRow: UKRowView {
    /// - Parameter avatar: The person's photo from Home Assistant; nil draws their initials.
    init(person: ProfileSummary.Person, avatar: AvatarBox? = nil) {
        var content = UKRowContent(person.name, value: person.stateText)
        content.leadingView = UKMonogramAvatar(person: person, avatar: avatar)
        content.valueInk = person.isHome ? UKDesignInk.success : UKDesignSurface.secondaryInSheet
        content.minHeight = HassTokens.minTarget
        content.verticalPadding = HassTokens.Spacing.xs
        content.identifier = "profile.person.\(person.id)"
        // `PersonRow` combines name and state into one element: "Alex Morgan, Home".
        content.spokenLabel = "\(person.name), \(person.stateText)"
        content.spokenValue = ""
        spokenName = "\(person.name), \(person.stateText)"
        identifier = "profile.person.\(person.id)"
        super.init(content, surface: .sheet)
    }

    private let spokenName: String
    private let identifier: String

    // The whole row is the element (a 44 pt frame, not the text block's), as `PersonRow`'s combined element is.
    override var isAccessibilityElement: Bool { get { true } set {} }
    override var accessibilityElements: [Any]? { get { nil } set {} }
    override var accessibilityLabel: String? { get { spokenName } set {} }
    override var accessibilityValue: String? { get { nil } set {} }
    override var accessibilityIdentifier: String? { get { identifier } set {} }
    override var accessibilityTraits: UIAccessibilityTraits { get { .staticText } set {} }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

/// A person's circle: their photo, or their initials on their colour, scaled with the body text.
@MainActor
final class UKMonogramAvatar: UIView {
    private var size: NSLayoutConstraint!
    private let monogram = UILabel()

    init(person: ProfileSummary.Person, avatar: AvatarBox?) {
        super.init(frame: CGRect(x: 0, y: 0, width: 36, height: 36))
        monogram.text = ProfileButton.initials(person.name) ?? "?"
        monogram.textColor = .white
        monogram.textAlignment = .center
        monogram.adjustsFontSizeToFitWidth = true
        monogram.minimumScaleFactor = 0.5
        monogram.isAccessibilityElement = false
        backgroundColor = UIColor(PersonRow.fillToken(for: person))
        isAccessibilityElement = false
        clipsToBounds = true
        monogram.translatesAutoresizingMaskIntoConstraints = false
        addSubview(monogram)
        size = widthAnchor.constraint(equalToConstant: 36)
        NSLayoutConstraint.activate([
            size, heightAnchor.constraint(equalTo: widthAnchor),
            monogram.centerXAnchor.constraint(equalTo: centerXAnchor), monogram.centerYAnchor.constraint(equalTo: centerYAnchor),
            monogram.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 2),
        ])
        if let avatar {
            let photo = UKProfilePhotoView()
            photo.translatesAutoresizingMaskIntoConstraints = false
            addSubview(photo)
            photo.ukPin(to: self)
            photo.bind { avatar }
        }
        // The monogram scales with the body text, and its initials with it.
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: UKMonogramAvatar, _) in view.rescale() }
        rescale()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func rescale() {
        let scaled = UKScaled.value(36, relativeTo: .body, traits: traitCollection)
        size.constant = scaled
        layer.cornerRadius = scaled / 2
        monogram.font = .systemFont(ofSize: scaled * 0.4, weight: .semibold)
    }
}

// MARK: - Profile tab

#endif
