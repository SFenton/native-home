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
    ///   - phase: Where the request stands, the screen's privacy and the first load.
    static func face(for tile: D.StateTile, library: ServerUIStateStyleLibrary?, capability: Bool, state: EntityState?,
                     request: UKStateTileLooks.Request, pendingWords: Bool = false) -> Face {
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
        let resolution = style.resolve(state, entityId: entityId)
        var spec = style.spec(for: state, entityId: entityId, requestInFlight: request.isInFlight)
        // An authored action symbol this OS cannot draw degrades to the fallback glyph; the call it runs is untouched.
        if let drawn = spec.map({ ServerUISymbolFallback.resolve($0.symbol) }) { spec?.symbol = drawn }
        // A state that gives no glyph, or one this OS does not draw, keeps the tile's own icon.
        let glyph = resolution.hasGlyph && UKServerUIPreflight.facts.drawsSymbol(resolution.glyph) ? resolution.glyph : tile.icon.drawn
        var words = resolution.words
        if request.failed { words = style.request?.errorWords ?? "Error" }
        else if request.isInFlight, let service = spec?.call?.service, let pending = style.request?.pendingWords[service] { words = pending }
        let look = UKStateTileLooks.look(resolution, request: request, icon: glyph, text: words, isActive: resolution.isActive,
                                         hasDisc: spec != nil)
        let hasDisc = spec != nil && !request.isUnknown
        var model = hasDisc
            ? UKGlassTileModel(title: tile.node.title, subtitle: words, symbol: glyph, family: .neutral, isActive: resolution.isActive,
                               isUnavailable: request.isUnknown, isError: look.stateClass == .error,
                               behavior: .perform(style.actionId), actions: spec.map { [$0].items } ?? [], identifier: tile.node.id)
            : UKGlassTileModel(title: tile.node.title, subtitle: words, symbol: glyph, family: .neutral, isActive: resolution.isActive,
                               isUnavailable: request.isUnknown, isError: look.stateClass == .error, kind: .state, identifier: tile.node.id)
        model.stateCandidates = style.rules.compactMap(\.words) + style.rules.flatMap(\.states).map { StateStyle.title($0) }
            + (style.request.map { Array($0.pendingWords.values) + [$0.errorWords] } ?? []) + ["Unavailable"]
        model.look = look
        model.isWarning = resolution.stateClass == .warning && !request.isUnknown && !request.failed && !request.isInFlight
        return Face(model: model, spec: spec)
    }

    static func bind(_ tile: D.StateTile, view: UKGlassTileView, bag: UKObservationBag, page: UKServerUIPage, renderer: UKServerUIRenderer) {
        var first = true
        bag.observe { [weak view, weak page, weak renderer] in
            guard let view, let page, let renderer else { return }
            let state = page.context.store.entity(tile.binding.entityId).state
            let hidden = ScreenshotPrivacy.isRedacting
            let loading = page.context.valuesPending
            let unavailable = state?.isUnavailable != false
            let busy = renderer.callRunner.isBusy(node: tile.node.id)
            let failed = renderer.callRunner.isFailed(node: tile.node.id)
            var face = face(for: tile, library: renderer.publication.document.stateStyles, capability: renderer.stateStylesEnabled, state: state,
                            request: .init(isInFlight: busy, failed: !hidden && failed, isUnknown: hidden || loading || unavailable))
            face.model.reapplyGeneration = page.context.store.reapplyGeneration
            // `enabledWhen`: while it says no, the action's disc dims in place and the tap does nothing.
            let allowed = renderer.isEnabled(node: tile.node)
            if !allowed, let spec = face.spec {
                face.spec = spec.with(phase: .unavailable)
                face.model.actions = face.spec.map { [$0].items } ?? []
            }
            view.configure(face.model, environment: UKTileEnvironment(context: page.context), animated: !first,
                           perform: { [weak page, weak renderer, weak view] _ in
                guard let page, let renderer, allowed, let call = face.spec?.call else { return }
                // The tile asked the question it carries before this runs.
                let authored = ServerUICallService(domain: call.domain, service: call.service,
                                                   target: ["entity_id": .literal(.string(tile.binding.entityId))])
                renderer.activate(.callService(authored), from: page, source: view, site: tile.node.id, confirmed: true)
            })
            first = false
            view.ukRemeasureContainers()
        }
    }
}
#endif
