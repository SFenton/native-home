@testable import HassUI
import Testing

struct ScreenshotPrivacyTests {
    @Test func redactsOnlyWhenFlaggedOutsideTheGalleries() {
        #expect(ScreenshotPrivacy.isRedacting(redactFlag: "1", gallery: nil))
        #expect(ScreenshotPrivacy.isRedacting(redactFlag: "1", gallery: ""))
        #expect(!ScreenshotPrivacy.isRedacting(redactFlag: "1", gallery: "security"), "Gallery data is synthetic")
        #expect(!ScreenshotPrivacy.isRedacting(redactFlag: nil, gallery: nil))
        #expect(!ScreenshotPrivacy.isRedacting(redactFlag: "0", gallery: nil))
    }
}
