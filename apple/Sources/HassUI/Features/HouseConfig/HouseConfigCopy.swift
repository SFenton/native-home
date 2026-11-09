import HassCore

/// The words and glyphs of the missing-layout states, verbatim from rule 12 of `.agents/design/house-config-states.md`.
enum HouseConfigCopy {
    /// The integration's manifest name (`SFenton/ha-fenton-home` manifest.json).
    static let integrationName = "S+H Home Integration"
    /// The VoiceOver label of every skeleton.
    static let skeletonLabel = "Getting your home from Home Assistant"
    /// The busy title of Try Again.
    static let tryAgainBusy = "Trying Again"

    /// What a message's action does.
    enum Action: Equatable {
        /// Opens one of Home Assistant's pages in the modal.
        case open(HomeAssistantSettingsView.WebPage)
        /// Subscribes to the house layout again.
        case tryAgain
    }

    /// One state's glyph, title, messages and action.
    struct Entry: Equatable {
        let symbol: String
        let title: String
        let adminMessage: String
        let memberMessage: String
        let actionTitle: String?
        let action: Action?

        /// The message for a role: administrators and the owner read the do-it-yourself text, everyone else the ask-someone text.
        func message(for role: HouseLayoutState.Role) -> String { role == .admin ? adminMessage : memberMessage }
    }

    /// The copy for a state.
    static func entry(_ kind: HouseLayoutState.Kind) -> Entry {
        switch kind {
        case .integrationMissing:
            Entry(symbol: "puzzlepiece.extension", title: "Add the \(integrationName)",
                  adminMessage: "S+H gets your rooms, cameras and controls from the \(integrationName) in Home Assistant. Install or update it there; S+H picks it up by itself.",
                  memberMessage: "S+H gets your rooms, cameras and controls from the \(integrationName) in Home Assistant. Ask whoever manages your Home Assistant to install or update it.",
                  actionTitle: "Open Integrations", action: .open(.integrations))
        case .notConfigured:
            Entry(symbol: "house", title: "Home Isn't Set Up Yet",
                  adminMessage: "The \(integrationName) is installed but has no house layout yet. Add one in Home Assistant; S+H picks it up by itself.",
                  memberMessage: "The \(integrationName) is installed but has no house layout yet. Ask whoever manages your Home Assistant to add one.",
                  actionTitle: "Open \(integrationName)", action: .open(.houseIntegration))
        case .invalid:
            Entry(symbol: "exclamationmark.triangle", title: "Unable to Read the House Layout",
                  adminMessage: "Home Assistant lists what's wrong under Repairs. Fix it there; S+H picks it up by itself.",
                  memberMessage: "Ask whoever manages your Home Assistant to check Repairs.",
                  actionTitle: "Open Repairs", action: .open(.repairs))
        case .newerSchema:
            Entry(symbol: "arrow.down.circle", title: "Update S+H",
                  adminMessage: "This Home Assistant has a newer house layout than this version of S+H can read. Update S+H to see your home.",
                  memberMessage: "This Home Assistant has a newer house layout than this version of S+H can read. Update S+H to see your home.",
                  actionTitle: nil, action: nil)
        case .timedOut:
            Entry(symbol: "exclamationmark.triangle", title: "Unable to Load the House Layout",
                  adminMessage: "Home Assistant hasn't sent the house layout. Try again; if it keeps happening, restart Home Assistant.",
                  memberMessage: "Home Assistant hasn't sent the house layout. Try again; if it keeps happening, restart Home Assistant.",
                  actionTitle: "Try Again", action: .tryAgain)
        }
    }
}
