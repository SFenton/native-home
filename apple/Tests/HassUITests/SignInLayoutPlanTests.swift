import CoreGraphics
@testable import HassUI
import Testing

/// Which sign-in layout each window gets, and where its regions sit (`.agents/design/sign-in-layout.md`).
struct SignInLayoutPlanTests {
    private func plan(_ container: CGRect, regular: Bool = true, hinge: CGRect? = nil, accessibility: Bool = false, rtl: Bool = false) -> SignInLayoutPlan {
        SignInLayoutPlan.resolve(container: container, isRegularWidth: regular, hinge: hinge, isAccessibilityText: accessibility, isRightToLeft: rtl)
    }

    @Test func phoneAndPortraitWindowsKeepTheColumn() {
        let phone = plan(CGRect(x: 0, y: 0, width: 402, height: 874), regular: false)
        #expect(!phone.isSplit)
        #expect(phone.form == SignInLayoutPlan.Span(x: 0, width: 402))
        #expect(phone.header == phone.form)
        let pad = plan(CGRect(x: 0, y: 0, width: 834, height: 1210))
        #expect(!pad.isSplit)
        #expect(pad.form == SignInLayoutPlan.Span(x: 187, width: 460), "centred, at most 460 pt")
    }

    @Test func theDecisionReadsTheKeyboardFreeHeight() {
        // iPad 13-inch portrait, 1032 x 1376: a 400 pt keyboard shortens the scroll view to 976, which alone would make it wider than tall.
        let scroll = CGRect(x: 0, y: 0, width: 1032, height: 976)
        #expect(plan(scroll).isSplit, "the keyboard-shortened frame alone would flip to two regions")
        let frame = SignInLayoutPlan.decisionFrame(scroll: scroll, keyboardFreeHeight: 1376)
        #expect(frame == CGRect(x: 0, y: 0, width: 1032, height: 1376), "width and origin from the scroll view, height from the window")
        #expect(!plan(frame).isSplit, "with the keyboard up or down the portrait window keeps the column")
        #expect(plan(frame) == plan(SignInLayoutPlan.decisionFrame(scroll: CGRect(x: 0, y: 0, width: 1032, height: 1376), keyboardFreeHeight: 1376)))
        // A landscape window keeps its split with the keyboard up.
        let wide = SignInLayoutPlan.decisionFrame(scroll: CGRect(x: 0, y: 0, width: 1194, height: 434), keyboardFreeHeight: 834)
        #expect(plan(wide).isSplit)
    }

    @Test func theFoldedDuoColumnFillsTheSafeWidth() {
        // 466 pt window, the system strip takes 84 pt: the scroll view is the 382 pt left of it.
        let folded = plan(CGRect(x: 0, y: 0, width: 382, height: 678), regular: false)
        #expect(!folded.isSplit)
        #expect(folded.form == SignInLayoutPlan.Span(x: 0, width: 382))
    }

    @Test func iPadLandscapeMeetsAtTheMidpoint() {
        let result = plan(CGRect(x: 0, y: 0, width: 1194, height: 834))
        #expect(result.isSplit)
        #expect(result.header == SignInLayoutPlan.Span(x: (596.5 - 460) / 2, width: 460), "centred in the leading region, as wide as the form")
        #expect(result.header.width - 48 == 412, "412 pt of text on the iPad")
        #expect(result.form.width == 460)
        #expect(abs(result.form.x - (597.5 + (596.5 - 460) / 2)) < 0.01, "centred in the trailing region")
    }

    @Test func theUnfoldedDuoLyingFlatSplitsOverTheSafeWidth() {
        let flat = plan(CGRect(x: 0, y: 0, width: 867, height: 669))
        #expect(flat.isSplit)
        #expect(flat.header == SignInLayoutPlan.Span(x: 0, width: 433))
        #expect(flat.form.width == 433, "the form takes its whole region under 460 pt")
        #expect(flat.form.x == 434)
    }

    @Test func thePartlyFoldedDuoSplitsEitherSideOfTheHinge() {
        let hinge = CGRect(x: 455.3, y: 0, width: 40.4, height: 669)
        let partly = plan(CGRect(x: 0, y: 0, width: 867, height: 669), hinge: hinge)
        #expect(partly.isSplit)
        #expect(abs(partly.header.width - 455.3) < 0.01)
        #expect(abs(partly.form.x - 495.7) < 0.01)
        #expect(abs(partly.form.width - 371.3) < 0.01)
    }

    @Test func theUnfoldedDuoInPortraitAndNarrowWindowsKeepTheColumn() {
        #expect(!plan(CGRect(x: 0, y: 0, width: 669, height: 951)).isSplit)
        #expect(!plan(CGRect(x: 0, y: 0, width: 700, height: 500)).isSplit, "halves under 360 pt")
    }

    @Test func anAccessibilityTextSizeAlwaysGetsTheColumn() {
        let result = plan(CGRect(x: 0, y: 0, width: 1194, height: 834), accessibility: true)
        #expect(!result.isSplit)
        #expect(result.form.width == 460)
    }

    @Test func theRegionsSwapInRightToLeft() {
        let left = plan(CGRect(x: 0, y: 0, width: 1194, height: 834))
        let right = plan(CGRect(x: 0, y: 0, width: 1194, height: 834), rtl: true)
        #expect(right.isSplit)
        #expect(abs(right.header.x - (597.5 + (596.5 - 460) / 2)) < 0.01, "the header takes the physical right region")
        #expect(right.form.x == (596.5 - 460) / 2)
    }

    @Test func aColumnMovesOffTheHingeWhereItCrosses() {
        let hinge = CGRect(x: 300, y: 0, width: 40, height: 600)
        let result = plan(CGRect(x: 0, y: 0, width: 640, height: 600), regular: false, hinge: hinge)
        #expect(!result.isSplit)
        #expect(result.form.x + result.form.width <= 300, "the form ends at the band")
    }
}
