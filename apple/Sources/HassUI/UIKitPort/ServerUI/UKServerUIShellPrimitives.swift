#if os(iOS)
import HassCore
import HassDesign
import UIKit

// MARK: - Auto Layout bridge

/// Bridges system fitting into the existing page/grid measurement contract.
@MainActor
class UKServerUIFittingView: UIView, UKGridMeasuring {
    static func wrapping(_ content: UIView) -> UKServerUIFittingView {
        let host = UKServerUIFittingView(frame: .zero)
        host.addSubview(content)
        content.ukPin(to: host)
        return host
    }

    func gridHeight(forWidth width: CGFloat) -> CGFloat {
        ceil(systemLayoutSizeFitting(CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
                                     withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        CGSize(width: size.width, height: gridHeight(forWidth: size.width))
    }
}

// MARK: - Sections and keyed rows

@MainActor
final class UKServerUIRow: UKServerUIFittingView {
    private let row = UKRowView(.init(""))
    private var button: UKRowButton?

    init() { super.init(frame: .zero) }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func apply(_ value: ServerUICompositionDocument.Row, bindings: UKServerUIBindings, surface: TileSurface,
               enabled: Bool, action: @escaping () -> Void) {
        func text(_ binding: ServerUICompositionDocument.StringValue) -> String {
            switch bindings.string(binding) {
            case .ready(let value): value
            case .loading: value.loadingText
            case .unavailable: value.unavailableText
            }
        }
        var content = UKRowContent(text(value.primary), subtitle: text(value.secondary).nilIfEmpty,
                                   value: text(value.value).nilIfEmpty, symbol: value.icon?.drawn,
                                   showsChevron: value.accessory == .disclosure)
        content.identifier = value.node.id
        row.update(content)
        row.surface = surface
        if value.action != nil {
            if button == nil {
                row.removeFromSuperview()
                let button = UKRowButton(row)
                self.button = button
                addSubview(button)
                button.ukPin(to: self)
            }
            button?.onTap = action
            button?.isEnabled = enabled
            button?.accessibilityIdentifier = value.node.id
        } else {
            if let button { button.removeFromSuperview(); self.button = nil; row.removeFromSuperview() }
            if row.superview !== self { addSubview(row); row.ukPin(to: self) }
        }
        ukRemeasureContainers(includingSelf: true)
    }
}

@MainActor
final class UKServerUIPrimaryButton: UKServerUIFittingView {
    let button = UKPrimaryButton("") {}

    init() {
        super.init(frame: .zero)
        addSubview(button)
        button.ukPin(to: self)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

@MainActor
final class UKServerUISection: UIView, UKGridMeasuring {
    private let column = UKColumnView()
    private let header = UKPageSectionHeaderView("")
    private let footer = UILabel.uk(.footnote, ink: UKDesignInk.secondary)
    private var body: UIView?
    private var children: [UIView] = []
    private var style: ServerUICompositionDocument.Section.Style?
    private var density: ServerUICompositionDocument.Section.Density?
    private var hasGlyphs: Bool?

    init() {
        super.init(frame: .zero)
        addSubview(column)
        shouldGroupAccessibilityChildren = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func needsReparent(_ value: ServerUICompositionDocument.Section, children: [UIView]) -> Bool {
        self.children != children || style != value.style || density != value.density || hasGlyphs != value.hasGlyphs
    }

    func clear() {
        (body as? UKColumnView)?.setViews([])
        body?.subviews.compactMap { $0 as? UKModuleListView }.forEach { $0.setRows([]) }
        children = []
    }

    func apply(_ value: ServerUICompositionDocument.Section, children: [UIView], surface: TileSurface,
               state: UKServerUISectionState = .init()) {
        if needsReparent(value, children: children) {
            clear()
            body?.removeFromSuperview()
            if value.style == .moduleList {
                body = UKServerUIFittingView.wrapping(UKModuleListView(value.density == .dense ? .dense : .thin,
                                                                     hasGlyphs: value.hasGlyphs, surface: surface, rows: children))
            } else {
                let column = UKColumnView()
                column.spacing = value.spacing.points
                column.setViews(children)
                body = column
            }
            self.children = children
            style = value.style
            density = value.density
            hasGlyphs = value.hasGlyphs
        }
        body?.subviews.compactMap { $0 as? UKModuleListView }.forEach { $0.surface = surface }
        if let column = body as? UKColumnView { column.spacing = value.spacing.points }
        column.spacing = value.spacing.points
        let title = state.header ?? value.header
        let description = state.footer ?? value.footer
        header.configure(title: title, detail: state.detail)
        header.surface = surface
        footer.text = description
        footer.textColor = surface == .sheet ? UKDesignInk.secondary : UKInk.onDarkSecondary
        let wanted = (title.isEmpty && state.detail == nil ? [] : [header]) + [body].compactMap { $0 }
            + (description.isEmpty ? [] : [footer])
        if column.views != wanted { column.setViews(wanted) }
    }

    func gridHeight(forWidth width: CGFloat) -> CGFloat { column.gridHeight(forWidth: width) }
    override func sizeThatFits(_ size: CGSize) -> CGSize { column.sizeThatFits(size) }
    override func layoutSubviews() { super.layoutSubviews(); column.frame = bounds }
}

/// A bounded collection uses the existing module rows, retaining each row instance by provider key.
@MainActor
final class UKServerUIRowCollection: UKServerUIFittingView {
    private let stack = UIStackView()
    private let list = UKModuleListView(hasGlyphs: false)
    private let message = UILabel.uk(.body, ink: UKDesignInk.secondary)
    private(set) var rows: [String: UKRowView] = [:]
    private var order: [String] = []

    init() {
        super.init(frame: .zero)
        stack.axis = .vertical
        stack.spacing = HassTokens.Spacing.s
        stack.addArrangedSubview(message)
        stack.addArrangedSubview(list)
        addSubview(stack)
        stack.ukPin(to: self)
        message.accessibilityTraits = .staticText
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func apply(_ value: ServerUICompositionDocument.RowCollection, model: ServerUIRowCollection, surface: TileSurface) {
        var retained: [String: UKRowView] = [:]
        for item in model.rows {
            var content = UKRowContent(item.title, subtitle: item.subtitle, value: item.value)
            content.identifier = value.node.id + "." + item.id
            let row = rows[item.id] ?? UKRowView(content, surface: surface)
            row.update(content)
            row.surface = surface
            row.accessibilityIdentifier = value.node.id + "." + item.id
            retained[item.id] = row
        }
        let nextOrder = model.rows.map(\.id)
        if nextOrder != order {
            list.setRows(nextOrder.compactMap { retained[$0] })
            order = nextOrder
        }
        rows = retained
        list.surface = surface
        switch model.phase {
        case .loading: message.text = value.loadingText
        case .ready: message.text = model.rows.isEmpty ? value.emptyText : nil
        case .stale: message.text = value.staleText
        case .failed: message.text = value.errorText
        case .unavailable: message.text = value.unavailableText
        }
        message.isHidden = message.text == nil
        list.isHidden = model.rows.isEmpty
        ukRemeasureContainers(includingSelf: true)
    }
}

// MARK: - Value controls

/// The canonical value controls over a ``UKServerUIControlBinding``: scene-local state (`local-control`) or a Home Assistant
/// entity with authored service calls (`bound-control`). The controls show the value they are given and report intent through
/// `send`; no optimistic domain or automation semantics live here.
@MainActor
final class UKServerUILocalControl: UKServerUIFittingView {
    typealias D = ServerUICompositionDocument
    private var spec: UKServerUIControlSpec?
    private var content: UIView?
    private var row: UKRowView?
    private var control: UIView?
    private var show: (D.LocalValue) -> Void = { _ in }
    private var enable: (Bool) -> Void = { _ in }
    private var sliderWork: Task<Void, Never>?
    private var lastSent: D.LocalValue?
    private var ruleDisabled = false

    init() { super.init(frame: .zero) }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func showAccepted(_ value: D.LocalValue) { show(value) }

    /// The control currently drawn, for hosted tests and accessibility checks.
    var drawnControl: UIView? { control }

    /// A scene-local control: the field's value, written through `send`.
    func apply(_ definition: D.LocalControl, field: D.LocalField, value: D.LocalValue,
               surface: TileSurface, send: @escaping (D.LocalValue) -> Void) {
        guard let binding = UKServerUILocalBinding(definition, field: field, value: value, send: send) else {
            // A document field that does not fit its control stays an inert titled row; nothing is sent.
            spec = nil
            content?.removeFromSuperview()
            let inert = UKRowView(.init(definition.node.title), surface: surface)
            content = inert
            addSubview(inert)
            inert.ukPin(to: self)
            return
        }
        apply(binding, surface: surface)
    }

    /// Draws `binding`'s control (rebuilt only when what it draws changes) and shows its value; `nil` is unavailable.
    func apply(_ binding: some UKServerUIControlBinding, surface: TileSurface, enabled: Bool = true) {
        let spec = binding.spec
        let send: (D.LocalValue) -> Void = { [weak self] value in
            guard let self else { return }
            if case .slider = spec.face { self.debouncedSend(binding, value) } else { binding.send(value) }
        }
        if self.spec != spec {
            content?.removeFromSuperview()
            self.spec = spec
            build(spec, surface: surface, send: send)
        }
        (content as? UKSurfaceStyled)?.surface = surface
        let value = binding.value()
        setAvailable(value != nil, spec: spec)
        if let value { show(value) }
        setEnabledByRule(enabled, spec: spec)
    }

    /// `enabledWhen`: while it says no the control cannot be touched and reads as dimmed and not enabled; when it says yes again the
    /// control goes back to whatever availability alone gave it.
    private func setEnabledByRule(_ enabled: Bool, spec: UKServerUIControlSpec) {
        if !enabled {
            ruleDisabled = true
            control?.isUserInteractionEnabled = false
            control?.alpha = 0.5
            enable(false)
            control?.accessibilityTraits.insert(.notEnabled)
        } else if ruleDisabled {
            ruleDisabled = false
            if spec.unavailableText == nil {
                control?.isUserInteractionEnabled = true
                control?.alpha = 1
                enable(true)
            }
            control?.accessibilityTraits.remove(.notEnabled)
        }
    }

    /// A slider reports every detent while it is dragged; the call goes out once the thumb has rested.
    private func debouncedSend(_ binding: some UKServerUIControlBinding, _ value: D.LocalValue) {
        lastSent = value
        sliderWork?.cancel()
        sliderWork = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, self?.lastSent == value else { return }
            binding.send(value)
        }
    }

    private func setAvailable(_ available: Bool, spec: UKServerUIControlSpec) {
        guard spec.unavailableText != nil else { return }
        control?.isUserInteractionEnabled = available
        control?.alpha = available ? 1 : 0.5
        if let row, !(row is UKPercentSliderRow) {
            row.update(UKRowContent(spec.title, subtitle: available ? nil : spec.unavailableText))
        }
        enable(available)
        control?.accessibilityValue = available ? control?.accessibilityValue : spec.unavailableText
    }

    private func build(_ spec: UKServerUIControlSpec, surface: TileSurface, send: @escaping (D.LocalValue) -> Void) {
        let row = UKRowView(.init(spec.title), surface: surface)
        self.row = row
        enable = { _ in }
        var host: UIView = row
        switch spec.face {
        case .toggle:
            let toggle = UKControllerToggle(isOn: false) { send(.boolean($0)) }
            toggle.accessibilityLabel = spec.title
            toggle.accessibilityIdentifier = spec.identifier + ".value"
            row.setAccessory(toggle)
            row.isTextAccessible = false
            control = toggle
            show = { if case .boolean(let value) = $0 { toggle.show(value) } }
        case .stepper(let minimum, let maximum, let step, let format):
            let stepper = UKControllerStepper(value: minimum, in: minimum...maximum, step: step, title: spec.title,
                                              format: { format?.replacingOccurrences(of: "{value}", with: "\($0)") ?? "\($0)" }) {
                send(.number(Double($0)))
            }
            stepper.accessibilityIdentifier = spec.identifier + ".value"
            row.setBody(stepper)
            row.isTextAccessible = false
            control = stepper
            show = { if case .number(let value) = $0 { stepper.show(Int(value.rounded())) } }
        case .slider:
            let slider = UKPercentSliderRow(spec.title, value: 0, identifier: spec.identifier + ".value") { send(.number($0)) }
            host = slider
            self.row = slider
            control = slider
            enable = { slider.isEnabled = $0 }
            show = { if case .number(let value) = $0 { slider.value = (min(max(value, 0), 100) / 5).rounded() * 5 } }
        case .choice(let options):
            let names = Dictionary(uniqueKeysWithValues: options.map { ($0.id, $0.label) })
            let picker = UKControllerPicker(spec.title, options: options.map(\.id), optionTitle: { names[$0] ?? "" },
                                            selection: options.first?.id ?? "") { send(.string($0)) }
            picker.accessibilityIdentifier = spec.identifier + ".value"
            picker.heightAnchor.constraint(greaterThanOrEqualToConstant: HassTokens.minTarget).isActive = true
            row.setAccessory(picker)
            row.isTextAccessible = false
            control = picker
            show = { if case .string(let value) = $0 { picker.show(value) } }
        case .segmented(let options):
            let names = Dictionary(uniqueKeysWithValues: options.map { ($0.id, $0.label) })
            let segmented = UKSegmentedChoice(label: spec.title, options: options.map(\.id), title: { names[$0] ?? $0 },
                                              selection: nil, identifier: spec.identifier + ".value") { send(.string($0)) }
            row.setBody(segmented)
            control = segmented
            enable = { segmented.isEnabled = $0 }
            show = { if case .string(let value) = $0 { segmented.selection = options.contains { $0.id == value } ? value : nil } }
        case .text(let placeholder):
            let field = UITextField()
            field.font = UKFont.preferred(.body)
            field.adjustsFontForContentSizeCategory = true
            field.textColor = UKDesignInk.primary
            field.placeholder = placeholder
            field.accessibilityLabel = spec.title
            field.accessibilityIdentifier = spec.identifier + ".value"
            field.heightAnchor.constraint(greaterThanOrEqualToConstant: HassTokens.minTarget).isActive = true
            field.addAction(UIAction { [weak field] _ in
                guard let field, field.markedTextRange == nil else { return }
                send(.string(field.text ?? ""))
            }, for: .editingChanged)
            field.returnKeyType = .done
            field.addAction(UIAction { [weak field] _ in field?.resignFirstResponder() }, for: .editingDidEndOnExit)
            row.setBody(field)
            control = field
            show = { if case .string(let value) = $0, field.text != value { field.text = value } }
        }
        content = host
        addSubview(host)
        host.ukPin(to: self)
    }
}

// MARK: - Retained local tabs

/// All panels retain their keyed children. Only the displayed panel belongs to the accessibility tree.
@MainActor
final class UKServerUILocalTabs: UIView, UKGridMeasuring {
    typealias D = ServerUICompositionDocument
    private struct TabID: Hashable, Identifiable { let id: String }
    private let column = UKColumnView(spacing: HassTokens.Spacing.m)
    private var panels: [String: UKColumnView] = [:]
    private var swap: UKSmoothContentSwapView<String>?
    private var choice: UKSegmentedChoice<String>?
    private var definition: D.LocalTabs?
    private var tabBar: UKModalTabBar<TabID>?
    private var pinnedBar: UKPagePinnedBar?
    private var barHost: UIView?
    private weak var page: UKServerUIPage?
    private var centerWhenFits = false
    private var automatic = ServerUIAutomaticSelection()
    private var scopeInitialized = false
    private var scopedInitial: String?
    private var scopedAllowed: [String] = []
    var isTransitioning: Bool { swap?.isTransitioning == true }

    init() {
        super.init(frame: .zero)
        addSubview(column)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func needsReparent(_ value: D.LocalTabs, children: [[UIView]]) -> Bool {
        zip(value.tabs, children).contains { panels[$0.0.id]?.views != $0.1 }
            || panels.keys.contains { id in !value.tabs.contains { $0.id == id } }
    }

    func clear() {
        for panel in panels.values {
            panel.setViews([])
        }
    }

    func prepareScope(_ scope: UKServerUITabScope, stateID: String, state: ServerUILocalState) throws {
        guard !scopeInitialized || scopedAllowed != scope.allowedTabIDs || scopedInitial != scope.initialTabID else { return }
        let selection: String
        if scopeInitialized, case .string(let current) = state.values[stateID], scope.allowedTabIDs.contains(current) {
            selection = current
        } else {
            selection = scope.initialTabID
        }
        try state.set(.string(selection), for: stateID)
        automatic = .init()
        scopeInitialized = true
        scopedInitial = scope.initialTabID
        scopedAllowed = scope.allowedTabIDs
    }

    func resolveSelection(_ scope: UKServerUITabScope?, stored: String, value: D.LocalTabs) throws -> String {
        guard let scope else { return stored }
        let proposed = scope.automaticSelection?() ?? stored
        return try automatic.resolve(proposed, initial: scope.initialTabID, allowed: scope.allowedTabIDs,
                                     retainsEngaged: value.retainsAutomaticSelection)
    }

    func departed() {
        if let scopedInitial { automatic.departed(initial: scopedInitial, retainsEngaged: definition?.retainsAutomaticSelection == true) }
    }

    func apply(_ value: D.LocalTabs, children: [[UIView]], selection: String, page: UKServerUIPage,
               badges: [String: Int] = [:], send: @escaping (String) -> Void) {
        self.page = page
        centerWhenFits = value.tabs.first(where: { $0.id == selection })?.centerWhenFits == true
        for (tab, views) in zip(value.tabs, children) {
            let panel = panels[tab.id] ?? UKColumnView()
            panel.spacing = HassTokens.Spacing.m
            panel.shouldGroupAccessibilityChildren = true
            if panel.views != views { panel.setViews(views) }
            panels[tab.id] = panel
        }
        panels = panels.filter { entry in value.tabs.contains { $0.id == entry.key } }
        if definition != value {
            detach()
            column.setViews([])
            let names = Dictionary(value.tabs.map { ($0.id, $0.label) }, uniquingKeysWith: { first, _ in first })
            let choice = UKSegmentedChoice(label: value.node.title, options: value.tabs.map(\.id), title: { names[$0] ?? $0 },
                                           selection: selection, identifier: value.node.id + ".tabs", select: send)
            let swap = UKSmoothContentSwapView(initial: selection) { [weak self] key in
                guard let panel = self?.panels[key] else { return UIView() }
                return panel
            }
            swap.didSwap = { [weak self] _ in self?.ukRemeasureContainers(includingSelf: true) }
            let displayed = UKServerUISwapMeasurement(swap) { [weak self, weak swap] width in
                guard let self, let swap, let panel = self.panels[swap.displayed] else { return 0 }
                return panel.gridHeight(forWidth: width)
            }
            if value.pinned {
                let icons = Dictionary(value.tabs.compactMap { tab in tab.icon.map { (tab.id, $0.drawn) } }, uniquingKeysWith: { first, _ in first })
                let bar = UKModalTabBar(tabs: value.tabs.map { TabID(id: $0.id) }, label: value.node.title,
                    title: { names[$0.id] ?? $0.id }, symbol: { icons[$0.id] ?? "circle" },
                    badge: value.scopeProviderId == nil ? nil : { badges[$0.id] ?? 0 }, selection: TabID(id: selection),
                    identifier: value.node.id + ".tabs", onSelect: { send($0.id) })
                let host = bar.inset()
                let pinned = UKPagePinnedBar(bar: host, scrollView: page.body)
                pinned.install(in: page)
                tabBar = bar; pinnedBar = pinned; barHost = host
                column.setViews([displayed])
                self.choice = nil
            } else {
                column.setViews(value.showsSelector ? [UKServerUIFittingView.wrapping(choice), displayed] : [displayed])
                self.choice = value.showsSelector ? choice : nil
            }
            self.swap = swap
            definition = value
        }
        choice?.selection = selection
        tabBar?.selection = TabID(id: selection)
        if value.scopeProviderId != nil { tabBar?.updateBadges { badges[$0.id] ?? 0 } }
        swap?.show(selection)
        layoutChanged()
    }

    func detach() {
        pinnedBar?.follow(nil)
        barHost?.removeFromSuperview()
        if pinnedBar != nil { page?.additionalSafeAreaInsets.bottom = 0 }
        pinnedBar = nil; barHost = nil; tabBar = nil
    }

    func layoutChanged() { pinnedBar?.layoutChanged() }

    func gridHeight(forWidth width: CGFloat) -> CGFloat {
        let natural = column.gridHeight(forWidth: width)
        guard centerWhenFits, let scroll = page?.body else { return natural }
        return max(natural, scroll.bounds.height - scroll.adjustedContentInset.top - scroll.adjustedContentInset.bottom
                   - scroll.padding.top - scroll.padding.bottom)
    }
    override func sizeThatFits(_ size: CGSize) -> CGSize { .init(width: size.width, height: gridHeight(forWidth: size.width)) }
    override func layoutSubviews() {
        super.layoutSubviews()
        let height = centerWhenFits ? min(bounds.height, column.gridHeight(forWidth: bounds.width)) : bounds.height
        column.frame = CGRect(x: 0, y: centerWhenFits ? max(0, (bounds.height - height) / 2) : 0, width: bounds.width, height: height)
        layoutChanged()
    }
}

/// Gives the canonical swap its displayed panel's natural height without introducing a second layout solver.
@MainActor
private final class UKServerUISwapMeasurement: UIView, UKGridMeasuring {
    private let content: UIView
    private let height: (CGFloat) -> CGFloat
    init(_ content: UIView, height: @escaping (CGFloat) -> CGFloat) {
        self.content = content
        self.height = height
        super.init(frame: .zero)
        addSubview(content)
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    func gridHeight(forWidth width: CGFloat) -> CGFloat { height(width) }
    override func layoutSubviews() { super.layoutSubviews(); content.frame = bounds }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
#endif
