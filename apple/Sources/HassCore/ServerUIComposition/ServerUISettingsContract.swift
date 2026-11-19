import Foundation

// MARK: - Injected domain identities

/// A session-owned model, not an endpoint, credential, page identifier or service dispatcher.
/// The host must register the exact provider and validate every referenced item before acceptance.
public struct ServerUISettingsSource: Equatable, Sendable {
    /// The authored domain choices.
    public enum Domain: String, CaseIterable, Sendable {
        case household, away, preferences, feedback, profile, performance
    }
    public let providerId: String
    public let domain: Domain

    /// Creates a server uisettings source.
    public init(providerId: String, domain: Domain) {
        self.providerId = providerId
        self.domain = domain
    }
}

// MARK: - Domain controls

/// Closed domain operations over existing models. Sections, collections, tabs and forms remain
/// shell-owned; each node represents one control, never a compiled feature screen.
public struct ServerUISettingsControl: Equatable, Sendable {
    /// The authored kind choices.
    public enum Kind: String, CaseIterable, Sendable {
        case householdToggle = "household-toggle"
        case householdRecovery = "household-recovery"
        case householdWarning = "household-relay-warning"
        case householdReadOnly = "household-read-only"
        case presenceRoom = "presence-room"
        case presenceChoice = "presence-choice"
        case vacationStatus = "vacation-status"
        case vacationToggle = "vacation-toggle"
        case vacationCheck = "vacation-check"
        case vacationDates = "vacation-dates"
        case vacationConfirm = "vacation-confirm"
        case awayStatus = "away-status"
        case soloTraveler = "solo-traveler"
        case soloToggle = "solo-toggle"
        case soloDates = "solo-dates"
        case soloReturn = "solo-return"
        case soloConfirm = "solo-confirm"
        case awayRestore = "away-restore"
        case blur = "background-blur"
        case resetBlur = "reset-background-blur"
        case badge = "app-badge"
        case iconChoice = "app-icon-choice"
        case version = "app-version"
        case feedbackField = "feedback-field"
        case feedbackMedia = "feedback-media"
        case feedbackSubmit = "feedback-submit"
        case feedbackStatus = "feedback-status"
        case feedbackStop = "feedback-stop"
        case locationAccount = "location-account"
        case locationStatus = "location-status"
        case locationAction = "location-action"
        case profilePerson = "profile-person"
        case profilePeople = "profile-people"
        case signOut = "sign-out"
        case homeAssistant = "ha-settings"
        case homeAssistantValue = "ha-value"
        case homeAssistantWeb = "ha-web"
        case performanceRecording = "performance-recording"
        case performanceAction = "performance-action"

        public var domain: ServerUISettingsSource.Domain {
            switch self {
            case .householdToggle, .householdRecovery, .householdWarning, .householdReadOnly, .presenceRoom, .presenceChoice: .household
            case .vacationStatus, .vacationToggle, .vacationCheck, .vacationDates, .vacationConfirm,
                 .awayStatus, .soloTraveler, .soloToggle, .soloDates, .soloReturn, .soloConfirm, .awayRestore: .away
            case .blur, .resetBlur, .badge, .iconChoice, .version: .preferences
            case .feedbackField, .feedbackMedia, .feedbackSubmit, .feedbackStatus, .feedbackStop: .feedback
            case .locationAccount, .locationStatus, .locationAction, .profilePerson, .profilePeople, .signOut,
                 .homeAssistant, .homeAssistantValue, .homeAssistantWeb: .profile
            case .performanceRecording, .performanceAction: .performance
            }
        }

        public var requiresDestination: Bool {
            [.presenceRoom, .vacationToggle, .soloToggle, .locationAccount].contains(self)
        }

        public var allowsItem: Bool {
            [.householdToggle, .householdRecovery, .householdReadOnly, .presenceRoom, .presenceChoice,
             .vacationCheck, .soloTraveler, .iconChoice, .awayRestore, .feedbackField, .profilePerson, .performanceAction,
             .homeAssistantValue, .homeAssistantWeb].contains(self)
        }

        /// Fixed operation keys are checked by both compilers; entity/person keys are provider-owned.
        public var fixedItems: [String]? {
            switch self {
            case .feedbackField: ["title", "description", "repro", "expected"]
            case .awayRestore: ["keep_current", "restore_saved"]
            case .performanceAction: ["refresh", "clear-images", "reset", "export"]
            case .iconChoice: AppIconChoice.allCases.map(\.rawValue)
            case .homeAssistantValue: ["address", "connection", "version", "house-layout", "account", "role"]
            case .homeAssistantWeb: ["settings", "profile"]
            default: nil
            }
        }
    }

    public let node: ServerUICompositionDocument.Node
    public let sourceId: String
    public let kind: Kind
    /// Provider-owned stable target key; never an index into a mutable list.
    public let item: String
    public let subtitle: String
    public let icon: ServerUICompositionDocument.Symbol
    public let destination: ServerUICompositionDocument.Action?
}

// MARK: - Controls of one provider

extension ServerUICompositionDocument {
    /// Every settings control the pages and modals place over the settings provider `providerId`, in document order.
    ///
    /// A provider is built from these rather than from house configuration, so the tiles a household page offers are the ones
    /// the publication authors; house configuration only supplies the roles (which entity is the relay switch, the high-AQI
    /// mode, the power-recovery automation).
    public func settingsControls(overProvider providerId: String) -> [ServerUISettingsControl] {
        let sources = Set(dataSources.compactMap { source -> String? in
            if case .settingsProvider(let id, let configuration) = source, configuration.providerId == providerId { id } else { nil }
        })
        var controls: [ServerUISettingsControl] = []
        func visit(_ nodes: [Component]) {
            for node in nodes {
                if case .settingsControl(let control) = node, sources.contains(control.sourceId) { controls.append(control) }
                visit(node.childComponents)
            }
        }
        visit((surfaces).flatMap(\.components))
        return controls
    }
}
