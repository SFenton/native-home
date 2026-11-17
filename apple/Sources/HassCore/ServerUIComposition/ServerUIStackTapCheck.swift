import Foundation

// MARK: - A stack with an action holds nothing that takes a tap (`sh.stack@1`)

/// The check that a `stack` with an `action` is one button: no descendant takes a tap of its own.
///
/// It reads the document as written, not as expanded, the way the Studio does (`compiler.ts`, `taps`): a `component-ref` is seen as the body of
/// its library entry (so a button inside a saved component is refused), and the walk goes into a stack's children, a `local-tabs` node's tabs
/// then its blocks, and a `pinned-actions` node's children. The pointer blamed is the `type` of the tappable node, at the index the walk
/// counted, which for a node under a reference or a tab list is where the Studio blames it too.
enum ServerUIStackTapCheck {
    typealias Issue = ServerUICompositionError

    /// The types of nodes that take a tap of their own.
    private static let tappable: Set<String> = ["primary-button", "bound-control", "local-control", "navigation-tile", "action-tile", "state-tile",
                                                "status-chip", "row", "settings-link"]
    /// The types whose `children` the walk enters.
    private static let containers: Set<String> = ["tile-grid", "overlay", "stack", "repeat", "section", "status-rail", "room-section", "paged-row",
                                                  "pinned-actions"]

    /// The issues of every stack with an action in the publication `json`, in walk order.
    static func issues(in json: JSONValue) -> [Issue] {
        guard let document = json["document"] else { return [] }
        var library: [String: JSONValue] = [:]
        for entry in document["componentLibrary"]?.array ?? [] {
            if let id = entry["id"]?.string, let node = entry["node"] { library[id] = node }
        }
        var found: [Issue] = []
        func visit(_ node: JSONValue, at pointer: String) {
            if node["type"]?.string == "stack", node["action"] != nil {
                taps(in: node["children"]?.array ?? [], at: pointer + "/children", library: library, into: &found)
            }
            // The Studio's own walk reaches a tab's or a block's child at its place in that list, not in the flattened one.
            if node["type"]?.string == "local-tabs" {
                for key in ["tabs", "blocks"] {
                    for (group, entry) in (node[key]?.array ?? []).enumerated() {
                        for (index, child) in (entry["children"]?.array ?? []).enumerated() { visit(child, at: "\(pointer)/\(key)/\(group)/children/\(index)") }
                    }
                }
            } else {
                for (index, child) in children(of: node).enumerated() { visit(child, at: "\(pointer)/children/\(index)") }
            }
        }
        for (key, kind) in [("pages", "pages"), ("modals", "modals")] {
            for (index, surface) in (document[key]?.array ?? []).enumerated() {
                for (position, node) in (surface["components"]?.array ?? []).enumerated() {
                    visit(node, at: "/document/\(kind)/\(index)/components/\(position)")
                }
            }
        }
        for (index, entry) in (document["componentLibrary"]?.array ?? []).enumerated() {
            if let node = entry["node"] { visit(node, at: "/document/componentLibrary/\(index)/node") }
        }
        return found
    }

    /// Blames each tappable node among `nodes`, looking into the rest.
    private static func taps(in nodes: [JSONValue], at path: String, library: [String: JSONValue], into found: inout [Issue]) {
        for (index, child) in nodes.enumerated() {
            var shown = child
            if child["type"]?.string == "component-ref" {
                if let id = child["componentId"]?.string, let body = library[id] { shown = body }
            }
            let type = shown["type"]?.string ?? ""
            if tappable.contains(type) || (type == "stack" && shown["action"] != nil) {
                found.append(Issue(.invalidCombination, "\(path)/\(index)/type"))
            } else {
                taps(in: children(of: shown), at: "\(path)/\(index)/children", library: library, into: &found)
            }
        }
    }

    /// The children of `node` as the Studio's `compositionChildren` lists them.
    private static func children(of node: JSONValue) -> [JSONValue] {
        let type = node["type"]?.string ?? ""
        if type == "local-tabs" {
            return ["tabs", "blocks"].flatMap { key in (node[key]?.array ?? []).flatMap { $0["children"]?.array ?? [] } }
        }
        return containers.contains(type) ? node["children"]?.array ?? [] : []
    }
}
