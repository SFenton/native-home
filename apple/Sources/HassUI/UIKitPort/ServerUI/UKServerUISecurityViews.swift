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
}
#endif
