#if os(iOS)
import HassCore

// MARK: - Configured household providers

/// Constructs canonical domain models from one verified, immutable house configuration and the publication's controls.
@MainActor
enum UKServerUIHouseholdProviders {
    /// The household provider `id` over the controls the document places on it.
    ///
    /// What the page offers (which entities, their titles and order) is the publication's: each target comes from a
    /// `settings-controls` node, and `HouseholdSettingsTarget` still checks its entity's domain. House configuration supplies
    /// only roles: the relay switch, the high-AQI mode, the power-recovery automation and the guest toggles.
    static func household(id: String, configuration: HouseConfig, document: ServerUICompositionDocument, store: EntityStore,
                          caller: any HassServiceCalling, current: @escaping () -> Bool) throws -> UKServerUIHouseholdProvider {
        let household = configuration.household
        var targets: [String: HouseholdSettingsTargetAdapter] = [:]
        func add(_ kind: HouseholdSettingsTarget.Kind, _ entity: String, _ title: String, key: String? = nil) throws {
            let target = try HouseholdSettingsTarget(kind: kind, entityId: entity, title: title)
            let key = key ?? entity
            if let existing = targets[key] {
                guard existing.target.kind == target.kind, existing.target.entityId == target.entityId else {
                    throw HouseholdSettingsTarget.Failure.invalidTarget
                }
                return
            }
            targets[key] = HouseholdSettingsTargetAdapter(target: target, store: store, caller: caller)
        }
        var warns = false
        for control in document.settingsControls(overProvider: id) {
            let title = control.node.title
            switch control.kind {
            case .householdToggle: try add(.toggle, control.item, title)
            case .householdReadOnly: try add(.readOnly, control.item, title)
            case .presenceRoom: try add(.presence, control.item, title)
            case .presenceChoice:
                if let entity = control.item.split(separator: "/", omittingEmptySubsequences: false).first.map(String.init) {
                    try add(.presence, entity, title)
                }
            case .householdRecovery:
                try add(.powerRecovery, household.powerRecoveryAutomation, HouseholdSettingsConfig.Admin.powerRecoveryTitle,
                        key: control.item)
            case .householdWarning: warns = true
            default: break
            }
        }
        let guests = configuration.home.guestToggles
        let warning = HouseholdSettingsController(store: store, caller: caller, targets: .init(
            toggleEntityIds: [], presenceTitles: [:], relayEntityId: household.relayControlEntityId,
            guestEntityId: guests.first?.entityId))
        return UKServerUIHouseholdProvider(id: id, targets: targets, highAQI: [household.highAqiTile.entityId],
            guests: Set(guests.map(\.entityId)), autoLock: Set(household.securityTiles.first.map(\.entityId).map { [$0] } ?? []),
            relayWarning: warns ? { warning.showsRelayGuestModeWarning } : nil, isCurrentSession: current)
    }

    static func away(id: String, configuration: HouseConfig, authenticatedUserID: String, store: EntityStore,
                     caller: any HassServiceResponding, current: @escaping () -> Bool) throws -> UKServerUIAwayProvider {
        let household = HouseholdAwayController(store: store, responder: caller, targets: try .init(
            statusEntityId: configuration.bedroom.householdAwayEntityId,
            commandService: configuration.bedroom.householdAwayScript), people: configuration.chores.people)
        let vacation = configuration.vacation
        let mode = VacationModeController(store: store, household: household, caller: caller, targets: try .init(
            modeEntityId: vacation.modeEntityId, invalidDatesPendingEntityId: vacation.invalidDatesPendingEntityId,
            startEntityId: vacation.startEntityId, endEntityId: vacation.endEntityId, checklist: vacation.checklist))
        let solo = SoloTripController(household: household)
        solo.viewer = try ServerUISummaryScope(authenticatedUserID: authenticatedUserID, people: configuration.chores.people).viewer
        let residents = Dictionary(uniqueKeysWithValues: configuration.chores.people.map { ($0.key, Resident(person: $0)) })
        return try UKServerUIAwayProvider(id: id, vacation: mode, solo: solo, residents: residents, isCurrentSession: current)
    }
}
#endif
