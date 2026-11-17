import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

// MARK: - The style parts

/// Hosted UX and accessibility checks for the four style capabilities (`sh.text-style@1`, `sh.stack@1`, `sh.symbol-part@1`,
/// `sh.choice-icons@1`) at the widths of the iPhone, the folded iPhone Duo and the iPad, in light and dark appearance and at the largest
/// accessibility text size.
///
/// Every document is a case of the shared corpus, with placeholder entity ids, so what the Studio previews is what these draw. A simulator
/// narrower than a width draws it at the simulator's own, as the other hosted layout tests do.
@MainActor
final class ServerUIStyleHostedTests: XCTestCase {
    private static let widths: [CGFloat] = [390, 744, 1024]
    private static let accessibilitySize = UIContentSizeCategory.accessibilityExtraExtraExtraLarge

    override func tearDown() async throws {
        UKMotion.reduceMotionOverride = nil
        HostedPage.hideTracked()
        HostedPage.resetGlobals()
        try await super.tearDown()
    }

    // MARK: Fixture

    private struct Shown {
        let host: UKServerUIRenderer
        let window: UIWindow
        let page: UKServerUIPage
        let store: EntityStore
        let caller: HostedCaller
    }

    /// The corpus case `file` of `folder`, with the components of its third page moved onto the page the renderer opens first, and `edit` run on
    /// the components that now stand there.
    private func publication(_ file: String, folder: String = "accept", edit: ([JSONValue]) -> [JSONValue] = { $0 },
                             adding: [String] = [], removing: [String] = []) throws -> ServerUICompositionPublication {
        let apple = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = apple.appendingPathComponent("Tests/HassCoreTests/ContractCorpus/\(folder)/\(file).json")
        var json = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
        let pages = try XCTUnwrap(json["document"]?["pages"]?.array)
        json = try ServerUIRendererFixture.changing(json, path: "/document/pages/0/components", to: .array(edit(XCTUnwrap(pages[2]["components"]?.array))))
        json = try ServerUIRendererFixture.changing(json, path: "/document/pages/2/components", to: XCTUnwrap(pages[0]["components"]))
        if !adding.isEmpty || !removing.isEmpty {
            // The edit brings a part the case did not use, so the manifest names it too.
            let held = (json["capabilities"]?.array ?? []).compactMap(\.string)
            json = try ServerUIRendererFixture.changing(json, path: "/capabilities", to: .array((held.filter { !removing.contains($0) } + adding).sorted().map(JSONValue.string)))
        }
        return try ServerUICompositionPublication.decode(JSONEncoder().encode(json))
    }

    /// Opens `file` at `width`.
    private func show(_ file: String, folder: String = "accept", width: CGFloat, entities: [EntityState] = [], dark: Bool = false,
                      edit: ([JSONValue]) -> [JSONValue] = { $0 }, adding: [String] = [], removing: [String] = []) throws -> Shown {
        let store = EntityStore()
        store.replaceAll(entities)
        let caller = HostedCaller()
        let host = try UKServerUIRenderer(publication: publication(file, folder: folder, edit: edit, adding: adding, removing: removing), context: UKContext(store: store, caller: caller),
                                          backdrop: ServerUIRendererFixture.backdrop())
        let window = HostedPage.show(host, size: HostedPage.inScene(CGSize(width: width, height: 1180)))
        window.overrideUserInterfaceStyle = dark ? .dark : .light
        HostedPage.wait(0.1)
        let page = try ServerUIRendererFixture.root(host)
        page.view.layoutIfNeeded()
        return Shown(host: host, window: window, page: page, store: store, caller: caller)
    }

    /// Draws the page again at the largest accessibility text size.
    private func enlarge(_ shown: Shown) {
        shown.window.traitOverrides.preferredContentSizeCategory = Self.accessibilitySize
        HostedPage.wait(0.1)
        shown.page.view.layoutIfNeeded()
        HostedPage.layoutTracked()
    }

    private func node<T: UIView>(_ type: T.Type, _ id: String, in shown: Shown) throws -> T {
        try XCTUnwrap(shown.page.nodes[id]?.view as? T, "no \(T.self) named \(id)")
    }

    private func all<T: UIView>(_ type: T.Type, in view: UIView) -> [T] {
        ((view as? T).map { [$0] } ?? []) + view.subviews.flatMap { all(type, in: $0) }
    }

    private func weather(_ state: String, bearing: Double = 90) -> EntityState {
        EntityState(entityId: "weather.demo_home", state: state, attributes: ["temperature": .number(72), "wind_bearing": .number(bearing)])
    }

    // MARK: Stack arrangement

    /// The header stays beside its numeral at the default text size and regroups at an accessibility size, on every family.
    func testTheHeaderRegroupsAtAnAccessibilitySizeAndStaysBesideTheNumeralOtherwise() throws {
        for width in Self.widths {
            let shown = try show("stack-collapse-both-with-regrouping", width: width)
            defer { shown.window.isHidden = true }
            let stack = try node(UKStackView.self, "s", in: shown)
            let numeral = try node(UKServerUIText.self, "numeral", in: shown)
            let condition = try node(UKServerUIText.self, "condition", in: shown)
            XCTAssertEqual(stack.arrangement?.collapsed, false, "width \(width)")
            XCTAssertGreaterThanOrEqual(numeral.frame.minX, condition.frame.maxX - 0.5, "the numeral sits beside the reading (width \(width))")
            enlarge(shown)
            XCTAssertEqual(stack.arrangement?.collapsed, true, "width \(width)")
            XCTAssertEqual(stack.arrangement?.reason, .accessibilitySize)
            let glyph = try node(UKSymbolPartView.self, "glyph", in: shown)
            let range = try node(UKServerUIText.self, "range", in: shown)
            XCTAssertLessThan(abs(glyph.frame.midY - numeral.frame.midY), 1, "the glyph and numeral share a row once regrouped (width \(width))")
            XCTAssertGreaterThanOrEqual(condition.frame.minY, glyph.frame.maxY - 0.5, "the condition drops below")
            XCTAssertGreaterThanOrEqual(range.frame.minY, condition.frame.maxY - 0.5, "the range drops below the condition")
            for child in [glyph, condition, range, numeral] {
                XCTAssertLessThanOrEqual(child.frame.maxX, stack.bounds.width + 0.5, "nothing leaves the stack (width \(width))")
                XCTAssertGreaterThanOrEqual(child.frame.minX, -0.5)
            }
        }
    }

    /// A stack whose counted child does not fit beside the other collapses to a column whatever the text size.
    func testARowCollapsesWhenWhatMustFitDoesNot() throws {
        for width in Self.widths {
            let shown = try show("stack-collapse-overflow", width: width)
            defer { shown.window.isHidden = true }
            let stack = try node(UKStackView.self, "s", in: shown)
            XCTAssertEqual(stack.arrangement?.collapsed, false, "two short texts fit (width \(width))")
            try node(UKServerUIText.self, "b", in: shown).apply(.ready(String(repeating: "Wide ", count: 80)), unavailable: "None")
            shown.page.view.layoutIfNeeded()
            XCTAssertEqual(stack.arrangement?.collapsed, true, "width \(width)")
            XCTAssertEqual(stack.arrangement?.reason, .overflow)
        }
    }

    /// A stack with an action is one 44 pt button named by its label and hint, and activating it presents its sheet.
    func testAStackWithAnActionIsOneNamedButtonThatPresentsItsSheet() throws {
        for width in Self.widths {
            let shown = try show("stack-action-opens-a-sheet", width: width)
            defer { shown.window.isHidden = true }
            let stack = try node(UKStackView.self, "s", in: shown)
            XCTAssertTrue(stack.isAccessibilityElement)
            XCTAssertEqual(stack.accessibilityLabel, "Open forecast")
            XCTAssertEqual(stack.accessibilityHint, "Shows the seven-day forecast.")
            XCTAssertTrue(stack.accessibilityTraits.contains(.button))
            XCTAssertGreaterThanOrEqual(stack.frame.height, HassTokens.minTarget, "width \(width)")
            stack.sendActions(for: .touchUpInside)
            XCTAssertTrue(HostedPage.until { shown.host.modal != nil }, "the sheet opens (width \(width))")
        }
    }

    /// A group names itself and its value; `children` leaves the children; `hidden` removes them; a header role is a heading.
    func testTheAccessibilityOfAStack() throws {
        for width in Self.widths {
            let reading = EntityState(entityId: "weather.demo_home", state: "rainy", attributes: ["temperature": .string("72")])
            let named = try show("stack-a11y-group-with-value", width: width, entities: [reading])
            let group = try node(UKStackView.self, "s", in: named)
            XCTAssertTrue(group.isAccessibilityElement, "width \(width)")
            XCTAssertEqual(group.accessibilityLabel, "Temperature")
            XCTAssertEqual(group.accessibilityValue, "72")
            named.window.isHidden = true
            let children = try show("stack-a11y-children", width: width)
            XCTAssertFalse(try node(UKStackView.self, "s", in: children).isAccessibilityElement, "width \(width)")
            children.window.isHidden = true
            let hidden = try show("stack-a11y-hidden", width: width)
            XCTAssertTrue(try node(UKStackView.self, "s", in: hidden).accessibilityElementsHidden, "width \(width)")
            hidden.window.isHidden = true
            let header = try show("stack-a11y-header-role", width: width)
            let heading = try node(UKStackView.self, "s", in: header)
            XCTAssertTrue(heading.accessibilityTraits.contains(.header), "width \(width)")
            XCTAssertEqual(heading.accessibilityLabel, "Today")
            header.window.isHidden = true
        }
    }

    /// A line between a column's children sits in the gap, and the module surface draws under the children.
    func testDividersAndTheModuleSurface() throws {
        for width in Self.widths {
            let lines = try show("stack-dividers", width: width)
            let stack = try node(UKStackView.self, "s", in: lines)
            let a = try node(UKServerUIText.self, "a", in: lines), b = try node(UKServerUIText.self, "b", in: lines)
            let line = try XCTUnwrap(stack.subviews.first { $0.frame.height <= 1.5 && $0.frame.width >= stack.bounds.width - 1 && $0 !== a && $0 !== b },
                                     "a line across the stack (width \(width))")
            XCTAssertGreaterThanOrEqual(line.frame.minY, a.frame.maxY - 0.5)
            XCTAssertLessThanOrEqual(line.frame.maxY, b.frame.minY + 0.5)
            lines.window.isHidden = true
            let module = try show("stack-surface-module", width: width)
            XCTAssertFalse(all(UKModuleView.self, in: try node(UKStackView.self, "s", in: module)).isEmpty, "the module surface (width \(width))")
            module.window.isHidden = true
        }
    }

    // MARK: Text

    /// An rgba ink keeps its opacity, and a light and dark pair follows the appearance.
    func testAnInkKeepsItsOpacityAndFollowsTheAppearance() throws {
        for width in Self.widths {
            for dark in [false, true] {
                let plain = try show("text-style-ink-rgba", width: width, dark: dark)
                var alpha: CGFloat = 0, white: CGFloat = 0
                let ink = try node(UKServerUIText.self, "t", in: plain).drawnInk.resolvedColor(with: plain.window.traitCollection)
                XCTAssertTrue(ink.getWhite(&white, alpha: &alpha))
                XCTAssertEqual(alpha, 0.85, accuracy: 0.01, "width \(width), dark \(dark)")
                plain.window.isHidden = true
                let pair = try show("text-style-ink-pair-of-rgba", width: width, dark: dark)
                let colour = try node(UKServerUIText.self, "t", in: pair).drawnInk.resolvedColor(with: pair.window.traitCollection)
                XCTAssertTrue(colour.getWhite(&white, alpha: &alpha))
                XCTAssertNotEqual(white, dark ? 0 : 1, "the ink differs between the appearances (width \(width), dark \(dark))")
                pair.window.isHidden = true
            }
        }
    }

    /// A scaled numeral starts at its authored size and stops at its cap.
    func testAScaledNumeralStopsAtItsCap() throws {
        for width in Self.widths {
            let shown = try show("text-style-font-scaled-numeral", width: width)
            defer { shown.window.isHidden = true }
            let text = try node(UKServerUIText.self, "t", in: shown)
            XCTAssertGreaterThanOrEqual(text.drawnFont.pointSize, 75, "width \(width)")
            XCTAssertLessThanOrEqual(text.drawnFont.pointSize, 96.5)
            enlarge(shown)
            XCTAssertEqual(text.drawnFont.pointSize, 96, accuracy: 0.5, "the cap holds at the largest size (width \(width))")
        }
    }

    /// A ticker is one line, read once as the text, and sits still under Reduce Motion.
    func testATickerIsOneLineReadOnce() throws {
        for width in Self.widths {
            for reduced in [false, true] {
                UKMotion.reduceMotionOverride = reduced
                let shown = try show("text-style-overflow-ticker", width: width)
                defer { shown.window.isHidden = true }
                let text = try node(UKServerUIText.self, "t", in: shown)
                let ticker = try XCTUnwrap(text.ticker, "a ticker (width \(width), reduced \(reduced))")
                XCTAssertFalse(ticker.isAccessibilityElement)
                XCTAssertEqual(text.accessibilityLabel, "72\u{00B0}")
                XCTAssertLessThan(ticker.bounds.height, text.drawnFont.lineHeight * 1.6, "one line, never wrapped")
            }
        }
    }

    // MARK: Symbols

    /// A symbol follows its entity's state, and is hidden from VoiceOver.
    func testASymbolFollowsItsStateAndIsHiddenFromVoiceOver() throws {
        for width in Self.widths {
            let shown = try show("symbol-part-by-state", width: width, entities: [weather("rainy")])
            defer { shown.window.isHidden = true }
            let part = try node(UKSymbolPartView.self, "sy", in: shown)
            XCTAssertEqual(part.name, "cloud.rain.fill", "width \(width)")
            XCTAssertFalse(part.isAccessibilityElement)
            shown.store.apply([weather("sunny")])
            XCTAssertTrue(HostedPage.until { part.name == "sun.max.fill" }, "one change swaps the image (width \(width))")
            shown.store.apply([weather("snowy")])
            XCTAssertTrue(HostedPage.until { part.name == "cloud.fill" }, "an unlisted state draws the fallback (width \(width))")
        }
    }

    /// A scaled symbol grows with the text size and never passes its cap.
    func testAScaledSymbolGrowsAndStopsAtItsCap() throws {
        for width in Self.widths {
            let shown = try show("symbol-part-scaled", width: width)
            defer { shown.window.isHidden = true }
            let part = try node(UKSymbolPartView.self, "sy", in: shown)
            let normal = part.drawnPoints
            enlarge(shown)
            XCTAssertGreaterThan(part.drawnPoints, normal, "width \(width)")
            XCTAssertEqual(part.drawnPoints, 80, accuracy: 0.5, "40 pt with a cap of twice")
        }
    }

    /// An image part is an image with its label; a turn follows the number it reads.
    func testAnImageSymbolHasItsLabelAndATurnFollowsItsNumber() throws {
        for width in Self.widths {
            let labelled = try show("symbol-part-image-label", width: width)
            let image = try node(UKSymbolPartView.self, "sy", in: labelled)
            XCTAssertTrue(image.isAccessibilityElement, "width \(width)")
            XCTAssertEqual(image.accessibilityLabel, "Rain")
            XCTAssertTrue(image.accessibilityTraits.contains(.image))
            labelled.window.isHidden = true
            let turned = try show("symbol-part-rotate-by-value", width: width, entities: [weather("rainy", bearing: 90)])
            let arrow = try node(UKSymbolPartView.self, "sy", in: turned)
            XCTAssertTrue(HostedPage.until { arrow.degrees == 90 }, "width \(width)")
            turned.store.apply([weather("rainy", bearing: 180)])
            XCTAssertTrue(HostedPage.until { arrow.degrees == 180 })
            turned.window.isHidden = true
        }
    }

    // MARK: Choice icons

    /// A segmented choice draws its symbols, each segment named by its label with its hint; at an accessibility size it is a menu that
    /// names each option and says its hint.
    func testASegmentedChoiceDrawsItsSymbolsAndSpeaksItsHints() throws {
        let labels = ["Condition", "Precipitation", "Wind"]
        let hints = ["Shows the temperature by hour.", "Shows the chance of rain.", "Shows the wind speed and gusts."]
        for width in Self.widths {
            let shown = try show("choice-icons-symbols-and-hints", width: width)
            defer { shown.window.isHidden = true }
            let choice = try XCTUnwrap(all(UKSegmentedChoice<String>.self, in: shown.page.view).first, "width \(width)")
            let segmented = try XCTUnwrap(all(UISegmentedControl.self, in: choice).first)
            XCTAssertEqual(segmented.numberOfSegments, 3)
            for index in 0..<3 { XCTAssertNotNil(segmented.imageForSegment(at: index), "segment \(index) draws a symbol (width \(width))") }
            let elements = try XCTUnwrap(choice.accessibilityElements as? [NSObject])
            XCTAssertEqual(elements.map(\.accessibilityLabel), labels)
            XCTAssertEqual(elements.map(\.accessibilityHint), hints)
            enlarge(shown)
            let menu = try XCTUnwrap(all(UIButton.self, in: choice).first { $0.menu != nil })
            let actions = (menu.menu?.children ?? []).compactMap { $0 as? UIAction }
            XCTAssertEqual(actions.map(\.title), labels, "width \(width)")
            XCTAssertEqual(actions.map(\.subtitle), hints)
            XCTAssertTrue(actions.allSatisfy { $0.image != nil })
        }
    }

    // MARK: Touches

    /// The stack with a button for its only child and no action of its own: the button the corpus refuses under an action stack, here legal.
    private func holdingAButton(_ components: [JSONValue]) -> [JSONValue] {
        let button = #"{"id":"b","title":"b","type":"primary-button","layout":{"span":1},"props":{},"icon":{"type":"sf-symbol","name":"plus","rendering":"canonical","unavailable":"fallback"},"action":{"type":"present","modalId":"modal-swatch","arguments":{},"ifPresented":"reject"}}"#
        return components.map { component in
            guard case .object(var object) = component, let child = try? JSONDecoder().decode(JSONValue.self, from: Data(button.utf8)) else { return component }
            object["children"] = .array([child])
            return .object(object)
        }
    }

    /// A button inside a stack with no action takes the tap, and the stack itself takes none, so a page still scrolls under it.
    func testAButtonInsideAPlainStackTakesTheTouch() throws {
        for width in Self.widths {
            let shown = try show("stack-column", width: width, edit: holdingAButton, adding: ["sh.primary-button@1"])
            defer { shown.window.isHidden = true }
            let stack = try node(UKStackView.self, "s", in: shown)
            let button = try node(UKServerUIPrimaryButton.self, "b", in: shown)
            XCTAssertTrue(stack.isUserInteractionEnabled, "width \(width)")
            let centre = button.convert(CGPoint(x: button.bounds.midX, y: button.bounds.midY), to: shown.window)
            let hit = try XCTUnwrap(shown.window.hitTest(centre, with: nil), "the touch lands (width \(width))")
            XCTAssertTrue(hit === button || hit.isDescendant(of: button),
                          "the button gets the touch, not the stack (width \(width)): hit \(type(of: hit))")
            let bare = CGPoint(x: stack.bounds.maxX - 1, y: stack.bounds.maxY - 1)
            if !button.frame.contains(bare) { XCTAssertNil(stack.hitTest(bare, with: nil), "the stack takes no touch of its own") }
        }
    }

    /// A stack with an action still takes the touch itself.
    func testAStackWithAnActionTakesTheTouchItself() throws {
        let shown = try show("stack-action-opens-a-sheet", width: Self.widths[0])
        defer { shown.window.isHidden = true }
        let stack = try node(UKStackView.self, "s", in: shown)
        XCTAssertTrue(stack.hitTest(CGPoint(x: stack.bounds.midX, y: stack.bounds.midY), with: nil) != nil)
    }

    // MARK: Section title and title3

    /// A `title3` text is the system's title3, regular and not a heading; a `section-title` is bold and a heading (HIG, Typography).
    func testTitle3IsPlainAndASectionTitleIsABoldHeading() throws {
        func restyle(_ style: String) -> ([JSONValue]) -> [JSONValue] {
            { components in
                components.map { component in
                    guard case .object(var object) = component, case .object(var props)? = object["props"] else { return component }
                    props["style"] = .string(style)
                    object["props"] = .object(props)
                    return .object(object)
                }
            }
        }
        for width in Self.widths {
            let plain = try show("text-style-style-title3", width: width)
            let title = try node(UKServerUIText.self, "t", in: plain)
            let reference = UIFont.preferredFont(forTextStyle: .title3, compatibleWith: plain.window.traitCollection)
            XCTAssertEqual(title.drawnFont.pointSize, reference.pointSize, accuracy: 0.5, "width \(width)")
            XCTAssertEqual(UKStyledText.styleWeight(.title3, traits: plain.window.traitCollection), .regular)
            XCTAssertFalse(title.accessibilityTraits.contains(.header), "a title3 is not announced as a heading (width \(width))")
            XCTAssertTrue(title.accessibilityTraits.contains(.staticText))
            let weight = (title.drawnFont.fontDescriptor.object(forKey: .traits) as? [UIFontDescriptor.TraitKey: Any])?[.weight] as? CGFloat ?? 0
            XCTAssertLessThan(weight, UIFont.Weight.medium.rawValue, "regular, not bold")
            plain.window.isHidden = true
            let section = try show("text-style-old-styles-need-no-id", width: width, edit: restyle("section-title"),
                               adding: ["sh.section-title@1"], removing: ["sh.supporting-text-styles@1"])
            let heading = try node(UKServerUIText.self, "t", in: section)
            XCTAssertTrue(heading.accessibilityTraits.contains(.header), "width \(width)")
            let bold = (heading.drawnFont.fontDescriptor.object(forKey: .traits) as? [UIFontDescriptor.TraitKey: Any])?[.weight] as? CGFloat ?? 0
            XCTAssertGreaterThan(bold, UIFont.Weight.medium.rawValue, "a section title is bold")
            section.window.isHidden = true
        }
    }

    // MARK: Redraws

    /// An observation tick that changes nothing keeps the module surface, so a label-bound change stays one box update.
    func testAnUnchangedTickKeepsTheSurface() throws {
        let shown = try show("stack-surface-module", width: Self.widths[0])
        defer { shown.window.isHidden = true }
        let stack = try node(UKStackView.self, "s", in: shown)
        let before = try XCTUnwrap(all(UKModuleView.self, in: stack).first)
        let definition = try XCTUnwrap(stack.definition)
        stack.apply(definition, members: stack.members, label: nil, spokenValue: nil, isEnabled: false)
        XCTAssertTrue(all(UKModuleView.self, in: stack).first === before, "the same surface view")
    }

    /// A choice keeps the same elements between reads, and each sits in its own segment of the choice's space.
    func testTheSegmentElementsAreKeptAndPlaced() throws {
        let shown = try show("choice-icons-symbols-and-hints", width: Self.widths[0])
        defer { shown.window.isHidden = true }
        let choice = try XCTUnwrap(all(UKSegmentedChoice<String>.self, in: shown.page.view).first)
        let first = try XCTUnwrap(choice.accessibilityElements as? [UIAccessibilityElement])
        let second = try XCTUnwrap(choice.accessibilityElements as? [UIAccessibilityElement])
        XCTAssertTrue(zip(first, second).allSatisfy { $0 === $1 }, "VoiceOver's focus stays on one element")
        let width = choice.bounds.width / 3
        let mirrored = choice.effectiveUserInterfaceLayoutDirection == .rightToLeft
        for (index, element) in first.enumerated() {
            let slot = CGFloat(mirrored ? 2 - index : index)
            XCTAssertEqual(element.accessibilityFrameInContainerSpace.minX, width * slot, accuracy: 1, "segment \(index)")
            XCTAssertEqual(element.accessibilityFrameInContainerSpace.width, width, accuracy: 1)
        }
    }

    // MARK: Lines

    /// A line limit that wraps ends with an ellipsis, as the Studio's clamp does.
    func testALineLimitEndsWithAnEllipsis() throws {
        let shown = try show("text-style-lines-three", width: Self.widths[0])
        defer { shown.window.isHidden = true }
        let text = try node(UKServerUIText.self, "t", in: shown)
        XCTAssertEqual(text.lineBreak, .byTruncatingTail)
    }

    /// A scaled size with no weight of its own keeps the weight of the style it is relative to (a headline stays semibold).
    func testAScaledTextWithNoWeightKeepsTheStylesWeight() throws {
        func scaledHeadline(_ components: [JSONValue]) -> [JSONValue] {
            components.map { component in
                guard case .object(var object) = component, case .object(var props)? = object["props"] else { return component }
                props["style"] = .string("headline")
                props["font"] = .object(["scale": .object(["points": .number(30), "relativeTo": .string("headline")])])
                object["props"] = .object(props)
                return .object(object)
            }
        }
        for width in Self.widths {
            let shown = try show("text-style-font-scaled-numeral", width: width, edit: scaledHeadline)
            defer { shown.window.isHidden = true }
            let text = try node(UKServerUIText.self, "t", in: shown)
            let weight = (text.drawnFont.fontDescriptor.object(forKey: .traits) as? [UIFontDescriptor.TraitKey: Any])?[.weight] as? CGFloat ?? 0
            XCTAssertEqual(weight, UKStyledText.styleWeight(.headline, traits: shown.window.traitCollection).rawValue, accuracy: 0.01, "width \(width)")
            XCTAssertGreaterThan(weight, UIFont.Weight.regular.rawValue, "a headline is heavier than regular")
        }
    }

    /// A tick that changes neither the part nor its label builds no image; a change builds one.
    func testAnUnchangedTickKeepsTheSymbolImage() throws {
        for width in Self.widths {
            let shown = try show("symbol-part-image-label", width: width)
            defer { shown.window.isHidden = true }
            let part = try node(UKSymbolPartView.self, "sy", in: shown)
            let value = try XCTUnwrap(part.applied)
            let before = part.drawCount
            XCTAssertGreaterThan(before, 0, "drawn once (width \(width))")
            part.apply(value, label: "Rain")
            part.show(name: part.name)
            XCTAssertEqual(part.drawCount, before, "nothing is drawn again")
            part.apply(value, label: "Rain showers")
            XCTAssertGreaterThan(part.drawCount, before, "a new label draws again")
        }
    }

    // MARK: Shapes

    /// A shape is decoration: it has the authored size and VoiceOver skips it.
    func testAShapeHasItsSizeAndIsSkippedByVoiceOver() throws {
        for width in Self.widths {
            let shown = try show("shape-capsule", width: width)
            defer { shown.window.isHidden = true }
            let shape = try node(UKShapeView.self, "sh", in: shown)
            XCTAssertFalse(shape.isAccessibilityElement)
            XCTAssertEqual(shape.drawnFrame.width, 28, accuracy: 0.5, "width \(width)")
            XCTAssertEqual(shape.drawnFrame.height, 8, accuracy: 0.5)
            XCTAssertEqual(shape.drawnFrame.minX, 0, accuracy: 0.5, "on the leading edge")
        }
    }
}
