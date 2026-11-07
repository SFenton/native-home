import Foundation
@testable import HassCore
import HassTestSupport
import Testing

/// The synthetic house tests, fixtures and the gallery read instead of the real one.
///
/// The privacy tests check **structure only**: ids match a pattern, people come from a fixed set, free text uses a neutral
/// vocabulary. They never hold a list of real values.
@MainActor
struct DemoHouseTests {
    // MARK: - Shape

    @Test func decodesThroughTheServerPathAndStaysUnderTheLimit() throws {
        let data = try DemoHouse.config.encoded()
        #expect(data.count < HouseConfig.serverByteLimit)
        #expect(DemoHouse.encodedByteCount == data.count)
        #expect(try HouseConfig.decode(data) == DemoHouse.config)
        #expect(DemoHouse.config.schema == HouseConfig.supportedSchema)
    }

    @Test func carriesEveryRoleTheAppReads() {
        let select = DemoHouse.config.media.sourceSelect
        #expect(HouseConfig.SourceSelectRemote.requiredEntityRoles.isSubset(of: Set(select.entityIds.keys)))
        #expect(HouseConfig.SourceSelectRemote.requiredSourceRoles.isSubset(of: Set(select.sources.keys)))
        #expect(HouseConfig.SourceSelectRemote.requiredRevertRoles.isSubset(of: Set(select.revertSeconds.keys)))
    }

    @Test func populatesEverySection() throws {
        let data = try DemoHouse.config.encoded()
        let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let sections = ["home", "security", "climate", "customLights", "food", "chores", "household", "media",
                        "roomDevices", "sprinklers", "vacation", "vacuums", "bedroom", "rooms"]
        for name in sections {
            let section = try #require(root[name] as? [String: Any], "missing section \(name)")
            #expect(!section.isEmpty, "empty section \(name)")
            for (key, value) in section {
                #expect(!isEmpty(value), "\(name).\(key) is empty")
            }
        }
    }

    @Test func keepsTheShapesTheAppExercises() {
        let config = DemoHouse.config
        #expect(config.security.garageDoors.count >= 2)
        #expect(config.bedroom.beds.count == 2)
        #expect(config.vacuums.vacuums.count >= 2)
        #expect(config.sprinklers.controllers.count >= 2)
        #expect(!config.home.cameras.isEmpty)
        #expect(config.media.remotes.count >= 2)
    }

    // MARK: - Privacy (structure only)

    /// Every string in the document, dictionary keys included, with the key it sits under (`""` for a key itself).
    private func strings() throws -> [(key: String, text: String)] {
        let root = try JSONSerialization.jsonObject(with: DemoHouse.config.encoded())
        var found: [(String, String)] = []
        func walk(_ node: Any, _ key: String) {
            if let text = node as? String {
                found.append((key, text))
            } else if let list = node as? [Any] {
                list.forEach { walk($0, key) }
            } else if let object = node as? [String: Any] {
                for (name, value) in object {
                    found.append(("", name))
                    walk(value, name)
                }
            }
        }
        walk(root, "")
        return found
    }

    private func dottedStrings() throws -> [String] {
        try strings().map(\.text).filter { $0.range(of: #"^[a-z_]+\.[a-z0-9_]+$"#, options: .regularExpression) != nil }
    }

    @Test func everyEntityIdIsSyntheticWhetherKeyOrValue() throws {
        let dotted = try dottedStrings()
        #expect(dotted.count > 300)
        for id in dotted {
            #expect(id.range(of: #"^[a-z_]+\.demo_[a-z0-9_]+$"#, options: .regularExpression) != nil, "not synthetic: \(id)")
        }
    }

    @Test func peopleAreTheDemoPeople() {
        let people = DemoHouse.config.chores.people
        #expect(!people.isEmpty)
        #expect(Set(people.map(\.name)).isSubset(of: ["Alex", "Sam", "Jordan"]))
        // The keys are neutral resident ids.
        #expect(Set(people.map(\.key)).isSubset(of: Set(["resident_1", "resident_2"])))
        #expect(people.allSatisfy { $0.haUserId.hasPrefix("demo-user-") })
    }

    @Test func freeTextTitlesUseOnlyNeutralWords() throws {
        let titleKeys: Set<String> = [
            "title", "label", "room", "roomTitle", "name", "section", "mapName", "sectionTitle", "remoteTitle",
            "volumeTitle", "emptyTitle", "modalTitle", "appSectionTitle", "lightingModeTitle",
        ]
        let words = try strings().filter { titleKeys.contains($0.key) }.flatMap {
            $0.text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        }
        #expect(words.count > 300)
        let unknown = Set(words).subtracting(Self.neutralWords)
        #expect(unknown.isEmpty, "words outside the neutral set: \(unknown.sorted())")
    }

    @Test func holdsNoHostAddressOrIdentifier() throws {
        let text = try strings().map(\.text).joined(separator: "\n")
        #expect(text.range(of: #"[0-9a-f]{32}"#, options: .regularExpression) == nil)
        #expect(text.range(of: #"\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b"#, options: .regularExpression) == nil)
        #expect(text.range(of: #"://|\.local\b|\.ts\.net"#, options: .regularExpression) == nil)
    }

    /// The words a free-text title may use: generic rooms, roles, devices and the demo people.
    private static let neutralWords: Set<String> = [
        "1", "2", "3", "4", "5", "6", "a", "admin", "afternoon", "air", "alarms", "alex", "and", "any", "app", "appliances",
        "aqi", "auto", "b", "back", "backyard", "bar", "bathroom", "bed", "bedroom", "boost", "brush", "c", "cabinet",
        "charge", "check", "chores", "clean", "climate", "closet", "computer", "computers", "console", "contact", "control",
        "couch", "couches", "counter", "custom", "d", "date", "deck", "detergent", "devices", "dining", "dishwasher", "do",
        "door", "doors", "down", "downstairs", "drain", "driver", "driveway", "dryer", "due", "dustbag", "e", "entry",
        "entryway", "evening", "f", "fan", "faucet", "faucets", "filter", "fireplace", "floodlight", "floor", "flush", "food",
        "freezer", "fresh", "fridge", "front", "fuel", "game", "garage", "grill", "groceries", "grocery", "guest", "gym",
        "hallway", "handheld", "high", "holiday", "home", "humidifier", "improvement", "keep", "keyboard", "kitchen",
        "kitchenette", "launch", "left", "level", "light", "lighting", "lights", "list", "listed", "living", "lock", "lower",
        "machine", "main", "make", "media", "menu", "mode", "morning", "mute", "nightstand", "no", "north", "occupancy",
        "off", "office", "out", "outdoor", "pantry", "passenger", "past", "path", "pause", "pc", "play", "power", "presence",
        "probe", "projector", "purifier", "quality", "quick", "rack", "rear", "receiver", "recipes", "relay", "remote",
        "right", "robot", "room", "rooms", "s", "sam", "screen", "seat", "security", "select", "sensors", "server", "side",
        "sink", "sleep", "smoke", "soundbar", "speaker", "spice", "sprinklers", "status", "streamer", "streaming", "studio",
        "system", "table", "take", "tasks", "the", "time", "to", "today", "towel", "trash", "turn", "tv", "unassigned",
        "unload", "up", "upcoming", "upper", "vacuum", "vacuums", "vent", "vents", "volume", "wake", "wall", "warm",
        "washing", "waste", "water", "wheels", "window", "windows", "yard",
    ]

    // MARK: - Seed and scope

    @Test func seedsAStateForEveryIdInTheDocument() throws {
        // Derived by walking the document, not from the list the seed was built from.
        let expected = Set(try dottedStrings())
        #expect(expected.count > 300)
        let store = EntityStore()
        DemoHouse.seed(store)
        #expect(store.hasReceivedFirstState)
        for id in expected { #expect(store.value(id) != nil, "no state for \(id)") }
        #expect(Set(store.allValues.keys) == expected)
        #expect(expected.contains { $0.hasPrefix("schedule.") })
        #expect(store.value(DemoHouse.config.security.entryLockEntityId)?.state == "locked")
    }

    @Test func scopesFacadesToTheDemoHouse() {
        let demoAlarm = DemoHouse.config.security.alarmEntityId
        let seen = HouseConfigSource.$scoped.withValue(DemoHouse.source) { SecurityConfig.alarmEntityId }
        #expect(seen == demoAlarm)
        let unscoped = HouseConfigSource.$scoped.withValue(HouseConfigSource()) { SecurityConfig.alarmEntityId }
        #expect(unscoped.isEmpty, "Without a document the facade answers empty, never house data")
    }

    private func isEmpty(_ value: Any) -> Bool {
        if let list = value as? [Any] { return list.isEmpty }
        if let object = value as? [String: Any] { return object.isEmpty }
        if let text = value as? String { return text.isEmpty }
        return false
    }
}
