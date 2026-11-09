import Foundation
@testable import HassUI
import SwiftUI
import Testing

/// The Profile count badge's text size: caption1 bold at the person's size, held at xLarge
/// (``ProfileButton/badgeTypeRange``), so it never covers the disc it marks.
struct ProfileBadgeTypeTests {
    @Test func followsTheTextSizeBelowTheCap() {
        for size in [DynamicTypeSize.xSmall, .large, .xLarge] {
            #expect(ProfileButton.badgeTypeSize(for: size) == size)
        }
    }

    @Test func holdsAtXLargeAboveTheCap() {
        for size in [DynamicTypeSize.xxLarge, .xxxLarge, .accessibility1, .accessibility3, .accessibility5] {
            #expect(ProfileButton.badgeTypeSize(for: size) == .xLarge)
        }
    }

    @Test func theCountStaysAnnouncedWhateverTheTextSize() {
        let spoken = ProfileButton.accessibilityValue(name: "Alex Demo", attentionCount: 12)
        #expect(spoken == "Alex Demo, 12 items need attention")
    }
}
