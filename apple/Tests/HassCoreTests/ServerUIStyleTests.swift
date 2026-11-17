import Foundation
import HassTestSupport
import Testing
@testable import HassCore

// MARK: - Style parts

/// Decode of the four style capabilities (`sh.text-style@1`, `sh.stack@1`, `sh.symbol-part@1`, `sh.choice-icons@1`): what each field becomes in the
/// compiled document, which ids it needs, and how an ink resolves for an appearance. The accept and reject cases themselves run in
/// ``ServerUIContractCorpusTests``.
@Suite(.timeLimit(.minutes(2)))
@MainActor
struct ServerUIStyleTests {
    typealias D = ServerUICompositionDocument

    private static let directory = ServerUIContractCorpusTests.directory
    /// The demo house the corpus's entity ids read.
    private static var house: HouseConfigSource {
        let source = HouseConfigSource()
        source.set(DemoHouse.config)
        return source
    }

    private func publication(_ file: String) throws -> ServerUICompositionPublication {
        let bytes = try Data(contentsOf: Self.directory.appendingPathComponent("accept/\(file).json"))
        return try HouseConfigSource.$scoped.withValue(Self.house) { try ServerUICompositionPublication.decode(bytes) }
    }

    /// The components of the page the corpus case puts its parts on.
    private func components(_ file: String) throws -> [D.Component] { try publication(file).document.pages[2].surface.components }

    // MARK: Ink

    /// A `title3` text keeps its own style: the section title is a different one, so a renderer cannot take the two for each other.
    @Test func aTitle3TextIsNotASectionTitle() throws {
        let texts = try components("text-style-style-title3").compactMap { component -> D.Text? in if case .text(let text) = component { return text } else { return nil } }
        let text = try #require(texts.first)
        #expect(text.style == .title3)
        #expect(text.style != .sectionTitle)
        #expect(text.style.needsTextStyle)
        #expect(!D.TextStyle.sectionTitle.needsTextStyle)
    }

    /// A line sits between groups in the row and in the collapsed column, so the larger count of the two sizes the lines.
    @Test func theDividerCountIsTheLargerOfTheRowAndTheCollapsedGroups() throws {
        let stacks = try components("stack-dividers").compactMap { component -> ServerUIStack? in if case .stack(let stack) = component { return stack } else { return nil } }
        var stack = try #require(stacks.first)
        #expect(stack.dividerCount(shown: 3) == 2, "each child is a group")
        stack.groups = [.init(children: ["a"]), .init(children: ["b", "c"])]
        #expect(stack.dividerCount(shown: 3) == 1)
        stack.collapse = .init(when: [.overflow], groups: [.init(children: ["a"]), .init(children: ["b"]), .init(children: ["c"])])
        #expect(stack.dividerCount(shown: 3) == 2, "the collapsed column has more groups")
        stack.collapse = .init(when: [.overflow], groups: [.init(children: ["a", "b", "c"])])
        #expect(stack.dividerCount(shown: 3) == 1)
        stack.dividers = nil
        #expect(stack.dividerCount(shown: 3) == 0)
        stack.groups = nil
        stack.collapse = nil
        stack.dividers = .init(ink: stack.dividers?.ink ?? ServerUIInk(light: .init(rgb: .init(red: 0, green: 0, blue: 0)), dark: .init(rgb: .init(red: 0, green: 0, blue: 0))), width: 1)
        #expect(stack.dividerCount(shown: 1) == 0, "one child has no line")
    }

    @Test func anInkResolvesPerAppearance() {
        let pair = ServerUIInk(light: .init(rgb: .init(red: 1, green: 2, blue: 3), alpha: 0.5), dark: .init(rgb: .init(red: 9, green: 8, blue: 7)))
        #expect(pair.color(isDark: false).alpha == 0.5)
        #expect(pair.color(isDark: true).rgb == .init(red: 9, green: 8, blue: 7))
        #expect(pair.color(isDark: true).alpha == 1)
    }

    @Test func aSingleColourIsTheSameInBothAppearances() {
        let one = ServerUIInk(.init(rgb: .init(red: 255, green: 255, blue: 255), alpha: 0.85))
        #expect(one.color(isDark: false) == one.color(isDark: true))
    }

    @Test func opacityIsHeldToZeroThroughOne() {
        #expect(ServerUIInk.Color(rgb: .init(red: 0, green: 0, blue: 0), alpha: 1.5).alpha == 1)
        #expect(ServerUIInk.Color(rgb: .init(red: 0, green: 0, blue: 0), alpha: -1).alpha == 0)
    }

    @Test func theScanFindsOpacityOutsideLiterals() throws {
        let inside = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"a":[{"type":"literal","value":{"type":"rgba"}}]}"#.utf8))
        let outside = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"a":[{"x":{"type":"rgba"}}]}"#.utf8))
        #expect(!ServerUIInkScan.holdsRGBA(inside))
        #expect(ServerUIInkScan.holdsRGBA(outside))
    }

    // MARK: Text

    @Test func aScaledNumeralKeepsItsFontAndInk() throws {
        let text = try #require(try components("text-style-font-scaled-numeral").compactMap { c -> D.Text? in if case .text(let t) = c { t } else { nil } }.first)
        #expect(text.style == .largeTitle)
        #expect(text.look.weight == .thin)
        #expect(text.look.digits == .monospaced)
        #expect(text.look.scale == .init(points: 76, relativeTo: .largeTitle, maxPoints: 96))
        #expect(text.look.lines == 1)
        #expect(text.look.isDeclared)
    }

    @Test func anOlderStyleWithNoLookFieldIsNotDeclared() throws {
        let text = try #require(try components("text-style-old-styles-need-no-id").compactMap { c -> D.Text? in if case .text(let t) = c { t } else { nil } }.first)
        #expect(!text.look.isDeclared)
        #expect(!text.style.needsTextStyle)
    }

    @Test func aTickerSlidesAndAWrappedLineAsksForItsWidth() {
        var look = ServerUITextLook()
        look.overflow = .ticker
        #expect(look.isTicker && look.shrinks)
        look.overflow = .truncate
        #expect(!look.isTicker && look.shrinks)
        look.overflow = .wrap
        #expect(!look.shrinks)
    }

    // MARK: Stack, shape and symbol

    @Test func theStackHeaderKeepsItsGroupsAndItsCollapse() throws {
        let stack = try #require(try components("stack-collapse-both-with-regrouping").compactMap { c -> ServerUIStack? in if case .stack(let s) = c { s } else { nil } }.first)
        #expect(stack.axis == .horizontal)
        #expect(stack.collapse?.when == [.accessibilitySize, .overflow])
        #expect(stack.groups?.count == 2)
        #expect(stack.children.count == 4)
    }

    @Test func theHeaderStackHoldsAGlyphAndATickerAndANumeral() throws {
        let stack = try #require(try components("stack-collapse-both-with-regrouping").compactMap { c -> ServerUIStack? in if case .stack(let s) = c { s } else { nil } }.first)
        let kinds = stack.children.map { child -> String in
            switch child {
            case .symbol: "symbol"
            case .text(let text): text.look.isTicker ? "ticker" : "text"
            default: "other"
            }
        }
        #expect(kinds == ["symbol", "ticker", "text", "text"])
    }

    @Test func aSymbolByStateKeepsItsFallbackAndItsRule() throws {
        let part = try #require(try components("symbol-part-by-state").compactMap { c -> ServerUISymbolPart? in if case .symbol(let s) = c { s } else { nil } }.first)
        #expect(part.symbol.name == "cloud.fill")
        #expect(part.rule != nil)
        #expect(part.size == .init(points: 40))
        #expect(part.rendering == .multicolor)
        #expect(part.accessibility == .hidden)
    }

    @Test func aTintedSymbolKeepsItsTrimAndTurn() throws {
        let part = try #require(try components("symbol-part-rotate-fixed").compactMap { c -> ServerUISymbolPart? in if case .symbol(let s) = c { s } else { nil } }.first)
        #expect(part.rotate?.staticKind == .number)
    }

    @Test func aShapeKeepsItsFormAndFill() throws {
        let shape = try #require(try components("shape-capsule").compactMap { c -> ServerUIShapePart? in if case .shape(let s) = c { s } else { nil } }.first)
        #expect(shape.form == .capsule)
        #expect(shape.width == 28 && shape.height == 8)
        #expect(shape.fill.color(isDark: false).alpha == 0.18)
    }

    // MARK: Choice options

    @Test func everyOptionOfASegmentedChoiceCarriesItsSymbolAndHint() throws {
        let fields = try publication("choice-icons-symbols-and-hints").document.localState
        guard case .choice(let options)? = fields.first?.rule else { Issue.record("not a choice"); return }
        #expect(options.map(\.id) == ["condition", "precipitation", "wind"])
        #expect(options.compactMap { $0.symbol?.name } == ["cloud.sun.fill", "drop.fill", "wind"])
        #expect(options.allSatisfy { $0.isDecorated })
        #expect(options.first?.hint == "Shows the temperature by hour.")
    }

    @Test func aChoiceWithNoIconsStaysPlain() throws {
        let option = ServerUICompositionDocument.LocalField.Option(id: "a", label: "A")
        #expect(!option.isDecorated)
    }
}
