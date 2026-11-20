import Foundation

// MARK: - Saved components (`sh.component-ref@1`) shape

extension ServerUICompositionShape {
    /// The most a library entry and a use of it may hold (the Studio's `COMPONENT_LIMITS`).
    enum ComponentLimits {
        static let parameters = 16, bindings = 128, arguments = 16, sources = 8, flows = 8
    }
    /// The kinds a parameter may have, as the Studio's `ComponentParamKind`.
    static let componentParameterKinds = ["source-id", "page-id", "modal-id", "entity-id", "state-id", "text", "symbol"]

    /// A use of a saved component: the entry it names, its width and one argument for each parameter. It has no title, rule, props or
    /// children; the entry's body is all of them.
    static let componentRef: Shape = {
        object([
            "id": id, "type": fixed("component-ref"), "componentId": id,
            "layout": layoutSpan,
            "args": .optional(.dictionary(.text(80, blank: true), .text(240, blank: false), ComponentLimits.arguments))
        ])
    }()

    /// A data source a component owns: a Home Assistant entity, as a literal.
    static let componentSource: Shape = {
        object(["id": id, "kind": fixed("ha-entity"), "entityId": object(["type": fixed("literal"), "value": .text(160, blank: false)])])
    }()

    /// One saved component: its name, where it came from, the parameters it declares, the data sources it owns, which field of which body node or source each
    /// parameter fills, and the body. `origin` and each parameter's `label` are read and ignored: they serve the Studio's editing forms.
    static let componentEntry: Shape = {
        object([
            "id": id, "name": label,
            "origin": .optional(object(["id": id, "version": .number(1, 9999, integer: true)])),
            "params": .optional(array(object([
                "name": id, "kind": .choice(componentParameterKinds), "label": .optional(label)
            ]), ComponentLimits.parameters)),
            "sources": .optional(array(componentSource, ComponentLimits.sources)),
            // The Data Flows it owns (`sh.repeat@1`), copied and renamed for each use like its sources.
            "flows": .optional(array(pipelineSource, ComponentLimits.flows)),
            "bindings": .optional(array(object([
                "param": id, "nodeId": .optional(id), "sourceId": .optional(id), "field": .text(160, blank: false)
            ]), ComponentLimits.bindings)),
            "node": .component
        ])
    }()
}
