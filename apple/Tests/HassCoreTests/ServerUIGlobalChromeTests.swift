import Foundation
@testable import HassCore
import Testing

// MARK: - The global-chrome contract

/// Sheet levels, a page's chrome hides, its wide-window open and the tab bar's visibility
/// (`sh.sheet-levels@1`, `sh.page-chrome-hide@1`, `sh.page-wide-open@1`, `sh.tabs-visibility@1`).
///
/// The app's own corpus (`GlobalChromeCorpus/`, kept apart from the byte-for-byte Studio copy) pins the first issue of every refusal; these tests pin
/// what the decoder made of an accepted document and that the four ids are understood by the compiler without being published.
@Suite(.timeLimit(.minutes(1)))
struct ServerUIGlobalChromeTests {
    /// The cases the app owns (`GlobalChromeCorpus/`): the Studio does not carry these four ids yet, so they live beside the shared corpus, not in it.
    private static let corpus = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("GlobalChromeCorpus", isDirectory: true)

    private static func file(_ name: String) -> URL {
        corpus.appendingPathComponent(name.contains("/") ? name : "reject/pending-\(name).json")
    }

    /// Decodes with the compiler's global-chrome rules on, the way a lane suite does before the ids are published.
    private static func decode(_ text: String) throws -> ServerUICompositionPublication {
        try ServerUIGlobalChrome.$understood.withValue(true) { try ServerUICompositionPublication.decode(Data(text.utf8)) }
    }

    private static func publication(_ name: String) throws -> ServerUICompositionPublication {
        try decode(String(contentsOf: file(name), encoding: .utf8))
    }

    /// The error a fixture's bytes raise, after `edit` changed the text.
    private static func refusal(_ name: String, edit: (String) -> String = { $0 }) throws -> ServerUICompositionError? {
        let text = try String(contentsOf: file(name), encoding: .utf8)
        do { _ = try decode(edit(text)); return nil } catch { return error as? ServerUICompositionError }
    }

    struct Held: Decodable, Sendable, CustomTestStringConvertible {
        struct Issue: Decodable, Equatable, Sendable { let code: String; let pointer: String }
        let file: String
        let pending: Bool?
        let studioIssue: Issue?
        var testDescription: String { file }
    }

    nonisolated static let held: [Held] = {
        struct Index: Decodable { let cases: [Held] }
        guard let data = try? Data(contentsOf: corpus.appendingPathComponent("index.json")),
              let index = try? JSONDecoder().decode(Index.self, from: data) else { return [] }
        return index.cases.filter { $0.file.hasPrefix("reject/pending-global-chrome-") }
    }()

    // MARK: Corpus

    /// The corpus holds each global-chrome case as a pending reject (a shipped build refuses it); here the rules run and must give the Studio's answer.
    @Test(arguments: held)
    func eachCaseGivesTheRecordedAnswerWithTheRulesOn(_ item: Held) throws {
        let text = try String(contentsOf: Self.file(item.file), encoding: .utf8)
        do {
            _ = try Self.decode(text)
            #expect(item.studioIssue == nil, "\(item.file) must be refused")
        } catch {
            let thrown = try #require(error as? ServerUICompositionError, "\(item.file) threw \(error)")
            #expect(item.studioIssue == .init(code: thrown.code.rawValue, pointer: thrown.pointer), "\(item.file) threw \(thrown)")
        }
    }

    @Test func theCorpusHoldsEveryCaseAsPending() {
        #expect(Self.held.count > 30 && Self.held.allSatisfy { $0.pending == true })
    }

    // MARK: Production

    @Test(arguments: ServerUIGlobalChrome.all)
    func aShippedBuildRefusesAPublicationThatUsesTheId(_ id: String) throws {
        let text = try String(contentsOf: Self.file("global-chrome-all"), encoding: .utf8)
        // Keep only `id` among the four, so the refusal names it whatever the document uses.
        var lines = text
        for other in ServerUIGlobalChrome.all where other != id { lines = lines.replacingOccurrences(of: "\"\(other)\",", with: "").replacingOccurrences(of: ",\n    \"\(other)\"", with: "") }
        do {
            _ = try ServerUICompositionPublication.decode(Data(lines.utf8))
            Issue.record("\(id) must be refused")
        } catch {
            let thrown = try #require(error as? ServerUICompositionError)
            #expect(thrown.code == .unsupportedCapability && thrown.capability == id)
        }
    }

    @Test func aDocumentThatUsesAFieldMustDeclareItsId() throws {
        let text = try String(contentsOf: Self.file("global-chrome-all"), encoding: .utf8)
        for id in ServerUIGlobalChrome.all {
            let without = text.replacingOccurrences(of: "\"\(id)\",", with: "").replacingOccurrences(of: ",\n    \"\(id)\"", with: "")
            do {
                _ = try Self.decode(without)
                Issue.record("\(id) must be declared")
            } catch {
                #expect((error as? ServerUICompositionError)?.code == .capabilityManifestMismatch, "\(id)")
            }
        }
    }

    // MARK: Levels

    @Test func levelsDecodeAsSurfacesApartFromPagesAndModals() throws {
        let document = try Self.publication("global-chrome-levels-two-levels").document
        #expect(document.levels.map(\.id) == ["level-one", "level-two"])
        #expect(document.pages.map(\.id) == ["page-orbit", "page-lattice", "page-echo"])
        #expect(document.modals.map(\.id) == ["modal-swatch"])
        #expect(document.levels[0].surface.title == "Level One")
    }

    @Test func aDocumentWithoutLevelsHasNone() throws {
        #expect(try Self.decode(String(contentsOf: Self.file("accept/badge-chrome-button.json"), encoding: .utf8)).document.levels.isEmpty)
    }

    @Test func twoSheetsMayPushTheSameLevel() throws {
        let document = try Self.publication("global-chrome-levels-shared").document
        #expect(document.modals.map(\.id) == ["modal-swatch", "modal-second"])
        #expect(document.levels.count == 2)
    }

    // MARK: Hides

    @Test func hidesKeepTheTabsFlagAndTheItemsInOrder() throws {
        let both = try Self.publication("global-chrome-hides-both").document
        #expect(both.pages[0].hides == .init(tabs: true, items: ["chrome-palette"]))
        #expect(both.pages[1].hides == nil)
        let items = try Self.publication("global-chrome-hides-items").document
        #expect(items.pages[0].hides == .init(tabs: false, items: ["chrome-inspect", "chrome-bell"]))
        let tabs = try Self.publication("global-chrome-hides-tabs").document
        #expect(tabs.pages[0].hides == .init(tabs: true, items: []))
    }

    @Test func anEmptyHidesObjectIsStillAUseOfTheCapability() throws {
        let text = try String(contentsOf: Self.file("global-chrome-hides-tabs"), encoding: .utf8)
        let emptied = text.replacingOccurrences(of: "\"tabs\": true", with: "\"tabs\": false")
        let publication = try Self.decode(emptied)
        #expect(publication.document.pages[0].hides == .init(tabs: false, items: []))
        #expect(publication.capabilities.contains(ServerUIGlobalChrome.pageChromeHide))
    }

    @Test func aPageThatHidesNothingIsUnchanged() throws {
        let document = try Self.decode(String(contentsOf: Self.file("accept/badge-chrome-button.json"), encoding: .utf8)).document
        #expect(document.pages.allSatisfy { $0.hides == nil && $0.wideOpen == nil })
    }

    @Test func theShellMenuIsNotAnItemAPageMayHide() throws {
        // Buttons are hideable and the menu is not; an id that names no item is a different error (the corpus holds it).
        let error = try Self.refusal("global-chrome-hides-tabs") { $0.replacingOccurrences(of: "\"tabs\": true", with: "\"items\": [\"chrome-menu\"]") }
        #expect(error?.code == .invalidCombination)
        #expect(error?.pointer == "/document/pages/0/hides/items/0")
    }

    // MARK: Wide open

    @Test func eachWideOpenValueDecodes() throws {
        let document = try Self.publication("global-chrome-wide-open-each").document
        #expect(document.pages.map(\.wideOpen) == [.automatic, .full, .beside])
        let columns = try Self.publication("global-chrome-wide-open-columns-page").document
        #expect(columns.pages[1].wideOpen == .beside && columns.pages[1].navigation == .columns)
    }

    @Test func aDocumentWithoutTheCapabilityKeepsTodaysRule() throws {
        let document = try Self.decode(String(contentsOf: Self.file("accept/badge-chrome-button.json"), encoding: .utf8)).document
        #expect(document.pages.allSatisfy { $0.wideOpen == nil })
    }

    // MARK: Tabs visibility

    @Test func absentTabsVisibilityIsAlways() throws {
        let absent = try Self.decode(String(contentsOf: Self.file("accept/badge-chrome-button.json"), encoding: .utf8)).document.navigation
        #expect(absent.tabsVisibility == nil)
        #expect(absent.effectiveTabsVisibility == .always)
    }

    @Test func eachTabsVisibilityDecodes() throws {
        let always = try Self.publication("global-chrome-tabs-visibility-always").document.navigation
        #expect(always.tabsVisibility == .always && always.effectiveTabsVisibility == .always)
        let rootOnly = try Self.publication("global-chrome-tabs-visibility-root-only").document.navigation
        #expect(rootOnly.tabsVisibility == .rootOnly && rootOnly.effectiveTabsVisibility == .rootOnly)
    }

    // MARK: Together

    @Test func allFourCanLiveInOneDocument() throws {
        let publication = try Self.publication("global-chrome-all")
        for id in ServerUIGlobalChrome.all { #expect(publication.capabilities.contains(id), "\(id)") }
        #expect(publication.document.levels.count == 2)
        #expect(publication.document.navigation.tabsVisibility == .rootOnly)
        #expect(publication.document.pages[0].hides == .init(tabs: true, items: ["chrome-bell"]))
    }

    // MARK: Capability ids

    @Test func theIdsAreAcceptedOnlyInsideTheScope() throws {
        #expect(ServerUIGlobalChrome.all == ["sh.sheet-levels@1", "sh.page-chrome-hide@1", "sh.page-wide-open@1", "sh.tabs-visibility@1"])
        let supported = Set(ServerUICompositionPublication.supportedCapabilities)
        let ingested = Set(ServerUIIngestedCapabilities.all)
        let published = try JSONDecoder().decode([String].self, from: Data(contentsOf: ServerUIContractCorpusTests.directory.appendingPathComponent("capabilities.json")))
        for id in ServerUIGlobalChrome.all {
            #expect(!supported.contains(id) && !ingested.contains(id) && !published.contains(id), "\(id) is published")
            #expect(!ServerUICompositionPublication.acceptedCapabilities.contains(id), "\(id) is accepted outside the scope")
            let scoped = ServerUIGlobalChrome.$understood.withValue(true) { ServerUICompositionPublication.acceptedCapabilities }
            #expect(scoped.contains(id), "\(id)")
        }
    }

    @Test func aComponentMayPushALevelFromASheetButNotFromAPage() throws {
        let sheet = try Self.publication("global-chrome-levels-component-in-sheet")
        #expect(sheet.document.levels.map(\.id) == ["level-one"])
        let error = try #require(try Self.refusal("global-chrome-levels-component-on-page"))
        #expect(error.code == .invalidCombination)
    }

    @Test func aReplacePageMayHideTabsButNotItems() throws {
        let tabs = try Self.publication("global-chrome-hides-tabs-with-replace").document
        #expect(tabs.pages[2].hides == .init(tabs: true, items: []))
        let error = try #require(try Self.refusal("global-chrome-hides-items-with-replace"))
        #expect(error.pointer == "/document/pages/2/hides/items")
    }
}
