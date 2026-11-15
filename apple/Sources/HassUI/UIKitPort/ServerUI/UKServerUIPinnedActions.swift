#if os(iOS)
import HassCore
import HassDesign
import UIKit

// MARK: - Authored canonical bottom actions

@MainActor
final class UKServerUIPinnedActions: UIView {
    private var bar: UKFloatingActionBar?
    private var pinned: UKPagePinnedBar?
    private var search: UKFloatingSearch?
    private var definition: ServerUICompositionDocument.PinnedActions?
    private let bag = UKObservationBag()
    private var builtKeys: [String] = []
    private var builtTitles: [Bool] = []
    private var searchShown: Bool?
    private var formStack: UIStackView?
    private var formButtons: [String: UIControl] = [:]
    private var nativeControls: [UIView] = []

    init() { super.init(frame: .zero) }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func bind(_ authored: ServerUICompositionDocument.PinnedActions, page: UKServerUIPage, controls: [UIView]? = nil) {
        guard let renderer = page.renderer else { return }
        if definition?.style != authored.style {
            bar?.removeFromSuperview(); bar = nil
            formStack?.removeFromSuperview(); formStack = nil
            formButtons = [:]
            isHidden = false; alpha = 1; isUserInteractionEnabled = true; accessibilityElementsHidden = false
            pinned?.removeMaterial(); pinned?.follow(nil); pinned = nil
        }
        if let controls { nativeControls = controls }
        if authored.style == .form {
            bindForm(authored, page: page)
            return
        }
        var value = authored
        var sender = page
        let isCreateBar = !authored.items.isEmpty && authored.items.allSatisfy { $0.role == .create }
        var hidden = false
        if isCreateBar, page.columns?.isWide == true,
           let detail = page.columns?.entries.last?.controller as? UKServerUIPage {
            if detail.formView != nil { hidden = true }
            else if let other = detail.pinnedDefinition, other.items.allSatisfy({ $0.role == .create }) {
                value = other; sender = detail
            }

        } else if isCreateBar, let columns = page.parent as? UKColumnsViewController,
                  let owner = columns.parent as? UKServerUIPage,
                  owner.pinnedDefinition?.items.allSatisfy({ $0.role == .create }) == true {
            hidden = true
        }
        alpha = hidden ? 0 : 1
        isUserInteractionEnabled = !hidden
        accessibilityElementsHidden = hidden
        let provider = value.searchProviderId.flatMap { renderer.recordCollection($0) }
        bag.removeAll()
        if definition?.searchProviderId != value.searchProviderId || definition?.searchPrompt != value.searchPrompt || bar == nil {
            bar?.removeFromSuperview()
            search = provider.map { UKFloatingSearch(prompt: value.searchPrompt, text: $0.searchText, isExpanded: !$0.searchText.isEmpty) }
            let bar = UKFloatingActionBar(actions: [], search: search)
            self.bar = bar
            builtKeys = []; builtTitles = []; searchShown = nil
            addSubview(bar); bar.ukPin(to: self)
        }
        if let provider, let search {
            bag.observe {
                if provider.searchText != search.text { provider.searchText = search.text }
            }
        }
        let target = sender
        bag.observe { [weak self, weak target] in
            guard let self, let target else { return }
            let items = value.items.compactMap { item -> (ServerUICompositionDocument.PinnedActions.Item, UKServerUIActionState)? in
                let state = item.role.flatMap { provider?.actionState($0) } ?? .init()
                return state.visible ? (item, state) : nil
            }
            let keys = items.map { $0.0.id }, titles = items.map { $0.1.showsTitle ?? $0.0.showsTitle }
            if definition != value || builtKeys != keys || builtTitles != titles {
                builtKeys = keys; builtTitles = titles
                bar?.actions = items.map { item, state in
                    UKFloatingAction(id: item.id, title: item.title, symbol: item.icon.drawn,
                        showsTitle: state.showsTitle ?? item.showsTitle, isActive: state.active, isProminent: item.prominent) { [weak target] in
                        guard let target else { return }
                        target.renderer?.activate(item.action, from: target)
                    }
                }
            } else {
                for (item, state) in items { bar?.setActive(state.active, forActionID: item.id) }
            }
            let shows = provider?.showsSearch == true
            if searchShown != shows { searchShown = shows; bar?.setSearch(shows ? search : nil) }
            definition = value
            pinned?.layoutChanged()
        }
        if pinned == nil {
            let pinned = UKPagePinnedBar(bar: self, edge: .bottom, scrollView: page.pageScroll)
            self.pinned = pinned
            pinned.install(in: page)
        }
        pinned?.layoutChanged()
    }

    private func bindForm(_ value: ServerUICompositionDocument.PinnedActions, page: UKServerUIPage) {
        guard let renderer = page.renderer else { return }
        bag.removeAll()
        if formStack == nil {
            let stack = UIStackView.ukColumn(spacing: HassTokens.Spacing.s)
            stack.isLayoutMarginsRelativeArrangement = true
            // This bar creates the page's bottom inset; inheriting it would add its own height on every layout.
            stack.insetsLayoutMarginsFromSafeArea = false
            stack.layoutMargins = .ukAll(HassTokens.Spacing.l)
            addSubview(stack); stack.ukPin(to: self)
            formStack = stack
        }
        definition = value
        bag.observe { [weak self, weak page, weak renderer] in
            guard let self, let page, let renderer, let stack = formStack else { return }
            var views: [UIView] = nativeControls
            for item in value.items {
                let state = item.stateProviderId.flatMap { renderer.records.actionStates[$0]?() } ?? .init()
                let action = { [weak page] in
                    guard let page else { return }
                    page.renderer?.activate(item.action, from: page)
                }
                let control: UIControl
                if item.prominent {
                    let button = (formButtons[item.id] as? UKPrimaryButton) ?? UKPrimaryButton(item.title, action: action)
                    button.title = item.title
                    button.action = action
                    button.isBusy = state.busy
                    button.isEnabled = state.enabled && !state.busy
                    control = button
                } else {
                    let button = (formButtons[item.id] as? UKFormActionRow)
                        ?? UKFormActionRow(title: item.title, ink: UKDesignInk.action, identifier: item.id)
                    button.onTap = action
                    button.show(title: item.title, isEnabled: state.enabled && !state.busy)
                    control = button
                }
                control.accessibilityIdentifier = item.id
                formButtons[item.id] = control
                if state.visible { views.append(control) }
            }
            if stack.arrangedSubviews != views {
                stack.arrangedSubviews.forEach { stack.removeArrangedSubview($0); $0.removeFromSuperview() }
                views.forEach(stack.addArrangedSubview)
            }
            isHidden = views.isEmpty
            pinned?.layoutChanged()
        }
        if pinned == nil {
            let pinned = UKPagePinnedBar(bar: self, scrollView: page.pageScroll, barMaterial: true)
            self.pinned = pinned
            pinned.install(in: page)
        }
        pinned?.layoutChanged()
    }

    func layoutChanged() { pinned?.layoutChanged() }
    func releaseControls() { nativeControls.forEach { $0.removeFromSuperview() } }
    func detach() { pinned?.follow(nil); pinned?.removeMaterial(); removeFromSuperview(); pinned = nil }
}
#endif
