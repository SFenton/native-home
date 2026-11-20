import Foundation
import Testing
@testable import HassCore

@MainActor
@Suite struct ServerUINavigationStateTests {
    // MARK: - Configured navigation

    @Test func arbitraryTabsKeepIndependentPaths() throws {
        let state = try ServerUINavigationState(catalog: document())
        #expect(state.snapshot.selection == .tab("tab-b"))
        try state.push(pageID: "detail")
        try state.selectTab("tab-a")
        try state.push(pageID: "leaf")
        try state.selectTab("tab-b")
        #expect(state.snapshot.stacks[.tab("tab-b")] == ["beta", "detail"])
        #expect(state.snapshot.stacks[.tab("tab-a")] == ["alpha", "leaf"])

        try state.trimVisiblePath(toDepth: 0)
        #expect(state.snapshot.stacks[.tab("tab-b")] == ["beta"])
        #expect(state.snapshot.stacks[.tab("tab-a")] == ["alpha", "leaf"])
    }

    @Test func initialPageDoesNotRequireATab() throws {
        let state = try ServerUINavigationState(catalog: document(initial: "detail", tabs: []))
        #expect(state.snapshot.selection == .initial)
        #expect(state.snapshot.tabs.isEmpty)
        #expect(state.snapshot.stacks[.initial] == ["detail"])
        try state.push(pageID: "leaf")
        try state.trimVisiblePath(toDepth: 0)
        #expect(state.snapshot.stacks[.initial] == ["detail"])
    }

    @Test func compositionUsesExplicitInitialTabEvenWhenTwoTabsShareARoot() throws {
        let state = try ServerUINavigationState(catalog: compositionCatalog(initialTab: "tab-beta", sharedRoot: true))
        #expect(state.snapshot.selection == .tab("tab-beta"))
        try state.push(pageID: "page-echo", fromDepth: 0)
        #expect(state.snapshot.stacks[.tab("tab-alpha")] == ["page-orbit"])
        #expect(state.snapshot.stacks[.tab("tab-beta")] == ["page-orbit", "page-echo"])

        let initial = try ServerUINavigationState(catalog: compositionCatalog(initialTab: nil))
        #expect(initial.snapshot.selection == .initial)
        #expect(initial.snapshot.stacks[.initial] == ["page-orbit"])
    }

    // MARK: - Push on another tab

    @Test func pushOnATabSelectsItAndAppendsOnTopOfItsStack() throws {
        let state = try ServerUINavigationState(catalog: document())
        try state.selectTab("tab-a")
        try state.push(pageID: "leaf")
        try state.selectTab("tab-b")
        try state.push(pageID: "detail")
        try state.selectTab("tab-a")
        try state.push(pageID: "detail", onTab: "tab-b")
        #expect(state.snapshot.selection == .tab("tab-b"))
        #expect(state.snapshot.stacks[.tab("tab-b")] == ["beta", "detail"], "not trimmed to its root")
        try state.push(pageID: "leaf", onTab: "tab-b")
        #expect(state.snapshot.stacks[.tab("tab-b")] == ["beta", "detail", "leaf"])
        #expect(state.snapshot.stacks[.tab("tab-a")] == ["alpha", "leaf"], "other stacks are untouched")
    }

    @Test func pushOnATabReusesAnAncestorAndDoesNothingWhenAlreadyOnTop() throws {
        let state = try ServerUINavigationState(catalog: document())
        try state.push(pageID: "detail")
        try state.push(pageID: "leaf")
        try state.selectTab("tab-a")
        try state.push(pageID: "detail", onTab: "tab-b")
        #expect(state.snapshot.selection == .tab("tab-b"))
        #expect(state.snapshot.stacks[.tab("tab-b")] == ["beta", "detail"], "popped to the page, not pushed again")
        let before = state.snapshot
        try state.push(pageID: "detail", onTab: "tab-b")
        #expect(state.snapshot == before)
    }

    @Test func pushOnATabRefusesWithoutChangingTheState() throws {
        let state = try ServerUINavigationState(catalog: document())
        let before = state.snapshot
        #expect(throws: ServerUINavigationState.Failure.unknownTab) { try state.push(pageID: "detail", onTab: "missing") }
        #expect(throws: ServerUINavigationState.Failure.unknownPage) { try state.push(pageID: "missing", onTab: "tab-a") }
        #expect(state.snapshot == before)
        try state.present(modalID: "panel-a")
        let open = state.snapshot
        #expect(throws: ServerUINavigationState.Failure.interactionBlocked) { try state.push(pageID: "detail", onTab: "tab-a") }
        #expect(state.snapshot == open)
    }

    @Test func compositionRejectsAnotherPresentationOrTabSwitchUntilDismissal() throws {
        let state = try ServerUINavigationState(catalog: compositionCatalog())
        let instance = try state.present(modalID: "modal-swatch")
        let before = state.snapshot
        #expect(throws: ServerUINavigationState.Failure.interactionBlocked) { try state.selectTab("tab-beta") }
        #expect(throws: ServerUINavigationState.Failure.interactionBlocked) { try state.present(modalID: "modal-swatch") }
        #expect(state.snapshot == before)
        try state.push(pageID: "page-echo", fromDepth: 0)
        try state.push(pageID: "page-lattice", fromDepth: 1)
        try state.push(pageID: "page-echo", fromDepth: 2)
        #expect(state.snapshot.presentations.first?.pages == ["page-echo"])
        try state.dismiss(presentationID: instance)
        try state.selectTab("tab-beta")
        #expect(state.snapshot.selection == .tab("tab-beta"))
    }

    @Test func senderPushTrimsAndReusesWithoutAnIntermediateInvalidState() throws {
        let state = try ServerUINavigationState(catalog: document())
        try state.push(pageID: "detail")
        try state.push(pageID: "leaf")
        let before = state.snapshot
        #expect(throws: ServerUINavigationState.Failure.unknownPage) { try state.push(pageID: "missing", fromDepth: 0) }
        #expect(throws: ServerUINavigationState.Failure.invalidDepth) { try state.push(pageID: "alpha", fromDepth: 3) }
        #expect(state.snapshot == before)
        try state.push(pageID: "alpha", fromDepth: 1)
        #expect(state.snapshot.stacks[.tab("tab-b")] == ["beta", "detail", "alpha"])
        try state.push(pageID: "detail", fromDepth: 2)
        #expect(state.snapshot.stacks[.tab("tab-b")] == ["beta", "detail"])
        try state.push(pageID: "beta", fromDepth: 1)
        #expect(state.snapshot.stacks[.tab("tab-b")] == ["beta"])
    }

    @Test func adaptiveDetailCanKeepItsPathUnderOnePreferenceSheet() throws {
        let state = try ServerUINavigationState(catalog: compositionCatalog())
        let detail = try state.present(modalID: "modal-swatch", asColumn: true)
        try state.push(pageID: "page-echo", fromDepth: 0)
        let sheet = try state.present(modalID: "modal-swatch")
        #expect(throws: ServerUINavigationState.Failure.interactionBlocked) { try state.present(modalID: "modal-swatch") }
        #expect(throws: ServerUINavigationState.Failure.interactionBlocked) { try state.present(modalID: "modal-swatch", asColumn: true) }
        let snapshot = state.snapshot
        try state.apply(catalog: compositionCatalog())
        #expect(state.snapshot == snapshot)
        try state.dismiss(presentationID: sheet)
        #expect(state.snapshot.presentations.map(\.id) == [detail])
        #expect(state.snapshot.presentations[0].pages == ["page-echo"])
        try state.trimVisiblePath(toDepth: 0, onRoot: true)
        #expect(state.snapshot.presentations[0].pages == ["page-echo"])
        try state.dismiss(presentationID: detail)
        try state.selectTab("tab-beta")
    }

    @Test func rootPushAndTrimRebaseAColumnSoAnotherPublicationKeepsIt() throws {
        let state = try ServerUINavigationState(catalog: compositionCatalog())
        let detail = try state.present(modalID: "modal-swatch", asColumn: true)
        try state.push(pageID: "page-echo", fromDepth: 0, onRoot: true)
        #expect(state.snapshot.stacks[.tab("tab-alpha")] == ["page-orbit", "page-echo"])
        try state.apply(catalog: compositionCatalog())
        #expect(state.snapshot.presentations.map(\.id) == [detail])

        try state.trimVisiblePath(toDepth: 0, onRoot: true)
        #expect(state.snapshot.stacks[.tab("tab-alpha")] == ["page-orbit"])
        try state.apply(catalog: compositionCatalog())
        #expect(state.snapshot.presentations.map(\.id) == [detail])

        // A sheet over the column still reconciles through the rebased presenter.
        let sheet = try state.present(modalID: "modal-swatch")
        try state.apply(catalog: compositionCatalog())
        #expect(state.snapshot.presentations.map(\.id) == [detail, sheet])
    }

    @Test func pathLimitFailsBeforeMutatingTheCurrentScene() throws {
        let state = try ServerUINavigationState(catalog: document())
        for _ in 0..<32 { try state.push(pageID: "detail") }
        let before = state.snapshot
        #expect(throws: ServerUINavigationState.Failure.limitExceeded) { try state.push(pageID: "leaf") }
        #expect(throws: ServerUINavigationState.Failure.limitExceeded) { try state.push(pageID: "leaf", fromDepth: 32) }
        #expect(state.snapshot == before)
        try state.push(pageID: "alpha", fromDepth: 0)
        #expect(state.snapshot.stacks[.tab("tab-b")] == ["beta", "alpha"])
    }

    @Test func nestedPresentationsHaveIndependentInstancesAndPaths() throws {
        let state = try ServerUINavigationState(catalog: document())
        try state.push(pageID: "detail")
        let first = try state.present(modalID: "panel-a", asColumn: true)
        try state.push(pageID: "leaf")
        let second = try state.present(modalID: "panel-b")
        try state.push(pageID: "alpha")
        try state.trimVisiblePath(toDepth: 0)
        #expect(state.snapshot.presentations.map(\.pages) == [["leaf"], []])
        #expect(state.snapshot.stacks[.tab("tab-b")] == ["beta", "detail"])
        try state.dismiss(presentationID: first)
        #expect(state.snapshot.presentations.isEmpty)
        #expect(throws: ServerUINavigationState.Failure.unknownPresentation) {
            try state.dismiss(presentationID: second)
        }
        #expect(try state.present(modalID: "panel-a") != first)
    }

    // MARK: - Last-good navigation

    @Test func metadataAndTabReorderingPreserveNavigation() throws {
        let state = try ServerUINavigationState(catalog: document())
        try state.push(pageID: "detail")
        let instance = try state.present(modalID: "panel-a")
        try state.push(pageID: "leaf")
        let paths = state.snapshot.stacks
        let presentations = state.snapshot.presentations
        try state.apply(catalog: document(tabs: [("tab-b", "beta"), ("tab-a", "alpha")], label: "Renamed"))
        #expect(state.snapshot.selection == .tab("tab-b"))
        #expect(state.snapshot.tabs.map(\.id) == ["tab-b", "tab-a"])
        #expect(state.snapshot.tabs[0].label == "Renamed")
        #expect(state.snapshot.stacks == paths)
        #expect(state.snapshot.presentations == presentations)
        #expect(state.snapshot.presentations[0].id == instance)
    }

    @Test func removedAncestorsTruncateInsteadOfReparentingChildren() throws {
        let state = try ServerUINavigationState(catalog: document())
        try state.push(pageID: "detail")
        try state.push(pageID: "leaf")
        let first = try state.present(modalID: "panel-a", asColumn: true)
        try state.push(pageID: "detail")
        try state.push(pageID: "leaf")
        try state.present(modalID: "panel-b")
        try state.apply(catalog: document(pages: ["alpha", "beta", "leaf"], modals: ["panel-a"]))
        #expect(state.snapshot.stacks[.tab("tab-b")] == ["beta"])
        #expect(state.snapshot.presentations.isEmpty)
        #expect(throws: ServerUINavigationState.Failure.unknownPresentation) {
            try state.dismiss(presentationID: first)
        }
    }

    @Test func removingAModalParentClosesOnlyItsDescendants() throws {
        let state = try ServerUINavigationState(catalog: document())
        let first = try state.present(modalID: "panel-a", asColumn: true)
        try state.push(pageID: "detail")
        try state.present(modalID: "panel-b")
        try state.apply(catalog: document(pages: ["alpha", "beta", "leaf"]))
        #expect(state.snapshot.presentations.map(\.id) == [first])
        #expect(state.snapshot.presentations[0].pages.isEmpty)

        try state.apply(catalog: document(initial: "alpha", tabs: [("tab-a", "alpha")]))
        #expect(state.snapshot.presentations.isEmpty)
        #expect(state.snapshot.selection == .tab("tab-a"))
    }

    @Test func changedRootAndRemovedTabReconcileOnlyAffectedStacks() throws {
        let state = try ServerUINavigationState(catalog: document())
        try state.push(pageID: "detail")
        try state.selectTab("tab-a")
        try state.push(pageID: "leaf")
        try state.apply(catalog: document(tabs: [("tab-a", "detail"), ("tab-b", "beta")]))
        #expect(state.snapshot.stacks[.tab("tab-a")] == ["detail"])
        #expect(state.snapshot.stacks[.tab("tab-b")] == ["beta", "detail"])
        try state.apply(catalog: document(tabs: [("tab-b", "beta")]))
        #expect(state.snapshot.selection == .tab("tab-b"))
        #expect(state.snapshot.stacks[.tab("tab-b")] == ["beta", "detail"])
        #expect(state.snapshot.stacks[.tab("tab-a")] == nil)
    }

    @Test func failedIntentsAndDifferentDocumentLeaveStateUntouched() throws {
        let state = try ServerUINavigationState(catalog: document())
        let before = state.snapshot
        #expect(throws: ServerUINavigationState.Failure.unknownPage) { try state.push(pageID: "missing") }
        #expect(throws: ServerUINavigationState.Failure.unknownTab) { try state.selectTab("missing") }
        #expect(throws: ServerUINavigationState.Failure.unknownModal) { try state.present(modalID: "missing") }
        #expect(throws: ServerUINavigationState.Failure.invalidDepth) { try state.trimVisiblePath(toDepth: -1) }
        #expect(throws: ServerUINavigationState.Failure.invalidDepth) { try state.trimVisiblePath(toDepth: 1) }
        #expect(throws: ServerUINavigationState.Failure.differentDocument) {
            try state.apply(catalog: document(id: "another-document"))
        }
        #expect(state.snapshot == before)
    }

    // MARK: - Wire fixture

    private func compositionCatalog(initialTab: String? = "tab-alpha", sharedRoot: Bool = false) throws -> ServerUINavigationCatalog {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("ServerUICompositionFixture.json")
        var root = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        var document = try #require(root["document"] as? [String: Any])
        var navigation = try #require(document["navigation"] as? [String: Any])
        navigation["initialTabId"] = initialTab.map { $0 as Any } ?? NSNull()
        if sharedRoot {
            var tabs = try #require(navigation["tabs"] as? [[String: Any]])
            tabs[1]["pageId"] = "page-orbit"
            navigation["tabs"] = tabs
        }
        document["navigation"] = navigation
        root["document"] = document
        let publication = try ServerUICompositionPublication.decode(JSONSerialization.data(withJSONObject: root))
        return ServerUINavigationCatalog(composition: publication.document)
    }

    /// A catalog over synthetic destinations. The initial tab is the first one rooted at the initial page.
    private func document(id: String = "navigation-test", initial: String = "beta",
                          pages: [String] = ["alpha", "beta", "detail", "leaf"],
                          tabs: [(String, String)] = [("tab-a", "alpha"), ("tab-b", "beta")],
                          modals: [String] = ["panel-a", "panel-b"], label: String = "Tab") -> ServerUINavigationCatalog {
        ServerUINavigationCatalog(
            documentID: id, initialPageID: initial, initialTabID: tabs.first { $0.1 == initial }?.0,
            tabs: tabs.map { .init(id: $0.0, label: label, icon: "circle", pageId: $0.1) },
            pageIDs: pages, modalIDs: modals)
    }
}
