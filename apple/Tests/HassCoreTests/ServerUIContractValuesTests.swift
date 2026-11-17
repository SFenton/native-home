import Foundation
import Testing
@testable import HassCore

private typealias D = ServerUICompositionDocument

/// Fails if: a spacing token's points drift from the scale the renderers lay out by, a chrome item reports another item's id, or a
/// local field's definition check lets through a malformed choice list.
@Suite struct ServerUIContractValuesTests {
    @Test func everySpaceTokenHasItsPoints() {
        let scale: [(D.SpaceToken, Double)] = [(.zero, 0), (.xs, 4), (.s, 8), (.m, 12), (.l, 16), (.xl, 24), (.sectionHeader, 10)]
        for (token, points) in scale {
            #expect(token.points == points)
            #expect(D.Space.token(token).points == points)
        }
        #expect(D.Space.points(6.5).points == 6.5)
    }

    @Test func aChromeItemIsIdentifiedByItsOwnPart() {
        let icon = D.Symbol(name: "gear", rendering: .canonical, unavailable: .canonical)
        let menu = D.MenuItem(id: "menu", label: "Menu", icon: icon, visibility: .always)
        let button = D.ChromeButton(id: "button", label: "B", menuLabel: "B", icon: icon, visibility: .rootOnly, priority: .normal,
                                    rail: .eligible, badge: .none, action: .back)
        let header = D.ShellHeader(id: "header", visibility: .always, quickLinksAction: .back, profileAction: .back)
        #expect([D.ChromeItem.shellMenu(menu), .button(button), .shellHeader(header)].map(\.id) == ["menu", "button", "header"])
    }

    @Test func aChoiceFieldNeedsTwoToTwelveDistinctLabelledOptions() {
        func field(_ options: [D.LocalField.Option], initial: String = "a") -> D.LocalField {
            D.LocalField(id: "f", initial: .string(initial), rule: .choice(options: options))
        }
        let a = D.LocalField.Option(id: "a", label: "A")
        let b = D.LocalField.Option(id: "b", label: "B")
        #expect(field([a, b]).isValidDefinition)
        #expect(!field([a]).isValidDefinition, "one option is not a choice")
        #expect(!field([a, a]).isValidDefinition, "duplicate ids")
        #expect(!field([a, .init(id: "bad id", label: "B")]).isValidDefinition, "an id the shape refuses")
        #expect(!field([a, .init(id: "b", label: "   ")]).isValidDefinition, "a blank label")
        #expect(!field([a, .init(id: "b", label: String(repeating: "x", count: 81))]).isValidDefinition, "a label over 80")
        let many = (0..<13).map { D.LocalField.Option(id: "o\($0)", label: "O") }
        #expect(!field(many, initial: "o0").isValidDefinition, "over twelve options")
        #expect(!field([a, b], initial: "zzz").isValidDefinition, "an initial that is no option")
        #expect(!D.LocalField(id: "", initial: .boolean(true), rule: .boolean).isValidDefinition, "an empty id")
    }
}
