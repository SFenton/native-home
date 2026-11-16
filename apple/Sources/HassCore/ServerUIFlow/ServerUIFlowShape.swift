import Foundation

// MARK: - The shape language of a Data Flow

/// What a value looks like, without its data (`sh.pipeline@1`): the Studio infers a shape from a sample, each step has a typing rule from
/// the shape it receives to the shape it gives, and the document carries the authored `responseShape` and `schema` the compiler checks the
/// steps against. Nothing here runs a step; ``ServerUIFlowEvaluator`` does that.
///
/// Nullability is a union with `null`; an object field that may be absent is `optional`. A value of kind `never` has been seen nowhere (an
/// empty list's items) and merges into anything; `any` is a value nothing is known about and absorbs everything.
public indirect enum ServerUIFlowShape: Equatable, Sendable {
    case never
    case any
    case null
    case boolean
    case number(integer: Bool)
    case string(format: Format?, values: [String]?)
    case array(ServerUIFlowShape)
    case object([String: Field])
    case union([ServerUIFlowShape])

    /// The text patterns the Studio recognises and offers steps for.
    public enum Format: String, Sendable, CaseIterable { case date, dateTime = "date-time", entityId = "entity-id", url, numeric }

    /// One field of an object shape. A field that is not `optional` is present in every value.
    public struct Field: Equatable, Sendable {
        public var shape: ServerUIFlowShape
        public var isOptional: Bool
        /// Creates a field.
        public init(_ shape: ServerUIFlowShape, optional: Bool = false) {
            self.shape = shape
            self.isOptional = optional
        }
    }

    /// The kinds of the members of a shape.
    public enum Kind: String, Sendable, CaseIterable { case null, boolean, number, string, array, object, any, never, union }

    /// Limits shared by inference, the schema and the compiler.
    public enum Limits {
        public static let depth = 6, fields = 64, enumValues = 8, enumLength = 64, unionMembers = 6
    }

    public static let integer = ServerUIFlowShape.number(integer: true)
    public static let float = ServerUIFlowShape.number(integer: false)
    public static let text = ServerUIFlowShape.string(format: nil, values: nil)
    public static func text(_ format: Format) -> Self { .string(format: format, values: nil) }

    /// An object whose fields are all required, unless named in `optional`.
    public static func record(_ fields: [String: ServerUIFlowShape], optional: Set<String> = []) -> Self {
        .object(fields.reduce(into: [:]) { result, entry in
            result[entry.key] = Field(entry.value, optional: optional.contains(entry.key))
        })
    }

    /// The kind of this shape.
    public var kind: Kind {
        switch self {
        case .never: .never
        case .any: .any
        case .null: .null
        case .boolean: .boolean
        case .number: .number
        case .string: .string
        case .array: .array
        case .object: .object
        case .union: .union
        }
    }
}

// MARK: - Members, kinds, merging

extension ServerUIFlowShape {
    /// The order unions list their members in.
    private static let order: [Kind] = [.null, .boolean, .number, .string, .array, .object, .any]

    /// The members of a shape: a union's, or the shape itself; `never` has none.
    public var members: [ServerUIFlowShape] {
        switch self {
        case .never: []
        case .union(let list): list
        default: [self]
        }
    }

    /// The one member of `kind` in a shape, if any.
    public func member(_ kind: Kind) -> ServerUIFlowShape? { members.first { $0.kind == kind } }

    /// The kinds a shape can take; `any` is every kind.
    public var kinds: Set<Kind> {
        let found = Set(members.map(\.kind))
        return found.contains(.any) ? Set(Self.order) : found
    }

    /// A shape without its `null` member.
    public var withoutNull: ServerUIFlowShape {
        switch self {
        case .union(let list): Self.combine(list.filter { $0.kind != .null })
        case .null: .never
        default: self
        }
    }

    /// A shape that may also be `null`.
    public var orNull: ServerUIFlowShape { merged(with: .null) }

    /// Whether the shape can be `null` (`any` can).
    public var isNullable: Bool { kinds.contains(.null) || self == .any }

    static func combine(_ list: [ServerUIFlowShape]) -> ServerUIFlowShape {
        list.reduce(.never) { $0.merged(with: $1) }
    }

    /// The shape that fits both. Same-kind members merge (an object keeps every field, a field missing from one side becomes optional; a
    /// string keeps its enum only while both sides have one and it stays within eight values; two different formats drop the format);
    /// different kinds make a union, in the closed order null, boolean, number, string, array, object. `any` absorbs, `never` is the identity.
    public func merged(with other: ServerUIFlowShape) -> ServerUIFlowShape {
        if self == .never { return other }
        if other == .never { return self }
        if self == .any || other == .any { return .any }
        var slots: [Kind: ServerUIFlowShape] = [:]
        for member in members + other.members {
            slots[member.kind] = slots[member.kind].map { Self.mergeMembers($0, member) } ?? member
        }
        let list = slots.values.sorted { Self.order.firstIndex(of: $0.kind)! < Self.order.firstIndex(of: $1.kind)! }
        return list.count == 1 ? list[0] : .union(list)
    }

    private static func mergeMembers(_ a: ServerUIFlowShape, _ b: ServerUIFlowShape) -> ServerUIFlowShape {
        switch (a, b) {
        case (.number(let x), .number(let y)): return .number(integer: x && y)
        case (.string(let formatA, let valuesA), .string(let formatB, let valuesB)):
            let format = formatA != nil && formatA == formatB ? formatA : nil
            var values: [String]?
            if let valuesA, let valuesB, format == nil {
                var all: [String] = []
                // Distinct by scalar values, as the Studio's set is: two spellings that are canonically equivalent are two values.
                var seen: Set<[UInt32]> = []
                for value in valuesA + valuesB where seen.insert(value.unicodeScalars.map(\.value)).inserted { all.append(value) }
                all.sort(by: ServerUIFlowText.scalarsPrecede)
                if all.count <= Limits.enumValues { values = all }
            }
            return .string(format: format, values: values)
        case (.array(let x), .array(let y)): return .array(x.merged(with: y))
        case (.object(let left), .object(let right)):
            var fields: [String: Field] = [:]
            for name in Set(left.keys).union(right.keys) {
                if let l = left[name], let r = right[name] {
                    fields[name] = Field(l.shape.merged(with: r.shape), optional: l.isOptional || r.isOptional)
                } else {
                    fields[name] = Field((left[name] ?? right[name]!).shape, optional: true)
                }
            }
            return .object(fields)
        default: return a
        }
    }
}

// MARK: - Fit

extension ServerUIFlowShape {
    /// Whether every value of `self` is a value of `target`. A target field the value lacks must be optional; extra fields on the value are
    /// fine; `any` fits only `any`; a string with an enum fits a string with the same or a wider enum; an integer fits a number.
    public func isAssignable(to target: ServerUIFlowShape) -> Bool {
        if target == .any || self == .never { return true }
        if self == .any { return false }
        if case .union(let list) = self { return list.allSatisfy { $0.isAssignable(to: target) } }
        if target == .never { return false }
        if case .union(let list) = target { return list.contains { isAssignable(to: $0) } }
        switch (self, target) {
        case (.number(let integer), .number(let needsInteger)): return !needsInteger || integer
        case (.string(let format, let values), .string(let wantedFormat, let wantedValues)):
            if let wantedFormat, format != wantedFormat { return false }
            guard let wantedValues else { return true }
            return values.map { $0.allSatisfy(wantedValues.contains) } ?? false
        case (.array(let x), .array(let y)): return x.isAssignable(to: y)
        case (.object(let have), .object(let want)):
            return want.allSatisfy { name, field in
                guard let held = have[name] else { return field.isOptional }
                return (!held.isOptional || field.isOptional) && held.shape.isAssignable(to: field.shape)
            }
        default: return kind == target.kind
        }
    }
}

// MARK: - Reading a shape

extension ServerUIFlowShape {
    /// The shape of the field `name` of an object, or of the fields of every object in a union; `null` and `any` members pass through.
    public func field(_ name: String) -> ServerUIFlowShape? {
        var result: ServerUIFlowShape?
        var reachable = false
        for member in members {
            switch member {
            case .any: return .any
            case .null: result = (result ?? .never).merged(with: .null)
            case .object(let fields):
                if let found = fields[name] {
                    reachable = true
                    result = (result ?? .never).merged(with: found.isOptional ? found.shape.orNull : found.shape)
                } else {
                    result = (result ?? .never).merged(with: .null)
                }
            default: break
            }
        }
        // Only an object that has the field makes it reachable; a union of objects that all lack it is an unknown field.
        return reachable ? result : nil
    }

    /// The shape at `path`, or `nil` when a segment names no field. An empty path is the shape itself.
    public func shape(at path: [String]) -> ServerUIFlowShape? {
        var current: ServerUIFlowShape? = self
        for segment in path {
            guard let held = current else { return nil }
            current = held.field(segment)
        }
        return current
    }

    /// The item shape of a list (`any` for an unknown list); `null` members count as an empty list. `nil` when the shape is not a list.
    public var element: ServerUIFlowShape? {
        var result: ServerUIFlowShape?
        for member in members {
            if member == .any { return .any }
            if case .array(let of) = member { result = (result ?? .never).merged(with: of) }
        }
        return result
    }

    /// Whether the shape has an object member (or is `any`).
    public var hasObject: Bool { kinds.contains(.object) }

    /// A copy of an object shape with the field at `path` set to `leaf` (required). The parents must be objects; `nil` when they are not.
    public func settingField(at path: [String], to leaf: ServerUIFlowShape) -> ServerUIFlowShape? {
        guard let head = path.first else { return leaf }
        let rest = Array(path.dropFirst())
        let slots = members
        if !slots.contains(where: { $0.kind == .object }) { return self == .any ? .any : nil }
        var result = ServerUIFlowShape.never
        for member in slots {
            guard case .object(let fields) = member else { result = result.merged(with: member); continue }
            let next: ServerUIFlowShape?
            if rest.isEmpty { next = leaf } else if let held = fields[head] { next = held.shape.settingField(at: rest, to: leaf) } else { next = nil }
            guard let next else { return nil }
            var copy = fields
            copy[head] = Field(next)
            result = result.merged(with: .object(copy))
        }
        return result
    }

    /// Whether the shape is made only of scalar kinds (and `null`), so it can be compared, sorted or printed.
    public var isScalar: Bool {
        members.allSatisfy { [.any, .null, .boolean, .number, .string].contains($0.kind) }
    }
}

// MARK: - Problems of size and form

extension ServerUIFlowShape {
    /// The first problem in a shape's size or form that the structure check cannot say, as a pointer suffix and code; `nil` when sound.
    public func problem(at pointer: String = "", depth: Int = 1) -> (code: ServerUICompositionError.Code, pointer: String)? {
        if depth > Limits.depth { return (.limitExceeded, pointer) }
        switch self {
        case .array(let of): return of.problem(at: pointer + "/of", depth: depth + 1)
        case .object(let fields):
            if fields.count > Limits.fields { return (.limitExceeded, pointer + "/fields") }
            for name in fields.keys.sorted() {
                if let found = fields[name]!.shape.problem(at: ServerUICompositionJSON.pointer(pointer + "/fields", name) + "/shape", depth: depth + 1) {
                    return found
                }
            }
            return nil
        case .union(let list):
            var seen: Set<Kind> = []
            for (index, member) in list.enumerated() {
                if member.kind == .union || member.kind == .never || !seen.insert(member.kind).inserted {
                    return (.invalidValue, pointer + "/of/\(index)")
                }
                if let found = member.problem(at: pointer + "/of/\(index)", depth: depth + 1) { return found }
            }
            return nil
        case .string(let format, let values):
            if let values, format != nil || Set(values.map { $0.unicodeScalars.map(\.value) }).count != values.count { return (.invalidValue, pointer + "/enum") }
            return nil
        default: return nil
        }
    }
}
