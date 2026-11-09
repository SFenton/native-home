#if os(iOS)
import HassCore
import HassDesign
import UIKit

// MARK: - Steps

/// Step 1 (`NotificationSetupStep`): explains door and camera alerts, then asks. A pre-alert screen: one Continue, no Close, no
/// swipe-down.
@MainActor
final class UKNotificationSetupStepViewController: UKSetupStepPageViewController {
    private let setup: SetupCoordinator

    init(setup: SetupCoordinator) {
        self.setup = setup
        let primary = UKPrimaryButton(NotificationPermissionCopy.stepAction) { Task { await setup.continueNotifications() } }
        primary.accessibilityIdentifier = "setup.notifications.primary"
        super.init(barTitle: SetupStep.notifications.barTitle, content: UKSetupStepContent(
            symbol: "bell.badge.fill", title: NotificationPermissionCopy.title, message: NotificationPermissionCopy.message,
            footnote: NotificationPermissionCopy.stepFootnote, identifier: "setup.notifications", actions: [primary]))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        (navigationController ?? self).isModalInPresentation = true
    }
}

/// Step 2 (`TimeSensitiveSetupStep`): explains Time Sensitive and reports the switch. No system alert stands behind it, so Not Now
/// is allowed; the copy follows the live switch, so it is right when the person returns from iOS Settings.
@MainActor
final class UKTimeSensitiveSetupStepViewController: UKSetupStepPageViewController {
    private let setup: SetupCoordinator
    private let openURL: (URL) -> Void
    private var lastIsOn: Bool?

    init(setup: SetupCoordinator, openURL: @escaping (URL) -> Void) {
        self.setup = setup
        self.openURL = openURL
        let isOn = setup.push.timeSensitive == .enabled
        super.init(barTitle: SetupStep.timeSensitive.barTitle, content: UKSetupStepContent(
            symbol: "bell.and.waves.left.and.right.fill", title: "", message: "", identifier: "setup.timeSensitive"))
        lastIsOn = isOn
        content = makeContent(isOn: isOn)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        // The copy follows the live switch.
        bag.observe { [weak self] in
            guard let self else { return }
            let isOn = self.setup.push.timeSensitive == .enabled
            guard isOn != self.lastIsOn else { return }
            self.lastIsOn = isOn
            self.content = self.makeContent(isOn: isOn)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        (navigationController ?? self).isModalInPresentation = true
    }

    private func makeContent(isOn: Bool) -> UKSetupStepContent {
        let copy = TimeSensitiveCopy(isOn: isOn)
        let status = UKSetupStatusRow(
            label: TimeSensitiveCopy.statusLabel, value: copy.status,
            valueColor: copy.action == .acknowledge ? UKDesignInk.success : UKDesignInk.warning, identifier: "setup.timeSensitive.status")
        let primary = UKPrimaryButton(copy.actionTitle) { [weak self] in self?.perform(copy.action) }
        primary.accessibilityIdentifier = "setup.timeSensitive.primary"
        var actions: [UIView] = [primary]
        if let secondary = copy.secondaryTitle {
            actions.append(UKSetupTextButton(secondary, identifier: "setup.timeSensitive.secondary") { [weak self] in
                guard let setup = self?.setup else { return }
                Task { await setup.finishTimeSensitive() }
            })
        }
        return UKSetupStepContent(symbol: "bell.and.waves.left.and.right.fill", title: copy.title, message: copy.message,
                                  points: TimeSensitiveCopy.points, footnote: copy.footnote, identifier: "setup.timeSensitive",
                                  status: status, actions: actions)
    }

    private func perform(_ action: TimeSensitiveCopy.Action) {
        switch action {
        case .acknowledge:
            Task { await setup.finishTimeSensitive() }
        case .openSettings:
            setup.openedSettingsFromTimeSensitive()
            if let url = SystemSettingsLink.notifications { openURL(url) }
        }
    }
}

// MARK: - Sheet

/// The Setup flow's one sheet (`SetupSheet`): Notifications, Time Sensitive and Location swap in place as each completes
/// (``SetupCoordinator``; owner, 2026-10-27). Always dark, full height (a content-fitted iPhone sheet is inset and iOS draws its
/// content at 0.96x, so the 50 pt buttons would read 48 pt), with no dots, counter or swipe between steps: the only way forward is
/// the step's button (HIG Privacy, pre-alert screens).
@MainActor
final class UKSetupSheet {
    let modal: UKHassModalController
    private let setup: SetupCoordinator
    private let openURL: (URL) -> Void
    private var shown: SetupStep
    private let bag = UKObservationBag()

    init(setup: SetupCoordinator, openURL: @escaping (URL) -> Void = { UIApplication.shared.open($0) }) {
        self.setup = setup
        self.openURL = openURL
        let step = setup.shownStep
        shown = step
        var options = UKHassModalOptions(title: nil, fitKey: "setup.sheet")
        options.closeIdentifier = "setup.close"
        options.showsClose = false
        options.appearance = .dark
        options.width = .page
        options.height = SetupSheet.height
        // A closed sheet (swipe-down on a Location status stage) tells the flow, so its state follows the screen.
        options.onDismissed = { [weak setup] in setup?.close() }
        let first = Self.page(for: step, setup: setup, openURL: openURL)
        first.navigationItem.title = step.barTitle
        modal = UKHassModalController(root: first, options: options)
        bag.observe { [weak self] in
            guard let self else { return }
            let next = self.setup.shownStep
            guard next != self.shown else { return }
            self.swap(to: next)
        }
    }

    /// Puts the next step in the same sheet, in place.
    private func swap(to step: SetupStep) {
        shown = step
        let page = Self.page(for: step, setup: setup, openURL: openURL)
        page.navigationItem.title = step.barTitle
        UKHassModal.applyChrome(to: page, options: modal.options, dismiss: nil, isRoot: false)
        modal.setViewControllers([page], animated: false)
    }

    private static func page(for step: SetupStep, setup: SetupCoordinator, openURL: @escaping (URL) -> Void) -> UIViewController {
        switch step {
        case .notifications:
            UKNotificationSetupStepViewController(setup: setup)
        case .timeSensitive:
            UKTimeSensitiveSetupStepViewController(setup: setup, openURL: openURL)
        case .location:
            if let location = setup.location {
                UKLocationPermission.make(location: location, onClose: { [weak setup] in setup?.close() }, sheetTitle: SetupStep.location.barTitle)
            } else {
                UKPageViewController(sheetTitle: step.barTitle)
            }
        }
    }
}

// MARK: - Presenter

/// Presents the Setup flow's sheet when ``SetupCoordinator`` has a step to show and closes it when the flow ends
/// (`SetupPresenter`); reads the notification answers again each time the app comes to the foreground.
@MainActor
final class UKSetupPresenter {
    private let setup: SetupCoordinator
    private let bag = UKObservationBag()
    private weak var host: UIViewController?
    private var sheet: UKSetupSheet?
    private let openURL: (URL) -> Void

    /// - Parameters:
    ///   - host: The controller the sheet is presented from.
    ///   - openURL: Opens a URL (iOS Settings); a gallery stands in for the person turning the switch on.
    init(setup: SetupCoordinator, host: UIViewController, openURL: @escaping (URL) -> Void = { UIApplication.shared.open($0) }) {
        self.setup = setup
        self.host = host
        self.openURL = openURL
        bag.observe { [weak self] in
            guard let self else { return }
            _ = self.setup.isPresenting
            _ = self.setup.shownStep
            Task { @MainActor in self.refresh() }
        }
    }

    /// Makes the sheet match the flow: up while it has a step, gone when it has none. Also run when the host appears, in case the
    /// flow started before there was a window.
    func refresh() { sync(presenting: setup.isPresenting) }

    /// The app came to the foreground: the Time Sensitive step and Settings follow a change made in iOS Settings.
    func sceneBecameActive() {
        Task { await setup.didBecomeActive() }
    }

    private func sync(presenting: Bool) {
        if presenting {
            guard sheet == nil, let host, host.viewIfLoaded?.window != nil else { return }
            let created = UKSetupSheet(setup: setup, openURL: openURL)
            sheet = created
            created.modal.present(from: Self.top(of: host))
        } else if let sheet {
            self.sheet = nil
            sheet.modal.dismiss(animated: true)
        }
    }

    private static func top(of controller: UIViewController) -> UIViewController {
        var top = controller
        while let presented = top.presentedViewController, !presented.isBeingDismissed { top = presented }
        return top
    }
}
#endif
