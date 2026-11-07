import Foundation
@testable import HassUI
import Testing

/// Which Setup step comes next: every row of the who-sees-what table in
/// `.agents/design/mockups/proposals/setup-flow-time-sensitive`, and the migration of the old location flag.
struct SetupFlowTests {
    private func inputs(_ push: PushAuthorization, _ timeSensitive: TimeSensitiveSetting = .enabled,
                        location: Bool = true) -> SetupFlow.Inputs {
        SetupFlow.Inputs(push: push, timeSensitive: timeSensitive, locationNeedsAsk: location)
    }

    private func next(_ inputs: SetupFlow.Inputs, seen: Set<SetupStep> = []) -> SetupStep? {
        SetupFlow.nextStep(for: inputs, seen: seen)
    }

    // MARK: Who sees what

    @Test func aFirstLaunchSeesEveryStepInOrderWhenTheyAllow() {
        // Notifications are asked first; the answer arrives with the re-evaluation.
        #expect(next(inputs(.notDetermined, .notSupported)) == .notifications)
        #expect(next(inputs(.granted, .enabled), seen: [.notifications]) == .timeSensitive)
        #expect(next(inputs(.granted, .enabled), seen: [.notifications, .timeSensitive]) == .location)
        #expect(next(inputs(.granted, .enabled), seen: Set(SetupStep.allCases)) == nil)
    }

    @Test func timeSensitiveShowsToEveryoneWhoHasNotSeenItEvenWhenTheSwitchIsOn() {
        // B1 (owner, 2026-10-27): shown once with the switch on (Got It) and with it off (Open Settings).
        for setting in [TimeSensitiveSetting.enabled, .disabled] {
            #expect(next(inputs(.granted, setting, location: false), seen: [.notifications]) == .timeSensitive)
        }
    }

    @Test func aPersonWhoAcceptedLocationGetsOnlyTimeSensitiveOnTheNextLaunch() {
        // The existing install: notifications allowed, location accepted (so nothing left to ask there).
        let you = inputs(.granted, .enabled, location: false)
        #expect(next(you, seen: [.location]) == .timeSensitive)
        #expect(next(you, seen: [.location, .timeSensitive]) == nil, "once, ever")
    }

    @Test func aPersonWhoAcceptedLocationButNeverAnsweredNotificationsIsAskedForThem() {
        let person = inputs(.notDetermined, .notSupported, location: false)
        #expect(next(person, seen: [.location]) == .notifications)
        // Refused: Time Sensitive is skipped (nothing to be time-sensitive about).
        #expect(next(inputs(.denied, .notSupported, location: false), seen: [.location, .notifications]) == nil)
        // Allowed: Time Sensitive follows in the same sheet.
        #expect(next(inputs(.granted, .enabled, location: false), seen: [.location, .notifications]) == .timeSensitive)
    }

    @Test func refusedNotificationsSkipTimeSensitiveAndShowItOnceIfTheyAllowLater() {
        let refused = inputs(.denied, .notSupported)
        #expect(next(refused, seen: [.notifications]) == .location, "Location has its own rule")
        #expect(next(refused, seen: [.notifications, .location]) == nil)
        // Allowed later in Settings: the next launch shows Time Sensitive, once.
        let later = inputs(.granted, .enabled, location: false)
        #expect(next(later, seen: [.notifications, .location]) == .timeSensitive)
        #expect(next(later, seen: [.notifications, .location, .timeSensitive]) == nil)
    }

    @Test func timeSensitiveTurnedOffByHandShowsOffOnce() {
        #expect(next(inputs(.granted, .disabled, location: false), seen: [.notifications, .location]) == .timeSensitive)
        #expect(next(inputs(.granted, .disabled, location: false), seen: Set(SetupStep.allCases)) == nil)
    }

    @Test func aSystemWithoutTimeSensitiveSkipsItsStep() {
        #expect(next(inputs(.granted, .notSupported, location: false), seen: [.notifications, .location]) == nil)
        #expect(next(inputs(.granted, .notSupported), seen: [.notifications]) == .location)
    }

    @Test func locationKeepsItsConditionAndIsSkippedWhenThereIsNothingToAsk() {
        #expect(next(inputs(.granted, .enabled, location: true), seen: [.notifications, .timeSensitive]) == .location)
        #expect(next(inputs(.granted, .enabled, location: false), seen: [.notifications, .timeSensitive]) == nil)
        #expect(SetupFlow.applies(.location, to: inputs(.denied, .notSupported, location: true)))
        #expect(!SetupFlow.applies(.location, to: inputs(.denied, .notSupported, location: false)))
    }

    @Test func eachConditionStandsAlone() {
        #expect(SetupFlow.applies(.notifications, to: inputs(.notDetermined)))
        #expect(!SetupFlow.applies(.notifications, to: inputs(.granted)))
        #expect(!SetupFlow.applies(.notifications, to: inputs(.denied)))
        #expect(SetupFlow.applies(.timeSensitive, to: inputs(.granted, .disabled)))
        #expect(!SetupFlow.applies(.timeSensitive, to: inputs(.notDetermined, .enabled)))
        #expect(!SetupFlow.applies(.timeSensitive, to: inputs(.denied, .enabled)))
    }

    @Test func theBarNamesTheStepOnScreen() {
        #expect(SetupStep.notifications.barTitle == "Notification Settings")
        #expect(SetupStep.timeSensitive.barTitle == "Time Sensitive Notification Settings")
        #expect(SetupStep.location.barTitle == "Location Settings")
    }

    @Test func theStepsAreOrdered() {
        #expect(SetupStep.allCases == [.notifications, .timeSensitive, .location])
        #expect(SetupStep.notifications < .timeSensitive && SetupStep.timeSensitive < .location)
    }

    // MARK: Persistence and migration

    private func defaults() -> UserDefaults { UserDefaults(suiteName: "setup-flow-\(UUID().uuidString)")! }

    @Test func aFreshInstallHasSeenNothing() {
        #expect(SetupFlow.seen(in: defaults()).isEmpty)
    }

    @Test func theOldLocationFlagCountsAsTheLocationStepSeen() {
        let store = defaults()
        store.set(true, forKey: LocationCoordinator.offeredKey)
        #expect(SetupFlow.seen(in: store) == [.location], "nobody sees the location step twice")
        // That person, with notifications allowed, gets only Time Sensitive.
        #expect(next(inputs(.granted, .enabled, location: true), seen: SetupFlow.seen(in: store)) == .timeSensitive)
    }

    @Test func markingAStepKeepsTheMigratedAndEarlierOnes() {
        let store = defaults()
        store.set(true, forKey: LocationCoordinator.offeredKey)
        SetupFlow.markSeen(.notifications, in: store)
        SetupFlow.markSeen(.notifications, in: store)
        #expect(SetupFlow.seen(in: store) == [.notifications, .location])
        #expect(store.stringArray(forKey: SetupFlow.seenKey) == ["notifications", "location"], "kept in flow order")
        SetupFlow.markSeen(.timeSensitive, in: store)
        #expect(SetupFlow.seen(in: store) == Set(SetupStep.allCases))
        #expect(SetupFlow.seenKey == "setup.stepsSeen")
    }

    @Test func unknownStoredValuesAreIgnored() {
        let store = defaults()
        store.set(["timeSensitive", "somethingFromTheFuture"], forKey: SetupFlow.seenKey)
        #expect(SetupFlow.seen(in: store) == [.timeSensitive])
    }
}
