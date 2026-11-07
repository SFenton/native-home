import HassCore
import HassDesign
import SwiftUI

// MARK: - Dial mapping

/// Maps a bed side onto ``ThermostatDial`` with the signed level scale (web `EightSleepThermostatHero`).
enum BedDial {
    @MainActor
    static func configuration(_ controller: BedSideController) -> ThermostatDialConfiguration {
        let range = controller.targetRange
        let target = controller.displayedTarget
        var configuration = ThermostatDialConfiguration(
            title: controller.config.title,
            min: range.lowerBound, max: range.upperBound, step: controller.targetStep,
            current: controller.currentLevel,
            targets: target.map { .single($0) },
            action: controller.isOn ? controller.action : "off",
            isUnavailable: !controller.sideAvailable,
            isOff: !controller.isOn,
            isInteractive: controller.canSetTarget,
            actionTextOverride: controller.sideAvailable ? (controller.hotFlashActive ? "Hot Flash" : (controller.isOn ? StateText.titleCase(controller.action, empty: "") : "Off")) : nil,
            // On, the signed-level scale draws the displayed target itself, so the number follows a drag; only Off replaces it.
            primaryValueOverride: controller.sideAvailable && !controller.isOn ? "OFF" : nil,
            primaryUnitOverride: .some(nil),
            targetCaption: controller.currentTemperature.map { .custom("Currently \(BedFormat.temperature($0))") } ?? .hidden
        )
        configuration.scale = .signedLevel
        let state = controller.sideAvailable ? (controller.isOn ? "\(StateText.titleCase(controller.action, empty: "")), target \(BedLevel.format(target))" : "Off") : "Unavailable"
        let current = controller.currentTemperature.map { ", currently \(BedFormat.temperature($0))" } ?? ""
        configuration.readoutAccessibilityLabelOverride = "\(controller.config.title), \(state)\(current)"
        return configuration
    }
}
