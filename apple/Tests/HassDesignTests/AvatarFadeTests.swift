import CoreGraphics
import Testing
@testable import HassDesign

/// How a person photo fades in, out and over another (`.agents/design/profile-photos.md`): the layers a view stacks and when it
/// may drop the one that is no longer visible.
struct AvatarFadeTests {
    private func photo(_ owner: String, _ revision: Int = 1) -> AvatarImage {
        let space = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return AvatarImage(context.makeImage()!, owner: owner, revision: revision)
    }

    @Test func aViewCreatedWithAPhotoShowsItAtOnceAndOneWithoutShowsTheInitials() {
        let shown = AvatarFade(image: photo("person.demo_sam"))
        #expect(shown.top != nil && shown.base == nil)
        #expect(shown.topOpacity == 1 && shown.discHidden && shown.isSettled && shown.hairlineOpacity == 1)
        let empty = AvatarFade(image: nil)
        #expect(empty.top == nil && empty.topOpacity == 0 && !empty.discHidden && empty.isSettled && empty.hairlineOpacity == 0)
    }

    @Test func aFirstPhotoFadesInOverTheInitials() {
        var fade = AvatarFade(image: nil)
        let sam = photo("person.demo_sam")
        let r1 = fade.begin(to: sam)
        #expect(r1)
        #expect(fade.top == sam && fade.base == nil && fade.topOpacity == 0, "the new layer exists at 0 before it animates")
        #expect(!fade.isSettled && fade.inFlight)
        fade.reveal()
        #expect(fade.topOpacity == 1)
        let r2 = fade.finish(epoch: fade.epoch)
        #expect(!r2)
        #expect(fade.isSettled && fade.discHidden && fade.base == nil && fade.top == sam)
    }

    @Test func aPhotoGoingAwayFadesOutOntoTheInitialsAndTheDiscComesBackAtOnce() {
        var fade = AvatarFade(image: photo("person.demo_sam"))
        let r3 = fade.begin(to: nil)
        #expect(r3)
        #expect(fade.top != nil && fade.topOpacity == 1 && !fade.discHidden, "the disc is back under the fading photo")
        fade.reveal()
        #expect(fade.topOpacity == 0)
        fade.finish(epoch: fade.epoch)
        #expect(fade.top == nil && fade.isSettled && fade.target == nil)
    }

    @Test func aNewPhotoFadesInOverTheOldOneNeverThroughTheInitials() {
        var fade = AvatarFade(image: photo("person.demo_sam"))
        let next = photo("person.demo_sam", 2)
        let r4 = fade.begin(to: next)
        #expect(r4)
        #expect(fade.base?.revision == 1 && fade.top == next && fade.topOpacity == 0)
        #expect(fade.hairlineOpacity == 1, "the hairline stays while the old photo is underneath")
        fade.reveal()
        fade.finish(epoch: fade.epoch)
        #expect(fade.base == nil && fade.top == next && fade.isSettled)
    }

    @Test func theSamePhotoIsNothingToAnimate() {
        var fade = AvatarFade(image: photo("person.demo_sam"))
        let r5 = fade.begin(to: photo("person.demo_sam"))
        #expect(!r5, "the same person and revision")
        var none = AvatarFade(image: nil)
        let r6 = none.begin(to: nil)
        #expect(!r6)
        #expect(fade.epoch == 0 && none.epoch == 0)
    }

    @Test func aChangeMidFadeIsCoalescedAndBeginsWhenTheFadeEnds() {
        var fade = AvatarFade(image: nil)
        let first = photo("person.demo_sam", 1), second = photo("person.demo_sam", 2), third = photo("person.demo_sam", 3)
        let r7 = fade.begin(to: first)
        #expect(r7)
        let r8 = fade.begin(to: second)
        #expect(!r8, "the fade in flight keeps going")
        let r9 = fade.begin(to: third)
        #expect(!r9, "only the latest waiting change is kept")
        fade.reveal()
        let epoch = fade.epoch
        let r10 = fade.finish(epoch: epoch)
        #expect(r10, "the waiting change has begun: run reveal and finish again")
        #expect(fade.base == first && fade.top == third && fade.epoch == epoch + 1)
        fade.reveal()
        let r11 = fade.finish(epoch: fade.epoch)
        #expect(!r11)
        #expect(fade.top == third && fade.isSettled)
    }

    @Test func aWaitingChangeBackToWhereTheFadeIsHeadingIsDropped() {
        var fade = AvatarFade(image: nil)
        let first = photo("person.demo_sam", 1)
        let r12 = fade.begin(to: first)
        #expect(r12)
        let r13 = fade.begin(to: photo("person.demo_sam", 2))
        #expect(!r13)
        let r14 = fade.begin(to: first)
        #expect(!r14, "back to the target cancels the waiting change")
        fade.reveal()
        let r15 = fade.finish(epoch: fade.epoch)
        #expect(!r15, "nothing was waiting")
        #expect(fade.top == first)
    }

    @Test func aStaleCompletionCannotDropANewerFadesLayers() {
        var fade = AvatarFade(image: photo("person.demo_sam", 1))
        fade.begin(to: photo("person.demo_sam", 2))
        let stale = fade.epoch
        fade.reveal()
        fade.finish(epoch: stale)
        fade.begin(to: photo("person.demo_sam", 3))
        #expect(fade.base != nil)
        let r16 = fade.finish(epoch: stale)
        #expect(!r16, "an older fade's completion does nothing")
        #expect(fade.base != nil && fade.inFlight)
    }

    @Test func nothingIsSettledWhileAFadeIsInFlight() {
        var fade = AvatarFade(image: nil)
        fade.begin(to: photo("person.demo_sam"))
        fade.reveal()
        #expect(!fade.isSettled, "the layers reached their goals but the completion has not run")
    }
}
