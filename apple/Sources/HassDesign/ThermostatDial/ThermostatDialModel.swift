import CoreGraphics
import Foundation

// MARK: - Targets

/// The setpoints a thermostat dial edits: one target, or a heat/cool range.
public enum ThermostatTargets: Hashable, Sendable {
    /// One target temperature (Home Assistant `temperature`).
    case single(Double)
    /// Heat-to and cool-to setpoints (`target_temp_low` / `target_temp_high`).
    case range(low: Double, high: Double)

    /// Which handle a gesture or adjustment moves.
    public enum Handle: String, CaseIterable, Sendable {
        case target, low, high
    }

    /// The handles these targets show, in ring order.
    public var handles: [Handle] {
        switch self {
        case .single: [.target]
        case .range: [.low, .high]
        }
    }

    /// The value of `handle`, or `nil` if these targets don't have it.
    public func value(of handle: Handle) -> Double? {
        switch (self, handle) {
        case let (.single(value), .target): value
        case let (.range(low, _), .low): low
        case let (.range(_, high), .high): high
        default: nil
        }
    }

    /// Moves `handle` to `value`, keeping heat-to at or below cool-to (web `nextValueFromHandleEvent`).
    public func setting(_ handle: Handle, to value: Double) -> ThermostatTargets {
        switch (self, handle) {
        case (.single, .target): .single(value)
        case let (.range(_, high), .low): .range(low: min(value, high), high: high)
        case let (.range(low, _), .high): .range(low: low, high: max(value, low))
        default: self
        }
    }

    /// The handle nearest `value`, for a touch on the ring between handles.
    public func nearestHandle(to value: Double) -> Handle {
        switch self {
        case .single: .target
        case let .range(low, high):
            // Past either end the outer handle wins; ties go to whichever side the touch is on.
            if value <= low { .low } else if value >= high { .high } else { value - low <= high - value ? .low : .high }
        }
    }

    /// Home Assistant `climate.set_temperature` service data for these targets.
    public var serviceData: [String: Double] {
        switch self {
        case let .single(value): ["temperature": value]
        case let .range(low, high): ["target_temp_low": low, "target_temp_high": high]
        }
    }
}

// MARK: - Thermal status

/// What the HVAC is doing, which colors the current-temperature marker and single handle.
public enum ThermostatThermalStatus: String, Sendable {
    case heat, cool, idle

    /// Maps an `hvac_action` (or, without one, the entity state) the way the web does
    /// (`DashboardViewPage.tsx` `thermostatThermalStatus`).
    public init(action: String) {
        switch action {
        case "heating", "heat": self = .heat
        case "cooling", "cool": self = .cool
        default: self = .idle
        }
    }
}

// MARK: - Non-temperature dials

/// An sRGB color for dial parts, kept out of SwiftUI so the model stays plain values.
public struct DialTint: Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var opacity: Double

    /// Creates a color from 0–255 components (as the web's `rgba()` values are written).
    public init(red: Double, green: Double, blue: Double, opacity: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.opacity = opacity
    }
}

/// A colored stretch of the ring between two values (web `CircularDialTrail`), e.g. a humidity comfort band.
public struct DialTrail: Hashable, Sendable, Identifiable {
    public var id: String
    public var from: Double
    public var to: Double
    public var tint: DialTint

    /// Creates a trail.
    public init(id: String, from: Double, to: Double, tint: DialTint) {
        self.id = id
        self.from = from
        self.to = to
        self.tint = tint
    }
}

/// How a dial that isn't a thermostat reads (web `SingleValueCircularDial` props). With one, the large number is
/// the setpoint and follows the handle while dragging, the handle and marker take ``tint``, and VoiceOver speaks
/// ``handleLabel`` and ``spokenUnit`` instead of temperatures.
public struct DialValueStyle: Hashable, Sendable {
    /// The handle, marker and accent color.
    public var tint: DialTint
    /// The handle's VoiceOver label, e.g. `Mist level`.
    public var handleLabel: String
    /// Spoken after the value (`percent`), or empty for a bare number.
    public var spokenUnit: String
    /// The readout's VoiceOver label.
    public var readoutLabel: String
    /// Colored stretches drawn under the handle.
    public var trails: [DialTrail]

    /// Creates a style.
    public init(tint: DialTint, handleLabel: String, spokenUnit: String = "", readoutLabel: String, trails: [DialTrail] = []) {
        self.tint = tint
        self.handleLabel = handleLabel
        self.spokenUnit = spokenUnit
        self.readoutLabel = readoutLabel
        self.trails = trails
    }
}

// MARK: - Configuration

/// Everything a ``ThermostatDial`` draws, as plain values. Callers map a climate entity into this
/// (see `HassUI` `ThermostatDialConfiguration.init(entity:title:)`).
public struct ThermostatDialConfiguration: Equatable, Sendable {
    /// What the setpoint caption shows.
    public enum TargetCaption: Equatable, Sendable {
        /// Formatted from the targets: `72°F`, or `68.0 · 74.0` for a range.
        case automatic
        /// Caller-supplied text.
        case custom(String)
        /// No caption.
        case hidden
    }

    /// Room or thermostat name, used in accessibility labels.
    public var title: String
    public var min: Double
    public var max: Double
    public var step: Double
    /// Measured temperature, if known.
    public var current: Double?
    /// Setpoints from Home Assistant; `nil` hides the handles.
    public var targets: ThermostatTargets?
    /// Raw `hvac_action` or state, e.g. `heating`.
    public var action: String
    /// Temperature unit, e.g. `°F`.
    public var unit: String
    /// The entity is missing, `unavailable` or `unknown`: no handles, no current marker.
    public var isUnavailable: Bool
    /// The thermostat is off (web: dims the dial when it has no range and isn't heating or cooling).
    public var isOff: Bool
    /// `false` shows the readout only.
    public var isInteractive: Bool

    // MARK: Overrides (web `ThermostatDial` props)

    /// Replaces the action line.
    public var actionTextOverride: String?
    /// Replaces the large current-temperature text.
    public var primaryValueOverride: String?
    /// Replaces the unit beside the primary text; `.some(nil)` hides it.
    public var primaryUnitOverride: String??
    /// The setpoint caption.
    public var targetCaption: TargetCaption
    /// Forces the dimmed state on or off.
    public var inactiveOverride: Bool?
    /// Makes this a single-value dial for something other than temperature (humidity, mist level).
    public var valueStyle: DialValueStyle?

    // MARK: Non-temperature scales

    /// How handle values are spoken and what the single handle is called, when there is no ``valueStyle``.
    public enum ValueScale: Equatable, Sendable {
        /// `72.5 degrees`; handle "<title> target temperature".
        case temperature
        /// `+3`, `0`, `-2` (the bed Pod's level scale); handle "<title> target level".
        case signedLevel
    }

    /// How handle values read (default: temperatures).
    public var scale: ValueScale = .temperature
    /// Replaces the readout's VoiceOver label.
    public var readoutAccessibilityLabelOverride: String?

    /// Creates a configuration.
    public init(
        title: String, min: Double = 45, max: Double = 95, step: Double = 0.5,
        current: Double?, targets: ThermostatTargets?, action: String, unit: String = "°F",
        isUnavailable: Bool = false, isOff: Bool = false, isInteractive: Bool = true,
        actionTextOverride: String? = nil, primaryValueOverride: String? = nil, primaryUnitOverride: String?? = nil,
        targetCaption: TargetCaption = .automatic, inactiveOverride: Bool? = nil, valueStyle: DialValueStyle? = nil
    ) {
        self.title = title
        self.min = min
        self.max = max
        self.step = step
        self.current = current
        self.targets = targets
        self.action = action
        self.unit = unit
        self.isUnavailable = isUnavailable
        self.isOff = isOff
        self.isInteractive = isInteractive
        self.actionTextOverride = actionTextOverride
        self.primaryValueOverride = primaryValueOverride
        self.primaryUnitOverride = primaryUnitOverride
        self.targetCaption = targetCaption
        self.inactiveOverride = inactiveOverride
        self.valueStyle = valueStyle
    }

    // MARK: Derived

    /// The ring geometry for this range.
    public var geometry: ThermostatDialGeometry { ThermostatDialGeometry(min: min, max: max, step: step) }

    /// Heating, cooling or idle.
    public var thermalStatus: ThermostatThermalStatus { ThermostatThermalStatus(action: action) }

    /// Dimmed: unavailable, or off with no range while neither heating nor cooling.
    public var isInactive: Bool {
        if let inactiveOverride { return inactiveOverride }
        guard !isUnavailable else { return true }
        if case .range = targets { return false }
        return isOff && thermalStatus == .idle
    }

    /// Whether handles are shown and gestures accepted.
    public var acceptsInput: Bool { isInteractive && !isUnavailable && targets != nil }

    /// The action line, title-cased (`heating` → `Heating`, `heat_cool` → `Heat Cool`).
    public var actionText: String {
        if let actionTextOverride { return actionTextOverride }
        if isUnavailable { return "Unavailable" }
        return action.split(separator: "_").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    /// The large current-temperature text (`71.5`, `72`, or `--`).
    public var primaryText: String {
        primaryValueOverride ?? (isUnavailable ? "--" : Self.compact(current))
    }

    /// The large text for the displayed (possibly pending) setpoints: with a ``valueStyle`` or the
    /// ``ValueScale/signedLevel`` scale it is the setpoint itself (`5`, `+3`), so it follows a drag;
    /// ``primaryValueOverride`` still wins (`Off`, `Sleep`).
    public func primaryText(for targets: ThermostatTargets?) -> String {
        guard valueStyle != nil || scale == .signedLevel, primaryValueOverride == nil else { return primaryText }
        guard !isUnavailable, case let .single(value)? = targets else { return "--" }
        return valueStyle == nil ? Self.signedLevel(value) : Self.compact(value)
    }

    /// The unit beside ``primaryText``, or `nil` to hide it.
    public var primaryUnit: String? {
        if let primaryUnitOverride { return primaryUnitOverride }
        return unit
    }

    /// The setpoint caption for `targets` (the displayed, possibly pending, setpoints).
    public func caption(for targets: ThermostatTargets?) -> String? {
        switch targetCaption {
        case .hidden: return nil
        case let .custom(text): return text
        case .automatic:
            switch targets {
            case let .single(value): return Self.oneDecimal(value) + unit
            case let .range(low, high): return "\(Self.oneDecimal(low)) · \(Self.oneDecimal(high))"
            case nil: return nil
            }
        }
    }

    // MARK: Accessibility

    /// The named accessibility action that raises a handle one step: the adjustable swipe's twin for Switch Control and
    /// Voice Control.
    public static let raiseActionName = "Raise"
    /// The named accessibility action that lowers a handle one step.
    public static let lowerActionName = "Lower"

    /// The VoiceOver label for `handle`.
    public func accessibilityLabel(for handle: ThermostatTargets.Handle) -> String {
        if let valueStyle { return valueStyle.handleLabel }
        return switch handle {
        case .target: scale == .signedLevel ? "\(title) target level" : "\(title) target temperature"
        case .low: "\(title) heat to"
        case .high: "\(title) cool to"
        }
    }

    /// A spoken temperature, e.g. `72.5 degrees`.
    public static func spokenTemperature(_ value: Double) -> String {
        "\(compact(value)) degrees"
    }

    /// A handle's spoken value: a temperature, a signed level (`+3`), or the value with the style's unit
    /// (`50 percent`, `5`).
    public func spokenValue(_ value: Double) -> String {
        guard let valueStyle else {
            switch scale {
            case .temperature: return Self.spokenTemperature(value)
            case .signedLevel: return Self.signedLevel(value)
            }
        }
        return valueStyle.spokenUnit.isEmpty ? Self.compact(value) : "\(Self.compact(value)) \(valueStyle.spokenUnit)"
    }

    /// The readout's VoiceOver label: name, action and current temperature.
    /// The readout's VoiceOver value: `set to 72.0°F`, or a value dial's caption as is.
    public func readoutAccessibilityValue(for targets: ThermostatTargets?) -> String {
        guard let caption = caption(for: targets) else { return "" }
        return valueStyle == nil ? "set to \(caption)" : caption
    }

    public var readoutAccessibilityLabel: String {
        if let readoutAccessibilityLabelOverride { return readoutAccessibilityLabelOverride }
        if let valueStyle { return valueStyle.readoutLabel }
        let current = isUnavailable || self.current == nil ? "current temperature unknown" : "currently \(primaryText)\(primaryUnit ?? "")"
        return "\(title) thermostat, \(actionText), \(current)"
    }

    // MARK: Formatting

    /// One decimal, like the web's `toFixed(1)`; `--` for `nil`.
    public static func oneDecimal(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(format: "%.1f", value)
    }

    /// One decimal with a trailing `.0` dropped (`72.0` → `72`).
    public static func compact(_ value: Double?) -> String {
        let text = oneDecimal(value)
        return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
    }

    /// A signed level, ``compact(_:)`` with a `+` above zero (`+3`, `0`, `-2.5`; web `formatEightSleepTargetLevel`).
    /// Zero is always `0`, never `-0` or `+0`, matching `BedLevel.format`.
    public static func signedLevel(_ value: Double) -> String {
        let text = compact(value)
        if text == "0" || text == "-0" { return "0" }
        return value > 0 ? "+" + text : text
    }
}

// MARK: - Pending edits

/// Optimistic setpoints shown while dragging or until Home Assistant echoes the change
/// (web `pendingTargets`, keyed by `sourceTargetKey`).
public struct ThermostatPendingTargets: Equatable, Sendable {
    /// The Home Assistant targets the edit started from.
    public var source: ThermostatTargets?
    /// The edited targets.
    public var value: ThermostatTargets

    /// Creates a pending edit.
    public init(source: ThermostatTargets?, value: ThermostatTargets) {
        self.source = source
        self.value = value
    }

    /// What to draw: the edit while Home Assistant still reports `source`, otherwise Home Assistant's value.
    public static func displayed(_ pending: ThermostatPendingTargets?, source: ThermostatTargets?) -> ThermostatTargets? {
        guard let pending, pending.source == source else { return source }
        return pending.value
    }
}

// MARK: - Commit de-duplication

/// Drops an identical `set_temperature` sent again within 400 ms (web `useCommitThermostatTemperature`),
/// e.g. a drag end immediately followed by the release handler.
public struct ThermostatCommitGate: Sendable {
    /// How long an identical commit is suppressed.
    public static let window: TimeInterval = 0.4

    private var last: (targets: ThermostatTargets, at: Date)?

    /// Creates an empty gate.
    public init() {}

    /// Records `targets` and returns whether they should be sent.
    public mutating func shouldSend(_ targets: ThermostatTargets, at now: Date = Date()) -> Bool {
        if let last, last.targets == targets, now.timeIntervalSince(last.at) < Self.window { return false }
        last = (targets, now)
        return true
    }
}

// MARK: - Editing

/// A commit Home Assistant rejected, numbered so the same targets rejected twice still count as a new event.
public struct ThermostatRejection: Equatable, Sendable {
    /// The rejected setpoints.
    public var targets: ThermostatTargets
    /// Rejections so far, from the caller.
    public var count: Int

    /// Creates a rejection.
    public init(targets: ThermostatTargets, count: Int) {
        self.targets = targets
        self.count = count
    }
}

/// The dial's interaction state machine, kept out of the view so every gesture path is unit-testable.
/// Each call takes the current configuration (Home Assistant's latest values) and returns the setpoints
/// to commit, if any.
public struct ThermostatDialEditor: Sendable {
    /// The optimistic edit, if one is showing.
    public private(set) var pending: ThermostatPendingTargets?
    /// The handle being dragged.
    public private(set) var activeHandle: ThermostatTargets.Handle?
    private var gate = ThermostatCommitGate()

    /// Creates an idle editor.
    public init() {}

    /// The setpoints to draw.
    public func displayed(_ configuration: ThermostatDialConfiguration) -> ThermostatTargets? {
        ThermostatPendingTargets.displayed(pending, source: configuration.targets)
    }

    /// A drag on `handle` moved to `point`.
    public mutating func drag(_ handle: ThermostatTargets.Handle, to point: CGPoint, side: CGFloat, in configuration: ThermostatDialConfiguration) {
        guard configuration.acceptsInput else { return }
        activeHandle = handle
        move(handle, to: configuration.geometry.value(at: point, side: side), in: configuration)
    }

    /// A drag on `handle` ended at `point`; returns the setpoints to commit.
    public mutating func endDrag(_ handle: ThermostatTargets.Handle, at point: CGPoint, side: CGFloat, in configuration: ThermostatDialConfiguration, now: Date = Date()) -> ThermostatTargets? {
        drag(handle, to: point, side: side, in: configuration)
        activeHandle = nil
        return commit(configuration, now: now)
    }

    /// A tap on the ring at `point` moves the nearest handle there; returns the setpoints to commit.
    public mutating func tap(at point: CGPoint, side: CGFloat, in configuration: ThermostatDialConfiguration, now: Date = Date()) -> ThermostatTargets? {
        guard configuration.acceptsInput, let displayed = displayed(configuration),
              configuration.geometry.isOnRing(point, side: side) else { return nil }
        let value = configuration.geometry.value(at: point, side: side)
        move(displayed.nearestHandle(to: value), to: value, in: configuration)
        return commit(configuration, now: now)
    }

    /// VoiceOver adjusted `handle` one step up or down; returns the setpoints to commit.
    public mutating func adjust(_ handle: ThermostatTargets.Handle, increment: Bool, in configuration: ThermostatDialConfiguration, now: Date = Date()) -> ThermostatTargets? {
        guard configuration.acceptsInput, let current = displayed(configuration)?.value(of: handle) else { return nil }
        let geometry = configuration.geometry
        move(handle, to: geometry.snapped(current + (increment ? geometry.step : -geometry.step)), in: configuration)
        return commit(configuration, now: now)
    }

    /// Home Assistant rejected the commit of `rejected`: if that is still the edit on screen and no handle is being
    /// dragged, drop it so the handles return to the entity's setpoints. A late failure of an older commit never
    /// undoes a newer edit. The same value may be sent again (pattern optimistic-actions: roll back, no error state).
    public mutating func rollBack(rejected: ThermostatTargets) {
        gate = ThermostatCommitGate()
        guard pending?.value == rejected, activeHandle == nil else { return }
        pending = nil
    }

    // MARK: Private

    private mutating func move(_ handle: ThermostatTargets.Handle, to value: Double, in configuration: ThermostatDialConfiguration) {
        guard let base = displayed(configuration) else { return }
        pending = ThermostatPendingTargets(source: configuration.targets, value: base.setting(handle, to: value))
    }

    /// The displayed setpoints if they differ from Home Assistant's and weren't just sent.
    private mutating func commit(_ configuration: ThermostatDialConfiguration, now: Date) -> ThermostatTargets? {
        guard let displayed = displayed(configuration), displayed != configuration.targets,
              gate.shouldSend(displayed, at: now) else { return nil }
        return displayed
    }
}
