import Testing
@testable import HassCore

/// The spoken cue of kept text (`sh.text-keep@1`, options B and C of T-text-keep).
@Suite(.timeLimit(.minutes(1)))
struct ServerUIKeptTextCueTests {
    @Test func aLiveElementSpeaksWhatItAlreadySpoke() {
        #expect(ServerUIKeptTextCue.value(spoken: nil, drawn: "21 degrees", kept: false) == nil)
        #expect(ServerUIKeptTextCue.value(spoken: "on", drawn: "21 degrees", kept: false) == "on")
    }

    @Test func aKeptElementWithNoSpokenValueSpeaksItsTextAndTheCue() {
        #expect(ServerUIKeptTextCue.value(spoken: nil, drawn: "21 degrees", kept: true) == "21 degrees, last known")
    }

    @Test func theCueIsAppendedToAnAuthoredSpokenValueNeverReplacingIt() {
        #expect(ServerUIKeptTextCue.value(spoken: "on, off in 12 minutes", drawn: "On", kept: true) == "on, off in 12 minutes, last known")
    }

    @Test func anElementWhoseTextIsInItsLabelGetsTheCueAsItsValue() {
        #expect(ServerUIKeptTextCue.value(appendingTo: nil, kept: true) == "last known")
        #expect(ServerUIKeptTextCue.value(appendingTo: "Home", kept: true) == "Home, last known")
        #expect(ServerUIKeptTextCue.value(appendingTo: nil, kept: false) == nil)
        #expect(ServerUIKeptTextCue.value(appendingTo: "Home", kept: false) == "Home")
    }

    @Test func theCueIsAppendedOnce() {
        let once = ServerUIKeptTextCue.append(to: "21 degrees")
        #expect(ServerUIKeptTextCue.append(to: once) == once)
        #expect(ServerUIKeptTextCue.value(spoken: once, drawn: "x", kept: true) == once)
    }

    @Test func strippingTheCueGivesTheLiveValueSoAnAnnouncementSeesNoChange() {
        #expect(ServerUIKeptTextCue.stripped("21 degrees, last known") == "21 degrees")
        #expect(ServerUIKeptTextCue.stripped("21 degrees") == "21 degrees")
        #expect(ServerUIKeptTextCue.stripped(nil) == nil)
    }

    @Test func aRealChangeWhileKeptStillDiffersWithTheCueStripped() {
        #expect(ServerUIKeptTextCue.stripped("21 degrees, last known") != ServerUIKeptTextCue.stripped("22 degrees, last known"))
    }
}
