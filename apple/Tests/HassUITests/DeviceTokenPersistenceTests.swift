import CoreSpotlight
import Foundation
import HassCore
import HassTestSupport
@testable import HassUI
import Testing

private let server = HassServer(baseURL: URL(string: "https://ha.example.com")!)
private let configJSON = #"{"available":true,"push_url":"https://relay/api/fenton_home/apns","bundle_id":"com.sfenton.home"}"#
private let saved = DeviceTokens(push: "ab", startActivity: "ee")

private func device() -> MobileAppDevice {
    MobileAppDevice(marketingVersion: "1", build: "2", name: "iPhone", model: "iPhone18,1", osVersion: "27.2",
                    deviceID: "v", apnsEnvironment: .sandbox)
}

/// The `app_data` of a request: register carries it at the top, `update_registration` under `data`.
private func appData(_ request: URLRequest) -> [String: Any] {
    let body = (request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? [:]
    return (body["app_data"] as? [String: Any]) ?? ((body["data"] as? [String: Any])?["app_data"] as? [String: Any]) ?? [:]
}

/// A store whose tokens cannot be read while `locked` (the Keychain before first unlock); it counts token writes.
private final class LockableStore: MobileAppRegistrationStore, @unchecked Sendable {
    let inner: InMemoryMobileAppRegistrationStore
    var locked = true
    private(set) var tokenWrites = 0

    init(tokens: DeviceTokens) { inner = InMemoryMobileAppRegistrationStore(tokens: tokens) }

    func registration(server: HassServer, userID: String) -> MobileAppRegistration? { inner.registration(server: server, userID: userID) }
    func save(_ registration: MobileAppRegistration) { inner.save(registration) }
    func remove(server: HassServer, userID: String) { inner.remove(server: server, userID: userID) }
    var active: MobileAppRegistration? { inner.active }
    func setActive(_ registration: MobileAppRegistration?) { inner.setActive(registration) }
    var pendingUnregisters: [PendingUnregister] { inner.pendingUnregisters }
    func addPending(_ entry: PendingUnregister) { inner.addPending(entry) }
    func removePending(_ entry: PendingUnregister) { inner.removePending(entry) }
    var deviceTokens: DeviceTokens? { locked ? nil : inner.deviceTokens }
    func setDeviceTokens(_ tokens: DeviceTokens) {
        tokenWrites += 1
        inner.setDeviceTokens(tokens)
    }
}

/// The install's push tokens: seeded at launch, gated by permission, kept across sign-out.
@MainActor
struct DeviceTokenPersistenceTests {
    private func coordinator(_ store: InMemoryMobileAppRegistrationStore, _ transport: StubHTTPTransport,
                             allowsRegistration: Bool = true) -> MobileAppCoordinator {
        let mobileApp = MobileAppCoordinator(device: device, store: store, transport: transport,
                                             allowsRegistration: allowsRegistration)
        mobileApp.sessionStarted(server: server) { "token" }
        return mobileApp
    }

    @Test func theFirstSyncAfterALaunchCarriesTheSavedTokens() async {
        let registration = MobileAppRegistration(server: server, userID: "u1", webhookID: "w1")
        let store = InMemoryMobileAppRegistrationStore([registration], active: registration, tokens: saved)
        let transport = StubHTTPTransport([(200, configJSON), (200, "{}")])
        let mobileApp = coordinator(store, transport)
        #expect(mobileApp.begin(userID: "u1", userName: nil))
        await mobileApp.sync()
        let data = appData(transport.requests[1])
        #expect(data["push_token"] as? String == "ab")
        #expect(data["start_live_activity_token"] as? String == "ee", "no later report is needed to keep the start token")
    }

    @Test func aFreshInstallSendsNoTokens() async {
        let transport = StubHTTPTransport([(200, configJSON), (201, #"{"webhook_id":"w1"}"#)])
        let mobileApp = coordinator(InMemoryMobileAppRegistrationStore(), transport)
        #expect(mobileApp.begin(userID: "u1", userName: nil))
        await mobileApp.sync()
        let data = appData(transport.requests[1])
        #expect(data["push_token"] == nil)
        #expect(data["start_live_activity_token"] == nil)
    }

    @Test func aRefusedPermissionSendsNoApnsTokenUntilItIsGranted() async {
        let registration = MobileAppRegistration(server: server, userID: "u1", webhookID: "w1")
        let store = InMemoryMobileAppRegistrationStore([registration], active: registration, tokens: saved)
        let transport = StubHTTPTransport([(200, configJSON), (200, "{}"), (200, configJSON), (200, "{}")])
        let mobileApp = coordinator(store, transport)
        #expect(mobileApp.begin(userID: "u1", userName: nil))
        #expect(mobileApp.setNotificationsGranted(false))
        #expect(!mobileApp.setNotificationsGranted(false))
        await mobileApp.sync()
        #expect(appData(transport.requests[1])["push_token"] == nil, "websocket-only, as a phone that never had permission")
        #expect(appData(transport.requests[1])["start_live_activity_token"] == nil)
        #expect(store.deviceTokens == saved, "the gate does not forget the token")

        #expect(mobileApp.setNotificationsGranted(true))
        await mobileApp.sync()
        #expect(appData(transport.requests[3])["push_token"] as? String == "ab")
        #expect(appData(transport.requests[3])["start_live_activity_token"] as? String == "ee")
    }

    @Test func aRotatedApnsTokenReplacesTheSavedOneAndKeepsTheStartToken() {
        let store = InMemoryMobileAppRegistrationStore(tokens: saved)
        let mobileApp = coordinator(store, StubHTTPTransport([]))
        #expect(!mobileApp.setPushToken("ab"), "the saved token is the current one")
        #expect(mobileApp.setPushToken("cd"))
        #expect(store.deviceTokens == DeviceTokens(push: "cd", startActivity: "ee"))
    }

    @Test func startTokenOffDropsItFromTheSyncButKeepsItForTurningOn() async {
        let registration = MobileAppRegistration(server: server, userID: "u1", webhookID: "w1")
        let store = InMemoryMobileAppRegistrationStore([registration], active: registration, tokens: saved)
        let transport = StubHTTPTransport([(200, configJSON), (200, "{}"), (200, configJSON), (200, "{}")])
        let mobileApp = coordinator(store, transport)
        #expect(mobileApp.begin(userID: "u1", userName: nil))
        #expect(mobileApp.knownStartActivityToken() == "ee")
        await mobileApp.registerStartActivityToken(nil)
        #expect(appData(transport.requests[1])["start_live_activity_token"] == nil)
        #expect(appData(transport.requests[1])["push_token"] as? String == "ab")
        #expect(store.deviceTokens?.startActivity == "ee", "kept for the next launch")
        await mobileApp.registerStartActivityToken("ee")
        #expect(appData(transport.requests[3])["start_live_activity_token"] as? String == "ee")
    }

    @Test func aNewStartTokenIsSavedAndSynced() async {
        let transport = StubHTTPTransport([(200, configJSON), (201, #"{"webhook_id":"w1"}"#)])
        let store = InMemoryMobileAppRegistrationStore()
        let mobileApp = coordinator(store, transport)
        #expect(mobileApp.begin(userID: "u1", userName: nil))
        #expect(mobileApp.setPushToken("ab"))
        await mobileApp.registerStartActivityToken("ff")
        #expect(store.deviceTokens == DeviceTokens(push: "ab", startActivity: "ff"))
        #expect(appData(transport.requests[1])["start_live_activity_token"] as? String == "ff")
    }

    @Test func signOutKeepsTheTokensSoTheNextSignInCarriesThem() async {
        let registration = MobileAppRegistration(server: server, userID: "u1", webhookID: "w1")
        let store = InMemoryMobileAppRegistrationStore([registration], active: registration, tokens: saved)
        // Sign-out unregisters; a different user then registers fresh on the same phone.
        let transport = StubHTTPTransport([(200, #"{"removed":true}"#), (200, configJSON), (201, #"{"webhook_id":"w2"}"#)])
        let mobileApp = coordinator(store, transport)
        await mobileApp.sessionEnded()
        #expect(store.deviceTokens == saved)

        mobileApp.sessionStarted(server: server) { "token" }
        #expect(mobileApp.begin(userID: "u2", userName: nil))
        await mobileApp.sync()
        let data = appData(transport.requests[2])
        #expect(data["push_token"] as? String == "ab")
        #expect(data["start_live_activity_token"] as? String == "ee")
    }

    @Test func aSimulatorSendsNothingWhateverIsSaved() async {
        let transport = StubHTTPTransport([(200, configJSON), (201, #"{"webhook_id":"w1"}"#)])
        let mobileApp = coordinator(InMemoryMobileAppRegistrationStore(tokens: saved), transport, allowsRegistration: false)
        #expect(mobileApp.begin(userID: "u1", userName: nil))
        await mobileApp.sync()
        #expect(transport.requests.isEmpty)
    }

    @Test func aStoreUnreadableAtFirstIsReadLaterAndNeverSentAsEmpty() async {
        let store = LockableStore(tokens: saved)
        let transport = StubHTTPTransport([(200, configJSON), (201, #"{"webhook_id":"w1"}"#)])
        let mobileApp = MobileAppCoordinator(device: device, store: store, transport: transport)
        mobileApp.sessionStarted(server: server) { "token" }
        #expect(mobileApp.begin(userID: "u1", userName: nil))
        await mobileApp.sync()
        #expect(transport.requests.isEmpty, "nothing goes out while the saved tokens cannot be read")

        // The system yields a rotated token meanwhile: it must not overwrite the unread pair.
        #expect(mobileApp.setPushToken("cd"))
        #expect(store.tokenWrites == 0)
        #expect(store.inner.deviceTokens == saved)

        store.locked = false
        await mobileApp.sync()
        let data = appData(transport.requests[1])
        #expect(data["push_token"] as? String == "cd", "the newer token wins")
        #expect(data["start_live_activity_token"] as? String == "ee", "the saved start token comes back")
        #expect(store.inner.deviceTokens == DeviceTokens(push: "cd", startActivity: "ee"))
    }

    @Test func aStartTokenWithdrawnWhileUnreadableStaysWithdrawn() async {
        let store = LockableStore(tokens: saved)
        let transport = StubHTTPTransport([(200, configJSON), (201, #"{"webhook_id":"w1"}"#)])
        let mobileApp = MobileAppCoordinator(device: device, store: store, transport: transport)
        mobileApp.sessionStarted(server: server) { "token" }
        #expect(mobileApp.begin(userID: "u1", userName: nil))
        await mobileApp.registerStartActivityToken(nil)
        store.locked = false
        await mobileApp.sync()
        #expect(appData(transport.requests[1])["push_token"] as? String == "ab")
        #expect(appData(transport.requests[1])["start_live_activity_token"] == nil)
        #expect(store.inner.deviceTokens?.startActivity == "ee", "kept for turning Live Activities on")
    }

    @Test func tokensAreWrittenOnlyWhenTheyChange() async {
        let store = LockableStore(tokens: saved)
        store.locked = false
        let mobileApp = MobileAppCoordinator(device: device, store: store, transport: StubHTTPTransport([]))
        #expect(!mobileApp.setPushToken("ab"))
        _ = mobileApp.setStartActivityToken("ee")
        _ = mobileApp.setStartActivityToken(nil)
        _ = mobileApp.setStartActivityToken("ee")
        #expect(store.tokenWrites == 0)
        #expect(mobileApp.setPushToken("cd"))
        #expect(store.tokenWrites == 1)
    }

    @Test func theCoordinatorNamesThisPhoneOnTheEventsItFires() {
        let mobileApp = coordinator(InMemoryMobileAppRegistrationStore(), StubHTTPTransport([]))
        let info = mobileApp.eventDeviceInfo
        #expect(info["sourceDevicePermanentID"] == "v" && info["sourceDeviceID"] == "v")
        #expect(info["sourceDeviceName"]?.isEmpty == false)
    }

    @Test func pushOpensAPageAndASpotlightResult() {
        let push = PushCoordinator.inert()
        #if DEBUG
        push.simulateConnected()
        #endif
        push.open(PushDestination(dashboardPath: "kitchen"))
        #expect(push.pendingRequest?.destination == PushDestination(dashboardPath: "kitchen"))
        #expect(push.open(spotlightUserInfo: [CSSearchableItemActivityIdentifier: "section.climate"]))
        #expect(!push.open(spotlightUserInfo: nil))
    }
}

/// The Keychain store's removal queue, which shares the item the tokens live in.
struct KeychainPendingRemovalTests {
    @Test func pendingRemovalsAndTokensShareOneItem() {
        let store = KeychainMobileAppRegistrationStore(service: "com.sfenton.home.push.tests.\(UUID().uuidString)")
        defer { store.setDeviceTokens(DeviceTokens()); store.removePending(PendingUnregister(server: server, webhookID: "w1")) }
        let entry = PendingUnregister(server: server, webhookID: "w1")
        #expect(store.deviceTokens == DeviceTokens(), "an empty item reads as empty, not unreadable")
        store.addPending(entry)
        store.setDeviceTokens(saved)
        #expect(store.pendingUnregisters == [entry])
        #expect(store.deviceTokens == saved)
        store.removePending(entry)
        #expect(store.pendingUnregisters.isEmpty)
        #expect(store.deviceTokens == saved, "removing an entry keeps the tokens")
    }
}
