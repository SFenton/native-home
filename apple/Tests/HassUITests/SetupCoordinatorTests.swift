import Foundation
import HassCore
@testable import HassUI
import Testing
@testable import HassCore

/// Answers the system questions the Setup flow asks, and counts the alert requests.
@MainActor
private final class SystemAnswers {
    var status: PushAuthorization = .notDetermined
    var timeSensitive: TimeSensitiveSetting = .enabled
    var requests = 0
    /// While set, the alert stays up until ``answer()``.
    var holdsAlert = false
    private var pending: CheckedContinuation<Void, Never>?

    var hasPending: Bool { pending != nil }
    func answer() { pending?.resume(); pending = nil }

    var platform: PushPlatform {
        PushPlatform(
            device: { MobileAppDevice(marketingVersion: "1", build: "2", name: "Test", model: "iPhone18,1", osVersion: "27.2",
                                      deviceID: "v", apnsEnvironment: .sandbox) },
            authorization: { await MainActor.run { self.status } },
            timeSensitiveSetting: { await MainActor.run { self.timeSensitive } },
            requestAuthorization: {
                await MainActor.run { self.requests += 1 }
                if await MainActor.run(body: { self.holdsAlert }) {
                    await withCheckedContinuation { c in Task { @MainActor in self.pending = c } }
                }
                return await MainActor.run { self.status = .granted; return true }
            },
            registerForRemoteNotifications: {},
            deliveredNotifications: { [] },
            removeDelivered: { _ in },
            openExternal: { _ in })
    }
}

/// The after-sign-in Setup flow: which step shows, what counts as shown, and what a publication may and may not change.
@MainActor
struct SetupCoordinatorTests {
    private func make(_ answers: SystemAnswers) throws -> (SetupCoordinator, UserDefaults) {
        let suite = "setup.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let push = PushCoordinator(platform: answers.platform, store: InMemoryMobileAppRegistrationStore(), isEnabled: false,
                                   defaults: defaults)
        push.simulateConnected()
        return (SetupCoordinator(push: push, location: nil, defaults: defaults), defaults)
    }

    @Test func theFlowWalksNotificationsThenTimeSensitiveThenCloses() async throws {
        let answers = SystemAnswers()
        let (setup, defaults) = try make(answers)
        #expect(!setup.isPresenting)
        await setup.offerIfNeeded()
        #expect(setup.step == .notifications && setup.shownStep == .notifications && setup.isPresenting)
        await setup.offerIfNeeded()
        #expect(setup.step == .notifications, "an open sheet is not offered again")

        await setup.continueNotifications()
        #expect(answers.requests == 1)
        #expect(setup.step == .timeSensitive)
        #expect(SetupFlow.seen(in: defaults).contains(.notifications))

        setup.openedSettingsFromTimeSensitive()
        #expect(setup.step == .timeSensitive, "opening Settings leaves the sheet on the step")
        await setup.finishTimeSensitive()
        #expect(setup.step == nil && !setup.isPresenting)
        #expect(setup.shownStep == .timeSensitive, "the sheet keeps drawing its last step while it dismisses")
        #expect(SetupFlow.seen(in: defaults) == [.notifications, .timeSensitive])
        await setup.didBecomeActive()
    }

    @Test func aStepAlreadyShownIsNotOfferedAgainAndClosingIsImmediate() async throws {
        let answers = SystemAnswers()
        answers.status = .granted
        let (setup, defaults) = try make(answers)
        SetupFlow.markSeen(.notifications, in: defaults)
        await setup.offerIfNeeded()
        #expect(setup.step == .timeSensitive)
        setup.close()
        #expect(setup.step == nil)
        setup.showForTesting(.location)
        #expect(setup.isPresenting && setup.shownStep == .location)
        setup.isPresenting = false
        #expect(setup.step == nil)
        setup.isPresenting = true
        #expect(setup.step == nil, "setting it true does not present by itself")
    }

    @Test func aPublicationAddsCopyButCannotReplaceAnOpenStep() async throws {
        let answers = SystemAnswers()
        let (setup, _) = try make(answers)
        let policy = ServerUIBootstrapPolicy(
            arrivalAnnouncement: "Welcome",
            recovery: .init(loadingTitle: "L", unavailableTitle: "U", unavailableMessage: "M", retryLabel: "R"),
            setup: [.init(permission: .notifications, explanation: "Why alerts"), .init(permission: .timeSensitive, explanation: nil),
                    .init(permission: .location, explanation: "Why location")])
        try setup.configure(bootstrap: policy)
        #expect(setup.explanation(for: .notifications) == "Why alerts")
        #expect(setup.explanation(for: .timeSensitive) == nil)
        #expect(setup.explanation(for: .location) == "Why location")

        await setup.offerIfNeeded()
        #expect(setup.blocksPublication)
        #expect(throws: SetupCoordinator.ConfigurationError.self) { try setup.configure(bootstrap: nil) }
        #expect(setup.bootstrapPolicy == policy)

        setup.sessionEnded()
        #expect(setup.step == nil && setup.bootstrapPolicy == nil && !setup.blocksPublication)
        #expect(setup.explanation(for: .notifications) == nil)
    }

    @Test func aSignOutDuringTheAlertStopsTheOldFlowFromAdvancing() async throws {
        let answers = SystemAnswers()
        let (setup, _) = try make(answers)
        await setup.offerIfNeeded()
        answers.holdsAlert = true
        let asking = Task { await setup.continueNotifications() }
        while answers.requests == 0 { await Task.yield() }
        #expect(setup.blocksPublication, "an outstanding alert holds publication")
        setup.sessionEnded()
        while !answers.hasPending { await Task.yield() }
        answers.answer()
        await asking.value
        #expect(!setup.blocksPublication)
        #expect(setup.step == nil, "the old answer cannot advance a flow that ended")
    }
}
