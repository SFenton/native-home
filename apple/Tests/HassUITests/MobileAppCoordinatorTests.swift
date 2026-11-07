import Foundation
import HassCore
import HassTestSupport
@testable import HassUI
import Testing

private let server = HassServer(baseURL: URL(string: "https://ha.example.com")!)
private let configJSON = #"{"available":true,"push_url":"https://relay/api/fenton_home/apns","bundle_id":"com.sfenton.home"}"#
private let zonesJSON = """
[{"entity_id":"zone.home","attributes":{"latitude":37.6,"longitude":-122.3,"radius":40,"friendly_name":"Home"}}]
"""
private let fix = LocationFix(latitude: 37.6, longitude: -122.3, horizontalAccuracy: 8, timestamp: Date(timeIntervalSince1970: 2_000_000))

private func device() -> MobileAppDevice {
    MobileAppDevice(marketingVersion: "1", build: "2", name: "iPhone", model: "iPhone18,1", osVersion: "27.2",
                    deviceID: "v", apnsEnvironment: .sandbox)
}

private func freshDefaults() -> UserDefaults {
    UserDefaults(suiteName: "location-tests-\(UUID().uuidString)")!
}

/// Runs the main actor until `condition` holds (the coordinators hand work to unstructured tasks).
@MainActor
private func eventually(_ condition: @MainActor () -> Bool) async {
    for _ in 0..<500 where !condition() {
        try? await Task.sleep(for: .milliseconds(2))
    }
}

private func paths(_ transport: StubHTTPTransport) -> [String] {
    transport.requests.map { request in
        let type = (request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any])?["type"] as? String
        return [request.url?.path ?? "", type].compactMap { $0 }.joined(separator: " ")
    }
}

// MARK: - Shared registration

/// The shared `mobile_app` registration: published to listeners, cleared on sign-out, read by location.
@MainActor
struct MobileAppCoordinatorTests {
    @Test func aSimulatorNeitherRegistersNorUsesASavedWebhook() async {
        let saved = MobileAppRegistration(server: server, userID: "u1", webhookID: "old")
        let store = InMemoryMobileAppRegistrationStore([saved], active: saved)
        let transport = StubHTTPTransport([(200, configJSON), (201, #"{"webhook_id":"w1"}"#)])
        let mobileApp = MobileAppCoordinator(device: device, store: store, transport: transport, allowsRegistration: false)
        #expect(!mobileApp.savedWebhookExists, "a webhook saved before the rule is ignored")

        mobileApp.sessionStarted(server: server) { "token" }
        #expect(mobileApp.begin(userID: "u1", userName: "Alex Demo"))
        await mobileApp.sync()
        #expect(mobileApp.registration == nil)
        #expect(transport.requests.isEmpty, "nothing reaches Home Assistant")
    }

    @Test func publishesTheRegistrationAndClearsItOnSignOut() async {
        let store = InMemoryMobileAppRegistrationStore()
        let transport = StubHTTPTransport([(404, ""), (404, ""), (201, #"{"webhook_id":"w1"}"#), (200, "{}")])
        let mobileApp = MobileAppCoordinator(device: device, store: store, transport: transport)
        var seen: [MobileAppRegistration?] = []
        mobileApp.onRegistrationChange { seen.append($0) }
        #expect(!mobileApp.begin(userID: "u1", userName: nil), "no session yet")
        #expect(!mobileApp.savedWebhookExists)

        mobileApp.sessionStarted(server: server) { "token" }
        #expect(mobileApp.begin(userID: "u1", userName: "Alex Demo"))
        #expect(!mobileApp.begin(userID: "u1", userName: "Alex Demo"), "same user again")
        await mobileApp.sync()
        let registration = MobileAppRegistration(server: server, userID: "u1", webhookID: "w1")
        #expect(mobileApp.registration == registration)
        #expect(mobileApp.savedWebhookExists)
        #expect(await mobileApp.webhookSource.currentWebhook() == registration.webhook)

        await mobileApp.sessionEnded()
        #expect(mobileApp.registration == nil)
        #expect(!mobileApp.savedWebhookExists)
        #expect(seen == [registration, nil])
        await #expect(throws: PushClientError.signedOut) {
            try await mobileApp.fireAction(PushActionEvent(action: "A", tag: nil))
        }
    }

    @Test func sessionEndCompletesTheUnregisterBeforeReturning() async {
        // AppSession awaits sessionEnded before it revokes the refresh token, so the token is still valid for the request.
        let saved = MobileAppRegistration(server: server, userID: "u1", webhookID: "w1")
        let store = InMemoryMobileAppRegistrationStore([saved], active: saved)
        let transport = StubHTTPTransport([(200, #"{"removed":true}"#)])
        let mobileApp = MobileAppCoordinator(device: device, store: store, transport: transport)
        mobileApp.sessionStarted(server: server) { "token" }
        await mobileApp.sessionEnded()
        #expect(paths(transport) == ["/api/fenton_home/devices/unregister"])
        #expect(transport.requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer token")
        #expect(store.registration(server: server, userID: "u1") == nil)
    }

    @Test func pendingRemovalsRetryAtLaunchAndWhenTheNetworkReturns() async {
        let pending = PendingUnregister(server: server, webhookID: "w1")
        let store = InMemoryMobileAppRegistrationStore(pending: [pending])
        let transport = StubHTTPTransport([(200, "{}")])
        transport.error = URLError(.notConnectedToInternet)
        let mobileApp = MobileAppCoordinator(device: device, store: store, transport: transport)
        let reachability = FakeReachability()
        mobileApp.startPendingUnregisterRetries(reachability: reachability)
        mobileApp.startPendingUnregisterRetries(reachability: FakeReachability())
        await eventually { transport.requests.count == 1 }
        #expect(store.pendingUnregisters == [pending], "offline keeps it")

        transport.error = nil
        reachability.change?(false)
        reachability.change?(true)
        await eventually { store.pendingUnregisters.isEmpty }
        #expect(store.pendingUnregisters.isEmpty)
        #expect(transport.requests.last?.value(forHTTPHeaderField: "Authorization") == nil)

        // Nothing pending: nothing sent.
        let before = transport.requests.count
        await mobileApp.retryPendingUnregisters()
        #expect(transport.requests.count == before)
    }

    @Test func theCoordinatorKeepsItsReachabilityWatcherAlive() {
        // A dropped NWPathMonitor cancels itself, so the network-return retry would never fire.
        weak var watcher: FakeReachability?
        let mobileApp = MobileAppCoordinator(device: device, store: InMemoryMobileAppRegistrationStore(),
                                             transport: StubHTTPTransport([]))
        do {
            let fake = FakeReachability()
            watcher = fake
            mobileApp.startPendingUnregisterRetries(reachability: fake)
        }
        #expect(watcher != nil)
        withExtendedLifetime(mobileApp) {}
    }

    @Test func disabledNeverRegisters() async {
        let saved = MobileAppRegistration(server: server, userID: "u1", webhookID: "w1")
        let transport = StubHTTPTransport([])
        let mobileApp = MobileAppCoordinator(device: device, store: InMemoryMobileAppRegistrationStore([saved], active: saved),
                                             transport: transport, isEnabled: false)
        mobileApp.sessionStarted(server: server) { "token" }
        #expect(!mobileApp.begin(userID: "u1", userName: nil))
        await mobileApp.sync()
        #expect(!mobileApp.savedWebhookExists, "a journey never reports on a real webhook")
        #expect(transport.requests.isEmpty)
    }

    @Test func aNewTokenSyncsOnce() {
        let mobileApp = MobileAppCoordinator(device: device, store: InMemoryMobileAppRegistrationStore())
        #expect(mobileApp.setPushToken("ab"))
        #expect(!mobileApp.setPushToken("ab"))
        #expect(mobileApp.setPushToken("cd"))
    }

    @Test func linksThePersonOncePerRegistrationAndRetriesWhileUnlinked() async {
        let transport = StubHTTPTransport([(404, ""), (404, ""), (201, #"{"webhook_id":"w1"}"#), (200, "{}")])
        let mobileApp = MobileAppCoordinator(device: device, store: InMemoryMobileAppRegistrationStore(), transport: transport)
        let user = HassUser(id: "u1", name: "Alex", isOwner: false, isAdmin: true)
        let api = LinkAPI()
        await mobileApp.linkPresence(user: user, api: api)
        #expect(api.calls == 0 && mobileApp.presenceLink == nil, "nothing before a registration")

        mobileApp.sessionStarted(server: server) { "token" }
        _ = mobileApp.begin(userID: "u1", userName: nil)
        await mobileApp.sync()
        api.trackerExists = false
        await mobileApp.linkPresence(user: user, api: api)
        #expect(mobileApp.presenceLink == .trackerMissing)
        api.trackerExists = true
        await mobileApp.linkPresence(user: user, api: api)
        #expect(mobileApp.presenceLink == .linked(person: "Alex"))
        let calls = api.calls
        await mobileApp.linkPresence(user: user, api: api)
        #expect(api.calls == calls, "a linked registration isn't linked again")

        await mobileApp.sessionEnded()
        #expect(mobileApp.presenceLink == nil)
    }
}

@MainActor
private final class LinkAPI: HassCommandSending {
    var trackerExists = true
    var calls = 0
    func command(_ type: String, data: [String: any Sendable]) async throws -> JSONValue {
        calls += 1
        switch type {
        case "config/entity_registry/list":
            return .array(trackerExists ? [.object(["platform": .string("mobile_app"), "unique_id": .string("w1"),
                                                    "entity_id": .string("device_tracker.demo_x")])] : [])
        case "person/list":
            return .object(["storage": .array([.object(["id": .string("p"), "name": .string("Alex"), "user_id": .string("u1"),
                                                        "device_trackers": .array([])])])])
        default: return .null
        }
    }
}

@MainActor
struct PresenceLifecycleTests {
    @Test func withdrawnUnlinksAndRestoredRelinks() async {
        let transport = StubHTTPTransport([(404, ""), (404, ""), (201, #"{"webhook_id":"w1"}"#)])
        let mobileApp = MobileAppCoordinator(device: device, store: InMemoryMobileAppRegistrationStore(), transport: transport)
        let api = TrackerAPI()
        mobileApp.sessionStarted(server: server) { "t" }
        _ = mobileApp.begin(userID: "u1", userName: nil)
        await mobileApp.sync()
        await mobileApp.linkPresence(user: HassUser(id: "u1", name: nil, isOwner: false, isAdmin: true), api: api)
        #expect(api.trackers == ["device_tracker.demo_x"])
        await mobileApp.locationWithdrawn()
        #expect(api.trackers.isEmpty)
        await mobileApp.locationRestored()
        #expect(api.trackers == ["device_tracker.demo_x"])
        await mobileApp.locationWithdrawn()
        await mobileApp.locationWithdrawn()
        #expect(api.trackers.isEmpty, "removing twice is fine")
    }
}

@MainActor
private final class TrackerAPI: HassCommandSending {
    var trackers: [String] = []
    func command(_ type: String, data: [String: any Sendable]) async throws -> JSONValue {
        switch type {
        case "config/entity_registry/list":
            return .array([.object(["platform": .string("mobile_app"), "unique_id": .string("w1"), "entity_id": .string("device_tracker.demo_x")])])
        case "person/list":
            return .object(["storage": .array([.object(["id": .string("p"), "name": .string("S"), "user_id": .string("u1"),
                                                        "device_trackers": .array(trackers.map(JSONValue.string))])])])
        case "person/update": trackers = data["device_trackers"] as? [String] ?? []; return .null
        default: return .null
        }
    }
}

@MainActor
struct PresenceGuardTests {
    @Test func simulatorsAndJourneysNeverWriteToHomeAssistant() async throws {
        let saved = MobileAppRegistration(server: server, userID: "u1", webhookID: "w1")
        let user = HassUser(id: "u1", name: nil, isOwner: true, isAdmin: true)
        for (enabled, allowed) in [(false, true), (true, false), (false, false)] {
            let mobileApp = MobileAppCoordinator(device: device, store: InMemoryMobileAppRegistrationStore([saved], active: saved),
                                                 transport: StubHTTPTransport([]), isEnabled: enabled, allowsRegistration: allowed)
            let api = GuardAPI()
            await mobileApp.linkPresence(user: user, api: api)
            try await mobileApp.unlinkPresence(user: user, api: api)
            await mobileApp.locationWithdrawn()
            await mobileApp.locationRestored()
            #expect(api.calls == 0, "enabled \(enabled), allowed \(allowed)")
        }
    }
}

@MainActor
private final class GuardAPI: HassCommandSending {
    var calls = 0
    func command(_ type: String, data: [String: any Sendable]) async throws -> JSONValue { calls += 1; return .null }
}

private final class FakeReachability: NetworkReachability, @unchecked Sendable {
    var isOnline = true
    var change: (@Sendable (Bool) -> Void)?
    func start(_ onChange: @escaping @Sendable (Bool) -> Void) { change = onChange }
}
