import CryptoKit
import Foundation
import FentonActivityModel

// MARK: - Pure compilation

struct ServerUICompositionCompiler {
    typealias D = ServerUICompositionDocument
    typealias Issue = ServerUICompositionError
    var issues: [Issue] = []
    var requirements: Set<String> = ["sh.composition@1"]
    private var catalogs: [String: [String: String]] = [:]
    private var pageRefs: [(String, String)] = []
    private var modalRefs: [(String, String)] = []
    private var tabRefs: [(String, String)] = []
    private var reads: [(D.Read, String)] = []
    private var powerRefs: [(String, String, Issue.Code)] = []
    private var alarmRefs: [(String, String)] = []
    private var homeRefs: [(String, String, String)] = []
    private var homePowerRefs: [(String, String, String)] = []
    private var doorRefs: [(String, D.DoorKind, String)] = []
    private var climateRefs: [(ServerUIClimateControl, String)] = []
    private var roomRefs: [(String, String, Bool)] = []
    private var visibilityRefs: [(String, String)] = []
    private var deviceRefs: [(ServerUIRoomDeviceControl, String)] = []
    private var providerControlRefs: [(ServerUIDeviceControl, String)] = []
    private var bedroomRefs: [(String, [ServerUIBedroomControl.ProviderKind], String)] = []
    private var titleSourceRefs: [(String, String)] = []
    private var remoteRefs: [(String, String)] = []
    private var vacuumRefs: [(D.VacuumControl, String)] = []
    private var profileRefs: [(String, String)] = []
    private var settingsRefs: [(ServerUISettingsControl, String)] = []
    private var cameraRefs: [(String, String, Bool)] = []
    private var cameraPresentations: [(String, String, String)] = []
    private var dependencies: [(String, String, String)] = []
    private var nodeCount = 0
    private var localFields: [D.LocalField] = []
    /// The document's decoded style library, which `state-tile` nodes check their bindings against.
    private var stateLibrary: ServerUIStateStyleLibrary?
    /// The `security-door@1` sources by id, read from the raw document before any component compiles (`door-tile` lowers to a state tile).
    private var doorSources: [String: ServerUIDoorLowering.Source] = [:]
    /// The saved styles `door-tile` nodes lowered to; they join the document's library.
    private var loweredStyles: [ServerUIStateStyleLibrary.Entry] = []
    private var localActions: [(String, D.LocalValue, String)] = []
    /// Expressions' source references, checked once every source is known.
    private var expressionRefs: [ServerUIExpressionParser.Reference] = []
    private var optimisticRefs: [(sourceId: String, pointer: String)] = []
    /// Whether `control` operands are valid where the action being compiled sits (a bound control's own calls).
    private var controlContext = false
    /// The document's saved components, expanded before decoding (`sh.component-ref@1`).
    private var components = ServerUIComponentExpansion(.null)

    static func decode(_ bytes: Data) throws -> ServerUICompositionPublication {
        var parser = try ServerUICompositionJSON(bytes)
        let json = try parser.parse()
        let versionIssues = [(json["envelopeVersion"], "/envelopeVersion"),
                             (json["document"]?["schemaVersion"], "/document/schemaVersion")].compactMap { value, pointer in
            value != nil && value != .string("2.0") ? Issue(.unsupportedSchema, pointer) : nil
        }
        if let first = ServerUICompositionShape.first(versionIssues) { throw first }
        // The document is serialized once: its size, the envelope overhead and its digest all derive from it.
        var documentCanonical: String?
        if let document = json["document"], case .object(var envelope) = json {
            let canonical = ServerUICompositionJSON.canonical(document)
            envelope["document"] = .null
            let overhead = ServerUICompositionJSON.canonical(.object(envelope)).utf8.count - "null".utf8.count
            guard canonical.utf8.count <= ServerUICompositionJSON.maximumDocumentBytes else { throw Issue(.limitExceeded, "/document") }
            guard overhead <= ServerUICompositionJSON.maximumOverheadBytes else { throw Issue(.limitExceeded, "") }
            documentCanonical = canonical
        }
        // A declared capability the app does not ship refuses the whole document before its shape is read.
        if let declared = json["capabilities"]?.array {
            try Self.refuseUnshippedCapabilities(declared.compactMap(\.string))
        }
        var unsupported = try ServerUICompositionShape.validate(json)
        if let tabs = json["document"]?["navigation"]?["tabs"]?.array, tabs.count > 5 {
            unsupported.append(Issue(.unsupportedCapability, "/document/navigation/tabs", capability: "sh.extended-tabs@1"))
        }
        let expansion = ServerUIComponentExpansion(json)
        let root = Cursor(expansion.expanded, "")
        let capabilities = try root.field("capabilities").array().map { try $0.string() }
        // A declared unknown requirement wins over equality or unsupported-profile diagnostics.
        // Unsupported variants cannot produce a typed first-slice plan.
        if let first = ServerUICompositionShape.first(unsupported) {
            try checkKnownCapabilities(capabilities)
            throw first
        }
        var compiler = Self()
        compiler.components = expansion
        return try compiler.compile(root, capabilities: capabilities, documentCanonical: documentCanonical)
    }

    private mutating func compile(_ root: Cursor, capabilities: [String], documentCanonical: String?) throws -> ServerUICompositionPublication {
        doorSources = ServerUIDoorLowering.sources(in: root.value["document"]?["dataSources"])
        var document = try document(root.field("document"))
        compileComponents()
        let updatedAt = try root.s("updatedAt"), publishedAt = try root.s("publishedAt")
        let updated = timestamp(updatedAt, at: "/updatedAt")
        let published = timestamp(publishedAt, at: "/publishedAt")
        if let updated, let published, updated > published { add(.invalidValue, "/updatedAt") }
        validateReferences(document)
        validateChromeContexts(document)
        if let first = ServerUICompositionShape.first(components.remapped(issues)) { throw first }
        document.dataSources = components.published(document.dataSources)
        try Self.checkKnownCapabilities(capabilities)
        guard capabilities == requirements.sorted() else { throw Issue(.capabilityManifestMismatch, "/capabilities") }
        let manifest = try root.field("document").field("assets")
        let digest = SHA256.hash(data: Data(ServerUICompositionJSON.canonical(manifest.value).utf8))
            .map { String(format: "%02x", $0) }.joined()
        guard try root.s("assetManifestSha256") == digest else { throw Issue(.assetIntegrity, "/assetManifestSha256") }
        let documentDigest = try SHA256.hash(data: Data((documentCanonical ?? ServerUICompositionJSON.canonical(root.field("document").value)).utf8))
            .map { String(format: "%02x", $0) }.joined()
        return try ServerUICompositionPublication(
            envelopeVersion: root.s("envelopeVersion"), publisherId: root.s("publisherId"),
            revision: root.i("revision"), updatedAt: updatedAt, publishedAt: publishedAt,
            capabilities: capabilities, assetManifestSha256: digest, document: document,
            documentSha256: documentDigest
        )
    }

    /// Saved components (`sh.component-ref@1`): each library body is compiled once at its own pointer (its nodes stay out of the total), and an
    /// argument that names a page, a sheet or a source must find it.
    private mutating func compileComponents() {
        if components.usesComponents { require("component-ref") }
        issues += components.issues
        for body in components.bodies {
            let outside = nodeCount
            nodeCount = 0
            do { _ = try component(Cursor(body.value, body.pointer), depth: 1, gridChild: false) } catch let issue as Issue { issues.append(issue) } catch {}
            nodeCount = outside
        }
        for argument in components.argumentReferences where catalogs[argument.catalog]?[argument.id] == nil { add(.invalidReference, argument.pointer) }
    }

    /// Throws the first `unsupported_capability` issue, in declaration order, among the declared capabilities, ignoring malformed ones.
    private static func refuseUnshippedCapabilities(_ capabilities: [String]) throws {
        let known = Set(ServerUICompositionPublication.supportedCapabilities)
        for (index, capability) in capabilities.enumerated() where !known.contains(capability) {
            guard ServerUICompositionShape.matches(capability, "^[a-z][a-z0-9]*(\\.[a-z][a-z0-9-]*)+@[1-9][0-9]*$") else { continue }
            // Declaration order, so the lowest index is first (the Studio's order; a string sort would put 10 before 6).
            throw Issue(.unsupportedCapability, "/capabilities/\(index)", capability: capability)
        }
    }

    private static func checkKnownCapabilities(_ capabilities: [String]) throws {
        let known = Set(ServerUICompositionPublication.supportedCapabilities)
        var issues: [Issue] = []
        for (index, capability) in capabilities.enumerated() {
            let pointer = "/capabilities/\(index)"
            if !ServerUICompositionShape.matches(capability, "^[a-z][a-z0-9]*(\\.[a-z][a-z0-9-]*)+@[1-9][0-9]*$") {
                issues.append(Issue(.invalidValue, pointer))
            } else if !known.contains(capability) {
                issues.append(Issue(.unsupportedCapability, pointer, capability: capability))
            }
        }
        if let first = ServerUICompositionShape.first(issues) { throw first }
    }

    private mutating func document(_ c: Cursor) throws -> D {
        if let value = c.value["stateStyles"] {
            require("state-style")
            let decoded = ServerUIStateStyles.decodeLibrary(value, at: c.path("stateStyles"))
            for (index, entry) in decoded.library.entries.enumerated() {
                register(entry.style.id, catalog: "state-style", at: c.path("stateStyles") + "/styles/\(index)/id")
            }
            issues.append(contentsOf: decoded.issues)
            stateLibrary = decoded.library
            if decoded.library.usesFills { require("state-style-fills") }
        }
        if c.value["localState"] != nil {
            require("local-state")
            localFields = try c.field("localState").array().map { try localField($0) }
        }
        let pages = try c.field("pages").array().map { p -> D.Page in
            let surface = try surface(p)
            register(surface.id, catalog: "surface", at: p.path("id"))
            register(surface.id, catalog: "page", at: p.path("id"))
            let route: D.RouteLayout = try p.field("navigation").e("type")
            if route == .columns { require("navigation-columns") }
            return D.Page(surface: surface, navigation: route,
                columnPlaceholder: try p.field("navigation").optionalString("placeholder"),
                standaloneColumns: try route == .columns ? p.field("navigation").b("standalone") : false,
                columnsOnDemand: p.value["navigation"]?["onDemand"]?.bool ?? false)
        }
        let modals = try c.field("modals").array().map { m -> D.Modal in
            let surface = try surface(m)
            register(surface.id, catalog: "surface", at: m.path("id"))
            register(surface.id, catalog: "modal", at: m.path("id"))
            if case .inherit = surface.toolbar { add(.invalidCombination, m.path("toolbar")) }
            return D.Modal(surface: surface, presentation: try sheet(m.field("presentation")))
        }
        if pages.count + modals.count > 512 { add(.limitExceeded, c.path("pages")) }
        let sources = try c.field("dataSources").array().map { try source($0) }
        let assets = try c.field("assets").array().map { try asset($0) }
        if assets.map(\.id) != assets.map(\.id).sorted() { add(.invalidValue, c.path("assets")) }
        let activities = try c.field("liveActivities").array().map { item -> ActivityPresentation in
            register(try item.s("id"), catalog: "activity", at: item.path("id"))
            register(try item.s("jobId"), catalog: "activity-job", at: item.path("jobId"))
            do { return try JSONDecoder().decode(ActivityPresentation.self, from: Data(ServerUICompositionJSON.canonical(item.value).utf8)) }
            catch { throw Issue(.invalidValue, item.pointer) }
        }
        if !activities.isEmpty { require("activity-presentation") }
        let extensions: NativeExtensionPresentation?
        if let value = c.value["extensions"] {
            require("native-extensions")
            // A route's `visibleWhen` may ask about the viewer only: the catalog is built without entity state.
            var named: [String: String] = [:]
            for route in try c.field("extensions").field("routes").array() {
                // A path or alias names one route only; the earlier pointer of a pair is the one reported.
                var names = [(try route.s("path"), route.path("path"))]
                if route.value["aliases"] != nil {
                    names += try route.field("aliases").array().map { (try $0.string(), $0.pointer) }
                }
                for (name, pointer) in names {
                    if let previous = named[name] { throw Issue(.duplicateID, min(previous, pointer)) }
                    named[name] = pointer
                }
                guard let rule = route.value["visibleWhen"] else { continue }
                require("visible-when")
                if !Self.asksOnlyAboutViewer(rule) { throw Issue(.invalidCombination, route.path("visibleWhen")) }
            }
            do { extensions = try NativeExtensionPresentation.decode(Data(ServerUICompositionJSON.canonical(value).utf8)) }
            catch { throw Issue(.invalidValue, c.path("extensions")) }
            if extensions?.linkPrefixes != nil || (extensions?.routes ?? []).contains(where: {
                !$0.aliases.isEmpty || !$0.keywords.isEmpty || $0.siri
            }) { require("route-links") }
            for (index, route) in (extensions?.routes ?? []).enumerated() {
                pageRefs.append((route.pageId, c.path("extensions") + "/routes/\(index)/pageId"))
                if let tab = route.tabId { tabRefs.append((tab, c.path("extensions") + "/routes/\(index)/tabId")) }
                for (offset, anchor) in (route.anchors ?? []).enumerated() {
                    modalRefs.append((anchor.modalId, c.path("extensions") + "/routes/\(index)/anchors/\(offset)/modalId"))
                }
            }
        } else { extensions = nil }
        return try D(
            schemaVersion: c.s("schemaVersion"), id: c.s("id"), name: c.s("name"),
            theme: theme(c.field("theme")), navigation: navigation(c.field("navigation")),
            pages: pages, modals: modals, dataSources: sources, variables: .init(),
            assets: assets, liveActivities: activities, localState: localFields,
            bootstrap: c.value["bootstrap"].map { try bootstrap(Cursor($0, c.path("bootstrap"))) },
            extensions: extensions,
            stateStyles: loweredStyles.isEmpty ? stateLibrary : ServerUIStateStyleLibrary(entries: (stateLibrary?.entries ?? []) + loweredStyles)
        )
    }

    private mutating func bootstrap(_ c: Cursor) throws -> ServerUIBootstrapPolicy {
        require("bootstrap-policy")
        let steps = try c.field("setup").array().map {
            try ServerUIBootstrapPolicy.PermissionExplanation(permission: $0.e("permission"),
                                                               explanation: $0.value["explanation"]?.string)
        }
        let permissions = steps.map(\.permission)
        if Set(permissions).count != 3 ||
            (permissions.firstIndex(of: .notifications) ?? 3) > (permissions.firstIndex(of: .timeSensitive) ?? 0) {
            add(.invalidCombination, c.path("setup"))
        }
        let recovery = try c.field("recovery")
        return try .init(arrivalAnnouncement: c.s("arrivalAnnouncement"),
            recovery: .init(loadingTitle: recovery.s("loadingTitle"), unavailableTitle: recovery.s("unavailableTitle"),
                            unavailableMessage: recovery.s("unavailableMessage"), retryLabel: recovery.s("retryLabel")),
            setup: steps)
    }

    // MARK: - Policies, geometry and symbols

    private mutating func theme(_ c: Cursor) throws -> D.Theme {
        require("backdrop")
        return try D.Theme(appearance: c.e("appearance"), tokens: c.e("tokens"),
                           typography: c.e("typography"), background: background(c.field("background")))
    }
    private mutating func background(_ c: Cursor) throws -> D.Background {
        if try c.s("type") == "solid" { return try .solid(token: c.e("token")) }
        let blur = try c.field("blur")
        let blurPolicy: D.Blur
        if try blur.s("type") == "fixed" {
            blurPolicy = try .fixed(percent: blur.i("percent"))
        } else {
            blurPolicy = try .preference(key: blur.e("key"), initialPercent: blur.i("initialPercent"))
        }
        let scrim = try c.field("scrim")
        let scrimPolicy: D.Scrim
        if try scrim.s("type") == "canonical@1" {
            scrimPolicy = .canonical
        } else {
            let stops = try scrim.field("stops").array().map {
                try D.GradientStop(location: $0.n("location"), opacity: $0.n("opacity"))
            }
            let boost = try scrim.n("increasedContrastBoost")
            for index in stops.indices {
                if index > 0, stops[index].location <= stops[index - 1].location {
                    add(.invalidValue, scrim.path("stops") + "/\(index)/location")
                }
                if stops[index].opacity + boost > 1 { add(.invalidValue, scrim.path("stops") + "/\(index)/opacity") }
            }
            scrimPolicy = .gradient(stops: stops, increasedContrastBoost: boost)
        }
        require("assets.publisher")
        return try .downloaded(assetId: c.s("assetId"), recipe: c.e("recipe"), blur: blurPolicy,
                               scrim: scrimPolicy, motion: c.e("motion"), reducedTransparency: c.e("reducedTransparency"))
    }
    mutating func symbol(_ c: Cursor) throws -> D.Symbol {
        require("symbols")
        return try .init(name: c.s("name"), rendering: c.e("rendering"), unavailable: c.e("unavailable"))
    }
    func space(_ c: Cursor) throws -> D.Space {
        if try c.s("type") == "points" { return try .points(c.n("value")) }
        return try .token(c.e("name"))
    }
    private func insets(_ c: Cursor) throws -> D.Insets {
        try .init(top: space(c.field("top")), leading: space(c.field("leading")),
                  bottom: space(c.field("bottom")), trailing: space(c.field("trailing")))
    }
    private func width(_ c: Cursor) throws -> D.Width {
        if try c.s("type") == "unbounded" { return .unbounded }
        return try .points(c.n("value"))
    }
    private func body(_ c: Cursor) throws -> D.BodyLayout {
        try .init(padding: insets(c.field("padding")), spacing: space(c.field("spacing")),
                  maxWidth: width(c.field("maxWidth")), scroll: c.e("scroll"),
                  chrome: c.e("chrome"), ground: c.e("ground"))
    }

    // MARK: - Shell and presentation

    private mutating func navigation(_ c: Cursor) throws -> D.Navigation {
        require("shell")
        let tabs = try c.field("tabs").array().map { t -> D.Tab in
            let id = try t.s("id"), pageId = try t.s("pageId")
            register(id, catalog: "tab", at: t.path("id"))
            pageRefs.append((pageId, t.path("pageId")))
            var tab = try D.Tab(id: id, label: t.s("label"), icon: symbol(t.field("icon")), pageId: pageId, arguments: .init(),
                                visibleWhen: visibility(t))
            tab.badgeValue = try badgeValue(in: t)
            return tab
        }
        let pageId = try c.s("initialPageId")
        pageRefs.append((pageId, c.path("initialPageId")))
        let tab = try c.field("initialTabId")
        let tabId: String? = tab.value == .null ? nil : try tab.string()
        if let tabId {
            tabRefs.append((tabId, tab.pointer))
            if let selected = tabs.first(where: { $0.id == tabId }), selected.pageId != pageId {
                add(.invalidCombination, tab.pointer)
            }
        }
        let policy = try c.field("policy")
        return try D.Navigation(
            initialPageId: pageId, initialTabId: tabId, initialArguments: .init(), tabs: tabs,
            policy: .init(type: policy.e("type"), tabSwitch: policy.e("tabSwitch"), reselect: policy.e("reselect"),
                          stackMotion: policy.e("stackMotion"), restoration: policy.e("restoration"),
                          selectionWhileModal: policy.e("selectionWhileModal")),
            chrome: .init(groups: groups(c.field("chrome").field("groups")))
        )
    }
    private mutating func groups(_ c: Cursor) throws -> [D.ChromeGroup] {
        require("chrome")
        return try c.array().map { group in
            let id = try group.s("id")
            register(id, catalog: "group", at: group.path("id"))
            let items = try group.field("items").array().map { try chromeItem($0) }
            if items.contains(where: { if case .shellHeader = $0 { true } else { false } }),
               (try group.s("placement") != "trailing" || items.count != 1 ||
                c.array().filter { $0.value["placement"]?.string == "trailing" }.count != 1) {
                add(.invalidCombination, group.pointer)
            }
            return try D.ChromeGroup(id: id, placement: group.e("placement"), horizontal: group.e("horizontal"),
                                     vertical: group.e("vertical"), items: items)
        }
    }
    private mutating func chromeItem(_ c: Cursor) throws -> D.ChromeItem {
        let id = try c.s("id")
        register(id, catalog: "item", at: c.path("id"))
        if try c.s("type") == "shell-header" {
            require("shell-header")
            for key in ["quickLinksAction", "profileAction"] where c.value[key]?["type"]?.string != "present" {
                add(.invalidCombination, c.path(key))
            }
            return try .shellHeader(.init(id: id, visibility: c.e("visibility"),
                quickLinksAction: action(c.field("quickLinksAction")), profileAction: action(c.field("profileAction"))))
        }
        let icon = try symbol(c.field("icon"))
        if try c.s("type") == "shell-menu" {
            return try .shellMenu(.init(id: id, label: c.s("label"), icon: icon, visibility: c.e("visibility")))
        }
        var button = try D.ChromeButton(
            id: id, label: c.s("label"), menuLabel: c.s("menuLabel"), icon: icon,
            visibility: c.e("visibility"), priority: c.e("priority"), rail: c.e("rail"),
            badge: c.field("badge").e("type"), action: action(c.field("action"))
        )
        button.badgeValue = try badgeValue(in: c, noneNeedsCapability: false)
        return .button(button)
    }
    private mutating func toolbar(_ c: Cursor) throws -> D.Toolbar {
        require("chrome")
        if try c.s("type") == "inherit" { return .inherit }
        return try .replace(groups: groups(c.field("groups")))
    }
    private mutating func surface(_ c: Cursor) throws -> D.Surface {
        require("page")
        let titleSource = try c.optionalString("titleSourceId")
        let children = try components(c.field("components"), depth: 1, gridChild: false)
        func containsSource(_ nodes: [D.Component], id: String) -> Bool {
            nodes.contains {
                if case .bedroom(let value) = $0, value.sourceId == id { return true }
                return containsSource($0.childComponents, id: id)
            }
        }
        if let titleSource {
            require("surface-title-source")
            titleSourceRefs.append((titleSource, c.path("titleSourceId")))
            if !containsSource(children, id: titleSource) { add(.invalidCombination, c.path("titleSourceId")) }
        }
        return try .init(
            id: c.s("id"), title: c.s("title"), icon: symbol(c.field("icon")), parameters: .init(),
            layout: body(c.field("layout")), toolbar: toolbar(c.field("toolbar")),
            components: children, titleSourceId: titleSource
        )
    }
    private mutating func sheet(_ c: Cursor) throws -> D.Sheet {
        require("sheet")
        let adaptive = c.value["adaptive"]?.bool ?? false
        if adaptive { require("adaptive-presentation") }
        let fullScreen = c.value["fullScreen"]?.bool ?? false
        if fullScreen { require("full-screen-modal") }
        let close = try c.field("close")
        let selection = try c.field("height")
        let height: D.SheetHeight
        if try selection.s("type") == "full" {
            height = .full
        } else {
            require("sheet-fit")
            height = try .fitted(follows: selection.e("follows"), firstOpen: selection.e("firstOpen"))
        }
        if fullScreen && (adaptive || height != .full) { add(.invalidCombination, c.path("fullScreen")) }
        return try .init(
            width: c.e("width"), height: height, appearance: c.e("appearance"),
            placement: c.e("placement"), grabber: c.e("grabber"), navigation: c.e("navigation"),
            close: .init(visibility: close.e("visibility"), placement: close.e("placement"),
                         rail: close.e("rail"), guardPolicy: close.field("guard").e("type")), adaptive: adaptive, fullScreen: fullScreen
        )
    }

    // MARK: - Reads and model dependencies

    private mutating func localField(_ c: Cursor) throws -> D.LocalField {
        let id = try c.s("id")
        register(id, catalog: "local-state", at: c.path("id"))
        let field: D.LocalField
        switch try c.s("type") {
        case "string":
            field = try .init(id: id, initial: .string(c.s("initial")), rule: .string(maxLength: c.i("maxLength")))
        case "boolean":
            field = try .init(id: id, initial: .boolean(c.b("initial")), rule: .boolean)
        case "number":
            let minimum = try c.n("minimum"), maximum = try c.n("maximum"), step = try c.n("step")
            if minimum > maximum { add(.invalidCombination, c.path("maximum")) }
            field = try .init(id: id, initial: .number(c.n("initial")),
                              rule: .number(minimum: minimum, maximum: maximum, step: step))
        case "choice":
            let options = try c.field("options").array().map { try D.LocalField.Option(id: $0.s("id"), label: $0.s("label")) }
            if Set(options.map(\.id)).count != options.count { add(.duplicateID, c.path("options")) }
            field = try .init(id: id, initial: .string(c.s("initial")), rule: .choice(options: options))
        default: throw Issue(.unknownVariant, c.path("type"))
        }
        if !field.accepts(field.initial) { add(.invalidValue, c.path("initial")) }
        return field
    }

    private func localValue(_ c: Cursor) throws -> D.LocalValue {
        switch try c.s("type") {
        case "string": return try .string(c.s("value"))
        case "number": return try .number(c.n("value"))
        case "boolean": return try .boolean(c.b("value"))
        default: throw Issue(.unknownVariant, c.path("type"))
        }
    }

    private mutating func source(_ c: Cursor) throws -> D.Source {
        require("bindings")
        let id = try c.s("id")
        register(id, catalog: "source", at: c.path("id"))
        let model = try c.s("kind") == "model" ? c.s("model") : nil
        if let model, ServerUICompositionShape.providerModels.contains(model) {
            require(String(model.dropLast(2)))
            let inputs = try c.field("inputs")
            if model == "media-remote-config@1", ServerUICompositionShape.remoteUsesSpeakerTargets(inputs.value) {
                require("remote-speaker-targets")
            }
            let descriptor: ServerUIDeviceProviderDescriptor
            do {
                descriptor = try .decode(model: model, data: Data(ServerUICompositionJSON.canonical(inputs.value).utf8))
            } catch { throw Issue(.invalidValue, inputs.pointer) }
            issues += ServerUIDeviceProviderValidation.validate(descriptor, at: inputs.pointer)
            return .deviceProvider(id: id, descriptor: descriptor)
        }
        if model == "home-status@1" {
            require("home-status")
            let inputs = try c.field("inputs"), labels = try c.field("labels")
            let projection: D.HomeStatus.Projection = try inputs.e("projection")
            let format: D.HomeStatus.Format = try inputs.e("format")
            let ids = try inputs.field("entityIds").array().map { try homeEntity($0) }
            if Set(ids).count != ids.count { add(.invalidCombination, inputs.path("entityIds")) }
            if [.entity, .airQuality].contains(projection) || format == .item, ids.count != 1 { add(.invalidCombination, inputs.path("entityIds")) }
            let away = try inputs.field("awayEntityIds").array().map { try homeEntity($0, domains: ["input_boolean", "binary_sensor"]) }
            let members: [D.HomeStatus.Member] = try inputs.value["members"].map { _ in
                try inputs.field("members").array().map {
                    try .init(entityId: homeEntity($0.field("entityId"), domains: ["binary_sensor"]),
                              title: $0.s("title"), contactCount: $0.i("contactCount"), contactKind: $0.e("contactKind"))
                }
            } ?? []
            if !members.isEmpty, projection != .contacts || Set(members.map(\.entityId)) != Set(ids) || members.count != ids.count {
                add(.invalidCombination, inputs.path("members"))
            }
            return try .homeStatus(id: id, configuration: .init(
                projection: projection, format: format, entityIds: ids,
                rangeEntityId: optionalHomeEntity(inputs, "rangeEntityId"),
                secondaryEntityId: optionalHomeEntity(inputs, "secondaryEntityId", domains: ["sensor", "input_text"]),
                alarmEntityId: optionalHomeEntity(inputs, "alarmEntityId", domains: ["alarm_control_panel"]),
                awayEntityIds: away,
                labels: .init(idle: labels.s("idle"), active: labels.s("active"), countSuffix: labels.s("countSuffix"),
                              loading: labels.s("loading"), unavailable: labels.s("unavailable"),
                              empty: labels.s("empty"), hidden: labels.s("hidden")),
                members: members, colorEntityId: optionalHomeEntity(inputs, "colorEntityId", domains: ["sensor", "input_text"])
            ))
        }
        if model == "home-weather@1" {
            require("home-weather")
            let inputs = try c.field("inputs")
            return try .homeWeather(id: id, configuration: .init(
                weatherEntityId: homeEntity(inputs.field("weatherEntityId"), domains: ["weather"]),
                sunEntityId: optionalHomeEntity(inputs, "sunEntityId", domains: ["sun"]),
                airQualityEntityId: optionalHomeEntity(inputs, "airQualityEntityId", domains: ["sensor"])
            ))
        }
        if model == "home-light@1" {
            require("home-light")
            let inputs = try c.field("inputs")
            let members = try inputs.value["memberEntityIds"].map { _ in
                try inputs.field("memberEntityIds").array().map { try homeEntity($0, domains: ["light", "switch", "input_boolean"]) }
            } ?? []
            if Set(members).count != members.count { add(.invalidCombination, inputs.path("memberEntityIds")) }
            return try .homeLight(id: id, entityId: homeEntity(inputs.field("entityId"), domains: ["light", "switch", "input_boolean"]),
                                  memberEntityIds: members)
        }
        if model == "climate@1" {
            require("climate-source")
            let inputs = try c.field("inputs")
            let configuration = try JSONDecoder().decode(ServerUIClimateSource.self, from: JSONEncoder().encode(inputs.value))
            issues += ServerUIClimateValidation.source(configuration, at: inputs.pointer)
            return .climate(id: id, configuration: configuration)
        }
        if model == "room-navigation@1" {
            require("room-navigation")
            let ranking: D.RoomRanking = try c.e("ranking")
            let script = try c.value["visitScriptEntityId"].map { _ in
                try literalEntity(c.field("visitScriptEntityId"), domain: "script")
            }
            var ids: Set<String> = []
            let items = try c.field("items").array().map { item -> D.RoomDestination in
                let id = try item.s("id")
                if !ids.insert(id).inserted { add(.duplicateID, item.path("id")) }
                let counter = try item.value["counterEntityId"].map { _ in
                    try literalEntity(item.field("counterEntityId"), domain: "counter")
                }
                if ranking == .visits, counter == nil { add(.invalidCombination, item.path("counterEntityId")) }
                let key = try item.optionalString("visitKey")
                if (script == nil) != (key == nil) { add(.invalidCombination, item.path("visitKey")) }
                let intent = try navigationAction(item.field("action"))
                let fill = try item.field("fill")
                return try .init(id: id, title: item.s("title"), icon: symbol(item.field("icon")),
                                 fill: .solidRGB(red: fill.i("red"), green: fill.i("green"), blue: fill.i("blue")),
                                 counterEntityId: counter, visibility: roomVisibility(item, key: "visibility"),
                                 visitKey: key, action: intent, bodyHint: item.s("bodyHint"))
            }
            return .roomNavigation(id: id, configuration: .init(items: items, ranking: ranking, visitScriptEntityId: script))
        }
        if let model, !ServerUIRoomDeviceDescriptor.domains(model).isEmpty {
            require(String(model.dropLast(2)))
            return try .roomDevice(id: id, descriptor: roomDevice(c.field("inputs"), model: model))
        }
        if model == "bedroom-provider@1" {
            require("bedroom-sources")
            let inputs = try c.field("inputs")
            return try .bedroom(id: id, providerId: inputs.s("providerId"), kind: inputs.e("kind"))
        }
        if model == "media-remote@1" {
            require("media-remote")
            return try .mediaRemote(id: id, providerId: c.field("inputs").s("providerId"))
        }
        if model == "vacuum@1" {
            require("vacuum")
            let inputs = try c.field("inputs")
            let descriptor: ServerUIVacuumDescriptor
            do {
                descriptor = try JSONDecoder().decode(ServerUIVacuumDescriptor.self,
                    from: Data(ServerUICompositionJSON.canonical(inputs.value).utf8))
            } catch { throw Issue(.invalidValue, inputs.pointer) }
            issues += ServerUIVacuumValidation.validate(descriptor, at: inputs.pointer)
            return .vacuum(id: id, descriptor: descriptor)
        }
        if model == "profile-account@1" {
            require("profile-account")
            return .profileAccount(id: id)
        }
        if model == "settings-provider@1" {
            require("settings-controls")
            let inputs = try c.field("inputs")
            return try .settingsProvider(id: id, configuration: .init(providerId: inputs.s("providerId"),
                                                                      domain: inputs.e("domain")))
        }
        if model == "app-state@1" {
            require("app-state")
            return try .appState(id: id, topic: c.field("inputs").e("topic"))
        }
        if model == "camera-stream@1" {
            require("camera-stream")
            let inputs = try c.field("inputs"), labels = try c.field("labels"), recording = try inputs.field("recording")
            let record: ServerUICameraDescriptor.Recording
            if try recording.s("type") == "disabled" { record = .disabled }
            else {
                record = try .script(stateEntityId: literalEntity(recording.field("stateEntityId"), domain: "input_boolean"),
                                     scriptEntityId: literalEntity(recording.field("scriptEntityId"), domain: "script"))
            }
            let stream = try inputs.s("rtcStreamId")
            if !ServerUICompositionShape.matches(stream, "^[A-Za-z0-9_][A-Za-z0-9_.-]*$") {
                add(.invalidValue, inputs.path("rtcStreamId"))
            }
            return try .camera(id: id, configuration: .init(
                entityId: literalEntity(inputs.field("entityId"), domain: "camera"),
                snapshotEntityId: literalEntity(inputs.field("snapshotEntityId"), domain: "camera"),
                rtcStreamId: stream, aspectRatio: inputs.n("aspectRatio"), recording: record,
                labels: .init(loading: labels.s("loading"), unavailable: labels.s("unavailable"), hidden: labels.s("hidden"),
                              connecting: labels.s("connecting"), live: labels.s("live"), delayed: labels.s("delayed"),
                              snapshot: labels.s("snapshot"), retry: labels.s("retry"), recordFailed: labels.s("recordFailed"),
                              photosTitle: labels.s("photosTitle"), photosMessage: labels.s("photosMessage"),
                              settings: labels.s("settings"), cancel: labels.s("cancel"))
            ))
        }
        if model == "alarm-mode@1" {
            require("alarm-mode")
            return try .alarmMode(id: id, entityId: literalEntity(c.field("inputs").field("entityId"), domain: "alarm_control_panel"))
        }
        if model == "security-door@1" {
            require("security-door")
            let inputs = try c.field("inputs"), kind: D.DoorKind = try inputs.e("kind")
            return try .securityDoor(id: id, entityId: literalEntity(inputs.field("entityId"), domain: kind == .lock ? "lock" : "cover"), kind: kind)
        }
        if model == "sprinkler-state@1" {
            require("sprinkler-state")
            let input = try c.field("inputs")
            let zones = try input.field("zones").array().map { zone in
                try SprinklersConfig.Zone(historyEntityId: literalEntity(zone.field("historyEntityId"), domain: "sensor"),
                    programEntityId: literalEntity(zone.field("programEntityId"), domain: "switch"),
                    valveEntityId: literalEntity(zone.field("valveEntityId"), domain: "valve"))
            }
            let controller = try SprinklersConfig.Controller(
                id: id, title: input.s("title"),
                batteryEntityId: literalEntity(input.field("batteryEntityId"), domain: "sensor"),
                faultEntityId: literalEntity(input.field("faultEntityId"), domain: "binary_sensor"),
                hubConnectedEntityId: literalEntity(input.field("hubConnectedEntityId"), domain: "binary_sensor"),
                modeEntityId: literalEntity(input.field("modeEntityId"), domain: "select"),
                nextWateringEntityId: literalEntity(input.field("nextWateringEntityId"), domain: "sensor"),
                rainDelayEntityId: literalEntity(input.field("rainDelayEntityId"), domain: "switch"),
                smartWateringEntityId: literalEntity(input.field("smartWateringEntityId"), domain: "switch"),
                stateEntityId: literalEntity(input.field("stateEntityId"), domain: "sensor"), zones: zones)
            return try .sprinklerState(id: id, configuration: .init(controller: controller, lowBatteryPercent: input.n("lowBatteryPercent")))
        }
        if model == "household-away-status@1" {
            require("household-away-status")
            return try .householdAwayStatus(id: id, entityId: literalEntity(c.field("inputs").field("entityId"), domain: "sensor"))
        }
        if model == "inventory-summary@1" {
            require("inventory-summary")
            let inputs = try c.field("inputs"), labels = try c.field("labels")
            if inputs.value["expiringLocation"] != nil, inputs.value["expiringEntityId"] == nil {
                add(.invalidCombination, inputs.path("expiringLocation"))
            }
            return try .inventorySummary(id: id, configuration: .init(
                totalEntityId: literalEntity(inputs.field("totalEntityId"), domain: "sensor"),
                expiringEntityId: inputs.value["expiringEntityId"] == nil ? nil : literalEntity(inputs.field("expiringEntityId"), domain: "sensor"),
                spaceEntityIds: inputs.field("spaceEntityIds").array().map { try literalEntity($0, domain: "sensor") },
                singular: labels.s("singular"), plural: labels.s("plural"), expiringSuffix: labels.s("expiringSuffix"),
                separator: labels.s("separator"), loadingText: labels.s("loadingText"), unavailableText: labels.s("unavailableText"),
                expiringLocation: inputs.value["expiringLocation"]?.string
            ))
        }
        if model == "todo-counts@1" {
            require("todo-counts")
            let inputs = try c.field("inputs"), labels = try c.field("labels")
            var seen: Set<String> = []
            let lists = try inputs.field("lists").array().map { entry -> D.TodoCounts.List in
                let entity = try literalEntity(entry.field("entityId"), domain: "todo")
                if !seen.insert(entity).inserted { add(.invalidCombination, entry.path("entityId") + "/value") }
                return try .init(entityId: entity, overdue: entry.b("overdue"))
            }
            return try .todoCounts(id: id, configuration: .init(
                lists: lists, openSuffix: labels.s("openSuffix"), overdueSuffix: labels.s("overdueSuffix"),
                separator: labels.s("separator"), zeroText: labels.s("zeroText"),
                loadingText: labels.s("loadingText"), unavailableText: labels.s("unavailableText")))
        }
        if model == "inventory-list@1" {
            require("inventory-list")
            return try .inventoryList(id: id, space: c.field("inputs").e("space"))
        }
        if model == "todo-collection@1" {
            require("todo-collection")
            return try .todoCollection(id: id, configuration: todoCollection(c.field("inputs")))
        }
        let power = model == "power-toggle@1"
        let value = try power ? c.field("inputs").field("entityId") : c.field("entityId")
        let entity = try entityValue(value, power: power)
        if case .read(let read) = entity { dependencies.append((id, read.sourceId, value.path("from") + "/sourceId")) }
        if power { require("power-toggle"); return .powerToggle(id: id, entityId: entity) }
        return .haEntity(id: id, entityId: entity)
    }
    /// The inputs of a `todo-collection@1` source: lists in order, each unique and a `todo` entity, an Add action over one of
    /// them, and a list rule that may name only user ids (a list is read where only the user id is known).
    private mutating func todoCollection(_ c: Cursor) throws -> D.TodoCollection {
        var seen: Set<String> = []
        let lists = try c.field("lists").array().map { entry -> D.TodoCollection.List in
            let entity = try literalEntity(entry.field("entityId"), domain: "todo")
            if !seen.insert(entity).inserted { add(.invalidCombination, entry.path("entityId") + "/value") }
            var script: String?
            if entry.value["completionScript"] != nil { script = try literalEntity(entry.field("completionScript"), domain: "script") }
            let rule = try visibility(entry)
            if let rule {
                if case .viewer(nil, let ids?) = rule.predicate, !ids.isEmpty {} else { add(.invalidCombination, entry.path("visibleWhen")) }
                // A restricted list stays hidden until the user is known, as it always did.
                if rule.whenUnknown != .hide { add(.invalidCombination, entry.path("whenUnknown")) }
            }
            return try .init(title: entry.s("title"), entityId: entity, completionScript: script,
                             hideCompleted: entry.b("hideCompleted"), hideWhenNoOpenItems: entry.b("hideWhenNoOpenItems"), visibility: rule)
        }
        let action = try c.field("addAction")
        let kind: String = try action.s("type")
        let addAction: D.TodoCollection.AddAction
        switch kind {
        case "task": addAction = .task(defaultAssignee: try action.s("defaultAssignee"))
        case "grocery", "admin":
            let entity = try literalEntity(action.field("entityId"), domain: "todo")
            if !seen.contains(entity) { add(.invalidReference, action.path("entityId") + "/value") }
            addAction = kind == "grocery" ? .grocery(entityId: entity) : .admin(entityId: entity)
        default: throw Issue(.unknownVariant, action.path("type"))
        }
        var personalization: D.TodoCollection.Personalization?
        if c.value["personalization"] != nil {
            let p = try c.field("personalization")
            personalization = try .init(residentId: p.s("residentId"), ownTitle: p.s("ownTitle"), otherTitle: p.s("otherTitle"),
                                        ownEmptyDescription: p.value["ownEmptyDescription"] == nil ? nil : p.s("ownEmptyDescription"))
        }
        return try .init(title: c.s("title"), lists: lists, addAction: addAction, hideListHeaders: c.b("hideListHeaders"),
                         hiddenByVacation: c.b("hiddenByVacation"), emptyTitle: c.field("empty").s("title"),
                         emptyDescription: c.field("empty").s("description"), personalization: personalization)
    }
    private mutating func literalEntity(_ c: Cursor, domain: String) throws -> String {
        let value = try c.s("value")
        if !ServerUICompositionShape.matches(value, "^[a-z][a-z0-9_]*\\.[a-z0-9_]+$") {
            add(.invalidValue, c.path("value"))
        } else if !value.hasPrefix(domain + ".") {
            add(.invalidCombination, c.path("value"))
        }
        return value
    }
    private mutating func homeEntity(_ c: Cursor, domains: [String] = []) throws -> String {
        let value = try c.s("value")
        if !ServerUICompositionShape.matches(value, "^[a-z][a-z0-9_]*\\.[a-z0-9_]+$") {
            add(.invalidValue, c.path("value"))
        } else if !domains.isEmpty, !domains.contains(String(value.prefix(while: { $0 != "." }))) {
            add(.invalidCombination, c.path("value"))
        }
        return value
    }
    private mutating func optionalHomeEntity(_ c: Cursor, _ key: String, domains: [String] = []) throws -> String? {
        guard c.value[key] != nil else { return nil }
        return try homeEntity(c.field(key), domains: domains)
    }

    private mutating func roomDevice(_ c: Cursor, model: String) throws -> ServerUIRoomDeviceDescriptor {
        for (field, domain) in ServerUIRoomDeviceDescriptor.domains(model).sorted(by: { $0.key < $1.key }) {
            let value = try c.s(field)
            if !ServerUICompositionShape.matches(value, "^[a-z][a-z0-9_]*\\.[a-z0-9_]+$") {
                add(.invalidValue, c.path(field))
            } else if !value.hasPrefix(domain + ".") { add(.invalidCombination, c.path(field)) }
        }
        for field in ["scriptService", "applyProfileScriptService", "setLevelScriptService", "scheduleId"] where c.value[field] != nil {
            if !ServerUICompositionShape.matches(try c.s(field), "^[a-z0-9_]+$") { add(.invalidValue, c.path(field)) }
        }
        if model == "grill@1" {
            var targets: Set<String> = []
            for detail in try c.field("details").array() {
                let id = try detail.s("entityId")
                if !ServerUICompositionShape.matches(id, "^(sensor|switch)\\.[a-z0-9_]+$") {
                    add(.invalidCombination, detail.path("entityId"))
                }
                if !targets.insert(id).inserted { add(.invalidCombination, detail.path("entityId")) }
            }
        }
        let data = try JSONEncoder().encode(c.value)
        let decoder = JSONDecoder()
        switch model {
        case "air-purifier@1": return try .purifier(decoder.decode(AirPurifierConfig.self, from: data))
        case "bathroom-fan@1": return try .fan(decoder.decode(BathroomFanConfig.self, from: data))
        case "grill@1": return try .grill(decoder.decode(GrillConfig.self, from: data))
        default: return try .humidifier(decoder.decode(HumidifierConfig.self, from: data))
        }
    }

    private mutating func deviceControl(_ c: Cursor, node: D.Node) throws -> ServerUIRoomDeviceControl {
        let props = try c.field("props")
        let kind: ServerUIRoomDeviceControl.Kind = try props.e("control")
        require(String(kind.model.dropLast(2))); require("bindings")
        if kind == .humidifierScheduling { require("humidifier-scheduling") }
        let options = try props.field("options").array().map {
            try ServerUIRoomDeviceControl.Option(value: $0.s("value"), label: $0.s("label"), actionLabel: $0.optionalString("actionLabel"))
        }
        var seen: Set<String> = []
        let allowed: [String]
        switch kind {
        case .purifierMode: allowed = ["Manual", "Sleep", "Auto"]
        case .purifierAuto: allowed = ["Default", "Quiet", "Efficient"]
        case .purifierSpeed: allowed = ["0", "33", "66", "100"]
        case .fanTimer: allowed = ["5", "10", "15", "20", "30", "60"]
        case .humidifierMode: allowed = HumidifierMode.allCases.map(\.rawValue)
        case .humidifierPresets: allowed = (1...9).map(String.init)
        case .humidifierWarm: allowed = ["0", "1", "2", "3"]
        default: allowed = []
        }
        if kind.hasOptions == options.isEmpty { add(.invalidCombination, props.path("options")) }
        for (index, option) in options.enumerated() {
            if !allowed.contains(option.value) || !seen.insert(option.value).inserted {
                add(.invalidCombination, props.path("options") + "/\(index)/value")
            }
            if (kind == .fanTimer) != (option.actionLabel != nil) {
                add(.invalidCombination, props.path("options") + "/\(index)/actionLabel")
            }
        }
        for (field, present) in [("detailEntityId", kind == .grillDetail), ("info", kind == .humidifierInfo),
                                  ("initialMinutes", kind == .fanTimer), ("modalId", kind == .fanRoom),
                                  ("fanRail", kind == .fanRoom)] {
            if (props.value[field] != nil) != present { add(.invalidCombination, props.path(field)) }
        }
        let initial = try props.value["initialMinutes"] == nil ? nil : props.i("initialMinutes")
        if let initial, !options.contains(where: { $0.value == String(initial) }) { add(.invalidCombination, props.path("initialMinutes")) }
        let labels = try props.field("labels")
        let rail: ServerUIRoomDeviceControl.FanRail?
        if props.value["fanRail"] != nil {
            let r = try props.field("fanRail")
            let order = try r.field("order").array().map { try $0.string() }
            if Set(order) != Set(["lock", "power"]) { add(.invalidCombination, r.path("order")) }
            rail = try .init(order: order, powerIcon: symbol(r.field("powerIcon")), lockedIcon: symbol(r.field("lockedIcon")),
                             unlockedIcon: symbol(r.field("unlockedIcon")), powerOn: r.s("powerOn"), powerOff: r.s("powerOff"),
                             lock: r.s("lock"), unlock: r.s("unlock"), locked: r.s("locked"))
        } else { rail = nil }
        let control = try ServerUIRoomDeviceControl(
            node: node, sourceId: c.field("binding").s("sourceId"), icon: symbol(c.field("icon")), control: kind,
            family: props.e("family"), options: options,
            labels: .init(loading: labels.s("loading"), unavailable: labels.s("unavailable"), failed: labels.s("failed"),
                          on: labels.s("on"), off: labels.s("off"), action: labels.s("action"),
                          cancel: labels.s("cancel"), footnote: labels.s("footnote"),
                          sleep: labels.s("sleep"), tankFault: labels.s("tankFault"), waterFault: labels.s("waterFault"),
                          invalidTarget: labels.s("invalidTarget"), highTarget: labels.s("highTarget")),
            detailEntityId: props.optionalString("detailEntityId"),
            info: props.value["info"] == nil ? nil : props.e("info"), initialMinutes: initial,
            modalId: props.optionalString("modalId"), fanRail: rail
        )
        if let id = control.modalId { modalRefs.append((id, props.path("modalId"))); require("actions.navigation") }
        deviceRefs.append((control, c.pointer))
        return control
    }
    private mutating func entityValue(_ c: Cursor, power: Bool) throws -> D.EntityValue {
        if try c.s("type") == "read" { return try .read(read(c, expected: .entityID)) }
        let value = try c.s("value")
        if !ServerUICompositionShape.matches(value, "^[a-z][a-z0-9_]*\\.[a-z0-9_]+$") {
            add(.invalidValue, c.path("value"))
        } else if power, !D.Source.powerEntityDomains.contains(String(value.prefix(while: { $0 != "." }))) {
            add(.invalidCombination, c.path("value"))
        }
        return .literal(value)
    }
    mutating func stringValue(_ c: Cursor) throws -> D.StringValue {
        switch try c.s("type") {
        case "literal": return try .literal(c.s("value"))
        case "expr":
            var rules = ServerUIRuleDecoder()
            let value = rules.expression(c.value, at: c.pointer)
            try absorb(rules)
            guard let value else { throw Issue(.invalidValue, c.pointer) }
            return value
        default:
            let fallback = try c.optionalString("fallback")
            if fallback != nil { require("rules") }
            return try .read(read(c, expected: .string), fallback: fallback)
        }
    }

    /// Folds a rule decoder's diagnostics, source references and capability needs into this compile.
    private mutating func absorb(_ rules: ServerUIRuleDecoder) throws {
        issues += rules.issues
        for need in rules.needs { require(need) }
        try absorb(rules.parserFacts)
    }

    /// A node's `enabledWhen` (`sh.enabled-when@1`).
    mutating func enabled(_ c: Cursor) throws -> ServerUIEnabledRule? {
        guard c.value["enabledWhen"] != nil else { return nil }
        require("enabled-when")
        let rule = try c.field("enabledWhen")
        return try ServerUIEnabledRule(condition: predicate(rule.field("condition")), whenUnknown: rule.e("whenUnknown"))
    }

    /// The `when` of a power action's authored question (`sh.confirm-when@1`).
    private mutating func confirmWhen(_ c: Cursor) throws -> ServerUIPredicate? {
        guard c.value["when"] != nil else { return nil }
        require("confirm-when")
        return try predicate(c.field("when"))
    }

    /// An action chosen by rule (`sh.action-rules@1`): one level, each case a plain action checked like any other, else an action or none.
    private mutating func conditionalAction(_ c: Cursor) throws -> D.Action {
        require("action-rules")
        let cases = try c.field("cases").array().map { item in
            try ServerUIActionRule.Case(when: predicate(item.field("when")), then: action(item.field("then")))
        }
        let otherwise = try c.field("otherwise")
        return try .conditional(ServerUIActionRule(cases: cases, otherwise: otherwise.s("type") == "none" ? nil : action(otherwise)))
    }

    /// Checks each plain action a slot can run against `allowed`, blaming the `type` of the case that fails.
    private mutating func check(_ intent: D.Action, at pointer: String, allowed: (D.Action) -> Bool) {
        if case .conditional(let rule) = intent {
            for (index, item) in rule.cases.enumerated() where !allowed(item.then) {
                add(.invalidCombination, pointer + "/cases/\(index)/then/type")
            }
            if let other = rule.otherwise, !allowed(other) { add(.invalidCombination, pointer + "/otherwise/type") }
        } else if !allowed(intent) {
            add(.invalidCombination, pointer + "/type")
        }
    }
    private mutating func read(_ c: Cursor, expected: D.ScalarKind) throws -> D.Read {
        require("bindings")
        let from = try c.field("from")
        let path = try from.field("path").array().map { try $0.string() }
        for (index, segment) in path.enumerated() {
            // Prototype segments, interpreters and numeric array indexing are disallowed in each segment.
            if segment.utf8.count > 500 || ["__proto__", "prototype", "constructor"].contains(segment) ||
                !ServerUICompositionShape.matches(segment, "^[A-Za-z0-9_-]+$") ||
                segment.allSatisfy(\.isNumber) {
                add(.invalidReference, from.path("path") + "/\(index)")
            }
        }
        let kind: D.ScalarKind = try c.e("as")
        if kind != expected { add(.bindingType, c.path("as")) }
        let result = try D.Read(sourceId: from.s("sourceId"), path: path, kind: kind)
        reads.append((result, c.pointer))
        return result
    }
    private mutating func homeComponent(_ c: Cursor, node: D.Node, props: Cursor, depth: Int) throws -> D.Component? {
        switch try c.s("type") {
        case "status-chip", "room-overview-tile":
            let room = try c.s("type") == "room-overview-tile"
            require(room ? "room-overview-tile" : "status-chip"); require("home-status"); require("bindings")
            let source = try props.s("sourceId")
            homeRefs.append((source, "home-status@1", props.path("sourceId")))
            var states: Set<String> = []
            let appearances = try props.field("states").array().map { state -> D.StatusState in
                let key = try state.s("state")
                if !states.insert(key).inserted { add(.invalidCombination, state.path("state")) }
                let appearance = try statusAppearance(state.field("appearance"))
                if room, appearance.glyph != nil { add(.invalidCombination, state.path("appearance") + "/glyph") }
                return try .init(state: key, appearance: appearance, text: state.optionalString("text"))
            }
            let fallback = try statusAppearance(props.field("fallback"))
            if room, fallback.glyph != nil { add(.invalidCombination, props.path("fallback") + "/glyph") }
            let intent = try optionalHomeAction(c)
            let chip = try D.StatusChip(node: node, sourceId: source, states: appearances,
                                        fallback: fallback,
                                        announcement: props.e("announcement"), action: intent)
            if room {
                let power = try props.optionalString("powerSourceId")
                if let power {
                    require("home-light")
                    require("room-light-power")
                    homeRefs.append((power, "home-light@1", props.path("powerSourceId")))
                    homePowerRefs.append((source, power, props.path("powerSourceId")))
                    if intent == nil { add(.invalidCombination, props.path("powerSourceId")) }
                }
                return try .roomOverviewTile(.init(chip: chip, hidesContactSubtitle: props.b("hidesContactSubtitle"), powerSourceId: power))
            }
            return .statusChip(chip)
        case "status-rail":
            require("status-rail")
            let children = try components(c.field("children"), depth: depth + 1, gridChild: false)
            for (index, child) in children.enumerated() {
                switch child {
                case .statusChip, .roomChip: break
                default: add(.invalidCombination, c.path("children") + "/\(index)/type")
                }
            }
            forbidRules(in: children, at: c.path("children"))
            return .statusRail(.init(node: node, children: children))
        case "light-group-tile":
            require("light-group-tile"); require("home-light"); require("bindings")
            let source = try props.s("sourceId")
            homeRefs.append((source, "home-light@1", props.path("sourceId")))
            return .homeLightTile(.init(node: node, sourceId: source))
        case "weather-panel":
            require("weather-panel"); require("home-weather"); require("bindings")
            let source = try props.s("sourceId")
            homeRefs.append((source, "home-weather@1", props.path("sourceId")))
            let modes: [D.WeatherPanel.Mode] = try props.field("modes").array().map { try $0.enumeration() }
            let initial: D.WeatherPanel.Mode = try props.e("initialMode")
            if Set(modes).count != modes.count { add(.invalidCombination, props.path("modes")) }
            if !modes.contains(initial) { add(.invalidCombination, props.path("initialMode")) }
            let highlights: [D.WeatherPanel.Highlight] = try props.field("highlights").array().map { try $0.enumeration() }
            if Set(highlights).count != highlights.count { add(.invalidCombination, props.path("highlights")) }
            let labels = try props.field("labels")
            let panel: D.WeatherPanel.Panel = try props.e("panel")
            let intent = try optionalHomeAction(c)
            if intent != nil, panel != .summary { add(.invalidCombination, c.path("action")) }
            return try .weatherPanel(.init(
                node: node, sourceId: source, panel: panel, modes: modes, initialMode: initial, highlights: highlights,
                compactHours: props.i("compactHours"), regularHours: props.i("regularHours"),
                labels: .init(loading: labels.s("loading"), empty: labels.s("empty"), stale: labels.s("stale"),
                              error: labels.s("error"), open: labels.s("open")), action: intent
            ))
        default: return nil
        }
    }
    mutating func action(_ c: Cursor) throws -> D.Action {
        switch try c.s("type") {
        case "set-local":
            require("local-state")
            let id = try c.s("stateId"), value = try localValue(c.field("value"))
            localActions.append((id, value, c.pointer))
            return .setLocal(stateId: id, value: value)
        case "domain":
            require("power-toggle"); require("bindings")
            let sourceId = try c.s("sourceId")
            powerRefs.append((sourceId, c.path("sourceId"), .invalidCombination))
            return try .domain(.init(sourceId: sourceId, intent: c.e("intent"), feedback: c.e("feedback"),
                                      confirmation: confirmation(c.field("confirmation")),
                                      confirmWhen: confirmWhen(c.field("confirmation"))))
        case "conditional": return try conditionalAction(c)
        case "call-service": return try .callService(callService(c))
        case "push": require("actions.navigation"); return try .push(push(c))
        case "select-tab":
            require("actions.navigation")
            let id = try c.s("tabId")
            tabRefs.append((id, c.path("tabId")))
            return .selectTab(tabId: id)
        case "present":
            require("actions.navigation")
            if c.value["ifPresented"] == .string("replace") { require("modal-handoff") }
            let id = try c.s("modalId")
            modalRefs.append((id, c.path("modalId")))
            return try .present(modalId: id, arguments: .init(), ifPresented: c.e("ifPresented"))
        case "back": require("actions.navigation"); return .back
        case "dismiss": require("actions.navigation"); return try .dismiss(scope: c.e("scope"))
        case "dismiss-then-push":
            require("actions.navigation")
            return try .dismissThenPush(push(c.field("destination")))
        default: throw Issue(.unknownVariant, c.path("type"))
        }
    }
    // MARK: - Expressions

    /// Folds a parser's diagnostics, source references and capability needs into this compile.
    private mutating func absorb(_ parser: ServerUIExpressionParser) throws {
        expressionRefs += parser.references
        optimisticRefs += parser.optimisticReferences
        if parser.usedOperands { require("operands") }
        for need in parser.needs { require(need) }
        if !parser.references.isEmpty || !parser.optimisticReferences.isEmpty { require("bindings") }
        if let first = parser.issues.first {
            issues += parser.issues
            throw first
        }
    }

    mutating func predicate(_ c: Cursor) throws -> ServerUIPredicate {
        var parser = ServerUIExpressionParser()
        let value = parser.predicate(c.value, at: c.pointer)
        try absorb(parser)
        guard let value else { throw Issue(.invalidValue, c.pointer) }
        return value
    }

    mutating func operand(_ c: Cursor) throws -> ServerUIOperand {
        var parser = ServerUIExpressionParser()
        let value = parser.operand(c.value, at: c.pointer)
        try absorb(parser)
        guard let value else { throw Issue(.invalidValue, c.pointer) }
        return value
    }

    private mutating func callService(_ c: Cursor) throws -> ServerUICallService {
        require("call-service")
        var parser = ServerUIExpressionParser(allowControl: controlContext)
        let value = parser.callService(c.value, at: c.pointer)
        try absorb(parser)
        guard let value else { throw Issue(.invalidValue, c.pointer) }
        return value
    }

    /// Whether a rule uses only the `viewer` predicate and the combinators (`all`, `any`, `not`).
    private static func asksOnlyAboutViewer(_ rule: JSONValue) -> Bool {
        guard case .object(let object) = rule, case .string(let type)? = object["type"] else { return false }
        switch type {
        case "viewer": return true
        case "not": return object["of"].map(asksOnlyAboutViewer) ?? false
        case "all", "any":
            guard case .array(let items)? = object["of"] else { return false }
            return items.allSatisfy(asksOnlyAboutViewer)
        default: return false
        }
    }

    /// A node's or tab's `visibleWhen` with its `whenUnknown` policy.
    mutating func visibility(_ c: Cursor) throws -> ServerUIVisibility? {
        guard c.value["visibleWhen"] != nil else {
            if c.value["whenUnknown"] != nil { add(.invalidCombination, c.path("whenUnknown")) }
            return nil
        }
        require("visible-when")
        let policy: ServerUIVisibility.WhenUnknown = try c.value["whenUnknown"] == nil ? .keep : c.e("whenUnknown")
        return try ServerUIVisibility(predicate: predicate(c.field("visibleWhen")), whenUnknown: policy)
    }

    private mutating func boundControl(_ c: Cursor, node: D.Node, props: Cursor) throws -> D.BoundControl {
        require("bound-control")
        let kind: D.BoundControl.Kind = try props.e("kind")
        let surface: D.BoundControl.Surface = try props.value["surface"] == nil ? .row : props.e("surface")
        if props.value["surface"] != nil, kind != .toggle { add(.invalidCombination, props.path("surface")) }
        // The fields each kind uses, and only those.
        let allowed: [D.BoundControl.Kind: Set<String>] = [
            .toggle: ["isOn"], .stepper: ["value", "range", "format"], .slider: ["value"],
            .choice: ["options"], .button: []
        ]
        for key in ["isOn", "value", "range", "format", "options"] where props.value[key] != nil && allowed[kind]?.contains(key) != true {
            add(.invalidCombination, props.path(key))
        }
        let actionKeys: [D.BoundControl.Kind: Set<String>] = [
            .toggle: ["onAction", "offAction"], .stepper: ["action"], .slider: ["action"], .choice: [], .button: ["action"]
        ]
        for key in ["onAction", "offAction", "action"] where c.value[key] != nil && actionKeys[kind]?.contains(key) != true {
            add(.invalidCombination, c.path(key))
        }
        for key in actionKeys[kind] ?? [] where c.value[key] == nil { add(.missingRequired, c.path(key)) }
        for key in allowed[kind] ?? [] where key != "format" && props.value[key] == nil { add(.missingRequired, props.path(key)) }
        // A slider is the canonical percent row, and a stepper's two ends and its step are whole numbers it can land on.
        controlContext = kind != .button
        defer { controlContext = false }
        func call(_ key: String, in compiler: inout Self) throws -> ServerUICallService? {
            guard c.value[key] != nil else { return nil }
            return try compiler.callService(c.field(key))
        }
        let onAction = try call("onAction", in: &self), offAction = try call("offAction", in: &self)
        let action = try call("action", in: &self)
        let isOn = try props.value["isOn"] == nil ? nil : predicate(props.field("isOn"))
        let value = try props.value["value"] == nil ? nil : operand(props.field("value"))
        var range: D.BoundControl.Range?
        if props.value["range"] != nil {
            let r = try props.field("range")
            let parsed = try D.BoundControl.Range(minimum: r.i("min"), maximum: r.i("max"), step: r.i("step"))
            if parsed.minimum >= parsed.maximum || (parsed.maximum - parsed.minimum) % parsed.step != 0 {
                add(.invalidValue, props.path("range"))
            }
            range = parsed
        }
        let format = try props.optionalString("format")
        if let format, !format.contains("{value}") { add(.invalidValue, props.path("format")) }
        var options: [D.BoundControl.Option] = []
        if props.value["options"] != nil {
            let items = try props.field("options").array()
            if items.count < 2 { add(.limitExceeded, props.path("options")) }
            options = try items.map { item in
                require("selected-when")
                let id = try item.s("id")
                return try D.BoundControl.Option(id: id, label: item.s("label"), selectedWhen: predicate(item.field("selectedWhen")),
                                                 action: callService(item.field("action")))
            }
            if Set(options.map(\.id)).count != options.count { add(.duplicateID, props.path("options")) }
        }
        return try D.BoundControl(
            node: node, icon: c.value["icon"] == nil ? nil : symbol(c.field("icon")), kind: kind, surface: surface,
            isOn: isOn, value: value, range: range, valueFormat: format, options: options,
            onAction: onAction, offAction: offAction, action: action, unavailableText: props.s("unavailableText"))
    }


    /// Containers that lay their children out themselves (module lists with their separators, pages of a paged row, the chip rail,
    /// room sections) take no `visibleWhen`: hiding one child there would leave a gap, a separator or an empty page. Plain sections,
    /// local tabs, tile grids and the page body hide a child in place.
    private mutating func forbidRules(in children: [D.Component], at pointer: String) {
        for (index, child) in children.enumerated() where child.node.visibleWhen != nil {
            add(.invalidCombination, pointer + "/\(index)/visibleWhen")
        }
    }

    private mutating func forbidRules(in children: [JSONValue], at pointer: String) {
        for (index, child) in children.enumerated() where child["visibleWhen"] != nil {
            add(.invalidCombination, pointer + "/\(index)/visibleWhen")
        }
    }

    private mutating func push(_ c: Cursor) throws -> D.Push {
        let id = try c.s("pageId")
        pageRefs.append((id, c.path("pageId")))
        return try .init(pageId: id, arguments: .init(), origin: c.e("origin"), duplicate: c.e("duplicate"))
    }
    private func confirmation(_ c: Cursor) throws -> D.Confirmation {
        if try c.s("type") == "policy" { return .policy }
        return try .additional(style: c.e("style"), title: c.s("title"), message: c.optionalString("message"),
                               confirmLabel: c.s("confirmLabel"), cancelLabel: c.s("cancelLabel"), destructive: c.b("destructive"))
    }

    mutating func navigationAction(_ c: Cursor) throws -> D.Action {
        let intent = try action(c)
        check(intent, at: c.pointer) { Self.navigates($0) }
        return intent
    }

    /// Whether an action navigates: a push, a presentation, a tab switch or a dismiss-then-push.
    private static func navigates(_ intent: D.Action) -> Bool {
        switch intent {
        case .push, .present, .dismissThenPush, .selectTab: true
        default: false
        }
    }

    private mutating func roomVisibility(_ c: Cursor, key: String) throws -> D.RoomVisibility? {
        guard c.value[key] != nil else { return nil }
        require("room-visibility"); require("bindings")
        let gate = try c.field(key), sourceId = try gate.s("sourceId")
        visibilityRefs.append((sourceId, gate.path("sourceId")))
        return try .init(sourceId: sourceId, states: gate.field("states").array().map { try $0.string() })
    }

    private mutating func roomCard(_ c: Cursor, node: D.Node, chip: Bool) throws -> D.RoomCard {
        require(chip ? "room-chip" : "room-card"); require("bindings")
        if !chip { require("tiles") }
        let binding = try c.field("binding"), sourceId = try binding.s("sourceId"), props = try c.field("props")
        roomRefs.append((sourceId, binding.path("sourceId"), false))
        let subtitles = try props.field("subtitleSourceIds").array().map { try $0.string() }
        for (index, id) in subtitles.enumerated() {
            roomRefs.append((id, props.path("subtitleSourceIds") + "/\(index)", false))
        }
        var states: Set<String> = []
        let labels = try props.field("stateLabels").array().map { item -> D.RoomStateLabel in
            let state = try item.s("state")
            if !states.insert(state).inserted { add(.invalidCombination, item.path("state")) }
            return try .init(state: state, label: item.s("label"))
        }
        let intent = try props.value["action"].map { _ in try navigationAction(props.field("action")) }
        let power: D.PowerAction?
        if props.value["power"] != nil {
            let action = try action(props.field("power"))
            if chip { add(.invalidCombination, props.path("power")) }
            guard case .domain(let value) = action else { throw Issue(.invalidCombination, props.path("power") + "/type") }
            power = value
        } else { power = nil }
        let alternate = try props.value["alternate"].map { _ -> D.RoomAlternate in
            let a = try props.field("alternate"), id = try a.s("sourceId")
            roomRefs.append((id, a.path("sourceId"), false))
            let subtitles = try a.field("subtitleSourceIds").array().map { item in
                let id = try item.string(); roomRefs.append((id, item.pointer, false)); return id
            }
            guard let gate = try roomVisibility(a, key: "when") else { throw Issue(.missingRequired, a.path("when")) }
            return try .init(when: gate, sourceId: id, showState: a.b("showState"), subtitleSourceIds: subtitles)
        }
        let chipSources = try props.value["chipSources"].map { _ -> D.RoomChipSources in
            let c = try props.field("chipSources")
            for key in ["aqiSourceId", "colorSourceId", "alarmSourceId", "homeAwaySourceId"] {
                if let id = try c.optionalString(key) { roomRefs.append((id, c.path(key), false)) }
            }
            let away = try c.field("awaySourceIds").array().map { item in
                let id = try item.string(); roomRefs.append((id, item.pointer, false)); return id
            }
            return try .init(aqiSourceId: c.optionalString("aqiSourceId"), colorSourceId: c.optionalString("colorSourceId"),
                             alarmSourceId: c.optionalString("alarmSourceId"), homeAwaySourceId: c.optionalString("homeAwaySourceId"),
                             awaySourceIds: away, pluralContacts: c.b("pluralContacts"))
        }
        let personalization = try props.value["personalization"].map { _ -> D.RoomPersonalization in
            let p = try props.field("personalization")
            return try .init(residentId: p.s("residentId"), ownTitle: p.s("ownTitle"), otherTitle: p.s("otherTitle"))
        }
        var colorStates: Set<String> = []
        let colors = try props.value["stateColors"].map { _ in
            try props.field("stateColors").array().map { item -> D.RoomStateColor in
                let state = try item.s("state")
                if !colorStates.insert(state).inserted { add(.invalidCombination, item.path("state")) }
                var rules = ServerUIRuleDecoder()
                let slot = try rules.fill(item.field("fill").value, at: item.path("fill"))
                try absorb(rules)
                guard let slot else { throw Issue(.invalidValue, item.path("fill")) }
                return .init(state: state, fill: slot.0, fillRule: slot.1)
            }
        } ?? []
        return try .init(node: node, icon: symbol(c.field("icon")), sourceId: sourceId, kind: props.e("kind"),
                         showState: props.b("showState"), subtitleSourceIds: subtitles,
                         activeStates: props.field("activeStates").array().map { try $0.string() },
                         disabledStates: props.field("disabledStates").array().map { try $0.string() },
                         stateLabels: labels, visibility: roomVisibility(props, key: "visibility"), action: intent, power: power,
                         alternate: alternate, chipSources: chipSources, personalization: personalization, stateColors: colors,
                         climateActionTone: props.value["climateActionTone"] == nil ? false : props.b("climateActionTone"))
    }

    // MARK: - Component forest

    mutating func components(_ c: Cursor, depth: Int, gridChild: Bool) throws -> [D.Component] {
        var result: [D.Component] = []
        for child in try c.array() {
            do { result.append(try component(child, depth: depth, gridChild: gridChild)) }
            catch let issue as Issue { issues.append(issue) }
        }
        if depth == 1 {
            let scopedTabs = result.filter { if case .localTabs(let tabs) = $0 { tabs.scopeProviderId != nil } else { false } }.count
            if scopedTabs > 1 { add(.invalidCombination, c.pointer) }
            let pinnedTabs = result.filter { if case .localTabs(let tabs) = $0 { tabs.pinned } else { false } }.count
            if pinnedTabs > 1 || (pinnedTabs > 0 && result.contains(where: {
                if case .pinnedActions = $0 { return true }
                if case .form = $0 { return true }
                return false
            })) { add(.invalidCombination, c.pointer) }
            for kind in ["form", "pinned-actions"] {
                let count = try c.array().filter { try $0.s("type") == kind }.count
                if count > 1 { add(.invalidCombination, c.pointer) }
            }
        }
        // Failed fragments are never returned as an accepted plan: compile checks all collected
        // diagnostics before returning. Continue only to order independent semantic failures.
        return result
    }

    private mutating func component(_ c: Cursor, depth: Int, gridChild: Bool) throws -> D.Component {
        nodeCount += 1
        guard nodeCount <= 4_096, depth <= 12 else { throw Issue(.limitExceeded, c.pointer) }
        let id = try c.s("id"), span = try layoutSpan(c)
        register(id, catalog: "node", at: c.path("id"))
        if !gridChild, span != 1 { add(.invalidCombination, c.path("layout") + "/span") }
        var node = try D.Node(id: id, title: c.s("title"), span: span, visibleWhen: visibility(c), enabledWhen: enabled(c))
        try badge(of: c, into: &node)
        let props = try c.field("props")
        if depth > 1, ["form", "pinned-actions"].contains(try c.s("type")) {
            add(.invalidCombination, c.path("type"))
        }
        if let home = try homeComponent(c, node: node, props: props, depth: depth) { return home }
        if let container = try containerComponent(c, node: node, props: props, depth: depth) { return container }
        return try leafComponent(c, node: node, props: props, gridChild: gridChild)
    }

    // Keep recursive container frames independent of the growing set of atomic controls.
    private mutating func containerComponent(_ c: Cursor, node: D.Node, props: Cursor, depth: Int) throws -> D.Component? {
        switch try c.s("type") {
        case "paged-row":
            require("paged-row")
            let children = try components(c.field("children"), depth: depth + 1, gridChild: false)
            forbidRules(in: children, at: c.path("children"))
            return .pagedRow(.init(node: node, perPage: try props.i("perPage"), pageLabel: try props.s("pageLabel"),
                showsIndicator: try props.b("showsIndicator"), children: children))
        case "section":
            require("section")
            if props.value["presentationProviderId"] != nil { require("presentation-providers") }
            let children = try components(c.field("children"), depth: depth + 1, gridChild: false)
            let style: D.Section.Style = try props.e("style")
            if style == .moduleList {
                for (index, child) in children.enumerated() {
                    switch child {
                    case .row, .localControl: break
                    case .boundControl(let control) where control.kind != .button && control.surface == .row: break
                    case .climate(let control) where [.toggle, .explicitSwitch, .status, .link].contains(control.props.kind): break
                    case .settingsLink: require("module-settings-rows")
                    case .settingsControl(let control):
                        switch control.kind {
                        case .householdRecovery, .presenceChoice, .vacationCheck, .vacationConfirm, .soloConfirm, .awayRestore,
                             .blur, .resetBlur, .badge, .iconChoice, .version, .profilePerson, .signOut, .homeAssistantValue,
                             .homeAssistantWeb, .performanceRecording: require("module-settings-rows")
                        default: add(.invalidCombination, c.path("children") + "/\(index)/type")
                        }
                    default: add(.invalidCombination, c.path("children") + "/\(index)/type")
                    }
                }
            }
            if style == .moduleList { forbidRules(in: children, at: c.path("children")) }
            return try .section(.init(node: node, header: props.s("header"), footer: props.s("footer"),
                                       style: style, density: props.e("density"), hasGlyphs: props.b("hasGlyphs"),
                                       spacing: space(props.field("spacing")), children: children,
                                       presentationProviderId: props.optionalString("presentationProviderId")))
        case "local-tabs":
            require("local-tabs"); require("local-state")
            let pinned = props.value["pinned"]?.bool ?? false
            let showsSelector = props.value["showsSelector"]?.bool ?? true
            let retainsAutomatic = props.value["retainsAutomaticSelection"]?.bool ?? false
            let scope = try props.optionalString("scopeProviderId")
            if scope != nil {
                require("presentation-providers")
                if depth != 1 { add(.invalidCombination, props.path("scopeProviderId")) }
            }
            if (!showsSelector || retainsAutomatic) && scope == nil || pinned && !showsSelector {
                add(.invalidCombination, props.pointer)
            }
            if pinned {
                require("pinned-tabs")
                if depth != 1 { add(.invalidCombination, props.path("pinned")) }
            }
            let stateId = try props.s("stateId")
            let tabs = try c.field("tabs").array().map { tab in
                try D.LocalTabs.TabContent(id: tab.s("id"), label: tab.s("label"),
                    children: components(tab.field("children"), depth: depth + 1, gridChild: false),
                    icon: tab.value["icon"] == nil ? nil : symbol(tab.field("icon")),
                    centerWhenFits: tab.value["centerWhenFits"]?.bool ?? false, visibility: tabRule(tab))
            }
            if pinned && props.value["tabBar"] == nil && tabs.contains(where: { $0.icon == nil }) { add(.invalidCombination, c.path("tabs")) }
            if Set(tabs.map(\.id)).count != tabs.count { add(.duplicateID, c.path("tabs")) }
            if let field = localFields.first(where: { $0.id == stateId }) {
                if case .choice(let options) = field.rule {
                    if options.map(\.id) != tabs.map(\.id) || options.map(\.label) != tabs.map(\.label) {
                        add(.invalidCombination, props.path("stateId"))
                    }
                } else { add(.bindingType, props.path("stateId")) }
            } else { add(.invalidReference, props.path("stateId")) }
            var automatic: [D.LocalTabs.AutomaticRule] = []
            if props.value["automatic"] != nil {
                require("selected-when")
                let rules = try props.field("automatic").array()
                automatic = try rules.map { rule in
                    let id = try rule.s("tabId")
                    if !tabs.contains(where: { $0.id == id }) { add(.invalidReference, rule.path("tabId")) }
                    return try .init(tabId: id, selectedWhen: predicate(rule.field("selectedWhen")))
                }
                if scope != nil { add(.invalidCombination, props.path("automatic")) }
            }
            var container = D.LocalTabs(node: node, stateId: stateId, tabs: tabs,
                resetOnPresentation: props.value["resetOnPresentation"]?.bool ?? false, pinned: pinned,
                scopeProviderId: scope, showsSelector: showsSelector, retainsAutomaticSelection: retainsAutomatic,
                automatic: automatic)
            try tabLayout(c, props: props, depth: depth, into: &container)
            return .localTabs(container)
        case "overlay":
            return try overlay(c, node: node, props: props, depth: depth)
        case "room-section":
            require("room-section"); require("grid")
            defer { if case .array(let items)? = c.value["children"] { forbidRules(in: items, at: c.path("children")) } }
            return try .roomSection(.init(
                node: node, layout: props.e("arrangement"), leadJoinsAtRegularWidth: props.b("leadJoinsAtRegularWidth"),
                visibility: roomVisibility(props, key: "visibility"),
                children: components(c.field("children"), depth: depth + 1, gridChild: true)
            ))
        case "tile-grid":
            require("grid")
            if try props.s("minimum") == D.Policy.sectionWide.rawValue {
                require("section-grid")
                if try props.i("maxColumns") > 2 { add(.invalidCombination, props.path("maxColumns")) }
            }
            if try props.s("minimum") == D.Policy.tileDynamicType.rawValue { require("grid-dynamic-type") }
            return try .grid(.init(
                node: node, minimum: props.e("minimum"), maxColumns: props.i("maxColumns"),
                spacing: space(props.field("spacing")), equalRowHeights: props.b("equalRowHeights"),
                shortRow: props.e("shortRow"), fold: props.e("fold"),
                children: components(c.field("children"), depth: depth + 1, gridChild: true)
            ))
        default: return nil
        }
    }

    private mutating func recordComponent(_ c: Cursor, node: D.Node, props: Cursor) throws -> D.Component? {
        switch try c.s("type") {
        case "collection":
            require("collection")
            let links: [D.Collection.BedroomLink] = try props.value["bedroomLinks"].map { _ in
                require("bedroom-collection-links")
                return try props.field("bedroomLinks").array().map {
                    try D.Collection.BedroomLink(side: $0.e("side"), label: $0.s("label"), action: navigationAction($0.field("action")))
                }
            } ?? []
            if !links.isEmpty, props.value["template"] != .string("rows") || Set(links.map(\.side)).count != links.count {
                add(.invalidCombination, props.path("bedroomLinks"))
            }
            let refreshes = try props.value["pullToRefresh"] == nil ? false : props.b("pullToRefresh")
            return try .collection(.init(node: node, providerId: props.s("providerId"), template: props.e("template"),
                loadingText: props.s("loadingText"), emptyText: props.s("emptyText"),
                selection: c.value["selection"].map { _ in try navigationAction(c.field("selection")) }, bedroomLinks: links,
                pullsToRefresh: refreshes))
        case "form":
            require("form")
            let fields = try props.field("fields").array().map {
                try D.Form.Field(key: $0.s("key"), label: $0.s("label"), control: $0.e("control"))
            }
            if Set(fields.map(\.key)).count != fields.count { add(.duplicateID, props.path("fields")) }
            if fields.contains(where: { $0.control == .scheduleDateTime }) { require("schedule-date-fields") }
            let success = try c.value["success"].map { _ in try action(c.field("success")) }
            if let success {
                switch success {
                case .back, .dismiss, .dismissThenPush: break
                default: add(.invalidCombination, c.path("success"))
                }
            }
            return try .form(.init(node: node, providerId: props.s("providerId"), fields: fields,
                                   saveLabel: props.s("saveLabel"), selectionOnly: props.b("selectionOnly"), success: success))
        case "recipe-part":
            require("recipe-part")
            return try .recipePart(.init(node: node, providerId: props.s("providerId"), part: props.e("part")))
        case "pinned-actions":
            require("pinned-actions")
            let children = try c.value["children"].map { _ in try components(c.field("children"), depth: 2, gridChild: false) } ?? []
            for (index, child) in children.enumerated() {
                switch child {
                case .button: break
                case .settingsControl(let control):
                    switch control.kind {
                    case .vacationConfirm, .soloConfirm, .feedbackSubmit, .feedbackStop, .performanceAction, .locationAction, .homeAssistant: break
                    default: add(.invalidCombination, c.path("children") + "/\(index)/type")
                    }
                default: add(.invalidCombination, c.path("children") + "/\(index)/type")
                }
            }
            let style = try props.value["style"] == nil ? D.PinnedActions.Style.floating : props.e("style")
            if style == .form { require("pinned-form-actions") }
            let items = try props.field("items").array().map {
                try D.PinnedActions.Item(id: $0.s("id"), title: $0.s("title"), icon: symbol($0.field("icon")),
                    prominent: $0.b("prominent"), showsTitle: $0.b("showsTitle"),
                    action: style == .form ? action($0.field("action")) : navigationAction($0.field("action")),
                    role: $0.value["role"] == nil ? nil : $0.e("role"), stateProviderId: $0.optionalString("stateProviderId"))
            }
            if style == .form {
                if items.count + children.count > 2 || items.filter(\.prominent).count + children.count != 1 || props.value["searchProviderId"] != nil || items.contains(where: { $0.role != nil }) {
                    add(.invalidCombination, props.pointer)
                }
            } else if !children.isEmpty || items.contains(where: { $0.stateProviderId != nil }) { add(.invalidCombination, props.pointer) }
            if Set(items.map(\.id)).count != items.count { add(.duplicateID, props.path("items")) }
            if items.isEmpty, children.isEmpty, props.value["searchProviderId"] == nil { add(.invalidCombination, props.pointer) }
            if items.contains(where: { $0.role != nil }), props.value["searchProviderId"] == nil { add(.invalidCombination, props.pointer) }
            return try .pinnedActions(.init(node: node, searchProviderId: props.optionalString("searchProviderId"),
                                             searchPrompt: props.s("searchPrompt"), items: items, style: style, children: children))
        default: return nil
        }
    }

    private mutating func leafComponent(_ c: Cursor, node: D.Node, props: Cursor, gridChild: Bool) throws -> D.Component {
        if let record = try recordComponent(c, node: node, props: props) { return record }
        switch try c.s("type") {
        case "info-box":
            require("info-box")
            return try .infoBox(.init(node: node, message: stringValue(props.field("message")), tone: props.e("tone"),
                                      unavailableText: props.s("unavailableText")))
        case "status-pill":
            require("status-pill")
            var rules = ServerUIRuleDecoder()
            let tone = try rules.tone(props.field("tone").value, at: props.path("tone"))
            try absorb(rules)
            guard let tone else { throw Issue(.invalidValue, props.path("tone")) }
            return try .statusPill(.init(node: node, icon: symbol(c.field("icon")), value: stringValue(props.field("value")),
                detail: stringValue(props.field("detail")), tone: tone.0, unavailableText: props.s("unavailableText"),
                toneCases: tone.1))
        case "row":
            require("rows")
            let intent = try c.value["action"] == nil ? nil : action(c.field("action"))
            if let intent { check(intent, at: c.path("action")) { if case .domain = $0 { false } else { true } } }
            if node.enabledWhen != nil, intent == nil { add(.invalidCombination, c.path("enabledWhen")) }
            let accessory: D.Row.Accessory = try props.e("accessory")
            if accessory == .disclosure, intent == nil { add(.invalidCombination, props.path("accessory")) }
            return try .row(.init(node: node, primary: stringValue(props.field("primary")),
                                  secondary: stringValue(props.field("secondary")), value: stringValue(props.field("value")),
                                  icon: props.value["icon"] == nil ? nil : symbol(props.field("icon")), accessory: accessory,
                                  loadingText: props.s("loadingText"), unavailableText: props.s("unavailableText"), action: intent))
        case "local-control":
            require("local-controls"); require("local-state")
            let stateId = try props.s("stateId"), kind: D.LocalControl.Kind = try props.e("kind")
            if let field = localFields.first(where: { $0.id == stateId }) {
                switch (kind, field.rule) {
                case (.toggle, .boolean), (.choice, .choice), (.textField, .string): break
                case (.segmentedChoice, .choice(let options)):
                    if options.count > 4 { add(.invalidCombination, props.path("stateId")) }
                case (.stepper, .number(let minimum, let maximum, let step)):
                    if minimum.rounded() != minimum || maximum.rounded() != maximum || step.rounded() != step {
                        add(.invalidCombination, props.path("stateId"))
                    }
                default: add(.bindingType, props.path("stateId"))
                }
            } else { add(.invalidReference, props.path("stateId")) }
            return try .localControl(.init(node: node, stateId: stateId, kind: kind, placeholder: props.s("placeholder")))
        case "bound-control": return try .boundControl(boundControl(c, node: node, props: props))
        case "primary-button":
            require("primary-button")
            let intent = try action(c.field("action"))
            check(intent, at: c.path("action")) { if case .domain = $0 { false } else { true } }
            return try .button(.init(node: node, icon: c.value["icon"] == nil ? nil : symbol(c.field("icon")),
                                      action: intent))
        case "row-collection":
            require("row-collection")
            return try .rowCollection(.init(node: node, providerId: props.s("providerId"),
                                             loadingText: props.s("loadingText"), emptyText: props.s("emptyText"),
                                             unavailableText: props.s("unavailableText"), errorText: props.s("errorText"),
                                             staleText: props.s("staleText")))
        case "alarm-panel":
            require("alarm-panel"); require("alarm-mode"); require("bindings")
            let source = try props.s("sourceId")
            alarmRefs.append((source, props.path("sourceId")))
            let modes = try props.field("modes").array()
            uniqueStates(modes)
            let states = try props.field("states").array()
            uniqueStates(states)
            let confirmation = try props.field("confirmation")
            return try .alarmPanel(.init(
                node: node, sourceId: source,
                modes: modes.map { try .init(state: $0.s("state"), label: $0.s("label"), hint: $0.s("hint"),
                                             icon: symbol($0.field("icon")), fill: solidFill($0.field("fill"))) },
                states: states.map { try .init(state: $0.s("state"), appearance: alarmAppearance($0.field("appearance"))) },
                fallback: alarmAppearance(props.field("fallback")), subtitle: props.s("subtitle"),
                sincePrefix: props.s("sincePrefix"), separator: props.s("separator"), loadingText: props.s("loadingText"),
                unavailableText: props.s("unavailableText"), hiddenText: props.s("hiddenText"), errorText: props.s("errorText"),
                pendingText: props.s("pendingText"),
                confirmation: .init(title: confirmation.s("title"), message: confirmation.s("message"),
                                    confirmLabel: confirmation.s("confirmLabel"), cancelLabel: confirmation.s("cancelLabel")),
                triggeredWash: solidFill(props.field("triggeredWash"))
            ))
        case "door-tile":
            require("security-door"); require("bindings"); require("tiles")
            let source = try props.s("sourceId"), kind: D.DoorKind = try props.e("kind")
            doorRefs.append((source, kind, props.path("sourceId")))
            let states = try props.field("states").array()
            uniqueStates(states)
            let allowed = kind == .lock
                ? Set(["locked", "unlocked", "locking", "unlocking", "open", "jammed"])
                : Set(["closed", "open", "opening", "closing"])
            for state in states where try !allowed.contains(state.s("state")) { add(.invalidCombination, state.path("state")) }
            let lowered = try ServerUIDoorLowering.lower(.init(
                node: node, sourceId: source, kind: kind,
                states: states.map { try .init(state: $0.s("state"), appearance: alarmAppearance($0.field("appearance")),
                                              active: $0.b("active"), error: $0.b("error")) },
                fallback: alarmAppearance(props.field("fallback")), loadingText: props.s("loadingText"),
                hiddenText: props.s("hiddenText"), unavailableText: props.s("unavailableText"), errorText: props.s("errorText"),
                sendingOpenText: props.s("sendingOpenText"), sendingCloseText: props.s("sendingCloseText"),
                openLabel: props.s("openLabel"), closeLabel: props.s("closeLabel"), reverseLabel: props.s("reverseLabel")
            ), entityId: doorSources[source]?.entityId ?? "")
            if !loweredStyles.contains(where: { $0.style.id == lowered.style.style.id }) { loweredStyles.append(lowered.style) }
            return .stateTile(lowered.tile)
        case "climate-control":
            require("bindings"); require("climate-source")
            let configuration = try JSONDecoder().decode(ServerUIClimateControl.Properties.self, from: JSONEncoder().encode(props.value))
            requirements.insert(configuration.kind.capability)
            let intent = try optionalHomeAction(c)
            if [.link, .roomTile].contains(configuration.kind) != (intent != nil) { add(.invalidCombination, c.path("action")) }
            if configuration.kind == .roomTile { require("tiles") }
            let control = ServerUIClimateControl(node: node, props: configuration, action: intent)
            climateRefs.append((control, props.pointer))
            return .climate(control)
        case "room-card": return try .roomCard(roomCard(c, node: node, chip: false))
        case "room-chip": return try .roomChip(roomCard(c, node: node, chip: true))
        case "room-navigation-grid":
            require("room-navigation"); require("bindings"); require("tiles"); require("grid")
            let binding = try c.field("binding"), sourceId = try binding.s("sourceId")
            roomRefs.append((sourceId, binding.path("sourceId"), true))
            return .roomNavigationGrid(.init(node: node, sourceId: sourceId))
        case "room-device-control": return try .roomDeviceControl(deviceControl(c, node: node))
        case "bedroom-control":
            return try .bedroom(bedroom(node: node, props: props))
        case "custom-light-control", "sprinkler-control":
            let domain: ServerUIDeviceControl.Domain = try c.s("type") == "custom-light-control" ? .lights : .sprinkler
            require(domain == .lights ? "custom-lights" : "sprinkler-controller"); require("bindings")
            let question = try props.value["confirmation"].map { _ in
                let q = try props.field("confirmation")
                return try ServerUIBedroomControl.Question(title: q.s("title"), message: q.s("message"),
                                                           confirmLabel: q.s("confirmLabel"), cancelLabel: q.s("cancelLabel"))
            }
            let intent = try props.value["action"].map { _ in try action(props.field("action")) }
            if let intent {
                switch intent {
                case .push, .present, .selectTab, .dismissThenPush: break
                default: add(.invalidCombination, props.path("action"))
                }
            }
            let control = try ServerUIDeviceControl(node: node, domain: domain, sourceId: props.s("sourceId"),
                kind: props.e("kind"), entityId: props.optionalString("entityId"), copySourceId: props.optionalString("copySourceId"),
                zone: props.value["zone"].map { _ in try props.i("zone") }, action: intent, confirmation: question)
            providerControlRefs.append((control, props.pointer))
            return .deviceControl(control)
        case "remote-control":
            require("bindings"); require("media-remote")
            let binding = try c.field("binding"), sourceId = try binding.s("sourceId")
            remoteRefs.append((sourceId, binding.path("sourceId")))
            let control = try remoteControl(props)
            requirements.insert(control.capability)
            let feedback = try c.field("feedback")
            let personalization = try props.value["personalization"].map { _ -> D.RoomPersonalization in
                let p = try props.field("personalization")
                return try .init(residentId: p.s("residentId"), ownTitle: p.s("ownTitle"), otherTitle: p.s("otherTitle"))
            }
            if props.value["presentation"] != .string("tile") {
                for key in ["personalization", "family"] where props.value[key] != nil { add(.invalidCombination, props.path(key)) }
            }
            return try .remote(.init(node: node, sourceId: sourceId, control: control,
                                      feedback: .init(loadingText: feedback.s("loadingText"), errorText: feedback.s("errorText")),
                                      deviceTile: props.value["presentation"] == .string("tile"), personalization: personalization,
                                      deviceFamily: props.optionalString("family").flatMap(RoomCardKind.init(rawValue:)) ?? .media))
        case "vacuum-control":
            require("vacuum"); require("bindings")
            let p = try props.field("primitive")
            let primitive: D.VacuumPrimitive
            switch try p.s("kind") {
            case "card":
                require("vacuum-controls")
                let commands = try p.field("commands").array().map { try $0.enumeration() as D.VacuumCardCommand }
                if Set(commands).count != commands.count { add(.invalidCombination, p.path("commands")) }
                let destination = try action(p.field("destination"))
                switch destination {
                case .push, .present: break
                default: add(.invalidCombination, p.path("destination") + "/type")
                }
                primitive = try .card(icon: symbol(p.field("icon")), commands: commands, destination: destination)
            case "map":
                require("vacuum-map")
                primitive = try .map(overlay: p.e("overlay"), height: p.n("height"), runtimeHeight: p.n("runtimeHeight"),
                                     label: p.s("label"), loading: p.s("loadingText"), unavailable: p.s("unavailableText"), locate: p.b("locate"))
            case "status":
                require("vacuum-controls")
                primitive = try .status(metric: p.e("metric"))
            case "notices":
                require("vacuum-controls")
                primitive = .notices
            case "auto-clean":
                require("vacuum-auto-clean")
                primitive = .autoClean
            case "clear-area":
                require("vacuum-controls")
                primitive = try .clearArea(icon: symbol(p.field("icon")))
            case "settings":
                require("vacuum-controls")
                let rows = try p.field("rows").array().map {
                    try D.VacuumSettingLabel(role: $0.e("role"), title: $0.s("title"), hint: $0.s("hint"))
                }
                if Set(rows.map(\.role)).count != rows.count { add(.invalidCombination, p.path("rows")) }
                primitive = .settings(rows: rows)
            case "command":
                require("vacuum-controls")
                primitive = try .command(kind: p.e("command"), icon: symbol(p.field("icon")))
            case "choice":
                require("vacuum-controls")
                primitive = try .choice(entityId: p.s("entityId"), selection: p.e("selection"))
            case "consumable":
                require("vacuum-controls")
                primitive = try .consumable(entityId: p.s("entityId"))
            case "report":
                require("vacuum-outcomes")
                let destination = try action(p.field("destination"))
                switch destination {
                case .push, .present: break
                default: add(.invalidCombination, p.path("destination") + "/type")
                }
                primitive = .report(destination: destination)
            case "outcomes": require("vacuum-outcomes"); primitive = .outcomes
            case "target":
                require("vacuum-controls")
                let destination = try action(p.field("destination"))
                switch destination {
                case .push, .present: break
                default: add(.invalidCombination, p.path("destination") + "/type")
                }
                primitive = try .target(mode: p.e("mode"), icon: symbol(p.field("icon")), destination: destination)
            case "area-editor":
                require("vacuum-area"); require("vacuum-map")
                let use = try action(p.field("onUse")), discard = try action(p.field("onDiscard"))
                for (intent, key) in [(use, "onUse"), (discard, "onDiscard")] {
                    switch intent {
                    case .back, .dismiss: break
                    default: add(.invalidCombination, p.path(key) + "/type")
                    }
                }
                primitive = try .areaEditor(height: p.n("height"), use: use, discardLabel: p.s("discardLabel"), discard: discard)
            default: throw Issue(.unknownVariant, p.path("kind"))
            }
            let value = try D.VacuumControl(node: node, sourceId: props.s("sourceId"), primitive: primitive)
            vacuumRefs.append((value, props.pointer))
            return .vacuum(value)
        case "settings-control":
            require("settings-controls"); require("bindings")
            let kind: ServerUISettingsControl.Kind = try props.e("kind")
            let item = try props.s("item")
            let destination = try props.value["destination"].map { _ in try navigationAction(props.field("destination")) }
            if kind.requiresDestination != (destination != nil) { add(.invalidCombination, props.path("destination")) }
            if kind.allowsItem == item.isEmpty { add(.invalidCombination, props.path("item")) }
            if let items = kind.fixedItems, !items.contains(item) { add(.invalidCombination, props.path("item")) }
            let control = try ServerUISettingsControl(node: node, sourceId: props.s("sourceId"), kind: kind,
                                                       item: item, subtitle: props.s("subtitle"),
                                                       icon: symbol(c.field("icon")), destination: destination)
            settingsRefs.append((control, props.path("sourceId")))
            return .settingsControl(control)
        case "account-header":
            require("profile-account"); require("bindings")
            if gridChild { add(.invalidCombination, c.path("type")) }
            let binding = try c.field("binding")
            let sourceId = try binding.s("sourceId")
            profileRefs.append((sourceId, binding.path("sourceId")))
            return try .accountHeader(.init(node: node, sourceId: sourceId,
                                             fallbackName: props.s("fallbackName"), loadingText: props.s("loadingText"),
                                             unavailableText: props.s("unavailableText")))
        case "camera-tile":
            require("camera-tile"); require("bindings")
            let source = try props.s("sourceId")
            cameraRefs.append((source, props.path("sourceId"), false))
            let intent = try action(c.field("action"))
            guard case .present(let modalID, _, _) = intent else { throw Issue(.invalidCombination, c.path("action") + "/type") }
            cameraPresentations.append((source, modalID, c.path("action") + "/modalId"))
            return try .cameraTile(.init(node: node, sourceId: source, openHint: props.s("openHint"), action: intent))
        case "camera-video":
            require("camera-video"); require("bindings")
            let source = try props.s("sourceId")
            cameraRefs.append((source, props.path("sourceId"), false))
            return .cameraVideo(.init(node: node, sourceId: source))
        case "camera-controls", "camera-viewer":
            let viewer = try c.s("type") == "camera-viewer"
            require(viewer ? "camera-viewer" : "camera-controls"); require("bindings")
            if viewer { require("camera-video"); require("camera-controls") }
            let source = try props.s("sourceId")
            var seen: Set<D.CameraIntent> = []
            let controls = try props.field("controls").array().map { control -> D.CameraControl in
                let intent: D.CameraIntent = try control.e("intent")
                if !seen.insert(intent).inserted { add(.invalidCombination, control.path("intent")) }
                return try .init(intent: intent, title: control.s("title"), activeTitle: control.s("activeTitle"),
                                 busyTitle: control.s("busyTitle"), failureTitle: control.s("failureTitle"),
                                 icon: symbol(control.field("icon")), activeIcon: symbol(control.field("activeIcon")),
                                 failureIcon: symbol(control.field("failureIcon")), tint: control.e("tint"))
            }
            cameraRefs.append((source, props.path("sourceId"), seen.contains(.record)))
            let value = D.CameraControls(node: node, sourceId: source, controls: controls)
            return viewer ? .cameraViewer(value) : .cameraControls(value)
        case "notification-permission-banner":
            require("bootstrap-notifications")
            return try .notificationBanner(.init(node: node, message: props.s("message"),
                enableLabel: props.s("enableLabel"), dismissLabel: props.s("dismissLabel")))
        case "bootstrap-message":
            require("bootstrap-message")
            return try .bootstrapMessage(.init(node: node, icon: symbol(c.field("icon")), message: props.s("message")))
        case "text":
            require("text")
            let style: D.TextStyle = try props.e("style")
            if [.subheadline, .footnote].contains(style) { require("supporting-text-styles") }
            if style == .sectionTitle { require("section-title") }
            return try .text(.init(node: node, value: stringValue(props.field("value")),
                                   style: style, unavailableText: props.s("unavailableText")))
        case "settings-link":
            require("settings-link")
            if gridChild { add(.invalidCombination, c.pointer) }
            let intent = try action(c.field("action"))
            let isPush: Bool
            switch intent {
            case .push: isPush = true
            case .present, .selectTab, .dismissThenPush: isPush = false
            default:
                isPush = false
                add(.invalidCombination, c.path("action") + "/type")
            }
            let chevron = try props.b("showsChevron")
            if chevron != isPush { add(.invalidCombination, props.path("showsChevron")) }
            return try .settingsLink(.init(node: node, icon: symbol(c.field("icon")), subtitle: props.s("subtitle"),
                                           hint: props.optionalString("hint"), showsChevron: chevron, action: intent))
        case "navigation-tile":
            require("tiles")
            let familyName = try props.s("family")
            if props.value["titleProviderId"] != nil || !["neutral", "lights"].contains(familyName) {
                require("collection-navigation")
            }
            let intent = try action(c.field("action"))
            check(intent, at: c.path("action")) { Self.navigates($0) }
            let selected: D.Policy = try props.e("selected")
            if selected == .none { require("tile-presentation") }
            let presentation: D.TilePresentation?
            if props.value["presentation"] != nil {
                require("tile-presentation")
                let p = try props.field("presentation"), fill = try p.field("fill")
                var rules = ServerUIRuleDecoder()
                let slot = rules.fill(fill.value, at: fill.pointer)
                try absorb(rules)
                guard let slot else { throw Issue(.invalidValue, fill.pointer) }
                // A custom fill (exact, by rule or from an entity) belongs to a neutral tile.
                if slot.0 != .standard || slot.1 != nil, try props.s("family") != "neutral" { add(.invalidCombination, props.path("family")) }
                presentation = try .init(layout: p.e("layout"), titleLines: p.i("titleLines"),
                                         fill: slot.0, bodyHint: p.optionalString("bodyHint"), fillRule: slot.1)
            } else {
                presentation = nil
            }
            let alarm: D.AlarmNavigation?
            if props.value["alarm"] != nil {
                require("alarm-mode"); require("bindings")
                let a = try props.field("alarm"), sourceId = try a.s("sourceId")
                alarmRefs.append((sourceId, a.path("sourceId")))
                if try props.s("family") != "neutral" { add(.invalidCombination, props.path("family")) }
                if selected != .none { add(.invalidCombination, props.path("selected")) }
                if let presentation, presentation.fill != .standard || presentation.fillRule != nil {
                    add(.invalidCombination, props.path("presentation") + "/fill")
                }
                let subtitle = try props.field("subtitle")
                if subtitle.value["type"] != .string("literal") || subtitle.value["value"] != .string("") {
                    add(.invalidCombination, subtitle.pointer)
                }
                var states: Set<String> = []
                let appearances = try a.field("states").array().map { s -> D.AlarmStateAppearance in
                    let state = try s.s("state")
                    if !states.insert(state).inserted { add(.invalidCombination, s.path("state")) }
                    return try .init(state: state, appearance: alarmAppearance(s.field("appearance")))
                }
                alarm = try .init(sourceId: sourceId, projection: a.e("projection"), states: appearances,
                                  fallback: alarmAppearance(a.field("fallback")), loadingText: a.s("loadingText"),
                                  unavailableText: a.s("unavailableText"), errorText: a.s("errorText"), hiddenText: a.s("hiddenText"))
            } else { alarm = nil }
            return try .navigationTile(.init(
                node: node, icon: symbol(c.field("icon")), family: props.e("family"), selected: selected,
                subtitle: stringValue(props.field("subtitle")), presentation: presentation, alarm: alarm, action: intent,
                roomVisibility: roomVisibility(props, key: "roomVisibility"), titleProviderId: props.optionalString("titleProviderId")
            ))
        case "state-tile":
            require("tiles"); require("state-style")
            let decoded = ServerUIStateStyles.decodeBinding(try c.field("binding").value, at: c.path("binding"), library: stateLibrary)
            issues.append(contentsOf: decoded.issues)
            var tile = try D.StateTile(node: node, icon: symbol(c.field("icon")), binding: decoded.binding)
            try tileParts(c, props: props, into: &tile)
            return .stateTile(tile)
        case "action-tile":
            require("tiles"); require("bindings"); require("power-toggle")
            let labels = try props.value["powerLabels"].map { _ in
                let labels = try props.field("powerLabels")
                return try D.PowerLabels(on: labels.s("on"), off: labels.s("off"))
            }
            if labels != nil || props.value["family"] == .string("occupancy") { require("power-labels") }
            let binding = try c.field("binding")
            let sourceId = try binding.s("sourceId")
            powerRefs.append((sourceId, binding.path("sourceId"), .bindingType))
            let intent = try action(c.field("action"))
            guard case .domain(let power) = intent else { throw Issue(.invalidCombination, c.path("action") + "/type") }
            if power.sourceId != sourceId { add(.invalidCombination, c.path("action") + "/sourceId") }
            return try .actionTile(.init(
                node: node, icon: symbol(c.field("icon")),
                binding: .init(sourceId: sourceId, projection: binding.e("projection")),
                family: props.e("family"), bodyActionId: props.e("bodyActionId"),
                actionOrder: props.field("actionOrder").array().map { try $0.enumeration() },
                stateText: props.e("stateText"), feedback: props.e("feedback"), action: power, powerLabels: labels
            ))
        default: throw Issue(.unknownVariant, c.path("type"))
        }
    }

    private mutating func bedroom(node: D.Node, props: Cursor) throws -> ServerUIBedroomControl {
        let kind: ServerUIBedroomControl.Kind = try props.e("control")
        require(kind.rawValue); require("bindings")
        if props.value["showsExplanation"] != nil { require("wake-hold-explanation") }
        if props.value["episode"] != nil { require("wake-episode") }
        if props.value["showsHeading"] != nil { require("bedroom-field-headings") }
        let sourceId = try props.s("sourceId")
        if kind == .reading, props.value["parameter"] == .string("pump-status"),
           props.value["activeLabel"] == nil || props.value["inactiveLabel"] == nil {
            add(.invalidCombination, props.pointer)
        }
        let options = try props.value["options"].map { _ in
            try props.field("options").array().map {
                try ServerUIBedroomControl.Option(value: $0.s("value"), label: $0.s("label"),
                                                   accessibilityLabel: $0.optionalString("accessibilityLabel"))
            }
        } ?? []
        if options.contains(where: { $0.accessibilityLabel != nil }) { require("weekday-accessibility-labels") }
        if Set(options.map(\.value)).count != options.count { add(.invalidCombination, props.path("options")) }
        if kind == .weekdays || kind == .alarmKind,
           Set(options.map(\.value)) != Set(ServerUIBedroomControl.allowedOptions(kind)) {
            add(.invalidCombination, props.path("options"))
        }
        let question = try props.value["confirmation"].map { _ in
            let q = try props.field("confirmation")
            return try ServerUIBedroomControl.Question(title: q.s("title"), message: q.s("message"),
                confirmLabel: q.s("confirmLabel"), cancelLabel: q.s("cancelLabel"),
                messageFormat: q.value["messageFormat"].map { _ in try q.e("messageFormat") })
        }
        if let question, question.messageFormat != nil {
            require("wake-alarm-confirmation")
            let remaining = question.message.replacingOccurrences(of: "{time}", with: "")
                .replacingOccurrences(of: "{schedule}", with: "")
            if remaining.contains("{") || remaining.contains("}") {
                add(.invalidCombination, props.path("confirmation") + "/message")
            }
        }
        bedroomRefs.append((sourceId, question?.messageFormat == .wakeAlarm ? [.wakeDraft] : kind.providers,
                            props.path("sourceId")))
        if let question, question.confirmLabel == question.cancelLabel { add(.invalidCombination, props.path("confirmation")) }
        let scope = try props.value["scope"].map { _ in
            let s = try props.field("scope")
            return try ServerUIBedroomControl.Scope(title: s.s("title"), message: s.s("message"),
                tonightLabel: s.s("tonightLabel"), allNightsLabel: s.s("allNightsLabel"), cancelLabel: s.s("cancelLabel"))
        }
        if let scope, Set([scope.tonightLabel, scope.allNightsLabel, scope.cancelLabel]).count != 3 {
            add(.invalidCombination, props.path("scope"))
        }
        return try .init(node: node, sourceId: sourceId, kind: kind, label: props.s("label"),
            unavailableText: props.s("unavailableText"), activeLabel: props.optionalString("activeLabel"),
            inactiveLabel: props.optionalString("inactiveLabel"), countdownSuffix: props.optionalString("countdownSuffix"),
            parameter: props.optionalString("parameter"), options: options, confirmation: question, scope: scope,
            icon: props.value["icon"].map { _ in try symbol(props.field("icon")) },
            family: props.value["family"].map { _ in try props.e("family") },
            action: props.value["action"].map { _ in try navigationAction(props.field("action")) },
            showsExplanation: props.value["showsExplanation"]?.bool ?? false,
            episode: props.value["episode"].map { _ in
                let episode = try props.field("episode")
                return try .init(heading: episode.s("heading"), detail: episode.s("detail"), pendingLabel: episode.s("pendingLabel"))
            }, showsHeading: props.value["showsHeading"]?.bool ?? false)
    }

    private mutating func alarmAppearance(_ c: Cursor) throws -> D.AlarmAppearance {
        return try .init(icon: symbol(c.field("icon")),
                         fill: solidFill(c.field("fill")), text: c.s("text"))
    }

    private func solidFill(_ c: Cursor) throws -> D.TileFill {
        try .solidRGB(red: c.i("red"), green: c.i("green"), blue: c.i("blue"))
    }

    private mutating func uniqueStates(_ values: [Cursor]) {
        var seen: Set<String> = []
        for value in values {
            if case .string(let state)? = value.value["state"], !seen.insert(state).inserted {
                add(.invalidCombination, value.path("state"))
            }
        }
    }
    private mutating func statusAppearance(_ c: Cursor) throws -> D.StatusAppearance {
        var rules = ServerUIRuleDecoder()
        let icon = try rules.symbol(c.field("icon").value, at: c.path("icon"))
        let fill = try rules.fill(c.field("fill").value, at: c.path("fill"))
        let glyph = c.value["glyph"].flatMap { rules.fill($0, at: c.path("glyph")) }
        try absorb(rules)
        guard let icon, let fill, glyph != nil || c.value["glyph"] == nil else { throw Issue(.invalidValue, c.pointer) }
        return .init(icon: icon.0, fill: fill.0, glyph: glyph?.0, iconRule: icon.1, fillRule: fill.1, glyphRule: glyph?.1)
    }
    private mutating func optionalHomeAction(_ c: Cursor) throws -> D.Action? {
        guard c.value["action"] != nil else { return nil }
        let intent = try action(c.field("action"))
        check(intent, at: c.path("action")) { Self.navigates($0) }
        return intent
    }

    // MARK: - Media remote controls

    private mutating func remoteOptions(_ c: Cursor) throws -> [D.RemoteOption] {
        var seen: Set<String> = []
        return try c.array().map { item in
            let value = try item.s("value")
            if !seen.insert(value).inserted { add(.invalidCombination, item.path("value")) }
            return try .init(value: value, label: item.s("label"))
        }
    }

    private mutating func remoteKeys(_ c: Cursor, layout: D.RemoteKeysLayout?, volume: Bool = false) throws -> [D.RemoteKey] {
        var positions: Set<Int> = [], slots: Set<D.RemoteSlot> = []
        let keys = try c.array().map { item -> D.RemoteKey in
            let position = try item.i("position"), slot: D.RemoteSlot = try item.e("slot")
            if !positions.insert(position).inserted { add(.invalidCombination, item.path("position")) }
            if !slots.insert(slot).inserted { add(.invalidCombination, item.path("slot")) }
            let allowed: Set<D.RemoteSlot> = volume ? [.volumeDown, .volumeMute, .volumeUp]
                : layout == .transport ? [.pause, .play] : [.power, .up, .left, .select, .right, .down, .back, .home, .keyboard]
            if !allowed.contains(slot) { add(.invalidCombination, item.path("slot")) }
            if (volume || layout == .transport), position > 2 { add(.invalidCombination, item.path("position")) }
            if volume {
                let expected: [D.RemoteSlot: Int] = [.volumeMute: 0, .volumeDown: 1, .volumeUp: 2]
                if expected[slot] != position { add(.invalidCombination, item.path("position")) }
            }
            let icon = try item.field("icon")
            return try .init(position: position, slot: slot, label: item.s("label"),
                             icon: icon.s("type") == "none" ? nil : symbol(icon), rotation: item.n("rotation"),
                             activeText: item.s("activeText"), inactiveText: item.s("inactiveText"))
        }
        return keys
    }

    private mutating func remoteControl(_ c: Cursor) throws -> D.RemoteControl {
        switch try c.s("kind") {
        case "keys":
            let layout: D.RemoteKeysLayout = try c.e("layout")
            return try .keys(layout: layout, label: c.s("label"), keys: remoteKeys(c.field("keys"), layout: layout))
        case "volume":
            return try .volume(keys: remoteKeys(c.field("keys"), layout: nil, volume: true),
                               unavailableText: c.s("unavailableText"), errorText: c.s("errorText"))
        case "keyboard":
            return try .keyboard(.init(label: c.s("label"), placeholder: c.s("placeholder"),
                                       sendLabel: c.s("sendLabel"), cancelLabel: c.s("cancelLabel"), errorText: c.s("errorText")))
        case "app":
            return try .app(key: c.s("key"), icon: symbol(c.field("icon")), artwork: c.e("artwork"),
                            whiteBackground: c.b("whiteBackground"), activeText: c.s("activeText"))
        case "device":
            return try .device(key: c.s("key"), icon: symbol(c.field("icon")), states: remoteOptions(c.field("states")),
                               fallbackText: c.s("fallbackText"), unavailableText: c.s("unavailableText"))
        case "hue-toggle":
            return try .hueToggle(target: c.e("target"), icon: symbol(c.field("icon")),
                                  onText: c.s("onText"), offText: c.s("offText"), unavailableText: c.s("unavailableText"))
        case "hue-choice":
            let options = try remoteOptions(c.field("options"))
            if options.isEmpty { add(.invalidCombination, c.path("options")) }
            return try .hueChoice(target: c.e("target"), options: options, unavailableText: c.s("unavailableText"))
        case "hue-brightness": return try .hueBrightness(unavailableText: c.s("unavailableText"))
        case "hue-input":
            return try .hueInput(option: c.s("option"), icon: symbol(c.field("icon")), selectedText: c.s("selectedText"),
                                 connectedText: c.s("connectedText"), disconnectedText: c.s("disconnectedText"),
                                 unavailableText: c.s("unavailableText"))
        case "card":
            let intent = try action(c.field("action"))
            switch intent {
            case .push, .present, .selectTab, .dismissThenPush: break
            default: add(.invalidCombination, c.path("action") + "/type")
            }
            var slots: Set<String> = []
            let actions = try c.field("actions").array().map { a -> D.RemoteCardAction in
                let slot = try a.s("slot")
                if !slots.insert(slot).inserted { add(.invalidCombination, a.path("slot")) }
                return try .init(slot: a.e("slot"), label: a.s("label"), icon: symbol(a.field("icon")))
            }
            return try .card(key: c.s("key"), icon: symbol(c.field("icon")), states: remoteOptions(c.field("states")),
                             fallbackText: c.s("fallbackText"), unavailableText: c.s("unavailableText"),
                             errorText: c.s("errorText"), actions: actions,
                             showsVolume: c.b("showsVolume"), volumeLabel: c.s("volumeLabel"), action: intent)
        default: throw Issue(.unknownVariant, c.path("kind"))
        }
    }

    // MARK: - Manifest descriptors

    private mutating func asset(_ c: Cursor) throws -> D.Asset {
        require("assets.publisher")
        let id = try c.s("id"), sha = try c.s("sha256")
        register(id, catalog: "asset", at: c.path("id"))
        let source = try c.field("source")
        let path = try source.s("path")
        let mime: D.MIMEType = try c.e("mimeType")
        let ext = mime == .png ? "png" : "jpg"
        if path != "/api/assets/\(sha).\(ext)" { add(.invalidValue, source.path("path")) }
        let width = try c.i("pixelWidth"), height = try c.i("pixelHeight")
        if width * height > 16_000_000 { add(.limitExceeded, c.path("pixelWidth")) }
        return try .init(id: id, role: c.e("role"), source: .init(path: path), sha256: sha,
                         mimeType: mime, byteLength: c.i("byteLength"), pixelWidth: width, pixelHeight: height)
    }

    // MARK: - Whole-document semantics

    private mutating func validateReferences(_ document: D) {
        for (id, value, pointer) in localActions {
            if let field = localFields.first(where: { $0.id == id }) {
                if !field.accepts(value) { add(.bindingType, pointer + "/value") }
            } else { add(.invalidReference, pointer + "/stateId") }
        }
        for (id, pointer) in pageRefs where catalogs["page"]?[id] == nil { add(.invalidReference, pointer) }
        for (id, pointer) in modalRefs where catalogs["modal"]?[id] == nil { add(.invalidReference, pointer) }
        for (id, pointer) in tabRefs where catalogs["tab"]?[id] == nil { add(.invalidReference, pointer) }
        // Duplicate IDs are diagnosed before using the first definition as a lookup.
        let sources = Dictionary(document.dataSources.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for (control, pointer) in climateRefs {
            guard let source = sources[control.props.sourceId] else { add(.invalidReference, pointer + "/sourceId"); continue }
            guard case .climate(_, let configuration) = source else { add(.bindingType, pointer + "/sourceId"); continue }
            issues += ServerUIClimateValidation.control(control, source: configuration, at: pointer)
        }
        for (id, pointer, code) in powerRefs {
            guard let source = sources[id] else { add(.invalidReference, pointer); continue }
            if case .powerToggle = source {} else { add(code, pointer) }
        }
        for (id, pointer) in alarmRefs {
            guard let source = sources[id] else { add(.invalidReference, pointer); continue }
            if case .alarmMode = source {} else { add(.bindingType, pointer) }
        }
        for (id, model, pointer) in homeRefs {
            guard let source = sources[id] else { add(.invalidReference, pointer); continue }
            let matches: Bool = switch source {
            case .homeStatus: model == "home-status@1"
            case .homeWeather: model == "home-weather@1"
            case .homeLight: model == "home-light@1"
            default: false
            }
            if !matches { add(.bindingType, pointer) }
        }
        for (statusID, powerID, pointer) in homePowerRefs {
            guard case .homeStatus(_, let status) = sources[statusID],
                  case .homeLight(_, let target, let members) = sources[powerID] else { continue }
            if status.projection != .lights || status.format != .room
                || Set(status.entityIds) != Set(members.isEmpty ? [target] : members)
                || (status.rangeEntityId ?? status.entityIds.first) != target {
                add(.invalidCombination, pointer)
            }
        }
        for (id, kind, pointer) in doorRefs {
            guard let source = sources[id] else { add(.invalidReference, pointer); continue }
            if case .securityDoor(_, _, let sourceKind) = source, sourceKind == kind {} else { add(.bindingType, pointer) }
        }
        for (id, pointer) in visibilityRefs {
            guard let source = sources[id] else { add(.invalidReference, pointer); continue }
            switch source {
            case .haEntity, .homeStatus: break
            default: add(.bindingType, pointer)
            }
        }
        for (id, pointer, navigation) in roomRefs {
            guard let source = sources[id] else { add(.invalidReference, pointer); continue }
            switch source {
            case .roomNavigation where navigation: break
            case .haEntity where !navigation: break
            default: add(.bindingType, pointer)
            }
        }
        for (control, pointer) in deviceRefs {
            guard let source = sources[control.sourceId] else { add(.invalidReference, pointer + "/binding/sourceId"); continue }
            guard case .roomDevice(_, let descriptor) = source, descriptor.model == control.control.model else {
                add(.bindingType, pointer + "/binding/sourceId"); continue
            }
            if case .grill(let config) = descriptor,
               !config.details.contains(where: { $0.entityId == control.detailEntityId }) {
                add(.invalidReference, pointer + "/props/detailEntityId")
            }
        }
        for (id, pointer) in titleSourceRefs {
            guard let source = sources[id] else { add(.invalidReference, pointer); continue }
            if case .bedroom(_, _, let kind) = source, [.bedDraft, .wakeDraft].contains(kind) {} else {
                add(.bindingType, pointer)
            }
        }
        for (id, providers, pointer) in bedroomRefs {
            guard let source = sources[id] else { add(.invalidReference, pointer); continue }
            if case .bedroom(_, _, let providerKind) = source, providers.contains(providerKind) {} else {
                add(.bindingType, pointer)
            }
            for (control, path) in providerControlRefs {
                guard let source = sources[control.sourceId] else { add(.invalidReference, path + "/sourceId"); continue }
                guard case .deviceProvider(_, let descriptor) = source else { add(.bindingType, path + "/sourceId"); continue }
                switch (control.domain, descriptor) {
                case (.lights, .lights(let group)):
                    for (field, id) in [("entityId", control.entityId), ("copySourceId", control.copySourceId)] {
                        if let id, !group.lights.contains(where: { $0.entityId == id }) { add(.invalidReference, path + "/" + field) }
                    }
                    if control.kind == .copyColor, control.entityId == control.copySourceId { add(.invalidCombination, path + "/copySourceId") }
                case (.sprinkler, .sprinkler(let configuration)):
                    if let zone = control.zone, !configuration.controller.zones.indices.contains(zone) { add(.invalidReference, path + "/zone") }
                default: add(.bindingType, path + "/sourceId")
                }
            }
        }
        for (id, pointer) in remoteRefs {
            guard let source = sources[id] else { add(.invalidReference, pointer); continue }
            if case .mediaRemote = source {} else { add(.bindingType, pointer) }
        }
        for (control, pointer) in vacuumRefs {
            guard let source = sources[control.sourceId] else { add(.invalidReference, pointer + "/sourceId"); continue }
            guard case .vacuum(_, let descriptor) = source else { add(.bindingType, pointer + "/sourceId"); continue }
            let config = descriptor.configuration
            let valid: Bool
            switch control.primitive {
            case .choice(let id, let selection):
                valid = selection == .rooms ? config.zones.contains { $0.entityId == id }
                    : config.autoCleanDisabledRooms.contains { $0.entityId == id }
            case .consumable(let id): valid = config.consumables.contains { $0.entityId == id }
            case .areaEditor, .clearArea, .command(kind: .cleanArea, icon: _), .target(mode: .area, icon: _, destination: _):
                valid = config.areaCleaning != nil
            case .status(metric: .dock): valid = config.dockControls != nil
            case .autoClean: valid = descriptor.autoCleanControl != nil
            default: valid = true
            }
            if !valid { add(.invalidCombination, pointer + "/primitive") }
        }
        for (id, pointer) in profileRefs {
            guard let source = sources[id] else { add(.invalidReference, pointer); continue }
            if case .profileAccount = source {} else { add(.bindingType, pointer) }
        }
        for (control, pointer) in settingsRefs {
            guard let source = sources[control.sourceId] else { add(.invalidReference, pointer); continue }
            guard case .settingsProvider(_, let configuration) = source,
                  configuration.domain == control.kind.domain else { add(.bindingType, pointer); continue }
        }
        var cameraEntities: Set<String> = []
        for (index, source) in document.dataSources.enumerated() {
            if case .camera(_, let configuration) = source, !cameraEntities.insert(configuration.entityId).inserted {
                add(.invalidCombination, "/document/dataSources/\(index)/inputs/entityId")
            }
        }
        for (id, pointer, records) in cameraRefs {
            guard let source = sources[id] else { add(.invalidReference, pointer); continue }
            guard case .camera(_, let configuration) = source else { add(.bindingType, pointer); continue }
            if records, configuration.recording == .disabled { add(.invalidCombination, pointer) }
        }
        func videoSources(_ nodes: [D.Component]) -> Set<String> {
            nodes.reduce(into: Set<String>()) { result, node in
                switch node {
                case .cameraVideo(let video): result.insert(video.sourceId)
                case .cameraViewer(let viewer): result.insert(viewer.sourceId)
                default: break
                }
                result.formUnion(videoSources(node.childComponents))
            }
        }
        for (index, modal) in document.modals.enumerated() where !videoSources(modal.surface.components).isEmpty {
            let path = "/document/modals/\(index)/presentation"
            if modal.presentation.height != .full { add(.invalidCombination, path + "/height") }
            if modal.presentation.width != .page { add(.invalidCombination, path + "/width") }
            if modal.presentation.appearance != .dark { add(.invalidCombination, path + "/appearance") }
        }
        for (source, modalID, pointer) in cameraPresentations {
            if let modal = document.modals.first(where: { $0.id == modalID }),
               !videoSources(modal.surface.components).contains(source) { add(.invalidCombination, pointer) }
        }
        for ref in expressionRefs {
            let sourcePointer = ref.pointer + (ref.kind == nil ? "/sourceId" : "/from/sourceId")
            guard let source = sources[ref.sourceId] else { add(.invalidReference, sourcePointer); continue }
            guard case .haEntity = source else {
                // Any model that has read fields can be read by an operand or a condition, through the slot-read vocabulary.
                switch ServerUIModelReads.check(source, path: ref.path, kind: ref.kind) {
                case .notReadable?: add(.bindingType, sourcePointer)
                case .issue(let code, let suffix)?: add(code, ref.pointer + suffix)
                case .needs(let capability)?: require(capability)
                case nil: break
                }
                continue
            }
            if ref.path == ["state"] {
                if ref.kind == .boolean { add(.bindingType, ref.pointer + "/as") }
            } else if ref.path.count < 2 || ref.path.first != "attributes" {
                add(.invalidReference, ref.pointer + (ref.kind == nil ? "/path" : "/from/path"))
            }
        }
        for (id, pointer) in optimisticRefs {
            guard let source = sources[id] else { add(.invalidReference, pointer); continue }
            if case .haEntity = source {} else { add(.bindingType, pointer) }
        }
        for (read, pointer) in reads {
            guard let source = sources[read.sourceId] else { add(.invalidReference, pointer + "/from/sourceId"); continue }
            switch source {
            case .bedroom(_, _, let kind):
                if ![.bed, .wake].contains(kind) || ![["stateText"], ["phase"]].contains(read.path) {
                    add(.invalidReference, pointer + "/from/path")
                } else if read.kind != .string { add(.bindingType, pointer + "/as") }
            case .haEntity:
                if read.path == ["state"] {
                    if read.kind != .string { add(.bindingType, pointer + "/as") }
                } else if read.path.count < 2 || read.path.first != "attributes" {
                    add(.invalidReference, pointer + "/from/path")
                }
            case .powerToggle:
                let fields: [String: D.ScalarKind] = [
                    "stateText": .string, "isOn": .boolean, "phase": .string, "isError": .boolean
                ]
                if read.path.count != 1 || fields[read.path[0]] == nil {
                    add(.invalidReference, pointer + "/from/path")
                } else if fields[read.path[0]] != read.kind {
                    add(.bindingType, pointer + "/as")
                }
            case .climate(_, let configuration):
                let fields: [String: D.ScalarKind] = configuration.tracking == nil ? ["phase": .string] : [
                    "phase": .string, "selectedCount": .number, "criticalCount": .number, "occupiedOnlyCount": .number,
                    "totalRooms": .number, "selectedEnabled": .boolean, "criticalEnabled": .boolean
                ]
                if read.path.count != 1 || fields[read.path[0]] == nil { add(.invalidReference, pointer + "/from/path") }
                else if fields[read.path[0]] != read.kind { add(.bindingType, pointer + "/as") }
            case .roomNavigation, .deviceProvider:
                add(.invalidReference, pointer + "/from/path")
            case .roomDevice:
                if read.path.count != 1 || !["stateText", "phase"].contains(read.path[0]) {
                    add(.invalidReference, pointer + "/from/path")
                } else if read.kind != .string { add(.bindingType, pointer + "/as") }
            case .sprinklerState:
                let fields: [String: D.ScalarKind] = [
                    "status": .string, "mode": .string, "phase": .string,
                    "batteryPercent": .number, "batteryLow": .boolean, "fault": .boolean,
                    "hubConnected": .boolean, "watering": .boolean, "available": .boolean,
                    "rainDelay": .boolean, "smartWatering": .boolean
                ]
                if read.path.count != 1 || fields[read.path[0]] == nil {
                    add(.invalidReference, pointer + "/from/path")
                } else if fields[read.path[0]] != read.kind {
                    add(.bindingType, pointer + "/as")
                }
            case .inventoryList, .todoCollection:
                add(.invalidReference, pointer + "/from/path")
            case .alarmMode, .inventorySummary, .securityDoor, .todoCounts,
                 .vacuum, .householdAwayStatus, .camera:
                let fields: [String]
                switch source {
                case .alarmMode, .securityDoor: fields = ["phase"]
                case .vacuum: fields = ["stateText", "batteryText", "phase"]
                case .householdAwayStatus: fields = ["phase", "mode", "state"]
                default: fields = ["stateText", "phase"]
                }
                if read.path.count != 1 || !fields.contains(read.path[0]) {
                    add(.invalidReference, pointer + "/from/path")
                } else if read.kind != .string {
                    add(.bindingType, pointer + "/as")
                }
            case .homeStatus, .appState:
                switch ServerUIModelReads.check(source, path: read.path, kind: read.kind) {
                case .issue(let code, let suffix)?: add(code, pointer + suffix)
                case .needs(let capability)?: require(capability)
                default: break
                }
            case .homeWeather, .homeLight:
                add(.invalidReference, pointer + "/from/path")
            case .mediaRemote:
                // Domain projections are typed atoms, not a second generic state/command DSL.
                add(.invalidReference, pointer + "/from/path")
            case .profileAccount, .settingsProvider:
                add(.invalidReference, pointer + "/from/path")
            }
        }
        validateSourceCycles()
        var referencedAssets: Set<String> = []
        if case .downloaded(let id, _, _, _, _, _) = document.theme.background {
            referencedAssets.insert(id)
            if let asset = document.assets.first(where: { $0.id == id }) {
                if asset.role != .backdrop { add(.invalidCombination, "/document/theme/background/assetId") }
            } else { add(.invalidReference, "/document/theme/background/assetId") }
        }
        for (index, asset) in document.assets.enumerated() where !referencedAssets.contains(asset.id) {
            add(.invalidReference, "/document/assets/\(index)")
        }
    }
    private mutating func validateSourceCycles() {
        let edges = Dictionary(grouping: dependencies, by: { $0.0 })
        func reaches(_ start: String, _ destination: String) -> Bool {
            var pending = [start]
            var visited: Set<String> = []
            while let id = pending.popLast() {
                if id == destination { return true }
                if visited.insert(id).inserted { pending += (edges[id] ?? []).map(\.1) }
            }
            return false
        }
        // At most 100 descriptors, each with at most one dependency. Diagnose every cycle edge
        // so the reported pointer does not depend on DFS traversal or dictionary iteration.
        for (source, target, pointer) in dependencies where reaches(target, source) {
            add(.invalidCombination, pointer)
        }
    }

    /// Validate every authored chrome definition and each reachable shell/modal attachment.
    /// Inherited groups remain a single definition, not new IDs in every surface.
    private mutating func validateChromeContexts(_ document: D) {
        let pageMap = Dictionary(document.pages.map { ($0.id, $0.surface) }, uniquingKeysWith: { first, _ in first })
        let pageIndices = Dictionary(document.pages.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { first, _ in first })
        func effective(_ toolbar: D.Toolbar, inherited: [D.ChromeGroup]) -> [D.ChromeGroup] {
            if case .replace(let groups) = toolbar { return groups }
            return inherited
        }
        func actions(_ components: [D.Component]) -> [D.Action] {
            components.flatMap { component in
                var own = component.ownActions
                if case .roomNavigationGrid(let grid) = component,
                   case .roomNavigation(_, let configuration) = document.dataSources.first(where: { $0.id == grid.sourceId }) {
                    own += configuration.items.map(\.action)
                }
                return own + actions(component.childComponents)
            }
        }
        func chromeActions(_ groups: [D.ChromeGroup], root: Bool) -> [D.Action] {
            groups.flatMap(\.items).flatMap { item -> [D.Action] in
                switch item {
                case .button(let button) where root || button.visibility == .always: button.action.plainActions
                case .shellHeader(let header) where root || header.visibility == .always: [header.quickLinksAction, header.profileAction]
                default: []
                }
            }
        }
        func count(_ groups: [D.ChromeGroup], root: Bool, shell: Bool) -> Int {
            groups.flatMap(\.items).filter {
                switch $0 {
                case .shellMenu: root && shell
                case .button(let button): root || button.visibility == .always
                case .shellHeader(let header): root || header.visibility == .always
                }
            }.count
        }
        for (index, page) in document.pages.enumerated() {
            if case .replace(let groups) = page.surface.toolbar, count(groups, root: true, shell: true) > 12 {
                add(.limitExceeded, "/document/pages/\(index)/toolbar")
            }
        }
        let shellRoots = Set([document.navigation.initialPageId] + document.navigation.tabs.map(\.pageId))
        for id in shellRoots.sorted() {
            guard let surface = pageMap[id], let index = pageIndices[id] else { continue }
            let items = effective(surface.toolbar, inherited: document.navigation.chrome.groups).flatMap(\.items)
            if items.count > 12 { add(.limitExceeded, "/document/pages/\(index)/toolbar") }
            if items.filter({ if case .shellMenu = $0 { true } else { false } }).count != 1 {
                add(.invalidCombination, "/document/pages/\(index)/toolbar")
            }
        }
        var modalExits: [String: Set<String>] = [:]
        for (index, modal) in document.modals.enumerated() {
            let groups = effective(modal.surface.toolbar, inherited: [])
            if count(groups, root: true, shell: false) + 1 > 12 { add(.limitExceeded, "/document/modals/\(index)/toolbar") }
            var pending = actions(modal.surface.components) + chromeActions(groups, root: true)
            var seen: Set<String> = []
            while let intent = pending.popLast() {
                if case .dismissThenPush(let push) = intent {
                    modalExits[modal.id, default: []].insert(push.pageId)
                }
                guard case .push(let push) = intent, seen.insert(push.pageId).inserted,
                      let surface = pageMap[push.pageId], let pageIndex = pageIndices[push.pageId] else { continue }
                let pageGroups = effective(surface.toolbar, inherited: groups)
                let hostItems = modal.presentation.close.visibility == .allDepths ? 2 : 1
                if count(pageGroups, root: false, shell: false) + hostItems > 12 {
                    add(.limitExceeded, "/document/pages/\(pageIndex)/toolbar")
                }
                pending += actions(surface.components) + chromeActions(pageGroups, root: false)
            }
        }
        for root in shellRoots.sorted() {
            var pending = [root]
            var seen: Set<String> = []
            while let id = pending.popLast() {
                guard seen.insert(id).inserted, let surface = pageMap[id], let index = pageIndices[id] else { continue }
                let atRoot = id == root
                let groups = effective(surface.toolbar, inherited: document.navigation.chrome.groups)
                if count(groups, root: atRoot, shell: true) + (atRoot ? 0 : 1) > 12 {
                    add(.limitExceeded, "/document/pages/\(index)/toolbar")
                }
                for intent in actions(surface.components) + chromeActions(groups, root: atRoot) {
                    switch intent {
                    case .push(let push): pending.append(push.pageId)
                    case .present(let modalId, _, _): pending += (modalExits[modalId] ?? []).sorted()
                    default: break
                    }
                }
            }
        }
    }

    // MARK: - Diagnostics and publication metadata

    mutating func require(_ name: String) { requirements.insert("sh.\(name)@1") }
    mutating func add(_ code: Issue.Code, _ pointer: String) { issues.append(Issue(code, pointer)) }
    mutating func register(_ id: String, catalog: String, at pointer: String) {
        if let previous = catalogs[catalog]?[id] {
            add(.duplicateID, min(previous, pointer))
        } else { catalogs[catalog, default: [:]][id] = pointer }
    }
    private mutating func timestamp(_ value: String, at pointer: String) -> String? {
        guard ServerUICompositionShape.matches(value, "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?Z$"),
              !value.hasPrefix("0000") else { add(.invalidValue, pointer); return nil }
        let base = String(value.prefix(19)) + "Z"
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: base), formatter.string(from: date) == base else {
            add(.invalidValue, pointer); return nil
        }
        // Compare decimal fractions without Date's sub-millisecond precision loss.
        let fraction = value.dropFirst(19).dropLast().dropFirst()
        return String(value.prefix(19)) + String(fraction) + String(repeating: "0", count: 20 - fraction.count)
    }
}

// MARK: - Checked access after exhaustive shape validation

struct Cursor {
    let value: JSONValue
    let pointer: String
    init(_ value: JSONValue, _ pointer: String) { self.value = value; self.pointer = pointer }
    func path(_ key: String) -> String { ServerUICompositionJSON.pointer(pointer, key) }
    func field(_ key: String) throws -> Self {
        guard let value = value[key] else { throw ServerUICompositionError(.missingRequired, path(key)) }
        return Self(value, path(key))
    }
    func array() throws -> [Self] {
        guard case .array(let array) = value else { throw ServerUICompositionError(.invalidValue, pointer) }
        return array.enumerated().map { Self($0.element, path(String($0.offset))) }
    }
    func string() throws -> String {
        guard case .string(let value) = value else { throw ServerUICompositionError(.invalidValue, pointer) }
        return value
    }
    func enumeration<T: RawRepresentable>() throws -> T where T.RawValue == String {
        guard let value = T(rawValue: try string()) else { throw ServerUICompositionError(.unknownVariant, pointer) }
        return value
    }
    func s(_ key: String) throws -> String { try field(key).string() }
    func e<T: RawRepresentable>(_ key: String) throws -> T where T.RawValue == String { try field(key).enumeration() }
    func n(_ key: String) throws -> Double {
        let child = try field(key)
        guard case .number(let value) = child.value else { throw ServerUICompositionError(.invalidValue, child.pointer) }
        return value
    }
    func i(_ key: String) throws -> Int {
        let value = try n(key)
        guard let integer = Int(exactly: value) else { throw ServerUICompositionError(.invalidValue, path(key)) }
        return integer
    }
    func b(_ key: String) throws -> Bool {
        let child = try field(key)
        guard case .bool(let value) = child.value else { throw ServerUICompositionError(.invalidValue, child.pointer) }
        return value
    }
    func optionalString(_ key: String) throws -> String? {
        if value[key] == nil { return nil }
        return try s(key)
    }
}
