import Foundation

// MARK: - Static operand kind

extension ServerUIOperand {
    /// The kind of value an operand gives, when it can be told from the document alone (the Studio's `operandKind`).
    ///
    /// `nil` means the kind depends on what is read at run time, or on an operand this table does not know; the compiler lets it pass.
    enum StaticKind: Equatable, Sendable { case string, number, boolean, structure }

    /// See ``StaticKind``.
    var staticKind: StaticKind? {
        switch self {
        case .literal(let value):
            switch value {
            case .string: .string
            case .number: .number
            case .bool: .boolean
            case .null: nil
            default: .structure
            }
        case .read(_, _, let kind): kind == .number ? .number : kind == .boolean ? .boolean : .string
        case .viewer(let field): field == .isAdmin ? .boolean : .string
        case .format, .rawState, .lastChanged: .string
        case .listCount, .count: .number
        case .listIncludes: .boolean
        case .math: .number
        case .object, .list: .structure
        case .map(_, _, let otherwise): otherwise.staticKind
        default: nil
        }
    }
}
