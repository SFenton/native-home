import FentonActivityModel
import Foundation
@testable import HassCore
import Testing

@MainActor
struct LiveActivityTokenReporterTests {
    private let now = Date(timeIntervalSince1970: 1_792_249_200)

    private final class Registered: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [String?] = []
        func add(_ value: String?) { lock.withLock { values.append(value) } }
        var all: [String?] { lock.withLock { values } }
    }

    private func make(enabled: Bool = true, webhook: RecordingActivityWebhook? = RecordingActivityWebhook())
        -> (LiveActivityTokenReporter, FakeLiveActivityClient, RecordingActivityWebhook?, Registered) {
        let client = FakeLiveActivityClient(enabled: enabled)
        let registered = Registered()
        let now = now
        let reporter = LiveActivityTokenReporter(client: client, webhook: { webhook }, registerStartToken: { registered.add($0) },
                                                 now: { now })
        return (reporter, client, webhook, registered)
    }

    private let state = HomeActivityState(value: ActivityValue(kind: .countup, startTs: 1_792_248_900))
    private let attributes = HomeActivityAttributes(tag: "job.dryer", title: "Dryer", kind: "dryer", symbol: "dryer", tint: "cleaning")

    @Test func theStartTokenGoesToTheRegistrationAndOffRemovesIt() async {
        let (reporter, client, _, registered) = make()
        reporter.start()
        reporter.start()
        #expect(await eventually { client.isWatching })
        client.emitStartToken("aa01")
        #expect(await eventually { registered.all == ["aa01"] })
        client.setEnabled(false)
        #expect(await eventually { registered.all == ["aa01", nil] })
        client.setEnabled(false)
        client.setEnabled(true)
        #expect(await eventually { registered.all == ["aa01", nil, "aa01"] })
        client.emitStartToken("bb02")
        #expect(await eventually { registered.all.last == "bb02" })
        reporter.stop()
    }

    @Test func aTokenWhileOffIsKeptUntilTheyTurnItOn() async {
        let (reporter, client, _, registered) = make(enabled: false)
        reporter.start()
        #expect(await eventually { client.isWatching })
        client.emitStartToken("cc03")
        client.setEnabled(true)
        #expect(await eventually { registered.all == ["cc03"] })
        reporter.stop()
    }

    @Test func eachActivityReportsItsUpdateTokenForEightHours() async {
        let (reporter, client, webhook, _) = make()
        reporter.start()
        #expect(await eventually { client.isWatching })
        let local = client.startFromPush(attributes: attributes, state: state)
        // The same activity seen twice is followed once.
        reporter.observe(local)
        #expect(await eventually { client.isWatching(activity: local.id) })
        client.emitPushToken(id: local.id, "dd04")
        let expected = RecordingActivityWebhook.Sent.token(tag: "job.dryer", token: "dd04", expiresAt: now.addingTimeInterval(8 * 3600))
        #expect(await eventually { webhook?.sent == [expected] })
        reporter.stop()
    }

    @Test func anActivityAlreadyRunningAtLaunchIsFollowed() async {
        let (reporter, client, webhook, _) = make()
        let existing = client.startFromPush(attributes: attributes, state: state)
        reporter.start()
        #expect(await eventually { client.isWatching(activity: existing.id) })
        client.emitPushToken(id: existing.id, "ee05")
        #expect(await eventually { webhook?.sent.count == 1 })
        reporter.stop()
    }

    @Test func aSwipeAwayDropsTheTokenAndTellsHomeAssistant() async {
        let (reporter, client, webhook, _) = make()
        reporter.start()
        #expect(await eventually { client.isWatching })
        let record = client.startFromPush(attributes: attributes, state: state)
        #expect(await eventually { client.isWatching(activity: record.id) })
        client.emitLifecycle(id: record.id, .dismissed)
        #expect(await eventually { webhook?.sent.count == 2 })
        #expect(webhook?.sent == [.dismissed(tag: "job.dryer"), .event(LiveActivityEventType.dismissed, ["tag": "job.dryer"])])
        reporter.stop()
    }

    @Test func anEndedActivityOnlyDropsTheToken() async {
        let (reporter, client, webhook, _) = make()
        reporter.start()
        #expect(await eventually { client.isWatching })
        let record = client.startFromPush(attributes: attributes, state: state)
        #expect(await eventually { client.isWatching(activity: record.id) })
        client.emitLifecycle(id: record.id, .stale)
        client.emitLifecycle(id: record.id, .ended)
        #expect(await eventually { webhook?.sent == [.dismissed(tag: "job.dryer")] })
        reporter.stop()
    }

    @Test func aNewActivityWithTheSameTagReplacesTheOldOne() async {
        let (reporter, client, webhook, _) = make()
        reporter.start()
        #expect(await eventually { client.isWatching })
        let vacuum = HomeActivityAttributes(tag: "job.vacuum.demo_vacuum_2", title: "Music Room Vacuum", kind: "vacuum")
        let first = client.startFromPush(attributes: vacuum, state: state)
        #expect(await eventually { client.isWatching(activity: first.id) })
        let second = client.startFromPush(attributes: vacuum, state: state)
        #expect(await eventually { client.isWatching(activity: second.id) })
        #expect(await eventually {
            client.calls.contains { if case let .end(id, _, _) = $0 { id == first.id } else { false } }
        })
        let endedIDs = client.calls.compactMap { call -> String? in
            if case let .end(id, _, _) = call { return id }
            return nil
        }
        #expect(endedIDs == [first.id], "only the older card ends")
        for _ in 0..<100 { await Task.yield() }
        #expect(webhook?.sent.isEmpty == true, "the token the new card shares is not dropped")
        reporter.stop()
    }

    @Test func endingEveryActivityLocallyTellsHomeAssistantAboutEach() async {
        let (reporter, client, webhook, _) = make()
        reporter.start()
        #expect(await eventually { client.isWatching })
        let first = client.startFromPush(attributes: attributes, state: state)
        let second = client.startFromPush(attributes: HomeActivityAttributes(tag: "job.fan.demo_guest", title: "Guest Bath Fan", kind: "fan"), state: state)
        #expect(await eventually { client.isWatching(activity: first.id) && client.isWatching(activity: second.id) })
        await reporter.endAll()
        #expect(webhook?.sent == [.dismissed(tag: "job.dryer"), .dismissed(tag: "job.fan.demo_guest")], "one report per card, and no swipe-away event")
        let ended = client.calls.compactMap { call -> LiveActivityDismissal? in
            if case let .end(_, _, dismissal) = call { return dismissal }
            return nil
        }
        #expect(ended == [.immediate, .immediate])
        for _ in 0..<100 { await Task.yield() }
        #expect(webhook?.sent.count == 2, "the lifecycle watchers do not report the same ends again")
    }

    @Test func endingEverythingWithoutARegistrationStillEndsTheCards() async {
        let (reporter, client, _, _) = make(webhook: nil)
        _ = client.startFromPush(attributes: attributes, state: state)
        await reporter.endAll()
        #expect(client.calls.count == 1)
    }

    @Test func nothingIsSentWithoutARegistration() async {
        let (reporter, client, _, _) = make(webhook: nil)
        reporter.start()
        #expect(await eventually { client.isWatching })
        let record = client.startFromPush(attributes: attributes, state: state)
        #expect(await eventually { client.isWatching(activity: record.id) })
        client.emitPushToken(id: record.id, "ff06")
        client.emitLifecycle(id: record.id, .dismissed)
        // Nothing to assert on a send that never happens; the watchers finish without one.
        for _ in 0..<100 { await Task.yield() }
        reporter.stop()
    }
}

struct HomeActivityActionHandlerTests {
    private let now = Date(timeIntervalSince1970: 1_792_249_200.7)
    private let attributes = HomeActivityAttributes(tag: "job.fan.demo_guest", title: "Guest Bath Fan", kind: "fan", symbol: "fan", tint: "air")
    private let state = HomeActivityState(value: ActivityValue(kind: .countdown, startTs: 1_792_248_900, endTs: 1_792_249_482),
                                          controls: [ActivityControl(id: "stop", title: "Stop", role: .primary)])

    private func make(webhook: RecordingActivityWebhook? = RecordingActivityWebhook(), timeout: Duration = .seconds(10))
        -> (HomeActivityActionHandler, FakeLiveActivityClient, RecordingActivityWebhook?, LiveActivityRecord) {
        let client = FakeLiveActivityClient()
        let record = client.startFromPush(attributes: attributes, state: state, relevanceScore: 77)
        let now = now
        return (HomeActivityActionHandler(client: client, webhook: { webhook }, now: { now }, timeout: timeout), client, webhook, record)
    }

    @Test func aControlWritesThePendingStateThenFiresTheEvent() async {
        let (handler, client, webhook, record) = make()
        #expect(await handler.handle(.control(tag: "job.fan.demo_guest", control: "stop")))
        let updated = client.activities[0].state
        #expect(updated.pending == ActivityPending(control: "stop", label: "Stopping…", sinceTs: 1_792_249_200))
        #expect(client.calls == [.update(id: record.id, updated, staleDate: Date(timeIntervalSince1970: 1_792_249_220), relevanceScore: 77,
                                         timestamp: Date(timeIntervalSince1970: 1_792_249_200))])
        #expect(webhook?.sent == [.event(LiveActivityEventType.action, ["tag": "job.fan.demo_guest", "job": "fan.demo_guest", "control": "stop"])])
    }

    @Test func theTimestampIsAWholeSecondNeverInTheFuture() async {
        let (handler, client, _, _) = make()
        _ = await handler.handle(.control(tag: "job.fan.demo_guest", control: "stop"))
        guard case let .update(_, _, staleDate, _, timestamp) = client.calls[0] else { Issue.record("no update"); return }
        #expect(timestamp.timeIntervalSince1970 == timestamp.timeIntervalSince1970.rounded(.down))
        #expect(timestamp <= now)
        #expect(staleDate == timestamp.addingTimeInterval(20))
    }

    @Test func aFailedControlWritesTheContentBackWithANotice() async {
        let (handler, client, webhook, _) = make()
        webhook?.fails = true
        #expect(await handler.handle(.control(tag: "job.fan.demo_guest", control: "stop")) == false)
        let restored = client.activities[0].state
        #expect(restored.pending == nil && restored.notice == "Couldn't reach Home" && restored.offers(control: "stop"))
        guard case let .update(_, _, staleDate, relevance, timestamp) = client.calls[1] else { Issue.record("no restore"); return }
        #expect(staleDate == nil && relevance == 77 && timestamp >= Date(timeIntervalSince1970: 1_792_249_200) && timestamp <= now)
        let noRegistration = make(webhook: nil)
        #expect(await noRegistration.0.handle(.control(tag: "job.fan.demo_guest", control: "stop")) == false)
        #expect(noRegistration.1.activities[0].state.notice == "Couldn't reach Home")
    }

    @Test func aWebhookThatNeverAnswersTimesOut() async {
        let (handler, client, webhook, _) = make(timeout: .milliseconds(30))
        webhook?.delay = .seconds(5)
        #expect(await handler.handle(.control(tag: "job.fan.demo_guest", control: "stop")) == false)
        #expect(client.activities[0].state.notice == "Couldn't reach Home")
    }

    @Test func anUnknownControlOrActivityIsRefused() async {
        let (handler, client, webhook, _) = make()
        #expect(await handler.handle(.control(tag: "job.fan.demo_guest", control: "launch")) == false)
        #expect(await handler.handle(.control(tag: "job.fan.master", control: "stop")) == false)
        #expect(client.calls.isEmpty && webhook?.sent.isEmpty == true, "nothing was changed or sent")
    }

    @Test func anEndedActivityIsNotWritten() async {
        let (handler, client, _, record) = make()
        client.emitLifecycle(id: record.id, .ended)
        #expect(await handler.handle(.control(tag: "job.fan.demo_guest", control: "stop")) == false)
        #expect(client.calls.isEmpty)
    }

    @Test func theActionHasItsTag() {
        #expect(LiveActivityAction.control(tag: "job.dryer", control: "x").tag == "job.dryer")
    }
}

struct LiveActivityWebhookTests {
    private let server = HassServer(baseURL: URL(string: "https://ha.example.com")!)

    private func sender(_ transport: StubHTTPTransport) -> MobileAppLiveActivityWebhook {
        MobileAppLiveActivityWebhook(client: MobileAppWebhookClient(
            source: FixedMobileAppWebhookSource(MobileAppWebhook(server: server, webhookID: "hook1")), transport: transport))
    }

    private func body(_ transport: StubHTTPTransport, _ index: Int = 0) throws -> [String: Any] {
        let data = try #require(transport.requests[index].httpBody)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func tokensDismissalsAndEventsAreMobileAppWebhookCommands() async throws {
        let transport = StubHTTPTransport([(200, "{}"), (200, "{}"), (200, "{}")])
        let sender = sender(transport)
        try await sender.reportToken(tag: "fenton-home", token: "ab12", expiresAt: Date(timeIntervalSince1970: 1_792_278_000))
        try await sender.reportDismissed(tag: "fenton-home")
        try await sender.fireEvent(LiveActivityEventType.action, data: ["tag": "fenton-home", "job": "dishwasher", "control": "stop"])
        #expect(transport.requests.allSatisfy { $0.url?.path == "/api/webhook/hook1" })

        let token = try body(transport, 0)
        #expect(token["type"] as? String == "live_activity_token")
        let tokenData = try #require(token["data"] as? [String: Any])
        #expect(tokenData["tag"] as? String == "fenton-home" && tokenData["push_token"] as? String == "ab12")
        #expect(tokenData["expires_at"] as? Double == 1_792_278_000)

        let dismissed = try body(transport, 1)
        #expect(dismissed["type"] as? String == "live_activity_dismissed")
        #expect((dismissed["data"] as? [String: Any])?["tag"] as? String == "fenton-home")

        let event = try body(transport, 2)
        #expect(event["type"] as? String == "fire_event")
        let eventData = try #require(event["data"] as? [String: Any])
        #expect(eventData["event_type"] as? String == "fenton_live_activity_action")
        #expect((eventData["event_data"] as? [String: String]) == ["tag": "fenton-home", "job": "dishwasher", "control": "stop"])
    }

    @Test func aMissingRegistrationThrows() async {
        let sender = MobileAppLiveActivityWebhook(client: MobileAppWebhookClient(
            source: FixedMobileAppWebhookSource(nil), transport: StubHTTPTransport([])))
        await #expect(throws: MobileAppWebhookError.notRegistered) { try await sender.reportDismissed(tag: "t") }
    }
}

struct StartTokenAppDataTests {
    private let config = PushConfig(json: Data(#"{"available":true,"push_url":"https://relay/api/fenton_home/apns","bundle_id":"com.sfenton.home"}"#.utf8))

    @Test func theStartTokenRidesNextToThePushDetails() {
        let data = PushAppData.resolve(config: config, token: "ab01", environment: .sandbox, startActivityToken: "cd02")
        #expect(data.json["start_live_activity_token"] as? String == "cd02")
        #expect(data.json["push_token"] as? String == "ab01")
        #expect(PushAppData.resolve(config: config, token: "ab01", environment: .sandbox).json["start_live_activity_token"] == nil)
        #expect(PushAppData.resolve(config: config, token: "ab01", environment: .sandbox, startActivityToken: "").json["start_live_activity_token"] == nil)
    }

    @Test func withoutPushDetailsThereIsNoStartToken() {
        let websocketOnly = PushAppData.resolve(config: config, token: nil, environment: .sandbox, startActivityToken: "cd02")
        #expect(websocketOnly.json.isEmpty)
        #expect(PushAppData.cleared.json.isEmpty, "sign-out removes the start token with the rest")
    }

    @Test func theUpdateRegistrationBodyCarriesIt() throws {
        let device = MobileAppDevice(marketingVersion: "1", build: "1", name: "iPhone", model: "m", osVersion: "27", deviceID: "d", apnsEnvironment: .sandbox)
        let data = PushAppData.resolve(config: config, token: "ab01", environment: .sandbox, startActivityToken: "cd02")
        let update = device.updateBody(appData: data)
        let appData = try #require((update["data"] as? [String: Any])?["app_data"] as? [String: Any])
        #expect(appData["start_live_activity_token"] as? String == "cd02")
    }
}
