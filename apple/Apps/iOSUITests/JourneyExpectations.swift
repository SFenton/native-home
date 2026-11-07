import Foundation
import XCTest

/// The expected names, ids and counts a journey asserts against, by role, for the target the run drives.
///
/// Journeys never hold a house's real values. Two targets exist:
///
/// - ``Target/gallery``: the DEBUG gallery and the hosted test instance both serve the synthetic DemoHouse, so the
///   expectations are ``demoValues``.
/// - ``Target/signedIn``: a run signed in to a server. Against the hosted test instance (`FENTON_HASS_SERVER` equals
///   `HASS_TEST_SERVER`, or `FENTON_JOURNEY_TARGET=demo`) the expectations are DemoHouse. Against the owner's own house
///   they come from the private JSON file named by `FENTON_JOURNEY_EXPECTATIONS` (keyed like
///   `JourneyExpectations.template.json`), which lives outside the repository and is never committed. Without that
///   file the journey skips with a reason; it never fails on house data.
///
/// Reading a value: `expectations[.key]` for a gallery journey (always answers), `try expectations.value(.key)` for a
/// signed-in one (skips when the private file lacks the key). System ids, SF Symbols and Home Assistant built-ins stay
/// literal in the journeys; only house content moves here. See `.agents/testing/apple/journey-expectations.md`.
struct JourneyExpectations {
    /// Which server a journey's expectations describe.
    enum Target {
        /// The gallery (DemoHouse by construction).
        case gallery
        /// A signed-in run: the test instance (DemoHouse) or the owner's house (private file).
        case signedIn
    }

    /// The environment variable naming the private expectations file.
    static let fileVariable = "FENTON_JOURNEY_EXPECTATIONS"

    /// The values this run asserts against, keyed by role.
    let values: [Key: String]

    /// Whether these are the DemoHouse values (gallery, or the hosted test instance).
    let isDemo: Bool

    /// The DemoHouse expectations for the gallery.
    static let gallery = JourneyExpectations(values: demoValues, isDemo: true)

    /// The expectations for `target`.
    ///
    /// - Parameters:
    ///   - target: The kind of run.
    ///   - environment: The process environment (injectable for tests).
    ///   - contents: Reads a file's data (injectable for tests).
    /// - Throws: `XCTSkip` when a signed-in run is neither on the test instance nor given a readable private file.
    static func current(
        for target: Target,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        contents: (String) -> Data? = { FileManager.default.contents(atPath: $0) }
    ) throws -> JourneyExpectations {
        guard target == .signedIn else { return gallery }
        if let path = environment[fileVariable], !path.isEmpty {
            guard let data = contents(path), let loaded = try? decode(data) else {
                throw XCTSkip("\(fileVariable) names a file that is missing or is not valid expectations JSON")
            }
            return JourneyExpectations(values: loaded, isDemo: false)
        }
        if onTestInstance(environment) { return gallery }
        throw XCTSkip("Live house journeys need \(fileVariable) (a private JSON file shaped like JourneyExpectations.template.json), or a run against the hosted test instance")
    }

    /// Whether the run signs in to the hosted test instance, which serves DemoHouse.
    static func onTestInstance(_ environment: [String: String]) -> Bool {
        if environment["FENTON_JOURNEY_TARGET"] == "demo" { return true }
        guard let server = environment["FENTON_HASS_SERVER"], !server.isEmpty else { return false }
        return server == environment["HASS_TEST_SERVER"]
    }

    /// Decodes the `values` object of an expectations file, ignoring comments and keys this build does not know.
    static func decode(_ data: Data) throws -> [Key: String] {
        struct File: Decodable { let values: [String: String] }
        let file = try JSONDecoder().decode(File.self, from: data)
        return Dictionary(uniqueKeysWithValues: file.values.compactMap { raw, value in Key(rawValue: raw).map { ($0, value) } })
    }

    /// A value that must be present; a live file that lacks it skips the journey instead of failing it.
    func value(_ key: Key) throws -> String {
        guard let found = values[key] else { throw XCTSkip("The expectations file has no value for \(key.rawValue)") }
        return found
    }

    /// A value for a gallery journey. A DemoHouse set answers every key; a set loaded from the private file answers only
    /// what it names, and asking for another key is a bug in the journey (use ``value(_:)``, which skips), never a
    /// reason to assert DemoHouse values against the owner's house.
    subscript(_ key: Key) -> String {
        if let found = values[key] { return found }
        assertionFailure("\(key.rawValue) is not in the loaded expectations; read it with value(_:) so the journey skips")
        return ""
    }

    /// A tint entry (`"red,green,blue"`, 0-255) as a tuple.
    func rgb(_ key: Key) -> (Int, Int, Int) {
        let parts = self[key].split(separator: ",").compactMap { Int($0) }
        return parts.count == 3 ? (parts[0], parts[1], parts[2]) : (0, 0, 0)
    }

    // MARK: - Keys and DemoHouse values

    /// Every value a journey asserts against, named by role. The raw value is the key in the expectations JSON.
    enum Key: String, CaseIterable, Sendable {

        // Bedroom
        /// Script object id (no 'script.' prefix) the bed power control calls.
        case bedHotFlashBrokerScript
        /// Script object id the whole-bed power control calls while one side is away.
        case bedHouseholdAwayScript
        /// Title of the first bed (the left side).
        case bedFirstTitle
        /// Bed id the gallery opens the first bed's sheet by (FENTON_GALLERY_SHEET).
        case bedFirstSheetId
        /// Bed id the gallery opens the second bed's sheet by.
        case bedSecondSheetId
        /// Title of the living-room remote (its name, as drawn).
        case remoteLivingRoomTitle
        /// Script object id that sets the first bed's level for tonight.
        case bedFirstTonightScript
        /// Asleep-stage level entity of the first bed.
        case bedFirstAsleepLevel
        /// Snooze button of the first bed's alarm.
        case bedFirstAlarmSnooze
        /// Stop button of the first bed's alarm.
        case bedFirstAlarmStop
        /// Hot Flash start button of the first bed.
        case bedFirstHotFlashButton
        /// Hot Flash cancel button of the first bed.
        case bedFirstHotFlashCancelButton

        // Chores
        /// Full script entity id the admin to-do list runs to complete an item.
        case choresAdminTodoCompletionScript
        /// Page id of the first resident's chores page (the 'chores.link.<id>' quick link).
        case choresFirstPageId
        /// Navigation title of the first resident's chores page.
        case choresFirstPageTitle
        /// Quick-link tint of the first resident, red,green,blue 0-255.
        case choresFirstLinkTint
        /// Page id of the second resident's chores page.
        case choresSecondPageId
        /// Accessibility label of the second resident's quick link.
        case choresSecondLinkTitle
        /// Quick-link tint of the second resident, red,green,blue 0-255.
        case choresSecondLinkTint
        /// Quick-link tint of the unassigned chores, red,green,blue 0-255.
        case choresUnassignedLinkTint
        /// Quick-link tint of the home chores, red,green,blue 0-255.
        case choresHomeLinkTint
        /// Quick-link tint of the groceries link, red,green,blue 0-255.
        case choresGroceriesLinkTint

        // Climate
        /// The whole-home hub thermostat the Climate page's mode and fan menus control.
        case climateHub

        // Custom lights
        /// Lighting-mode select of the Custom Lights page.
        case customLightsModeEntity
        /// A non-default lighting mode the journeys pick from the mode menu.
        case customLightsModeChoice
        /// Manual-control switch of the Custom Lights page.
        case customLightsManualControl
        /// The first custom light (its tile, sheet and 'other light' list).
        case customLightsFirstLight
        /// A second custom light listed as 'other' in the first light's sheet.
        case customLightsSecondLight
        /// The group light Reset All targets.
        case customLightsGroup

        // Household settings
        /// Front-door auto-lock toggle on the Admin page.
        case householdAutoLock
        /// First show-specific tile on the Admin page.
        case householdOutdoorFaucets
        /// Automation the power-recovery tile triggers.
        case householdPowerRecoveryAutomation
        /// Relay control mode toggle.
        case householdRelayControl
        /// Presence-override switch of the first presence room.
        case householdFirstPresence
        /// Presence-override switch of the last presence room (unavailable in the fixtures).
        case householdUnavailablePresence
        /// Auto re-enable switch of the second presence room.
        case householdKitchenAutoReenable
        /// Presence-override switch of the second presence room.
        case householdKitchenPresence
        /// High AQI Mode toggle.
        case householdHighAqi
        /// First guest toggle (the fixtures start it on).
        case householdGuestFirst
        /// Second guest toggle (the fixtures start it off).
        case householdGuestSecond
        /// Third guest toggle.
        case householdGuestThird
        /// Vehicle door lock on the Vehicle page.
        case householdVehicleDoors
        /// Vehicle charge-status sensor.
        case householdVehicleCharge

        // Security
        /// The security alarm panel.
        case securityAlarm
        /// The entry lock.
        case securityFrontDoorLock
        /// Left garage door.
        case securityGarageLeft
        /// Right garage door.
        case securityGarageRight
        /// Vehicle door lock shown on the Security page.
        case securityVehicleLock

        // Vacation
        /// The vacation-mode boolean.
        case vacationMode

        // Vacuums
        /// Vacuum-map id of the first vacuum (the gallery's FENTON_GALLERY_VACUUM value).
        case vacuumMainFloorMapId
        /// Vacuum-map id of the third vacuum (a second unit used for the settings and unavailable journeys).
        case vacuumMusicRoomMapId
        /// Vacuum entity of the first vacuum.
        case vacuumMainFloorEntity
        /// Mode select of the third vacuum.
        case vacuumSecondaryModeSelect
        /// Fan select of the third vacuum.
        case vacuumSecondaryFanSelect
        /// Zone-clean script of the first vacuum.
        case vacuumMainFloorZoneScript
        /// Clean-selected-segments script of the first vacuum.
        case vacuumMainFloorCleanScript
        /// Dock-clean script of the first vacuum.
        case vacuumMainFloorDockCleanScript
        /// Auto-clean pause switch of the first vacuum.
        case vacuumMainFloorAutoCleanPause

        // Room devices
        /// Script object id of the first bathroom fan's command script.
        case fanFirstScript
        /// Script object id of the second bathroom fan's command script.
        case fanSecondScript
        /// The grill's Keep Warm switch.
        case grillKeepWarm
        /// Script object id that sets the humidifier mist level.
        case humidifierSetLevelScript
        /// Humidifier warm-level number.
        case humidifierWarmLevel
        /// Humidifier power switch.
        case humidifierPower
        /// Fan entity of the first purifier (the manual fixture).
        case purifierFirstFan
        /// Fan-mode select of the first purifier.
        case purifierFirstModeSelect
        /// Auto-mode select of the fourth purifier (the auto fixture).
        case purifierFourthAutoModeSelect

        // Rooms
        /// Room page id of the first bathroom fan's room.
        case roomsFirstFanRoom
        /// Room page id of the second bathroom fan's room.
        case roomsSecondFanRoom
        /// The first fan room's towel-rack switch.
        case roomsTowelRack
        /// Script entity id the room grid runs to count a room access.
        case roomsAccessIncrementScript

        // Media
        /// Accessibility id of the living-room remote card on the Media page.
        case mediaLivingRoomCard
        /// Accessibility id of a console source card.
        case mediaConsoleCard
        /// Script entity id the console card runs.
        case mediaConsoleScript
        /// Accessibility id of the handheld-console card.
        case mediaHandheldCard
        /// Script entity id the handheld-console card runs.
        case mediaHandheldScript
        /// Accessibility id of the server source card.
        case mediaServerCard
        /// Accessibility id of the second room's streamer card.
        case mediaStreamerCard
        /// Remote id of the living-room remote (FENTON_GALLERY_REMOTE).
        case remoteLivingRoomId
        /// Remote id of the bedroom remote.
        case remoteBedroomId
        /// Remote id of the remote with apps, devices and light sync.
        case remoteStudioId
        /// Remote id of the remote with a device list.
        case remoteMediaRoomId
        /// Remote entity the living-room remote sends commands to.
        case remoteLivingRoomRemote
        /// Media player the living-room remote launches apps on.
        case remoteLivingRoomPlayer
        /// Media player the living-room keyboard types into.
        case remoteLivingRoomControl
        /// App id of the living-room remote's first app.
        case remoteLivingRoomAppId
        /// Title of the living-room remote's first app tile (the `remote.app.<title>` identifier).
        case remoteLivingRoomAppTitle
        /// Title of the studio remote's app tile (the `remote.app.<title>` identifier).
        case remoteStudioAppTitle
        /// Title of the studio remote's state-only speaker row (`remote.device.<title>`; it reports state and is not a button).
        case remoteStudioSpeakerTitle
        /// Remote entity of the bedroom remote.
        case remoteBedroomRemote
        /// Volume media player of the bedroom remote.
        case remoteBedroomVolumePlayer
        /// Script entity id the bedroom remote's Mute runs.
        case remoteMuteScript
        /// Script entity id the living-room remote runs to launch an app.
        case remoteLaunchAppScript
        /// Data key of the mute script's speaker argument.
        case remoteMuteSpeakerKey
        /// Script entity id the studio remote's power runs when on.
        case remoteStudioPowerOffScript
        /// Script entity id of the studio remote's first app.
        case remoteStudioAppScript
        /// Media player toggled by the media-room remote's first device row.
        case remoteProjector
        /// Input button the media-room computer row presses to turn it on.
        case remoteComputerPress
        /// Sync-mode select of the studio remote's light sync.
        case remoteSyncMode
        /// Intensity select of the studio remote's light sync.
        case remoteSyncIntensity

        // Titles and ids of rooms and people
        /// Room page id of the bedroom with the beds and the wake light.
        case roomBedroomId
        /// Title of that bedroom.
        case roomBedroomTitle
        /// Room page id of the room whose remote has apps, devices and light sync.
        case roomStudioId
        /// Title of that room.
        case roomStudioTitle
        /// Room page id of the room with the projector remote.
        case roomMediaId
        /// Title of that room.
        case roomMediaTitle
        /// Full name of the first resident (a profile name the gallery is launched with, or the signed-in user).
        case personFirstFullName
        /// Full name of the second resident.
        case personSecondFullName
        /// Person entity of the first resident.
        case personFirstEntity
        /// Person entity of the second resident.
        case personSecondEntity
        /// Title of the second bed (the right side).
        case bedSecondTitle
        /// A long, two-line tile title used to test wrapping.
        case tileClosetTitle
        /// A very long Live Activity title used to test wrapping.
        case tileClosetFanTitle
        /// A page title long enough to wrap in the navigation bar.
        case longPageTitle
        /// Title of the media-room remote's computer device row.
        case remoteComputerTitle

        // Sprinklers
        /// Rain-delay switch of the first controller.
        case sprinklerFirstRainDelay
        /// Valve of the first controller's first zone.
        case sprinklerFirstZoneValve
        /// Program switch of the first controller's first zone.
        case sprinklerFirstProgram
        /// Valve of the second controller's first zone.
        case sprinklerSecondZoneValve
    }

    /// The DemoHouse values (`HassDemoHouse`), served by the hosted test instance and drawn by the gallery.
    static let demoValues: [Key: String] = [
        // Bedroom
        .bedHotFlashBrokerScript: "demo_bed_hot_flash_broker",
        .bedHouseholdAwayScript: "demo_household_away_command",
        .bedFirstTitle: "Alex's Bed",
        .bedFirstSheetId: "alexs-bed",
        .bedSecondSheetId: "sams-bed",
        .remoteLivingRoomTitle: "Living Room STREAMER",
        .bedFirstTonightScript: "demo_bed_alex_temperature_tonight",
        .bedFirstAsleepLevel: "input_number.demo_level_1",
        .bedFirstAlarmSnooze: "button.demo_bedroom_1_alarm_1",
        .bedFirstAlarmStop: "button.demo_bedroom_1_alarm_2",
        .bedFirstHotFlashButton: "input_button.demo_input_button_1",
        .bedFirstHotFlashCancelButton: "input_button.demo_input_button_2",
        // Chores
        .choresAdminTodoCompletionScript: "script.demo_script_1",
        .choresFirstPageId: "alexs-chores",
        .choresFirstPageTitle: "Alex's Chores",
        .choresFirstLinkTint: "0,96,120",
        .choresSecondPageId: "sams-chores",
        .choresSecondLinkTitle: "Sam's Tasks",
        .choresSecondLinkTint: "212,108,0",
        .choresUnassignedLinkTint: "81,58,126",
        .choresHomeLinkTint: "64,143,154",
        .choresGroceriesLinkTint: "155,67,72",
        // Climate
        .climateHub: "climate.demo_climate_3",
        // Custom lights
        .customLightsModeEntity: "input_select.demo_front_yard_1",
        .customLightsModeChoice: "Team Colors",
        .customLightsManualControl: "input_boolean.demo_front_yard_1",
        .customLightsFirstLight: "light.demo_front_door_door_1",
        .customLightsSecondLight: "light.demo_front_door_door_2",
        .customLightsGroup: "light.demo_front_yard_1",
        // Household settings
        .householdAutoLock: "input_boolean.demo_front_door_lock_1",
        .householdOutdoorFaucets: "input_boolean.demo_input_boolean_3",
        .householdPowerRecoveryAutomation: "automation.demo_living_room_power_1",
        .householdRelayControl: "input_boolean.demo_mode_2",
        .householdFirstPresence: "switch.demo_living_room_presence_2",
        .householdUnavailablePresence: "switch.demo_back_deck_presence_1",
        .householdKitchenAutoReenable: "switch.demo_kitchen_presence_1",
        .householdKitchenPresence: "switch.demo_kitchen_presence_2",
        .householdHighAqi: "input_boolean.demo_mode_1",
        .householdGuestFirst: "input_boolean.demo_guest_room_1",
        .householdGuestSecond: "input_boolean.demo_studio_1",
        .householdGuestThird: "input_boolean.demo_media_room_1",
        .householdVehicleDoors: "lock.demo_lock_1",
        .householdVehicleCharge: "sensor.demo_sensor_16",
        // Security
        .securityAlarm: "alarm_control_panel.demo_alarm_control_panel_1",
        .securityFrontDoorLock: "lock.demo_lock_2",
        .securityGarageLeft: "cover.demo_garage_door_1",
        .securityGarageRight: "cover.demo_garage_door_2",
        .securityVehicleLock: "lock.demo_lock_1",
        // Vacation
        .vacationMode: "input_boolean.demo_mode_3",
        // Vacuums
        .vacuumMainFloorMapId: "mapped_devicea",
        .vacuumMusicRoomMapId: "mapped_devicec",
        .vacuumMainFloorEntity: "vacuum.demo_vacuum_1",
        .vacuumSecondaryModeSelect: "select.demo_mode_5",
        .vacuumSecondaryFanSelect: "select.demo_fan_3",
        .vacuumMainFloorZoneScript: "script.demo_main_floor_zone_1",
        .vacuumMainFloorCleanScript: "script.demo_main_floor_1",
        .vacuumMainFloorDockCleanScript: "script.demo_main_floor_2",
        .vacuumMainFloorAutoCleanPause: "switch.demo_main_floor_1",
        // Room devices
        .fanFirstScript: "demo_guest_bathroom_fan_command",
        .fanSecondScript: "demo_bathroom_1_fan_command",
        .grillKeepWarm: "switch.demo_enabled_1",
        .humidifierSetLevelScript: "demo_bedroom_1_humidifier_set_level",
        .humidifierWarmLevel: "number.demo_level_2",
        .humidifierPower: "switch.demo_power_1",
        .purifierFirstFan: "fan.demo_living_room_1_purifier",
        .purifierFirstModeSelect: "select.demo_living_room_1_fan_mode",
        .purifierFourthAutoModeSelect: "select.demo_office_1_auto_mode",
        // Rooms
        .roomsFirstFanRoom: "guest-bathroom",
        .roomsSecondFanRoom: "bathroom-1",
        .roomsTowelRack: "switch.demo_switch_2",
        .roomsAccessIncrementScript: "script.demo_script_2",
        // Media
        .mediaLivingRoomCard: "media.card.living-room.living-room-streamer",
        .mediaConsoleCard: "media.card.studio.game-console",
        .mediaConsoleScript: "script.demo_studio_console",
        .mediaHandheldCard: "media.card.media-room.handheld-console",
        .mediaHandheldScript: "script.demo_media_room_handheld_switch",
        .mediaServerCard: "media.card.studio.server",
        .mediaStreamerCard: "media.card.media-room.media-streamer",
        .remoteLivingRoomId: "living-room-streamer",
        .remoteBedroomId: "bedroom-1-streamer-tv",
        .remoteStudioId: "studio-remote",
        .remoteMediaRoomId: "media-room-streamer",
        .remoteLivingRoomRemote: "remote.demo_living_room_1",
        .remoteLivingRoomPlayer: "media_player.demo_living_room_1",
        .remoteLivingRoomControl: "media_player.demo_living_room_2",
        .remoteLivingRoomAppId: "com.streamapp.player",
        .remoteLivingRoomAppTitle: "Streaming A",
        .remoteStudioAppTitle: "Game",
        .remoteStudioSpeakerTitle: "Soundbar",
        .remoteBedroomRemote: "remote.demo_bedroom_1_1",
        .remoteBedroomVolumePlayer: "media_player.demo_media_player_4",
        .remoteMuteScript: "script.demo_toggle_speaker_mute",
        .remoteLaunchAppScript: "script.demo_launch_app_on_media_player",
        .remoteMuteSpeakerKey: "speakerdevice",
        .remoteStudioPowerOffScript: "script.demo_studio_tv_off",
        .remoteStudioAppScript: "script.demo_studio_game",
        .remoteProjector: "media_player.demo_media_player_2",
        .remoteComputerPress: "input_button.demo_input_button_6",
        .remoteSyncMode: "select.demo_studio_mode_1",
        .remoteSyncIntensity: "select.demo_studio_2",
        // Titles and ids of rooms and people
        .roomBedroomId: "bedroom-1",
        .roomBedroomTitle: "Bedroom 1",
        .roomStudioId: "studio",
        .roomStudioTitle: "Studio",
        .roomMediaId: "media-room",
        .roomMediaTitle: "Media room",
        .personFirstFullName: "Alex Demo",
        .personSecondFullName: "Sam Demo",
        .personFirstEntity: "person.demo_alex",
        .personSecondEntity: "person.demo_sam",
        .bedSecondTitle: "Sam's Bed",
        .tileClosetTitle: "Bedroom 1 Closet",
        .tileClosetFanTitle: "Bedroom 1 Closet Exhaust Fan",
        .longPageTitle: "Bedroom 1 Walk-in Wardrobe and Dressing Area",
        .remoteComputerTitle: "Media Room Computer",
        // Sprinklers
        .sprinklerFirstRainDelay: "switch.demo_front_yard_1",
        .sprinklerFirstZoneValve: "valve.demo_front_yard_zone_item_1",
        .sprinklerFirstProgram: "switch.demo_front_yard_program_1",
        .sprinklerSecondZoneValve: "valve.demo_backyard_zone_1",
    ]
}
