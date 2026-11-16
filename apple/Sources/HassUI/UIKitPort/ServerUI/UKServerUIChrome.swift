#if os(iOS)
import HassCore
import UIKit

// MARK: - Configured native bar items

/// Per-page bar objects with cross-page semantic identifiers, using the canonical system/material branches.
@MainActor
final class UKServerUIChrome {
    typealias D = ServerUICompositionDocument
    private weak var page: UKServerUIPage?
    private var items: [String: UIBarButtonItem] = [:]
    private var circles: [String: UKMaterialCircleButton] = [:]
    private var spaces: [String: UIBarButtonItem] = [:]
    private let bag = UKObservationBag()
    private var menu: UIBarButtonItem?
    private var closeItem: UIBarButtonItem?
    private var lastGroups: [D.ChromeGroup]?
    private var lastRail: Bool?
    private var lastMenu: Bool?
    private var lastClose: D.Close?
    private var shellHeader: UKShellHeaderItems?
    private var headerDefinition: D.ShellHeader?

    init(page: UKServerUIPage) { self.page = page }

    func apply(groups: [D.ChromeGroup], close: D.Close?) {
        guard let page, let renderer = page.renderer else { return }
        let rail = page.context.shell?.inVerticalBar == true
        let menuAvailable = !page.isSheet && page.depth == 0 && page.context.shell?.chrome.showsMenuButton == true
        let facts = UKServerUIPreflight.facts
        bag.removeAll()
        menu = nil
        var changed = lastGroups != groups || lastRail != rail || lastMenu != menuAvailable || lastClose != close
        lastGroups = groups
        lastRail = rail
        lastMenu = menuAvailable
        lastClose = close
        let ids = Set(groups.flatMap(\.items).map(\.id))
        items = items.filter { ids.contains($0.key) }
        circles = circles.filter { ids.contains($0.key) }
        let spaceIDs = Set(ids.map { "item." + $0 }).union(["host.close"])
        spaces = spaces.filter { spaceIDs.contains($0.key) }
        var leading: [(D.ChromeGroup, [UIBarButtonItem])] = []
        var trailing: [(D.ChromeGroup, [UIBarButtonItem])] = []
        for group in groups {
            var visible: [UIBarButtonItem] = []
            for definition in group.items {
                if case .shellHeader(let definition) = definition {
                    guard definition.visibility == .always || page.depth == 0 else { continue }
                    guard let source = renderer.shellHeader else {
                        renderer.onError(.init(code: .unavailableSource, pointer: "/document/navigation/chrome"))
                        return
                    }
                    headerDefinition = definition
                    if shellHeader == nil {
                        let header = UKShellHeaderItems(openQuickLinks: { [weak self, weak page] in
                            guard let page, let action = self?.headerDefinition?.quickLinksAction else { return }
                            page.renderer?.activate(action, from: page)
                        }, openAccount: { [weak self, weak page] in
                            guard let page, let action = self?.headerDefinition?.profileAction else { return }
                            page.renderer?.activate(action, from: page)
                        })
                        header.bindAvatar(source.avatar)
                        shellHeader = header
                    }
                    var state = source.state()
                    state.inVerticalBar = rail
                    state.contentSize = page.traitCollection.preferredContentSizeCategory
                    changed = changed || shellHeader?.lastState != state
                    if let shellHeader { visible.append(contentsOf: shellHeader.items(for: state).reversed()) }
                    bag.observe { [weak self, weak page] in
                        guard let self, let page else { return }
                        var next = source.state()
                        next.inVerticalBar = page.context.shell?.inVerticalBar == true
                        next.contentSize = page.traitCollection.preferredContentSizeCategory
                        if shellHeader?.lastState != next { page.refreshChrome() }
                    }
                    continue
                }
                let id = definition.id
                let label: String
                let menuLabel: String
                let icon: String
                let action: D.Action?
                let priority: D.Priority
                let axis: D.Rail
                switch definition {
                case .shellMenu(let value):
                    guard menuAvailable else { continue }
                    label = value.label; menuLabel = value.label; icon = value.icon.drawn
                    action = nil; priority = .required; axis = .eligible
                case .button(let value):
                    guard value.visibility == .always || page.depth == 0 else { continue }
                    label = value.label; menuLabel = value.menuLabel; icon = value.icon.drawn
                    action = value.action; priority = facts.priority(value.priority); axis = facts.rail(value.rail)
                case .shellHeader: continue
                }
                let run: () -> Void = { [weak page] in
                    guard let page else { return }
                    if let action { page.renderer?.activate(action, from: page, symbol: icon) }
                    else { page.openMenu() }
                }
                let image = UIImage(systemName: icon, withConfiguration: UIImage.SymbolConfiguration(font: UKShellFont.preferred(.body, weight: .medium)))
                let item: UIBarButtonItem
                if let existing = items[id] { item = existing }
                else if UKGlassEra.hasGlass {
                    item = UIBarButtonItem()
                    items[id] = item
                } else {
                    let circle = UKMaterialCircleButton(image: image)
                    circles[id] = circle
                    item = UIBarButtonItem(customView: circle)
                    items[id] = item
                }
                if item.customView == nil { item.image = image; item.primaryAction = UIAction { _ in run() } }
                circles[id]?.onTap = run
                // A changed definition gets a fresh glyph in pre-glass bars too, without replacing an unaffected item.
                if changed, let circle = circles[id] {
                    let replacement = UKMaterialCircleButton(image: image)
                    replacement.onTap = run
                    item.customView = replacement
                    circles[id] = replacement
                    circle.removeFromSuperview()
                }
                item.title = menuLabel
                item.accessibilityLabel = label
                item.accessibilityIdentifier = id
                item.largeContentSizeImage = image
                item.menuRepresentation = UIAction(title: menuLabel, image: image) { _ in run() }
                if #available(iOS 26.0, *) { item.identifier = id }
                if #available(iOS 27.0, *) {
                    switch priority {
                    case .required: item.visibilityPriority = .high
                    case .normal: item.visibilityPriority = .standard
                    case .low: item.visibilityPriority = .low
                    }
                }
                #if !FENTON_IOS_SDK_BEFORE_27_1
                if #available(iOS 27.1, *) { item.axisBehavior = axis == .eligible ? .verticalPreferred : .horizontalOnly }
                #endif
                circles[id]?.accessibilityLabel = label
                circles[id]?.accessibilityIdentifier = id
                if let action {
                    bag.observe { [weak item, weak page, weak renderer, weak self] in
                        guard let page, let renderer else { return }
                        let enabled = renderer.isEnabled(action, from: page)
                        item?.isEnabled = enabled
                        self?.circles[id]?.isEnabled = enabled
                    }
                } else { menu = item; item.isEnabled = true }
                visible.append(item)
            }
            if group.placement == .leading { leading.append((group, visible)) }
            else { trailing.append((group, visible)) }
        }
        if let close, page.depth == 0 || close.visibility == .allDepths {
            if closeItem == nil {
                closeItem = UKSheetItems.close(identifier: "server-ui.sheet.close") { [weak page] in
                    guard let page else { return }
                    page.renderer?.activate(.dismiss(scope: .currentModal), from: page)
                }
            }
        } else { closeItem = nil }
        page.navigationItem.leftItemsSupplementBackButton = true
        if changed {
            install(leading, trailing: false, rail: rail)
            install(trailing, trailing: true, rail: rail, hostClose: closeItem)
        }
    }

    private func install(_ definitions: [(D.ChromeGroup, [UIBarButtonItem])], trailing: Bool, rail: Bool,
                         hostClose: UIBarButtonItem? = nil) {
        guard let page else { return }
        let navigation = page.navigationItem
        let shared = rail || definitions.contains { UKServerUIPreflight.facts.horizontal($0.0.horizontal) == .shared }
        if shared {
            var groups: [UIBarButtonItemGroup] = []
            for (definition, items) in definitions where !items.isEmpty {
                if rail && definition.vertical == .separate {
                    groups += items.map { UIBarButtonItemGroup(barButtonItems: [$0], representativeItem: nil) }
                } else {
                    groups.append(UIBarButtonItemGroup(barButtonItems: items, representativeItem: nil))
                }
            }
            if let hostClose { groups.append(UIBarButtonItemGroup(barButtonItems: [hostClose], representativeItem: nil)) }
            if trailing { navigation.trailingItemGroups = groups }
            else { navigation.leadingItemGroups = groups }
        } else {
            var result: [UIBarButtonItem] = []
            for item in definitions.flatMap(\.1) + [hostClose].compactMap({ $0 }) {
                if UKGlassEra.hasGlass, !result.isEmpty {
                    let key = item === hostClose ? "host.close" : "item." + (item.accessibilityIdentifier ?? "")
                    let spacer = spaces[key] ?? UIBarButtonItem.fixedSpace(12)
                    spaces[key] = spacer
                    result.append(spacer)
                }
                result.append(item)
            }
            if trailing {
                navigation.trailingItemGroups = []
                let desired = Array(result.reversed())
                if navigation.rightBarButtonItems != desired { navigation.rightBarButtonItems = desired }
            } else {
                navigation.leadingItemGroups = []
                if navigation.leftBarButtonItems != result { navigation.leftBarButtonItems = result }
            }
        }
    }

    func focusMenu() {
        if let menu { UIAccessibility.post(notification: .layoutChanged, argument: menu) }
    }
}
#endif
