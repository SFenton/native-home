import Foundation

// MARK: - Saved components (`sh.component-ref@1`) shape

extension ServerUICompositionShape {
    /// A use of a saved component: the entry it names, its width and one argument for each parameter. It has no title, rule, props or
    /// children; the entry's body is all of them.
    static let componentRef: Shape = {
        object([
            "id": id, "type": fixed("component-ref"), "componentId": id,
            "layout": object(["span": .optional(.number(1, 4, integer: true))]),
            "args": .optional(.dictionary(.text(80, blank: true), .text(240, blank: false), 8))
        ])
    }()

    /// One saved component: its name, the parameters it declares, which field of which body node each one fills, and the body.
    static let componentEntry: Shape = {
        object([
            "id": id, "name": label,
            "params": .optional(array(object(["name": id, "kind": .choice(["source-id", "page-id", "modal-id", "text", "symbol"])]), 8)),
            "bindings": .optional(array(object(["param": id, "nodeId": id, "field": .text(160, blank: false)]), 64)),
            "node": .component
        ])
    }()
}
