import Foundation
import Testing
@testable import HassCore

// MARK: - Typed shell contracts

@Suite struct ServerUIShellContractTests {
    private typealias P = ServerUICompositionPublication
    private typealias E = ServerUICompositionError

    private func fixture(_ name: String) throws -> JSONValue {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(name)
        return try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
    }

    private func publication(pinned: Bool = false, header: Bool = false, atoms: Bool = false, coordinated: Bool = false,
                             _ edit: (inout [String: JSONValue]) -> Void = { _ in }) throws -> P {
        guard case .object(var root) = try fixture("ServerUICompositionFixture.json"),
              case .object(var document)? = root["document"],
              case .array(var pages)? = document["pages"],
              case .object(var page) = pages[2],
              case .object(var shell) = try fixture("ServerUIShellFixture.json") else {
            throw E(.invalidValue, "")
        }
        if coordinated {
            let addition = try fixture("ServerUIPresentationFixture.json")
            shell["components"] = .array(try #require(shell["components"]?.array) + #require(addition["components"]?.array))
            shell["localState"] = .array(try #require(shell["localState"]?.array) + #require(addition["localState"]?.array))
            var modals = try #require(document["modals"]?.array)
            guard case .object(var modal) = modals[0], case .object(var presentation)? = modal["presentation"] else { throw E(.invalidValue, "") }
            presentation["fullScreen"] = .bool(true)
            modal["presentation"] = .object(presentation); modals[0] = .object(modal)
            document["modals"] = .array(modals)
        }
        edit(&shell)
        if pinned {
            guard case .array(let roots)? = shell["components"], case .object(var section) = roots[0],
                  case .array(let children)? = section["children"], case .object(var tabs) = children[5],
                  case .object(var props)? = tabs["props"], case .array(let panels)? = tabs["tabs"] else { throw E(.invalidValue, "") }
            props["pinned"] = .bool(true); props["resetOnPresentation"] = .bool(true)
            tabs["props"] = .object(props)
            tabs["tabs"] = .array(try panels.map { panel in
                guard case .object(var value) = panel else { throw E(.invalidValue, "") }
                value["icon"] = page["icon"]
                value["centerWhenFits"] = .bool(true)
                return .object(value)
            })
            section["children"] = .array(Array(children.prefix(5)) + Array(children.dropFirst(6)))
            shell["components"] = .array([.object(section), .object(tabs)])
        }
        document["localState"] = shell["localState"]
        if atoms, case .array(let original)? = shell["components"], case .array(let nodes) = try fixture("ServerUIShellAtomsFixture.json") {
            shell["components"] = .array(original + nodes)
        }
        page["components"] = shell["components"]
        pages[2] = .object(page)
        document["pages"] = .array(pages)
        if header {
            guard case .object(var navigation)? = document["navigation"], case .object(var chrome)? = navigation["chrome"],
                  case .array(var groups)? = chrome["groups"], case .object(var group) = groups[1],
                  case .array(let modals)? = document["modals"], let modalID = modals.first?["id"] else { throw E(.invalidValue, "") }
            let action = JSONValue.object(["type": .string("present"), "modalId": modalID, "arguments": .object([:]), "ifPresented": .string("reject")])
            group["items"] = .array([.object(["id": .string("native-header"), "type": .string("shell-header"),
                "visibility": .string("always"), "quickLinksAction": action, "profileAction": action])])
            groups[1] = .object(group); chrome["groups"] = .array(groups); navigation["chrome"] = .object(chrome)
            document["navigation"] = .object(navigation)
        }
        root["document"] = .object(document)
        root["capabilities"] = .array((P.firstSliceCapabilities + [
            "sh.section@1", "sh.rows@1", "sh.local-tabs@1", "sh.local-state@1",
            "sh.local-controls@1", "sh.primary-button@1", "sh.row-collection@1"
        ] + (pinned ? ["sh.pinned-tabs@1"] : []) + (header ? ["sh.shell-header@1"] : [])
          + (atoms ? ["sh.info-box@1", "sh.status-pill@1", "sh.paged-row@1"] : [])
          + (coordinated ? ["sh.presentation-providers@1", "sh.section-grid@1", "sh.pinned-form-actions@1",
                             "sh.pinned-actions@1", "sh.collection@1", "sh.full-screen-modal@1",
                             "sh.settings-link@1", "sh.module-settings-rows@1"] : [])).sorted().map(JSONValue.string))
        return try P.decode(JSONEncoder().encode(JSONValue.object(root)))
    }

    @Test func negotiatedShellForestIncludesHiddenPanelsAndTypedLocalFields() throws {
        let publication = try publication()
        #expect(publication.document.localState.count == 4)
        guard case .section(let section) = publication.document.pages[2].surface.components[0],
              case .localTabs(let tabs) = section.children[5] else { Issue.record("Expected shared shell tree"); return }
        #expect(tabs.tabs.map(\.id) == ["details", "options"])
        #expect(tabs.tabs[1].children[0].node.id == "shell-choice")
        #expect(section.children[4].ownActions == [.setLocal(stateId: "enabled", value: .boolean(true))])
        #expect(publication.document.pages[0].surface.components[0].childComponents.count == 2)
    }

    @Test func pinnedTabsKeepExplicitSymbolsAndPresentationResetInTheTypedPlan() throws {
        let plan = try publication(pinned: true)
        guard case .localTabs(let tabs) = plan.document.pages[2].surface.components[1] else { Issue.record("Expected tabs"); return }
        #expect(tabs.pinned && tabs.resetOnPresentation)
        #expect(tabs.tabs.allSatisfy { $0.icon != nil && $0.centerWhenFits })
    }

    @Test func shellHeaderKeepsBothAuthoredDestinations() throws {
        let plan = try publication(header: true)
        guard case .shellHeader(let header) = plan.document.navigation.chrome.groups[1].items[0] else { Issue.record("Expected header"); return }
        #expect(header.visibility == .always)
        #expect(header.quickLinksAction == header.profileAction)
    }

    @Test func pagingTraversesEveryStatusAndNoticeWithoutLosingTheirTypes() throws {
        let plan = try publication(atoms: true)
        let components = plan.document.pages[2].surface.components
        guard case .pagedRow(let row) = components.last else { Issue.record("Expected pager"); return }
        #expect(row.perPage == 2 && row.children.count == 2)
        #expect(components.last?.childComponents.count == 2)
        guard case .statusPill(let pill) = row.children[0] else { Issue.record("Expected status"); return }
        #expect(pill.tone == .ok)
    }

    @Test func rejectsInvalidInitialValuesAndClosedLocalStateShapes() throws {
        let invalid = JSONValue.object(["id": .string("enabled"), "type": .string("boolean"), "initial": .string("true")])
        #expect(throws: E(.invalidValue, "/document/localState/0/initial")) {
            try publication { $0["localState"] = .array([invalid]) }
        }

        let offStep = JSONValue.object(["id": .string("count"), "type": .string("number"), "initial": .number(3),
                                       "minimum": .number(0), "maximum": .number(10), "step": .number(2)])
        #expect(throws: E(.invalidValue, "/document/localState/0/initial")) {
            try publication { $0["localState"] = .array([offStep]) }
        }
    }

    @Test func pinsAnExistingPrimaryControlWithoutAddingACommandDispatcher() throws {
        let plan = try publication(coordinated: true) { shell in
            guard case .array(var nodes)? = shell["components"], case .object(var actions) = nodes[3],
                  case .object(var props)? = actions["props"], case .array(var items)? = props["items"],
                  let action = items[0]["action"] else { return }
            items.removeFirst()
            props["items"] = .array(items)
            actions["props"] = .object(props)
            actions["children"] = .array([.object([
                "id": .string("native-primary"), "title": .string("Submit"), "type": .string("primary-button"),
                "layout": .object(["span": .number(1)]), "props": .object([:]), "action": action
            ])])
            nodes[3] = .object(actions); shell["components"] = .array(nodes)
        }
        guard case .pinnedActions(let value) = plan.document.pages[2].surface.components[3] else {
            Issue.record("Expected pinned native control"); return
        }
        #expect(value.items.count == 1 && !value.items[0].prominent)
        #expect(value.children.count == 1 && value.children[0].ownActions.count == 1)
        #expect(plan.document.pages[2].surface.components[3].childComponents == value.children)
    }

    @Test func negotiatesScopedSectionsPinnedFormsAndFullScreenWithoutAddingDomainSyntax() throws {
        let plan = try publication(coordinated: true)
        let nodes = plan.document.pages[2].surface.components
        guard case .grid(let grid) = nodes[1], case .localTabs(let tabs) = nodes[2],
              case .pinnedActions(let actions) = nodes[3] else { Issue.record("Expected presentation primitives"); return }
        #expect(grid.minimum.rawValue == "section-wide@1" && grid.maxColumns == 2)
        #expect(tabs.scopeProviderId == "summary" && tabs.showsSelector)
        #expect(actions.style == .form && actions.items[0].stateProviderId == "save-state")
        #expect(plan.document.modals[0].presentation.fullScreen)
        #expect(throws: E.self) {
            try publication(coordinated: true) { shell in
                guard case .array(var nodes)? = shell["components"], case .object(var grid) = nodes[1],
                      case .object(var props)? = grid["props"] else { return }
                props["maxColumns"] = .number(3); grid["props"] = .object(props); nodes[1] = .object(grid)
                shell["components"] = .array(nodes)
            }
        }
        #expect(throws: E.self) {
            try publication(coordinated: true) { shell in
                guard case .array(var nodes)? = shell["components"], case .object(var actions) = nodes[3],
                      case .object(var props)? = actions["props"] else { return }
                props["style"] = .string("floating"); actions["props"] = .object(props); nodes[3] = .object(actions)
                shell["components"] = .array(nodes)
            }
        }
    }
}

@Suite struct ServerUIRecordsContractTests {
    private func object(_ value: JSONValue?) throws -> [String: JSONValue] {
        guard case .object(let result) = value else { throw ServerUICompositionError(.invalidValue, "") }
        return result
    }

    private func publication(columns: Bool = false, adaptive: Bool = false, components edit: (inout [JSONValue]) -> Void = { _ in }) throws -> ServerUICompositionPublication {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        var root = try object(JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: directory.appendingPathComponent("ServerUICompositionFixture.json"))))
        var document = try object(root["document"])
        var pages = try #require(document["pages"]?.array)
        var page = try object(pages[2])
        let fragment = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: directory.appendingPathComponent("ServerUIRecordsFixture.json")))
        var components = try #require(fragment["components"]?.array)
        edit(&components)
        if columns {
            page["navigation"] = .object(["type": .string("navigation-columns"), "placeholder": .string("Select an Item"), "standalone": .bool(false)])
        }
        page["components"] = .array(components); pages[2] = .object(page)
        if adaptive {
            var modals = try #require(document["modals"]?.array)
            var modal = try object(modals[0]), presentation = try object(modal["presentation"])
            presentation["adaptive"] = .bool(true)
            modal["presentation"] = .object(presentation); modals[0] = .object(modal)
            document["modals"] = .array(modals)
        }
        document["pages"] = .array(pages); root["document"] = .object(document)
        root["capabilities"] = .array((ServerUICompositionPublication.firstSliceCapabilities + [
            "sh.collection@1", "sh.form@1", "sh.recipe-part@1", "sh.pinned-actions@1",
        ] + (columns ? ["sh.navigation-columns@1"] : []) + (adaptive ? ["sh.adaptive-presentation@1"] : [])).sorted().map(JSONValue.string))
        return try ServerUICompositionPublication.decode(JSONEncoder().encode(JSONValue.object(root)))
    }

    @Test func compilesClosedCollectionFormRecipeAndPinnedBarTogether() throws {
        let plan = try publication()
        let nodes = plan.document.pages[2].surface.components
        #expect(nodes.count == 4)
        guard case .form(let form) = nodes[1], case .collection(let collection) = nodes[0] else {
            Issue.record("Expected shared record primitives"); return
        }
        #expect(form.fields.map(\.control) == [.text, .toggle])
        #expect(collection.template == .rows)
        #expect(nodes[1].ownActions == [.back])
    }

    @Test func rejectsUnknownFieldsAndDuplicateFormKeys() throws {
        #expect(throws: ServerUICompositionError.self) {
            try publication { nodes in
                guard case .object(var form) = nodes[1], case .object(var props)? = form["props"] else { return }
                props["controller"] = .string("forbidden-dispatch"); form["props"] = .object(props); nodes[1] = .object(form)
            }
        }
        #expect(throws: ServerUICompositionError.self) {
            try publication { nodes in
                guard case .object(var form) = nodes[1], case .object(var props)? = form["props"],
                      case .array(var fields)? = props["fields"] else { return }
                fields.append(fields[0]); props["fields"] = .array(fields); form["props"] = .object(props); nodes[1] = .object(form)
            }
        }
    }

    @Test func negotiatesColumnRoutesAndAdaptivePresentationsExplicitly() throws {
        let plan = try publication(columns: true, adaptive: true)
        #expect(plan.document.pages[2].navigation == .columns)
        #expect(plan.document.pages[2].columnPlaceholder == "Select an Item")
        #expect(!plan.document.pages[2].standaloneColumns)
        #expect(plan.document.modals[0].presentation.adaptive)
    }
}

// MARK: - Scene value, draft and collection lifetimes

@Suite @MainActor struct ServerUIShellStateTests {
    private typealias D = ServerUICompositionDocument
    private let count = D.LocalField(id: "count", initial: .number(2), rule: .number(minimum: 0, maximum: 10, step: 2))
    private let name = D.LocalField(id: "name", initial: .string("Old"), rule: .string(maxLength: 10))

    @Test func automaticRouteRetainsEngagedPanelButNotAcrossANewPresentation() throws {
        let allowed = ["chooser", "vacation", "solo"]
        var state = ServerUIAutomaticSelection()
        #expect(try state.resolve("vacation", initial: "chooser", allowed: allowed, retainsEngaged: true) == "vacation")
        state.departed(initial: "chooser", retainsEngaged: true)
        #expect(try state.resolve("chooser", initial: "chooser", allowed: allowed, retainsEngaged: true) == "vacation")
        #expect(try state.resolve("solo", initial: "chooser", allowed: allowed, retainsEngaged: true) == "solo")
        #expect(throws: ServerUIRecordFailure.invalidValue) {
            try state.resolve("unknown", initial: "chooser", allowed: allowed, retainsEngaged: true)
        }
        #expect(state.displayed == "solo")
        var fresh = ServerUIAutomaticSelection()
        #expect(try fresh.resolve("chooser", initial: "chooser", allowed: allowed, retainsEngaged: true) == "chooser")
        fresh.departed(initial: "chooser", retainsEngaged: true)
        #expect(try fresh.resolve("vacation", initial: "chooser", allowed: allowed, retainsEngaged: true) == "chooser")
        #expect(try fresh.resolve("vacation", initial: "chooser", allowed: allowed, retainsEngaged: false) == "vacation")
    }

    @Test func preservesLocalEditsAndRejectsRemovalOrIncompatibleNarrowingAtomically() throws {
        let state = try ServerUILocalState(fields: [count, name])
        try state.set(.number(8), for: "count")
        #expect(throws: ServerUILocalState.Failure.invalidValue) { try state.set(.number(3), for: "count") }
        #expect(throws: ServerUILocalState.Failure.invalidValue) { try state.set(.boolean(true), for: "count") }
        #expect(throws: ServerUILocalState.Failure.interactionBlocked) { try state.apply([name]) }
        let narrower = D.LocalField(id: "count", initial: .number(0), rule: .number(minimum: 0, maximum: 4, step: 2))
        #expect(throws: ServerUILocalState.Failure.interactionBlocked) { try state.apply([narrower, name]) }
        #expect(state.values["count"] == .number(8))
        let next = D.LocalField(id: "new", initial: .boolean(true), rule: .boolean)
        try state.apply([count, name, next])
        #expect(state.values["count"] == .number(8))
        #expect(state.values["new"] == .boolean(true))
    }

    @Test func savePinsIdentityAndValuesBlocksMutationsAndRetainsFailureForRetry() throws {
        let draft = try ServerUIDraft(identity: .init(ownerId: "schedule", recordId: "sample-record"), fields: [name])
        try draft.set(.string("Edited"), for: "name")
        let ticket = try draft.beginSave()
        #expect(ticket.identity.recordId == "sample-record")
        #expect(ticket.values["name"] == .string("Edited"))
        #expect(throws: ServerUILocalState.Failure.interactionBlocked) { try draft.set(.string("Lost"), for: "name") }
        #expect(throws: ServerUILocalState.Failure.interactionBlocked) { try draft.discard() }
        try draft.complete(ticket, failure: "Save failed")
        #expect(draft.hasChanges && draft.blocksExit)
        #expect(draft.failure == "Save failed")
        let retry = try draft.beginSave()
        #expect(throws: ServerUILocalState.Failure.staleCommand) { try draft.complete(ticket) }
        #expect(draft.pending == retry)
        try draft.complete(retry)
        #expect(!draft.hasChanges && !draft.blocksExit)
        try draft.set(.string("Later"), for: "name")
        try draft.discard()
        #expect(draft.values["name"] == .string("Edited"))
    }

    @Test func collectionRetainsLastGoodRowsAndRejectsDuplicateKeysWithoutMutation() throws {
        let collection = ServerUIRowCollection()
        let first = ServerUIRowItem(id: "first", title: "First", value: "Ready")
        try collection.apply([first], phase: .ready)
        for phase in [ServerUIRowCollection.Phase.loading, .stale, .failed, .unavailable] {
            try collection.apply(nil, phase: phase)
            #expect(collection.rows == [first])
        }
        #expect(throws: ServerUIRowCollection.Failure.invalidRows) { try collection.apply([first, first], phase: .ready) }
        #expect(collection.rows == [first] && collection.phase == .unavailable)
        #expect(throws: ServerUIRowCollection.Failure.invalidRows) { try collection.apply(nil, phase: .ready) }
        try collection.apply([], phase: .ready)
        #expect(collection.rows.isEmpty && collection.phase == .ready)
    }
}
