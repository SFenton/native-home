import Foundation
@testable import HassCore
import Testing

// MARK: - A device fact degrades a node, never rejects the document

/// Device gaps (a symbol this OS lacks, a chrome priority or rail it does not honour, a shared group before glass) are not document
/// validity. Each degrades the node and is reported; the publication still commits.
@Suite(.serialized) struct ServerUIDeviceFactsTests {
    typealias D = ServerUICompositionDocument

    private let older = ServerUIDeviceFacts(hasGlass: false, supportsPriority: false, supportsHorizontalOnlyRail: false,
                                            drawsSymbol: { $0 != "demo.symbol.that.does.not.exist" })

    private func group(horizontal: String, priority: String = "normal", rail: String = "eligible") throws -> D.ChromeGroup {
        var json = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: fixtureURL))
        let path = ["document", "navigation", "chrome", "groups", "0"]
        func set(_ value: JSONValue, _ keys: [String]) {
            func walk(_ node: JSONValue, _ keys: ArraySlice<String>) -> JSONValue {
                guard let key = keys.first else { return value }
                switch node {
                case .object(var object): object[key] = walk(object[key] ?? .null, keys.dropFirst()); return .object(object)
                case .array(var array):
                    let index = Int(key) ?? 0
                    array[index] = walk(array[index], keys.dropFirst()); return .array(array)
                default: return node
                }
            }
            json = walk(json, keys[...])
        }
        set(.string(horizontal), path + ["horizontal"])
        set(.string(priority), path + ["items", "1", "priority"])
        set(.string(rail), path + ["items", "1", "rail"])
        return try ServerUICompositionPublication.decode(JSONEncoder().encode(json)).document.navigation.chrome.groups[0]
    }

    private var fixtureURL: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("ServerUICompositionFixture.json") }

    // MARK: Symbols

    @Test func aSymbolTheOSLacksDrawsTheFallbackAndOneItHasDrawsItself() {
        #expect(older.symbol("demo.symbol.that.does.not.exist") == ServerUIDeviceFacts.fallbackSymbol)
        #expect(older.symbol("house") == "house")
        #expect(ServerUIDeviceFacts.unrestricted.symbol("demo.symbol.that.does.not.exist") == "demo.symbol.that.does.not.exist")
    }

    @Test func aMissingSymbolIsADegradeAtItsPointerAndAPresentOneIsNot() {
        #expect(older.degradation(symbol: "demo.symbol.that.does.not.exist", at: "/p/icon/name") == ServerUIDegradation(.symbol, at: "/p/icon/name"))
        #expect(older.degradation(symbol: "house", at: "/p/icon/name") == nil)
    }

    @Test func theCoreSymbolNameIsTheAuthoredNameWhateverTheDeviceDraws() throws {
        let symbol = try ServerUICompositionPublication.decode(Data(contentsOf: fixtureURL)).document.navigation.tabs[0].icon
        let before = symbol.name
        // Core reads no process-global: facts only change an answer when a caller asks them (`older.symbol`), never `Symbol.name`.
        #expect(older.symbol("demo.symbol.that.does.not.exist") == ServerUIDeviceFacts.fallbackSymbol)
        #expect(symbol.name == before)
        let missing = D.Symbol(name: "demo.symbol.that.does.not.exist", rendering: .canonical, unavailable: .fallback)
        #expect(missing.name == "demo.symbol.that.does.not.exist")
    }

    // MARK: Chrome

    @Test func priorityAndRailActAsNormalBelowTheirOSes() {
        #expect(older.priority(.required) == .normal && older.priority(.low) == .normal)
        #expect(older.rail(.horizontalOnly) == .eligible)
        #expect(ServerUIDeviceFacts.unrestricted.priority(.low) == .low)
        #expect(ServerUIDeviceFacts.unrestricted.rail(.horizontalOnly) == .horizontalOnly)
    }

    @Test func aSharedGroupActsAsSeparateBeforeGlassOnly() {
        #expect(older.horizontal(.shared) == .separateCircles)
        #expect(older.horizontal(.separateCircles) == .separateCircles)
        #expect(ServerUIDeviceFacts.unrestricted.horizontal(.shared) == .shared)
    }

    @Test func eachChromeGapIsReportedWithItsPointer() throws {
        let value = try group(horizontal: "shared@1", priority: "low", rail: "horizontal-only")
        let found = older.degradations(groups: [value], at: "/g")
        #expect(found == [ServerUIDegradation(.sharedGroup, at: "/g/0/horizontal"),
                          ServerUIDegradation(.priority, at: "/g/0/items/1/priority"),
                          ServerUIDegradation(.rail, at: "/g/0/items/1/rail")])
        #expect(ServerUIDeviceFacts.unrestricted.degradations(groups: [value], at: "/g").isEmpty)
    }

    @Test func aGroupThatAsksForNothingExtraReportsNothing() throws {
        let value = try group(horizontal: "separate-circles@1")
        #expect(older.degradations(groups: [value], at: "/g").isEmpty)
    }

    @Test func aDegradeDescribesItselfWithKindAndPointerOnly() {
        #expect(ServerUIDegradation(.sharedGroup, at: "/x").description == "degraded_shared_group at /x")
    }
}
