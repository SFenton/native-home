#if os(iOS)
import HassCore
import HassDesign
import Observation
import UIKit

// MARK: - Authenticated profile values and system intents

/// Bootstrap supplies existing session operations, not credentials or a second connection.
/// The person projection must already apply the viewer's visibility/privacy policy.
@MainActor @Observable
final class UKServerUIProfileProvider: UKServerUISettingsProvider {
    let definition: ServerUISettingsSource
    private let current: () -> Bool
    private let location: LocationCoordinator?
    private let people: [String: () -> (ProfileSummary.Person, AvatarBox?)?]
    private let allPeople: (() -> [(ProfileSummary.Person, AvatarBox?)])?
    private let supportsLocation: Bool
    private let signOut: () async throws -> Void
    private let homeAssistant: (UIViewController) -> Void
    private let homeAssistantSnapshot: (() -> UKServerUIHomeAssistantSnapshot)?
    private let openHomeAssistantWeb: ((HomeAssistantSettingsView.WebPage, UIViewController) -> Void)?
    private var signingOut = false
    private var confirming = false
    var isCurrentSession: Bool { current() }
    var protectsPublication: Bool { signingOut || confirming }

    init(id: String, location: LocationCoordinator?,
         people: [String: () -> (ProfileSummary.Person, AvatarBox?)?],
         allPeople: (() -> [(ProfileSummary.Person, AvatarBox?)])? = nil, supportsLocation: Bool = true,
         isCurrentSession: @escaping () -> Bool, signOut: @escaping () async throws -> Void,
         homeAssistant: @escaping (UIViewController) -> Void,
         homeAssistantSnapshot: (() -> UKServerUIHomeAssistantSnapshot)? = nil,
         openHomeAssistantWeb: ((HomeAssistantSettingsView.WebPage, UIViewController) -> Void)? = nil) {
        definition = .init(providerId: id, domain: .profile)
        self.location = location
        self.people = people
        self.allPeople = allPeople
        self.supportsLocation = supportsLocation
        current = isCurrentSession
        self.signOut = signOut
        self.homeAssistant = homeAssistant
        self.homeAssistantSnapshot = homeAssistantSnapshot
        self.openHomeAssistantWeb = openHomeAssistantWeb
    }

    func accepts(_ control: ServerUISettingsControl) -> Bool {
        guard control.kind.domain == .profile else { return false }
        switch control.kind {
        case .locationAccount, .locationStatus, .locationAction: return !supportsLocation || location != nil
        case .profilePerson: return people[control.item] != nil
        case .profilePeople: return allPeople != nil
        case .homeAssistantValue: return homeAssistantSnapshot != nil
        case .homeAssistantWeb: return homeAssistantSnapshot != nil && openHomeAssistantWeb != nil
        default: return true
        }
    }

    func make(_ control: ServerUISettingsControl, host: UKServerUISettingsAtom, page: UKServerUIPage) throws -> UIView {
        guard accepts(control) else { throw UKServerUIRendererError(code: .unavailableSource, pointer: "/document/dataSources") }
        if control.kind == .homeAssistantValue, let homeAssistantSnapshot {
            let row = UKRowView(.init(control.node.title, style: .form))
            host.bag.observe { [weak self, weak row, weak host] in
                let snapshot = homeAssistantSnapshot()
                let value = self?.isCurrentSession == true ? snapshot.value(for: control.item) : nil
                row?.update(.init(control.node.title, subtitle: control.item == "house-layout" ? snapshot.houseLayout.footer : nil,
                                  value: value, style: .form))
                host?.isHidden = value == nil
                host?.ukRemeasureContainers(includingSelf: true)
            }
            return row
        }
        if control.kind == .homeAssistantWeb, let homeAssistantSnapshot, let openHomeAssistantWeb,
           let destination = HomeAssistantSettingsView.WebPage(rawValue: control.item) {
            let row = UKGroupedRowButton(title: control.node.title, symbol: control.icon.drawn, identifier: control.node.id)
            row.hint = control.subtitle
            row.onTap = { [weak self, weak host, weak page] in
                guard let self, let host, let page else { return }
                host.perform(from: page) {
                    try self.requireCurrent()
                    guard !self.signingOut, destination == .profile || homeAssistantSnapshot().canAdminister else {
                        throw HouseholdSettingsTarget.Failure.unavailable
                    }
                    openHomeAssistantWeb(destination, page)
                }
            }
            host.bag.observe { [weak self, weak host, weak row] in
                host?.isHidden = destination == .settings && !homeAssistantSnapshot().canAdminister
                row?.isEnabled = self?.isCurrentSession == true && self?.signingOut == false
                host?.ukRemeasureContainers(includingSelf: true)
            }
            return row
        }
        if [.locationAccount, .locationStatus, .locationAction].contains(control.kind), !supportsLocation {
            let view = UIView()
            view.isHidden = true
            host.isHidden = true
            return view
        }
        if control.kind == .profilePeople, let allPeople {
            let slot = UIStackView.ukColumn(spacing: 0)
            var previous: [ProfileSummary.Person]?
            host.bag.observe { [weak self, weak slot, weak host] in
                guard let self, let slot else { return }
                let values = self.isCurrentSession ? allPeople() : []
                guard previous != values.map(\.0) else { return }
                previous = values.map(\.0)
                slot.arrangedSubviews.forEach { $0.removeFromSuperview() }
                for (person, avatar) in values { slot.addArrangedSubview(UKPersonRow(person: person, avatar: avatar)) }
                host?.ukRemeasureContainers(includingSelf: true)
            }
            return slot
        }
        if control.kind == .profilePerson {
            let slot = UIStackView.ukColumn(spacing: 0)
            var previous: ProfileSummary.Person?
            host.bag.observe { [weak self, weak slot, weak host] in
                guard let self, let slot else { return }
                let value = self.isCurrentSession ? self.people[control.item]?() : nil
                guard previous != value?.0 || slot.arrangedSubviews.isEmpty else { return }
                previous = value?.0
                slot.arrangedSubviews.forEach { $0.removeFromSuperview() }
                if let (person, avatar) = value {
                    slot.addArrangedSubview(UKPersonRow(person: person, avatar: avatar))
                }
                host?.ukRemeasureContainers(includingSelf: true)
            }
            return slot
        }
        if control.kind == .locationAccount, let location {
            let section = UKLocationAccountSection(title: control.node.title, rowTitle: control.subtitle,
                                                   symbol: control.icon.drawn, content: .current(location)) { [weak self, weak host, weak page] in
                guard let self, let host, let page else { return }
                host.perform(from: page) {
                    try self.requireCurrent()
                    if let destination = control.destination { try page.renderer?.perform(destination, from: page) }
                }
            }
            host.bag.observe { [weak section, weak host] in
                section?.update(.current(location))
                host?.ukRemeasureContainers(includingSelf: true)
            }
            return section
        }
        if control.kind == .locationStatus, let location {
            let label = UILabel.uk(.body, ink: UKDesignInk.primary)
            label.numberOfLines = 0
            host.bag.observe { [weak label, weak host] in
                let permission = location.reporter.permission
                let copy = LocationPermissionCopy(stage: permission.stage, canAskForAlways: !location.hasAskedForAlways)
                label?.text = [copy.title, copy.message, LocationPermissionCopy.status(permission), control.subtitle, copy.footnote]
                    .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n\n")
                host?.ukRemeasureContainers(includingSelf: true)
            }
            return label
        }
        if control.kind == .signOut {
            let row = UKSignOutRow(identifier: control.node.id, title: control.node.title)
            row.onTap = { [weak self, weak host, weak page] in
                guard let self, let host, let page else { return }
                host.perform(from: page) { try self.requireCurrent(); self.confirmSignOut(from: page) }
            }
            host.bag.observe { [weak self, weak row, weak page] in
                row?.update(isSigningOut: self?.signingOut == true)
                page?.renderer?.updateSettingsExitGuard()
            }
            return row
        }
        let button = UKPrimaryButton(control.node.title) { [weak self, weak host, weak page] in
            guard let self, let host, let page else { return }
            host.perform(from: page) {
                try self.requireCurrent()
                if control.kind == .homeAssistant { self.homeAssistant(page) }
                else if let location = self.location {
                    let copy = LocationPermissionCopy(stage: location.reporter.permission.stage, canAskForAlways: !location.hasAskedForAlways)
                    switch copy.action {
                    case .requestPermission: location.requestPermission()
                    case .openSettings:
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    case nil: throw HouseholdSettingsTarget.Failure.unavailable
                    }
                }
            }
        }
        if let location, control.kind == .locationAction {
            host.bag.observe { [weak button] in
                let copy = LocationPermissionCopy(stage: location.reporter.permission.stage, canAskForAlways: !location.hasAskedForAlways)
                button?.isHidden = copy.actionTitle == nil
                button?.title = copy.actionTitle ?? control.node.title
            }
        }
        return button
    }

    private func confirmSignOut(from page: UKServerUIPage) {
        guard !signingOut, !confirming else { return }
        confirming = true
        let spec = AlertCopy.signOut
        let alert = UIAlertController(title: spec.title, message: spec.message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: spec.confirm.title, style: .destructive) { [weak self, weak page] _ in
            guard let self, let page else { return }
            confirming = false
            executeSignOut(from: page)
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in self?.confirming = false })
        page.present(alert, animated: true)
    }

    private func executeSignOut(from page: UKServerUIPage) {
        guard isCurrentSession else {
            page.renderer?.onError(.init(code: .interactionBlocked, pointer: "/document/dataSources"))
            return
        }
        guard !signingOut else { return }
        signingOut = true
        Task { [self] in
            do {
                try await signOut()
                signingOut = false
            } catch {
                signingOut = false
                confirming = true
                let spec = AlertCopy.signOutFailed(device: .current)
                let alert = UIAlertController(title: spec.title, message: spec.message, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: spec.confirm.title, style: .default) { [weak self, weak page] _ in
                    guard let page else { return }; self?.confirming = false; self?.executeSignOut(from: page)
                })
                alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in self?.confirming = false })
                page.present(alert, animated: true)
            }
        }
    }
}
#endif
