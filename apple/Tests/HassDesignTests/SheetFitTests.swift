import SwiftUI
import Testing
@testable import HassDesign

/// Content-fitted sheet height (owner, 2026-10-16): the pure decisions behind `hassSheet(height: .fitted)` and the edit
/// state of the confirm check.
@MainActor
struct SheetFitTests {
    // MARK: - Detent

    @Test func noMeasurementIsProvisional() {
        #expect(SheetFit.detent(contentHeight: nil, availableHeight: 800) == .provisional)
        #expect(SheetFit.detent(contentHeight: .nan, availableHeight: 800) == .provisional)
    }

    @Test func shortContentGetsItsOwnHeight() {
        #expect(SheetFit.detent(contentHeight: 360.2, availableHeight: 800) == .height(361))
    }

    @Test func tooShortAReadingIsRaisedToTheMinimum() {
        #expect(SheetFit.detent(contentHeight: 40, availableHeight: 800) == .height(SheetFit.minimumHeight))
    }

    @Test func contentReachingLargeIsLarge() {
        #expect(SheetFit.detent(contentHeight: 800, availableHeight: 800) == .large)
        #expect(SheetFit.detent(contentHeight: 2400, availableHeight: 800) == .large)
        // Within the snap distance: a custom detent a hair under large would leave a sliver of the page.
        #expect(SheetFit.detent(contentHeight: 800 - SheetFit.largeSnap + 1, availableHeight: 800) == .large)
        #expect(SheetFit.detent(contentHeight: 800 - SheetFit.largeSnap - 1, availableHeight: 800) != .large)
    }

    @Test func noWindowMeansLarge() {
        #expect(SheetFit.detent(contentHeight: 300, availableHeight: 0) == .large)
    }

    // MARK: - Readings

    @Test func smallChangesDoNotMoveTheSheet() {
        #expect(SheetFit.shouldUpdate(from: nil, to: 300))
        #expect(!SheetFit.shouldUpdate(from: 300, to: 301))
        #expect(SheetFit.shouldUpdate(from: 300, to: 302))
        #expect(!SheetFit.shouldUpdate(from: 300, to: 0))
        #expect(!SheetFit.shouldUpdate(from: 300, to: .infinity))
    }

    @Test func wantedHeightAddsTheInsets() {
        #expect(SheetFit.wantedHeight(contentHeight: 200, topInset: 56, bottomInset: 34) == 290, "A measure that is not a detent counts every inset")
        #expect(SheetFit.wantedHeight(contentHeight: -5, topInset: -1, bottomInset: 34) == 34)
    }

    /// Owner, 2026-10-28 (`proposals/sheet-bottom-gap`, option B): UIKit measures a custom detent up from the bottom safe area and adds
    /// that area itself (a detent of 479 was a 513 pt sheet on the folded Duo), so the detent leaves the safe area out.
    @Test func aDetentDoesNotAskForTheBottomSafeAreaTheSystemAdds() {
        #expect(SheetFit.wantedHeight(contentHeight: 371, topInset: 74, bottomInset: 34, systemBottomInset: 34) == 445, "Upper Deck was 479")
        #expect(SheetFit.wantedHeight(contentHeight: 413, topInset: 70, bottomInset: 34, systemBottomInset: 34) == 483, "Front Door on an iPhone 17 Pro was 517")
        #expect(SheetFit.wantedHeight(contentHeight: 300, topInset: 64, bottomInset: 20, systemBottomInset: 20) == 364, "An iPad's safe area is 20")
    }

    @Test func aBottomInsetBeyondTheSafeAreaStaysInTheDetent() {
        // A pinned bar under the content is not the home indicator: the system does not add it.
        #expect(SheetFit.bottomBeyondSafeArea(inset: 94, safeArea: 34) == 60)
        #expect(SheetFit.bottomBeyondSafeArea(inset: 34, safeArea: 34) == 0)
        #expect(SheetFit.bottomBeyondSafeArea(inset: 20, safeArea: 34) == 0, "Never negative")
        #expect(SheetFit.bottomBeyondSafeArea(inset: -5, safeArea: -5) == 0)
        #expect(SheetFit.wantedHeight(contentHeight: 200, topInset: 56, bottomInset: 94, systemBottomInset: 34) == 316)
    }

    @Test func horizontalRailsAndTinyContainersAreNotThePageScroller() {
        #expect(SheetFit.isPageScroller(contentWidth: 390, containerWidth: 390, containerHeight: 700))
        #expect(!SheetFit.isPageScroller(contentWidth: 900, containerWidth: 390, containerHeight: 700), "A chip rail scrolls sideways")
        #expect(!SheetFit.isPageScroller(contentWidth: 390, containerWidth: 390, containerHeight: 60), "A small carousel")
    }

    // MARK: - The channel

    @Test func theFirstPageOwnsTheSheetHeight() {
        var accepted: [CGFloat] = []
        let model = SheetFitModel { accepted.append($0) }
        let root = UUID(), pushed = UUID()
        model.report(320, from: root)
        model.report(900, from: pushed)
        #expect(model.contentHeight == 320, "A pushed page must not resize the sheet")
        model.report(380, from: root)
        #expect(model.contentHeight == 380, "The root page's content change resizes it")
        #expect(accepted == [320, 380])
    }

    @Test func aSheetThatFollowsItsTopPageFitsEachPageAndBackRestoresTheRoot() {
        // Quick Links (owner, 2026-10-26): the tiles, then Rooms pushed, then Back.
        var remembered: [CGFloat] = []
        let model = SheetFitModel(followsTopPage: true) { remembered.append($0) }
        let root = UUID(), rooms = UUID()
        model.pageAppeared(root)
        model.report(380, from: root)
        #expect(model.contentHeight == 380)
        model.report(760, from: rooms) // laid out before it appears
        #expect(model.contentHeight == 380, "Not the owner until it is on screen")
        model.pageAppeared(rooms)
        #expect(model.contentHeight == 760, "The pushed page fits the sheet to its own content")
        model.report(770, from: rooms)
        #expect(model.contentHeight == 770, "And keeps fitting it while on top")
        model.pageAppeared(root)
        #expect(model.contentHeight == 380, "Back returns to the root's height without a new reading")
        #expect(remembered == [380, 380], "Only the root's heights are remembered for the next presentation")
    }

    @Test func aPushedPageWithoutAReadingKeepsTheHeight() {
        let model = SheetFitModel(followsTopPage: true)
        let root = UUID()
        model.pageAppeared(root)
        model.report(380, from: root)
        model.pageAppeared(UUID())
        #expect(model.contentHeight == 380)
    }

    @Test func theDefaultModeIgnoresAppearances() {
        let model = SheetFitModel()
        let root = UUID(), pushed = UUID()
        model.pageAppeared(root)
        model.report(320, from: root)
        model.pageAppeared(pushed)
        model.report(900, from: pushed)
        #expect(model.contentHeight == 320)
    }

    @Test func aPhoneFitsToItsContentAndSafeAreasNotItsOwnHeight() {
        // The bathroom fan sheet's trace (iPhone 17 Pro, 2026-10-17): content 328, a 314 pt scroller that did not grow with
        // the sheet, safe areas 70 and 34. Counting the sheet's own height asked for 14 pt more each time, up to large.
        let model = SheetFitModel()
        model.setSafeInsets(top: 70, bottom: 34)
        for sheet: CGFloat in [451, 465, 479, 778] {
            model.setSheetHeight(sheet)
            model.report(SheetFit.Reading(content: 328, viewport: 314), from: UUID())
        }
        #expect(model.contentHeight == 432, "Content plus the safe areas, however tall the sheet is")
    }

    @Test func aRegularWidthSheetCountsItsHeaderBelowTheScroller() {
        // An iPad form sheet whose scroller sits below a 90 pt header and reports no top inset.
        let pad = SheetFitModel()
        pad.usesSheetEstimate = true
        pad.setSheetHeight(500)
        pad.report(SheetFit.Reading(content: 300, viewport: 410), from: UUID())
        #expect(pad.contentHeight == 390)
        let phone = SheetFitModel()
        phone.setSheetHeight(500)
        phone.report(SheetFit.Reading(content: 300, viewport: 410), from: UUID())
        #expect(phone.contentHeight == 300, "A phone does not use the sheet estimate")
    }

    @Test func aRememberedHeightIsTheStartingPoint() {
        let model = SheetFitModel(initial: 410)
        #expect(model.contentHeight == 410)
        model.report(411, from: UUID())
        #expect(model.contentHeight == 410, "Within hysteresis of the remembered height")
    }

    @Test func memoryIsPerCallSite() {
        SheetFitMemory.reset()
        SheetFitMemory.remember(300, for: "A.swift:10")
        #expect(SheetFitMemory.height(for: "A.swift:10") == 300)
        #expect(SheetFitMemory.height(for: "A.swift:11") == nil)
        SheetFitMemory.reset()
    }

    @Test func theTextSizeKeyIsTheAppsAndMarksAnOverride() {
        let ax5 = "UICTContentSizeCategoryAccessibilityXXXL", large = "UICTContentSizeCategoryL"
        // Shipping app: the window shows the app's own setting.
        #expect(LargeDetent.textSizeName(window: large, app: large) == large)
        #expect(LargeDetent.textSizeName(window: ax5, app: ax5) == ax5)
        // A scene trait override (the UI tests' in-place AX5) is filed apart from both sizes, so an AX5 launch never reads it.
        #expect(LargeDetent.textSizeName(window: ax5, app: large) == ax5 + "|override")
        // No window yet, or an unspecified trait: the app's.
        #expect(LargeDetent.textSizeName(window: nil, app: large) == large)
        #expect(LargeDetent.textSizeName(window: "", app: large) == large)
    }

    @Test func aRememberedHeightSurvivesARelaunchInTheSameContext() throws {
        let suite = try #require(UserDefaults(suiteName: "SheetFitTests.\(UUID().uuidString)"))
        let (oldStore, oldContext) = (SheetFitMemory.store, SheetFitMemory.context)
        defer { SheetFitMemory.store = oldStore; SheetFitMemory.context = oldContext; SheetFitMemory.reset() }
        SheetFitMemory.store = suite
        SheetFitMemory.context = { "build 1|800|large" }
        SheetFitMemory.reset()
        SheetFitMemory.remember(420, for: "B.swift:1")
        SheetFitMemory.dropProcessMemory()
        #expect(SheetFitMemory.height(for: "B.swift:1") == 420, "Read back from disk")
        SheetFitMemory.remember(420, for: "B.swift:1") // unchanged: no write needed
        SheetFitMemory.context = { "build 1|800|AX5" }
        SheetFitMemory.dropProcessMemory()
        #expect(SheetFitMemory.height(for: "B.swift:1") == nil, "A different text size is a different height")
        SheetFitMemory.store = nil
        #expect(SheetFitMemory.height(for: "B.swift:2") == nil)
        SheetFitMemory.remember(300, for: "B.swift:2")
        #expect(SheetFitMemory.height(for: "B.swift:2") == 300, "Without a store the process still remembers")
    }

    @Test func aTallFittedSheetOffersLargeToo() {
        #expect(SheetFit.offersLarge(.provisional, availableHeight: 800), "Unmeasured: expandable, so iOS 17 can see it all")
        #expect(SheetFit.offersLarge(.height(500), availableHeight: 800))
        #expect(!SheetFit.offersLarge(.height(300), availableHeight: 800), "A short sheet stays one detent")
        #expect(!SheetFit.offersLarge(.height(400), availableHeight: 800), "Exactly half is not taller than half")
        #expect(!SheetFit.offersLarge(.large, availableHeight: 800))
        #expect(!SheetFit.offersLarge(.height(500), availableHeight: .nan))
    }

    // MARK: - Edit state

    @Test func confirmNeedsAValidChangedIdleDraft() {
        #expect(SheetEditState.canConfirm(isValid: true, hasChanges: true))
        #expect(!SheetEditState.canConfirm(isValid: true, hasChanges: false), "Nothing changed")
        #expect(!SheetEditState.canConfirm(isValid: false, hasChanges: true), "An empty name")
        #expect(!SheetEditState.canConfirm(isValid: true, hasChanges: true, isBusy: true), "A save in flight")
    }
}

// MARK: - Chrome and prediction

/// What a sheet adds around its content is learned from any fitted sheet with the standard header and remembered without the
/// build; a prediction (owner, 2026-10-26: "Can't we precompute this?") opens a sheet at its final height on its first
/// presentation.
@MainActor
struct SheetChromeTests {
    private func isolated(_ body: () throws -> Void) throws {
        let suite = try #require(UserDefaults(suiteName: "SheetChromeTests.\(UUID().uuidString)"))
        let (oldStore, oldContext) = (SheetChromeMemory.store, SheetChromeMemory.context)
        defer { SheetChromeMemory.store = oldStore; SheetChromeMemory.context = oldContext; SheetChromeMemory.reset() }
        SheetChromeMemory.store = suite
        SheetChromeMemory.context = { "26.5|800|large|compact" }
        SheetChromeMemory.reset()
        try body()
    }

    @Test func chromeIsTheTopAndBottomAroundTheContent() {
        let chrome = SheetChrome(top: 74, bottom: 0)
        #expect(chrome.sheetHeight(forContent: 392) == 466, "Header and content: the safe area is the system's")
        #expect(SheetChrome(top: 74.4, bottom: 0.2).sheetHeight(forContent: 391.6) == 466)
        #expect(SheetChrome(top: 74, bottom: 60).sheetHeight(forContent: 392) == 526, "A pinned bar under the content is the chrome's")
    }

    @Test func theWidthTheyTeachNarrowsTheWindowForAPrediction() throws {
        try isolated {
            #expect(SheetMemory.pageWidth(inWindowOfWidth: 466) == 466, "Nothing learned: the window's width")
            SheetChromeMemory.learn(SheetChrome(top: 74, bottom: 0, widthInset: 16))
            #expect(SheetMemory.pageWidth(inWindowOfWidth: 466) == 450, "The folded Duo lays its page out at the sheet's width")
            SheetChromeMemory.dropProcessMemory()
            #expect(SheetMemory.pageWidth(inWindowOfWidth: 466) == 450, "Read back from disk")
            SheetChromeMemory.learn(SheetChrome(top: 74, bottom: 0, widthInset: 90))
            #expect(SheetMemory.pageWidth(inWindowOfWidth: 466) == 450, "An implausible inset is ignored")
        }
    }

    @Test func nothingLearnedFallsBackToTheDefaults() throws {
        try isolated {
            let fallback = SheetChromeMemory.fallback()
            #expect(SheetChromeMemory.current() == fallback)
            #expect(fallback.top == SheetChromeMemory.defaultTop())
            #expect(fallback.top >= 60 && fallback.top <= 90, "A documented per-system header height")
        }
    }

    @Test func aLearnedChromeReplacesTheFallbackAndSurvivesARelaunch() throws {
        try isolated {
            SheetChromeMemory.learn(SheetChrome(top: 71, bottom: 0))
            #expect(SheetChromeMemory.current() == SheetChrome(top: 71, bottom: 0))
            SheetChromeMemory.dropProcessMemory()
            #expect(SheetChromeMemory.current() == SheetChrome(top: 71, bottom: 0), "Read back from disk")
        }
    }

    @Test func chromeIsKeyedWithoutTheBuildButWithTheSystemTextSizeAndWidth() throws {
        try isolated {
            SheetChromeMemory.learn(SheetChrome(top: 71, bottom: 0))
            // A new build changes the heights table's context, not this one.
            let (oldHeights) = SheetFitMemory.context
            defer { SheetFitMemory.context = oldHeights }
            SheetFitMemory.context = { "build 999|800|large" }
            #expect(SheetChromeMemory.current() == SheetChrome(top: 71, bottom: 0), "A new build does not forget the chrome")
            for other in ["27.0|800|large|compact", "26.5|700|large|compact", "26.5|800|AX5|compact", "26.5|800|large|regular"] {
                SheetChromeMemory.context = { other }
                #expect(SheetChromeMemory.current() == SheetChromeMemory.fallback(), "\(other) learns for itself")
            }
        }
    }

    @Test func theRealContextHasNoBuildNumber() {
        // system | large detent | text size | width class
        #expect(SheetChromeMemory.context().split(separator: "|").count == 4)
    }

    @Test func anImplausibleChromeIsNotLearned() throws {
        try isolated {
            SheetChromeMemory.learn(SheetChrome(top: 0, bottom: 0))
            SheetChromeMemory.learn(SheetChrome(top: 150, bottom: 0))
            SheetChromeMemory.learn(SheetChrome(top: 74, bottom: 90))
            #expect(SheetChromeMemory.current() == SheetChromeMemory.fallback())
        }
    }

    @Test func aPredictionWinsOverARememberedHeight() throws {
        try isolated {
            SheetChromeMemory.learn(SheetChrome(top: 74, bottom: 0))
            #expect(SheetFitStart.height(predictedContent: 392, remembered: 410) == 466)
            #expect(SheetFitStart.height(predictedContent: nil, remembered: 410) == 410, "No prediction: the remembered height")
            #expect(SheetFitStart.height(predictedContent: nil, remembered: nil) == nil, "Neither: measure after it appears")
            #expect(SheetFitStart.height(predictedContent: .nan, remembered: 410) == 410)
            #expect(SheetFitStart.height(predictedContent: 0, remembered: 410) == 410)
        }
    }

    @Test func aPredictionBeforeAnythingIsLearnedUsesTheFallbackChrome() throws {
        try isolated {
            let expected = SheetChromeMemory.fallback().sheetHeight(forContent: 300)
            #expect(SheetFitStart.height(predictedContent: 300, remembered: nil) == expected)
        }
    }

    @Test func aPredictionWithinHysteresisOfTheMeasurementDoesNotMoveTheSheet() {
        let model = SheetFitModel(initial: 466)
        model.systemBottomInset = 34
        model.setSafeInsets(top: 74, bottom: 34)
        model.report(SheetFit.Reading(content: 393), from: UUID())
        #expect(model.contentHeight == 466, "A point off is inside the 2 pt hysteresis")
        model.report(SheetFit.Reading(content: 380), from: UUID())
        #expect(model.contentHeight == 466, "Only the first page reports")
    }

    @Test func clearingAllForgetsHeightsAndChromeInMemoryAndOnDisk() throws {
        let heights = try #require(UserDefaults(suiteName: "SheetChromeTests.\(UUID().uuidString)"))
        let chromes = try #require(UserDefaults(suiteName: "SheetChromeTests.\(UUID().uuidString)"))
        let (oldHeights, oldChromes) = (SheetFitMemory.store, SheetChromeMemory.store)
        let (heightContext, chromeContext) = (SheetFitMemory.context, SheetChromeMemory.context)
        defer {
            SheetFitMemory.store = oldHeights; SheetChromeMemory.store = oldChromes
            SheetFitMemory.context = heightContext; SheetChromeMemory.context = chromeContext
            SheetMemory.clearAll()
        }
        SheetFitMemory.store = heights
        SheetChromeMemory.store = chromes
        SheetFitMemory.context = { "build 1|800|large" }
        SheetChromeMemory.context = { "26.5|800|large|compact" }
        SheetMemory.clearAll()
        SheetFitMemory.remember(420, for: "A.swift:1")
        SheetChromeMemory.learn(SheetChrome(top: 71, bottom: 0))
        #expect(SheetFitMemory.height(for: "A.swift:1") == 420)
        SheetMemory.clearAll()
        SheetFitMemory.dropProcessMemory()
        SheetChromeMemory.dropProcessMemory()
        #expect(SheetFitMemory.height(for: "A.swift:1") == nil, "Cleared on disk too")
        #expect(SheetChromeMemory.current() == SheetChromeMemory.fallback(), "Chrome is back to the fallback")
        #expect(heights.dictionary(forKey: SheetFitMemory.storeKey) == nil)
        #expect(chromes.dictionary(forKey: SheetChromeMemory.storeKey) == nil)
    }

    @Test func aPredictedSheetIgnoresTransientReadingsWhileItPresents() async throws {
        // The camera viewer read 569, 517, 551 ... 518 pt on the way to its predicted 517 (iPhone 17 Pro, iOS 26.5).
        let model = SheetFitModel(initial: 483, settleDelay: .milliseconds(60))
        model.systemBottomInset = 34
        let page = UUID()
        model.setSafeInsets(top: 70, bottom: 34)
        for content: CGFloat in [465, 413, 447, 443, 426, 414] {
            model.report(SheetFit.Reading(content: content), from: page)
        }
        try await Task.sleep(for: .milliseconds(150))
        #expect(model.contentHeight == 483, "The last reading stood within hysteresis: the sheet never moved")
    }

    @Test func aPredictedSheetStillCorrectsAWrongPredictionOnceReadingsStandStill() async throws {
        var accepted: [CGFloat] = []
        let model = SheetFitModel(initial: 483, settleDelay: .milliseconds(60)) { accepted.append($0) }
        model.systemBottomInset = 34
        let page = UUID()
        model.setSafeInsets(top: 70, bottom: 34)
        model.report(SheetFit.Reading(content: 380), from: page)
        #expect(model.contentHeight == 483, "Not yet: the reading has not stood still")
        // Wait for the delayed accept rather than a fixed sleep: parallel suites can keep the main actor busy past it (a hosted
        // runner starved it for over 2 s). The poll returns the moment the condition holds; the deadline only bounds a real failure.
        let deadline = ContinuousClock.now + .seconds(30)
        while model.contentHeight != 450, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        #expect(model.contentHeight == 450)
        #expect(accepted == [450])
    }

    @Test func anUnpredictedSheetFollowsAReadingAtOnce() {
        let model = SheetFitModel()
        model.systemBottomInset = 34
        model.setSafeInsets(top: 70, bottom: 34)
        model.report(SheetFit.Reading(content: 380), from: UUID())
        #expect(model.contentHeight == 450)
    }

    @Test func theModelKeepsTheRootWidth() {
        let model = SheetFitModel()
        model.setSafeInsets(top: 74, bottom: 34)
        model.report(SheetFit.Reading(content: 300, width: 450), from: UUID())
        #expect(model.rootWidth == 450)
    }

    @Test func aWrongPredictionIsCorrectedByTheMeasurement() {
        let model = SheetFitModel(initial: 470)
        model.systemBottomInset = 34
        let page = UUID()
        model.setSafeInsets(top: 74, bottom: 34)
        model.report(SheetFit.Reading(content: 420), from: page)
        #expect(model.contentHeight == 494)
    }

    @Test func theRootPageTeachesTheChromeWhenItHasTheStandardHeader() {
        let model = SheetFitModel()
        model.systemBottomInset = 34
        let root = UUID(), pushed = UUID()
        #expect(model.rootChrome == nil)
        model.setSafeInsets(top: 74, bottom: 34)
        model.report(SheetFit.Reading(content: 392), from: root)
        #expect(model.rootChrome == SheetChrome(top: 74, bottom: 0), "The home indicator is the system's, not the chrome's")
        model.setSafeInsets(top: 100, bottom: 34)
        model.report(SheetFit.Reading(content: 200, topInset: 100), from: pushed)
        #expect(model.rootChrome == SheetChrome(top: 100, bottom: 0), "Safe insets are shared; the readings still come from the root")
    }

    @Test func aPageWithATopBarDoesNotTeachTheChrome() {
        let model = SheetFitModel()
        model.systemBottomInset = 34
        let root = UUID()
        model.setStandardHeader(false, for: root)
        model.setSafeInsets(top: 130, bottom: 34)
        model.report(SheetFit.Reading(content: 392), from: root)
        #expect(model.rootChrome == nil)
        model.setStandardHeader(true, for: root)
        #expect(model.rootChrome == SheetChrome(top: 130, bottom: 0))
    }

    @Test func theChromeUsesTheLargerOfTheScrollerInsetAndTheSafeArea() {
        let model = SheetFitModel()
        model.setSafeInsets(top: 62, bottom: 34)
        model.report(SheetFit.Reading(content: 300, topInset: 74, bottomInset: 20), from: UUID())
        #expect(model.rootChrome == SheetChrome(top: 74, bottom: 34), "Without a system inset every inset is the chrome's")
        model.systemBottomInset = 34
        #expect(model.rootChrome == SheetChrome(top: 74, bottom: 0), "A model told the system's safe area leaves it out")
    }

    // MARK: Stored by an older build

    /// The chrome and the heights an older build stored counted the bottom safe area in the detent (a chrome of 74 / 34, a camera sheet
    /// of 517). Reused, they would open every sheet 34 pt too tall and then move it, so they are stored under new keys and the old
    /// tables are never read.
    @Test func aChromeAndHeightsStoredByTheOlderBuildAreNotReused() throws {
        try isolated {
            let store = try #require(SheetChromeMemory.store)
            #expect(SheetChromeMemory.storeKey != SheetChromeMemory.legacyStoreKey && SheetFitMemory.storeKey != SheetFitMemory.legacyStoreKey)
            store.set([SheetChromeMemory.context(): [74.0, 34.0, 16.0]], forKey: SheetChromeMemory.legacyStoreKey)
            SheetChromeMemory.dropProcessMemory()
            #expect(SheetChromeMemory.current() == SheetChromeMemory.fallback(), "The old chrome (bottom 34) is not the chrome")
            #expect(!SheetChromeMemory.isLearned)

            let (oldHeights, oldContext) = (SheetFitMemory.store, SheetFitMemory.context)
            defer { SheetFitMemory.store = oldHeights; SheetFitMemory.context = oldContext; SheetFitMemory.reset() }
            SheetFitMemory.store = store
            SheetFitMemory.context = { "build 1|800|large" }
            SheetFitMemory.reset()
            store.set(["A.swift:1|build 1|800|large": 517.0], forKey: SheetFitMemory.legacyStoreKey)
            SheetFitMemory.dropProcessMemory()
            #expect(SheetFitMemory.height(for: "A.swift:1") == nil, "The old height (517, with the safe area) is not remembered")
        }
    }

    @Test func theOlderTablesAreRemovedAtLaunchAndWhenEverythingIsCleared() throws {
        let store = try #require(UserDefaults(suiteName: "SheetChromeTests.\(UUID().uuidString)"))
        store.set(["x": 1.0], forKey: SheetFitMemory.legacyStoreKey)
        store.set(["x": [1.0]], forKey: SheetChromeMemory.legacyStoreKey)
        SheetFitStorage.removeLegacyTables(from: store)
        #expect(store.object(forKey: SheetFitMemory.legacyStoreKey) == nil && store.object(forKey: SheetChromeMemory.legacyStoreKey) == nil)
        UserDefaults.standard.set(["x": 1.0], forKey: SheetFitMemory.legacyStoreKey)
        SheetMemory.clearAll()
        #expect(UserDefaults.standard.object(forKey: SheetFitMemory.legacyStoreKey) == nil)
    }

    // MARK: Maximum height

    @Test func theMaximumSheetHeightIsLearnedPerContextAndSurvivesARelaunch() throws {
        try isolated {
            #expect(SheetChromeMemory.maxSheetHeight == nil)
            SheetChromeMemory.learnMaxSheetHeight(588)
            #expect(SheetChromeMemory.maxSheetHeight == 588)
            SheetChromeMemory.dropProcessMemory()
            #expect(SheetChromeMemory.maxSheetHeight == 588, "Read back from disk")
            SheetChromeMemory.context = { "27.1|678|large|compact" }
            #expect(SheetChromeMemory.maxSheetHeight == nil, "Another window size learns for itself")
            SheetChromeMemory.learnMaxSheetHeight(0)
            SheetChromeMemory.learnMaxSheetHeight(.infinity)
            #expect(SheetChromeMemory.maxSheetHeight == nil, "A reading that is no sheet is not learned")
        }
    }

    @Test func isLearnedFollowsTheChromeOnly() throws {
        try isolated {
            #expect(!SheetChromeMemory.isLearned)
            SheetChromeMemory.learnMaxSheetHeight(588)
            #expect(!SheetChromeMemory.isLearned, "The maximum is not the chrome")
            SheetChromeMemory.learn(SheetChrome(top: 74, bottom: 0, widthInset: 16))
            #expect(SheetChromeMemory.isLearned)
            SheetChromeMemory.dropProcessMemory()
            #expect(SheetChromeMemory.isLearned, "Also from disk")
        }
    }

    @Test func clearingAllForgetsTheMaximumToo() {
        SheetChromeMemory.learnMaxSheetHeight(588)
        SheetMemory.clearAll()
        #expect(SheetChromeMemory.maxSheetHeight == nil)
        #expect(UserDefaults.standard.object(forKey: SheetChromeMemory.maxStoreKey) == nil)
    }

    /// The folded iPhone Duo (iOS 27.1), measured 2026-10-26: Front Door asks for 565 pt in a sheet whose page area can be 554
    /// pt at most (a 588 pt sheet); its header then reads 82 pt, not the 74 of every other sheet, so the measured height
    /// is 8 pt more than the prediction of 557 and the sheet cannot show any of it.
    @Test func aSheetAlreadyAsTallAsTheSystemAllowsDoesNotMoveForATallerReading() {
        let model = SheetFitModel(initial: 586)
        model.systemBottomInset = 34
        model.maxSheetHeight = 554
        model.setSheetHeight(554)
        model.setSafeInsets(top: 82, bottom: 34)
        model.report(SheetFit.Reading(content: 512, viewport: 472, topInset: 82, bottomInset: 34, width: 450), from: UUID())
        #expect(model.contentHeight == 586, "594 would be a detent move that changes nothing on screen")
    }

    @Test func aSheetTheSystemCutShortDoesNotGrowEvenBeforeAnyMaximumIsLearned() {
        let model = SheetFitModel(initial: 586)
        model.systemBottomInset = 34
        model.setSheetHeight(554)
        model.setSafeInsets(top: 82, bottom: 34)
        model.report(SheetFit.Reading(content: 512, viewport: 472, topInset: 82, bottomInset: 34, width: 450), from: UUID())
        #expect(model.contentHeight == 586, "Given 554 of the 586 asked: the 594 reading cannot make it taller")
    }

    @Test func aSheetAtItsMaximumStillShrinksForAShorterPage() {
        let model = SheetFitModel(initial: 557)
        model.systemBottomInset = 34
        model.maxSheetHeight = 554
        let page = UUID()
        model.setSafeInsets(top: 74, bottom: 34)
        model.report(SheetFit.Reading(content: 300, width: 450), from: page)
        #expect(model.contentHeight == 374)
    }

    @Test func aSheetBelowItsMaximumGrowsForATallerReading() {
        let model = SheetFitModel(initial: 400)
        model.systemBottomInset = 34
        model.maxSheetHeight = 554
        model.setSafeInsets(top: 74, bottom: 34)
        model.report(SheetFit.Reading(content: 440, width: 450), from: UUID())
        #expect(model.contentHeight == 514)
    }

    @Test func withNoMaximumLearnedAReadingMovesTheSheetAsBefore() {
        // The folded Duo's Front Door: 565 asked for (it counted the home indicator), 531 now, which the 554 pt page area holds.
        let model = SheetFitModel(initial: 523)
        model.systemBottomInset = 34
        model.setSafeInsets(top: 82, bottom: 34)
        model.report(SheetFit.Reading(content: 449, width: 450), from: UUID())
        #expect(model.contentHeight == 531)
    }

    @Test func aRegularWidthSheetIsNotHeldToThePhoneMaximum() {
        let model = SheetFitModel(initial: 557)
        model.maxSheetHeight = 554
        model.usesSheetEstimate = true
        model.systemBottomInset = 20
        model.setSafeInsets(top: 74, bottom: 20)
        model.report(SheetFit.Reading(content: 500, width: 450), from: UUID())
        #expect(model.contentHeight == 574)
    }

    @Test func aSheetThatKeepsGrowingAtItsMaximumSettlesInsteadOfOscillating() {
        // The lab sheet at 620 and 628 pt on the Duo flipped between a 74 and an 82 pt header 22 times: each reading
        // was 8 pt from the other, both past the 588 pt maximum.
        var accepted: [CGFloat] = []
        let model = SheetFitModel(initial: 586) { accepted.append($0) }
        model.systemBottomInset = 34
        model.maxSheetHeight = 554
        let page = UUID()
        for top: CGFloat in [82, 74, 82, 74, 82] {
            model.setSafeInsets(top: top, bottom: 34)
            model.report(SheetFit.Reading(content: 512, width: 450), from: page)
        }
        #expect(accepted.isEmpty && model.contentHeight == 586, "Neither the 594 nor the 586 moves a sheet at its maximum")
    }

    // MARK: What a sheet teaches

    @Test func aSheetTheSystemCutShortIsFlaggedSoItsHeaderIsNotTaughtAsTheChrome() {
        // Its header reads 82, not 74, because the sheet is pinned under the status area.
        let model = SheetFitModel(initial: 586)
        model.systemBottomInset = 34
        model.setSheetHeight(554)
        model.setSafeInsets(top: 82, bottom: 34)
        model.report(SheetFit.Reading(content: 512, topInset: 82, bottomInset: 34, width: 450), from: UUID())
        #expect(model.rootIsCutShort)
        #expect(model.rootWidth == 450)
    }

    @Test func aCutShortSheetTeachesTheWidthAndBottomButKeepsTheKnownTop() throws {
        try isolated {
            let model = SheetFitModel(initial: 586)
            model.systemBottomInset = 34
            model.setSheetHeight(554)
            model.setSafeInsets(top: 82, bottom: 34)
            model.report(SheetFit.Reading(content: 512, topInset: 82, bottomInset: 34, width: 450), from: UUID())
            SheetChromeMemory.learn(from: model, windowWidth: 466)
            let learned = SheetChromeMemory.current()
            #expect(learned.top == SheetChromeMemory.fallback().top, "82 is the pinned sheet's header, not every sheet's")
            #expect(learned.widthInset == 16 && learned.bottom == 0)
        }
    }

    @Test func aSheetAtTheLargeDetentTeachesTheChromeAndTheMaximumHeight() {
        let model = SheetFitModel()
        model.systemBottomInset = 34
        model.detentIsLarge = true
        model.setSheetHeight(554)
        model.setSafeInsets(top: 74, bottom: 34)
        model.report(SheetFit.Reading(content: 3000, topInset: 74, bottomInset: 34, width: 450), from: UUID())
        #expect(model.rootChrome == SheetChrome(top: 74, bottom: 0) && !model.rootIsCutShort)
        #expect(model.largeSheetHeight == 554)
    }

    @Test func aSheetNotAtLargeReportsNoMaximum() {
        let model = SheetFitModel()
        model.setSheetHeight(369)
        #expect(model.largeSheetHeight == nil)
    }

    /// The folded iPhone Duo (iOS 27.1), measured 2026-10-26 with the probe: a sheet that got the detent it asked for reads
    /// a page area of exactly that detent (Upper Deck 479, Driveway 370), because the page does not extend into the bottom inset.
    /// It used to be compared with the detent plus the inset, so every such sheet read as cut short and taught nothing.
    @Test func aSheetGivenAllItAskedForTeachesItsChrome() {
        let model = SheetFitModel(initial: 335)
        model.systemBottomInset = 34
        model.setSheetHeight(335)
        model.setSafeInsets(top: 74, bottom: 34)
        model.report(SheetFit.Reading(content: 261, viewport: 296, topInset: 74, bottomInset: 34, width: 450), from: UUID())
        #expect(model.rootChrome == SheetChrome(top: 74, bottom: 0))
        #expect(!model.rootIsCutShort)
    }

    /// The reported bug: without a warm-up, the first camera sheet on the folded Duo (Driveway, opened from the fallback chrome)
    /// taught nothing, so the second (Upper Deck, 16:9) opened at the fallback prediction (484) and moved to 479.
    @Test func theFirstSheetTeachesTheSecondItsExactHeight() throws {
        try isolated {
            SheetChromeMemory.context = { "27.1|668|L|compact" }
            // Driveway: predicted from the fallback chrome (top 70, width 466), opens at 335, is given 335 and reads 74/34 at 450.
            let driveway = SheetFitModel(initial: 335)
            driveway.systemBottomInset = 34
            driveway.setSheetHeight(335)
            driveway.setSafeInsets(top: 74, bottom: 34)
            driveway.report(SheetFit.Reading(content: 261, viewport: 296, topInset: 74, bottomInset: 34, width: 450), from: UUID())
            SheetChromeMemory.learn(from: driveway, windowWidth: 466)
            #expect(SheetChromeMemory.isLearned)
            #expect(SheetChromeMemory.current() == SheetChrome(top: 74, bottom: 0, widthInset: 16))
            // Upper Deck: the page is laid out 16 pt narrower, so its content is 371, and the sheet opens at its final 445.
            #expect(SheetMemory.pageWidth(inWindowOfWidth: 466) == 450)
            #expect(SheetFitStart.height(predictedContent: 371, remembered: nil) == 445)
        }
    }
}
