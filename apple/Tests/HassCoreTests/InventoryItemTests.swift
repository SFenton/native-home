import Foundation
@testable import HassCore
import Testing

/// Lenient parsing of `list_inventory` rows, and the location/page enums.
struct InventoryItemTests {
    private func parse(_ fields: [String: JSONValue]) throws -> InventoryItem {
        try #require(InventoryItem(json: .object(fields)))
    }

    // MARK: Ids

    @Test func nonObjectsDoNotParse() {
        #expect(InventoryItem(json: .string("row")) == nil)
        #expect(InventoryItem(json: .array([])) == nil)
        #expect(InventoryItem(json: .null) == nil)
    }

    @Test func inventoryIdWinsOverId() throws {
        #expect(try parse(["inventory_id": .number(5), "id": .number(9)]).inventoryId == 5)
        #expect(try parse(["inventory_id": .string("12")]).inventoryId == 12)
        #expect(try parse(["inventory_id": .number(2.7)]).inventoryId == 2)
    }

    @Test func nullOrMissingInventoryIdFallsBackToId() throws {
        #expect(try parse(["inventory_id": .null, "id": .number(7)]).inventoryId == 7)
        #expect(try parse(["id": .string("8")]).inventoryId == 8)
        #expect(try parse([:]).inventoryId == nil)
    }

    @Test func nonPositiveInventoryIdDoesNotFallBack() throws {
        // JavaScript `??` only skips null/undefined, so a 0 stays and is rejected.
        #expect(try parse(["inventory_id": .number(0), "id": .number(3)]).inventoryId == nil)
        #expect(try parse(["inventory_id": .number(-1)]).inventoryId == nil)
        #expect(try parse(["inventory_id": .string("abc")]).inventoryId == nil)
        #expect(try parse(["inventory_id": .bool(true)]).inventoryId == nil)
        #expect(try parse(["inventory_id": .number(1e300)]).inventoryId == nil)
    }

    @Test func inventoryIdsKeepPositiveNumbers() throws {
        let item = try parse(["inventory_ids": .array([.number(1), .string("2"), .number(0), .number(-3), .string("x"), .null])])
        #expect(item.inventoryIds == [1, 2])
        #expect(try parse(["inventory_ids": .string("1,2")]).inventoryIds == [])
        #expect(try parse([:]).inventoryIds == [])
    }

    // MARK: Name and quantity

    @Test func nameIsTrimmedWithFallback() throws {
        #expect(try parse([:]).name == "Untitled item")
        #expect(try parse(["name": .string("   ")]).name == "Untitled item")
        #expect(try parse(["name": .null]).name == "Untitled item")
        #expect(try parse(["name": .string("  Milk \n")]).name == "Milk")
        #expect(try parse(["name": .number(42)]).name == "42")
    }

    @Test func quantityMustBePositive() throws {
        #expect(try parse(["quantity": .number(3)]).quantity == 3)
        #expect(try parse(["quantity": .string(" 2.5 ")]).quantity == 2.5)
        #expect(try parse(["quantity": .number(0)]).quantity == 1)
        #expect(try parse(["quantity": .number(-3)]).quantity == 1)
        #expect(try parse(["quantity": .string("abc")]).quantity == 1)
        #expect(try parse(["quantity": .number(.infinity)]).quantity == 1)
        #expect(try parse([:]).quantity == 1)
    }

    @Test func unitAndProduct() throws {
        let item = try parse(["unit": .string(" pz "), "product_id": .string("11")])
        #expect(item.unit == "pz")
        #expect(item.productId == 11)
        #expect(try parse(["unit": .string("")]).unit == nil)
        #expect(try parse(["product_id": .number(0)]).productId == nil)
    }

    // MARK: Location and expiry

    @Test func locationsAreStorageOnly() throws {
        #expect(try parse(["location": .string("frigo")]).location == .fridge)
        #expect(try parse(["location": .string(" dispensa ")]).location == .pantry)
        #expect(try parse(["location": .string("freezer")]).location == .freezer)
        #expect(try parse(["location": .string("spice_rack")]).location == .spiceRack)
        #expect(try parse(["location": .string("cabinet")]).location == .cabinet)
        #expect(try parse(["location": .string("altro")]).location == nil, "The library bucket is add-only")
        #expect(try parse(["location": .string("garage")]).location == nil)
        #expect(try parse([:]).location == nil)
    }

    @Test func expiryFallsBackThroughKeys() throws {
        #expect(try parse(["expiry_date": .string("2026-10-20"), "expiration_date": .string("2026-01-01")]).expiryDate == "2026-10-20")
        #expect(try parse(["expiry_date": .string("  "), "expiration_date": .string("2026-01-01")]).expiryDate == "2026-01-01")
        #expect(try parse(["expires_at": .string("2026-02-02T10:00:00Z")]).expiryDate == "2026-02-02T10:00:00Z")
        #expect(try parse([:]).expiryDate == nil)
    }

    // MARK: Flags

    static let preparedCases: [(JSONValue, Bool)] = [
        (.bool(true), true), (.bool(false), false), (.number(1), true), (.number(2), false), (.number(0), false),
        (.string("1"), true), (.string("true"), false), (.null, false), (.array([]), false),
    ]

    static let vacuumCases: [(JSONValue, Bool)] = [
        (.bool(true), true), (.bool(false), false), (.number(2), true), (.number(0), false),
        (.string("yes"), true), (.string("0"), false), (.string("FALSE"), false), (.string(" "), false), (.string(""), false),
        (.array([]), true), (.object([:]), true), (.null, false),
    ]

    @Test(arguments: InventoryItemTests.preparedCases)
    func preparedFlag(value: JSONValue, expected: Bool) throws {
        #expect(InventoryItem.isPreparedFlag(value) == expected)
        #expect(try parse(["prepared_food": value]).preparedFood == expected)
    }

    @Test(arguments: InventoryItemTests.vacuumCases)
    func vacuumFlag(value: JSONValue, expected: Bool) throws {
        #expect(InventoryItem.isTruthy(value) == expected)
        #expect(try parse(["vacuum_sealed": value]).vacuumSealed == expected)
    }

    @Test func flagsDefaultFalse() throws {
        let item = try parse([:])
        #expect(!item.preparedFood)
        #expect(!item.vacuumSealed)
    }

    // MARK: Search text and grouping

    @Test func searchTextJoinsNameBrandCategoryShoppingAndCanonicalTerms() throws {
        let item = try parse([
            "name": .string("Black Beans"), "brand": .string("ACME"), "category": .string("Legumes"),
            "shopping_name": .string("beans"),
            "canonical_ingredients": .array([
                .object(["name": .string("Black Bean"), "slug": .string("black-bean")]),
                .object(["role": .string(" ")]),
                .string("ignored"),
            ]),
        ])
        #expect(item.searchText == "black beans acme legumes beans black bean black-bean")
    }

    @Test func searchTextSkipsBlankFields() throws {
        let item = try parse(["name": .string("Eggs"), "brand": .string("  ")])
        #expect(item.searchText == "eggs")
    }

    @Test func directInitDefaults() {
        let item = InventoryItem(inventoryId: 3, name: "Whole Milk")
        #expect(item.quantity == 1)
        #expect(item.searchText == "whole milk")
        #expect(item.inventoryIds.isEmpty)
        #expect(item.unit == nil && item.location == nil && item.expiryDate == nil && item.productId == nil)
        #expect(!item.preparedFood && !item.vacuumSealed)
        let custom = InventoryItem(inventoryId: nil, name: "X", searchText: "custom")
        #expect(custom.searchText == "custom")
    }

    @Test func groupKeyIsLowercasedName() throws {
        #expect(try parse(["name": .string("Whole MILK")]).groupKey == "whole milk")
    }

    // MARK: Lenient JSON helpers

    @Test func looseAccessors() {
        #expect(JSONValue.number(2).finiteNumber == 2)
        #expect(JSONValue.string(" 2.5 ").finiteNumber == 2.5)
        #expect(JSONValue.bool(true).finiteNumber == nil)
        #expect(JSONValue.string("a").looseString == "a")
        #expect(JSONValue.number(2.5).looseString == "2.5")
        #expect(JSONValue.number(12).looseString == "12")
        #expect(JSONValue.null.looseString == nil)
        #expect(JSONValue.number(4).positiveInt == 4)
        #expect(JSONValue.number(.nan).positiveInt == nil)
        #expect(JSONValue.number(-.infinity).positiveInt == nil)
    }

    @Test func compactTrims() {
        #expect(InventoryItem.compact("  a ") == "a")
        #expect(InventoryItem.compact(" \n ") == nil)
    }

    // MARK: StorageLocation

    @Test func storageLocationProperties() {
        #expect(StorageLocation.allCases.count == 6)
        #expect(StorageLocation.storage == [.pantry, .fridge, .freezer, .spiceRack, .cabinet])
        #expect(!StorageLocation.storage.contains(.library))
        #expect(StorageLocation.pantry.rawValue == "dispensa")
        #expect(StorageLocation.fridge.id == "frigo")
        #expect(StorageLocation.library.rawValue == "altro")
        let titles = StorageLocation.allCases.map(\.title)
        #expect(titles == ["Pantry", "Fridge", "Freezer", "Spice Rack", "Cabinet", "Library"])
        #expect(StorageLocation.spiceRack.phrase == "spice rack")
        #expect(StorageLocation.library.phrase == "library")
    }

    // MARK: InventorySpace

    @Test func inventorySpaceProperties() {
        #expect(InventorySpace.allCases.count == 6)
        #expect(InventorySpace.allFood.id == "all-food")
        #expect(InventorySpace.spiceRack.rawValue == "spice-rack")
        #expect(InventorySpace.allCases.map(\.location) == [nil, .pantry, .fridge, .freezer, .spiceRack, .cabinet])
        #expect(InventorySpace.allCases.map(\.title) == ["All Food", "Pantry", "Fridge", "Freezer", "Spice Rack", "Cabinet"])
        #expect(InventorySpace.allFood.phrase == "library")
        #expect(InventorySpace.fridge.phrase == "fridge")
        #expect(InventorySpace.allCases.map(\.mdiIcon) == [
            "mdi:food-variant", "mdi:food-fork-drink", "mdi:fridge", "mdi:snowflake", "mdi:shaker-outline", "mdi:cupboard",
        ])
        #expect(InventorySpace.allFood.defaultScanLocation == .pantry)
        #expect(InventorySpace.freezer.defaultScanLocation == .freezer)
        #expect(!InventorySpace.allFood.hasOwnScanLocation)
        #expect(InventorySpace.cabinet.hasOwnScanLocation)
    }
}
