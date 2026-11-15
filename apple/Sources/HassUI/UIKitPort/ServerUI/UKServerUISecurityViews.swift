#if os(iOS)
import HassCore
import HassDesign
import UIKit

// MARK: - Value/closure presentation adapters

@MainActor
enum UKServerUISecurityViews {
    typealias D = ServerUICompositionDocument

    static func rgb(_ fill: D.TileFill) -> UInt32 {
        switch fill {
        case .solidRGB(let red, let green, let blue): UInt32(red) << 16 | UInt32(green) << 8 | UInt32(blue)
        case .standard: 0
        }
    }

    static func modes(_ panel: D.AlarmPanel) -> [UKAlarmModeButton.Value] {
        panel.modes.map { .init(state: $0.state, label: $0.label, symbol: $0.icon.drawn, fill: rgb($0.fill), hint: $0.hint) }
    }

    static func bind(_ panel: D.AlarmPanel, view: UKAlarmPanelControl, bag: UKObservationBag,
                     page: UKServerUIPage, renderer: UKServerUIRenderer) {
        view.setModes(modes(panel))
        view.followsFold = !page.isSheet && !page.context.isPane
        var generation: Int?
        bag.observe { [weak view, weak page, weak renderer] in
            guard let view, let page, let renderer, let model = renderer.bindings.alarms[panel.sourceId] else { return }
            let live = page.context.store.entity(model.entityID).state
            let hidden = ScreenshotPrivacy.isRedacting
            let loading = page.context.valuesPending
            let unavailable = live?.isUnavailable != false
            let shown = model.shownState
            let appearance = hidden || loading || unavailable ? panel.fallback
                : panel.states.first(where: { $0.state == shown })?.appearance ?? panel.fallback
            let title = hidden ? panel.hiddenText : loading ? panel.loadingText : unavailable ? panel.unavailableText : appearance.text
            var subtitle = panel.subtitle
            if model.network != nil { subtitle = panel.pendingText }
            else if !hidden, !loading, !unavailable, let changed = live?.lastChanged,
                    changed != .distantPast, changed <= .now.addingTimeInterval(60) {
                let date = Calendar.current.isDateInToday(changed)
                    ? changed.formatted(date: .omitted, time: .shortened)
                    : changed.formatted(.dateTime.month(.abbreviated).day())
                subtitle += panel.separator + panel.sincePrefix + date
            }
            let currentGeneration = page.context.store.reapplyGeneration
            view.configure(.init(
                title: title, subtitle: subtitle, accessibilityLabel: panel.node.title,
                accessibilityValue: [title, subtitle].joined(separator: panel.separator),
                symbol: appearance.icon.drawn, badgeFill: rgb(appearance.fill), washFill: rgb(panel.triggeredWash),
                selectedState: hidden || unavailable || loading ? nil : shown,
                unavailable: hidden || loading || unavailable || !model.canSend,
                pending: model.network != nil || model.confirmation != nil,
                triggered: !hidden && !loading && !unavailable && shown == "triggered",
                failure: !hidden && model.actions?.isFailed(model.entityID) == true ? panel.errorText : nil
            ), animated: generation == currentGeneration)
            generation = currentGeneration
            view.onSelect = { [weak page, weak renderer, weak view] state in
                guard let page, let renderer, let view,
                      model.shownState != state,
                      let expected = model.modeSpec(state, confirmation: panel.confirmation.spec) else { return }
                renderer.activateAlarmPanel(panel, mode: state, expected: expected, from: page, source: view)
            }
            view.ukRemeasureContainers()
        }
    }

    static func bind(_ tile: D.DoorTile, view: UKGlassTileView, bag: UKObservationBag,
                     page: UKServerUIPage, renderer: UKServerUIRenderer) {
        var first = true
        bag.observe { [weak view, weak page, weak renderer] in
            guard let view, let page, let renderer, let source = renderer.bindings.doors[tile.sourceId] else { return }
            let hidden = ScreenshotPrivacy.isRedacting
            let loading = page.context.valuesPending
            let unavailable = page.context.store.entity(source.entityID).state?.isUnavailable != false
            let state = tile.states.first { $0.state == source.state }
            let appearance = hidden || loading || unavailable ? tile.fallback : state?.appearance ?? tile.fallback
            let phase = source.garage?.phase ?? .idle
            let text = hidden ? tile.hiddenText : loading ? tile.loadingText : unavailable ? tile.unavailableText
                : source.failed ? tile.errorText
                : phase == .sending ? (source.garage?.opens == true ? tile.sendingOpenText : tile.sendingCloseText) : appearance.text
            let expected = source.spec
            var spec = expected
            spec.verb = tile.kind == .lock
                ? (spec.call?.service == "lock" ? tile.closeLabel : tile.openLabel)
                : (source.garage?.liveState == "opening" || source.garage?.liveState == "closing") ? tile.reverseLabel
                : spec.call?.service == "open_cover" ? tile.openLabel : tile.closeLabel
            spec.symbol = appearance.icon.drawn
            var model = UKGlassTileModel(
                title: tile.node.title, subtitle: text, symbol: appearance.icon.drawn, family: .contact,
                fillRGB: rgb(appearance.fill), isActive: !hidden && !loading && !unavailable && state?.active == true,
                isUnavailable: hidden || loading || unavailable, isError: !hidden && (source.failed || state?.error == true),
                behavior: .perform(spec.id), actions: [spec].items, identifier: tile.node.id)
            model.stateCandidates = tile.states.map(\.appearance.text) + [tile.fallback.text, tile.loadingText,
                tile.unavailableText, tile.hiddenText, tile.errorText, tile.sendingOpenText, tile.sendingCloseText]
            model.reapplyGeneration = page.context.store.reapplyGeneration
            // The style classes the state; the request decides the rest. The state-styled tile moves its layers one by one.
            let resolution = source.style.resolve(EntityState(entityId: source.entityID, state: source.state ?? "unavailable"), entityId: source.entityID)
            let look = UKStateTileLooks.look(
                resolution, request: .init(isInFlight: expected.phase == .inFlight, failed: !hidden && source.failed,
                                           isUnknown: hidden || loading || unavailable),
                icon: appearance.icon.drawn, text: text, isActive: model.isActive)
            model.look = look
            model.isWarning = look.stateClass == .warning
            view.configure(model, environment: UKTileEnvironment(context: page.context), animated: !first,
                           perform: { [weak page, weak renderer, weak view] _ in
                guard let page, let renderer, let view else { return }
                renderer.activateDoor(tile, expected: expected, from: page, source: view)
            })
            first = false
            view.ukRemeasureContainers()
        }
    }
}
#endif
