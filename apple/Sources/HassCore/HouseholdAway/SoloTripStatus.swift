import Foundation

/// What the Solo Trip status section shows (web `SoloTripStatusSection.tsx`). Only confirmed state is
/// described; backend codes stay diagnostics.
public struct SoloTripStatus: Equatable, Sendable {
    /// A button in the section.
    public enum Action: String, Equatable, Sendable, CaseIterable {
        case keepCurrent, restoreSaved, endNow

        public var title: String {
            switch self {
            case .keepCurrent: SoloTripCopy.restoreKeepCurrent
            case .restoreSaved: SoloTripCopy.restoreSaved
            case .endNow: SoloTripCopy.endNow
            }
        }
    }

    /// Which parts the host page shows (web props of the same names).
    public struct Options: Equatable, Sendable {
        public var showsConfirmedActiveNotice = true
        public var showsActivatingEndNow = true
        public var showsActivationProgress = true

        public init(showsConfirmedActiveNotice: Bool = true, showsActivatingEndNow: Bool = true, showsActivationProgress: Bool = true) {
            self.showsConfirmedActiveNotice = showsConfirmedActiveNotice
            self.showsActivatingEndNow = showsActivatingEndNow
            self.showsActivationProgress = showsActivationProgress
        }

        /// The Solo Trip page shows its own notice and toggle, so only errors and the restore choice.
        public static let soloTripPage = Options(showsConfirmedActiveNotice: false, showsActivatingEndNow: false, showsActivationProgress: false)
    }

    public var title: String?
    public var description: String?
    public var error: String?
    public var actions: [Action] = []
    /// Show ``SoloTripNotice`` under the title.
    public var showsActiveNotice = false

    public init(title: String? = nil, description: String? = nil, error: String? = nil, actions: [Action] = [], showsActiveNotice: Bool = false) {
        self.title = title
        self.description = description
        self.error = error
        self.actions = actions
        self.showsActiveNotice = showsActiveNotice
    }

    /// Nothing to show.
    public var isEmpty: Bool { title == nil && description == nil && error == nil && actions.isEmpty && !showsActiveNotice }

    /// The section for `snapshot`.
    public static func make(snapshot: HouseholdAway.Snapshot, errorCode: String?, options: Options = .init()) -> SoloTripStatus {
        let error = SoloTripCopy.commandError(errorCode)
        let travelerTitle = SoloTripCopy.activeTitle(traveler: snapshot.traveler?.name ?? "")
        switch snapshot.state {
        case .restoreRequired:
            return SoloTripStatus(title: SoloTripCopy.restoreRequiredTitle, description: SoloTripCopy.restoreRequiredDescription,
                                  error: error, actions: [.keepCurrent, .restoreSaved])
        case .activating:
            guard options.showsActivationProgress else { return SoloTripStatus(error: error) }
            return SoloTripStatus(title: SoloTripCopy.activatingTitle, description: SoloTripCopy.activatingDescription,
                                  error: error, actions: options.showsActivatingEndNow ? [.endNow] : [])
        case .ending:
            return SoloTripStatus(title: SoloTripCopy.endingTitle, description: SoloTripCopy.endingDescription, error: error)
        case .scheduled:
            return SoloTripStatus(error: error)
        case .degraded:
            return SoloTripStatus(title: SoloTripCopy.degradedTitle, description: SoloTripCopy.degradedDescription, error: error)
        case .active, .idle:
            if snapshot.isFullyActive {
                guard options.showsConfirmedActiveNotice else { return SoloTripStatus(error: error) }
                // The notice box carries "<Traveler> Away"; a section title would say it twice.
                return SoloTripStatus(error: error, showsActiveNotice: true)
            }
            if !options.showsConfirmedActiveNotice {
                guard options.showsActivationProgress else { return SoloTripStatus(error: error) }
                return SoloTripStatus(description: SoloTripCopy.activeUnconfirmedDescription, error: error)
            }
            return SoloTripStatus(title: travelerTitle, description: SoloTripCopy.activeUnconfirmedDescription, error: error)
        }
    }
}

/// The "<Traveler> Away" notice (web `SoloTripActiveNotice`).
public struct SoloTripNotice: Equatable, Sendable {
    public var title: String
    /// Green and described only once every effect is confirmed, or while activation settles.
    public var isSuccess: Bool
    public var description: String?

    /// The notice while the traveler is away, else `nil`.
    public static func make(snapshot: HouseholdAway.Snapshot, viewer: HouseholdResident?) -> SoloTripNotice? {
        guard snapshot.isTravelerAway, let traveler = snapshot.traveler else { return nil }
        let success = snapshot.isFullyActive || snapshot.isActivationSettling
        var description: String?
        if success {
            if viewer == traveler, let home = snapshot.homeResident {
                description = SoloTripCopy.activeDescriptionTraveler(homeResident: home.name)
            } else {
                description = SoloTripCopy.activeDescription(traveler: traveler.name)
            }
        }
        return SoloTripNotice(title: SoloTripCopy.activeTitle(traveler: traveler.name), isSuccess: success, description: description)
    }
}
