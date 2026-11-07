import Foundation

/// How an active Solo Trip changes one bed side (web `householdAwayBedScope`,
/// `ha-sfenton-react-dash@9ac2a46:src/components/hass/householdAway/householdAwayContract.ts:302`).
///
/// While one resident travels, the resident at home controls the whole bed through the Household Away
/// command, and the traveler's side is read-only.
public struct HouseholdAwayBedScope: Equatable, Sendable {
    /// A Solo Trip is running (not idle or merely scheduled).
    public var engaged: Bool
    /// This side's owner is at home and every Solo Trip effect is confirmed: changes go through the Household
    /// Away command and apply to both sides.
    public var controlsWholeBed: Bool
    public var traveler: HouseholdResident?
    public var homeResident: HouseholdResident?
    /// Household Away's revision, sent as `expected_revision`.
    public var revision: Int

    /// The side is view-only.
    public var readOnly: Bool { engaged && !controlsWholeBed }
    /// Controls accept input (no trip, or this side controls the whole bed).
    public var interactive: Bool { !engaged || controlsWholeBed }

    /// No Solo Trip.
    public static let noTrip = HouseholdAwayBedScope(engaged: false, controlsWholeBed: false, traveler: nil, homeResident: nil, revision: 0)

    /// Reads the Household Away status sensor for `owner`'s side.
    public init(entity: EntityState?, owner: HouseholdResident) {
        let attributes = entity?.attributes ?? [:]
        let state = entity?.state ?? "unavailable"
        let solo = attributes["mode"]?.string == "solo_trip"
        engaged = solo && !["idle", "scheduled", "unknown", "unavailable"].contains(state)
        let effects = attributes["effects"]
        let fullyActive = solo && state == "active"
            && effects?["wake_light_source"]?.bool == true
            && effects?["sleepypod_schedule"]?.bool == true
            && effects?["sleepypod_live_follow"]?.bool == true
        homeResident = attributes["home_resident"]?.string.flatMap { HouseholdResident(soloTripId: $0) }
        traveler = attributes["traveler"]?.string.flatMap { HouseholdResident(soloTripId: $0) }
        controlsWholeBed = engaged && fullyActive && homeResident == owner
        revision = WakeLight.integer(attributes["revision"]) ?? 0
    }

    init(engaged: Bool, controlsWholeBed: Bool, traveler: HouseholdResident?, homeResident: HouseholdResident?, revision: Int) {
        self.engaged = engaged
        self.controlsWholeBed = controlsWholeBed
        self.traveler = traveler
        self.homeResident = homeResident
        self.revision = revision
    }

    /// `Away · Read Only`.
    public static let readOnlySubtitle = "Away · Read Only"

    /// The Solo Trip notice for the sheet (web `householdAwayBedDescription`, viewer-neutral wording).
    public var notice: (title: String, message: String)? {
        guard engaged, let traveler else { return nil }
        let title = "\(traveler.name) Away"
        if controlsWholeBed {
            return (title, "While \(traveler.name) is away from home and the Solo Trip setting is enabled in settings, these controls and alarms control the entire bed.")
        }
        let home = homeResident?.name ?? "the other"
        return (title, "This traveler bed side is view-only during an active Solo Trip. Make changes from \(home)'s bed side.")
    }

    /// Household Away `sleepypod_command` service data (web `householdAwayServiceCall`).
    public func commandData(action: String, side: BedSide, extra: [String: any Sendable] = [:], requestId: String) -> [String: any Sendable] {
        var data: [String: any Sendable] = [
            "expected_revision": revision,
            "operation": "sleepypod_command",
            "request_id": requestId,
            "action": action,
            "side": side.rawValue,
        ]
        for (key, value) in extra { data[key] = value }
        return data
    }
}
