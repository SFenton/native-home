import Foundation
import Observation

/// Inventory-owned adapter for a configured source. The host supplies the session's list model.
/// A card key is the catalog's lowercased-name identity, scoped to this source.
@MainActor
@Observable
public final class InventoryCompositionProvider {
    /// Summary projection is independent of the shared inventory screen's sort/filter draft.
    public enum Query: Sendable { case collection, expiredFoodSummary }
    /// An interaction was rejected before a service call.
    public enum Failure: Error, Equatable, Sendable {
        case wrongSource, wrongSpace, missingItem, unaddressable, invalidQuantity, changedItem, busy
        case commandFailed(String)
    }

    /// Captures the exact card presented to a person before a confirmation or quantity prompt.
    public struct Selection: Equatable, Sendable {
        public let item: InventoryDisplayItem
        public let space: InventorySpace
        public let sourceID: String
    }

    /// Sort and filter selections are temporary until explicitly applied.
    public struct Draft: Equatable, Sendable {
        public var sort: InventorySortMode
        public var direction: InventorySortDirection
        public var filter: InventoryFilterMode
    }

    public let sourceID: String
    public let model: InventoryListModel
    public let query: Query
    public private(set) var pendingKeys: Set<String> = []

    /// Rejects a model for a different configured space, rather than silently retargeting it.
    public init(sourceID: String, space: InventorySpace, model: InventoryListModel, query: Query = .collection) throws {
        guard model.space == space, query != .expiredFoodSummary || space == .allFood else { throw Failure.wrongSpace }
        self.sourceID = sourceID
        self.model = model
        self.query = query
    }

    public var items: [InventoryDisplayItem] {
        query == .expiredFoodSummary
            ? InventoryCatalog.visible(model.displayItems, sort: .expiry, direction: .ascending, filter: .expired, calendar: model.calendar)
                .filter { model.pendingRemoval[$0.id] == nil }
            : model.visibleItems
    }
    public var hasPendingIntent: Bool { !pendingKeys.isEmpty }
    public var draft: Draft { Draft(sort: model.sortMode, direction: model.sortDirection, filter: model.filterMode) }

    /// Applies a draft; discarding it requires no changes to the provider.
    public func apply(_ draft: Draft) {
        model.sortMode = draft.sort
        model.sortDirection = draft.direction
        model.filterMode = draft.filter
    }

    /// Obtains the current card by its stable key, not its index or display order.
    public func select(_ key: String) throws -> Selection {
        guard let item = model.displayItem(id: key) else { throw Failure.missingItem }
        return Selection(item: item, space: model.space, sourceID: sourceID)
    }

    /// Opens the canonical batch editor against the same session list model.
    public func editor(for selection: Selection) throws -> InventoryEditorModel {
        let item = try current(selection)
        return InventoryEditorModel(item: item, list: model)
    }

    /// Revalidates the confirmed card and quantity immediately before dispatch.
    /// The caller must present the canonical confirmation or quantity prompt first.
    /// - Parameter accepted: called once, before the service call, with whether the card leaves the list (see ``InventoryListModel/delete(_:quantity:accepted:)``).
    ///   A delete refused before the call (a changed card, a bad quantity, a busy card) never calls it: the caller learns from the thrown error.
    public func delete(_ selection: Selection, quantity: Double? = nil, accepted: ((Bool) -> Void)? = nil) async throws {
        let item = try current(selection)
        guard let rows = model.deletableRows(of: item) else { throw Failure.unaddressable }
        let total = rows.reduce(0) { $0 + $1.quantity }
        if let quantity, !quantity.isFinite || quantity < 1 || quantity > total {
            throw Failure.invalidQuantity
        }
        guard !model.deleting.contains(item.id), pendingKeys.insert(item.id).inserted else { throw Failure.busy }
        defer { pendingKeys.remove(item.id) }
        await model.delete(item, quantity: quantity, accepted: accepted)
        if let error = model.rowErrors[item.id] { throw Failure.commandFailed(error) }
    }

    /// Revalidates a shopping prompt and delegates to the canonical two-service action.
    public func addToShopping(_ selection: Selection, quantity: Double) async throws {
        let item = try current(selection)
        guard quantity.isFinite, quantity >= 1 else { throw Failure.invalidQuantity }
        guard model.shopping[item.id, default: .idle] == .idle,
              pendingKeys.insert(item.id).inserted else { throw Failure.busy }
        defer { pendingKeys.remove(item.id) }
        await model.addToShopping(item, quantity: quantity)
        if let error = model.rowErrors[item.id] { throw Failure.commandFailed(error) }
    }

    private func current(_ selection: Selection) throws -> InventoryDisplayItem {
        guard selection.sourceID == sourceID else { throw Failure.wrongSource }
        guard selection.space == model.space else { throw Failure.wrongSpace }
        guard let item = model.displayItem(id: selection.item.id) else { throw Failure.missingItem }
        guard item == selection.item else { throw Failure.changedItem }
        return item
    }
}
