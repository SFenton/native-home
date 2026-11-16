#if os(iOS) && DEBUG
import Foundation
import HassCore

// MARK: - Read-only record and schedule services

/// The services the production record, schedule and device providers take, answered from the preview's one connection for reads
/// and refused for everything else.
///
/// The production route hands these providers a session-fenced caller (``UKServerUISessionCaller``). The preview has no session,
/// so it hands the same providers this one instead: a to-do list and the schedules are plain websocket reads and pass through; every
/// service call, with or without a response, an admin to-do upload and a schedule update end in
/// ``UKServerUIPreviewLiveData/ReadOnlyCaller/reject()``, which counts the attempt and throws. A response-bearing service call is
/// refused too, because the connection cannot tell a read from a write by its name.
@MainActor
final class UKServerUIPreviewReadOnlyServices: HassServiceResponding, TodoServicing, HassScheduleStoring {
    private let connection: HassConnection
    private let caller: UKServerUIPreviewLiveData.ReadOnlyCaller

    /// - Parameters:
    ///   - connection: The preview's one connection; only its reads are used.
    ///   - caller: The rejecting caller that counts the refused writes for the receipt.
    init(connection: HassConnection, caller: UKServerUIPreviewLiveData.ReadOnlyCaller) {
        self.connection = connection
        self.caller = caller
    }

    // MARK: Refused

    func callService(_ domain: String, _ service: String, data: [String: any Sendable]) async throws {
        try await caller.callService(domain, service, data: data)
    }

    func callServiceWithResponse(_ domain: String, _ service: String, data: [String: any Sendable]) async throws -> JSONValue {
        try await caller.callServiceWithResponse(domain, service, data: data)
    }

    func callServiceForResponse(_ domain: String, _ service: String, data: [String: any Sendable]) async throws -> JSONValue {
        try await caller.callServiceWithResponse(domain, service, data: data)
    }

    /// A Data Flow's service call: the flow's only way to act, so the preview's flows read and never call.
    func rejectFlowCall() throws -> JSONValue {
        try caller.reject()
    }

    func uploadAdminTodo(_ upload: AdminTodoUpload, accessToken: String) async throws {
        try caller.reject()
    }

    func updateSchedule(_ message: [String: JSONValue]) async throws -> HassSchedule {
        try caller.reject()
    }

    // MARK: Reads

    func todoItems(entityId: String) async throws -> [TodoItem] {
        try await connection.todoItems(entityId: entityId)
    }

    func listSchedules() async throws -> [HassSchedule] {
        try await connection.listSchedules()
    }

    func userIsAdmin() async throws -> Bool {
        try await connection.userIsAdmin()
    }

    /// The record providers ask for a bearer to upload with; the preview never has one to give.
    func accessToken() async throws -> String {
        try caller.reject()
    }
}
#endif
