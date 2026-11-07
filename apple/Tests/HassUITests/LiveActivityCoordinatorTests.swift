import FentonActivityModel
import Foundation
import HassCore
import HassTestSupport
@testable import HassUI
import Testing

private let server = HassServer(baseURL: URL(string: "https://ha.example.com")!)
private let configJSON = #"{"available":true,"push_url":"https://relay/api/fenton_home/apns","bundle_id":"com.sfenton.home"}"#
private let now = Date(timeIntervalSince1970: 1_792_249_200)

private func device() -> MobileAppDevice {
    MobileAppDevice(marketingVersion: "1", build: "2", name: "iPhone", model: "iPhone18,1", osVersion: "27.2",
                    deviceID: "v", apnsEnvironment: .sandbox)
}

@MainActor
private func eventually(_ condition: @MainActor () -> Bool) async -> Bool {
    for _ in 0..<1_000 where !condition() { try? await Task.sleep(for: .milliseconds(5)) }
    return condition()
}

private func json(_ request: URLRequest) -> [String: Any] {
    (request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? [:]
}

private let fan = HomeActivityAttributes(tag: "job.fan.demo_guest", title: "Guest Bath Fan", kind: "fan", symbol: "fan", tint: "air")
private let fanState = HomeActivityState(value: ActivityValue(kind: .countdown, startTs: 1_792_248_900, endTs: 1_792_249_482),
                                         controls: [ActivityControl(id: "stop", title: "Stop")])

/// The Live Activities for a session: tokens for Home Assistant, button presses, sign-out.
@MainActor
struct LiveActivityCoordinatorTests {
    private func make(enabled: Bool = true, transport: StubHTTPTransport = StubHTTPTransport([]))
        -> (LiveActivityCoordinator, FakeLiveActivityClient, MobileAppCoordinator) {
        let client = FakeLiveActivityClient()
        let mobileApp = MobileAppCoordinator(device: device, store: InMemoryMobileAppRegistrationStore(), transport: transport)
        let coordinator = LiveActivityCoordinator(client: client, mobileApp: mobileApp, isEnabled: enabled, now: { now })
        return (coordinator, client, mobileApp)
    }

    @Test func aSessionStartsWatchingTokensAndStartsNothingItself() async {
        let (coordinator, client, _) = make()
        coordinator.sessionStarted()
        #expect(await eventually { client.isWatching })
        #expect(client.activities.isEmpty && client.calls.isEmpty, "the engine starts cards; the app never does")
        await coordinator.sessionEnded()
    }

    @Test func signingOutEndsEveryCardAndStopsWatching() async {
        let (coordinator, client, _) = make()
        coordinator.sessionStarted()
        #expect(await eventually { client.isWatching })
        client.startFromPush(attributes: fan, state: fanState)
        client.startFromPush(attributes: HomeActivityAttributes(tag: "job.dryer", title: "Dryer", kind: "dryer"), state: fanState)
        await coordinator.sessionEnded()
        #expect(client.activities.allSatisfy { $0.lifecycle == .dismissed })
        #expect(client.calls.count == 2)
    }

    @Test func aDisabledCoordinatorDoesNothing() async {
        let (coordinator, client, _) = make(enabled: false)
        coordinator.sessionStarted()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(!client.isWatching)
        let inert = LiveActivityCoordinator.inert(mobileApp: MobileAppCoordinator(device: device, store: InMemoryMobileAppRegistrationStore()))
        #expect(!inert.isEnabled)
        await coordinator.sessionEnded()
    }

    @Test func thePushToStartTokenReachesHomeAssistantWithTheRegistration() async throws {
        let transport = StubHTTPTransport([(200, configJSON), (201, #"{"webhook_id":"w1"}"#), (200, configJSON), (200, "{}")])
        let (coordinator, client, mobileApp) = make(transport: transport)
        mobileApp.sessionStarted(server: server) { "token" }
        #expect(mobileApp.begin(userID: "u1", userName: nil))
        #expect(mobileApp.setPushToken("ab"))
        await mobileApp.sync()
        coordinator.sessionStarted()
        #expect(await eventually { client.isWatching })
        client.emitStartToken("cd01")
        #expect(await eventually { transport.requests.count == 4 })
        let appData = try #require((json(transport.requests[3])["data"] as? [String: Any])?["app_data"] as? [String: Any])
        #expect(appData["start_live_activity_token"] as? String == "cd01")
        #expect(appData["push_token"] as? String == "ab")
        await coordinator.sessionEnded()
    }

    @Test func buttonsReachTheRegistrationWebhook() async throws {
        let registration = MobileAppRegistration(server: server, userID: "u1", webhookID: "w1")
        let transport = StubHTTPTransport([(200, "{}"), (200, "{}")])
        let client = FakeLiveActivityClient()
        let mobileApp = MobileAppCoordinator(device: device, store: InMemoryMobileAppRegistrationStore([registration], active: registration),
                                             transport: transport)
        let coordinator = LiveActivityCoordinator(client: client, mobileApp: mobileApp, now: { now })
        client.startFromPush(attributes: fan, state: fanState)
        let handled = await coordinator.intentHandler.handle(.control(tag: "job.fan.demo_guest", control: "stop"))
        #expect(handled)
        let sent = try #require(transport.requests.first)
        #expect(sent.url?.path == "/api/webhook/w1")
        let event = try #require((json(sent)["data"] as? [String: Any]))
        #expect(event["event_type"] as? String == "fenton_live_activity_action")
        #expect((event["event_data"] as? [String: String]) == ["tag": "job.fan.demo_guest", "job": "fan.demo_guest", "control": "stop"])
    }
}

@MainActor
struct LiveActivityRegistrationTests {
    @Test func theWebhookProviderFollowsTheSignedInRegistration() {
        let registration = MobileAppRegistration(server: server, userID: "u1", webhookID: "w1")
        let store = InMemoryMobileAppRegistrationStore([registration], active: registration)
        let mobileApp = MobileAppCoordinator(device: device, store: store, transport: StubHTTPTransport([]))
        let provider = mobileApp.activityWebhookProvider()
        #expect(provider() != nil)
        store.setActive(nil)
        #expect(provider() == nil, "signed out: no webhook")
        let simulator = MobileAppCoordinator(device: device, store: InMemoryMobileAppRegistrationStore([registration], active: registration),
                                             transport: StubHTTPTransport([]), allowsRegistration: false)
        #expect(simulator.activityWebhookProvider()() == nil, "a simulator never reaches the real Home Assistant")
        let disabled = MobileAppCoordinator(device: device, store: InMemoryMobileAppRegistrationStore([registration], active: registration),
                                            transport: StubHTTPTransport([]), isEnabled: false)
        #expect(disabled.activityWebhookProvider()() == nil)
    }

    @Test func aChangedStartTokenSyncsOnceAndOffClearsIt() async throws {
        let transport = StubHTTPTransport([(200, configJSON), (201, #"{"webhook_id":"w1"}"#), (200, configJSON), (200, "{}"), (200, configJSON), (200, "{}")])
        let mobileApp = MobileAppCoordinator(device: device, store: InMemoryMobileAppRegistrationStore(), transport: transport)
        mobileApp.sessionStarted(server: server) { "token" }
        #expect(mobileApp.begin(userID: "u1", userName: nil))
        #expect(mobileApp.setPushToken("ab"))
        await mobileApp.sync()
        #expect(transport.requests.count == 2)
        await mobileApp.registerStartActivityToken("ee")
        await mobileApp.registerStartActivityToken("ee")
        #expect(transport.requests.count == 4, "the same token is not sent twice")
        await mobileApp.registerStartActivityToken(nil)
        #expect(transport.requests.count == 6)
        let appData = try #require((json(transport.requests[5])["data"] as? [String: Any])?["app_data"] as? [String: Any])
        #expect(appData["start_live_activity_token"] == nil)
    }

    @Test func launchPolicy() {
        #expect(LiveActivityLaunchPolicy.isEnabled(environment: [:]))
        #if DEBUG
        for journey in ["FENTON_HASS_TOKEN", "FENTON_UITEST_RESET", "FENTON_GALLERY"] {
            #expect(!LiveActivityLaunchPolicy.isEnabled(environment: [journey: "x"]))
            #expect(LiveActivityLaunchPolicy.isEnabled(environment: [journey: "x", "FENTON_LIVE_ACTIVITY": "1"]))
        }
        #endif
    }
}

@MainActor
struct LiveActivityLinkTests {
    @Test func aTapOnTheActivityOpensTheJobsPage() throws {
        let push = PushCoordinator.inert()
        let state = try #require(HomeActivityFixtures.fixture("dishwasher", now: now)).state
        let url = try #require(ActivityDeepLink.url(for: state))
        #expect(push.openLiveActivity(url))
        #expect(push.pendingRequest?.destination == PushDestination(dashboardPath: "kitchen"))
        #expect(!push.openLiveActivity(URL(string: "https://example.com")!), "any other URL is not ours")
        #expect(!push.openLiveActivity(URL(string: "fentonhome://other")!))
    }
}
