#if os(iOS)
import HassCore
import HassDesign
import Observation
import UIKit

// MARK: - Session-owned domain seam

/// Inject one provider per authenticated session. Preview can inject isolated models without
/// exposing its connection or replacing its rejecting caller.
@MainActor
protocol UKServerUISettingsProvider: AnyObject {
    var definition: ServerUISettingsSource { get }
    var isCurrentSession: Bool { get }
    var protectsPublication: Bool { get }
    var blocksExit: Bool { get }
    var canDiscard: Bool { get }
    func accepts(_ control: ServerUISettingsControl) -> Bool
    func make(_ control: ServerUISettingsControl, host: UKServerUISettingsAtom, page: UKServerUIPage) throws -> UIView
    func discard()
    func didExit()
}

extension UKServerUISettingsProvider {
    var blocksExit: Bool { protectsPublication }
    var canDiscard: Bool { false }
    func discard() {}
    func didExit() {}

    func requireCurrent() throws {
        guard isCurrentSession else {
            throw UKServerUIRendererError(code: .unavailableSource, pointer: "/document/dataSources")
        }
    }
}

@MainActor
enum UKServerUISettingsProviders {
    static func validate(_ document: ServerUICompositionDocument,
                         providers: [String: any UKServerUISettingsProvider]) throws {
        var sources: [String: any UKServerUISettingsProvider] = [:]
        for (index, source) in document.dataSources.enumerated() {
            guard case .settingsProvider(let id, let definition) = source else { continue }
            guard let provider = providers[definition.providerId], provider.definition == definition,
                  provider.isCurrentSession else {
                throw UKServerUIRendererError(code: .unavailableSource, pointer: "/document/dataSources/\(index)")
            }
            sources[id] = provider
        }
        func visit(_ components: [ServerUICompositionDocument.Component], surfaceID: String) throws {
            for component in components {
                if case .settingsControl(let control) = component,
                   sources[control.sourceId]?.accepts(control) != true {
                    throw UKServerUIRendererError(code: .unavailableSource,
                        pointer: "/document/surfaces/\(surfaceID)/components/\(control.node.id)/props")
                }
                try visit(component.childComponents, surfaceID: surfaceID)
            }
        }
        for surface in document.pages.map(\.surface) + document.modals.map(\.surface) {
            try visit(surface.components, surfaceID: surface.id)
        }
    }
}

// MARK: - Width-driven native atom

/// Keeps the canonical child and observation lifetime across compatible publications.
///
/// The child is pinned to the atom's edges with constraints, so the atom has the child's height under Auto Layout as well as through
/// ``gridHeight(forWidth:)``. A settings row in a module list (a `UIStackView` of rows, sized by system fitting) would otherwise have
/// no size of its own and collapse to a hairline: the 350x1 rows of the preview's Settings page.
@MainActor
final class UKServerUISettingsAtom: UIView, UKGridMeasuring {
    let bag = UKObservationBag()
    private(set) var content: UIView?
    private var definition: ServerUISettingsControl?
    private weak var provider: (any UKServerUISettingsProvider)?

    func bind(_ control: ServerUISettingsControl, provider: any UKServerUISettingsProvider,
              page: UKServerUIPage) throws {
        if definition == control, self.provider === provider { return }
        try provider.requireCurrent()
        bag.removeAll()
        content?.removeFromSuperview()
        definition = control
        self.provider = provider
        install(try provider.make(control, host: self, page: page), identifier: control.node.id)
    }

    /// Shows `view` as the atom's child, pinned to its edges.
    /// - Parameters:
    ///   - view: The control the provider made.
    ///   - identifier: The accessibility identifier it carries.
    func install(_ view: UIView, identifier: String) {
        content = view
        addSubview(view)
        view.ukPin(to: self)
        view.accessibilityIdentifier = identifier
        ukRemeasureContainers(includingSelf: true)
    }

    func gridHeight(forWidth width: CGFloat) -> CGFloat {
        guard let content, !content.isHidden else { return 0 }
        if let measuring = content as? UKGridMeasuring { return measuring.gridHeight(forWidth: width) }
        if let label = content as? UILabel {
            return ceil(label.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height)
        }
        if let field = content as? UKFeedbackTextView {
            return max(field.minimumHeight, ceil(field.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height))
        }
        return ceil(content.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height)
    }

    /// A rejected session/target never looks like a successful tap.
    func perform(from page: UKServerUIPage, _ operation: () throws -> Void) {
        do { try operation() }
        catch {
            page.renderer?.onError(.init(code: .interactionBlocked, pointer: "/document/dataSources"))
            guard page.presentedViewController == nil else { return }
            let alert = UIAlertController(title: "Couldn't Apply Change",
                                          message: "The account or control changed. Try again after reconnecting.",
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .cancel))
            page.present(alert, animated: true)
        }
    }
}

// MARK: - Household

/// Targets and confirmation policy are injected, never inferred from an authored page ID.
@MainActor
@Observable
final class UKServerUIHouseholdProvider: UKServerUISettingsProvider {
    let definition: ServerUISettingsSource
    private let current: () -> Bool
    private let targets: [String: HouseholdSettingsTargetAdapter]
    private let highAQI: Set<String>
    private let guests: Set<String>
    private let autoLock: Set<String>
    private let relayWarning: (() -> Bool)?
    private var confirming = false
    var isCurrentSession: Bool { current() }
    var protectsPublication: Bool { confirming || targets.values.contains(where: \.hasPendingIntent) }

    init(id: String, targets: [String: HouseholdSettingsTargetAdapter], highAQI: Set<String> = [], guests: Set<String> = [], autoLock: Set<String> = [],
         relayWarning: (() -> Bool)? = nil,
         isCurrentSession: @escaping () -> Bool) {
        definition = .init(providerId: id, domain: .household)
        self.targets = targets
        self.highAQI = highAQI
        self.guests = guests
        self.autoLock = autoLock
        self.relayWarning = relayWarning
        current = isCurrentSession
    }

    private func selection(_ item: String) -> (String, PresenceOverrideState)? {
        let pieces = item.split(separator: "/", omittingEmptySubsequences: false)
        guard pieces.count == 2, let mode = PresenceOverrideState(rawValue: String(pieces[1])),
              mode != .unavailable else { return nil }
        return (String(pieces[0]), mode)
    }

    func accepts(_ control: ServerUISettingsControl) -> Bool {
        guard control.kind.domain == .household else { return false }
        switch control.kind {
        case .householdWarning: return relayWarning != nil
        case .householdReadOnly: return targets[control.item]?.target.kind == .readOnly
        case .householdToggle: return targets[control.item]?.target.kind == .toggle
        case .householdRecovery: return targets[control.item]?.target.kind == .powerRecovery
        case .presenceRoom: return targets[control.item]?.target.kind == .presence
        case .presenceChoice:
            return selection(control.item).map { targets[$0.0]?.target.kind == .presence } ?? false
        default: return false
        }
    }

    func make(_ control: ServerUISettingsControl, host: UKServerUISettingsAtom, page: UKServerUIPage) throws -> UIView {
        if control.kind == .householdWarning, let relayWarning {
            let warning = UKInlineAlertView(control.subtitle, severity: .warning)
            host.bag.observe { [weak self, weak host, weak warning] in
                let shown = self?.isCurrentSession == true && relayWarning()
                warning?.isHidden = !shown
                host?.isHidden = !shown
                host?.ukRemeasureContainers(includingSelf: true)
            }
            return warning
        }
        guard accepts(control), let adapter = targets[selection(control.item)?.0 ?? control.item] else {
            throw UKServerUIRendererError(code: .unavailableSource, pointer: "/document/dataSources")
        }
        let controller = adapter.controller, entity = adapter.target.entityId
        if control.kind == .householdReadOnly {
            func model() -> UKGlassTileModel {
                let display = controller.readOnly(.init(title: control.node.title, entityId: entity, icon: "", showsState: true))
                return UKGlassTileModel(title: control.node.title, subtitle: display.subtitle, symbol: control.icon.drawn,
                                        tint: UKHouseholdTint.settingsControl, isActive: display.isActive,
                                        isUnavailable: display.isUnavailable || !isCurrentSession, kind: .state,
                                        identifier: control.node.id, spokenValue: display.subtitle)
            }
            let tile = UKGlassTileView(model: model(), environment: UKTileEnvironment(context: page.context))
            host.bag.observe { [weak tile, weak host, weak page] in
                guard let page else { return }
                tile?.configure(model(), environment: UKTileEnvironment(context: page.context))
                host?.ukRemeasureContainers(includingSelf: true)
            }
            return tile
        }
        let row = UKGroupedRowButton(title: control.node.title, symbol: control.icon.drawn, identifier: control.node.id)
        row.onTap = { [weak self, weak host, weak page] in
            guard let self, let host, let page else { return }
            host.perform(from: page) {
                try self.requireCurrent()
                switch control.kind {
                case .householdToggle:
                    let expected = controller.toggle(entity)
                    if self.highAQI.contains(control.item) {
                        self.confirming = true
                        let spec = AlertCopy.highAqiMode(turningOn: !expected.isOn)
                        let alert = UIAlertController(title: spec.title, message: spec.message, preferredStyle: .alert)
                        alert.addAction(UIAlertAction(title: spec.confirm.title, style: .default) { [weak self] _ in
                            guard let self else { return }
                            defer { self.confirming = false }
                            host.perform(from: page) { try self.requireCurrent(); try adapter.flip(expected: expected) }
                        })
                        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in self?.confirming = false })
                        page.present(alert, animated: true)
                    } else { try adapter.flip(expected: expected) }
                case .householdRecovery: try adapter.triggerPowerRecovery()
                case .presenceRoom:
                    if let destination = control.destination { page.renderer?.activate(destination, from: page, source: host) }
                case .presenceChoice:
                    guard let mode = self.selection(control.item)?.1 else { throw HouseholdSettingsTarget.Failure.invalidTarget }
                    try adapter.selectPresence(mode, expected: controller.presence(entity))
                default: throw HouseholdSettingsTarget.Failure.invalidTarget
                }
            }
        }
        host.bag.observe { [weak self, weak host, weak row] in
            guard let self, let row else { return }
            switch control.kind {
            case .householdToggle:
                let display = controller.toggle(entity)
                row.isEnabled = self.isCurrentSession && !display.isUnavailable && !adapter.hasPendingIntent
                row.accessibilityValue = display.subtitle
                row.value = display.subtitle
            case .presenceRoom, .presenceChoice:
                let mode = controller.presence(entity)
                row.value = mode.summary
                row.isEnabled = self.isCurrentSession && (control.kind == .presenceRoom || (mode != .unavailable && !adapter.hasPendingIntent))
                row.accessibilityTraits = self.selection(control.item)?.1 == mode ? [.button, .selected] : .button
            default:
                row.isEnabled = self.isCurrentSession && !adapter.hasPendingIntent
                    && controller.store.entity(entity).state?.isUnavailable == false
                row.value = controller.powerRecoveryFailed ? "Didn't Respond" : ""
            }
            host?.ukRemeasureContainers(includingSelf: true)
        }
        let tap = row.onTap
        if control.kind == .presenceChoice, let mode = selection(control.item)?.1 {
            let choice = UKSelectableOptionRow(title: control.node.title, detail: control.subtitle, symbol: control.icon.drawn,
                                               tint: UIColor(mode.tintToken), isSelected: false)
            choice.onTap = tap
            host.bag.observe { [weak self, weak choice] in
                choice?.isSelectedChoice = controller.presence(entity) == mode
                choice?.isDisabled = self?.isCurrentSession != true || controller.presence(entity) == .unavailable || adapter.hasPendingIntent
            }
            return choice
        }
        if control.kind == .householdToggle || control.kind == .presenceRoom {
            func model() -> UKGlassTileModel {
                if control.kind == .householdToggle {
                    return UKHouseholdTiles.toggleModel(entityId: entity, title: control.node.title, symbol: control.icon.drawn,
                                                        identifier: control.node.id, isAutoLock: autoLock.contains(control.item),
                                                        display: controller.toggle(entity),
                                                        face: guests.contains(control.item) ? .guest : .settings)
                }
                let mode = controller.presence(entity)
                return UKGlassTileModel(title: control.node.title, subtitle: mode.summary, symbol: control.icon.drawn,
                                        tint: UIColor(mode.tintToken), isActive: mode != .unavailable,
                                        kind: .navigate, identifier: control.node.id)
            }
            let view = UKGlassTileView(model: model(), environment: UKTileEnvironment(context: page.context))
            host.bag.observe { [weak view, weak host, weak page] in
                guard let page else { return }
                view?.configure(model(), environment: UKTileEnvironment(context: page.context),
                                action: { tap?() }, perform: { _ in tap?() })
                host?.ukRemeasureContainers(includingSelf: true)
            }
            return view
        }
        return row
    }
}
#endif
