#if os(iOS)
import HassCore
import HassDesign
import UIKit

// MARK: - UIKit acceptance

extension ServerUIDeviceFacts {
    /// The running device: the OS versions that honour chrome priority and a horizontal-only rail, glass, and the symbol set it draws.
    static var current: ServerUIDeviceFacts {
        let priority: Bool
        if #available(iOS 27.0, *) { priority = true } else { priority = false }
        #if FENTON_IOS_SDK_BEFORE_27_1
        let rail = false
        #else
        let rail: Bool
        if #available(iOS 27.1, *) { rail = true } else { rail = false }
        #endif
        return ServerUIDeviceFacts(hasGlass: UKGlassEra.hasGlass, supportsPriority: priority,
                                   supportsHorizontalOnlyRail: rail, drawsSymbol: { UIImage(systemName: $0) != nil })
    }
}

/// Renderer diagnostics contain locations and codes, never document copy or entity values.
struct UKServerUIRendererError: Error, Equatable, CustomStringConvertible, ServerUIDiagnosable {
    enum Code: String {
        case unsupportedPolicy = "unsupported_capability"
        /// Retained for the diagnostic vocabulary. A symbol the OS lacks degrades the node and is never thrown.
        case symbolUnavailable = "symbol_unavailable"
        case interactionBlocked = "interaction_blocked"
        case differentDocument = "different_document"
        case unavailableSource = "unavailable_source"
        /// An input the document binds has not arrived yet (house configuration, the signed-in user). Timing, not a rejection.
        case inputsPending = "inputs_pending"
    }

    let code: Code
    let pointer: String
    var description: String { "\(code.rawValue) at \(pointer)" }
    /// The case and pointer only, for the rejection log and the DEBUG boundary label.
    var diagnostic: String { description }
}

/// Exact mappings to canonical primitives. Wire validation is Core's; OS support is this gate's.
@MainActor
enum UKServerUIPreflight {
    typealias D = ServerUICompositionDocument

    /// A test's forced OS gaps. Assign it to model an older OS and set it back to nil afterwards.
    static var override: ServerUIDeviceFacts? {
        didSet { ServerUISymbolFallback.install(facts.drawsSymbol) }
    }

    /// What this device draws: the override, or the running OS.
    static var facts: ServerUIDeviceFacts { override ?? .current }

    /// The degrades the running validation found. Preflight is synchronous on the main actor, so one pass owns it at a time.
    private static var found: [ServerUIDegradation] = []

    /// Validates every definition, including unreachable surfaces. Does not publish, fetch or stage assets.
    ///
    /// A document that is invalid throws. A device fact (an SF Symbol this OS lacks, a chrome priority or rail it does not honour,
    /// a shared group before glass) never does: the node degrades and the result lists each degrade, which this also records.
    /// - Returns: The degrades, in document order.
    @discardableResult
    static func validate(_ publication: ServerUICompositionPublication,
                         collections: [String: ServerUIRowCollection] = [:]) throws -> [ServerUIDegradation] {
        ServerUISymbolFallback.install(facts.drawsSymbol)
        found = []
        defer { found = [] }
        try check(publication, collections: collections)
        let result = found
        result.forEach { $0.record() }
        return result
    }

    private static func check(_ publication: ServerUICompositionPublication,
                              collections: [String: ServerUIRowCollection]) throws {
        let document = publication.document
        // The rules that depend only on the document (a dark shell, the canonical scrim, one horizontal policy per chrome side, at most
        // five tabs with an initial one, readable chip colours) are `ServerUIAcceptance`'s, which the draft tool also runs.
        if let refusal = ServerUIAcceptance.refusal(in: document) { try reject(refusal.pointer) }
        for (index, route) in (document.extensions?.routes ?? []).enumerated() {
            if let degrade = facts.degradation(symbol: route.icon, at: "/document/extensions/routes/\(index)/icon") { found.append(degrade) }
        }
        try groups(document.navigation.chrome.groups, at: "/document/navigation/chrome/groups")
        for (index, source) in document.dataSources.enumerated() {
            if case .roomNavigation(_, let configuration) = source {
                for (itemIndex, item) in configuration.items.enumerated() {
                    try symbol(item.icon, at: "/document/dataSources/\(index)/items/\(itemIndex)/icon")
                }
            }
        }
        for (index, tab) in document.navigation.tabs.enumerated() {
            try symbol(tab.icon, at: "/document/navigation/tabs/\(index)/icon")
        }
        for (index, page) in document.pages.enumerated() {
            try surface(page.surface, at: "/document/pages/\(index)", collections: collections)
        }
        for (index, modal) in document.modals.enumerated() {
            try surface(modal.surface, at: "/document/modals/\(index)", collections: collections)
        }
    }

    private static func reject(_ pointer: String) throws -> Never {
        throw UKServerUIRendererError(code: .unsupportedPolicy, pointer: pointer)
    }

    private static func symbol(_ symbol: D.Symbol, at pointer: String) throws {
        if let degrade = facts.degradation(symbol: symbol.name, at: pointer + "/name") { found.append(degrade) }
    }

    private static func surface(_ surface: D.Surface, at pointer: String,
                                collections: [String: ServerUIRowCollection]) throws {
        try symbol(surface.icon, at: pointer + "/icon")
        if case .replace(let value) = surface.toolbar { try groups(value, at: pointer + "/toolbar/groups") }
        try components(surface.components, at: pointer + "/components", collections: collections)
    }

    private static func groups(_ groups: [D.ChromeGroup], at pointer: String) throws {
        found += facts.degradations(groups: groups, at: pointer)
        for (index, group) in groups.enumerated() {
            let path = pointer + "/\(index)"
            for (itemIndex, item) in group.items.enumerated() {
                let path = path + "/items/\(itemIndex)"
                switch item {
                case .shellMenu(let item): try symbol(item.icon, at: path + "/icon")
                case .shellHeader: break
                case .button(let item):
                    try symbol(item.icon, at: path + "/icon")
                }
            }
        }
    }

    private static func components(_ components: [D.Component], at pointer: String,
                                   collections: [String: ServerUIRowCollection]) throws {
        for (index, component) in components.enumerated() {
            let path = pointer + "/\(index)"
            switch component {
            case .statusRail(let rail): try self.components(rail.children, at: path + "/children", collections: collections)
            case .statusChip(let chip): try status(chip, at: path + "/props")
            case .roomOverviewTile(let tile): try status(tile.chip, at: path + "/props")
            case .homeLightTile, .weatherPanel, .deviceControl: break
            case .alarmPanel(let panel):
                try symbol(panel.fallback.icon, at: path + "/props/fallback/icon")
                for (index, mode) in panel.modes.enumerated() {
                    try symbol(mode.icon, at: path + "/props/modes/\(index)/icon")
                }
                for (index, state) in panel.states.enumerated() {
                    try symbol(state.appearance.icon, at: path + "/props/states/\(index)/appearance/icon")
                }
            case .climate(let control):
                let choices = (control.props.choices ?? []).enumerated().map { ($0.element.icon, path + "/props/choices/\($0.offset)/icon") }
                let modes = (control.props.hub?.modes ?? []).enumerated().map { ($0.element.icon, path + "/props/hub/modes/\($0.offset)/icon") }
                let fans = (control.props.hub?.fans ?? []).enumerated().map { ($0.element.icon, path + "/props/hub/fans/\($0.offset)/icon") }
                for (name, pointer) in [(control.props.icon, path + "/props/icon")] + choices + modes + fans {
                    if let degrade = facts.degradation(symbol: name, at: pointer) { found.append(degrade) }
                }
            case .roomDeviceControl(let control):
                try symbol(control.icon, at: path + "/icon")
                if let rail = control.fanRail {
                    try symbol(rail.powerIcon, at: path + "/props/fanRail/powerIcon")
                    try symbol(rail.lockedIcon, at: path + "/props/fanRail/lockedIcon")
                    try symbol(rail.unlockedIcon, at: path + "/props/fanRail/unlockedIcon")
                }
            case .vacuum(let control):
                switch control.primitive {
                case .command(_, let icon), .card(let icon, _, _), .target(_, let icon, _), .clearArea(let icon):
                    try symbol(icon, at: path + "/props/primitive/icon")
                default: break
                }
            case .cameraTile, .cameraVideo: break
            case .cameraControls(let camera), .cameraViewer(let camera):
                for (index, control) in camera.controls.enumerated() {
                    try symbol(control.icon, at: path + "/props/controls/\(index)/icon")
                    try symbol(control.activeIcon, at: path + "/props/controls/\(index)/activeIcon")
                    try symbol(control.failureIcon, at: path + "/props/controls/\(index)/failureIcon")
                }
            case .notificationBanner: break
            case .settingsControl(let control): try symbol(control.icon, at: path + "/icon")
            case .bootstrapMessage(let message): try symbol(message.icon, at: path + "/icon")
            case .bedroom(let value):
                if let icon = value.icon { try symbol(icon, at: path + "/props/icon") }
            case .text, .localControl, .accountHeader, .collection, .form, .recipePart: break
            case .pinnedActions(let value):
                for (index, item) in value.items.enumerated() {
                    try symbol(item.icon, at: path + "/props/items/\(index)/icon")
                }
            case .grid, .section, .pagedRow:
                try self.components(component.childComponents, at: path + "/children", collections: collections)
            case .infoBox: break
            case .localTabs(let tabs):
                for (index, tab) in tabs.tabs.enumerated() {
                    if let icon = tab.icon { try symbol(icon, at: path + "/tabs/\(index)/icon") }
                    try self.components(tab.children, at: path + "/tabs/\(index)/children", collections: collections)
                }
                for (index, area) in tabs.areas.enumerated() {
                    try self.components(area.children, at: path + "/blocks/\(index)/children", collections: collections)
                }
            case .overlay(let overlay):
                try self.components(overlay.children, at: path + "/children", collections: collections)
            case .row(let row):
                if let icon = row.icon { try symbol(icon, at: path + "/props/icon") }
            case .statusPill(let pill): try symbol(pill.icon, at: path + "/icon")
            case .button(let button):
                if let icon = button.icon { try symbol(icon, at: path + "/icon") }
            case .boundControl(let control):
                if let icon = control.icon { try symbol(icon, at: path + "/icon") }
            case .rowCollection(let collection):
                if collections[collection.providerId] == nil {
                    throw UKServerUIRendererError(code: .unavailableSource, pointer: path + "/props/providerId")
                }
            case .roomSection(let section): try self.components(section.children, at: path + "/children", collections: collections)
            case .roomCard(let card), .roomChip(let card): try symbol(card.icon, at: path + "/icon")
            case .roomNavigationGrid: break
            case .navigationTile(let tile):
                try symbol(tile.icon, at: path + "/icon")
                if let alarm = tile.alarm {
                    try symbol(alarm.fallback.icon, at: path + "/props/alarm/fallback/icon")
                    for (index, state) in alarm.states.enumerated() {
                        try symbol(state.appearance.icon, at: path + "/props/alarm/states/\(index)/appearance/icon")
                    }
                }
            case .actionTile(let tile): try symbol(tile.icon, at: path + "/icon")
            case .stateTile(let tile):
                try symbol(tile.icon, at: path + "/icon")
                for (index, disc) in tile.parts.discs.enumerated() { try symbol(disc.icon, at: path + "/props/discs/\(index)/icon") }
            case .settingsLink(let link): try symbol(link.icon, at: path + "/icon")
            case .remote(let remote):
                switch remote.control {
                case .keys(_, _, let keys), .volume(let keys, _, _):
                    for (index, key) in keys.enumerated() {
                        if let icon = key.icon { try symbol(icon, at: path + "/props/keys/\(index)/icon") }
                    }
                case .app(_, let icon, _, _, _), .device(_, let icon, _, _, _),
                     .hueToggle(_, let icon, _, _, _), .hueInput(_, let icon, _, _, _, _):
                    try symbol(icon, at: path + "/props/icon")
                case .card(_, let icon, _, _, _, _, let actions, _, _, _):
                    try symbol(icon, at: path + "/props/icon")
                    for (index, action) in actions.enumerated() { try symbol(action.icon, at: path + "/props/actions/\(index)/icon") }
                case .keyboard, .hueChoice, .hueBrightness: break
                }
            }
        }
    }

    private static func status(_ chip: D.StatusChip, at pointer: String) throws {
        func appearance(_ value: D.StatusAppearance, _ path: String) throws {
            try symbol(value.icon, at: path + "/icon")
        }
        try appearance(chip.fallback, pointer + "/fallback")
        for (index, state) in chip.states.enumerated() {
            try appearance(state.appearance, pointer + "/states/\(index)/appearance")
        }
    }

    // MARK: - Canonical values

    static func grid(_ value: D.Grid, traits: UITraitCollection) -> UKGridConfiguration {
        let minimum = value.minimum == .sectionWide ? UKFont.scaled(340, relativeTo: .body, traits: traits) : value.minimum == .tileDynamicType
            ? UKFont.scaled(DynamicGridMetrics.tileMinWidth, relativeTo: .subheadline, traits: traits)
            : DynamicGridMetrics.tileMinWidth
        return UKGridConfiguration(minCellWidth: minimum, maxColumns: value.maxColumns,
                                   spacing: value.spacing.points, equalRowHeights: value.equalRowHeights,
                                   fill: value.shortRow == .share ? .share : .none, minimumColumns: value.minimumColumns)
    }

    static func padding(_ value: D.Insets, rightToLeft: Bool) -> UIEdgeInsets {
        UIEdgeInsets(top: value.top.points, left: (rightToLeft ? value.trailing : value.leading).points,
                     bottom: value.bottom.points, right: (rightToLeft ? value.leading : value.trailing).points)
    }

    static func family(_ value: D.Family) -> ColorFamily? {
        switch value {
        case .neutral: nil
        case .lights: .lights
        case .occupancy: .occupancy
        case .groceries: .groceries
        case .choreResident1: .choreResident1
        case .choreResident2: .choreResident2
        case .choreUnassigned: .choreUnassigned
        case .choreHome: .choreHome
        }
    }

    static func textStyle(_ value: D.TextStyle) -> UIFont.TextStyle {
        switch value {
        case .body: .body
        case .headline: .headline
        case .caption1: .caption1
        case .subheadline: .subheadline
        case .footnote: .footnote
        case .sectionTitle: .title3
        }
    }
}
#endif
