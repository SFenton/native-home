import Foundation
import Observation

// MARK: - Injected remote interaction

/// One controller's local keyboard and gesture lifetime. No configuration lookup, transport, or state cache.
@MainActor
@Observable
public final class ServerUIRemoteSession {
    /// The authored interaction error choices.
    public enum InteractionError: Error, Equatable {
        case unavailable, unknownControl, blankText, busy
    }

    public let controller: MediaRemoteController
    public private(set) var keyboardTarget: String?
    public var keyboardText = ""
    public private(set) var keyboardSending = false
    public private(set) var keyboardFailed = false
    public private(set) var editingControls: Set<String> = []

    /// Creates a server uiremote session.
    public init(controller: MediaRemoteController) { self.controller = controller }

    /// Publications cannot remove or retarget a source while it owns a draft, gesture or actual call.
    public var hasInteraction: Bool {
        keyboardTarget != nil || keyboardSending || !editingControls.isEmpty || controller.pendingCallCount > 0 ||
            !controller.overlay.pending.isEmpty || !controller.volumeOverlay.pending.isEmpty
    }

    /// Tells the session the control is being edited, so a live update does not overwrite the edit in progress.
    public func setEditing(_ editing: Bool, controlID: String) {
        if editing { editingControls.insert(controlID) } else { editingControls.remove(controlID) }
    }

    /// Resolves only a native descriptor's known slot. Authored copy cannot alter the command.
    public func button(_ slot: ServerUICompositionDocument.RemoteSlot) -> MediaRemoteButton? {
        let c = controller.config
        switch slot {
        case .power: return c.power
        case .up: return c.up
        case .left: return c.left
        case .select: return c.select
        case .right: return c.right
        case .down: return c.down
        case .back: return c.back
        case .home: return c.home
        case .keyboard: return c.keyboard
        case .pause: return c.pause
        case .play: return c.play
        case .volumeDown: return c.volumeDown
        case .volumeMute: return c.volumeMute
        case .volumeUp: return c.volumeUp
        }
    }

    /// Whether the remote slot is available in the current device state.
    public func isEnabled(_ slot: ServerUICompositionDocument.RemoteSlot) -> Bool {
        guard button(slot) != nil else { return false }
        switch slot {
        case .power: return true
        case .volumeDown, .volumeMute, .volumeUp: return !controller.volumeDisabled
        case .keyboard: return !controller.controlsDisabled && !controller.hidesKeyboard && !keyboardSending
        default: return !controller.controlsDisabled
        }
    }

    /// Revalidates at activation time, rather than trusting a previously rendered enabled face.
    public func press(_ slot: ServerUICompositionDocument.RemoteSlot) throws {
        guard let button = button(slot) else { throw InteractionError.unknownControl }
        guard isEnabled(slot) else { throw InteractionError.unavailable }
        if let target = controller.press(button) {
            guard !keyboardSending else { throw InteractionError.busy }
            if keyboardTarget == target {
                keyboardTarget = nil
                keyboardText = ""
            } else {
                keyboardTarget = target
                keyboardText = ""
            }
            keyboardFailed = false
        }
    }

    /// Abandons the keyboard entry in progress.
    public func cancelKeyboard() throws {
        guard !keyboardSending else { throw InteractionError.busy }
        keyboardTarget = nil
        keyboardText = ""
        keyboardFailed = false
    }

    /// Target and text are pinned before awaiting; a rejection leaves the exact draft available for retry.
    public func submitKeyboard() async throws {
        guard !keyboardSending else { throw InteractionError.busy }
        guard let target = keyboardTarget, !controller.controlsDisabled else { throw InteractionError.unavailable }
        guard !keyboardText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw InteractionError.blankText }
        let text = keyboardText
        keyboardSending = true
        keyboardFailed = false
        defer { keyboardSending = false }
        do {
            try await controller.sendTextAcknowledged(text, to: target)
            keyboardTarget = nil
            keyboardText = ""
        } catch {
            keyboardFailed = true
            throw error
        }
    }

    // MARK: - State-dependent card actions

    /// Canonical transport eligibility with authored action order, labels and symbols.
    public func cardActions(_ appearances: [ServerUICompositionDocument.RemoteCardAction]) -> [TileActionSpec] {
        let c = controller.config
        let live = controller.store.entity(c.mediaEntityId).state
        let shown = live?.showing(controller.displayedState(c.mediaEntityId))
        let specs = MediaTransportActions(config: c).actions(for: shown)
        let paused = shown?.state == "paused"
        return appearances.compactMap { appearance in
            let id: String
            switch appearance.slot {
            case .play where !paused, .pause where paused: return nil
            case .play, .pause: id = "play_pause"
            default: id = appearance.slot.rawValue
            }
            guard var spec = specs.first(where: { $0.id == id }) else { return nil }
            spec.verb = appearance.label
            spec.label = nil
            spec.symbol = appearance.icon.name
            return spec
        }
    }

    /// Revalidates the exact currently displayed action before handing it to the existing controller.
    public func performCard(_ spec: TileActionSpec, appearances: [ServerUICompositionDocument.RemoteCardAction]) throws {
        guard cardActions(appearances).contains(spec), spec.phase == .ready else { throw InteractionError.unavailable }
        guard let call = spec.call else { throw InteractionError.unavailable }
        controller.perform(call, intents: spec.optimistic)
    }

    // MARK: - Validated value intents

    /// Commits only a live, enabled volume target and a valid percent.
    public func setVolume(percent: Int) throws {
        guard !controller.volumeDisabled, (0...100).contains(percent) else { throw InteractionError.unavailable }
        controller.setVolume(percent: percent)
    }

    /// Preserves the canonical power-off and light-sync-on dependent projections.
    public func toggleHue(_ target: ServerUICompositionDocument.RemoteHueToggle) throws {
        guard let hue = controller.config.lightSync else { throw InteractionError.unknownControl }
        let entity = target == .power ? hue.powerEntityId : hue.lightSyncEntityId
        guard !controller.hueToggle(entity).isUnavailable else { throw InteractionError.unavailable }
        controller.toggleHue(entity, offProjections: target == .power ? [hue.lightSyncEntityId] : [],
                             onProjections: target == .lightSync ? [hue.powerEntityId] : [])
    }

    /// Both the authored subset and the current live options must permit a choice.
    public func chooseHue(_ target: ServerUICompositionDocument.RemoteHueChoice, value: String, allowed: [String]) throws {
        guard let hue = controller.config.lightSync else { throw InteractionError.unknownControl }
        let entity = target == .mode ? hue.syncModeEntityId : hue.intensityEntityId
        let select = controller.hueSelect(entity)
        guard !select.isUnavailable, allowed.contains(value), select.options.contains(value) else { throw InteractionError.unavailable }
        if target == .mode { controller.selectSyncMode(hue, mode: value) }
        else { controller.selectHue(entity, option: value) }
    }

    /// Revalidates the live brightness range at release or accessibility adjustment.
    public func setHueBrightness(_ value: Double) throws {
        guard let hue = controller.config.lightSync else { throw InteractionError.unknownControl }
        let display = controller.hueBrightness(hue.brightnessEntityId)
        guard !display.isUnavailable, value.isFinite, display.range.contains(value) else { throw InteractionError.unavailable }
        controller.setHueBrightness(hue.brightnessEntityId, value: value)
    }

    /// Disconnected or removed HDMI options cannot be activated from a stale row.
    public func selectHueInput(_ option: String) throws {
        guard let hue = controller.config.lightSync else { throw InteractionError.unknownControl }
        guard controller.hdmiInputs(hue).contains(where: { $0.option == option && !$0.isDisabled }) else {
            throw InteractionError.unavailable
        }
        controller.selectHue(hue.hdmiInputEntityId, option: option)
    }
}
