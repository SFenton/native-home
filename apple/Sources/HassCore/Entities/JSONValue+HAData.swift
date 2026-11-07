import Foundation
@preconcurrency import HAKit

extension JSONValue {
    /// Converts a HAKit result.
    init(haData: HAData) {
        switch haData {
        case let .dictionary(values): self = JSONValue(any: values)
        case let .array(values): self = .array(values.map(JSONValue.init(haData:)))
        case let .primitive(value): self = JSONValue(any: value)
        case .empty: self = .null
        }
    }
}
