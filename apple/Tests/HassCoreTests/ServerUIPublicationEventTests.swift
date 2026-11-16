import Foundation
import Testing
@testable import HassCore

@Suite struct ServerUIPublicationEventTests {
    private typealias F = ServerUIPublicationFixtures

    @Test func aPublishedReplyBecomesACompiledPublicationWithTheIntegrationsOrdering() throws {
        guard case let .published(value) = try F.event(epoch: "e", revision: 7) else { Issue.record("not published"); return }
        #expect(value.epoch == "e")
        #expect(value.revision == 7)
        #expect(value.envelopeSha256.count == 64)
        #expect(value.publication.document.id.isEmpty == false)
        #expect(try ServerUICompositionPublication.decode(value.bytes) == value.publication)
    }

    @Test func unpublishedAndIncompatibleRepliesCarryTheirFields() throws {
        guard case .unpublished = ServerUIPublicationEvent.judge(.success(try F.reply(["state": "unpublished"]))) else {
            Issue.record("not unpublished"); return
        }
        let reply = try F.reply(["state": "incompatible", "epoch": "e", "revision": 4, "missing": ["sh.future@2"]])
        guard case let .incompatible(epoch, revision, missing) = ServerUIPublicationEvent.judge(.success(reply)) else {
            Issue.record("not incompatible"); return
        }
        #expect(epoch == "e" && revision == 4 && missing == ["sh.future@2"])
    }

    @Test func refusedAndMalformedRepliesNeverBecomeAPublication() throws {
        struct Refused: Error {}
        func invalid(_ reply: Result<Data, any Error>) -> ServerUIStoreError? {
            if case let .invalid(error) = ServerUIPublicationEvent.judge(reply) { return error }
            return nil
        }
        #expect(invalid(.failure(Refused())) == .subscription)
        #expect(invalid(.success(Data("not json".utf8))) == .malformedEvent)
        #expect(invalid(.success(try F.reply(["state": "surprise"]))) == .malformedEvent)
        #expect(invalid(.success(try F.reply(["noState": 1]))) == .malformedEvent)
        #expect(invalid(.success(try F.reply(["state": "incompatible", "epoch": "e", "revision": 1]))) == .malformedEvent)
        #expect(invalid(.success(try F.reply(["state": "incompatible", "epoch": "", "revision": 1, "missing": []]))) == .malformedEvent)
        #expect(invalid(.success(try F.reply(["state": "incompatible", "epoch": "e", "revision": -1, "missing": []]))) == .malformedEvent)
        #expect(invalid(.success(try F.reply(["state": "incompatible", "epoch": "e", "revision": true, "missing": []]))) == .malformedEvent)
        #expect(invalid(.success(try F.reply(["state": "incompatible", "epoch": "e", "revision": 1.5, "missing": []]))) == .malformedEvent)
        let badHash = try F.reply(["state": "published", "epoch": "e", "revision": 1, "envelopeSha256": "XYZ",
                                   "envelope": try F.envelope()])
        #expect(invalid(.success(badHash)) == .malformedEvent)
        let noEnvelope = try F.reply(["state": "published", "epoch": "e", "revision": 1, "envelopeSha256": F.sha])
        #expect(invalid(.success(noEnvelope)) == .malformedEvent)
        let notAnEnvelope = try F.reply(["state": "published", "epoch": "e", "revision": 1, "envelopeSha256": F.sha,
                                         "envelope": ["envelopeVersion": "1.0"]])
        guard case .invalid(.composition) = ServerUIPublicationEvent.judge(.success(notAnEnvelope)) else {
            Issue.record("a bad envelope must surface its compiler error"); return
        }
    }
}
