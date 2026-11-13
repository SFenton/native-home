import Foundation
@testable import HassCore
import HassTestSupport
import Testing
#if canImport(UserNotifications)
import UserNotifications
#endif

// MARK: - Fixtures

private let server = HassServer(baseURL: URL(string: "https://ha.example.com")!)
private let device = MobileAppDevice(marketingVersion: "1.2.0", build: "45", name: "Alex's iPhone", model: "iPhone18,1",
                                osVersion: "27.2", deviceID: "VENDOR-1", apnsEnvironment: .sandbox)
private let configJSON = #"{"available":true,"push_url":"http://example.local:8123/api/fenton_home/apns","bundle_id":"com.sfenton.home","critical_alerts":false}"#

private func body(_ request: URLRequest) -> [String: Any] {
    (request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? [:]
}

// MARK: - Config and device

@Suite("Push config and device", .demoHouse)
struct PushConfigTests {
    @Test func configParses() {
        let config = PushConfig(json: Data(configJSON.utf8))
        #expect(config.available)
        #expect(config.pushURL?.absoluteString == "http://example.local:8123/api/fenton_home/apns")
        #expect(config.bundleID == "com.sfenton.home")
        #expect(!config.criticalAlerts)
        // Available without a URL is unavailable; junk is unavailable.
        #expect(!PushConfig(json: Data(#"{"available":true}"#.utf8)).available)
        #expect(!PushConfig(json: Data("nope".utf8)).available)
        #expect(PushConfig(json: Data(#"{"available":false,"push_url":"https://x","critical_alerts":true}"#.utf8)).criticalAlerts)
    }

    @Test func deviceBodies() throws {
        #expect(device.appVersion == "1.2.0 (45)")
        #expect(device.deviceName == "Alex's iPhone" + PushApp.deviceNameSuffix)
        #expect(MobileAppDevice(marketingVersion: "1", build: "1", name: "  ", model: "m", osVersion: "o", deviceID: "d",
                           apnsEnvironment: .production).deviceName == "iPhone" + PushApp.deviceNameSuffix)
        let data = PushAppData(pushURL: URL(string: "https://relay"), pushToken: "ab01", apnsEnvironment: .sandbox)
        let registration = device.registrationBody(appData: data)
        #expect(registration["app_id"] as? String == "com.sfenton.home")
        #expect(registration["app_name"] as? String == "Fenton Home")
        #expect(registration["manufacturer"] as? String == "Apple")
        #expect(registration["os_name"] as? String == "iOS")
        #expect(registration["device_id"] as? String == "VENDOR-1")
        #expect(registration["supports_encryption"] as? Bool == false)
        let appData = try #require(registration["app_data"] as? [String: Any])
        #expect(appData["push_url"] as? String == "https://relay")
        #expect(appData["push_token"] as? String == "ab01")
        #expect(appData["apns_environment"] as? String == "sandbox")
        #expect(appData["push_websocket_channel"] == nil, "not claimed until the app listens on it")

        let update = device.updateBody(appData: .cleared)
        #expect(update["type"] as? String == "update_registration")
        let updateData = try #require(update["data"] as? [String: Any])
        #expect((updateData["app_data"] as? [String: Any])?.isEmpty == true)
        #expect(updateData["app_version"] as? String == "1.2.0 (45)")
        #expect(updateData["device_name"] as? String == "Alex's iPhone" + PushApp.deviceNameSuffix)
    }

    @Test func genericNamesTakeTheOwnersFirstName() {
        let generic = MobileAppDevice(marketingVersion: "1", build: "1", name: "iPhone", model: "iPhone19,2", osVersion: "27",
                                 deviceID: "d", apnsEnvironment: .sandbox)
        #expect(generic.owned(by: "Alex Demo").deviceName == "Alex's iPhone 18 Pro" + PushApp.deviceNameSuffix)
        #expect(generic.owned(by: nil).deviceName == "iPhone 18 Pro" + PushApp.deviceNameSuffix)
        #expect(generic.owned(by: "  ").deviceName == "iPhone 18 Pro" + PushApp.deviceNameSuffix)
        // A name the person chose is kept.
        #expect(device.owned(by: "Sam").deviceName == "Alex's iPhone" + PushApp.deviceNameSuffix)
    }

    @Test func eachPhoneNamesItselfAfterItsModel() {
        func phone(_ name: String, _ model: String) -> MobileAppDevice {
            MobileAppDevice(marketingVersion: "1", build: "1", name: name, model: model, osVersion: "27", deviceID: "d",
                            apnsEnvironment: .sandbox)
        }
        #expect(phone("iPhone", "iPhone19,4").owned(by: "Alex Demo").deviceName == "Alex's iPhone Duo" + PushApp.deviceNameSuffix)
        #expect(phone("iPhone", "iPhone19,4").owned(by: nil).deviceName == "iPhone Duo" + PushApp.deviceNameSuffix)
        #expect(phone("iPhone", "iPhone19,2").owned(by: "Alex").deviceName == "Alex's iPhone 18 Pro" + PushApp.deviceNameSuffix)
        #expect(phone("iPhone", "iPhone18,4").owned(by: nil).deviceName == "iPhone Air" + PushApp.deviceNameSuffix)
        // An unknown identifier keeps the generic name; a chosen name is kept whatever the model.
        #expect(phone("iPhone", "iPhone99,9").owned(by: "Alex").deviceName == "Alex's iPhone" + PushApp.deviceNameSuffix)
        #expect(phone("iPad", "iPad99,9").owned(by: nil).deviceName == "iPad" + PushApp.deviceNameSuffix)
        #expect(phone("Kitchen phone", "iPhone19,4").owned(by: "Alex").deviceName == "Kitchen phone" + PushApp.deviceNameSuffix)
        #expect(MobileAppDevice.marketingName(forModel: "iPhone17,5") == "iPhone 16e")
        #expect(MobileAppDevice.marketingName(forModel: "nope") == nil)
    }

    @Test func registrationCarriesTheRunningBundle() {
        #expect(device.appID == PushApp.appID)
        let uikit = MobileAppDevice(marketingVersion: "1", build: "1", name: "iPhone", model: "m", osVersion: "o", deviceID: "d",
                                    apnsEnvironment: .sandbox, appID: "com.sfenton.home.uikit")
        #expect(uikit.registrationBody(appData: .cleared)["app_id"] as? String == "com.sfenton.home.uikit")
    }

    @Test func appDataResolves() {
        let config = PushConfig(json: Data(configJSON.utf8))
        let push = PushAppData.resolve(config: config, token: "ff", environment: .production)
        #expect(push.pushToken == "ff")
        #expect(push.json["apns_environment"] as? String == "production")
        // No token, empty token or no relay: websocket only.
        for socketOnly in [PushAppData.resolve(config: config, token: nil, environment: .sandbox),
                           PushAppData.resolve(config: config, token: "", environment: .sandbox),
                           PushAppData.resolve(config: PushConfig(available: false), token: "ff", environment: .sandbox)] {
            #expect(socketOnly.pushURL == nil)
            #expect(socketOnly.json.isEmpty)
        }
        // A URL without a token sends no push fields.
        #expect(PushAppData(pushURL: URL(string: "https://r"), pushToken: nil, apnsEnvironment: .sandbox).json["push_url"] == nil)
        #expect(PushAppData(pushURL: URL(string: "https://r"), pushToken: "a", apnsEnvironment: nil).json["apns_environment"] == nil)
        #expect(PushAppData.cleared.json.isEmpty)
        #expect(PushAppData(pushURL: nil, pushToken: nil, apnsEnvironment: nil, websocketChannel: true).json["push_websocket_channel"] as? Bool == true)
    }

    @Test func tokenIsLowercaseHex() {
        #expect(PushToken.hex(Data([0x00, 0xAB, 0x7F, 0xFF])) == "00ab7fff")
    }

    @Test func apnsEnvironmentFromProfile() {
        let profile = { (value: String) in Data("junk<plist><key>aps-environment</key>\n\t<string>\(value)</string></plist>".utf8) }
        #expect(APNsEnvironment.detect(provisioningProfile: profile("production"), isSimulator: false) == .production)
        #expect(APNsEnvironment.detect(provisioningProfile: profile("development"), isSimulator: false) == .sandbox)
        #expect(APNsEnvironment.detect(provisioningProfile: Data("no entitlement".utf8), isSimulator: false) == .sandbox)
        #expect(APNsEnvironment.detect(provisioningProfile: nil, isSimulator: false) == .production)
        #expect(APNsEnvironment.detect(provisioningProfile: profile("production"), isSimulator: true) == .sandbox)
    }
}

// MARK: - Client

@Suite("Home Assistant push client", .demoHouse)
struct HomeAssistantPushClientTests {
    let registration = MobileAppRegistration(server: server, userID: "u1", webhookID: "hook1")

    func client(_ transport: StubHTTPTransport) -> HomeAssistantPushClient {
        HomeAssistantPushClient(server: server, accessToken: { "ha-token" }, transport: transport)
    }

    @Test func configReadsAndMissingIntegration() async throws {
        let transport = StubHTTPTransport([(200, configJSON), (404, ""), (404, "")])
        let push = client(transport)
        #expect(try await push.config()?.available == true)
        #expect(try await push.config() == nil)
        #expect(transport.requests.first?.url?.path == "/api/fenton_home/config")
        #expect(transport.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer ha-token")
        await #expect(throws: PushClientError.status(500)) { try await client(StubHTTPTransport([(500, "")])).config() }
    }

    @Test func oldServerFallsBackToTheLegacyPath() async throws {
        let transport = StubHTTPTransport([(404, ""), (200, configJSON)])
        #expect(try await client(transport).config()?.available == true)
        #expect(transport.requests.map { $0.url?.path } == ["/api/fenton_home/config", "/api/fenton_push/config"])
        #expect(transport.requests.last?.value(forHTTPHeaderField: "Authorization") == "Bearer ha-token")
    }

    @Test func missingOnBothPathsMeansNotInstalled() async throws {
        let transport = StubHTTPTransport([(404, ""), (404, "")])
        #expect(try await client(transport).config() == nil)
        #expect(transport.requests.count == 2)
    }

    @Test func otherFailuresOnTheNewPathDoNotFallBack() async throws {
        let transport = StubHTTPTransport([(500, ""), (200, configJSON)])
        await #expect(throws: PushClientError.status(500)) { try await client(transport).config() }
        #expect(transport.requests.count == 1)
        let denied = StubHTTPTransport([(401, ""), (200, configJSON)])
        await #expect(throws: PushClientError.status(401)) { try await client(denied).config() }
        #expect(denied.requests.count == 1)
    }

    @Test func registers() async throws {
        let transport = StubHTTPTransport([(201, #"{"webhook_id":"new-hook","cloudhook_url":null}"#)])
        let id = try await client(transport).register(device, appData: PushAppData.cleared)
        #expect(id == "new-hook")
        let request = try #require(transport.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/api/mobile_app/registrations")
        #expect(body(request)["device_name"] as? String == "Alex's iPhone" + PushApp.deviceNameSuffix)
        await #expect(throws: PushClientError.unexpectedResponse) {
            try await client(StubHTTPTransport([(201, "{}")])).register(device, appData: .cleared)
        }
        await #expect(throws: PushClientError.status(400)) {
            try await client(StubHTTPTransport([(400, "")])).register(device, appData: .cleared)
        }
    }

    @Test func webhookCalls() async throws {
        let transport = StubHTTPTransport([(200, "{}"), (200, "")])
        let push = client(transport)
        try await push.updateRegistration(registration, device: device, appData: .cleared)
        try await push.fireAction(registration, event: PushActionEvent(action: "LOCK", tag: "door", replyText: "hi"))
        #expect(transport.requests.map { $0.url?.path } == ["/api/webhook/hook1", "/api/webhook/hook1"])
        // Webhooks carry no token.
        #expect(transport.requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == nil })
        #expect(body(transport.requests[0])["type"] as? String == "update_registration")
        let fire = body(transport.requests[1])
        #expect(fire["type"] as? String == "fire_event")
        let data = try #require(fire["data"] as? [String: Any])
        #expect(data["event_type"] as? String == "mobile_app_notification_action")
        let event = try #require(data["event_data"] as? [String: Any])
        #expect(event["action"] as? String == "LOCK")
        #expect(event["tag"] as? String == "door")
        #expect(event["reply_text"] as? String == "hi")

        await #expect(throws: PushClientError.registrationGone) {
            try await client(StubHTTPTransport([(410, "")])).updateRegistration(registration, device: device, appData: .cleared)
        }
        await #expect(throws: PushClientError.status(503)) {
            try await client(StubHTTPTransport([(503, "")])).fireAction(registration, event: PushActionEvent(action: "A", tag: nil))
        }
    }

    @Test func failuresMap() async {
        let offline = StubHTTPTransport([])
        offline.error = URLError(.notConnectedToInternet)
        await #expect(throws: PushClientError.network) { try await client(offline).config() }
        let cancelled = StubHTTPTransport([])
        cancelled.error = CancellationError()
        await #expect(throws: CancellationError.self) { try await client(cancelled).config() }
        let signedOut = HomeAssistantPushClient(server: server, accessToken: { throw TokenManager.SignedOut() },
                                                transport: StubHTTPTransport([]))
        await #expect(throws: PushClientError.signedOut) { try await signedOut.config() }
        let cancelledToken = HomeAssistantPushClient(server: server, accessToken: { throw CancellationError() },
                                                     transport: StubHTTPTransport([]))
        await #expect(throws: CancellationError.self) { try await cancelledToken.config() }
    }

    @Test func eventOmitsEmptyFields() throws {
        let data = try #require(PushActionEvent(action: "OK", tag: nil).webhookBody["data"] as? [String: Any])
        #expect((data["event_data"] as? [String: Any])?.keys.sorted() == ["action"])
    }
}

// MARK: - Registrar

@Suite("Mobile app registrar", .demoHouse)
struct MobileAppRegistrarTests {
    func registrar(_ transport: StubHTTPTransport, store: InMemoryMobileAppRegistrationStore) -> MobileAppRegistrar {
        MobileAppRegistrar(server: server,
                      client: HomeAssistantPushClient(server: server, accessToken: { "t" }, transport: transport),
                      store: store, device: device)
    }

    @Test func aSimulatorNeverRegisters() async {
        // Each simulator signs in as a real person; registering would add a device and a notify service to them.
        let transport = StubHTTPTransport([(200, configJSON), (201, #"{"webhook_id":"w1"}"#)])
        let store = InMemoryMobileAppRegistrationStore()
        let blocked = MobileAppRegistrar(server: server,
                                         client: HomeAssistantPushClient(server: server, accessToken: { "t" }, transport: transport),
                                         store: store, device: device, allowsRegistration: false)
        await #expect(throws: MobileAppRegistrar.Refusal.simulator) { try await blocked.sync(userID: "u1", token: "aa") }
        #expect(transport.requests.isEmpty)
        #expect(store.active == nil)
    }

    @Test func registrationPolicyBlocksOnlyTheSimulator() {
        #expect(MobileAppRegistrationPolicy.allowsRegistration(environment: [:], isSimulator: false))
        #expect(MobileAppRegistrationPolicy.allowsRegistration(environment: ["FENTON_MOBILE_APP_REGISTER": "1"], isSimulator: false))
        #expect(!MobileAppRegistrationPolicy.allowsRegistration(environment: [:], isSimulator: true))
        #expect(!MobileAppRegistrationPolicy.allowsRegistration(environment: ["FENTON_PUSH": "1"], isSimulator: true),
                "turning push on doesn't register a simulator")
        #expect(!MobileAppRegistrationPolicy.allowsRegistration(environment: ["FENTON_MOBILE_APP_REGISTER": "0"], isSimulator: true))
        #expect(MobileAppRegistrationPolicy.allowsRegistration(environment: ["FENTON_MOBILE_APP_REGISTER": "1"], isSimulator: true))
        #expect(!MobileAppRegistrationPolicy.isSimulator, "unit tests run on the Mac")
    }

    @Test func registersWebsocketOnlyWithoutTheIntegration() async throws {
        // 404: location and sensors still need the registration, so it goes ahead without push details.
        let transport = StubHTTPTransport([(404, ""), (404, ""), (201, #"{"webhook_id":"w1"}"#), (404, ""), (404, ""), (200, "{}")])
        let store = InMemoryMobileAppRegistrationStore()
        let shared = registrar(transport, store: store)
        let outcome = try await shared.sync(userID: "u1", token: "aa")
        guard case let .registered(registration, appData) = outcome else {
            Issue.record("expected a registration")
            return
        }
        #expect(outcome.registration == registration)
        #expect(appData == PushAppData(pushURL: nil, pushToken: nil, apnsEnvironment: nil))
        #expect(transport.requests[2].url?.path == "/api/mobile_app/registrations")
        #expect((body(transport.requests[2])["app_data"] as? [String: Any])?.isEmpty == true)
        #expect(store.active == registration)
        #expect(await store.currentWebhook() == MobileAppWebhook(server: server, webhookID: "w1"))

        // Still no integration on the next launch: the same registration is updated, not duplicated.
        let again = try await shared.sync(userID: "u1", token: "aa")
        #expect(again == .updated(registration, appData))
        #expect(again.registration == registration)
        #expect(transport.requests[5].url?.path == "/api/webhook/w1")
    }

    @Test func unavailableIntegrationIsWebsocketOnly() async throws {
        let unavailable = #"{"available":false}"#
        let transport = StubHTTPTransport([(200, unavailable), (201, #"{"webhook_id":"w"}"#)])
        guard case let .registered(_, appData) = try await registrar(transport, store: InMemoryMobileAppRegistrationStore())
            .sync(userID: "u1", token: "aa") else {
            Issue.record("expected a registration")
            return
        }
        #expect(appData.pushURL == nil)
        #expect(appData.pushToken == nil)
    }

    @Test func aForeignBundleRegistersWithoutPushDetails() async throws {
        // The relay's bundle_id is com.sfenton.home; this build runs as another bundle, so its token would be for the wrong topic.
        let uikit = MobileAppDevice(marketingVersion: "1", build: "1", name: "iPhone", model: "iPhone19,4", osVersion: "27",
                                    deviceID: "d", apnsEnvironment: .sandbox, appID: "com.sfenton.home.uikit")
        let transport = StubHTTPTransport([(200, configJSON), (201, #"{"webhook_id":"w1"}"#)])
        let foreign = MobileAppRegistrar(server: server,
                                         client: HomeAssistantPushClient(server: server, accessToken: { "t" }, transport: transport),
                                         store: InMemoryMobileAppRegistrationStore(), device: uikit)
        guard case let .registered(_, appData) = try await foreign.sync(userID: "u1", token: "aa") else {
            Issue.record("expected a registration")
            return
        }
        #expect(appData.pushToken == nil)
        let sent = body(transport.requests[1])
        #expect((sent["app_data"] as? [String: Any])?.isEmpty == true)
        #expect(sent["app_id"] as? String == "com.sfenton.home.uikit")
    }

    @Test func configFailuresStopTheSync() async {
        // A broken integration (not a missing one) must not clear working push details.
        let store = InMemoryMobileAppRegistrationStore()
        await #expect(throws: PushClientError.status(500)) {
            try await registrar(StubHTTPTransport([(500, "")]), store: store).sync(userID: "u1", token: "aa")
        }
        #expect(store.active == nil)
    }

    @Test func registersThenUpdates() async throws {
        let transport = StubHTTPTransport([(200, configJSON), (201, #"{"webhook_id":"w1"}"#), (200, configJSON), (200, "{}")])
        let store = InMemoryMobileAppRegistrationStore()
        let push = registrar(transport, store: store)
        guard case let .registered(registration, appData) = try await push.sync(userID: "u1", token: "aa") else {
            Issue.record("expected a registration")
            return
        }
        #expect(registration.webhookID == "w1")
        #expect(appData.pushToken == "aa")
        #expect(store.active == registration)
        #expect(store.registration(server: server, userID: "u1") == registration)
        guard case .updated = try await push.sync(userID: "u1", userName: "Alex Demo", token: "bb") else {
            Issue.record("expected an update")
            return
        }
        #expect(transport.requests.last?.url?.path == "/api/webhook/w1")
        let sent = try #require(body(transport.requests[3])["data"] as? [String: Any])
        #expect((sent["app_data"] as? [String: Any])?["push_token"] as? String == "bb")
    }

    @Test func reRegistersWhenGone() async throws {
        let saved = MobileAppRegistration(server: server, userID: "u1", webhookID: "old")
        let store = InMemoryMobileAppRegistrationStore([saved])
        let transport = StubHTTPTransport([(200, configJSON), (410, ""), (201, #"{"webhook_id":"fresh"}"#)])
        guard case let .registered(registration, _) = try await registrar(transport, store: store).sync(userID: "u1", token: nil) else {
            Issue.record("expected a new registration")
            return
        }
        #expect(registration.webhookID == "fresh")
        #expect(store.registration(server: server, userID: "u1")?.webhookID == "fresh")
    }

    @Test func otherErrorsPropagate() async {
        let store = InMemoryMobileAppRegistrationStore([MobileAppRegistration(server: server, userID: "u1", webhookID: "w")])
        await #expect(throws: PushClientError.status(500)) {
            try await registrar(StubHTTPTransport([(200, configJSON), (500, "")]), store: store).sync(userID: "u1", token: nil)
        }
        #expect(store.registration(server: server, userID: "u1") != nil)
    }

    @Test func otherBundleIsWebsocketOnly() async throws {
        let foreign = #"{"available":true,"push_url":"https://relay","bundle_id":"io.robbie.HomeAssistant"}"#
        let transport = StubHTTPTransport([(200, foreign), (201, #"{"webhook_id":"w"}"#)])
        guard case let .registered(_, appData) = try await registrar(transport, store: InMemoryMobileAppRegistrationStore())
            .sync(userID: "u1", token: "aa") else {
            Issue.record("expected a registration")
            return
        }
        #expect(appData.pushURL == nil)
    }

    private func signedIn() -> (MobileAppRegistration, InMemoryMobileAppRegistrationStore) {
        let saved = MobileAppRegistration(server: server, userID: "u1", webhookID: "w1")
        return (saved, InMemoryMobileAppRegistrationStore([saved], active: saved))
    }

    @Test func signOutRemovesTheRegistration() async throws {
        let (_, store) = signedIn()
        let transport = StubHTTPTransport([(200, #"{"removed":true}"#)])
        await registrar(transport, store: store).signOut()
        #expect(transport.requests.count == 1)
        let request = transport.requests[0]
        #expect(request.url?.path == "/api/fenton_home/devices/unregister")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer t")
        #expect(body(request)["webhook_id"] as? String == "w1")
        #expect(store.active == nil)
        #expect(store.registration(server: server, userID: "u1") == nil)
        #expect(store.pendingUnregisters.isEmpty)
    }

    @Test func signOutTreatsAlreadyGoneAsRemoved() async {
        let (_, store) = signedIn()
        await registrar(StubHTTPTransport([(410, "")]), store: store).signOut()
        #expect(store.registration(server: server, userID: "u1") == nil)
        #expect(store.pendingUnregisters.isEmpty)
    }

    @Test func signOutOnAServerWithout11ClearsPushDetailsAndKeepsTheWebhook() async throws {
        let (saved, store) = signedIn()
        let transport = StubHTTPTransport([(404, ""), (200, "{}")])
        await registrar(transport, store: store).signOut()
        #expect(transport.requests.count == 2)
        let sent = try #require(body(transport.requests[1])["data"] as? [String: Any])
        #expect((sent["app_data"] as? [String: Any])?.isEmpty == true)
        #expect(store.active == nil)
        #expect(store.registration(server: server, userID: "u1") == saved)
        #expect(store.pendingUnregisters.isEmpty)
    }

    @Test func signOutFallsBackOnNotOwnerOrServerError() async throws {
        for status in [403, 400, 500] {
            let (saved, store) = signedIn()
            let transport = StubHTTPTransport([(status, ""), (200, "{}")])
            await registrar(transport, store: store).signOut()
            #expect(transport.requests.count == 2, "status \(status)")
            #expect(body(transport.requests[1])["type"] as? String == "update_registration")
            #expect(store.registration(server: server, userID: "u1") == saved)
            #expect(store.pendingUnregisters.isEmpty)
        }
        // The fallback finding the webhook gone forgets it.
        let (_, store) = signedIn()
        await registrar(StubHTTPTransport([(403, ""), (410, "")]), store: store).signOut()
        #expect(store.registration(server: server, userID: "u1") == nil)
    }

    @Test func signOutOfflineQueuesTheRemoval() async {
        let (_, store) = signedIn()
        let transport = StubHTTPTransport([])
        transport.error = URLError(.notConnectedToInternet)
        await registrar(transport, store: store).signOut()
        #expect(transport.requests.count == 1)
        #expect(store.pendingUnregisters == [PendingUnregister(server: server, webhookID: "w1")])
        #expect(store.registration(server: server, userID: "u1") == nil)
        #expect(store.active == nil)
    }

    private func tokenless(_ transport: StubHTTPTransport, store: InMemoryMobileAppRegistrationStore) -> MobileAppRegistrar {
        // The token store was cleared (or the token is near expiry and the refresh failed): no access token.
        MobileAppRegistrar(
            server: server, client: HomeAssistantPushClient(server: server, accessToken: { throw URLError(.userAuthenticationRequired) },
                                                           transport: transport),
            store: store, device: device)
    }

    @Test func signOutWithoutAValidTokenUnregistersWithoutAuthRightAway() async {
        let (_, store) = signedIn()
        let transport = StubHTTPTransport([(200, #"{"removed":true}"#)])
        await tokenless(transport, store: store).signOut()
        #expect(transport.requests.count == 1)
        #expect(transport.requests[0].url?.path == "/api/fenton_home/devices/unregister")
        #expect(transport.requests[0].value(forHTTPHeaderField: "Authorization") == nil)
        #expect(body(transport.requests[0])["webhook_id"] as? String == "w1")
        #expect(store.registration(server: server, userID: "u1") == nil)
        #expect(store.pendingUnregisters.isEmpty, "a missing token is not a network failure")
    }

    @Test func signOutWithoutATokenAndOfflineQueues() async {
        let (_, store) = signedIn()
        let transport = StubHTTPTransport([])
        transport.error = URLError(.notConnectedToInternet)
        await tokenless(transport, store: store).signOut()
        #expect(store.pendingUnregisters == [PendingUnregister(server: server, webhookID: "w1")])
    }

    @Test func signOutQueuesWhenTheServerAsksToRetryLater() async {
        for status in [429, 503] {
            let (_, store) = signedIn()
            let transport = StubHTTPTransport([(status, "")])
            await registrar(transport, store: store).signOut()
            #expect(transport.requests.count == 1, "no clear-push fallback for \(status)")
            #expect(store.pendingUnregisters.count == 1)
            #expect(store.registration(server: server, userID: "u1") == nil)
        }
    }

    @Test func signOutWithNothingActiveSendsNothing() async {
        let idle = StubHTTPTransport([])
        await registrar(idle, store: InMemoryMobileAppRegistrationStore()).signOut()
        let elsewhere = MobileAppRegistration(server: HassServer(baseURL: URL(string: "https://other")!), userID: "u1", webhookID: "w")
        await registrar(idle, store: InMemoryMobileAppRegistrationStore([elsewhere], active: elsewhere)).signOut()
        #expect(idle.requests.isEmpty)
    }

    @Test func signingInAfterARemovalRegistersFresh() async throws {
        let (_, store) = signedIn()
        let transport = StubHTTPTransport([(200, "{}"), (200, configJSON), (201, #"{"webhook_id":"fresh"}"#)])
        let registrar = registrar(transport, store: store)
        await registrar.signOut()
        let outcome = try await registrar.sync(userID: "u1", token: "aa")
        guard case let .registered(registration, _) = outcome else { Issue.record("expected register"); return }
        #expect(registration.webhookID == "fresh")
        // unregister, config, register: no update_registration on the removed webhook.
        #expect(transport.requests.count == 3)
        #expect(transport.requests[2].url?.path == "/api/mobile_app/registrations")
    }

    @Test func unregisterWithoutAuthSendsNoToken() async throws {
        let transport = StubHTTPTransport([(200, "{}"), (410, ""), (404, ""), (403, "")])
        let client = HomeAssistantPushClient(server: server, accessToken: { "t" }, transport: transport)
        #expect(try await client.unregister(webhookID: "w", authenticated: false) == .removed)
        #expect(try await client.unregister(webhookID: "w", authenticated: false) == .gone)
        #expect(try await client.unregister(webhookID: "w", authenticated: false) == .unsupported)
        await #expect(throws: PushClientError.status(403)) { try await client.unregister(webhookID: "w", authenticated: false) }
        #expect(transport.requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == nil })
    }

    // MARK: Pending retries

    private func retrier(_ transport: StubHTTPTransport, store: InMemoryMobileAppRegistrationStore) -> PendingUnregisterRetrier {
        PendingUnregisterRetrier(store: store, transport: transport) { device }
    }

    @Test func pendingRetrySuccessDropsTheEntry() async {
        let one = PendingUnregister(server: server, webhookID: "w1")
        let two = PendingUnregister(server: server, webhookID: "w2")
        let store = InMemoryMobileAppRegistrationStore(pending: [one, two])
        let transport = StubHTTPTransport([(200, "{}"), (410, "")])
        await retrier(transport, store: store).run()
        #expect(store.pendingUnregisters.isEmpty)
        #expect(transport.requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == nil })
    }

    @Test func pendingRetryKeepsEntriesThatCannotBeReachedOrServerFails() async {
        let one = PendingUnregister(server: server, webhookID: "w1")
        let store = InMemoryMobileAppRegistrationStore(pending: [one])
        let offline = StubHTTPTransport([])
        offline.error = URLError(.notConnectedToInternet)
        await retrier(offline, store: store).run()
        #expect(store.pendingUnregisters == [one])
        await retrier(StubHTTPTransport([(503, "")]), store: store).run()
        #expect(store.pendingUnregisters == [one])
        // 403 and 400 can never succeed.
        await retrier(StubHTTPTransport([(403, "")]), store: store).run()
        #expect(store.pendingUnregisters.isEmpty)
    }

    @Test func pendingRetryOnAnOldServerClearsPushDetailsAndDrops() async throws {
        let one = PendingUnregister(server: server, webhookID: "w1")
        let store = InMemoryMobileAppRegistrationStore(pending: [one])
        let transport = StubHTTPTransport([(404, ""), (200, "{}")])
        await retrier(transport, store: store).run()
        #expect(store.pendingUnregisters.isEmpty)
        #expect(transport.requests.count == 2)
        #expect(transport.requests[1].url?.path.hasSuffix("/api/webhook/w1") == true)
        #expect(body(transport.requests[1])["type"] as? String == "update_registration")
    }

    @Test func pendingEntriesSurviveInTheStoreList() throws {
        var list = MobileAppRegistrationList()
        list.addPending(PendingUnregister(server: server, webhookID: "w1"))
        list.addPending(PendingUnregister(server: server, webhookID: "w1"))
        #expect(list.pending.count == 1)
        let decoded = try JSONDecoder().decode(MobileAppRegistrationList.self, from: JSONEncoder().encode(list))
        #expect(decoded == list)
        // A list saved before pending existed still loads.
        let old = try JSONDecoder().decode(MobileAppRegistrationList.self, from: Data(#"{"registrations":[]}"#.utf8))
        #expect(old.pending.isEmpty)
        list.removePending(PendingUnregister(server: server, webhookID: "w1"))
        #expect(list.pending.isEmpty)
    }

    @Test func deviceTokensSurviveEveryRegistrationChange() throws {
        // A list saved before tokens existed has none; the tokens round-trip with the list.
        let old = try JSONDecoder().decode(MobileAppRegistrationList.self, from: Data(#"{"registrations":[]}"#.utf8))
        #expect(old.tokens == DeviceTokens())
        let tokens = DeviceTokens(push: "ab", startActivity: "ee")
        let list = MobileAppRegistrationList(tokens: tokens)
        #expect(try JSONDecoder().decode(MobileAppRegistrationList.self, from: JSONEncoder().encode(list)).tokens == tokens)

        let saved = MobileAppRegistration(server: server, userID: "u1", webhookID: "w1")
        let memory = InMemoryMobileAppRegistrationStore(tokens: tokens)
        let keychain = KeychainMobileAppRegistrationStore(service: "com.sfenton.home.push.tests.\(UUID().uuidString)")
        defer { keychain.setDeviceTokens(DeviceTokens()); keychain.remove(server: server, userID: "u1") }
        for store in [memory, keychain] as [any MobileAppRegistrationStore] {
            if store.deviceTokens == DeviceTokens() { store.setDeviceTokens(tokens) }
            store.save(saved)
            store.setActive(saved)
            // Sign-out forgets the user's webhook and the active pointer, never the install's tokens.
            store.setActive(nil)
            store.remove(server: server, userID: "u1")
            #expect(store.deviceTokens == tokens)
            store.setDeviceTokens(DeviceTokens(push: "cd", startActivity: "ee"))
            #expect(store.deviceTokens == DeviceTokens(push: "cd", startActivity: "ee"))
        }
    }

    @Test func firesActions() async throws {
        let saved = MobileAppRegistration(server: server, userID: "u1", webhookID: "w1")
        let transport = StubHTTPTransport([(200, "")])
        try await registrar(transport, store: InMemoryMobileAppRegistrationStore([saved], active: saved))
            .fireAction(PushActionEvent(action: "SNOOZE", tag: "t"))
        #expect(transport.requests.first?.url?.path == "/api/webhook/w1")

        await #expect(throws: PushClientError.signedOut) {
            try await registrar(StubHTTPTransport([]), store: InMemoryMobileAppRegistrationStore()).fireAction(PushActionEvent(action: "A", tag: nil))
        }
        let goneStore = InMemoryMobileAppRegistrationStore([saved], active: saved)
        await #expect(throws: PushClientError.registrationGone) {
            try await registrar(StubHTTPTransport([(410, "")]), store: goneStore).fireAction(PushActionEvent(action: "A", tag: nil))
        }
        #expect(goneStore.active == nil)
        #expect(goneStore.registration(server: server, userID: "u1") == nil)
    }
}

// MARK: - Stores

@Suite("Mobile app registration stores", .demoHouse)
struct MobileAppRegistrationStoreTests {
    @Test func listKeepsOnePerUser() {
        let store = InMemoryMobileAppRegistrationStore()
        let first = MobileAppRegistration(server: server, userID: "u1", webhookID: "a")
        let replaced = MobileAppRegistration(server: server, userID: "u1", webhookID: "b")
        let other = MobileAppRegistration(server: server, userID: "u2", webhookID: "c")
        store.save(first)
        store.save(replaced)
        store.save(other)
        store.setActive(replaced)
        #expect(store.registration(server: server, userID: "u1") == replaced)
        #expect(store.registration(server: server, userID: "u2") == other)
        store.remove(server: server, userID: "u2")
        #expect(store.active == replaced)
        store.remove(server: server, userID: "u1")
        #expect(store.active == nil)
        #expect(replaced.webhookURL.absoluteString == "https://ha.example.com/api/webhook/b")
    }

    @Test func storesSupplyTheActiveWebhook() async {
        let saved = MobileAppRegistration(server: server, userID: "u1", webhookID: "hook")
        let store = InMemoryMobileAppRegistrationStore([saved])
        let source: any MobileAppWebhookSource = store
        #expect(await source.currentWebhook() == nil, "saved but not signed in")
        store.setActive(saved)
        #expect(await source.currentWebhook() == saved.webhook)
        #expect(saved.webhook.url == saved.webhookURL)
        store.setActive(nil)
        #expect(await source.currentWebhook() == nil)
    }

    @Test func keychainRoundTrips() {
        let store = KeychainMobileAppRegistrationStore(service: "com.sfenton.home.push.tests.\(UUID().uuidString)")
        defer { store.remove(server: server, userID: "u1") }
        let saved = MobileAppRegistration(server: server, userID: "u1", webhookID: "kc")
        #expect(store.registration(server: server, userID: "u1") == nil)
        store.save(saved)
        store.setActive(saved)
        #expect(store.registration(server: server, userID: "u1") == saved)
        #expect(store.active == saved)
        store.remove(server: server, userID: "u1")
        #expect(store.active == nil)
        #expect(store.registration(server: server, userID: "u1") == nil)
    }

    @Test func tokenStoreRoundTripsAndFallsBack() throws {
        let service = "com.sfenton.home.auth.tests.\(UUID().uuidString)"
        let plain = KeychainTokenStore(service: service)
        // A group this test process has no entitlement for: saves fall back to an unshared item.
        let grouped = KeychainTokenStore(service: service, accessGroup: KeychainTokenStore.sharedAccessGroup)
        defer { plain.clear() }
        let credentials = StoredCredentials(server: server, refreshToken: "refresh")
        #expect(grouped.load() == nil)
        try plain.save(credentials)
        #expect(grouped.load() == credentials)
        try grouped.save(credentials)
        #expect(plain.load() == credentials)
        grouped.clear()
        #expect(plain.load() == nil)
    }
}

// MARK: - Payload

@Suite("Push payload", .demoHouse)
struct PushPayloadTests {
    @Test func readsTheFentonBlock() throws {
        let userInfo: [AnyHashable: Any] = [
            "aps": ["alert": ["title": "Doorbell"]],
            "fenton": [
                "v": 1, "tag": "doorbell", "group": "security",
                "url": "/sfenton-react-dash/home?path=security#camera-front-door",
                "entity_id": "camera.demo_front_door", "image": "/api/image/x", "video": "https://v/clip.mp4",
                "attachment": ["url": "https://a/file.pdf"],
                "actions": [
                    ["action": "OPEN", "title": "Open", "uri": "/sfenton-react-dash/home?path=security", "icon": "sfsymbols:door.left.hand.open"],
                    ["action": "SILENCE", "title": "Silence", "authenticationRequired": true, "destructive": true,
                     "activationMode": "foreground", "icon": "mdi:bell"],
                    ["action": "REPLY", "title": "Reply", "behavior": "textInput", "textInputButtonTitle": "Send it",
                     "textInputPlaceholder": "Say something"],
                    ["action": "", "title": "Dropped"],
                    ["title": "No id"],
                ],
                "ext": ["screen": "security"],
                "extra": ["presentation_options": ["alert", "sound"]],
            ] as [String: Any],
        ]
        let payload = try #require(PushPayload(userInfo: userInfo))
        #expect(payload.tag == "doorbell")
        #expect(payload.group == "security")
        #expect(payload.entityID == "camera.demo_front_door")
        #expect(payload.image == "/api/image/x")
        #expect(payload.video == "https://v/clip.mp4")
        #expect(payload.attachmentURL == "https://a/file.pdf")
        #expect(payload.ext?["screen"]?.string == "security")
        #expect(payload.extra?["presentation_options"]?.array?.count == 2)
        #expect(payload.command == nil)
        #expect(payload.actions.map(\.action) == ["OPEN", "SILENCE", "REPLY"])
        let open = try #require(payload.action("OPEN"))
        #expect(open.symbol == "door.left.hand.open")
        #expect(open.activationMode == .foreground)
        let silence = try #require(payload.action("SILENCE"))
        #expect(silence.authenticationRequired && silence.destructive)
        #expect(silence.symbol == nil)
        #expect(silence.activationMode == .foreground)
        let reply = try #require(payload.action("REPLY"))
        #expect(reply.isTextInput)
        #expect(reply.activationMode == .background)
        #expect(reply.textInputButtonTitle == "Send it")
        #expect(payload.action("MISSING") == nil)
    }

    @Test func theOfficialAppsCommandBlockIsRead() {
        // A push built for the companion app carries `homeassistant.command`, not the `fenton` block.
        let official: [AnyHashable: Any] = ["aps": ["content-available": 1], "homeassistant": ["command": "request_location_update"]]
        #expect(PushPayload(userInfo: official)?.command == .requestLocationUpdate)
        let clear: [AnyHashable: Any] = ["homeassistant": ["command": "clear_notification", "tag": "door"]]
        #expect(PushPayload(userInfo: clear)?.command == .clearNotification(tag: "door"))
        #expect(PushPayload(userInfo: ["homeassistant": ["command": "clear_notification"]])?.command == .unsupported("clear_notification"))
        #expect(PushPayload(userInfo: ["homeassistant": ["command": "update_widgets"]])?.command == .unsupported("update_widgets"))
        #expect(PushPayload(userInfo: ["homeassistant": ["command": ""]]) == nil)
        #expect(PushPayload(userInfo: ["homeassistant": "text"]) == nil)
        #expect(PushPayload(userInfo: ["homeassistant": ["live_update": true]]) == nil)
        // The relay's own block wins; the official block fills in when it has no command.
        let both: [AnyHashable: Any] = ["fenton": ["v": 1, "command": "clear_notification", "tag": "a"],
                                        "homeassistant": ["command": "request_location_update"]]
        #expect(PushPayload(userInfo: both)?.command == .clearNotification(tag: "a"))
        let fillIn: [AnyHashable: Any] = ["fenton": ["v": 1, "tag": "a"], "homeassistant": ["command": "request_location_update"]]
        #expect(PushPayload(userInfo: fillIn)?.command == .requestLocationUpdate)
        #expect(PushPayload(userInfo: ["fenton": ["v": 2]]) == nil)
    }

    @Test func commandsAndVersions() {
        #expect(PushPayload(json: .object(["v": .number(1), "command": "clear_notification", "tag": "door"]))?.command == .clearNotification(tag: "door"))
        #expect(PushPayload(json: .object(["command": "clear_notification"]))?.command == .unsupported("clear_notification"))
        #expect(PushPayload(json: .object(["command": "request_location_update"]))?.command == .requestLocationUpdate)
        #expect(PushPayload(json: .object(["command": "update_widgets"]))?.command == .unsupported("update_widgets"))
        #expect(PushPayload(json: .object(["v": .number(2), "tag": "x"])) == nil)
        #expect(PushPayload(json: .string("nope")) == nil)
        #expect(PushPayload(userInfo: ["aps": [:]]) == nil)
        #expect(PushPayload(json: .object(["tag": ""]))?.tag == nil)
        #expect(PushAction.symbol(fromIcon: "sfsymbols: ") == nil)
    }
}

// MARK: - Links

@Suite("Push links", .demoHouse)
struct PushLinkTests {
    @Test func dashboardLinks() {
        #expect(PushLink("/sfenton-react-dash/home?path=security#security-system") == .dashboard(path: "security", anchor: "security-system"))
        #expect(PushLink("/sfenton-react-dash/home?path=overview&user=sam&tab=auto#daily-report") == .dashboard(path: "overview", anchor: "daily-report"))
        #expect(PushLink("/sfenton-react-dash/home?route=%2Fsfenton-react-dash%2Fgarage%3Fx%3D1") == .dashboard(path: "garage", anchor: nil))
        #expect(PushLink("/sfenton-react-dash/kitchen") == .dashboard(path: "kitchen", anchor: nil))
        #expect(PushLink("/sfenton-react-dash/home") == .dashboard(path: "overview", anchor: nil))
        #expect(PushLink("/sfenton-react-dash/home?path=") == .dashboard(path: "overview", anchor: nil))
        #expect(PushLink("/") == .dashboard(path: "overview", anchor: nil))
        #expect(PushLink("https://HA.example.com/sfenton-react-dash/home?path=office", server: server) == .dashboard(path: "office", anchor: nil))
    }

    @Test func otherLinks() {
        #expect(PushLink("/config/automation/trace/automation.demo_x") == .homeAssistant(path: "/config/automation/trace/automation.demo_x"))
        #expect(PushLink("https://example.org/page") == .external(URL(string: "https://example.org/page")!))
        #expect(PushLink("https://ha.example.com/x") == .external(URL(string: "https://ha.example.com/x")!))
        #expect(PushLink("") == nil)
        #expect(PushLink("noAction") == nil)
        #expect(PushLink("entityId:light.demo_kitchen_item_1") == nil)
        #expect(PushLink("http://[bad") == nil)
    }

    @Test func destinations() {
        let cases: [(String, PushDestination)] = [
            ("overview", .section(.home)), ("", .section(.home)), ("security", .section(.security)),
            ("thermostat", .section(.climate)), ("chores", .section(.chores)), ("sams-chores", .section(.chores)),
            ("groceries", .section(.chores)), ("admin", .section(.settings)), ("to-do", .section(.settings)),
            ("master-bedroom", .homePage("master-bedroom")), ("grocery-list", .homePage("grocery-list")),
            ("all-food", .homePage("all-food")), ("car", .section(.settings)),
        ]
        for (path, destination) in cases {
            #expect(PushDestination(dashboardPath: path) == destination, "\(path)")
        }
    }
}

// MARK: - Categories and attachments

@Suite("Push categories and attachments", .demoHouse)
struct PushCategoryTests {
    let actions = [PushAction(action: "LOCK", title: "Lock"), PushAction(action: "IGNORE", title: "Ignore", destructive: true)]

    @Test func identifierIsStable() throws {
        let category = try #require(PushCategory(actions: actions))
        #expect(category.identifier.hasPrefix("fenton.dynamic."))
        #expect(PushCategory(actions: actions)?.identifier == category.identifier)
        #expect(PushCategory(actions: [actions[0]])?.identifier != category.identifier)
        #expect(PushCategory(actions: []) == nil)
    }

    @Test func buttonsAreCappedAtWhatTheSystemPresents() throws {
        let many = (0..<6).map { PushAction(action: "A\($0)", title: "Button \($0)") }
        let category = try #require(PushCategory(actions: many))
        #expect(category.actions.map(\.action) == ["A0", "A1", "A2", "A3"])
        #expect(PushCategory(cameraActions: many).actions.count == PushCategory.maxActions)
        #if canImport(UserNotifications)
        #expect(category.notificationCategory.hiddenPreviewsBodyPlaceholder == PushCategory.hiddenPreviewsPlaceholder)
        #endif
    }

    @Test func mergeKeepsFixedAndCapsBuilt() throws {
        let category = try #require(PushCategory(actions: actions))
        let built = (0..<40).map { "fenton.dynamic.\($0)" }
        let merged = category.identifiers(merging: ["calendar"] + built + [category.identifier])
        #expect(merged.first == "calendar")
        #expect(merged.last == category.identifier)
        #expect(merged.filter { $0.hasPrefix(PushCategory.prefix) }.count == PushCategory.limit)
        #expect(!merged.contains("fenton.dynamic.0"))
    }

    #if canImport(UserNotifications)
    @Test func systemCategory() throws {
        let reply = PushAction(action: "REPLY", title: "Reply", symbol: "text.bubble", authenticationRequired: true,
                               activationMode: .foreground, isTextInput: true)
        let category = try #require(PushCategory(actions: actions + [reply]))
        let system = category.notificationCategory
        #expect(system.identifier == category.identifier)
        #expect(system.actions.map(\.identifier) == ["LOCK", "IGNORE", "REPLY"])
        #expect(system.actions[1].options.contains(.destructive))
        let text = try #require(system.actions[2] as? UNTextInputNotificationAction)
        #expect(text.textInputButtonTitle == "Send")
        #expect(text.options.contains(.authenticationRequired) && text.options.contains(.foreground))
        let existing: Set<UNNotificationCategory> = [UNNotificationCategory(identifier: "calendar", actions: [], intentIdentifiers: [])]
        #expect(Set(category.merged(into: existing).map(\.identifier)) == ["calendar", category.identifier])
    }
    #endif

    @Test func attachmentSources() {
        let camera = PushAttachmentSource.resolve(PushPayload(entityID: "camera.demo_front_door", image: "https://x/y.png"), server: server)
        #expect(camera == PushAttachmentSource(url: URL(string: "https://ha.example.com/api/camera_proxy/camera.demo_front_door")!,
                                              kind: .image, needsAuthorization: true))
        #expect(PushAttachmentSource.resolve(PushPayload(entityID: "lock.demo_front", image: "/local/a.jpg"), server: server)
            == PushAttachmentSource(url: URL(string: "https://ha.example.com/local/a.jpg")!, kind: .image, needsAuthorization: true))
        #expect(PushAttachmentSource.resolve(PushPayload(video: "https://cdn.example.org/c.mp4"), server: server)
            == PushAttachmentSource(url: URL(string: "https://cdn.example.org/c.mp4")!, kind: .video, needsAuthorization: false))
        #expect(PushAttachmentSource.resolve(PushPayload(image: "ftp://nope", attachmentURL: "https://ha.example.com/f.pdf"), server: server)
            == PushAttachmentSource(url: URL(string: "https://ha.example.com/f.pdf")!, kind: .file, needsAuthorization: true))
        #expect(PushAttachmentSource.resolve(PushPayload(image: "  "), server: server) == nil)
        #expect(PushAttachmentSource.resolve(PushPayload(), server: server) == nil)
    }

    @Test func attachmentFileTypes() {
        let image = PushAttachmentSource(url: URL(string: "https://x/snap")!, kind: .image, needsAuthorization: false)
        let mimes: [(String?, String)] = [("image/jpeg", "jpg"), ("image/JPG", "jpg"), ("image/png", "png"), ("image/gif", "gif"),
                                          ("image/heic", "heic"), ("video/mp4", "mp4"), ("video/quicktime", "mov"),
                                          ("audio/mpeg", "mp3"), ("application/pdf", "pdf"), (nil, "jpg")]
        for (mime, ext) in mimes { #expect(image.fileExtension(mimeType: mime) == ext) }
        #expect(PushAttachmentSource(url: URL(string: "https://x/a.webp")!, kind: .image, needsAuthorization: false).fileExtension(mimeType: "x/y") == "webp")
        #expect(PushAttachmentSource(url: URL(string: "https://x/clip")!, kind: .video, needsAuthorization: false).fileExtension(mimeType: nil) == "mp4")
        #expect(image.byteLimit == 10_000_000)
        #expect(PushAttachmentSource(url: image.url, kind: .video, needsAuthorization: false).byteLimit == 50_000_000)
        #expect(PushAttachmentSource(url: image.url, kind: .file, needsAuthorization: false).byteLimit == 5_000_000)
    }
}

// MARK: - Enrichment

@Suite("Push enrichment", .demoHouse)
struct PushEnrichmentTests {
    @Test func plansCategoryThreadAndAttachment() {
        let payload = PushPayload(group: "garage", actions: [PushAction(action: "CLOSE", title: "Close")], entityID: "camera.demo_front")
        let plan = PushEnrichment(payload: payload, categoryIdentifier: PushPayload.dynamicCategory, threadIdentifier: "", server: server)
        #expect(plan.category?.actions.map(\.action) == ["CLOSE"])
        #expect(!plan.clearsPlaceholderCategory)
        #expect(plan.threadIdentifier == "garage")
        #expect(plan.attachment?.url.path == "/api/camera_proxy/camera.demo_front")

        let plain = PushEnrichment(payload: PushPayload(group: "g"), categoryIdentifier: PushPayload.dynamicCategory,
                                   threadIdentifier: "relay-thread", server: nil)
        #expect(plain.category == nil)
        #expect(plain.clearsPlaceholderCategory)
        #expect(plain.threadIdentifier == nil, "the relay's thread wins")
        #expect(plain.attachment == nil, "no server, no attachment")
        #expect(!PushEnrichment(payload: PushPayload(), categoryIdentifier: "calendar", threadIdentifier: "", server: nil).clearsPlaceholderCategory)
    }

    @Test func cameraNotificationsUseTheFixedCameraCategory() {
        let buttons = [PushAction(action: "VIEW", title: "View", uri: "/x")]
        let camera = PushEnrichment(payload: PushPayload(actions: buttons, entityID: "camera.demo_front"),
                                    categoryIdentifier: PushPayload.dynamicCategory, threadIdentifier: "", server: nil)
        #expect(camera.category?.identifier == PushCategory.camera)
        #expect(camera.category?.actions == buttons)
        let silent = PushEnrichment(payload: PushPayload(entityID: "camera.demo_front"), categoryIdentifier: "", threadIdentifier: "", server: nil)
        #expect(silent.category?.identifier == PushCategory.camera, "the live view needs the category even without buttons")
        #expect(!silent.clearsPlaceholderCategory)
        // Registered once, next to the others.
        #expect(PushCategory(cameraActions: buttons).identifiers(merging: ["calendar", PushCategory.camera]) == ["calendar", PushCategory.camera])
    }

    #if canImport(UserNotifications)
    @Test func appliesToContent() {
        let content = UNMutableNotificationContent()
        content.categoryIdentifier = PushPayload.dynamicCategory
        let built = PushEnrichment(payload: PushPayload(group: "g", actions: [PushAction(action: "A", title: "A")]),
                                   categoryIdentifier: content.categoryIdentifier, threadIdentifier: "", server: nil)
        built.apply(to: content)
        #expect(content.categoryIdentifier.hasPrefix(PushCategory.prefix))
        #expect(content.threadIdentifier == "g")
        let cleared = UNMutableNotificationContent()
        cleared.categoryIdentifier = PushPayload.dynamicCategory
        PushEnrichment(payload: PushPayload(), categoryIdentifier: cleared.categoryIdentifier, threadIdentifier: "t", server: nil)
            .apply(to: cleared)
        #expect(cleared.categoryIdentifier.isEmpty)
        #expect(cleared.threadIdentifier.isEmpty)
    }
    #endif

    @Test func loaderDownloadsWithinLimits() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("push-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let snapshot = PushAttachmentSource(url: URL(string: "https://ha.example.com/api/camera_proxy/camera.demo_x")!, kind: .image, needsAuthorization: true)
        let transport = StubHTTPTransport([(200, "jpeg-bytes")])
        let file = try #require(await PushAttachmentLoader(transport: transport, directory: directory).load(snapshot, accessToken: "tok"))
        #expect(try String(contentsOf: file, encoding: .utf8) == "jpeg-bytes")
        #expect(file.pathExtension == "jpg")
        #expect(transport.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer tok")

        // No token for a server file, a failed status, an empty body: nothing.
        #expect(await PushAttachmentLoader(transport: StubHTTPTransport([]), directory: directory).load(snapshot, accessToken: nil) == nil)
        #expect(await PushAttachmentLoader(transport: StubHTTPTransport([(404, "x")]), directory: directory).load(snapshot, accessToken: "t") == nil)
        #expect(await PushAttachmentLoader(transport: StubHTTPTransport([(200, "")]), directory: directory).load(snapshot, accessToken: "t") == nil)
        // Over the limit.
        let file5 = PushAttachmentSource(url: URL(string: "https://cdn/x.pdf")!, kind: .file, needsAuthorization: false)
        let big = String(repeating: "x", count: 5_000_001)
        #expect(await PushAttachmentLoader(transport: StubHTTPTransport([(200, big)]), directory: directory).load(file5, accessToken: nil) == nil)
        // A public file needs no token; an unwritable folder fails.
        let open = StubHTTPTransport([(200, "pdf")])
        #expect(await PushAttachmentLoader(transport: open, directory: directory).load(file5, accessToken: nil)?.pathExtension == "pdf")
        #expect(open.requests.first?.value(forHTTPHeaderField: "Authorization") == nil)
        let missing = directory.appendingPathComponent("missing/deeper")
        #expect(await PushAttachmentLoader(transport: StubHTTPTransport([(200, "pdf")]), directory: missing).load(file5, accessToken: nil) == nil)
        #expect(PushAttachmentSource(url: snapshot.url, kind: .image, needsAuthorization: false).fileExtension(mimeType: "image/png; q=1") == "png")
    }
}

// MARK: - Trace

@Suite("Push trace", .demoHouse)
struct PushTraceTests {
    @Test func recordsAndTrims() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("trace-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let trace = PushTrace(directory: directory)
        for index in 0..<(PushTrace.limit + 5) { trace.record("step \(index)") }
        let lines = trace.lines()
        #expect(lines.count == PushTrace.limit)
        #expect(lines.last?.hasSuffix("step \(PushTrace.limit + 4)") == true)
        // No directory: nothing recorded.
        let off = PushTrace(directory: nil)
        off.record("ignored")
        #expect(off.lines().isEmpty)
        _ = PushTrace.shared
    }

    @Test func loaderNotesNetworkFailures() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("trace-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let trace = PushTrace(directory: directory)
        let offline = StubHTTPTransport([])
        offline.error = URLError(.timedOut)
        let source = PushAttachmentSource(url: URL(string: "https://cdn/x.jpg")!, kind: .image, needsAuthorization: false)
        #expect(await PushAttachmentLoader(transport: offline, directory: directory, trace: trace).load(source, accessToken: nil) == nil)
        #expect(trace.lines().last?.contains("attachment failed: /x.jpg") == true)
    }
}

// MARK: - MJPEG

@Suite("MJPEG frame scanner", .demoHouse)
struct MJPEGFrameScannerTests {
    let frameA = Data([0xFF, 0xD8, 0x01, 0x02, 0xFF, 0xD9])
    let frameB = Data([0xFF, 0xD8, 0x03, 0xFF, 0xD9])

    @Test func findsFramesAcrossChunks() {
        var scanner = MJPEGFrameScanner()
        let header = Data("--frame\r\nContent-Type: image/jpeg\r\n\r\n".utf8)
        let stream = header + frameA + Data("\r\n".utf8) + header + frameB + Data("\r\n".utf8)
        var frames: [Data] = []
        // Byte by byte: markers split across chunks still match.
        for byte in stream { frames += scanner.append(Data([byte])) }
        #expect(frames == [frameA, frameB])
        // Whole stream at once.
        var whole = MJPEGFrameScanner()
        #expect(whole.append(stream) == [frameA, frameB])
    }

    @Test func dropsJunkAndWaitsForTheEnd() {
        var scanner = MJPEGFrameScanner()
        #expect(scanner.append(Data([0x00, 0x11, 0xFF])).isEmpty)
        #expect(scanner.append(Data([0xD8, 0x05])).isEmpty, "a frame without its end waits")
        #expect(scanner.append(Data([0xFF, 0xD9])) == [Data([0xFF, 0xD8, 0x05, 0xFF, 0xD9])])
        // A start marker's own D8 is not taken for an end.
        #expect(scanner.append(Data([0xFF, 0xD8, 0xD9])).isEmpty)
    }

    @Test func dropsAnOversizedFrame() {
        var scanner = MJPEGFrameScanner()
        let huge = Data([0xFF, 0xD8]) + Data(repeating: 0x01, count: MJPEGFrameScanner.maxFrameBytes)
        #expect(scanner.append(huge).isEmpty)
        #expect(scanner.append(frameB) == [frameB], "resynchronizes on the next frame")
    }
}

@Suite("MJPEG chunk stream", .demoHouse)
struct MJPEGChunkStreamTests {
    final class Stub: URLProtocol {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            let status = request.url?.lastPathComponent == "denied" ? 401 : 200
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!,
                                cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data([0xFF, 0xD8, 0x01]))
            client?.urlProtocol(self, didLoad: Data([0xFF, 0xD9]))
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    @Test func deliversStatusAndChunksInOrder() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Stub.self]
        let stream = MJPEGChunkStream.open(URLRequest(url: URL(string: "https://example.test/ok")!), configuration: configuration)
        #expect(await stream.statusCode() == 200)
        var scanner = MJPEGFrameScanner()
        var frames: [Data] = []
        for try await chunk in stream.chunks { frames += scanner.append(chunk) }
        #expect(frames == [Data([0xFF, 0xD8, 0x01, 0xFF, 0xD9])])
    }

    @Test func reportsANon200Status() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Stub.self]
        let stream = MJPEGChunkStream.open(URLRequest(url: URL(string: "https://example.test/denied")!), configuration: configuration)
        #expect(await stream.statusCode() == 401)
    }
}
