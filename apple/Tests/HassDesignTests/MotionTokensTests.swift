@testable import HassDesign
import SwiftUI
import Testing

/// ``MotionTokens`` (design: `.agents/design/motion.md` §7).
struct MotionTokensTests {
    @Test func tokensHaveTheirSpecifiedValues() {
        #expect(MotionTokens.quick == .easeOut(duration: 0.2))
        #expect(MotionTokens.state == .easeInOut(duration: 0.6))
        #expect(MotionTokens.stateReduced == .easeInOut(duration: 0.2))
        #expect(MotionTokens.standard == .smooth(duration: 0.3))
        #expect(MotionTokens.emphasized == .spring(duration: 0.5, bounce: 0.2))
        #expect(MotionTokens.segment == .snappy(duration: 0.2))
        #expect(MotionTokens.contentFade == .easeInOut(duration: 0.15))
        #expect(MotionTokens.reducedMoment == .easeInOut(duration: 0.35))
        #expect(MotionTokens.arrivalStagger == 0.06)
    }

    @Test func reduceMotionColourFadeIsShorterButStillAFade() {
        #expect(MotionTokens.stateReduced != MotionTokens.state)
        #expect(MotionTokens.stateReduced == .easeInOut(duration: 0.2))
    }

    @Test func theSignInLanesNamesAgreeWithTheTokens() {
        #expect(MotionTokens.quickDuration == 0.2 && MotionTokens.standardDuration == 0.3 && MotionTokens.stateDuration == 0.6)
        #expect(MotionTokens.crossFade == MotionTokens.reducedMoment && MotionTokens.crossFadeDuration == 0.35)
        #expect(MotionTokens.press == .easeOut(duration: 0.12))
        #expect(MotionTokens.Arrival.staggerLimit == 5)
        #expect(MotionTokens.Arrival.slideDistance == 30 && MotionTokens.Arrival.riseDistance == 16)
        #expect(MotionTokens.Intro.formDelay > MotionTokens.Intro.titleDelay && MotionTokens.Intro.titleDelay > MotionTokens.Intro.markDelay)
        #expect(MotionTokens.Intro.markPeak > 1 && MotionTokens.Intro.markStart < 1)
        let curves: [Animation] = [MotionTokens.Intro.glow, MotionTokens.Intro.markRise, MotionTokens.Intro.title, MotionTokens.Intro.form,
                                   MotionTokens.Arrival.lift, MotionTokens.Arrival.backdrop]
        #expect(curves.count == 6)
    }
}
