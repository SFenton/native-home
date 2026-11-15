import Foundation
import Observation

// MARK: - Authored custom-light session

/// Retains transport ownership and color debounce independently of mounted light controls.
@MainActor @Observable
public final class ServerUICustomLightsSource {
    /// A one-use ticket for a group-wide change, pinned to the group and members it was issued for.
    public struct Confirmation: Equatable, Sendable {
        /// What a confirmation applies to the whole group.
        public enum Action: Equatable, Sendable { case reset, applyColor(String, CustomLightsConfig.RGB) }
        /// The group action the ticket confirms.
        public let action: Action
        fileprivate let group: String
        fileprivate let members: [String]
    }

    /// The validated group, palettes and reset policy.
    public let settings: CustomLightsSettings
    /// The store the group's lights are read from.
    public let store: EntityStore
    /// Fixed copy for the last rejected or failed change, or `nil`.
    public private(set) var error: String?
    /// Service calls in flight.
    public private(set) var pendingCalls = 0
    private var editing: Set<String> = []
    private var queued: Set<String> = []
    @ObservationIgnored private let caller: any HassServiceCalling
    @ObservationIgnored private var colorTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var lights: [String: ServerUIHomeLightSource] = [:]
    @ObservationIgnored private var idleWaiters: [CheckedContinuation<Void, Never>] = []

    /// Creates the session over one store and transport.
    public init(settings: CustomLightsSettings, store: EntityStore, caller: any HassServiceCalling) {
        self.settings = settings
        self.store = store
        self.caller = caller
        for light in settings.lights {
            lights[light.entityId] = ServerUIHomeLightSource(entityId: light.entityId, caller: caller) { store.entity(light.entityId).state }
        }
    }

    // MARK: - Group state

    /// Whether a call, debounce, gesture or light intent forbids replacing this source.
    public var protectsPublication: Bool {
        pendingCalls > 0 || !queued.isEmpty || !editing.isEmpty || lights.values.contains { $0.hasPendingIntent }
    }
    /// Suspends until no call is in flight and no color is waiting out its debounce, then returns.
    public func waitForCalls() async {
        if pendingCalls == 0 && queued.isEmpty { return }
        await withCheckedContinuation { idleWaiters.append($0) }
    }

    /// Wakes `waitForCalls()` once the source is idle.
    private func settle() {
        guard pendingCalls == 0, queued.isEmpty, !idleWaiters.isEmpty else { return }
        let waiters = idleWaiters
        idleWaiters = []
        waiters.forEach { $0.resume() }
    }
    /// The manual-control switch's state.
    public var manual: EntityState? { store.entity(settings.manualEntityId).state }
    /// The mode selector's state.
    public var mode: EntityState? { store.entity(settings.modeEntityId).state }
    /// Whether manual control is on and the custom mode is selected.
    public var isCustom: Bool { manual?.state == "on" && mode?.state == settings.customMode && mode?.isUnavailable == false }
    /// The modes the selector offers.
    public var modes: [String] { settings.modes(mode) }
    /// The colors representing the current mode.
    public var swatch: [CustomLightsConfig.RGB] {
        settings.swatch(for: mode?.state ?? "", custom: settings.lights.compactMap { CustomLightsConfig.RGB(entity: store.entity($0.entityId).state) })
    }
    /// The per-light source for `entityId`, or `nil` for a light outside the group.
    public func light(_ entityId: String) -> ServerUIHomeLightSource? { lights[entityId] }
    /// Whether `entityId` is in the group, available and in custom mode.
    public func canEdit(_ entityId: String) -> Bool {
        isCustom && lights[entityId] != nil && store.entity(entityId).state?.isUnavailable == false
    }
    /// Marks a gesture on `id` as active so a publication cannot replace the source mid-drag.
    public func setEditing(_ id: String, _ active: Bool) {
        if active { editing.insert(id) } else { editing.remove(id) }
    }

    // MARK: - Changes

    /// Turns manual control on or off. Returns whether the call was accepted and succeeded.
    @discardableResult
    public func setManual(_ enabled: Bool) async -> Bool {
        guard manual?.isUnavailable == false else { return reject() }
        return await send(settings.setManual(on: enabled))
    }
    /// Selects a mode the selector currently offers. Returns whether the call succeeded.
    @discardableResult
    public func selectMode(_ option: String) async -> Bool {
        guard manual?.state == "on" else { return reject() }
        do { return await send(try settings.selectMode(option, offeredBy: mode)) }
        catch { return reject() }
    }
    /// Resets one editable light to the configured reset color. Returns whether the call succeeded.
    @discardableResult
    public func resetLight(_ id: String) async -> Bool {
        guard canEdit(id), let light = settings.lights.first(where: { $0.entityId == id }) else { return reject() }
        do { return await send(try settings.resetLight(light)) }
        catch { return reject() }
    }
    /// Copies one light's color to another. Both must be editable and the target must support color.
    @discardableResult
    public func copyColor(from sourceId: String, to targetId: String) async -> Bool {
        guard canEdit(sourceId), canEdit(targetId), sourceId != targetId,
              CustomLightsConfig.supportsColor(store.entity(targetId).state),
              let color = CustomLightsConfig.RGB(entity: store.entity(sourceId).state) else { return reject() }
        return await send(CustomLightsConfig.setColor(color, on: targetId))
    }

    /// The pending value is pinned immediately; a timer never follows a later source publication.
    public func setColor(_ color: CustomLightsConfig.RGB, on id: String) {
        guard canEdit(id), valid(color), CustomLightsConfig.supportsColor(store.entity(id).state) else { _ = reject(); return }
        colorTasks[id]?.cancel()
        queued.insert(id)
        colorTasks[id] = Task { @MainActor [self] in
            do { try await Task.sleep(for: .milliseconds(250)) } catch is CancellationError { return }
            catch { queued.remove(id); _ = reject(); settle(); return }
            colorTasks[id] = nil
            guard canEdit(id), CustomLightsConfig.supportsColor(store.entity(id).state) else {
                queued.remove(id); _ = reject(); settle(); return
            }
            // Count the call before releasing the debounce hold.
            pendingCalls += 1
            queued.remove(id)
            _ = await send(CustomLightsConfig.setColor(color, on: id), counted: true)
        }
    }

    /// Issues a ticket for a group-wide action, or `nil` while the group is unavailable or the color changed.
    public func confirmation(_ action: Confirmation.Action) -> Confirmation? {
        guard isCustom, store.entity(settings.groupEntityId).state?.isUnavailable == false else { return nil }
        if case .applyColor(let id, let color) = action {
            guard canEdit(id), valid(color), CustomLightsConfig.RGB(entity: store.entity(id).state) == color else { return nil }
        }
        return Confirmation(action: action, group: settings.groupEntityId, members: settings.lights.map(\.entityId))
    }
    /// Applies a ticket after revalidating it against the live group.
    @discardableResult
    public func confirm(_ ticket: Confirmation) async -> Bool {
        guard confirmation(ticket.action) == ticket else { return reject() }
        switch ticket.action {
        case .reset: return await send(settings.resetGroup())
        case .applyColor(_, let color): return await send(CustomLightsConfig.setColor(color, on: ticket.group))
        }
    }

    private func valid(_ value: CustomLightsConfig.RGB) -> Bool {
        [value.red, value.green, value.blue].allSatisfy { (0...255).contains($0) }
    }
    private func reject() -> Bool { error = "The lights changed or are unavailable. Try again."; return false }
    private func send(_ call: ServiceCall, counted: Bool = false) async -> Bool {
        if !counted { pendingCalls += 1 }
        defer { pendingCalls -= 1; settle() }
        error = nil
        do { try await caller.call(call); return true }
        catch { self.error = "Couldn't change lights. Check the connection and try again."; return false }
    }
}
