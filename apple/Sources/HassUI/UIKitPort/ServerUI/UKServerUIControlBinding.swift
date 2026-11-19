#if os(iOS)
import HassCore
import UIKit

// MARK: - What a control draws

/// What a value control draws, whatever backs its value (scene-local state or a Home Assistant entity).
///
/// One description serves both `local-control` and `bound-control`, so a bound control is exactly the canonical control a local
/// one is: the same switch row, stepper, picker, segmented choice and slider, never a second look.
struct UKServerUIControlSpec: Equatable {
    typealias D = ServerUICompositionDocument

    enum Face: Equatable {
        case toggle
        case stepper(minimum: Int, maximum: Int, step: Int, format: String?)
        /// The 0...100 percent row in steps of 5 (`UKPercentSliderRow`).
        case slider
        /// A menu button.
        case choice([D.LocalField.Option])
        /// 2 to 4 segments (a menu at accessibility sizes).
        case segmented([D.LocalField.Option])
        case text(placeholder: String)
    }

    var title: String
    var identifier: String
    var face: Face
    /// Said under the title while the value cannot be read (bound controls only).
    var unavailableText: String?
    /// A toggle row's own parts and face (`sh.bound-row-parts@1`, `sh.check-face@1`); `nil` is the plain switch row.
    var row: Row?
}

/// A source of a control's value and a sink for what the person asks for.
///
/// The control keeps no copy: it shows ``value()`` and, after reporting a request through ``send(_:)``, puts the shown value back
/// until the source hands it the new one (`.agents/design/controller-bound-controls.md`).
@MainActor
protocol UKServerUIControlBinding {
    var spec: UKServerUIControlSpec { get }
    /// The value now, or `nil` while it cannot be read. Call it inside an observation so a change redraws the control.
    func value() -> ServerUICompositionDocument.LocalValue?
    /// Reports what the person asked for.
    func send(_ value: ServerUICompositionDocument.LocalValue)
    /// What a toggle row's parts show now (its subtitle, glyph tint and failure); `nil` for a control with none. Call it inside an observation.
    func rowDetails() -> UKServerUIRowDetails?
}

extension UKServerUIControlBinding {
    func rowDetails() -> UKServerUIRowDetails? { nil }
}

// MARK: - Scene-local state

/// A control over a scene-local field: the value is the field's, a request writes it.
struct UKServerUILocalBinding: UKServerUIControlBinding {
    let spec: UKServerUIControlSpec
    private let current: ServerUICompositionDocument.LocalValue
    private let write: (ServerUICompositionDocument.LocalValue) -> Void

    init?(_ definition: ServerUICompositionDocument.LocalControl, field: ServerUICompositionDocument.LocalField,
          value: ServerUICompositionDocument.LocalValue, send: @escaping (ServerUICompositionDocument.LocalValue) -> Void) {
        typealias Face = UKServerUIControlSpec.Face
        let face: Face
        switch (definition.kind, field.rule) {
        case (.toggle, .boolean): face = .toggle
        case (.stepper, .number(let minimum, let maximum, let step)):
            face = .stepper(minimum: Int(minimum), maximum: Int(maximum), step: Int(step), format: nil)
        case (.choice, .choice(let options)): face = .choice(options)
        case (.segmentedChoice, .choice(let options)): face = .segmented(options)
        case (.textField, .string): face = .text(placeholder: definition.placeholder)
        default: return nil
        }
        spec = UKServerUIControlSpec(title: definition.node.title, identifier: definition.node.id, face: face, unavailableText: nil)
        current = value
        write = send
    }

    func value() -> ServerUICompositionDocument.LocalValue? { current }
    func send(_ value: ServerUICompositionDocument.LocalValue) { write(value) }
}

// MARK: - Home Assistant entity

/// A control over entity state: the value is read from the document's `ha-entity` sources and a request sends an authored call.
struct UKServerUIBoundBinding: UKServerUIControlBinding {
    typealias D = ServerUICompositionDocument
    let control: D.BoundControl
    let reader: UKServerUIReader
    /// What a string slot says (the row's subtitle); `nil` when the control has none to resolve.
    var strings: ((D.StringValue) -> UKServerUIStringAnswer)?
    /// Whether the last call from the control failed (the row's failure words show under it).
    var failed = false
    /// Sends one authored call with the control's new value (the slot names which of the control's calls it is).
    let dispatch: (ServerUICallService, JSONValue?, String) -> Void

    var spec: UKServerUIControlSpec {
        let face: UKServerUIControlSpec.Face
        switch control.kind {
        case .toggle, .button: face = .toggle
        case .stepper:
            let range = control.range ?? .init(minimum: 0, maximum: 100, step: 1)
            face = .stepper(minimum: range.minimum, maximum: range.maximum, step: range.step, format: control.valueFormat)
        case .slider: face = .slider
        case .choice:
            let options = shownOptions
            face = options.count <= 4 ? .segmented(options) : .choice(options)
        }
        return UKServerUIControlSpec(title: control.node.title, identifier: control.node.id, face: face,
                                     unavailableText: control.unavailableText, row: row)
    }

    /// The options a choice shows now: the entity's list when `optionsFrom` reads two or more usable items, else the authored ones
    /// (`sh.bound-options-read@1`).
    private var shownOptions: [D.LocalField.Option] {
        if let read = control.optionsFrom, let items = read.options(in: reader) {
            return items.map { D.LocalField.Option(id: $0.value, label: $0.label) }
        }
        return control.options.map { D.LocalField.Option(id: $0.id, label: $0.label) }
    }

    /// The row's structure, for a toggle drawn as a row that has any authored part; `nil` is the plain switch row.
    ///
    /// The node's `icon` is drawn only with an authored glyph (`sh.bound-row-parts@1`): a bound toggle that carries an icon and no part
    /// keeps the plain switch row it always drew, with no glyph column.
    private var row: UKServerUIControlSpec.Row? {
        guard control.kind == .toggle, control.surface == .row else { return nil }
        let parts = control.row
        guard parts.isAuthored else { return nil }
        return UKServerUIControlSpec.Row(symbol: parts.drawsIcon ? control.icon?.drawn : nil, metrics: parts.metrics,
                                         isCheck: parts.isCheck, checkTint: parts.checkTint, hint: parts.hint,
                                         failureText: parts.failureText, hasSubtitle: parts.subtitle != nil)
    }

    func rowDetails() -> UKServerUIRowDetails? {
        guard row != nil else { return nil }
        var details = UKServerUIRowDetails(failed: failed)
        if let subtitle = control.row.subtitle {
            let answer = strings?(subtitle) ?? UKServerUIStringAnswer(value: .unavailable, isKept: false)
            details.subtitleIsKept = answer.isKept
            switch answer.value {
            case .ready(let text): details.subtitle = text
            case .loading: details.keepsSubtitle = true
            case .unavailable: break
            }
        }
        // A glyph authored for light and dark is a dynamic colour, so a trait change redraws it with no reload (`sh.solid-appearance@1`).
        if let fill = control.row.resolvedGlyph(in: reader), let pair = UKServerUIHomeViews.pair(fill) {
            details.glyph = UIColor(pair.token)
        }
        return details
    }

    func value() -> D.LocalValue? {
        switch control.kind {
        case .toggle:
            switch control.isOn?.evaluate(reader) {
            case .yes: return .boolean(true)
            case .no: return .boolean(false)
            default: return nil
            }
        case .stepper, .slider:
            guard let number = control.value?.evaluate(reader).json?.finiteNumber else { return nil }
            return .number(number)
        case .choice:
            // The options the entity's list gives: the chosen one is the item `current` equals, and none when it is none of them.
            if let read = control.optionsFrom, let items = read.options(in: reader) {
                guard let current = read.currentValue(in: reader) else { return nil }
                return .string(items.contains { $0.value == current } ? current : "")
            }
            let results = control.options.map { $0.selectedWhen.evaluate(reader) }
            if let index = results.firstIndex(of: .yes) { return .string(control.options[index].id) }
            return results.contains(.unknown) ? nil : .string("")
        case .button: return .boolean(false)
        }
    }

    func send(_ value: D.LocalValue) {
        switch (control.kind, value) {
        case (.toggle, .boolean(let on)):
            if let call = on ? control.onAction : control.offAction { dispatch(call, .bool(on), on ? "on" : "off") }
        case (.stepper, .number(let number)), (.slider, .number(let number)):
            if let call = control.action { dispatch(call, .number(number), "set") }
        case (.choice, .string(let id)):
            if let read = control.optionsFrom, let items = read.options(in: reader), items.contains(where: { $0.value == id }) {
                dispatch(read.action, .string(id), "option-\(id)")
            } else if let option = control.options.first(where: { $0.id == id }) { dispatch(option.action, .string(id), "option-\(id)") }
        default: break
        }
    }
}
#endif
