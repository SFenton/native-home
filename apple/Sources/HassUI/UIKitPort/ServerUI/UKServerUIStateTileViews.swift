#if os(iOS)
import HassCore
import HassDesign
import UIKit

// MARK: - The state-styled tile over an authored style

/// Binds a `state-tile` node (`sh.state-style@1`): the style the tile resolves to decides the four layers, and a tap runs the
/// state's action as an authored `call-service` through the renderer's one call path.
///
/// A gap at run time degrades the tile and never rejects the layout: a style id the document does not define uses the tile's
/// built-in style, a device without the capability uses the built-in style alone, no style at all draws the unknown look, and a
/// glyph this OS does not draw falls back to the node's own icon.
@MainActor
enum UKServerUIStateTileViews {
    typealias D = ServerUICompositionDocument

    /// The style a tile shows, the entity's state and the resolved look, for the bind below and for tests.
    struct Face {
        var model: UKGlassTileModel
        var spec: TileActionSpec?
    }

    /// The face for `tile` now.
    /// - Parameters:
    ///   - library: The document's style library.
    ///   - capability: Whether this device negotiated the capability.
    ///   - state: The entity's live state.
    ///   - request: Where the request stands, the screen's privacy and the first load.
    ///   - shown: The state a call put on the entity until Home Assistant's own arrives (`StateRequest.pendingStates`); the look follows it
    ///     while the disc and the words of a call in flight still follow the live state.
    ///   - hidden: Whether the screen redacts its values, which shows the style's hidden words.
    ///   - sending: Whether the call is on the wire, which is when the pending words show; defaults to `request.isInFlight`.
    static func face(for tile: D.StateTile, library: ServerUIStateStyleLibrary?, capability: Bool, state: EntityState?,
                     request: UKStateTileLooks.Request, shown: String? = nil, sending: Bool? = nil, hidden: Bool = false) -> Face {
        let entityId = tile.binding.entityId
        guard let style = tile.binding.resolve(in: library, capability: capability) else {
            // No authored style and no built-in one: the tile is unavailable, with the node's own icon.
            var look = StateTileLook(icon: tile.icon.drawn, colour: .init(.unknown, active: false), text: "Unavailable", hasAction: false)
            look.indicator = .none
            var model = UKGlassTileModel(title: tile.node.title, subtitle: look.text, symbol: look.icon, family: .neutral, isActive: false,
                                         isUnavailable: true, kind: .state, identifier: tile.node.id)
            model.look = look
            return Face(model: model, spec: nil)
        }
        // A screen that hides its values, or a tile that has none yet, reads as the unknown state; a call on its way shows the state
        // it asked for, and the words of the call still follow the state the entity is in.
        let shownState = request.isUnknown ? nil : state?.showing(shown)
        let resolution = style.resolve(shownState, entityId: entityId)
        var spec = style.spec(for: shownState, entityId: entityId, requestInFlight: request.isInFlight)
        let callSpec = shown == nil ? spec : style.spec(for: state, entityId: entityId, requestInFlight: request.isInFlight)
        // An authored action symbol this OS cannot draw degrades to the fallback glyph; the call it runs is untouched.
        if let drawn = spec.map({ ServerUISymbolFallback.resolve($0.symbol) }) { spec?.symbol = drawn }
        // A state that gives no glyph, or one this OS does not draw, keeps the tile's own icon.
        let glyph = resolution.hasGlyph && UKServerUIPreflight.facts.drawsSymbol(resolution.glyph) ? resolution.glyph : tile.icon.drawn
        var words = resolution.words
        if hidden, let hiddenWords = style.hiddenWords { words = hiddenWords }
        else if request.isUnknown {}
        else if request.failed { words = style.request?.errorWords ?? "Error" }
        else if sending ?? request.isInFlight, let service = callSpec?.call?.service, let pending = style.request?.pendingWords[service] { words = pending }
        let look = UKStateTileLooks.look(resolution, request: request, icon: glyph, text: words, isActive: resolution.isActive,
                                         hasDisc: spec != nil)
        let hasDisc = spec != nil && (!request.isUnknown || style.keepsDiscWhenUnknown)
        var model = hasDisc
            ? UKGlassTileModel(title: tile.node.title, subtitle: words, symbol: glyph, family: .neutral, isActive: resolution.isActive,
                               isUnavailable: request.isUnknown, isError: look.stateClass == .error,
                               behavior: .perform(style.actionId), actions: spec.map { [$0].items } ?? [], identifier: tile.node.id)
            : UKGlassTileModel(title: tile.node.title, subtitle: words, symbol: glyph, family: .neutral, isActive: resolution.isActive,
                               isUnavailable: request.isUnknown, isError: look.stateClass == .error, kind: .state, identifier: tile.node.id)
        model.fillRGB = resolution.fill
        model.stateCandidates = style.rules.compactMap(\.words) + style.rules.flatMap(\.states).map { StateStyle.title($0) }
            + (style.request.map { Array($0.pendingWords.values) + [$0.errorWords] } ?? []) + ["Unavailable"]
        model.look = look
        model.isWarning = resolution.stateClass == .warning && !request.isUnknown && !request.failed && !request.isInFlight
        return Face(model: model, spec: spec)
    }

    static func bind(_ tile: D.StateTile, view: UKGlassTileView, bag: UKObservationBag, page: UKServerUIPage, renderer: UKServerUIRenderer,
                     node: UKServerUINode? = nil) {
        var first = true
        bag.observe { [weak view, weak page, weak renderer] in
            guard let view, let page, let renderer else { return }
            let state = page.context.store.entity(tile.binding.entityId).state
            let hidden = ScreenshotPrivacy.isRedacting
            let loading = page.context.valuesPending
            let unavailable = state?.isUnavailable != false
            let busy = renderer.callRunner.isBusy(node: tile.node.id)
            let sending = renderer.callRunner.isSending(node: tile.node.id)
            let failed = renderer.callRunner.isFailed(node: tile.node.id)
            var face = face(for: tile, library: renderer.publication.document.stateStyles, capability: renderer.stateStylesEnabled, state: state,
                            request: .init(isInFlight: busy, failed: !hidden && failed, isUnknown: hidden || loading || unavailable),
                            shown: busy ? renderer.callRunner.pendingState(tile.binding.entityId) : nil, sending: sending, hidden: hidden)
            face.model.reapplyGeneration = page.context.store.reapplyGeneration
            // `enabledWhen`: while it says no, the action's disc dims in place and the taps do nothing.
            let allowed = renderer.isEnabled(node: tile.node)
            if !allowed, let spec = face.spec {
                face.spec = spec.with(phase: .unavailable)
                face.model.actions = face.spec.map { [$0].items } ?? []
            }
            var subtitle: String?
            if let value = tile.parts.subtitle, case .ready(let text) = renderer.bindings.string(value) { subtitle = text }
            var discMemory = node?.layoutMemory ?? UKServerUILayoutMemory()
            UKServerUIStateTileParts.apply(tile, to: &face.model, reader: renderer.reader(), subtitle: subtitle,
                                           unknown: hidden || loading || unavailable, busy: busy,
                                           read: { renderer.bindings.textResult($0) }, memory: &discMemory)
            node?.layoutMemory = discMemory
            view.configure(face.model, environment: UKTileEnvironment(context: page.context), animated: !first,
                           action: tile.action.map { destination in { [weak page, weak renderer, weak view] in
                               guard let page else { return }
                               renderer?.activate(destination, from: page, source: view)
                           } },
                           perform: { [weak page, weak renderer, weak view] id in
                guard let page, let renderer, allowed else { return }
                if let disc = tile.parts.discs.first(where: { UKServerUIStateTileParts.itemID($0) == id }) {
                    renderer.activate(disc.action, from: page, source: view)
                    return
                }
                guard let call = face.spec?.call else { return }
                // The tile asked the question it carries before this runs.
                // The style's own feedback: the state the entity shows once the call is on its way, until the real one arrives.
                let request = tile.binding.resolve(in: renderer.publication.document.stateStyles, capability: renderer.stateStylesEnabled)?.request
                let optimistic = request?.pendingStates[call.service].map {
                    [ServerUICallService.Optimistic(sourceId: tile.binding.entityId, value: $0,
                                                    revertAfterSeconds: Double(request?.settleTimeout.components.seconds ?? 45),
                                                    failsOnTimeout: request?.onTimeout == .error)]
                } ?? []
                let authored = ServerUICallService(domain: call.domain, service: call.service,
                                                   target: ["entity_id": .literal(.string(tile.binding.entityId))], optimistic: optimistic)
                renderer.activate(.callService(authored), from: page, source: view, site: tile.node.id, confirmed: true)
            })
            first = false
            view.ukRemeasureContainers()
        }
    }
}
#endif
