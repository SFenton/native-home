import Foundation

// MARK: - Hooks into the document compiler

/// A node that names a source as the provider of its rows: a `row-collection` or a `collection`.
struct ServerUIFlowProviderRef {
    let id: String
    let isCollection: Bool
    let template: String?
    let refreshable: Bool
    /// The pointer of the node's `props`.
    let pointer: String
}

extension ServerUICompositionCompiler {
    /// Compiles a `pipeline@1` source: reads its inputs, checks the flow against its own shapes, and gives the document compiler the
    /// reads (for the source checks) and the dependencies (for the cycle check) it needs.
    mutating func flowSource(id: String, _ c: Cursor) throws -> D.Source {
        let inputs = try c.field("inputs")
        let decoded = ServerUIFlowDecoder.decode(inputs.value, at: inputs.pointer)
        issues += decoded.issues
        guard let flow = decoded.flow else { throw Issue(.invalidValue, inputs.pointer) }
        let found = ServerUIFlowCompiler.check(flow, at: c.pointer)
        issues += found.issues
        for capability in found.capabilities { require(capability) }
        // Only a parameter may read another source; the typing refuses a `read` anywhere else.
        let parameters = inputs.pointer + "/parameters/"
        expressionRefs += decoded.references.filter { $0.kind != nil && $0.pointer.hasPrefix(parameters) }
        for read in found.reads { dependencies.append((id, read.sourceId, read.pointer + "/from/sourceId")) }
        flowCount += 1
        if flowCount > ServerUIFlow.Limits.flows { add(.limitExceeded, c.pointer) }
        return .pipeline(id: id, flow: flow)
    }

    /// The parts of a `row-collection` beyond its texts (`sh.list-parts@1`): a tap on a row, pull to refresh and a line under the empty
    /// title. Each is needed only when present, and a row's action is never a domain action.
    mutating func listParts(_ props: Cursor) throws -> (rowAction: D.Action?, refreshable: Bool, emptyMessage: D.StringValue?) {
        let hasParts = props.value["rowAction"] != nil || props.value["refreshable"] != nil || props.value["emptyMessage"] != nil
        if hasParts { require("list-parts") }
        var rowAction: D.Action?
        if props.value["rowAction"] != nil {
            let field = try props.field("rowAction")
            let intent = try action(field)
            check(intent, at: field.pointer) { if case .domain = $0 { false } else { true } }
            rowAction = intent
        }
        let refreshable = try props.value["refreshable"] == nil ? false : props.b("refreshable")
        let message = try props.value["emptyMessage"] == nil ? nil : stringValue(props.field("emptyMessage"))
        providerRefs.append(.init(id: try props.s("providerId"), isCollection: false, template: nil, refreshable: refreshable, pointer: props.pointer))
        return (rowAction, refreshable, message)
    }

    /// Checks each node that names a flow as its provider: only a rows flow is one, and pulling it needs a flow a person can pull.
    mutating func checkFlowProviders(_ sources: [String: D.Source]) {
        for ref in providerRefs {
            guard case .pipeline(_, let flow)? = sources[ref.id] else { continue }
            issues += ServerUIFlowCompiler.checkProvider(flow, isCollection: ref.isCollection, template: ref.template,
                                                         refreshable: ref.refreshable, at: ref.pointer)
        }
    }
}
