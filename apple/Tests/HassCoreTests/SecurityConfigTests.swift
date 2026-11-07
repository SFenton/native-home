import Foundation
@testable import HassCore
import HassTestSupport
import Testing

/// Security tiles, tones, lock services and alarm modes match the web (`securityPage.ts`, `SecurityDashboard.tsx`).
@Suite(.demoHouse)
struct SecurityConfigTests {
    @Test func tilesMatchTheWebInOrder() {
        #expect(SecurityConfig.controlTiles.map(\.title) == ["Security System", "Front Door", "Left Door", "Right Door"])
        #expect(SecurityConfig.controlTiles.map(\.kind) == [.alarm, .lock, .garageDoor, .garageDoor])
        #expect(SecurityConfig.controlTiles[0].entityId == HomeConfig.statusChips.first { $0.sheet == .security }?.entityId)
        #expect(SecurityConfig.vehicleTiles.map(\.entityId) == ["lock.demo_lock_1"])
        #expect(!SecurityConfig.showsVehicleSection, "The web hides the Vehicle section")
        let ids = (SecurityConfig.controlTiles + SecurityConfig.vehicleTiles).map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test(arguments: [
        ("closed", SecurityConfig.Tone.secure), ("closing", .active), ("opening", .danger), ("open", .danger),
        ("unavailable", .neutral), ("unknown", .neutral), ("stopped", .active),
    ])
    func garageTones(state: String, tone: SecurityConfig.Tone) {
        #expect(SecurityConfig.tone(for: .garageDoor, state: state) == tone)
    }

    @Test(arguments: [
        ("locked", SecurityConfig.Tone.secure), ("locking", .active), ("unlocking", .active), ("unlocked", .danger),
        ("jammed", .danger), ("open", .danger),
    ])
    func lockTones(state: String, tone: SecurityConfig.Tone) {
        #expect(SecurityConfig.tone(for: .lock, state: state) == tone)
        #expect(SecurityConfig.tone(for: .vehicle, state: state) == tone)
    }

    @Test func alarmTones() {
        #expect(SecurityConfig.tone(for: .alarm, state: "disarmed") == .secure)
        #expect(SecurityConfig.tone(for: .alarm, state: "armed_away") == .active)
        #expect(SecurityConfig.tone(for: .alarm, state: "triggered") == .danger)
        #expect(SecurityConfig.tone(for: .alarm, state: nil) == .neutral)
    }

    /// Unlocked or unlocking locks; anything else (locked, locking, jammed, missing) unlocks. Never `toggle`.
    @Test func lockServicesAreExplicit() {
        #expect(SecurityConfig.lockService(for: "unlocked") == "lock")
        #expect(SecurityConfig.lockService(for: "unlocking") == "lock")
        #expect(SecurityConfig.lockService(for: "open") == "lock")
        #expect(SecurityConfig.lockService(for: "locked") == "unlock")
        #expect(SecurityConfig.lockService(for: "locking") == "unlock")
        #expect(SecurityConfig.lockService(for: nil) == "unlock")
        let call = SecurityConfig.lockCall(entityId: SecurityConfig.frontDoorLockEntityId, state: "locked")
        #expect(call == ServiceCall("lock", "unlock", target: "lock.demo_lock_2"))
    }

    @Test func alarmModesCallThePanel() {
        #expect(SecurityConfig.alarmModes.map(\.title) == ["Home", "Away", "Night", "Disarmed"])
        #expect(SecurityConfig.alarmModes.map(\.call.service) == ["alarm_arm_home", "alarm_arm_away", "alarm_arm_night", "alarm_disarm"])
        #expect(SecurityConfig.alarmModes.allSatisfy { $0.call.domain == "alarm_control_panel" && $0.call.target == SecurityConfig.alarmEntityId })
        #expect(SecurityConfig.alarmModes.filter(\.needsConfirmation).map(\.state) == ["disarmed"])
        #expect(SecurityConfig.disarmMode.service == "alarm_disarm")
    }

    /// The alarm card leads with Disarm, labelled as the action (mockup n3).
    @Test func modeButtonsLeadWithDisarm() {
        #expect(SecurityConfig.modeButtons.map(\.buttonTitle) == ["Disarm", "Home", "Away", "Night"])
        #expect(SecurityConfig.modeButtons.map(\.state) == ["disarmed", "armed_home", "armed_away", "armed_night"])
        #expect(SecurityConfig.panelTitle("armed_away") == "Armed Away")
        #expect(SecurityConfig.panelTitle("triggered") == "Alarm Triggered")
    }

    /// "Since" names the time today and the date before today; no time, no line.
    @Test func sinceTextNamesTimeOrDate() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 22, minute: 10))!
        let today = calendar.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 21, minute: 30))!
        let earlier = calendar.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 21, minute: 30))!
        #expect(SecurityConfig.sinceText(today, now: now, calendar: calendar) == "Since \(today.formatted(date: .omitted, time: .shortened))")
        #expect(SecurityConfig.sinceText(earlier, now: now, calendar: calendar) == "Since \(earlier.formatted(.dateTime.month(.abbreviated).day()))")
        #expect(SecurityConfig.sinceText(.distantPast, now: now, calendar: calendar) == nil)
        #expect(SecurityConfig.sinceText(now.addingTimeInterval(3600), now: now, calendar: calendar) == nil)
    }

    @Test func alarmIconsAndColors() {
        #expect(SecurityConfig.alarmIcon(for: "armed_home") == "mdi:shield-home")
        #expect(SecurityConfig.alarmIcon(for: "armed_night") == "mdi:shield-moon")
        #expect(SecurityConfig.alarmIcon(for: "armed_away") == "mdi:shield")
        #expect(SecurityConfig.alarmIcon(for: "disarmed") == "mdi:shield-off")
        #expect(SecurityConfig.alarmIcon(for: "triggered") == "mdi:shield-alert")
        #expect(SecurityConfig.alarmIcon(for: "arming") == "mdi:shield-outline")
        #expect(rgb("armed_home") == [30, 136, 229])
        #expect(rgb("armed_night") == [142, 36, 170])
        #expect(rgb("armed_away") == [229, 57, 53])
        #expect(rgb("triggered") == [229, 57, 53])
        #expect(rgb("disarmed") == [67, 160, 71])
        #expect(rgb(nil) == [84, 110, 122])
    }

    func rgb(_ state: String?) -> [Int] {
        let color = SecurityConfig.alarmColor(for: state)
        return [color.red, color.green, color.blue]
    }

    @Test func stateTextIsTitleCased() {
        #expect(SecurityConfig.stateText("armed_home") == "Armed Home")
        #expect(SecurityConfig.stateText("locked") == "Locked")
        #expect(SecurityConfig.stateText("") == "Unknown")
        #expect(SecurityConfig.stateText(nil) == "Unknown")
    }
}
