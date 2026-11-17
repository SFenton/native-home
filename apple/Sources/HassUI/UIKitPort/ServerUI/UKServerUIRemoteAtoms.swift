#if os(iOS)
import HassCore
import HassDesign
import UIKit

// MARK: - Injected provider acceptance

/// Validates domain references against parent-injected controllers, never global house configuration.
@MainActor
enum UKServerUIRemoteProviders {
    typealias D = ServerUICompositionDocument

    static func validate(_ document: D, providers: [String: ServerUIRemoteSession], store: EntityStore) throws {
        let sources = Dictionary(uniqueKeysWithValues: document.dataSources.compactMap { source -> (String, ServerUIRemoteSession)? in
            guard case .mediaRemote(let id, let providerID) = source, let provider = providers[providerID] else { return nil }
            return (id, provider)
        })
        for (index, source) in document.dataSources.enumerated() {
            if case .mediaRemote(let id, _) = source {
                guard let session = sources[id], session.controller.store === store else {
                    throw UKServerUIRendererError(code: .unavailableSource, pointer: "/document/dataSources/\(index)/inputs/providerId")
                }
            }
        }
        var keyboardOwners: Set<ObjectIdentifier> = []
        func visit(_ components: [D.Component], path: String) throws {
            for (index, component) in components.enumerated() {
                let path = path + "/\(index)"
                try visit(component.childComponents, path: path + "/children")
                guard case .remote(let remote) = component, let session = sources[remote.sourceId] else { continue }
                let config = session.controller.config
                let valid: Bool
                switch remote.control {
                case .keys(_, _, let keys), .volume(let keys, _, _):
                    valid = keys.allSatisfy { session.button($0.slot) != nil }
                case .keyboard:
                    valid = config.keyboard != nil && keyboardOwners.insert(ObjectIdentifier(session)).inserted
                case .app(let key, _, _, _, _): valid = config.apps.filter { $0.id == key }.count == 1
                case .device(let key, _, _, _, _), .card(let key, _, _, _, _, _, _, _, _, _):
                    valid = config.devices.filter { $0.id == key }.count == 1
                case .hueToggle, .hueChoice, .hueBrightness, .hueInput: valid = config.lightSync != nil
                }
                guard valid else { throw UKServerUIRendererError(code: .unavailableSource, pointer: path + "/props") }
            }
        }
        for (index, page) in document.pages.enumerated() { try visit(page.surface.components, path: "/document/pages/\(index)/components") }
        for (index, modal) in document.modals.enumerated() { try visit(modal.surface.components, path: "/document/modals/\(index)/components") }
    }

    /// Full attachment paths guard reparenting, surface removal and definition edits while interacting.
    static func attachments(_ document: D) -> [String: [String: D.Remote]] {
        var result: [String: [String: D.Remote]] = [:]
        func visit(_ components: [D.Component], path: String) {
            for (index, component) in components.enumerated() {
                let path = path + "/\(index)/" + component.node.id
                switch component {
                case .remote(let remote): result[remote.sourceId, default: [:]][path] = remote
                default: break
                }
                visit(component.childComponents, path: path)
            }
        }
        for surface in document.pages.map(\.surface) + document.modals.map(\.surface) {
            visit(surface.components, path: surface.id)
        }
        return result
    }
}

// MARK: - Atomic presentation adapter

/// One configured atomic control. Reuses canonical native values/closures; never embeds a feature controller.
@MainActor
final class UKServerUIRemoteAtom: UIView, UKGridWrapping {
    typealias D = ServerUICompositionDocument
    private let column = UKColumnView(spacing: HassTokens.Spacing.m)
    private let bag = UKObservationBag()
    private var definition: D.Remote?
    private var session: ServerUIRemoteSession?
    private var error: UKInlineAlertView?
    private var loading: UILabel?
    private var actionFailed = false
    private var announcedFailure = false
    private var report: () -> Void = {}
    private var residentId: () -> String? = { nil }

    init() {
        super.init(frame: .zero)
        addSubview(column)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(_ remote: D.Remote, session: ServerUIRemoteSession, context: UKContext,
                   artwork: @escaping (String) -> URL?, navigate: @escaping (D.Action, UIView) -> Void,
                   residentId: @escaping () -> String? = { nil },
                   onError: @escaping () -> Void) {
        self.residentId = residentId
        guard definition != remote || self.session !== session else { return }
        definition = remote
        self.session = session
        report = onError
        actionFailed = false
        bag.removeAll()
        let loading = UILabel.uk(.body, ink: UKDesignInk.secondary)
        loading.text = remote.feedback.loadingText
        self.loading = loading
        let error = UKInlineAlertView(remote.feedback.errorText, severity: .error)
        self.error = error
        let content = make(remote, session: session, context: context, artwork: artwork, navigate: navigate)
        column.setViews([loading, content, error])
        content.accessibilityIdentifier = remote.node.id + ".control"
        bag.observe { [weak self, weak content] in
            guard let self else { return }
            let pending = context.valuesPending
            loading.isHidden = !pending
            content?.isUserInteractionEnabled = !pending
            content?.accessibilityElementsHidden = pending
            content?.alpha = pending ? 0 : 1
            refreshFailure(session.controller.lastCommandFailed)
            ukInvalidateEnclosingLayout()
        }
    }

    func gridHeight(forWidth width: CGFloat) -> CGFloat { column.gridHeight(forWidth: width) }
    override func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: size.width, height: gridHeight(forWidth: size.width)) }
    override func layoutSubviews() { super.layoutSubviews(); column.frame = bounds }

    private func refreshFailure(_ failed: Bool) {
        let visible = failed || actionFailed
        error?.isHidden = !visible
        if visible, !announcedFailure, let definition {
            UIAccessibility.post(notification: .announcement, argument: definition.feedback.errorText)
        }

        announcedFailure = visible
        ukInvalidateEnclosingLayout()
    }

    private func title(_ remote: D.Remote) -> String {
        guard let personalization = remote.personalization, let resident = residentId(), !ScreenshotPrivacy.isRedacting else { return remote.node.title }
        return resident == personalization.residentId ? personalization.ownTitle : personalization.otherTitle
    }

    private func perform(_ action: () throws -> Void) {
        actionFailed = false
        do { try action() }
        catch { actionFailed = true; report() }
        refreshFailure(session?.controller.lastCommandFailed == true)
    }

    private func key(_ key: D.RemoteKey, session: ServerUIRemoteSession, diameter: CGFloat, fill: UIColor? = UKDesignSurface.sheetCell) -> UKRemoteRoundButton {
        let view = UKRemoteRoundButton(appearance: .init(label: key.label, symbol: key.icon?.drawn, rotation: key.rotation),
                                      role: key.slot == .power ? .power : .key, diameter: diameter, fill: fill, state: {
            guard let button = session.button(key.slot) else { return .init(enabled: false) }
            let controller = session.controller
            return .init(semantics: controller.semantics(for: button), tone: controller.iconTone(for: button),
                         enabled: session.isEnabled(key.slot),
                         value: key.slot == .power ? (controller.isControlOff ? key.inactiveText : key.activeText)
                            : key.slot == .keyboard ? (session.keyboardTarget == nil ? key.inactiveText : key.activeText) : nil,
                         inputLabels: key.slot == .power
                            ? [key.label, "\(key.label) \(controller.isControlOff ? key.activeText : key.inactiveText)"] : nil)
        }, press: { [weak self] in self?.perform { try session.press(key.slot) } })
        view.accessibilityIdentifier = (definition?.node.id ?? "") + "." + key.slot.rawValue
        return view
    }

    private func make(_ remote: D.Remote, session: ServerUIRemoteSession, context: UKContext,
                      artwork: @escaping (String) -> URL?, navigate: @escaping (D.Action, UIView) -> Void) -> UIView {
        let controller = session.controller
        switch remote.control {
        case .keys(let layout, let label, let keys):
            var slots = Array<UKRemoteRoundButton?>(repeating: nil, count: layout == .pad ? 9 : 3)
            var power: UKRemoteRoundButton?
            for appearance in keys {
                let button = key(appearance, session: session, diameter: layout == .pad ? 76 : 56)
                slots[appearance.position] = button
                if appearance.slot == .power { power = button }
                if appearance.slot == .keyboard {
                    bag.observe { [weak button] in button?.isHidden = controller.hidesKeyboard }
                }
            }
            if layout == .transport { return UKRemoteTransportRow(label: label, buttons: slots) }
            return UKRemoteDPadView(label: label, rows: [Array(slots[0...2]), Array(slots[3...5]), Array(slots[6...8])],
                                   power: power, limitsToBounds: true)
        case .volume(let keys, let unavailable, let error):
            func button(_ slot: D.RemoteSlot) -> UKRemoteRoundButton? {
                // Shape + semantic compilation guarantees the exact three unique volume slots.
                guard let appearance = keys.first(where: { $0.slot == slot }) else { return nil }
                return key(appearance, session: session, diameter: HassTokens.minTarget, fill: .clear)
            }
            guard let mute = button(.volumeMute), let down = button(.volumeDown), let up = button(.volumeUp) else {
                return UKServerUIRejected.view("remote volume slots", pointer: "/document/components")
            }
            return UKRemoteVolumeCard(title: remote.node.title, mute: mute, down: down, up: up,
                                      unavailableText: unavailable, errorText: error, state: {
                .init(percent: Double(controller.volumePercent), disabled: controller.volumeDisabled,
                      visible: controller.showsVolume, failed: controller.volumeWriteFailed)
            }, commit: { [weak self] value in
                self?.perform {
                    try session.setVolume(percent: Int(value.rounded()))
                }
            }, editingChanged: { session.setEditing($0, controlID: remote.node.id) })
        case .keyboard(let copy):
            return UKRemoteKeyboardForm(copy: copy, identifier: remote.node.id, state: {
                .init(text: session.keyboardText, isOpen: session.keyboardTarget != nil,
                      canSubmit: session.keyboardTarget != nil && !controller.controlsDisabled &&
                        !session.keyboardText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      sending: session.keyboardSending, failed: session.keyboardFailed)
            }, edit: { session.keyboardText = $0 }, submit: { [weak self] in
                Task { @MainActor [weak self] in
                    do { try await session.submitKeyboard() }
                    catch { self?.report() }
                }
            }, cancel: { [weak self] in self?.perform { try session.cancelKeyboard() } })
        case .app(let key, let icon, let usesArtwork, let white, let activeText):
            guard let app = controller.config.apps.first(where: { $0.id == key }) else { return UKServerUIRejected.view("unprepared remote app", pointer: "/document/components") }
            let tile = UKAppTileView(surface: context.surface)
            bag.observe { [weak self, weak tile] in
                tile?.configure(appearance: .init(title: remote.node.title, symbol: icon.drawn, whiteBackground: white, activeText: activeText),
                                display: controller.display(app), imageURL: usesArtwork == .provider ? artwork(key) : nil,
                                identifier: remote.node.id + ".control") {
                    self?.perform {
                        guard !controller.display(app).isUnavailable else { throw ServerUIRemoteSession.InteractionError.unavailable }
                        controller.tap(app)
                    }
                }
            }
            return tile
        case .device(let key, let icon, let states, let fallback, let unavailable):
            guard let device = controller.config.devices.first(where: { $0.id == key }) else { return UKServerUIRejected.view("unprepared remote device", pointer: "/document/components") }
            if remote.deviceTile {
                let tile = UKGlassTileView(model: .init(title: remote.node.title, symbol: icon.drawn, isActive: false, identifier: remote.node.id))
                bag.observe { [weak self, weak tile] in
                    guard let self, let tile else { return }
                    let display = controller.display(device)
                    let phase: TileActionSpec.Phase = display.isDisabled ? .unavailable
                        : controller.overlay.pending[device.entityId] != nil ? .inFlight : .ready
                    var spec = TileActionSpec(id: "device", verb: display.isActive ? "Turn Off" : "Turn On",
                        symbol: "power", isOn: display.isActive, phase: phase, feedback: .optimistic,
                        isError: controller.lastCommandFailed)
                    if case .selection(let selected) = display.semantics {
                        spec.verb = selected ? "Turn Off" : "Select"
                        spec.selection = .single(isSelected: selected)
                        spec.isOn = nil
                    }
                    let specs = device.action == nil ? [] : [spec]
                    let subtitle = display.isUnavailable ? unavailable : states.first { $0.value == display.state }?.label ?? fallback
                    let model = UKGlassTileModel(title: self.title(remote), subtitle: subtitle, symbol: icon.drawn,
                        family: RoomTileFace.family(remote.deviceFamily, icon: icon.drawn),
                        isActive: display.isActive, isUnavailable: display.isUnavailable, isError: controller.lastCommandFailed,
                        behavior: specs.isEmpty ? .inert : .perform("device"), actions: specs.items, identifier: remote.node.id)
                    tile.configure(model, environment: UKTileEnvironment(context: context), animated: tile.window != nil,
                        perform: { [weak self] _ in
                            self?.perform {
                                guard !controller.display(device).isDisabled, device.action != nil else {
                                    throw ServerUIRemoteSession.InteractionError.unavailable
                                }
                                controller.tap(device)
                            }
                        })
                    tile.ukRemeasureContainers()
                }
                return tile
            }
            return UKRemoteDeviceRow(title: remote.node.title, symbol: icon.drawn, state: {
                var display = controller.display(device)
                display.subtitle = display.isUnavailable ? unavailable : states.first { $0.value == display.state }?.label ?? fallback
                return display
            }, action: { [weak self] in
                self?.perform {
                    guard !controller.display(device).isDisabled, device.action != nil else { throw ServerUIRemoteSession.InteractionError.unavailable }
                    controller.tap(device)
                }
            })
        case .hueToggle(let target, let icon, let on, let off, let unavailable):
            guard let hue = controller.config.lightSync else { return UKServerUIRejected.view("unprepared Hue Sync", pointer: "/document/components") }
            let entity = target == .power ? hue.powerEntityId : hue.lightSyncEntityId
            return UKRemoteHueToggleRow(title: remote.node.title, symbol: icon.drawn, state: {
                var display = controller.hueToggle(entity)
                display.subtitle = display.isUnavailable ? unavailable : display.isOn ? on : off
                return display
            }, action: { [weak self] in
                self?.perform { try session.toggleHue(target) }
            })
        case .hueChoice(let target, let options, let unavailable):
            guard let hue = controller.config.lightSync else { return UKServerUIRejected.view("unprepared Hue Sync", pointer: "/document/components") }
            let entity = target == .mode ? hue.syncModeEntityId : hue.intensityEntityId
            return UKRemoteHueChoiceRow(title: remote.node.title, identifier: remote.node.id, unavailableText: unavailable,
                                       optionTitle: { value in options.first { $0.value == value }?.label ?? unavailable }, state: {
                let select = controller.hueSelect(entity)
                let valid = options.map(\.value).filter(select.options.contains)
                return (valid, select.selected, select.isUnavailable || valid.isEmpty)
            }, choose: { [weak self] value in
                self?.perform { try session.chooseHue(target, value: value, allowed: options.map(\.value)) }
            })
        case .hueBrightness(let unavailable):
            guard let hue = controller.config.lightSync else { return UKServerUIRejected.view("unprepared Hue Sync", pointer: "/document/components") }
            return UKRemoteHueBrightnessRow(title: remote.node.title, unavailableText: unavailable,
                                           state: { controller.hueBrightness(hue.brightnessEntityId) }, commit: { [weak self] value in
                self?.perform { try session.setHueBrightness(value) }
            }, editingChanged: { session.setEditing($0, controlID: remote.node.id) })
        case .hueInput(let option, let icon, let selected, let connected, let disconnected, let unavailable):
            guard let hue = controller.config.lightSync else { return UKServerUIRejected.view("unprepared Hue Sync", pointer: "/document/components") }
            return UKRemoteHdmiRow(title: remote.node.title, symbol: icon.drawn, state: {
                let input = controller.hdmiInputs(hue).first { $0.option == option }
                let text = input == nil || controller.hueSelect(hue.hdmiInputEntityId).isUnavailable ? unavailable
                    : input?.isDisconnected == true ? disconnected : input?.isSelected == true ? selected : connected
                return .init(selected: input?.isSelected == true, disconnected: input?.isDisconnected ?? true,
                             disabled: input?.isDisabled ?? true, subtitle: text)
            }, action: { [weak self] in
                self?.perform { try session.selectHueInput(option) }
            })
        case .card(let key, let icon, let states, let fallback, let unavailable, let errorText, let appearances, let showsVolume, let volumeLabel, let action):
            guard let device = controller.config.devices.first(where: { $0.id == key }) else { return UKServerUIRejected.view("unprepared remote card", pointer: "/document/components") }
            let tile = UKGlassTileView(model: .init(title: remote.node.title, symbol: icon.drawn, isActive: false, identifier: remote.node.id))
            let slider = UKTileVolumeSlider(title: volumeLabel, percent: 0, identifier: remote.node.id + ".volume")
            slider.accessibilityLabel = volumeLabel
            slider.onEditingChanged = { session.setEditing($0, controlID: remote.node.id) }
            tile.setAccessory(slider)
            bag.observe { [weak self, weak tile] in
                guard let self, let tile else { return }
                let display = controller.display(device)
                let specs = session.cardActions(appearances)
                let failed = controller.lastCommandFailed || controller.volumeWriteFailed
                let text = failed ? errorText : display.isUnavailable ? unavailable : states.first { $0.value == display.state }?.label ?? fallback
                var model = UKGlassTileModel(title: remote.node.title, subtitle: text, symbol: icon.drawn, family: .media,
                                             isActive: display.isActive, isError: failed,
                                             behavior: TileBehavior(.navigation(actionCount: specs.items.count), primary: nil),
                                             actions: specs.items.map { spec in var drawn = spec; drawn.symbol = ServerUISymbolFallback.resolve(spec.symbol); return drawn },
                                             identifier: remote.node.id)
                model.stateCandidates = states.map(\.label) + [fallback, unavailable, errorText]
                model.accessoryShown = showsVolume && RemoteTileSupport.showsVolume(config: controller.config, specs: specs,
                                                                                   volume: controller.store.entity(controller.config.volumeEntityId).state)
                model.reapplyGeneration = controller.store.reapplyGeneration
                slider.update(percent: controller.volumePercent, isDisabled: controller.volumeDisabled)
                slider.onCommit = { [weak self] value in
                    self?.perform {
                        try session.setVolume(percent: value)
                    }
                }
                tile.configure(model, environment: UKTileEnvironment(context: context), animated: tile.window != nil,
                               action: { [weak tile] in
                    guard let tile else { return }
                    navigate(action, tile)
                }, perform: { [weak self] id in
                    self?.perform {
                        guard let spec = specs.first(where: { $0.id == id }) else { throw ServerUIRemoteSession.InteractionError.unknownControl }
                        try session.performCard(spec, appearances: appearances)
                    }
                })
                tile.ukRemeasureContainers()
            }
            return tile
        }
    }
}
#endif
