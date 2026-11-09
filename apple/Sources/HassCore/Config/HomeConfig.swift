import Foundation

/// Entity configuration for the Home page, ported from the React dashboard.
///
/// Source: `ha-sfenton-react-dash@9ac2a46:src/constants/atAGlance.ts` and `src/constants/portedDashboard.ts`; the status
/// rail and its summaries follow `ha-sfenton-react-dash@f5a7bf9`.
public enum HomeConfig {
    // MARK: - Status rail

    /// Which sheet a status chip opens.
    public enum ChipSheet: String, Sendable, Hashable, CaseIterable, Identifiable, Codable {
        case lights, security, climate, occupancy, contacts, airQuality
        public var id: String { rawValue }

        /// The room overview this chip opens, or `nil` for Security (its own controls).
        public var overview: RoomOverviewKind? {
            switch self {
            case .lights: .lights
            case .climate: .climate
            case .occupancy: .occupancy
            case .contacts: .contacts
            case .airQuality: .airQuality
            case .security: nil
            }
        }
    }

    /// Visual tone of a chip (web `StatusChipConfig.tone`).
    public enum ChipTone: String, Sendable, Codable { case light, security, climate, presence, contact, air }

    /// One chip in the Home status rail.
    public struct StatusChip: Sendable, Identifiable, Hashable, Codable {
        public var title: String
        /// Web MDI icon name, mapped to an SF Symbol by `HassDesign`.
        public var icon: String
        public var entityId: String
        public var tone: ChipTone
        public var sheet: ChipSheet
        /// A text helper holding the chip's colour (Climate: the temperature colour; Air Quality: the AQI colour, which
        /// the web draws on the icon; web `colorEntityId`). See `ChipWebColor`.
        public var colorEntityId: String? = nil
        /// A second text helper the chip's summary reads (Air Quality: the PM2.5 range beside the AQI range in `entityId`).
        /// Optional in the document, so a document without it decodes as before.
        public var detailEntityId: String? = nil
        public var id: String { entityId }
    }

    /// The status rail, in order: the server's document.
    public static var statusChips: [StatusChip] { HouseConfigSource.active.read { $0.home.statusChips } ?? [] }


    // MARK: - Weather

    /// Weather entity used by the web `WeatherSummary`: the server's document.
    public static var weatherEntityId: String { HouseConfigSource.active.read { $0.home.weatherEntityId } ?? "" }

    // MARK: - Guests

    /// One guest-stay toggle (`GUEST_CONTROL_ITEMS`, portedDashboard.ts:391).
    public struct GuestToggle: Sendable, Identifiable, Hashable, Codable {
        public var title: String
        public var entityId: String
        public var icon: String
        public var id: String { entityId }
    }

    /// The optimistic-clear rule of every guest toggle, by entity id. A toggle the document repeats keeps one rule.
    public static var guestToggleRules: [String: OptimisticOverlay.ClearRule] {
        Dictionary(guestToggles.map { ($0.entityId, OptimisticOverlay.ClearRule.confirmation) }, uniquingKeysWith: { first, _ in first })
    }

    /// Guest-stay toggles; the guest presence section shows when any is on. The server's document.
    public static var guestToggles: [GuestToggle] { HouseConfigSource.active.read { $0.home.guestToggles } ?? [] }

    // MARK: - Cameras

    /// One camera tile (`CAMERA_ITEMS`, atAGlance.ts:281).
    public struct Camera: Sendable, Identifiable, Hashable, Codable {
        public var title: String
        public var entityId: String
        /// go2rtc stream id for live video.
        public var rtcStreamId: String
        /// Width / height.
        public var aspectRatio: Double
        /// `on` while the camera is recording (web `recordingEntityId`).
        public var recordingEntityId: String?
        /// Script that toggles a manual recording (web `recordingScriptEntityId`).
        public var recordingScriptEntityId: String?
        public var id: String { entityId }

        public init(title: String, entityId: String, rtcStreamId: String, aspectRatio: Double,
                    recordingEntityId: String? = nil, recordingScriptEntityId: String? = nil) {
            self.title = title
            self.entityId = entityId
            self.rtcStreamId = rtcStreamId
            self.aspectRatio = aspectRatio
            self.recordingEntityId = recordingEntityId
            self.recordingScriptEntityId = recordingScriptEntityId
        }

        /// Starts or stops a manual recording (web `toggleRecording`: `script.turn_on`; the script toggles).
        public var recordCall: ServiceCall? {
            recordingScriptEntityId.map { ServiceCall("script", "turn_on", target: $0) }
        }
    }

    /// Home cameras in web order: the server's document.
    public static var cameras: [Camera] { HouseConfigSource.active.read { $0.home.cameras } ?? [] }

    // MARK: - Lights

    /// Room light groups shown in the Lights sheet, in web order (`LIGHT_GROUPS`, atAGlance.ts:343).
    public static var lightGroups: [RoomGroup] { RoomGroups.allLights }
}

// MARK: - Summaries

public extension HomeConfig {
    /// The short value a status chip shows under its title.
    /// - Parameters:
    ///   - chip: The chip.
    ///   - value: Looks up an entity's current state.
    static func summary(for chip: StatusChip, value: (String) -> EntityState?) -> String {
        // Lights, Contact Sensors and Air Quality count their rooms' entities (web `subtitleByHash`), so they read
        // even while the chip's own group entity is missing.
        switch chip.sheet {
        case .lights: return RoomOverview.lightCountSummary(RoomOverview.activeLightCount(read: value))
        case .contacts: return RoomOverview.contactCountSummary(RoomOverview.openContactCount(read: value))
        case .airQuality: return RoomOverview.airQualityChipSummary(read: value)
        default: break
        }
        guard let entity = value(chip.entityId), !entity.isUnavailable else { return "Unavailable" }
        switch chip.sheet {
        case .security: return StateText.titleCase(entity.state)
        case .occupancy: return RoomFormat.occupancy(entity)
        default: return entity.state
        }
    }
}
