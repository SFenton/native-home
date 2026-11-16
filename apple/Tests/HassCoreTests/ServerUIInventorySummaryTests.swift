import Testing
@testable import HassCore

// MARK: - Configured inventory behavior

@Suite struct ServerUIInventorySummaryTests {
    private let configuration = ServerUICompositionDocument.InventorySummary(
        totalEntityId: "sensor.demo_total", expiringEntityId: "sensor.demo_expiry",
        spaceEntityIds: ["sensor.demo_a", "sensor.demo_b"], singular: "Unit", plural: "Units",
        expiringSuffix: "Due", separator: " / ", loadingText: "Reading", unavailableText: "No stock data"
    )

    @Test func totalWinsWithoutReadingSpacesAndCopyUsesTheComputedSingular() {
        var reads: [String] = []
        let summary = ServerUIInventorySummary.text(configuration: configuration) { id in
            reads.append(id)
            return ["sensor.demo_total": "1.9", "sensor.demo_expiry": "2"][id]
        }
        #expect(summary == "1 Unit / 2 Due")
        #expect(reads == ["sensor.demo_total", "sensor.demo_expiry"])
    }

    @Test func zeroTotalSumsOnlyExplicitSpacesAndRequiresEverySelectedRead() {
        var states = ["sensor.demo_total": "0", "sensor.demo_expiry": "1", "sensor.demo_a": "2", "sensor.demo_b": "3"]
        #expect(ServerUIInventorySummary.text(configuration: configuration) { states[$0] } == "5 Units / 1 Due")
        states["sensor.demo_b"] = nil
        #expect(ServerUIInventorySummary.text(configuration: configuration) { states[$0] } == nil)
        states["sensor.demo_total"] = "6"
        #expect(ServerUIInventorySummary.text(configuration: configuration) { states[$0] } == "6 Units / 1 Due")
        states["sensor.demo_expiry"] = "unknown"
        #expect(ServerUIInventorySummary.text(configuration: configuration) { states[$0] } == nil)
        states["sensor.demo_total"] = nil
        #expect(ServerUIInventorySummary.text(configuration: configuration) { states[$0] } == nil)
    }

    @Test(arguments: ["", " ", "unknown", "unavailable", "NaN", "inf", "1e999", "-1", "9007199254740992", "1e30"])
    func invalidOrUnsafeCountsAreNotManufacturedZeros(_ text: String) {
        #expect(ServerUIInventorySummary.count(text) == nil)
    }

    @Test func sumOverflowFailsExplicitlyAndFiniteBoundaryIsSafe() {
        #expect(ServerUIInventorySummary.count("9007199254740991") == ServerUIInventorySummary.maximumCount)
        let states = ["sensor.demo_total": "0", "sensor.demo_expiry": "0",
                      "sensor.demo_a": "9007199254740991", "sensor.demo_b": "1"]
        #expect(ServerUIInventorySummary.text(configuration: configuration) { states[$0] } == nil)
    }

    @Test func spaceCounterDoesNotBorrowAWholeHouseExpiryCount() {
        let configuration = ServerUICompositionDocument.InventorySummary(totalEntityId: "sensor.demo_space", expiringEntityId: nil,
            spaceEntityIds: ["sensor.demo_space"], singular: "Item", plural: "Items", expiringSuffix: "Expiring",
            separator: " / ", loadingText: "Loading", unavailableText: "Unavailable")
        #expect(ServerUIInventorySummary.text(configuration: configuration) { $0 == "sensor.demo_space" ? "1" : nil } == "1 Item")
        #expect(ServerUIInventorySummary.text(configuration: configuration, state: { _ in nil }) == nil)
    }

    @Test func spaceExpiryUsesExplicitSensorAndCanonicalLocationNormalization() {
        var space = configuration
        space.expiringLocation = "frigo"
        let values = [
            "sensor.demo_total": EntityState(entityId: "sensor.demo_total", state: "2"),
            "sensor.demo_expiry": EntityState(entityId: "sensor.demo_expiry", state: "8", attributes: ["expiring_list": .array([
                .object(["location": .string("Fridge"), "days_remaining": .number(2)]),
                .object(["location": .string("Pantry"), "days_remaining": .number(1)]),
                .object(["location": .string("frigo"), "days_remaining": .number(9)]),
            ])]),
        ]
        #expect(ServerUIInventorySummary.text(configuration: space, entity: { values[$0] }) == "2 Units / 1 Due")
        #expect(ServerUIInventorySummary.text(configuration: space, entity: { _ in nil }) == nil)
    }
}
