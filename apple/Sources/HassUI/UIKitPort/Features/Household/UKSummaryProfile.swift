#if os(iOS)
import HassCore
import HassDesign
import UIKit

// MARK: - Account header

/// The signed-in person at the top of the Profile tab, centred as in Apple's account sheets: a large monogram, their name and
/// the server they are signed in to (`AccountHeader`).
@MainActor
final class UKAccountHeaderView: UIView {
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
    }

    /// Draws the signed-in person's photo on the disc while they have one (`AccountHeader.avatar`).
    func bindAvatar(_ box: @escaping @MainActor () -> AvatarBox?) { photo.bind(box) }

    func update(name: String?, server: String) {
        let initials = ProfileButton.initials(name)
        avatar.text = initials
        avatar.isHidden = initials == nil
        avatarFallback.isHidden = initials != nil
        nameLabel.text = name ?? "Signed In"
        serverLabel.text = server
        accessibilityLabel = [name ?? "Signed In", server].joined(separator: ", ")
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

/// The Summary sheet's Profile tab: the app's own extras. Who is signed in and to which server, who is home, Location on phones,
/// and Sign Out behind the sheet's alert (`ProfileTab`).
@MainActor
final class UKProfileTabViewController: UKPaneViewController {
    private let context: UKContext
    private let bag = UKObservationBag()
    private let container = UKColumnContainer(spacing: HassTokens.Spacing.xl, padding: HassTokens.Spacing.l, maxWidth: nil)
    private let header = UKAccountHeaderView()
    private let peopleSlot = UIStackView.ukColumn(spacing: 0)
    private let signOutRow = UKSignOutRow(identifier: "account.signOut")
    private let groups = UIStackView.ukColumn(spacing: HassTokens.Spacing.xl)
    private var personIds: [String]
    private var peopleSignature = ""
    private let confirmSignOut: () -> Void
    private let showLocation: () -> Void
    private let serverLine: String

    var sheetFitScrollView: UIScrollView? { container.scrollView }

    /// The people's photos; nil (a gallery without them) draws every monogram.
    private var avatars: PersonAvatars? { context.avatars ?? context.session?.avatars }

    /// A confirmed sign-out is waiting on the server: the Sign Out row shows the arc and the rest of the tab is off.
    var isSigningOut = false { didSet { applySigningOut() } }

    init(context: UKContext, confirmSignOut: @escaping () -> Void, showLocation: @escaping () -> Void) {
        self.context = context
        self.confirmSignOut = confirmSignOut
        self.showLocation = showLocation
        // The person ids are read once when the sheet opens: people rarely come and go, and the section then observes their states.
        personIds = context.store.allValues.keys.filter { $0.hasPrefix("person.") }.sorted()
        serverLine = context.connection.map { HomeAssistantSettingsView.displayedServer($0.server, redacting: ScreenshotPrivacy.isRedacting) } ?? "Home Assistant"
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        let scroll = container.scrollView
        scroll.accessibilityIdentifier = "account.list"
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        scroll.ukPin(to: view)

        header.bindAvatar { [weak self] in self?.avatars?.viewerBox }
        groups.addArrangedSubview(header)
        groups.addArrangedSubview(peopleSlot)
        if let location = context.location {
            groups.addArrangedSubview(UKLocationAccountSection(location: location) { [weak self] in self?.showLocation() })
        }
        signOutRow.onTap = { [weak self] in self?.confirmSignOut() }
        let signOut = UKGroupedSection(header: nil, rows: [signOutRow], footer: nil)
        container.column.addArrangedSubview(groups)
        container.column.addArrangedSubview(signOut)

        bag.observe { [weak self] in
            guard let self else { return }
            self.header.update(name: self.context.navigator?.profileName, server: self.serverLine)
        }
        bag.observe { [weak self] in self?.refreshPeople() }
    }

    private func refreshPeople() {
        let people = ProfileSummary.people(personIds.compactMap { context.store.entity($0).state })
        let signature = people.map { "\($0.id)|\($0.name)|\($0.state)" }.joined(separator: ";")
        guard signature != peopleSignature else { return }
        peopleSignature = signature
        peopleSlot.arrangedSubviews.forEach { $0.removeFromSuperview() }
        peopleSlot.isHidden = people.isEmpty
        guard !people.isEmpty else { return }
        let title = UKFormText.header("People at Home", style: .subheadline)
        title.font = .ukFont(.subheadline, weight: .semibold)
        title.accessibilityIdentifier = "profile.people"
        // Explicit ink: the plain footer measured 3.3:1 in the Account sheet's audit.
        let footer = UILabel.uk(.footnote, ink: UKDesignSurface.secondaryInSheet)
        footer.text = ProfileSummary.homeSummary(people)
        peopleSlot.addArrangedSubview(UKGroupedSection(header: title, rows: people.map { UKPersonRow(person: $0, avatar: avatars?.box(for: $0.id)) }, footer: footer))
    }

    private func applySigningOut() {
        guard isViewLoaded else { return }
        signOutRow.update(isSigningOut: isSigningOut)
        groups.isUserInteractionEnabled = !isSigningOut
        groups.alpha = isSigningOut ? CGFloat(HassTokens.ControlState.disabledOpacity) : 1
    }
}

extension UKProfileTabViewController: UKSheetFitting {}
#endif
