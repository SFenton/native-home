import HassCore

/// The House Layout row of the Home Assistant modal's Server section (rule 16 of `.agents/design/house-config-states.md`):
/// the one place a stale or partial layout is visible.
struct HouseLayoutSummary: Equatable {
    /// The most ids the footer lists before "and N more".
    static let listedIdLimit = 5

    /// The row's value.
    let value: String
    /// The section footer under the Server rows, or nil.
    let footer: String?

    /// - Parameters:
    ///   - hasDocument: Whether the facades have a document (``HouseConfigSource/current``).
    ///   - status: ``HouseConfigStore/status``, or nil when no store runs.
    ///   - missing: The configured entity ids Home Assistant did not report (``HouseConfig/missingEntityIds(hasReceivedFirstState:state:)``).
    init(hasDocument: Bool, status: HouseConfigStore.Status?, missing: [String]) {
        let status = status ?? .idle
        guard hasDocument else {
            if case let .message(kind, _) = HouseLayoutState.resolve(document: nil, status: status, role: .unknown) {
                value = HouseConfigCopy.entry(kind).title
            } else {
                value = Self.waiting
            }
            footer = nil
            return
        }
        switch status {
        case .ready:
            if missing.isEmpty {
                value = "Loaded"
                footer = nil
            } else {
                value = "Loaded, \(missing.count) not found"
                footer = Self.footer(missing: missing)
            }
        case .idle, .loading:
            value = Self.waiting
            footer = nil
        default:
            value = "Saved copy"
            footer = "Home Assistant can't send the house layout right now (\(Self.reason(status))), so S+H shows the copy it saved."
        }
    }

    private static let waiting = "Waiting for Home Assistant"

    /// "Not found in Home Assistant: a, b, c, d, e, and 3 more. Their tiles show Unavailable."
    static func footer(missing: [String]) -> String {
        let listed = missing.prefix(listedIdLimit).joined(separator: ", ")
        let more = missing.count - listedIdLimit
        let tail = more > 0 ? "\(listed), and \(more) more" : listed
        return "Not found in Home Assistant: \(tail). Their tiles show Unavailable."
    }

    /// Why Home Assistant is not sending a layout, in words.
    static func reason(_ status: HouseConfigStore.Status) -> String {
        switch status {
        case .integrationMissing: "the \(HouseConfigCopy.integrationName) is missing or out of date"
        case .notConfigured: "it has no house layout set up"
        case .invalid: "the layout can't be read"
        case .newerSchema: "the layout is newer than this version of S+H"
        case .timedOut: "it didn't answer"
        case .idle, .loading, .ready: "it isn't answering"
        }
    }
}
