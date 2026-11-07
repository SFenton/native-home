import Foundation

/// Everything the app knows about one house, as a single document (schema 2).
///
/// House data (entity ids, room lists, people, titles, icons, colours, order) lives on the server, which serves this
/// document (`build/decisions/house-config-runtime.md`); the app holds none of it. A change to the house is a
/// server-side edit of the document, not an app change.
///
/// The types are generic: no house names appear in a type or property name. Each section reuses the value types the
/// screens already use (made `Codable`), so a decoded section drops straight into the code that reads the `*Config`
/// facades, which answer empty values when there is no document.
///
/// Intentionally not mirrored, because they are not house data and stay in code:
/// - behaviour: state rules, service builders, tone and colour functions, optimistic-revert timings of the
///   page controllers (`SprinklersConfig.optimisticRevert`, the wake light's `revert`);
/// - prose: section paragraphs, empty-state, error and warning text, tab and sheet titles that the app words
///   (`ClimateConfig.Copy`, `HouseholdSettingsConfig` copy, `Vacation.Copy`);
/// - app-owned titles and colours: alarm mode titles and colours, the vehicle page's `pageTitle` and
///   `sectionTitle`, `ClimateConfig.Tab` names and icons, `FoodConfig` hub copy.
///
/// Titles and colours that name a house thing (a room, a camera, a tile, a chip) are mirrored through the value
/// types that carry them.
public struct HouseConfig: Codable, Equatable, Sendable {
    /// The newest document ``schema`` this build understands. Schema 1 is no longer read: every server has been
    /// re-uploaded as schema 2.
    public static let supportedSchema = 2

    /// The largest encoded document the server accepts, in bytes (`HOUSE_CONFIG_MAX_BYTES`,
    /// `SFenton/ha-fenton-home#13`). The demo-house exporter (`tools/`, `DemoHouse`) writes compact JSON so the file stays under it.
    public static let serverByteLimit = 256 * 1024

    // MARK: - Document

    /// The document's schema version: always ``supportedSchema`` once decoded. A
    /// newer one than ``supportedSchema`` is refused by ``decode(_:)``.
    public var schema: Int
    /// The Home page: status chips, weather, guest toggles and cameras.
    public var home: HomeSection
    /// The Security page: alarm, locks, garage and vehicle tiles.
    public var security: SecuritySection
    /// The Climate page: whole-home entities, rooms and contact sensors.
    public var climate: ClimateSection
    /// The Custom Lights page.
    public var customLights: CustomLightsSection
    /// The Food and Recipes hub.
    public var food: FoodSection
    /// Chores, groceries and to-do pages, and the people behind them.
    public var chores: ChoresSection
    /// The household Settings pages: admin tiles, presence rooms and the vehicle page.
    public var household: HouseholdSection
    /// The Media page and every media remote.
    public var media: MediaSection
    /// Bathroom fans, air purifiers, humidifiers and grills.
    public var roomDevices: RoomDevicesSection
    /// The Sprinklers page.
    public var sprinklers: SprinklersSection
    /// Vacation Mode helpers and checklist.
    public var vacation: VacationSection
    /// Robot vacuums and their auto-clean switches.
    public var vacuums: VacuumsSection
    /// The bedroom: wake light and beds.
    public var bedroom: BedroomSection
    /// Room groups, room pages, the room grid and Quick Links.
    public var rooms: RoomsSection

    /// Creates a document from its sections.
    public init(
        schema: Int = HouseConfig.supportedSchema, home: HomeSection, security: SecuritySection, climate: ClimateSection,
        customLights: CustomLightsSection, food: FoodSection, chores: ChoresSection, household: HouseholdSection,
        media: MediaSection, roomDevices: RoomDevicesSection, sprinklers: SprinklersSection, vacation: VacationSection,
        vacuums: VacuumsSection, bedroom: BedroomSection, rooms: RoomsSection
    ) {
        self.schema = schema
        self.home = home
        self.security = security
        self.climate = climate
        self.customLights = customLights
        self.food = food
        self.chores = chores
        self.household = household
        self.media = media
        self.roomDevices = roomDevices
        self.sprinklers = sprinklers
        self.vacation = vacation
        self.vacuums = vacuums
        self.bedroom = bedroom
        self.rooms = rooms
    }

    // MARK: - Errors

    /// Why a document could not be used.
    public enum DecodeError: Error, Equatable, Sendable {
        /// The document's `schema` is newer than this build understands; the app should keep its own values.
        case unsupportedSchema(found: Int, supported: Int)
        /// The data is not a valid document (not JSON, a missing section or a wrong type).
        case malformed(String)
    }

    /// The oldest schema version this app reads: a decoded document below it is refused (``DecodeError``) and the app
    /// fetches again. The server is unchanged and stores any integer schema.
    public static let minimumSchema = 2

    // MARK: - Coding

    /// Reads a document from JSON, ignoring keys it does not know.
    ///
    /// The `schema` is checked first, so a document written by a newer server is refused with
    /// ``DecodeError/unsupportedSchema(found:supported:)`` even when its sections have changed shape.
    /// - Parameter data: The JSON document.
    /// - Throws: ``DecodeError``, including `malformed` when a role-keyed map lacks a role the app reads (``validateRoles()``).
    public static func decode(_ data: Data) throws -> HouseConfig {
        let decoder = JSONDecoder()
        let probe: SchemaProbe
        do {
            probe = try decoder.decode(SchemaProbe.self, from: data)
        } catch {
            throw DecodeError.malformed(String(describing: error))
        }
        guard probe.schema >= minimumSchema else {
            throw DecodeError.malformed("schema must be \(minimumSchema) or newer, found \(probe.schema)")
        }
        guard probe.schema <= supportedSchema else {
            throw DecodeError.unsupportedSchema(found: probe.schema, supported: supportedSchema)
        }
        let config: HouseConfig
        do {
            config = try decoder.decode(HouseConfig.self, from: data)
        } catch {
            throw DecodeError.malformed(String(describing: error))
        }
        try config.validateRoles()
        return config
    }

    /// The document as compact JSON with sorted keys, the form the server stores.
    ///
    /// The bytes are deterministic: every dictionary encodes as a keyed object (enum keys are
    /// `CodingKeyRepresentable`), keys are sorted, and no value depends on process state. The server hashes
    /// these bytes to tell subscribers when the house changed, so an unstable encoding would fire spurious
    /// pushes. Compact output keeps the file under ``serverByteLimit``.
    /// - Throws: An encoding error, which does not occur for the shipped value types.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    /// Just the version, so it can be read before the rest of a document is trusted.
    private struct SchemaProbe: Decodable {
        var schema: Int
    }
}
