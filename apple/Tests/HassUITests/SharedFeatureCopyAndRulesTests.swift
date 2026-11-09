import Foundation
import HassCore
import HassDesign
import SwiftUI
import Testing
@testable import HassUI

/// The words and small rules the UIKit pages read from `HassUI/Features` and `HassUI/Controls`: what a person is told, and which
/// actions VoiceOver offers.
struct SharedFeatureCopyAndRulesTests {
    // MARK: Todo rows

    @Test func voiceOverOffersUndoToggleEditAndDeleteInThatOrder() {
        let item = TodoItem(uid: "1", summary: "Milk")
        let exposed = TodoRowActions(item: item, canEdit: true, canDelete: true)
        let actions = TodoItemRow.voiceOverActions(hasUndo: true, exposed: exposed, hasEdit: true, hasDelete: true)
        #expect(actions.map(\.kind) == [.undo, .toggle, .edit, .delete])
        #expect(actions.map(\.title) == ["Undo", "Complete", "Edit", "Delete"])
    }

    @Test func aCompletedItemOffersMarkNotDoneAndEditNeedsAHandler() {
        let done = TodoItem(uid: "1", summary: "Milk", status: .completed)
        let exposed = TodoRowActions(item: done, canEdit: true, canDelete: false)
        let actions = TodoItemRow.voiceOverActions(hasUndo: false, exposed: exposed, hasEdit: false, hasDelete: false)
        #expect(actions.map(\.title) == ["Mark Not Done"], "no edit handler: no Edit action")
        #expect(TodoItemRow.voiceOverActions(hasUndo: false, exposed: nil, hasEdit: true, hasDelete: false).isEmpty)
    }

    @Test func performingAnActionCallsTheMatchingHandler() {
        var calls: [String] = []
        let row = TodoItemRow(item: TodoItem(uid: "1", summary: "Milk"), onToggle: { calls.append("toggle") },
                              onEdit: { calls.append("edit") }, onUndo: { calls.append("undo") }, onDelete: { calls.append("delete") },
                              exposedActions: TodoRowActions(item: TodoItem(uid: "1", summary: "Milk"), canEdit: true, canDelete: true))
        for kind in [TodoItemRow.VoiceOverAction.Kind.undo, .toggle, .edit, .delete] { row.perform(kind) }
        #expect(calls == ["undo", "toggle", "edit", "delete"])
        #expect(row.voiceOverActions.count == 4)
        let bare = TodoItemRow(item: TodoItem(uid: "2", summary: "Eggs"), onToggle: {})
        bare.perform(.edit)
        bare.perform(.undo)
        bare.perform(.delete)
        #expect(bare.voiceOverActions.isEmpty)
    }

    @Test func rowSymbolsAndSpokenValue() {
        #expect(TodoItemRow.checkSymbol(done: true) == "checkmark.circle.fill")
        #expect(TodoItemRow.checkSymbol(done: false) == "circle")
        #expect(TodoItemRow.accessibilityValue(completed: true, due: "Today") == "Done")
        #expect(TodoItemRow.accessibilityValue(completed: false, due: "Today") == "Not done, Today")
        #expect(TodoItemRow.accessibilityValue(completed: false, due: nil) == "Not done")
        #expect(TodoItemRow.completionAnnouncement("Milk") == "Milk completed. Undo available")
    }

    // MARK: Time Sensitive copy

    @Test func timeSensitiveOnOnlyAcknowledges() {
        let copy = TimeSensitiveCopy(isOn: true)
        #expect(copy.status == "On")
        #expect(copy.action == .acknowledge)
        #expect(copy.actionTitle == "Got It")
        #expect(copy.secondaryTitle == nil)
        #expect(TimeSensitiveCopy.rowStatus(isOn: true).hasPrefix("On."))
    }

    @Test func timeSensitiveOffSendsThePersonToSettingsWithANotNow() {
        let copy = TimeSensitiveCopy(isOn: false)
        #expect(copy.status == "Off")
        #expect(copy.action == .openSettings)
        #expect(copy.actionTitle == "Open Settings")
        #expect(copy.secondaryTitle == "Not Now")
        #expect(TimeSensitiveCopy.rowStatus(isOn: false).hasPrefix("Off."))
        #expect(TimeSensitiveCopy.points.map(\.key) == ["urgent", "focus", "settings"])
        #expect(TimeSensitiveCopy.statusLabel == "Time Sensitive Notifications")
        #expect(TimeSensitiveCopy.notificationsRowStatus.hasPrefix("On."))
    }

    // MARK: Location account section

    @Test func locationWarningsNameTheProblemOnlyWhenThereIsOne() {
        #expect(LocationAccountSection.warning(stage: .notDetermined)?.contains("isn't set") == true)
        #expect(LocationAccountSection.warning(stage: .denied)?.contains("is off") == true)
        #expect(LocationAccountSection.warning(stage: .reducedAccuracy)?.contains("Precise Location") == true)
        #expect(LocationAccountSection.warning(stage: .whenInUse) == nil)
        #expect(LocationAccountSection.warning(stage: .always) == nil)
        #expect(LocationAccountSection.footer.contains("iPhone"))
        #expect(LocationAccountSection.footerWithoutPerson.contains("iPad"))
    }

    @Test func presenceLinkNoticesExplainWhatToDo() {
        #expect(LocationAccountSection.linkNotice(.needsAdmin)?.contains("administrator") == true)
        #expect(LocationAccountSection.linkNotice(.noPerson)?.contains("No person") == true)
        #expect(LocationAccountSection.linkNotice(.trackerMissing)?.contains("next sign-in") == true)
        #expect(LocationAccountSection.linkNotice(.failed)?.contains("Couldn't") == true)
        #expect(LocationAccountSection.linkNotice(.linked(person: "person.demo_a")) == nil)
        #expect(LocationAccountSection.linkNotice(.alreadyLinked(person: "person.demo_a")) == nil)
        #expect(LocationAccountSection.linkNotice(.compositeManaged(person: "person.demo_a")) == nil)
        #expect(LocationAccountSection.linkNotice(nil) == nil)
    }

    // MARK: Remote controls

    @Test func theDirectionalPadShrinksToFitAndNeverBelowATarget() {
        #expect(DirectionalPad.diameter(scaled: 76, maxWidth: nil) == 76)
        #expect(DirectionalPad.diameter(scaled: 10, maxWidth: nil) == 64)
        #expect(DirectionalPad.diameter(scaled: 500, maxWidth: nil) == 104)
        #expect(DirectionalPad.diameter(scaled: 100, maxWidth: 200) < 100)
        #expect(DirectionalPad.diameter(scaled: 76, maxWidth: 10) >= 44)
    }

    @Test func aSliderDraftCommitsOnceOnReleaseAndShowsTheDraftWhileDragging() {
        var draft = SliderDraft()
        var committed: [Double] = []
        #expect(draft.shown(live: 30) == 30)
        draft.set(40, commit: { committed.append($0) })
        #expect(committed == [40], "an accessibility adjust with no drag commits at once")
        draft.editingChanged(true, live: 30, commit: { committed.append($0) })
        draft.set(55, commit: { committed.append($0) })
        #expect(draft.shown(live: 30) == 55)
        #expect(committed == [40])
        draft.editingChanged(false, live: 30, commit: { committed.append($0) })
        #expect(committed == [40, 55])
        #expect(draft.draft == nil)
        draft.editingChanged(false, live: 30, commit: { committed.append($0) })
        #expect(committed == [40, 55], "releasing without a drag commits nothing")
    }

    @Test func theKeyboardPromptTogglesPerTargetAndIgnoresBlankText() {
        var prompt = KeyboardPrompt()
        #expect(!prompt.isOpen)
        prompt.toggle("remote.demo_tv")
        #expect(prompt.isOpen)
        prompt.toggle("remote.demo_tv")
        #expect(!prompt.isOpen)
        prompt.toggle("remote.demo_a")
        prompt.toggle("remote.demo_b")
        #expect(prompt.target == "remote.demo_b")
        #expect(prompt.isBlank)
        prompt.text = "  \n"
        #expect(prompt.isBlank)
        prompt.text = "hello"
        #expect(!prompt.isBlank)
        prompt.close()
        #expect(prompt == KeyboardPrompt())
    }

    @Test func percentSlidersStepByFiveWithinZeroToAHundred() {
        #expect(PercentSliderRow.adjusted(50, increment: true) == 55)
        #expect(PercentSliderRow.adjusted(50, increment: false) == 45)
        #expect(PercentSliderRow.adjusted(98, increment: true) == 100)
        #expect(PercentSliderRow.adjusted(2, increment: false) == 0)
        #expect(PercentSliderRow.adjusted(50, .increment) == 55)
        #expect(PercentSliderRow.adjusted(50, .decrement) == 45)
    }

    // MARK: Bedroom clock field

    @Test func clockTimesRoundTripAsTwoDigitHoursAndMinutes() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = ClockTimeField.date("06:45", calendar: calendar)
        #expect(ClockTimeField.string(date, calendar: calendar) == "06:45")
        #expect(ClockTimeField.string(ClockTimeField.date("7", calendar: calendar), calendar: calendar) == "07:00")
        #expect(ClockTimeField.string(ClockTimeField.date("", calendar: calendar), calendar: calendar) == "07:00", "no value: 7:00")
    }

    // MARK: Thermostat targets

    @Test func aRejectedSetpointSaysWhichTemperatureFailed() {
        #expect(ThermostatTargets.single(68).failureMessage == "Couldn't set 68°. Check the connection.")
        #expect(ThermostatTargets.single(68.5).failureMessage == "Couldn't set 68.5°. Check the connection.")
        #expect(ThermostatTargets.range(low: 66, high: 72.5).failureMessage == "Couldn't set 66° to 72.5°. Check the connection.")
    }

    @Test func setTemperatureServiceDataTargetsOneOrManyEntities() {
        let single = ThermostatTargets.single(70).setTemperatureData(entityIds: ["climate.demo_a"])
        #expect(single["entity_id"] as? String == "climate.demo_a")
        #expect(single["temperature"] as? Double == 70)
        let range = ThermostatTargets.range(low: 66, high: 72).setTemperatureData(entityIds: ["climate.demo_a", "climate.demo_b"])
        #expect(range["entity_id"] as? [String] == ["climate.demo_a", "climate.demo_b"])
        #expect(range["target_temp_low"] as? Double == 66)
        #expect(range["target_temp_high"] as? Double == 72)
    }
}
