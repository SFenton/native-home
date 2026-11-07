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
private let fix = LocationFix(latitude: 37.6, longitude: -122.3, horizontalAccuracy: 8, timestamp: .now)

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

// MARK: - Location

/// Location: starts on a webhook and permission, with no switch; offers the screen once.
@MainActor
struct LocationCoordinatorTests {
    struct Harness {
        let platform: FakeLocationPlatform
        let transport: StubHTTPTransport
        let store: InMemoryMobileAppRegistrationStore
        let mobileApp: MobileAppCoordinator
        let location: LocationCoordinator
        let defaults: UserDefaults
    }

    func harness(_ permission: LocationPermission, replies: [StubHTTPTransport.Reply] = [],
                 saved: MobileAppRegistration? = nil, defaults: UserDefaults = freshDefaults(),
                 inBackground: @escaping @MainActor () -> Bool = { false }) -> Harness {
        let platform = FakeLocationPlatform(permission)
        let transport = StubHTTPTransport(replies)
        let store = InMemoryMobileAppRegistrationStore(saved.map { [$0] } ?? [], active: saved)
        let mobileApp = MobileAppCoordinator(device: device, store: store, transport: transport)
        let location = LocationCoordinator(platform: platform, mobileApp: mobileApp,         transport: transport, batteryLevel: { 64 }, defaults: defaults,
                                      isInBackground: inBackground)
        return Harness(platform: platform, transport: transport, store: store, mobileApp: mobileApp, location: location,
                       defaults: defaults)
    }

    @Test func startsOnceRegisteredAndStopsOnSignOut() async {
        let h = harness(LocationPermission(authorization: .always),
                        replies: [(200, configJSON), (201, #"{"webhook_id":"w1"}"#), (200, zonesJSON), (200, "{}"), (200, "{}")])
        h.platform.fixes = [fix]
        h.mobileApp.sessionStarted(server: server) { "token" }
        _ = h.mobileApp.begin(userID: "u1", userName: nil)
        await h.mobileApp.sync()
        await eventually { h.location.reporter.lastReportDate != nil }
        #expect(h.location.reporter.isRunning)
        #expect(paths(h.transport) == ["/api/fenton_home/config", "/api/mobile_app/registrations",
                                       "/api/webhook/w1 get_zones", "/api/webhook/w1 update_location"])

        await h.mobileApp.sessionEnded()
        await eventually { !h.location.reporter.isRunning }
        #expect(!h.location.reporter.isRunning)
    }

    @Test func resumesOnTheSavedWebhookWithoutASync() async {
        let saved = MobileAppRegistration(server: server, userID: "u1", webhookID: "w1")
        let h = harness(LocationPermission(authorization: .whenInUse), replies: [(200, zonesJSON), (200, "{}"), (200, "{}")],
                        saved: saved)
        h.platform.fixes = [fix, LocationFix(latitude: 37.7, longitude: -122.3, horizontalAccuracy: 8, timestamp: .now)]
        await h.location.resume()
        #expect(h.location.reporter.isRunning)
        #expect(paths(h.transport) == ["/api/webhook/w1 get_zones", "/api/webhook/w1 update_location"])

        // Coming back to the foreground sends another fix (While Using reports only then).
        h.location.didEnterBackground()
        await h.location.didBecomeActive()
        #expect(paths(h.transport).last == "/api/webhook/w1 update_location")
        #expect(h.location.reporter.lastTrigger == .launch)
    }

    /// Whether the app is in the background, moved by a test.
    @MainActor final class AppState { var inBackground = false }

    private func updateCount(_ h: Harness) -> Int { paths(h.transport).filter { $0.hasSuffix("update_location") }.count }

    @Test func theLaunchUpdateIsSentOncePerForegroundSession() async {
        let saved = MobileAppRegistration(server: server, userID: "u1", webhookID: "w1")
        let h = harness(LocationPermission(authorization: .whenInUse), replies: [(200, zonesJSON)] + Array(repeating: (200, "{}"), count: 6),
                        saved: saved)
        h.platform.fixes = (0..<4).map { LocationFix(latitude: 37.6 + Double($0) / 100, longitude: -122.3, horizontalAccuracy: 8, timestamp: .now) }
        await h.location.resume()
        #expect(updateCount(h) == 1, "The cold launch sends it")
        // Reactivations inside the session (a system alert, the app switcher) send nothing.
        await h.location.didBecomeActive()
        await h.location.didBecomeActive()
        #expect(updateCount(h) == 1)
        // Leaving and coming back is a new session.
        h.location.didEnterBackground()
        await h.location.didBecomeActive()
        #expect(updateCount(h) == 2)
        #expect(h.location.reporter.lastTrigger == .launch)
        await h.location.didBecomeActive()
        #expect(updateCount(h) == 2)
    }

    @Test func aBackgroundRelaunchSendsNoLaunchUpdateUntilTheAppOpens() async {
        let state = AppState()
        state.inBackground = true
        let saved = MobileAppRegistration(server: server, userID: "u1", webhookID: "w1")
        let h = harness(LocationPermission(authorization: .always), replies: [(200, zonesJSON)] + Array(repeating: (200, "{}"), count: 4),
                        saved: saved, inBackground: { state.inBackground })
        h.platform.fixes = [fix]
        await h.location.resume()
        #expect(h.location.reporter.isRunning)
        #expect(updateCount(h) == 0, "A relaunch for a zone event is not the person opening the app")
        state.inBackground = false
        await h.location.didBecomeActive()
        #expect(updateCount(h) == 1)
        #expect(h.location.reporter.lastTrigger == .launch)
    }

    @Test func aPushRequestSendsAFixWithThePushTrigger() async {
        let saved = MobileAppRegistration(server: server, userID: "u1", webhookID: "w1")
        let h = harness(LocationPermission(authorization: .always), replies: [(200, zonesJSON)] + Array(repeating: (200, "{}"), count: 4),
                        saved: saved)
        h.platform.fixes = [fix, LocationFix(latitude: 37.7, longitude: -122.3, horizontalAccuracy: 8, timestamp: .now)]
        await h.location.resume()
        #expect(await h.location.handleLocationRequest())
        #expect(h.location.reporter.lastTrigger == .pushNotification)
        #expect(h.platform.timeouts.last == 10, "Push fixes wait 10 s at most")
        #expect(updateCount(h) == 2)
    }

    @Test func aPushRequestStartsReportingWhenTheRelaunchGetsThereFirst() async {
        let state = AppState()
        state.inBackground = true
        let saved = MobileAppRegistration(server: server, userID: "u1", webhookID: "w1")
        // The relaunch reads the zones after its update, so the update's reply comes first.
        let h = harness(LocationPermission(authorization: .always), replies: [(200, "{}"), (200, zonesJSON)],
                        saved: saved, inBackground: { state.inBackground })
        h.platform.fixes = [fix]
        #expect(!h.location.reporter.isRunning)
        #expect(await h.location.handleLocationRequest(), "No resume() yet: the request starts reporting itself")
        #expect(h.location.reporter.lastTrigger == .pushNotification)
        #expect(updateCount(h) == 1, "And no launch update in the background")
    }

    @Test func aBackgroundPushWithWhileUsingOnlySendsNothing() async {
        let state = AppState()
        let saved = MobileAppRegistration(server: server, userID: "u1", webhookID: "w1")
        let h = harness(LocationPermission(authorization: .whenInUse), replies: [(200, zonesJSON)] + Array(repeating: (200, "{}"), count: 4),
                        saved: saved, inBackground: { state.inBackground })
        h.platform.fixes = [fix, LocationFix(latitude: 37.7, longitude: -122.3, horizontalAccuracy: 8, timestamp: .now)]
        await h.location.resume()
        state.inBackground = true
        #expect(!(await h.location.handleLocationRequest()), "A fix cannot be taken in the background")
        #expect(updateCount(h) == 1)
        state.inBackground = false
        #expect(await h.location.handleLocationRequest(), "In the foreground While Using is enough")
        #expect(updateCount(h) == 2)
    }

    @Test func aPushRequestWithoutAWebhookDoesNothing() async {
        let h = harness(LocationPermission(authorization: .always))
        #expect(!(await h.location.handleLocationRequest()))
        #expect(h.transport.requests.isEmpty)
    }

    @Test func aBackgroundFetchSendsALocationUpdateWithTheFetchTrigger() async {
        let state = AppState()
        state.inBackground = true
        let saved = MobileAppRegistration(server: server, userID: "u1", webhookID: "w1")
        let h = harness(LocationPermission(authorization: .always), replies: [(200, "{}"), (200, zonesJSON)],
                        saved: saved, inBackground: { state.inBackground })
        h.platform.fixes = [fix]
        var sensorRuns = 0
        h.location.sendSensorsOnly = { sensorRuns += 1 }
        #expect(await h.location.backgroundFetch())
        #expect(h.location.reporter.lastTrigger == .backgroundFetch)
        #expect(h.platform.timeouts.last == 10)
        #expect(sensorRuns == 0, "Location was allowed")
    }

    @Test func aBackgroundFetchWithoutBackgroundLocationSendsSensorsOnly() async {
        let state = AppState()
        state.inBackground = true
        let saved = MobileAppRegistration(server: server, userID: "u1", webhookID: "w1")
        let h = harness(LocationPermission(authorization: .whenInUse), replies: [(200, zonesJSON)],
                        saved: saved, inBackground: { state.inBackground })
        h.platform.fixes = [fix]
        var sensorRuns = 0
        h.location.sendSensorsOnly = { sensorRuns += 1 }
        #expect(await h.location.backgroundFetch())
        #expect(sensorRuns == 1)
        #expect(updateCount(h) == 0, "No location update: While Using cannot take a fix in the background")
    }

    @Test func aBackgroundFetchWithoutAWebhookFails() async {
        let h = harness(LocationPermission(authorization: .always))
        var sensorRuns = 0
        h.location.sendSensorsOnly = { sensorRuns += 1 }
        #expect(!(await h.location.backgroundFetch()))
        #expect(sensorRuns == 0)
    }

    @Test func startsWhenPermissionArrives() async {
        let saved = MobileAppRegistration(server: server, userID: "u1", webhookID: "w1")
        let h = harness(.notDetermined, replies: [(200, zonesJSON), (200, "{}")], saved: saved)
        h.platform.fixes = [fix]
        await h.location.resume()
        #expect(!h.location.reporter.isRunning, "nothing allowed yet")
        await h.location.didBecomeActive()
        #expect(!h.location.reporter.isRunning)

        let allowed = LocationPermission(authorization: .whenInUse)
        h.platform.permission = allowed
        h.platform.onEvent?(.permissionChanged(allowed))
        await eventually { h.location.reporter.lastReportDate != nil }
        #expect(h.location.reporter.isRunning)
    }

    @Test func aDeletedRegistrationRegistersAgainAndResumes() async {
        let saved = MobileAppRegistration(server: server, userID: "u1", webhookID: "old")
        let h = harness(LocationPermission(authorization: .whenInUse),
                        replies: [(410, ""), (200, configJSON), (410, ""), (201, #"{"webhook_id":"fresh"}"#),
                                  (200, zonesJSON), (200, "{}")],
                        saved: saved)
        h.platform.fixes = [fix]
        h.mobileApp.sessionStarted(server: server) { "token" }
        _ = h.mobileApp.begin(userID: "u1", userName: nil)
        await h.location.resume()
        await eventually { h.location.reporter.lastReportDate != nil }
        #expect(h.store.active?.webhookID == "fresh")
        #expect(h.location.reporter.isRunning)
        #expect(paths(h.transport) == ["/api/webhook/old get_zones", "/api/fenton_home/config", "/api/webhook/old update_registration",
                                       "/api/mobile_app/registrations", "/api/webhook/fresh get_zones",
                                       "/api/webhook/fresh update_location"])
    }

    @Test func theLocationStepNeedsAskingWhileThereIsSomethingToAsk() {
        #expect(harness(.notDetermined).location.needsPermissionStep)
        #expect(harness(LocationPermission(authorization: .whenInUse)).location.needsPermissionStep, "While Using can still be upgraded")
        // Nothing to ask: Always, Off, Approximate.
        for permission in [LocationPermission(authorization: .always), LocationPermission(authorization: .denied),
                           LocationPermission(authorization: .always, isPrecise: false)] {
            #expect(!harness(permission).location.needsPermissionStep)
        }
        // The old offered flag is only read by the Setup flow's migration (SetupFlow); it neither hides nor shows the step.
        let defaults = freshDefaults()
        defaults.set(true, forKey: LocationCoordinator.offeredKey)
        #expect(harness(.notDetermined, defaults: defaults).location.needsPermissionStep)
        SetupFlow.markSeen(.timeSensitive, in: defaults)
        LocationCoordinator.resetOffers(in: defaults)
        #expect(!defaults.bool(forKey: LocationCoordinator.offeredKey))
        #expect(defaults.stringArray(forKey: SetupFlow.seenKey) == nil, "a journey reset forgets the seen steps too")
    }

    @Test func aPhoneLinksItsTrackerToThePersonAndAnIPadNeverDoes() async {
        let saved = MobileAppRegistration(server: server, userID: "u1", webhookID: "w1")
        let user = HassUser(id: "u1", name: "Alex", isOwner: false, isAdmin: true)
        for linksPresence in [true, false] {
            let platform = FakeLocationPlatform(LocationPermission(authorization: .always))
            let transport = StubHTTPTransport([])
            let mobileApp = MobileAppCoordinator(device: device, store: InMemoryMobileAppRegistrationStore([saved], active: saved),
                                                 transport: transport)
            mobileApp.sessionStarted(server: server) { "token" }
            _ = mobileApp.begin(userID: "u1", userName: nil)
            await mobileApp.sync()
            let location = LocationCoordinator(platform: platform, mobileApp: mobileApp, transport: transport, batteryLevel: { 64 },
                                               linksPresence: linksPresence, defaults: freshDefaults())
            #expect(location.linksPresence == linksPresence)
            let api = CountingAPI()
            await location.linkPresence(user: user, api: api)
            // Permission going away and coming back must not touch the person either.
            await location.permissionChanged(LocationPermission(authorization: .denied))
            await location.permissionChanged(LocationPermission(authorization: .always))
            try? await location.unlinkPresence(user: user, api: api)
            if linksPresence {
                #expect(!api.commands.isEmpty, "a phone reaches Home Assistant's registry to link its tracker")
            } else {
                #expect(api.commands.isEmpty, "PresenceLinker is never invoked for an iPad: \(api.commands)")
                #expect(location.mobileAppPresenceLink == nil)
            }
        }
    }

    @Test func anIPadStillStartsReportingOnItsOwnTracker() async {
        let saved = MobileAppRegistration(server: server, userID: "u1", webhookID: "w1")
        let platform = FakeLocationPlatform(LocationPermission(authorization: .whenInUse))
        platform.fixes = [fix]
        let transport = StubHTTPTransport([(200, zonesJSON), (200, "{}")])
        let mobileApp = MobileAppCoordinator(device: device, store: InMemoryMobileAppRegistrationStore([saved], active: saved),
                                             transport: transport)
        let location = LocationCoordinator(platform: platform, mobileApp: mobileApp, transport: transport, batteryLevel: { 64 },
                                           linksPresence: false, defaults: freshDefaults())
        await location.resume()
        #expect(location.reporter.isRunning)
        #expect(paths(transport) == ["/api/webhook/w1 get_zones", "/api/webhook/w1 update_location"])
    }

    @Test func remembersTheAlwaysRequest() {
        let defaults = freshDefaults()
        let h = harness(LocationPermission(authorization: .whenInUse), defaults: defaults)
        #expect(h.location.needsPermissionStep, "While Using can still be upgraded")
        h.location.requestPermission()
        #expect(h.location.hasAskedForAlways)
        #expect(h.platform.calls == ["always"])

        // iOS shows the Always alert once: a later launch neither offers it nor asks again.
        LocationCoordinator.resetOffers(in: freshDefaults())
        defaults.removeObject(forKey: LocationCoordinator.offeredKey)
        let later = harness(LocationPermission(authorization: .whenInUse), defaults: defaults)
        #expect(later.location.hasAskedForAlways)
        #expect(!later.location.needsPermissionStep)

        let fresh = harness(.notDetermined)
        fresh.location.requestPermission()
        #expect(!fresh.location.hasAskedForAlways)
        #expect(fresh.platform.calls == ["whenInUse"])
    }
}

/// Counts what the person-link would send to Home Assistant.
@MainActor
private final class CountingAPI: HassCommandSending {
    var commands: [String] = []
    func command(_ type: String, data: [String: any Sendable]) async throws -> JSONValue {
        commands.append(type)
        return .array([])
    }
}
