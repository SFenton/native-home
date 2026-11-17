import Foundation
import Testing
@testable import HassCore

// MARK: - A stack with an action holds nothing that takes a tap

/// ``ServerUIStackTapCheck``: the walk the Studio's compiler makes under a stack with an action. It sees a `component-ref` as the body of its
/// library entry, and goes into a stack's children, a `local-tabs` node's tabs and blocks, and a `pinned-actions` node's children.
@Suite(.timeLimit(.minutes(1)))
struct ServerUIStackTapCheckTests {
    private static let button = #"{"id":"b","type":"primary-button","props":{},"action":{"type":"back"}}"#
    private static let text = #"{"id":"t","type":"text","props":{}}"#

    /// A publication whose first page holds `component`, and whose library holds `library`.
    private func issues(_ component: String, library: String = "[]") throws -> [ServerUICompositionError] {
        let json = #"{"document":{"pages":[{"components":[\#(component)]}],"modals":[],"componentLibrary":\#(library)}}"#
        return ServerUIStackTapCheck.issues(in: try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8)))
    }

    private func stack(_ children: String, action: Bool = true) -> String {
        let held = action ? #""action":{"type":"back"},"# : ""
        return #"{"id":"s","type":"stack","props":{},\#(held)"children":[\#(children)]}"#
    }

    private func pointers(_ found: [ServerUICompositionError]) -> [String] { found.map(\.pointer) }

    @Test func aButtonUnderAStackWithAnActionIsBlamedAtItsType() throws {
        let found = try issues(stack(Self.button))
        #expect(pointers(found) == ["/document/pages/0/components/0/children/0/type"])
        #expect(found.allSatisfy { $0.code == .invalidCombination })
    }

    @Test func aStackWithNoActionHoldsAnything() throws {
        #expect(try issues(stack(Self.button, action: false)).isEmpty)
        #expect(try issues(stack(Self.text)).isEmpty)
    }

    @Test func aReferenceIsSeenAsItsEntryBody() throws {
        let library = #"[{"id":"entry","node":\#(Self.button)}]"#
        let reference = #"{"id":"r","type":"component-ref","componentId":"entry"}"#
        #expect(pointers(try issues(stack(reference), library: library)) == ["/document/pages/0/components/0/children/0/type"])
        // A reference to a harmless body, and one to a missing entry, are not refused.
        let harmless = #"[{"id":"entry","node":\#(Self.text)}]"#
        #expect(try issues(stack(reference), library: harmless).isEmpty)
        #expect(try issues(stack(reference)).isEmpty)
    }

    @Test func aTappableDeepInAReferenceBodyIsBlamedUnderTheReference() throws {
        let body = stack(Self.button, action: false)
        let library = #"[{"id":"entry","node":\#(body)}]"#
        let reference = #"{"id":"r","type":"component-ref","componentId":"entry"}"#
        #expect(pointers(try issues(stack(reference), library: library)) == ["/document/pages/0/components/0/children/0/children/0/type"])
    }

    @Test func tabBlocksAndPinnedActionsAreWalked() throws {
        let tabs = #"{"id":"l","type":"local-tabs","props":{},"tabs":[{"id":"a","children":[\#(Self.text)]}],"blocks":[{"id":"x","children":[\#(Self.text),\#(Self.button)]}]}"#
        // Tabs first, then blocks: the button is the third child the walk counts.
        #expect(pointers(try issues(stack(tabs))) == ["/document/pages/0/components/0/children/0/children/2/type"])
        let pinned = #"{"id":"p","type":"pinned-actions","props":{},"children":[\#(Self.button)]}"#
        #expect(pointers(try issues(stack(pinned))) == ["/document/pages/0/components/0/children/0/children/0/type"])
    }

    @Test func anActionStackUnderAnActionStackIsBlamed() throws {
        #expect(pointers(try issues(stack(stack(Self.text)))) == ["/document/pages/0/components/0/children/0/type"])
    }

    @Test func aStackInAReferenceBodyIsCheckedAtTheLibraryPointer() throws {
        let body = stack(Self.button)
        let library = #"[{"id":"entry","node":\#(body)}]"#
        #expect(pointers(try issues(Self.text, library: library)) == ["/document/componentLibrary/0/node/children/0/type"])
    }

    @Test func anActionStackUnderATabOrABlockIsCheckedWhereItStands() throws {
        let inner = stack(Self.button)
        let tabs = #"{"id":"l","type":"local-tabs","props":{},"tabs":[{"id":"a","children":[\#(Self.text)]},{"id":"c","children":[\#(Self.text),\#(inner)]}],"blocks":[{"id":"x","children":[\#(inner)]}]}"#
        #expect(pointers(try issues(tabs)) == ["/document/pages/0/components/0/tabs/1/children/1/children/0/type",
                                                "/document/pages/0/components/0/blocks/0/children/0/children/0/type"])
    }
}
