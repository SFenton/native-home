import Foundation

// MARK: - Canonical light and sprinkler atoms

/// Domain gestures only. Generic rows, tabs, routing and editor hosts remain shell-owned.
public struct ServerUIDeviceControl: Equatable, Sendable {
    /// The authored domain choices.
    public enum Domain: String, Sendable { case lights, sprinkler }
    /// The authored kind choices.
    public enum Kind: String, CaseIterable, Sendable {
        case manual, mode, brightness, color, reset, resetAll = "reset-all", applyAll = "apply-all", copyColor = "copy-color"
        case card, status, zone, program, rainDelay = "rain-delay", smartWatering = "smart-watering", stop
        case duration, presets, start, days, times, budget, apply, reload
        case programEnabled = "program-enabled", startProgram = "start-program", waterBlocker = "water-blocker"
    }
    public let node: ServerUICompositionDocument.Node
    public let domain: Domain
    public let sourceId: String
    public let kind: Kind
    public let entityId: String?
    public let copySourceId: String?
    public let zone: Int?
    public let action: ServerUICompositionDocument.Action?
    public let confirmation: ServerUIBedroomControl.Question?
}

extension ServerUICompositionShape {
    static func deviceControlNode(base: [String: Shape], domain: ServerUIDeviceControl.Domain) -> Shape {
        let isLight = domain == .lights
        let kinds: [ServerUIDeviceControl.Kind] = isLight
            ? [.manual, .mode, .brightness, .color, .reset, .resetAll, .applyAll, .copyColor]
            : [.card, .status, .zone, .program, .rainDelay, .smartWatering, .stop, .duration, .presets,
               .start, .days, .times, .budget, .apply, .reload, .programEnabled, .startProgram, .waterBlocker]
        var variants: [String: Shape] = [:]
        for kind in kinds {
            var fields: [String: Shape] = ["sourceId": id, "kind": fixed(kind.rawValue)]
            if [.brightness, .color, .reset, .applyAll, .copyColor].contains(kind) { fields["entityId"] = providerEntity }
            if kind == .copyColor { fields["copySourceId"] = providerEntity }
            if [.zone, .program, .duration, .presets, .start, .days, .times, .budget, .apply, .reload, .programEnabled, .startProgram].contains(kind) {
                fields["zone"] = .number(0, 31, integer: true)
            }
            if [.card, .zone, .program].contains(kind) { fields["action"] = action }
            if kind == .brightness { fields["action"] = .optional(action) }
            if kind == .resetAll || kind == .applyAll {
                fields["confirmation"] = object(["title": title, "message": .text(2000, blank: false),
                                                 "confirmLabel": label, "cancelLabel": fixed("Cancel")])
            }
            variants[kind.rawValue] = object(fields)
        }
        return object(base.merging(["type": fixed(isLight ? "custom-light-control" : "sprinkler-control"),
                                    "props": .variant("kind", variants)]) { _, new in new })
    }
}
