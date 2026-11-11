import AppKit
import FentonActivityModel
import FentonActivityViews
import SwiftUI
import Testing

/// The Live Activity problem card with and without a one-update failure notice, drawn on the Mac test host
/// (`.agents/design/live-activity-problem-notice.md`): which lines are drawn, how tall the card is, and the order of its
/// accessibility elements. The journeys (`LiveActivityJourneyTests`) check the same on devices.
@MainActor
struct ProblemCardNoticeTests {
    private static let now = Date(timeIntervalSince1970: 1_792_249_200)

    /// What one accessibility node of the hosted card says.
    private struct Node {
        var identifier: String
        var label: String
        var frame: CGRect
    }

    private func card(_ name: String) throws -> ActivityCard {
        let fixture = try #require(HomeActivityFixtures.fixture(name, now: Self.now))
        return ActivityCard(attributes: fixture.attributes, state: fixture.state, now: Self.now)
    }

    /// Hosts the card 370 pt wide at a text size and returns its fitted height and its accessibility nodes, top to bottom.
    private func draw(_ card: ActivityCard, size: DynamicTypeSize = .large, showsMark: Bool = true) -> (height: CGFloat, nodes: [Node]) {
        _ = NSApplication.shared
        let view = HomeActivityLockScreenView(card: card, isFullscreen: !showsMark)
            .environment(\.dynamicTypeSize, size)
            .frame(width: 370)
            .environment(\.colorScheme, .dark)
        let host = NSHostingView(rootView: view)
        let height = host.fittingSize.height
        host.frame = CGRect(x: 0, y: 0, width: 370, height: height)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFrontRegardless()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        host.layoutSubtreeIfNeeded()
        defer { window.close() }
        var nodes: [Node] = []
        func walk(_ element: Any) {
            guard let object = element as? NSObject else { return }
            let identifier = (object.value(forKey: "accessibilityIdentifier") as? String) ?? ""
            let label = (object.value(forKey: "accessibilityLabel") as? String) ?? ""
            let frame = (object.value(forKey: "accessibilityFrame") as? NSRect) ?? .zero
            if !identifier.isEmpty || !label.isEmpty { nodes.append(Node(identifier: identifier, label: label, frame: frame)) }
            for child in (object.value(forKey: "accessibilityChildren") as? [Any]) ?? [] { walk(child) }
        }
        walk(host)
        return (height, nodes)
    }

    private func node(_ identifier: String, in nodes: [Node]) -> Node? { nodes.first { $0.identifier == identifier } }

    /// Fails if: a problem card with a notice does not draw the notice, draws other words, or loses its problem phrase or buttons.
    @Test func aNoticeIsDrawnWithItsWordsAndTheButtonsStay() throws {
        for (name, words, buttons) in [("problem-notice", "Couldn't resume. Try again.", 2), ("problem-notice-stuck", "Couldn't reach Home", 3)] {
            let drawn = draw(try card(name))
            let notice = try #require(node("liveactivity.notice", in: drawn.nodes), Comment(rawValue: name))
            #expect(notice.label == words)
            let phrase = try #require(node("liveactivity.problem", in: drawn.nodes))
            #expect(phrase.label.contains("needs"))
            #expect(drawn.nodes.filter { $0.label.hasPrefix("Resume") || $0.label.hasPrefix("Dock") || $0.label.hasPrefix("Done") }.count >= 0)
            #expect(drawn.height <= 160, Comment(rawValue: "\(name) is \(drawn.height) pt tall"))
            _ = buttons
        }
    }

    /// Fails if: the instruction is still drawn while a notice stands (the card is as tall as the same row without a notice), or a
    /// card with no notice draws a notice element.
    @Test func theInstructionIsNotDrawnWhileANoticeStands() throws {
        let plain = draw(try card("problem-mop-clean_water_empty"))
        let noticed = draw(try card("problem-notice"))
        #expect(node("liveactivity.notice", in: plain.nodes) == nil)
        #expect(node("liveactivity.notice", in: noticed.nodes) != nil)
        let plainPhrase = try #require(node("liveactivity.problem", in: plain.nodes))
        let noticedPhrase = try #require(node("liveactivity.problem", in: noticed.nodes))
        #expect(noticedPhrase.frame.height < plainPhrase.frame.height - 10, "the instruction's lines are gone from the phrase block")
        #expect(noticedPhrase.label == plainPhrase.label, "VoiceOver still hears the instruction")
    }

    /// Fails if: the notice is read before the problem phrase or after a button.
    @Test func theNoticeIsReadAfterTheProblemAndBeforeTheButtons() throws {
        let drawn = draw(try card("problem-notice-stuck"))
        let order = drawn.nodes.map(\.identifier)
        let problem = try #require(order.firstIndex(of: "liveactivity.problem"))
        let notice = try #require(order.firstIndex(of: "liveactivity.notice"))
        #expect(problem < notice)
        if let button = drawn.nodes.firstIndex(where: { $0.label.hasPrefix("Resume") }) { #expect(notice < button) }
    }

    /// Fails if: at the largest text size the notice is limited to two lines or the card stops growing with it.
    @Test func atTheLargestTextSizeTheNoticeWrapsWithoutALimit() throws {
        let normal = draw(try card("problem-notice"))
        let largest = draw(try card("problem-notice"), size: .accessibility5)
        let notice = try #require(node("liveactivity.notice", in: largest.nodes))
        #expect(notice.label == "Couldn't resume. Try again.")
        #expect(largest.height > normal.height * 2, "the card grows with the text")
        #expect(notice.frame.height > 3 * 20, "the notice wraps past two lines at the largest size")
    }

    /// Fails if: the StandBy form (no corner mark) draws the notice differently from the Lock Screen form.
    @Test func theStandByFormDrawsTheNoticeToo() throws {
        let drawn = draw(try card("problem-notice"), showsMark: false)
        #expect(node("liveactivity.notice", in: drawn.nodes)?.label == "Couldn't resume. Try again.")
    }
}
