import SwiftUI
@testable import HassDesign
import Testing

/// The selection face (owner, 2026-10-27, option C of selection-tiles) and the confirmation a disc can carry: the pure rules, the
/// strip's accessibility, and the indicator's metrics. The hosted accessibility tests are `SelectionTileTests` in HassUITests.
struct TileSelectionTests {
    // MARK: Selection

    @Test func singleChoiceReadsChosenOrNot() {
        #expect(TileSelection.single(isSelected: true).isSelected && !TileSelection.single(isSelected: false).isSelected)
        #expect(TileSelection.single(isSelected: true).position == nil)
    }

    @Test func orderedChoiceIsChosenOnlyWithAPlace() {
        #expect(TileSelection.ordered(position: 1).isSelected && TileSelection.ordered(position: 1).position == 1)
        #expect(!TileSelection.ordered(position: nil).isSelected && TileSelection.ordered(position: nil).position == nil)
    }

    // MARK: Strip accessibility

    private func item(selection: TileSelection? = nil, isOn: Bool? = nil, verb: String = "Select", label: String? = nil) -> TileActionItem {
        TileActionItem(id: "select", verb: verb, symbol: "circle", isOn: isOn, feedback: .optimistic, label: label, selection: selection)
    }

    @Test func aChosenDiscIsSelectedNeverASwitch() {
        let chosen = item(selection: .single(isSelected: true), isOn: true)
        let traits = TileActionStrip.traits(for: chosen)
        #expect(traits.contains(.isSelected) && !traits.contains(.isToggle), "isOn on a selection disc must not become a switch")
        #expect(TileActionStrip.value(for: chosen).isEmpty, "the trait speaks, not On or Off")
    }

    @Test func anUnchosenDiscCarriesNoTrait() {
        #expect(TileActionStrip.traits(for: item(selection: .ordered(position: nil))) == [])
        #expect(TileActionStrip.traits(for: item(selection: .ordered(position: 2))).contains(.isSelected))
    }

    @Test func aToggleStaysAToggleWithAValue() {
        let on = item(isOn: true)
        #expect(TileActionStrip.traits(for: on).contains(.isToggle) && !TileActionStrip.traits(for: on).contains(.isSelected))
        #expect(TileActionStrip.value(for: on) == "On" && TileActionStrip.value(for: item(isOn: false)) == "Off")
        #expect(TileActionStrip.value(for: item()).isEmpty && TileActionStrip.traits(for: item()) == [])
    }

    @Test func theLabelIsVerbAndTitleUnlessTheItemSpeaksItself() {
        #expect(TileActionStrip.label(for: item(verb: "Select"), title: "Xbox") == "Select Xbox")
        #expect(TileActionStrip.label(for: item(verb: "Turn Off TV", label: "Turn Off TV"), title: "Xbox") == "Turn Off TV")
    }

    // MARK: Indicator metrics

    @Test func theIndicatorIs28PtScalingToAtMost1_5x() {
        #expect(TileSelectionIndicator.diameter(scaled: 28) == 28)
        #expect(TileSelectionIndicator.diameter(scaled: 20) == 28, "never under the mockup's 28 pt")
        #expect(TileSelectionIndicator.diameter(scaled: 39) == 39)
        #expect(TileSelectionIndicator.diameter(scaled: 90) == 42, "capped at 1.5x, inside the 44 pt scaled target")
        #expect(TileSelectionIndicator.baseDiameter * 1.5 <= HassTokens.minTarget * 1.5)
    }

    @Test func theMarkStaysInsideTheDisc() {
        for d in [28.0, 42.0] {
            let mark = TileSelectionIndicator.markSize(diameter: d)
            #expect(mark < d * 0.6 && mark > d * 0.4)
        }
    }

    @Test func theRingKeepsAtLeast3To1OnTheDarkGround() {
        let white = 0xFFFFFF
        let ground = HassTokens.Palette.moduleThin
        let blended = ColorFamily.mix(UInt32(white), ground, TileSelectionIndicator.ringOpacity)
        #expect(ChipTint.contrast(blended, ground) >= TileActionInk.minimumContrast)
    }

    // MARK: Confirmation

    @Test func onlyAReadyActionWithAQuestionAsks() {
        let ask = TileActionConfirmation(title: "Disarm?", confirmVerb: "Disarm")
        var disarm = TileActionItem(id: "alarm", verb: "Disarm", symbol: "shield.slash", feedback: .tracked, confirmation: ask)
        let arm = TileActionItem(id: "arm", verb: "Arm Home", symbol: "shield", feedback: .tracked)
        #expect(TileActionConfirmation.required(forPerforming: "alarm", in: [disarm, arm]) == ask)
        #expect(TileActionConfirmation.required(forPerforming: "arm", in: [disarm, arm]) == nil, "no question on the other disc")
        #expect(TileActionConfirmation.required(forPerforming: "missing", in: [disarm]) == nil)
        disarm.phase = .inFlight
        #expect(TileActionConfirmation.required(forPerforming: "alarm", in: [disarm]) == nil, "a waiting action cannot run, so it cannot ask")
        disarm.phase = .unavailable
        #expect(TileActionConfirmation.required(forPerforming: "alarm", in: [disarm]) == nil)
    }

    @Test func aConfirmationDefaultsToAPlainAlert() {
        let ask = TileActionConfirmation(title: "T", confirmVerb: "Go")
        #expect(ask.style == .alert && !ask.isDestructive && ask.message == nil)
    }

    @Test func theButtonsHaveStableIdentifiers() {
        #expect(TileActionConfirmation.confirmIdentifier("security.quick.alarm") == "security.quick.alarm.confirm")
        #expect(TileActionConfirmation.cancelIdentifier("security.quick.alarm") == "security.quick.alarm.cancel")
        #expect(TileActionConfirmation.confirmIdentifier(nil) == "confirm")
    }

    // MARK: Rendering

    @MainActor
    @Test func everySelectionFaceRenders() {
        let faces: [TileSelection] = [.single(isSelected: true), .single(isSelected: false), .ordered(position: 1), .ordered(position: 12), .ordered(position: nil)]
        for face in faces {
            for reduce in [false, true] {
                let ink = TileActionInk.resolve(face: face.isSelected ? .filled : .dark, isOn: face.isSelected, family: nil)
                let view = TileSelectionIndicator(selection: face, ink: ink, isPressed: false)
                    .environment(\.reduceMotionOverride, reduce)
                #expect(ImageRenderer(content: view).cgImage != nil, "\(face) reduce=\(reduce)")
            }
        }
    }
}
