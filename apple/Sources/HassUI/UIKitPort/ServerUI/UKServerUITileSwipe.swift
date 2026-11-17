#if os(iOS)
import HassCore
import HassDesign
import Observation
import UIKit

// MARK: - The document's swipe on a tile (`sh.tile-swipe@1`)

extension UKTileSwipeConfig {
    /// The swipe a document authored for a tile, or `nil` when it authored none: no pan, no adjustable trait, no hint.
    ///
    /// A light group tile adjusts a light's brightness, so its bubble reads the light's own words: "Off" at the minimum and the level word
    /// elsewhere (`sh.state-words@1`).
    init?(_ swipe: ServerUITileSwipe?, lightGroup: Bool = false, words: ServerUIStateWords? = nil) {
        guard let swipe else { return nil }
        self.init(swipe: TileSwipe(min: swipe.range.min, max: swipe.range.max, step: swipe.range.step, detent: swipe.detent),
                  format: lightGroup ? words?.level ?? "{value}%" : swipe.format, zeroWord: lightGroup ? words?.off ?? "Off" : nil,
                  showsBand: swipe.showsBand, ticks: swipe.haptic == .detent,
                  label: lightGroup ? "brightness" : (swipe.label ?? "value").lowercased())
    }
}

extension UKLightWords {
    /// The words a document authored, production's for the rest.
    init(_ words: ServerUIStateWords?) {
        self.init(on: words?.on, off: words?.off, unavailable: words?.unavailable, level: words?.level)
    }
}

/// A swiped `state-tile`: reads the swipe's value, draws it as the band, speaks it, and sends the one call on release through the renderer's one
/// call path (`HassConnection.callService` behind it). The band stays at the committed value, optimistic, until live state replaces it, the
/// action's `revertAfterSeconds` pass or the call fails.
@MainActor
@Observable
final class UKServerUITileSwipeBinding {
    /// The pan, the bubble and VoiceOver's step.
    @ObservationIgnored let controller: UKTileSwipeController
    @ObservationIgnored private let swipe: ServerUITileSwipe
    @ObservationIgnored private let tile: ServerUICompositionDocument.StateTile
    @ObservationIgnored private weak var view: UKGlassTileView?
    @ObservationIgnored private weak var page: UKServerUIPage?
    @ObservationIgnored private weak var renderer: UKServerUIRenderer?
    @ObservationIgnored private var pending: (value: Double, liveAtCommit: Double?, deadline: ContinuousClock.Instant)?
    @ObservationIgnored private var expiry: Task<Void, Never>?
    @ObservationIgnored private var enabled = false
    /// Read by the tile's observation, so an expired optimistic value draws the live one again.
    private var generation = 0

    init?(tile: ServerUICompositionDocument.StateTile, view: UKGlassTileView, page: UKServerUIPage, renderer: UKServerUIRenderer) {
        guard let swipe = tile.swipe, let config = UKTileSwipeConfig(swipe) else { return nil }
        self.swipe = swipe
        self.tile = tile
        self.view = view
        self.page = page
        self.renderer = renderer
        controller = UKTileSwipeController(host: view, config: config)
        controller.isEnabled = { [weak self] in self?.enabled == true }
        controller.shownValue = { [weak self] in self?.shown() ?? config.swipe.min }
        controller.onFrame = { [weak self, weak view] value in
            guard let self, let view else { return }
            view.showSwipeFrame(level: value.map { config.swipe.fraction(of: $0) }, usesBand: config.showsBand)
        }
        controller.onCommit = { [weak self] value in self?.commit(value) }
        controller.holdsCommittedFrame = { [weak self] in self?.pending != nil }
        controller.onFrameHold = { [weak view] in view?.holdSwipeFrameUntilConfigure() }
        view.swipe = controller
    }

    deinit { MainActor.assumeIsolated { expiry?.cancel() } }

    // MARK: Reading

    private func live() -> Double? {
        guard let operand = swipe.value, let renderer, case .value(.number(let number)) = operand.evaluate(renderer.reader()), number.isFinite else { return nil }
        return controller.config.swipe.snapped(number)
    }

    private func shown() -> Double? { pending?.value ?? live() }

    // MARK: Applying

    /// Puts the swipe's value, spoken value and adjust handler on `model` and the tile, before the tile is configured.
    func apply(to model: inout UKGlassTileModel, allowed: Bool, unknown: Bool, failed: Bool) {
        _ = generation
        let current = live()
        if let held = pending, failed || current != held.liveAtCommit || ContinuousClock.now >= held.deadline { pending = nil }
        let value = pending?.value ?? current
        enabled = allowed && !unknown && value != nil
        let config = controller.config
        model.progress = config.showsBand ? value.map { config.swipe.fraction(of: $0) } : nil
        view?.onAdjust = enabled ? { [weak controller] up in controller?.step(up: up) } : nil
        guard enabled, let value else { return }
        let words = controller.text(value)
        model.spokenValue = model.subtitle.map { $0.isEmpty || $0 == words ? words : "\(words), \($0)" } ?? words
    }

    // MARK: Releasing

    private func commit(_ value: Double) {
        guard let swipe = swipe.action, let page, let renderer, let view else { return }
        let seconds = swipe.optimistic.first?.revertAfterSeconds ?? 4
        let deadline = ContinuousClock.now + .seconds(seconds)
        pending = (value, live(), deadline)
        expiry?.cancel()
        expiry = Task { @MainActor [weak self] in
            try? await Task.sleep(until: deadline, clock: .continuous)
            guard !Task.isCancelled else { return }
            self?.generation += 1
        }
        generation += 1
        renderer.activate(.callService(swipe), from: page, source: view, control: .number(value), site: tile.node.id, confirmed: true)
    }
}
#endif
