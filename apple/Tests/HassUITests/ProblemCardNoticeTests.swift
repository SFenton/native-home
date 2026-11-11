import AppKit
import FentonActivityModel
@testable import FentonActivityViews
import SwiftUI
import Testing

/// The Live Activity problem card with and without a one-update failure notice, on the Mac test host
/// (`.agents/design/live-activity-problem-notice.md`). The macOS host has no accessibility tree, so which lines the card
/// draws and in what order is read from its view value with ``ControlProbe`` (every string in declaration order, which is
/// reading order), and its height from a hosted layout at each text size. The journeys (`LiveActivityJourneyTests`) check the
/// same on devices.
@MainActor
struct ProblemCardNoticeTests {
    private static let now = Date(timeIntervalSince1970: 1_792_249_200)

    private func card(_ name: String) throws -> ActivityCard {
        let fixture = try #require(HomeActivityFixtures.fixture(name, now: Self.now))
        return ActivityCard(attributes: fixture.attributes, state: fixture.state, now: Self.now)
    }

    private func problemCard(_ card: ActivityCard, showsMark: Bool = true) throws -> ProblemCardView {
        ProblemCardView(card: card, problem: try #require(card.problem), showsMark: showsMark)
    }

    /// The strings the card's own lines hold, in reading order: its text, identifiers and labels, up to where the buttons
    /// start carrying the whole card (they begin with its tag).
    private func strings(_ card: ActivityCard) throws -> [String] {
        let all = ControlProbe.all(String.self, in: try problemCard(card).body)
        return Array(all.prefix { $0 != card.attributes.tag })
    }

    /// The card's height when laid out 370 pt wide at a text size.
    private func height(_ card: ActivityCard, size: DynamicTypeSize = .large, showsMark: Bool = true) throws -> CGFloat {
        _ = NSApplication.shared
        let view = HomeActivityLockScreenView(card: card, isFullscreen: !showsMark)
            .environment(\.dynamicTypeSize, size)
            .frame(width: 370)
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(x: 0, y: 0, width: 370, height: 10)
        host.layoutSubtreeIfNeeded()
        return host.fittingSize.height
    }

    /// Fails if: a problem card with a notice does not draw the notice words, or draws the instruction beside them.
    @Test func aNoticeStandsInPlaceOfTheInstruction() throws {
        let plain = try card("problem-mop-clean_water_empty")
        let amber = try card("problem-notice")
        let instruction = try #require(plain.problem?.message)
        #expect(try strings(plain).contains(instruction))
        #expect(!(try strings(plain).contains("Couldn't resume. Try again.")))
        let drawn = try strings(amber)
        #expect(drawn.contains("Couldn't resume. Try again."))
        #expect(!drawn.contains(instruction), "the instruction is not drawn while a notice stands")
        let stuck = try card("problem-notice-stuck")
        #expect(try strings(stuck).contains("Couldn't reach Home"))
        #expect(!(try strings(stuck).contains(try #require(stuck.problem?.message))))
    }

    /// Fails if: the notice is read before the problem line or the notice element loses its identifier, or the phrase stops
    /// speaking the instruction.
    @Test func theNoticeIsReadAfterTheProblemAndBeforeTheButtons() throws {
        let noticed = try card("problem-notice-stuck")
        let drawn = try strings(noticed)
        let problem = try #require(drawn.firstIndex(of: "liveactivity.problem"))
        let notice = try #require(drawn.firstIndex(of: "liveactivity.notice"))
        #expect(problem < notice)
        #expect(drawn.contains(noticed.spokenSummary), "the phrase still speaks the instruction")
        #expect(noticed.spokenSummary.contains(try #require(noticed.problem?.message)))
        #expect(!(try strings(card("problem-navigation-stuck")).contains("liveactivity.notice")), "no notice element without a notice")
    }

    /// Fails if: either notice fixture grows past the 160 pt Lock Screen limit at the default size, or the card no longer
    /// has room for the buttons under the notice.
    @Test func theNoticeCardsFitTheLockScreenLimit() throws {
        for name in ["problem-notice", "problem-notice-stuck"] {
            let fitted = try height(try card(name))
            #expect(fitted <= 160 && fitted > 84, Comment(rawValue: "\(name) is \(fitted) pt tall"))
        }
        let plainFitted = try height(try card("problem-mop-clean_water_empty"))
        #expect(try height(try card("problem-notice")) < plainFitted, "the notice replaces the instruction's lines, so the card is shorter")
    }

    /// Fails if: laying the card out at the largest text size (where the notice has no line limit) or in the StandBy form (no
    /// corner mark) draws a card shorter than the default one or taller than the Lock Screen form. The Mac host does not scale
    /// text with the size, so the wrapping itself is checked by the journeys at accessibility 5.
    @Test func theLargestTextSizeAndStandByLayOutTheNoticeCard() throws {
        let amber = try card("problem-notice")
        let normal = try height(amber)
        #expect(try height(amber, size: .accessibility5) >= normal)
        #expect(try height(amber, showsMark: false) <= normal)
        #expect(try height(try card("problem-notice-stuck"), size: .accessibility5) > 84)
    }
}
