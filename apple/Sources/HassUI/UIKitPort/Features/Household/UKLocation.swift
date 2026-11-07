#if os(iOS)
import HassCore
import HassDesign
import UIKit

// MARK: - Status row

/// "Location Access" and its value in an inset cell (`LocationStatusRow`): the Setup flow's status row (``UKSetupStatusRow``) with
/// the permission's words and colour.
@MainActor
final class UKLocationStatusRow: UKSetupStatusRow {
    init() {
        super.init(label: "Location Access", value: "", identifier: "location.status")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Shows the permission: Off reads red and Approximate amber; the words carry the meaning too.
    func update(_ permission: LocationPermission) {
        let color: UIColor
        switch permission.stage {
        case .denied: color = UKDesignInk.danger
        case .reducedAccuracy: color = UKDesignInk.warning
        case .notDetermined, .whenInUse, .always: color = UKDesignInk.secondary
        }
        setValue(LocationPermissionCopy.status(permission), color: color)
    }
}

// MARK: - Screen

/// Explains location reporting and walks through the permission steps (`LocationPermissionView`,
/// `.agents/pages/settings/location.md`): not asked, While Using, Always, with Settings as the way back from Off or Approximate.
///
/// HIG: Privacy (pre-alert screens: one button titled "Continue", no other way out) and Sheets. The asking stages drop Direction
/// G's Close and can't be swiped away, because HIG's pre-alert rule wins over the modal pattern; the status stages (Always, Off,
/// Approximate) keep Close.
@MainActor
final class UKLocationPermissionViewController: UKPageViewController, UKSheetFitting {
    var permission: LocationPermission { didSet { if permission != oldValue { apply() } } }
    var canAskForAlways: Bool { didSet { if canAskForAlways != oldValue { apply() } } }
    private let onRequestPermission: () -> Void
    private let onOpenSettings: (() -> Void)?
    private let onClose: () -> Void
    private let isPushed: Bool
    private let footer: UIView?
    private let sheetTitle: String

    private let container = UKColumnContainer(
        spacing: HassTokens.Spacing.xl,
        margins: NSDirectionalEdgeInsets(top: HassTokens.Spacing.l, leading: HassTokens.Spacing.xl, bottom: HassTokens.Spacing.l, trailing: HassTokens.Spacing.xl),
        maxWidth: 560, clearsHinge: true)
    private let symbolView = UIImageView()
    private let titleLabel = UILabel.uk(.title2, weight: .bold, ink: UKDesignInk.primary)
    private let messageLabel = UILabel.uk(.body, ink: UKDesignInk.secondary)
    private let statusRow = UKLocationStatusRow()
    private let pointsStack = UIStackView.ukColumn(spacing: HassTokens.Spacing.l)
    private let footnoteLabel = UILabel.uk(.footnote, ink: UKDesignInk.secondary)
    private var primaryButton: UKPrimaryButton?
    private let actionBar = UIStackView.ukColumn(spacing: HassTokens.Spacing.s)
    private var closeItem: UIBarButtonItem?
    /// Bindings that live as long as the screen.
    var bindings: [AnyObject] = []

    var sheetFitScrollView: UIScrollView? { container.scrollView }

    /// - Parameters:
    ///   - permission: The current permission; the screen follows it as it changes.
    ///   - canAskForAlways: Whether iOS will still show the Always alert (it shows it once); when not, While Using offers Settings and Close.
    ///   - onRequestPermission: Shows the next system alert.
    ///   - onOpenSettings: Opens Settings; nil opens the app's Settings page.
    ///   - onClose: Dismisses the screen (the whole sheet when pushed).
    ///   - isPushed: The screen is a page pushed inside another sheet's navigation stack (Your Summary's Share Location), not a sheet
    ///     of its own: it keeps the system Back, can be left by Back even before the first prompt, and follows the sheet's appearance.
    ///   - sheetTitle: The navigation title; "Location Settings" everywhere (Setup step, Your Summary, gallery).
    ///   - footer: Content under the action (the debug gallery's last-action line), inside the scroll content.
    init(permission: LocationPermission, canAskForAlways: Bool = true, onRequestPermission: @escaping () -> Void,
         onOpenSettings: (() -> Void)? = nil, onClose: @escaping () -> Void, isPushed: Bool = false, sheetTitle: String = "Location Settings", footer: UIView? = nil) {
        self.sheetTitle = sheetTitle
        self.permission = permission
        self.canAskForAlways = canAskForAlways
        self.onRequestPermission = onRequestPermission
        self.onOpenSettings = onOpenSettings
        self.onClose = onClose
        self.isPushed = isPushed
        self.footer = footer
        super.init(sheetTitle: sheetTitle)
        // Sheets are dark in Direction G v1, as the signed-in shell's are; set here too so the screen stays dark wherever it is
        // presented from. A pushed page follows the sheet it is in.
        if !isPushed { overrideUserInterfaceStyle = .dark }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private var copy: LocationPermissionCopy { LocationPermissionCopy(stage: permission.stage, canAskForAlways: canAskForAlways) }

    override func viewDidLoad() {
        super.viewDidLoad()
        install(scrollView: container.scrollView)

        symbolView.isAccessibilityElement = false
        symbolView.contentMode = .scaleAspectFit
        symbolView.setContentHuggingPriority(.required, for: .vertical)
        titleLabel.accessibilityTraits = [.header, .staticText]
        titleLabel.accessibilityIdentifier = "location.title"
        messageLabel.accessibilityIdentifier = "location.message"
        footnoteLabel.accessibilityIdentifier = "location.footnote"
        let heading = UIStackView.ukColumn([symbolView, titleLabel, messageLabel], spacing: HassTokens.Spacing.m)
        heading.alignment = .leading
        for label in [titleLabel, messageLabel] { label.setContentHuggingPriority(.defaultLow, for: .horizontal) }
        for point in LocationPermissionCopy.points(for: .current) { pointsStack.addArrangedSubview(UKSetupPointRow(point: point, identifier: "location.point")) }
        if let footer { actionBar.addArrangedSubview(footer) }
        [heading, statusRow, pointsStack, footnoteLabel, actionBar].forEach(container.column.addArrangedSubview)
        // Text sizes: the symbol follows the title's largest style.
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (page: UKLocationPermissionViewController, _) in page.updateSymbol() }
        apply()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        applyDismissal()
    }

    private func updateSymbol() {
        let symbol: String
        let colour: UIColor
        switch permission.stage {
        case .notDetermined, .whenInUse: symbol = "location.circle.fill"; colour = UKDesignInk.action
        case .always: symbol = "location.fill"; colour = UKDesignInk.action
        case .denied: symbol = "location.slash.fill"; colour = UKDesignInk.danger
        case .reducedAccuracy: symbol = "scope"; colour = UKDesignInk.warning
        }
        let size = UKScaled.value(56, relativeTo: .largeTitle, traits: traitCollection)
        symbolView.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: size))
        symbolView.tintColor = colour
    }

    private func apply() {
        guard isViewLoaded else { return }
        let copy = copy
        updateSymbol()
        titleLabel.text = copy.title
        messageLabel.text = copy.message
        statusRow.update(permission)
        pointsStack.isHidden = !copy.showsPoints
        footnoteLabel.text = copy.footnote
        footnoteLabel.isHidden = copy.footnote == nil
        primaryButton?.removeFromSuperview()
        primaryButton = nil
        if let actionTitle = copy.actionTitle {
            let action = copy.action
            let button = UKPrimaryButton(actionTitle) { [weak self] in self?.perform(action) }
            button.accessibilityIdentifier = "location.primary"
            actionBar.insertArrangedSubview(button, at: 0)
            primaryButton = button
        }
        // The first-run prompt has no Close: it asks first. A pushed page keeps its Close (the whole sheet) beside Back.
        if isPushed || !copy.isPreAlert {
            if closeItem == nil { closeItem = UKSheetItems.close(identifier: "location.close") { [weak self] in self?.onClose() } }
            navigationItem.rightBarButtonItem = closeItem
        } else {
            navigationItem.rightBarButtonItem = nil
        }
        applyDismissal()
    }

    private func applyDismissal() {
        let blocks = !isPushed && copy.isPreAlert
        (navigationController ?? self).isModalInPresentation = blocks
        isModalInPresentation = blocks
    }

    private func perform(_ action: LocationPermissionCopy.Action?) {
        switch action {
        case .requestPermission: onRequestPermission()
        case .openSettings: openSettings()
        case nil: break
        }
    }

    private func openSettings() {
        if let onOpenSettings { return onOpenSettings() }
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }
}

// MARK: - Coordinator

/// ``UKLocationPermissionViewController`` for a ``LocationCoordinator`` (`LocationPermissionSheet`): the after-sign-in offer
/// presents it as a sheet, and Your Summary's Share Location row pushes it inside the summary's own stack (`isPushed`), so no
/// sheet is stacked on another.
@MainActor
enum UKLocationPermission {
    static func make(location: LocationCoordinator, onClose: @escaping () -> Void, isPushed: Bool = false,
                     sheetTitle: String = "Location Settings") -> UIViewController {
        let page = UKLocationPermissionViewController(
            permission: location.reporter.permission, canAskForAlways: !location.hasAskedForAlways,
            onRequestPermission: { location.requestPermission() }, onClose: onClose, isPushed: isPushed, sheetTitle: sheetTitle)
        let bag = UKObservationBag()
        bag.observe { [weak page] in
            page?.permission = location.reporter.permission
            page?.canAskForAlways = !location.hasAskedForAlways
        }
        page.bindings.append(bag)
        return page
    }
}

// MARK: - Account section

/// The Summary sheet's Profile-tab Location section (`LocationAccountSection`): Share Location with the permission state, which
/// opens the permission screen, and why this iPhone isn't on its person yet, if it isn't.
@MainActor
final class UKLocationAccountSection: UIView {
    private let location: LocationCoordinator
    private let row = UKGroupedRowButton(title: "Share Location", symbol: "location.fill", identifier: "account.location")
    private let warning = UKErrorSlot()
    private let linkNotice = UKErrorSlot()
    private let bag = UKObservationBag()

    /// What reporting does, under the row: an iPad reports to its own device and is never added to a person.
    private static func footer(_ location: LocationCoordinator) -> String {
        location.linksPresence ? LocationAccountSection.footer : LocationAccountSection.footerWithoutPerson
    }

    /// - Parameter show: Opens the permission screen.
    init(location: LocationCoordinator, show: @escaping () -> Void) {
        self.location = location
        super.init(frame: .zero)
        row.onTap = show
        row.hint = "Shows location access for this \(location.linksPresence ? "iPhone" : "iPad")."
        let header = UKFormText.header("Location", style: .subheadline)
        header.font = .ukFont(.subheadline, weight: .semibold)
        // The warning sits under the card, above what reporting does, so the card keeps its corners.
        let footerLabel = UKFormText.footer(Self.footer(location))
        let warnings = UIStackView.ukColumn([warning, linkNotice, footerLabel], spacing: HassTokens.Spacing.s)
        let section = UKGroupedSection(header: header, rows: [row], footer: warnings)
        addSubview(section)
        section.ukPin(to: self)
        bag.observe { [weak self] in
            guard let self else { return }
            let permission = location.reporter.permission
            let status = LocationPermissionCopy.status(permission)
            self.row.value = status
            self.row.refresh()
            self.warning.showWarning(LocationAccountSection.warning(stage: permission.stage), identifier: "account.location.warning")
            self.linkNotice.showWarning(LocationAccountSection.linkNotice(location.mobileAppPresenceLink), identifier: "account.location.link")
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

extension UKErrorSlot {
    /// An inline warning (`InlineAlert`) under a card: empty and hidden until there is a message.
    func showWarning(_ message: String?, identifier: String) {
        show(message, severity: .warning, identifier: identifier)
    }
}
#endif
