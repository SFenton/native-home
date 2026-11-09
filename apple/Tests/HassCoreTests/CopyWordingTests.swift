@testable import HassCore
import Testing
import HassTestSupport

/// The strings the copy review changed (`proposals/copy-wording`, decided 2026-10-24).
@Suite(.demoHouse)
struct CopyWordingTests {
    @Test func pluralsAgreeWithTheirNumber() {
        #expect(PluralCopy.count(0, "sensor") == "0 sensors")
        #expect(PluralCopy.count(1, "sensor") == "1 sensor")
        #expect(PluralCopy.count(3, "room") == "3 rooms")
        #expect(PluralCopy.count(2, "box", plural: "boxes") == "2 boxes")
        #expect(PluralCopy.count(1, "box", plural: "boxes") == "1 box")
        #expect(PluralCopy.noun(1, "room") == "room")
        #expect(PluralCopy.noun(2, "room") == "rooms")
    }

    @Test func emptyChoresReadAsTwoSentences() {
        for page in ChoresConfig.pages {
            #expect(!page.emptyDescription.contains("- "), "\(page.emptyDescription)")
        }
        #expect(ChoresConfig.unassignedChores.emptyDescription == "There are no unassigned chores due. Nice job!")
        #expect(ChoresConfig.homeImprovementChores.emptyDescription == "There are no home improvement tasks due. Nice job!")
    }

    @Test func feedbackFailuresNameATakeableNextStep() {
        let notConfigured = FeedbackFilingError.notConfigured.errorDescription ?? ""
        let github = FeedbackFilingError.githubProblem.errorDescription ?? ""
        #expect(notConfigured == "Reporting isn't set up in Home Assistant yet. Ask whoever manages Home Assistant to set it up.")
        #expect(github == "Home Assistant couldn't file this on GitHub. Try again later, or ask whoever manages Home Assistant to check its GitHub connection.")
        for text in [notConfigured, github] {
            #expect(!text.contains("Fenton Home Feedback"))
            #expect(!text.contains("token"))
        }
    }

    @Test func theSetupSubtitleIsPlainText() {
        #expect(SoloTripCopy.setupRequiredSubtitle == "Needs setup in Home Assistant")
        #expect(!SoloTripCopy.setupRequiredSubtitle.contains("Learn More"))
    }

    @Test func theLowBatteryWarningNamesTheAction() {
        #expect(SprinklerFormat.lowBatteryWarning(title: "Garden Sprinklers", percent: 15)
            == "Garden Sprinklers battery is low (15%). Replace the batteries soon.")
        #expect(SprinklerFormat.lowBatteryWarning(title: "Front Yard", percent: 12.5).contains("(12.5%)"))
    }
}
