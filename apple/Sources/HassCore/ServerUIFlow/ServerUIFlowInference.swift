import Foundation

// MARK: - Shape inference

/// Shape inference: the shape of a sample, and the merge of many. The rules are fixed so the Studio and the app show the same outline:
/// a whole number is `number` with `integer`; a string is a `date`, `date-time`, `entity-id`, `url` or `numeric` in that order, else a
/// candidate for an `enum` (at most 64 characters); a list is the merge of its items; an object lists its fields, each required.
public enum ServerUIFlowInference {
    /// Whether the text is a date (`YYYY-MM-DD`, a real calendar date).
    public static func isDateText(_ text: String) -> Bool {
        text.utf8.count == 10 && ServerUIDates.wallTime(text, utcOffsetMinutes: 0) != nil
    }

    /// Whether the text is a date and time.
    public static func isDateTimeText(_ text: String) -> Bool {
        text.utf8.count > 10 && ServerUIDates.wallTime(text, utcOffsetMinutes: 0) != nil
    }

    /// The format a string is recognised as, if any.
    public static func stringFormat(_ value: String) -> ServerUIFlowShape.Format? {
        if isDateText(value) { return .date }
        if isDateTimeText(value) { return .dateTime }
        if value.utf16.count <= 160, ServerUICompositionShape.matches(value, "^[a-z][a-z0-9_]*\\.[a-z0-9_]+$") { return .entityId }
        if ServerUICompositionShape.matches(value, "^https?://[^\\s]+$") { return .url }
        if ServerUICompositionShape.matches(value, "^-?[0-9]{1,18}(\\.[0-9]{1,18})?$") { return .numeric }
        return nil
    }

    /// The shape of one value.
    public static func shape(of value: JSONValue, depth: Int = 1) -> ServerUIFlowShape {
        switch value {
        case .null: return .null
        case .bool: return .boolean
        case .number(let number): return .number(integer: number.isFinite && number.rounded() == number)
        case .string(let text):
            if let format = stringFormat(text) { return .string(format: format, values: nil) }
            return text.utf16.count <= ServerUIFlowShape.Limits.enumLength ? .string(format: nil, values: [text]) : .text
        case .array(let items):
            if depth > 32 { return .any }
            return .array(items.reduce(.never) { $0.merged(with: shape(of: $1, depth: depth + 1)) })
        case .object(let fields):
            if depth > 32 { return .any }
            return .object(fields.mapValues { ServerUIFlowShape.Field(shape(of: $0, depth: depth + 1)) })
        }
    }

    /// The shape that fits every sample (`never` for none).
    public static func shape(ofSamples samples: [JSONValue]) -> ServerUIFlowShape {
        samples.reduce(.never) { $0.merged(with: shape(of: $1)) }
    }
}
