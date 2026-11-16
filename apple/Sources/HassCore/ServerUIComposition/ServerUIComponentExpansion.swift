import Foundation

// MARK: - Saved components (`sh.component-ref@1`)

/// The compile-time expansion of a document's saved components.
///
/// A document may carry a `componentLibrary` (saved nodes with named parameters) and `component-ref` nodes that stand for one entry.
/// This type turns the shape-checked publication into the document the compiler decodes: every reference is replaced by its entry's
/// body, so the pages and the UIKit renderer see plain nodes and nothing is resolved at run time. The same pure rules run in the
/// Studio (`src/shared/composition/components.ts`, `expandRef`).
///
/// - The root of an expansion takes the reference's id and width; every other node is `<reference id>~<its id>`, a character the
///   identifier alphabet excludes, so a derived id never equals an authored one.
/// - Each binding writes the reference's argument into one field of one body node. Nothing else changes: tab, option, source, page
///   and sheet ids are document-level names and stay as written.
/// - Each library body is also compiled once, at its own pointer, whether or not anything uses it (``bodies``).
/// - Issues the compiler finds in an expansion move back to where the author can fix them: a bound field to `args/<name>`, the root's
///   placement to the reference's `componentId`, a limit to the reference, anything else to the body (``remapped(_:)``).
struct ServerUIComponentExpansion {
    typealias Issue = ServerUICompositionError

    /// A library body the compiler checks once at its own pointer.
    struct Body {
        /// `/document/componentLibrary/<i>/node`.
        let pointer: String
        /// The body with each nested reference replaced by a placeholder (a reference there is reported separately).
        let value: JSONValue
    }

    /// An argument that names a page, a sheet or a data source, checked once the document's catalogs are known.
    struct ArgumentReference {
        /// `page`, `modal` or `source`, a key of the compiler's catalogs.
        let catalog: String
        let id: String
        /// `<reference>/args/<name>`.
        let pointer: String
    }

    /// One use of a component: where the reference sits (and so where its expansion sits), which entry it expands, and which
    /// expansion pointers hold an argument.
    struct Region {
        let pointer: String
        let entry: Int
        /// The pointer inside the expansion of each bound field, to the parameter that filled it.
        let bound: [String: String]
    }

    /// The publication the compiler decodes: references replaced, `componentLibrary` removed.
    let expanded: JSONValue
    /// Whether the document holds a library or a reference, so it needs `sh.component-ref@1`.
    let usesComponents: Bool
    /// Structural issues of the library and of the references, at the document's own pointers.
    let issues: [Issue]
    /// Every library body, in library order.
    let bodies: [Body]
    /// The arguments that name a page, a sheet or a source.
    let argumentReferences: [ArgumentReference]
    private let regions: [Region]
    /// Argument pointers already refused for their value: what the compiler also finds there is the same fault, said twice.
    private let refusedArguments: Set<String>

    /// Expands `publication` (shape-checked already). A document without components is returned as it is.
    init(_ publication: JSONValue) {
        guard case .object(var envelope) = publication, case .object(var document)? = envelope["document"] else {
            self.init(expanded: publication, builder: nil)
            return
        }
        var builder = Builder()
        let uses = builder.run(&document)
        envelope["document"] = .object(document)
        self.init(expanded: uses ? .object(envelope) : publication, builder: uses ? builder : nil)
    }

    private init(expanded: JSONValue, builder: Builder?) {
        self.expanded = expanded
        usesComponents = builder != nil
        issues = builder?.issues ?? []
        bodies = builder?.bodies ?? []
        argumentReferences = builder?.argumentReferences ?? []
        regions = builder?.regions ?? []
        refusedArguments = builder?.refusedArguments ?? []
    }

    // MARK: - Moving issues back

    /// `issues`, found in the expanded document, at the pointers an author can act on.
    func remapped(_ issues: [Issue]) -> [Issue] {
        guard !regions.isEmpty else { return issues }
        return issues.map(remap).filter { !($0.code != .invalidValue && refusedArguments.contains($0.pointer)) }
    }

    private func remap(_ issue: Issue) -> Issue {
        guard let region = regions.first(where: { issue.pointer == $0.pointer || issue.pointer.hasPrefix($0.pointer + "/") }) else { return issue }
        let relative = String(issue.pointer.dropFirst(region.pointer.count))
        func moved(to pointer: String) -> Issue { Issue(issue.code, pointer, capability: issue.capability) }
        if relative == "/args" || relative.hasPrefix("/args/") { return issue }
        // A limit counts the whole body in the place that uses it.
        if issue.code == .limitExceeded { return moved(to: region.pointer) }
        // The body's root decides where it may stand, so a refusal of its place belongs to the reference's `componentId`.
        let placement = relative.isEmpty || relative == "/type"
            || (issue.code == .invalidCombination && (relative == "/props/scopeProviderId" || relative == "/props/pinned"))
        if placement { return moved(to: region.pointer + "/componentId") }
        if relative == "/id" || relative == "/layout" || relative == "/layout/span" { return moved(to: region.pointer + relative) }
        if let parameter = region.bound[relative] { return moved(to: ServerUICompositionJSON.pointer(region.pointer + "/args", parameter)) }
        return moved(to: "/document/componentLibrary/\(region.entry)/node" + relative)
    }

    // MARK: - Shared walks

    /// `node` with each child (and each tab's and area's child) run through `visit`, given the child's pointer.
    static func mapChildren(_ node: JSONValue, at pointer: String, _ visit: (JSONValue, String) -> JSONValue) -> JSONValue {
        guard case .object(var object) = node else { return node }
        func list(_ value: JSONValue?, at path: String) -> JSONValue? {
            guard let items = value?.array else { return nil }
            return .array(items.enumerated().map { visit($1, "\(path)/\($0)") })
        }
        if node["type"]?.string == "local-tabs" {
            for key in ["tabs", "blocks"] {
                guard let groups = object[key]?.array else { continue }
                object[key] = .array(groups.enumerated().map { index, group in
                    guard case .object(var entry) = group,
                          let children = list(entry["children"], at: "\(pointer)/\(key)/\(index)/children") else { return group }
                    entry["children"] = children
                    return .object(entry)
                })
            }
        } else if let children = list(object["children"], at: "\(pointer)/children") {
            object["children"] = children
        }
        return .object(object)
    }

    /// The node `reference` stands for while it cannot be expanded (a missing entry, or a reference inside a body): a blank text node with
    /// the reference's id and width, so decoding goes on and the reference's own issue is the one reported.
    static func placeholder(for reference: JSONValue) -> JSONValue {
        .object([
            "id": reference["id"] ?? .string(""), "title": .string(""), "type": .string("text"),
            "layout": .object(["span": reference["layout"]?["span"] ?? .number(1)]),
            "props": .object([
                "value": .object(["type": .string("literal"), "value": .string("")]),
                "style": .string("body"), "unavailableText": .string("")
            ])
        ])
    }
}
