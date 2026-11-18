import Foundation

// MARK: - Compiling a flow

/// The compiler rules of `sh.pipeline@1` that need only the flow itself: every reference inside it, the acyclic parameters, each step's
/// typing, the output and `schema`, the request and refresh rules, and the limits. What needs the whole document (a `read` of another
/// source, a node that names the flow as its provider) is ``checkRead(_:path:as:)`` and ``checkProvider(_:isCollection:template:refreshable:at:)``,
/// which the document compiler calls with the source in hand.
public enum ServerUIFlowCompiler {
    typealias Issue = ServerUICompositionError
    typealias Typing = ServerUIFlowTyping
    typealias Shape = ServerUIFlowShape
    typealias Kind = ServerUICompositionDocument.ScalarKind

    /// What compiling one flow found.
    public struct Result {
        public var issues: [ServerUICompositionError]
        /// Every `read` a parameter makes: the source it names and the pointer of the operand.
        var reads: [(sourceId: String, pointer: String)]
        /// The capabilities (without `sh.` and `@1`) the flow needs.
        public var capabilities: [String]
    }

    /// The capability of the data-source model.
    public static let capability = "pipeline"
    /// The capability of the operands that exist only inside a flow (`item`, `param`, `clock`, `date`).
    public static let operandsCapability = "pipeline-operands"

    private static func join(_ base: String, _ parts: Any...) -> String {
        parts.reduce(base) { pointer, part in
            if let name = part as? String { ServerUICompositionJSON.pointer(pointer, name) } else { pointer + "/\(part)" }
        }
    }

    private static let entityPattern = "^[a-z][a-z0-9_]*\\.[a-z0-9_]+$"

    // MARK: The flow

    /// Compiles one flow. `at` is the source's pointer, such as `/document/dataSources/3`.
    public static func check(_ flow: ServerUIFlow, at source: String) -> Result {
        let base = join(source, "inputs")
        var facts = Typing.Facts()
        func issue(_ code: Issue.Code, _ pointer: String) { facts.issues.append(Issue(code, pointer)) }

        // Parameters: unique names, typed values, no reference to an unknown name, no cycle.
        var kinds: [String: Kind] = [:]
        for (index, parameter) in flow.parameters.enumerated() {
            if kinds[parameter.name] != nil { issue(.duplicateID, join(base, "parameters", index, "name")) } else { kinds[parameter.name] = parameter.kind }
        }
        var parameterRefs: [(from: String, name: String, pointer: String)] = []
        let parameterScope = Typing.Scope(item: nil, parameters: kinds, allowsRead: true, allowsViewer: true)
        for (index, parameter) in flow.parameters.enumerated() {
            let own = join(base, "parameters", index, "value")
            var local = Typing.Facts()
            var budget = Typing.Budget()
            let shape = Typing.type(parameter.value, parameterScope, at: own, &local, budget: &budget)
            facts.issues += local.issues
            facts.reads += local.reads
            facts.needsOperands = facts.needsOperands || local.needsOperands
            facts.usesRules = facts.usesRules || local.usesRules
            facts.flowExtras = facts.flowExtras || local.flowExtras
            facts.usesRepeat = facts.usesRepeat || local.usesRepeat
            facts.edge.formUnion(local.edge)
            for ref in local.parameterReferences {
                facts.parameterReferences.append(ref)
                parameterRefs.append((parameter.name, ref.name, ref.pointer))
            }
            let have = shape.withoutNull.kinds
            let wants: Shape.Kind = parameter.kind == .number ? .number : parameter.kind == .boolean ? .boolean : .string
            if !have.isEmpty, !have.contains(wants) { issue(.bindingType, own) }
            if parameter.kind == .entityID, case .literal(let value) = parameter.value {
                if case .string(let text) = value, ServerUICompositionShape.matches(text, entityPattern) {} else { issue(.invalidValue, join(own, "value")) }
            }
        }
        for ref in parameterRefs where kinds[ref.name] != nil {
            var pending = [ref.name], seen: Set<String> = []
            while let name = pending.popLast() {
                if name == ref.from { issue(.invalidCombination, ref.pointer); break }
                if seen.insert(name).inserted { pending += parameterRefs.filter { $0.from == name }.map(\.name) }
            }
        }

        // Request.
        let requestAt = join(base, "request")
        let requestScope = Typing.Scope(item: nil, parameters: kinds, allowsRead: false, allowsViewer: true)
        func absorb(_ local: Typing.Facts) {
            facts.issues += local.issues
            facts.parameterReferences += local.parameterReferences
            facts.needsOperands = facts.needsOperands || local.needsOperands
            facts.usesRules = facts.usesRules || local.usesRules
            facts.flowExtras = facts.flowExtras || local.flowExtras
            facts.usesRepeat = facts.usesRepeat || local.usesRepeat
            facts.edge.formUnion(local.edge)
        }
        func shapeCheck(_ shape: Shape, _ pointer: String) { if let found = shape.problem(at: pointer) { issue(found.code, found.pointer) } }
        func entity(_ value: String, at: String, domain: String? = nil) {
            if !ServerUICompositionShape.matches(value, entityPattern) { issue(.invalidValue, join(at, "value")) }
            else if let domain, !value.hasPrefix(domain + ".") { issue(.invalidCombination, join(at, "value")) }
        }
        switch flow.request {
        case .serviceResponse(_, _, let target, let data, _, let responseShape):
            var local = Typing.Facts()
            let targets = (target ?? [:]).sorted { $0.key < $1.key }
            if target != nil, targets.isEmpty { issue(.invalidValue, join(requestAt, "target")) }
            for (key, operand) in targets {
                let own = join(requestAt, "target", key)
                var budget = Typing.Budget()
                _ = Typing.type(operand, requestScope, at: own, &local, budget: &budget)
                if case .literal(let value) = operand {
                    let strings = value.array?.compactMap(\.string)
                    let listed = strings.map { !$0.isEmpty && $0.count == value.array?.count } ?? false
                    let ok: Bool
                    if key == "entity_id" {
                        ok = (value.string.map { ServerUICompositionShape.matches($0, entityPattern) } ?? false)
                            || (listed && strings!.allSatisfy { ServerUICompositionShape.matches($0, entityPattern) })
                    } else {
                        ok = (value.string.map { !$0.isEmpty } ?? false) || (listed && strings!.allSatisfy { !$0.isEmpty })
                    }
                    if !ok { issue(.invalidValue, join(own, "value")) }
                }
                if case .object(let fields)? = data, fields[key] != nil { issue(.invalidCombination, own) }
            }
            if let data {
                var budget = Typing.Budget()
                _ = Typing.type(data, requestScope, at: join(requestAt, "data"), &local, budget: &budget)
            }
            absorb(local)
            shapeCheck(responseShape, join(requestAt, "responseShape"))
        case .entityAttribute(let id, let path, let responseShape):
            entity(id, at: join(requestAt, "entityId"))
            Typing.checkSegments(path, at: join(requestAt, "path"), &facts)
            shapeCheck(responseShape, join(requestAt, "responseShape"))
        case .entities(let ids, let attributes):
            var seen: Set<String> = [], names: Set<String> = []
            for (index, id) in ids.enumerated() {
                let own = join(requestAt, "entityIds", index)
                entity(id, at: own)
                if !seen.insert(id).inserted { issue(.invalidCombination, join(own, "value")) }
            }
            for (index, name) in attributes.enumerated() {
                let own = join(requestAt, "attributes", index)
                if name.allSatisfy(\.isNumber) || ServerUICompositionJSON.reserved.contains(name) || ["entityId", "state"].contains(name) {
                    issue(.invalidReference, own)
                } else if names.contains(name) { issue(.invalidCombination, own) }
                names.insert(name)
            }
        case .none(let value):
            var local = Typing.Facts()
            var budget = Typing.Budget()
            _ = Typing.type(value, requestScope, at: join(requestAt, "value"), &local, budget: &budget)
            absorb(local)
        case .subscription(let feed):
            entity(feed.entityId, at: join(requestAt, "entityId"), domain: ServerUIFlowSources.domain(feed))
        }

        // Refresh: a live source takes none; the others state when they run again.
        let refreshAt = join(base, "refresh")
        var isService = false
        var takesRefresh = true
        switch flow.request {
        case .subscription, .entities, .none: takesRefresh = false
        case .serviceResponse: isService = true
        case .entityAttribute: break
        }
        if !takesRefresh {
            if flow.refresh != nil { issue(.invalidCombination, refreshAt) }
        } else if let refresh = flow.refresh {
            if Set(refresh.on).count != refresh.on.count { issue(.invalidCombination, join(refreshAt, "on")) }
            let watches = refresh.on.contains(.entityChange)
            if isService {
                if watches, refresh.entityIds == nil { issue(.invalidCombination, join(refreshAt, "on")) }
                if !watches, refresh.entityIds != nil { issue(.invalidCombination, join(refreshAt, "entityIds")) }
            } else if refresh.entityIds != nil { issue(.invalidCombination, join(refreshAt, "entityIds")) }
            var seen: Set<String> = []
            for (index, id) in (refresh.entityIds ?? []).enumerated() {
                let own = join(refreshAt, "entityIds", index)
                entity(id, at: own)
                if !seen.insert(id).inserted { issue(.invalidCombination, join(own, "value")) }
            }
        } else { issue(.missingRequired, refreshAt) }

        // Steps and output.
        var stepIds: Set<String> = []
        for (index, step) in flow.steps.enumerated() {
            if !stepIds.insert(step.id).inserted { issue(.duplicateID, join(base, "steps", index, "id")) }
        }
        let before = facts.issues.count
        var stepFacts = Typing.Facts()
        let input: Shape
        if case .none(let value) = flow.request {
            var scratch = Typing.Facts()
            var budget = Typing.Budget()
            input = Typing.type(value, requestScope, at: join(requestAt, "value"), &scratch, budget: &budget)
        } else { input = ServerUIFlowSources.requestShape(flow.request) }
        let shapes = Typing.types(flow.steps, input: input, parameters: kinds, at: base, &stepFacts)
        absorb(stepFacts)
        let final = shapes.last ?? input
        let clean = facts.issues.count == before
        let outputAt = join(base, "output")
        let rowScope = { (item: Shape) in Typing.Scope(item: item, parameters: kinds, allowsRead: false, allowsViewer: false) }
        if clean {
            let core = final.withoutNull, present = core.kinds
            switch flow.output {
            case .rows(_, let row):
                if let element = final.element {
                    var local = Typing.Facts()
                    let operands: [(String, ServerUIOperand?)] = [("id", row.id), ("title", row.title), ("subtitle", row.subtitle), ("value", row.value)]
                    for (key, operand) in operands {
                        guard let operand else { continue }
                        let own = join(outputAt, "row", key)
                        var budget = Typing.Budget()
                        let shape = Typing.type(operand, rowScope(element), at: own, &local, budget: &budget)
                        let have = shape.withoutNull.kinds
                        if !have.isEmpty, ![Shape.Kind.boolean, .number, .string].contains(where: have.contains) { issue(.bindingType, own) }
                    }
                    absorb(local)
                } else { issue(.bindingType, join(outputAt, "kind")) }
            case .records:
                // `sh.repeat@1`: a list of objects, which the `repeat` node reads by field.
                if let element = final.element { if !element.hasObject { issue(.bindingType, join(outputAt, "kind")) } }
                else { issue(.bindingType, join(outputAt, "kind")) }
            case .record:
                if core != .any, !(present.count == 1 && present.contains(.object)) { issue(.bindingType, join(outputAt, "kind")) }
            case .scalar:
                if core != .any, present.isEmpty || !present.allSatisfy({ [Shape.Kind.boolean, .number, .string].contains($0) }) {
                    issue(.bindingType, join(outputAt, "kind"))
                }
            }
        }

        // The authored shape must be sound, of the output's kind, and something the steps produce.
        let schemaAt = join(base, "schema")
        if let found = flow.schema.problem(at: schemaAt) { issue(found.code, found.pointer) }
        else {
            let have = flow.schema.withoutNull.kinds
            let wanted: Bool
            switch flow.output {
            case .rows: wanted = have.count == 1 && have.contains(.array)
            case .records:
                if have.count == 1, have.contains(.array), let element = flow.schema.element, element != .any, element.hasObject {
                    wanted = element.withoutNull.kinds.count == 1
                } else { wanted = false }
            case .record: wanted = have.count == 1 && have.contains(.object)
            case .scalar: wanted = !have.isEmpty && have.allSatisfy { [Shape.Kind.boolean, .number, .string].contains($0) } && flow.schema != .any
            }
            if flow.schema == .any || !wanted { issue(.invalidCombination, schemaAt) }
            else if facts.issues.count == before, !final.withoutNull.isAssignable(to: flow.schema.withoutNull) { issue(.bindingType, schemaAt) }
        }

        // References to parameters that do not exist.
        for ref in facts.parameterReferences where kinds[ref.name] == nil { issue(.invalidReference, ref.pointer) }
        if flow.steps.count > ServerUIFlow.Limits.steps { issue(.limitExceeded, join(base, "steps")) }

        let capabilities = [capability] + (facts.needsOperands ? [operandsCapability] : []) + (facts.usesRules ? ["rules"] : [])
            + (flow.givesRecords || facts.usesRepeat ? ["repeat"] : []) + (facts.flowExtras ? ["flow-extras"] : []) + facts.edge.sorted()
        return Result(issues: facts.issues, reads: facts.reads.map { ($0.sourceId, $0.pointer) }, capabilities: capabilities)
    }

    // MARK: Reads and providers

    /// What was wrong with a read or a provider: the code and the pointer suffix relative to the reference.
    public struct ReadIssue: Equatable, Sendable {
        public let code: ServerUICompositionError.Code
        public let suffix: String
    }

    /// Checks a `read` that names a flow: a record flow is read by field name, a scalar flow by `["value"]`, a rows or records flow not at all (a list
    /// cannot be indexed; a node shows rows through its provider). The field must exist in `schema` and be a scalar of the kind the read asks for.
    public static func checkRead(_ flow: ServerUIFlow, path: [String], as kind: ServerUICompositionDocument.ScalarKind) -> ReadIssue? {
        let leaf: Shape?
        switch flow.output {
        case .rows, .records: return ReadIssue(code: .invalidReference, suffix: "/from/path")
        case .scalar: leaf = path == ["value"] ? flow.schema : nil
        case .record: leaf = flow.schema.shape(at: path)
        }
        guard let leaf else { return ReadIssue(code: .invalidReference, suffix: "/from/path") }
        let have = leaf.withoutNull.kinds
        if have.isEmpty { return nil }
        let want: Shape.Kind = kind == .number ? .number : kind == .boolean ? .boolean : .string
        return have.contains(want) ? nil : ReadIssue(code: .bindingType, suffix: "/as")
    }

    /// Checks a `repeat` node's `providerId` (`sh.repeat@1`): only a records flow is drawn by a `repeat`, so any other output is `binding_type` at the
    /// provider. `at` is the pointer of the node's `props`. Returns the shape of one record when the flow gives records.
    public static func checkRepeatProvider(_ flow: ServerUIFlow, at: String) -> (issues: [ServerUICompositionError], item: ServerUIFlowShape?) {
        guard flow.givesRecords else { return ([Issue(.bindingType, join(at, "providerId"))], nil) }
        return ([], flow.schema.element)
    }

    /// Checks a node that names a flow as its `providerId`: only a rows flow is a provider, and a `collection` shows it with the `rows`
    /// template. `at` is the pointer of the node's `props`. Returns issues with absolute pointers.
    public static func checkProvider(_ flow: ServerUIFlow, isCollection: Bool, template: String?, refreshable: Bool, at: String) -> [ServerUICompositionError] {
        var found: [ServerUICompositionError] = []
        if !flow.givesRows { found.append(Issue(.bindingType, join(at, "providerId"))) }
        // Pull to refresh runs the flow again, so the flow must be one a person can pull ("When pulled": `manual`); a live flow has no refresh.
        if refreshable, !flow.refreshesManually { found.append(Issue(.invalidCombination, join(at, "refreshable"))) }
        if isCollection, template != "rows" { found.append(Issue(.invalidCombination, join(at, "template"))) }
        return found
    }
}
