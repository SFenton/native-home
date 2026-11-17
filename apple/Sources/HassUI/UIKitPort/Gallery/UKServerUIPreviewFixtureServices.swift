#if os(iOS) && DEBUG
import Foundation
import HassCore
import Observation

// MARK: - Canonical fixture service adapters

/// Routes device intents to existing gallery doubles. There is no connection or credential path.
@MainActor
final class UKServerUIPreviewFixtureCaller: HassServiceResponding {
    private let pages: PageGalleryRecorder
    private let bedroom: BedroomGalleryRecorder
    private let away: VacationGalleryHouse
    private let isCurrent: () -> Bool
    /// The `failCalls` flag: every call answers with ``UKServerUIPreviewFault/callFailed`` and changes nothing.
    private let failsCalls: Bool

    init(store: EntityStore, failsCalls: Bool = false, isCurrent: @escaping () -> Bool) {
        self.failsCalls = failsCalls
        self.isCurrent = isCurrent
        pages = PageGalleryRecorder(store: store)
        bedroom = BedroomGalleryRecorder(store: store)
        away = VacationGalleryHouse(store: store)
    }

    func callService(_ domain: String, _ service: String, data: [String: any Sendable]) async throws {
        guard isCurrent() else { throw CancellationError() }
        if failsCalls { throw UKServerUIPreviewFault.callFailed }
        let target = data["entity_id"] as? String
        let bedTarget = MasterBedroom.beds.contains {
            [$0.alarmSnoozeButtonEntityId, $0.alarmStopButtonEntityId, $0.hotFlashButtonEntityId,
             $0.hotFlashCancelButtonEntityId, $0.targetLevelEntityId].contains(target ?? "")
                || [$0.tonightScript, $0.outsideScheduleScript].contains(service)
        }
        if bedTarget || domain == "mqtt" || (domain == "script" && service == MasterBedroom.hotFlashBrokerScript) {
            try await bedroom.callService(domain, service, data: data)
        } else if domain == "input_datetime" {
            try await away.callService(domain, service, data: data)
        } else {
            try await pages.callService(domain, service, data: data)
        }
    }

    func callServiceWithResponse(_ domain: String, _ service: String, data: [String: any Sendable]) async throws -> JSONValue {
        guard isCurrent() else { throw CancellationError() }
        if failsCalls { throw UKServerUIPreviewFault.callFailed }
        if domain == "wake_light", service == "command" {
            return try await bedroom.callServiceWithResponse(domain, service, data: data)
        }
        if domain == "script", service == MasterBedroom.householdAwayScript {
            return try await away.callServiceWithResponse(domain, service, data: data)
        }
        throw UKServerUIPreviewFixtureRecords.Failure.unsupportedService
    }
}

/// Canonical todo and inventory fixtures share the preview's entity boxes; unknown services fail explicitly.
@MainActor @Observable
final class UKServerUIPreviewFixtureRecords: TodoServicing {
    enum Failure: Error, LocalizedError {
        case unsupportedService
        var errorDescription: String? { "This service is not supported by the isolated gallery." }
    }
    let chores: ChoresFixtureService
    let inventory: EverShelfFixtureServer
    var isCurrent = true
    private let store: EntityStore
    private let listIDs: Set<String>
    private var completionScripts: Set<String> = []
    /// The `failCalls` flag: every call answers with ``UKServerUIPreviewFault/callFailed``.
    private let failsCalls: Bool

    /// - Parameters:
    ///   - empty: The `empty` flag: every list keeps its id and holds no item, and the inventory holds no row.
    ///   - failsCalls: The `failCalls` flag.
    init(store: EntityStore, empty: Bool = false, failsCalls: Bool = false) {
        self.store = store
        self.failsCalls = failsCalls
        let lists = ChoresFixtures.lists()
        listIDs = Set(lists.keys)
        chores = ChoresFixtureService(store: store, lists: empty ? lists.mapValues { _ in [] } : lists)
        inventory = EverShelfFixtureServer.sample()
        if empty { inventory.rows = [] }
        retainOtherEntities()
        store.apply(chores.entityStates())
    }

    /// The completion scripts the publication's todo collections name; the fixture answers only those.
    func allowCompletionScripts(from document: ServerUICompositionDocument) {
        completionScripts = Set(document.dataSources.flatMap { source -> [String] in
            guard case .todoCollection(_, let page) = source else { return [] }
            return page.lists.compactMap(\.completionScript)
        }.map { $0.hasPrefix("script.") ? String($0.dropFirst("script.".count)) : $0 })
    }

    private func retainOtherEntities() {
        chores.extraStates = store.allValues.values.filter { !listIDs.contains($0.entityId) }
    }

    func requireCurrent() throws {
        guard isCurrent else { throw CancellationError() }
    }

    func todoItems(entityId: String) async throws -> [TodoItem] {
        try requireCurrent()
        guard listIDs.contains(entityId) else { throw Failure.unsupportedService }
        return try await chores.todoItems(entityId: entityId)
    }

    func callService(_ domain: String, _ service: String, data: [String: any Sendable]) async throws {
        try requireCurrent()
        if failsCalls { throw UKServerUIPreviewFault.callFailed }
        if domain == "evershelf" { try await inventory.callService(domain, service, data: data); return }
        guard (domain == "todo" && ["update_item", "add_item", "remove_item"].contains(service))
                || (domain == "script" && completionScripts.contains(service)) else {
            throw Failure.unsupportedService
        }
        if domain == "todo", !listIDs.contains(data["entity_id"] as? String ?? "") { throw Failure.unsupportedService }
        retainOtherEntities()
        try await chores.callService(domain, service, data: data)
    }

    func callServiceForResponse(_ domain: String, _ service: String, data: [String: any Sendable]) async throws -> JSONValue {
        try requireCurrent()
        if failsCalls { throw UKServerUIPreviewFault.callFailed }
        if domain == "evershelf" { return try await inventory.callServiceForResponse(domain, service, data: data) }
        guard domain == "donetick", service == "get_task" else { throw Failure.unsupportedService }
        return try await chores.callServiceForResponse(domain, service, data: data)
    }

    func uploadAdminTodo(_ upload: AdminTodoUpload, accessToken: String) async throws {
        try requireCurrent()
        if failsCalls { throw UKServerUIPreviewFault.callFailed }
        guard listIDs.contains(upload.entityId) else { throw Failure.unsupportedService }
        retainOtherEntities()
        try await chores.uploadAdminTodo(upload, accessToken: accessToken)
    }
}
#endif
