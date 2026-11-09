import Foundation

// MARK: - Shared value types

public extension HouseConfig {
    /// An sRGB tint, 0...255 per channel, for the config values the code holds as bare tuples.
    struct Tint: Codable, Hashable, Sendable {
        /// Red, 0...255.
        public var red: Double
        /// Green, 0...255.
        public var green: Double
        /// Blue, 0...255.
        public var blue: Double

        /// Creates a tint.
        public init(red: Double, green: Double, blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }
    }

    /// A household member, keyed by a neutral id and tied to their Home Assistant user.
    struct Person: Codable, Hashable, Sendable, Identifiable {
        /// Stable neutral key (`resident_1`), the value ``Resident`` holds and the pages and beds refer to.
        public var key: String
        /// Display name.
        public var name: String
        /// Home Assistant user id.
        public var haUserId: String
        /// The person's `person.*` entity.
        public var personEntityId: String
        /// The task form's assignee value ("" is Anyone).
        public var taskAssignee: String
        /// The value Home Assistant's Solo Trip scope uses for this person.
        public var soloTripId: String
        /// Whether the admin To-Do page shows for this person.
        public var seesAdminTodo: Bool
        /// The three open-item lists the Your Summary sheet reads for this person.
        public var summaryLists: SummaryLists
        /// The person's key.
        public var id: String { key }

        /// Creates a person.
        public init(
            key: String, name: String, haUserId: String, personEntityId: String, taskAssignee: String, soloTripId: String,
            seesAdminTodo: Bool, summaryLists: SummaryLists
        ) {
            self.key = key
            self.name = name
            self.haUserId = haUserId
            self.personEntityId = personEntityId
            self.taskAssignee = taskAssignee
            self.soloTripId = soloTripId
            self.seesAdminTodo = seesAdminTodo
            self.summaryLists = summaryLists
        }
    }

    /// A person's three summary lists, as entity ids (chores past due, due today, without a due date).
    struct SummaryLists: Codable, Hashable, Sendable {
        /// Chores past their due date.
        public var overdue: String
        /// Chores due today.
        public var dueToday: String
        /// Chores without a due date.
        public var noDueDate: String

        /// Creates the three lists.
        public init(overdue: String, dueToday: String, noDueDate: String) {
            self.overdue = overdue
            self.dueToday = dueToday
            self.noDueDate = noDueDate
        }
    }
}

// MARK: - Home, Security, Climate

public extension HouseConfig {
    /// The Home page (`HomeConfig`).
    struct HomeSection: Codable, Hashable, Sendable {
        /// The status rail, in order.
        public var statusChips: [HomeConfig.StatusChip]
        /// The weather entity.
        public var weatherEntityId: String
        /// The air-quality (US AQI) sensor the weather card reads. Optional: absent leaves it empty.
        public var airQualityEntityId: String?
        /// The sun entity (next sunrise and sunset). Optional: absent leaves it empty.
        public var sunEntityId: String?
        /// Guest-stay toggles.
        public var guestToggles: [HomeConfig.GuestToggle]
        /// Camera tiles.
        public var cameras: [HomeConfig.Camera]
    }

    /// The Security page (`SecurityConfig`).
    struct SecuritySection: Codable, Hashable, Sendable {
        /// The alarm panel.
        public var alarmEntityId: String
        /// The entry lock the Security page leads with.
        public var entryLockEntityId: String
        /// Garage door covers by role (`left`, `right`).
        public var garageDoors: [String: String]
        /// The vehicle's door lock.
        public var vehicleLockEntityId: String
        /// The aggregate contact sensor the Contact Sensors chip summarizes.
        public var contactSensorsEntityId: String
        /// Whether the Vehicle section shows.
        public var showsVehicleSection: Bool
        /// The control tiles, in order.
        public var controlTiles: [SecurityConfig.Tile]
        /// The vehicle tiles.
        public var vehicleTiles: [SecurityConfig.Tile]
    }

    /// The Climate page (`ClimateConfig`).
    struct ClimateSection: Codable, Hashable, Sendable {
        /// The whole-home virtual thermostat.
        public var globalThermostatEntityId: String
        /// The thermostat the whole-home dial shows while the house is effectively away.
        public var ecoAwayThermostatEntityId: String
        /// The physical thermostat.
        public var hubEntityId: String
        /// Away Mode, the fallback when the effective home/away sensor is unknown.
        public var awayModeEntityId: String
        /// The effective `Home` / `Away` sensor.
        public var homeAwayEntityId: String
        /// Why the effective mode is what it is.
        public var homeAwayReasonEntityId: String
        /// The switch for Home Assistant's automatic thermostat control.
        public var integrationEntityId: String
        /// The Eco Mode switch.
        public var ecoModeEntityId: String
        /// The Eco Mode critical-tracking select.
        public var ecoCriticalEntityId: String
        /// The Eco Mode behaviour-when-away select.
        public var ecoAwayEntityId: String
        /// The Predictive Comfort switch.
        public var predictiveComfortEntityId: String
        /// The Predictive Comfort auto-adjust switch.
        public var predictiveAutoAdjustEntityId: String
        /// The Predictive Comfort HVAC-mode-change switch.
        public var predictiveHvacModeChangesEntityId: String
        /// The Predictive Comfort allow-while-away switch.
        public var predictiveAllowAwayEntityId: String
        /// The Predictive Comfort recommendation sensor.
        public var predictiveSensorEntityId: String
        /// The track-only-selected-rooms switch.
        public var trackSelectedEntityId: String
        /// The select option that enables per-room Critical Protection.
        public var trackSelectCriticalOption: String
        /// Heating tint as `0xRRGGBB`.
        public var heatColorHex: Int
        /// Cooling tint as `0xRRGGBB`.
        public var coolColorHex: Int
        /// Rooms with a virtual thermostat, in order.
        public var rooms: [ClimateConfig.Room]
        /// Contact sensors listed in the Open Contact Sensors section.
        public var contactSensors: [ClimateConfig.ContactSensor]
    }
}

// MARK: - Lights, Food, Chores

public extension HouseConfig {
    /// The Custom Lights page (`CustomLightsConfig`).
    struct CustomLightsSection: Codable, Hashable, Sendable {
        /// The helper that turns manual control on or off.
        public var manualControlEntityId: String
        /// The lighting-mode select.
        public var modeEntityId: String
        /// The group of every light on the page.
        public var groupEntityId: String
        /// The section title above the lights.
        public var sectionTitle: String
        /// The lighting-mode picker's title.
        public var lightingModeTitle: String
        /// The mode that shows each light.
        public var customMode: String
        /// Modes used when the select reports no options.
        public var fallbackModes: [String]
        /// The lights, in order.
        public var lights: [CustomLightsConfig.Light]
    }

    /// The Food and Recipes hub (`FoodConfig`).
    struct FoodSection: Codable, Hashable, Sendable {
        /// The expiring-soon sensor.
        public var expiringSoonEntityId: String
        /// The total-items sensor.
        public var totalItemsEntityId: String
        /// The sensor listing expired items (the Your Summary sheet reads its `expired_list`).
        public var expiredItemsEntityId: String
        /// The storage places, in order.
        public var spaces: [FoodConfig.Space]
        /// The All Recipes tile tint.
        public var allRecipesTint: Tint
        /// The All Food tile tint.
        public var allFoodTint: Tint
    }

    /// One Chores tab quick link (`ChoresConfig.QuickLink`, whose colour is a bare tuple).
    struct ChoreQuickLink: Codable, Hashable, Sendable, Identifiable {
        /// The link's title.
        public var title: String
        /// The page it opens (`ChoresConfig.Page.id`).
        public var pageId: String
        /// The web card colour.
        public var tint: Tint
        /// Whether the subtitle counts grocery items.
        public var countsGroceries: Bool
        /// The resident whose link this is (a ``Resident`` key).
        public var resident: ChoresConfig.Resident?
        /// The page id.
        public var id: String { pageId }
    }

    /// Chores, groceries and the to-do pages (`ChoresConfig`).
    struct ChoresSection: Codable, Hashable, Sendable {
        /// The household's people, in order.
        public var people: [Person]
        /// The admin to-do list.
        public var adminTodoEntityId: String
        /// The grocery list.
        public var groceryEntityId: String
        /// The endpoint for admin to-dos with images.
        public var adminTodoUploadPath: String
        /// The empty-state text shown on vacation.
        public var vacationEmptyDescription: String
        /// Every page, keyed by its `id` route path.
        public var pages: [ChoresConfig.Page]
        /// The Chores tab quick links, in order.
        public var quickLinks: [ChoreQuickLink]
    }
}

// MARK: - Household, Media, Room devices

public extension HouseConfig {
    /// The household Settings pages (`HouseholdSettingsConfig`).
    struct HouseholdSection: Codable, Hashable, Sendable {
        /// Security control tiles on the Admin page.
        public var securityTiles: [HouseholdSettingsConfig.Tile]
        /// The relay-control-mode switch.
        public var relayControlEntityId: String
        /// Relay control tiles.
        public var relayTiles: [HouseholdSettingsConfig.Tile]
        /// Tiles that show or hide optional controls.
        public var showSpecificTiles: [HouseholdSettingsConfig.Tile]
        /// The automation that restores power after an outage.
        public var powerRecoveryAutomation: String
        /// Rooms in the presence-lighting grids, in order.
        public var presenceRooms: [HouseholdSettingsConfig.PresenceRoom]
        /// The high-AQI mode tile.
        public var highAqiTile: HouseholdSettingsConfig.Tile
        /// The vehicle page's tiles.
        public var vehicleTiles: [HouseholdSettingsConfig.Tile]
    }

    /// A media source-select remote's role constants and action graphs (`MediaRemotes.MusicRoom`): the ids, option names and timings
    /// the source tiles, the power buttons and the controller read by role. Keys are role names; values are the
    /// house's entity ids, options and seconds.
    struct SourceSelectRemote: Codable, Hashable, Sendable {
        /// Entity ids by role: `control`, `console`, `remote`, `volume`, `mediaSource`, `activeMediaSource`,
        /// `consoleHdmiStatus`, `syncPower`, `syncLightSync`, `syncBrightness`, `syncHdmiInput`, `syncMode`,
        /// `syncIntensity`.
        public var entityIds: [String: String]
        /// The sync box's HDMI status sensors, in port order.
        public var syncHdmiStatusEntityIds: [String]
        /// The source-select options by role: `launcher`, `off`, `server`, `tv`, `pc`, `console`.
        public var sources: [String: String]
        /// How long each optimistic value holds before reverting, in seconds, by role: `launcher`, `server`, `tv`,
        /// `pc`, `console`, `consoleOff`, `sync`.
        public var revertSeconds: [String: Double]
        /// How long the console keeps showing active after its live state drops, in seconds.
        public var activeHoldSeconds: Double
        /// Console states that count as active.
        public var activeStates: [String]
        /// The state the console's HDMI port reports while linked.
        public var linkedState: String
        /// The id of the remote (`media.remotes[].id`) these roles belong to. Optional: absent leaves it empty.
        public var remoteId: String?
        /// The scripts that choose a source, by role: `tvOn`, `tvOff`, `consoleOn`, `consoleOff`, `serverOn`, `pcOn`, `launcher`.
        public var commands: [String: MediaRemoteCommand]
        /// The tile actions built from those scripts and the source state, by role: `tvToggle`, `consoleToggle`,
        /// `consoleSourceToggle`, `serverToggle`, `pcToggle`, `launcher`.
        public var actions: [String: MediaRemoteAction]
    }

    /// The Media page and its remotes (`MediaPageConfig`, `MediaRemotes`).
    struct MediaSection: Codable, Hashable, Sendable {
        /// The Media page's rooms.
        public var pageSections: [MediaPageConfig.Section]
        /// Every remote.
        public var remotes: [MediaRemoteConfig]
        /// Which remote each media player opens.
        public var remoteIdByMediaPlayer: [String: String]
        /// The source-select remote's role constants.
        public var sourceSelect: SourceSelectRemote
        /// Devices powered through a script, each a power disc tracked by an `input_boolean` (`ScriptPowerActions`). Optional:
        /// absent means none.
        public var scriptPowerDevices: [ScriptPowerActions]?
    }

    /// Room devices (`BathroomFanConfig`, `AirPurifierConfig`, `HumidifierConfig`, `GrillConfig`).
    struct RoomDevicesSection: Codable, Hashable, Sendable {
        /// Bathroom fans.
        public var bathroomFans: [BathroomFanConfig]
        /// Air purifiers.
        public var airPurifiers: [AirPurifierConfig]
        /// Humidifiers.
        public var humidifiers: [HumidifierConfig]
        /// Grills.
        public var grills: [GrillConfig]
    }
}

// MARK: - Sprinklers, Vacation, Vacuums

public extension HouseConfig {
    /// The Sprinklers page (`SprinklersConfig`).
    struct SprinklersSection: Codable, Hashable, Sendable {
        /// The helper that shows the Sprinklers link on Home.
        public var visibilityEntityId: String
        /// At or below this battery percent a controller warns.
        public var lowBatteryPercent: Double
        /// A new start time's default (`HH:mm`).
        public var defaultStartTime: String
        /// The controllers, in order.
        public var controllers: [SprinklersConfig.Controller]
    }

    /// Vacation Mode (`Vacation`).
    struct VacationSection: Codable, Hashable, Sendable {
        /// The Vacation Mode switch.
        public var modeEntityId: String
        /// The flag raised when the saved dates are unusable.
        public var invalidDatesPendingEntityId: String
        /// The start date-time helper.
        public var startEntityId: String
        /// The end date-time helper.
        public var endEntityId: String
        /// The pre-vacation checklist, in order.
        public var checklist: [Vacation.ChecklistItem]
    }

    /// One `input_text` marker that reconciles a failed outcome room (`Vacuums.outcomeReconciliations`).
    struct VacuumReconciliation: Codable, Hashable, Sendable {
        /// The outcome room id.
        public var roomId: String
        /// The marker helper.
        public var entityId: String
    }

    /// Robot vacuums (`Vacuums`).
    struct VacuumsSection: Codable, Hashable, Sendable {
        /// Vacuums in page order.
        public var vacuums: [VacuumConfig]
        /// Auto-Clean tiles; they also order the vacuum tiles.
        public var autoCleanControls: [Vacuums.AutoCleanControl]
        /// Outcome reconciliation markers by `vacuumMapId`.
        public var outcomeReconciliations: [String: [VacuumReconciliation]]
    }
}

// MARK: - Bedroom, Rooms

public extension HouseConfig {
    /// The bedroom's wake light and beds (`MasterBedroom`).
    struct BedroomSection: Codable, Hashable, Sendable {
        /// The sensor that carries both sides' schedules.
        public var scheduleEntityId: String
        /// The MQTT topic that replaces one side's schedule.
        public var scheduleSetTopic: String
        /// The script that powers a side on or off through the hot-flash broker.
        public var hotFlashBrokerScript: String
        /// The Household Away status sensor.
        public var householdAwayEntityId: String
        /// The Household Away command script.
        public var householdAwayScript: String
        /// The wake light.
        public var wakeLight: WakeLightConfig
        /// The beds, left first.
        public var beds: [BedSideConfig]
    }

    /// The wake light's sheet and section names on a room page (`RoomsConfig.WakeLight`); its status entity is
    /// `bedroom.wakeLight.statusEntityId`.
    struct WakeLightPage: Codable, Hashable, Sendable {
        /// The sheet hash.
        public var sheet: String
        /// The card title.
        public var title: String
        /// The section title.
        public var sectionTitle: String
    }

    /// Room-page values shared between pages. Entity ids that other sections already hold (fans, humidifiers, garage
    /// doors, the wake light's status) are not repeated here.
    struct RoomShared: Codable, Hashable, Sendable {
        /// The sheet each bathroom fan opens, keyed by the fan's power entity id (`roomDevices.bathroomFans`).
        public var bathroomFanSheets: [String: String]
        /// The wake light's room-page names.
        public var wakeLightPage: WakeLightPage
        /// The dishwasher's program select, which marks the dishwasher card.
        public var dishwasherProgramEntityId: String
    }

    /// The Rooms grid (`RoomNavigation`).
    struct RoomGridSection: Codable, Hashable, Sendable {
        /// The script that counts a room visit.
        public var accessIncrementScript: String
        /// The grid tiles, in configured order.
        public var items: [RoomNavigationItem]
    }

    /// Room groups, pages, the grid and Quick Links (`RoomGroups`, `RoomsConfig`, `RoomNavigation`, `RoomOverview`,
    /// `QuickLinks`).
    struct RoomsSection: Codable, Hashable, Sendable {
        /// Every room's lights.
        public var lightGroups: [RoomGroup]
        /// Every room's temperatures and vents.
        public var climateGroups: [RoomGroup]
        /// Every room's presence sensors.
        public var occupancyGroups: [RoomGroup]
        /// Every room's doors and windows.
        public var contactGroups: [RoomGroup]
        /// The Air Quality sheet's rooms.
        public var airQualityRooms: [AirQualityRoom]
        /// The room pages, in order.
        public var pages: [RoomPage]
        /// Values shared between pages.
        public var shared: RoomShared
        /// The Rooms grid.
        public var grid: RoomGridSection
        /// The Quick Links tiles.
        public var quickLinks: [QuickLink]
    }
}
