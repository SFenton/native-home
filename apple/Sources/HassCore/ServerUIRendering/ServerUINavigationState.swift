import Foundation
import Observation

/// Navigation over published identifiers, independent of feature enums and presentation geometry.
///
/// The UIKit host owns animations and reports completed pops here. These operations do not interpret
/// document actions, perform service calls, or accept a publication on behalf of the renderer.
@MainActor
@Observable
public final class ServerUINavigationState {
    // MARK: - State

    /// Why a navigation intent or a reconciliation was refused. A refusal leaves the state untouched.
    public enum Failure: Error, Equatable, Sendable {
        case invalidDocument, differentDocument, unknownPage, unknownTab, unknownModal
        case unknownPresentation, invalidDepth, limitExceeded, interactionBlocked
    }

    /// The base of a stack: the initial page, or one tab.
    public enum Root: Hashable, Sendable {
        case initial
        case tab(String)
    }

    /// One modal instance and its pushed pages. Reopening a modal creates a new instance.
    public struct Presentation: Equatable, Sendable, Identifiable {
        /// The instance id; reopening a modal creates a new one.
        public let id: UUID
        /// The published modal this instance shows.
        public let modalID: String
        /// The root stack the presentation sits over.
        public let root: Root
        /// Whether it is an adaptive detail column beside the page rather than a sheet over it.
        public let isColumn: Bool
        /// Pages pushed inside the presentation.
        public fileprivate(set) var pages: [String]
        fileprivate var presenterPath: [String]
    }

    /// One observable navigation transaction. Stack arrays include their root page.
    public struct Snapshot: Equatable, Sendable {
        /// The document this navigation belongs to.
        public let documentID: String
        /// The configured tabs.
        public let tabs: [ServerUINavigationCatalog.Tab]
        /// The selected root.
        public fileprivate(set) var selection: Root
        /// Each root's pages, root page first.
        public fileprivate(set) var stacks: [Root: [String]]
        /// Open presentations, oldest first.
        public fileprivate(set) var presentations: [Presentation]
    }

    /// One non-column modal at a time: a published sheet is never stacked on another sheet.
    private static let maximumPresentations = 1

    /// The observable navigation state.
    public private(set) var snapshot: Snapshot
    @ObservationIgnored private var catalog: Catalog

    /// Takes an explicit destination catalog after the renderer's acceptance/preparation gate.
    public init(catalog destinations: ServerUINavigationCatalog) throws {
        let catalog = try Catalog(destinations)
        self.catalog = catalog
        snapshot = Snapshot(documentID: destinations.documentID, tabs: destinations.tabs,
                            selection: catalog.initialSelection, stacks: catalog.rootStacks, presentations: [])
    }

    // MARK: - Navigation intents

    /// Changes only selection. Each configured tab keeps its own path.
    public func selectTab(_ id: String) throws {
        guard catalog.tabRoots[id] != nil else { throw Failure.unknownTab }
        guard snapshot.presentations.isEmpty else { throw Failure.interactionBlocked }
        snapshot.selection = .tab(id)
    }

    /// Pushes on the visible modal's stack, or on the selected root stack when no modal is open.
    public func push(pageID: String) throws {
        guard catalog.pages.contains(pageID) else { throw Failure.unknownPage }
        if let index = snapshot.presentations.indices.last {
            guard snapshot.presentations[index].pages.count < 32 else { throw Failure.limitExceeded }
            snapshot.presentations[index].pages.append(pageID)
        } else {
            guard var path = snapshot.stacks[snapshot.selection] else { throw Failure.invalidDocument }
            guard path.count <= 32 else { throw Failure.limitExceeded }
            path.append(pageID)
            snapshot.stacks[snapshot.selection] = path
        }
    }

    /// Replaces descendants of a validated sender and reuses its nearest matching ancestor atomically.
    ///
    /// Depth counts pushed pages. The coordinator must validate sender identity and exit guards first.
    /// No intermediate trimmed-only snapshot is observable if the destination or depth is invalid.
    public func push(pageID: String, fromDepth depth: Int, onRoot: Bool = false) throws {
        guard catalog.pages.contains(pageID) else { throw Failure.unknownPage }
        guard depth >= 0 else { throw Failure.invalidDepth }
        var next = snapshot
        if !onRoot, let index = next.presentations.indices.last {
            let path = next.presentations[index].pages
            guard depth <= path.count else { throw Failure.invalidDepth }
            var destination = Array(path.prefix(depth))
            if let ancestor = destination.lastIndex(of: pageID) {
                destination = Array(destination.prefix(ancestor + 1))
            } else {
                guard destination.count < 32 else { throw Failure.limitExceeded }
                destination.append(pageID)
            }
            next.presentations[index].pages = destination
        } else {
            guard let path = next.stacks[next.selection], depth < path.count else { throw Failure.invalidDepth }
            var destination = Array(path.prefix(depth + 1))
            if let ancestor = destination.lastIndex(of: pageID) {
                destination = Array(destination.prefix(ancestor + 1))
            } else {
                guard destination.count <= 32 else { throw Failure.limitExceeded }
                destination.append(pageID)
            }
            next.stacks[next.selection] = destination
            Self.rebaseColumn(in: &next)
        }
        if next != snapshot { snapshot = next }
    }

    /// Reports a completed back operation. Depth counts pushed pages, not the page or modal root.
    ///
    /// An interactive transition that cancels must not call this method.
    public func trimVisiblePath(toDepth depth: Int, onRoot: Bool = false) throws {
        guard depth >= 0 else { throw Failure.invalidDepth }
        if !onRoot, let index = snapshot.presentations.indices.last {
            guard depth <= snapshot.presentations[index].pages.count else { throw Failure.invalidDepth }
            snapshot.presentations[index].pages = Array(snapshot.presentations[index].pages.prefix(depth))
        } else {
            guard let path = snapshot.stacks[snapshot.selection], depth < path.count else { throw Failure.invalidDepth }
            var next = snapshot
            next.stacks[next.selection] = Array(path.prefix(depth + 1))
            Self.rebaseColumn(in: &next)
            snapshot = next
        }
    }

    /// A column presentation sits beside the selected root stack, so a root push or trim moves its presenter.
    /// Rebasing keeps `apply(catalog:)` from dropping the column because its remembered presenter path went stale.
    private static func rebaseColumn(in snapshot: inout Snapshot) {
        guard let first = snapshot.presentations.first, first.isColumn, first.root == snapshot.selection,
              let path = snapshot.stacks[snapshot.selection] else { return }
        snapshot.presentations[0].presenterPath = path
    }

    /// Opens an instance of a configured modal. No modal identity is compiled into the navigator.
    @discardableResult
    public func present(modalID: String, asColumn: Bool = false) throws -> UUID {
        guard catalog.modals.contains(modalID) else { throw Failure.unknownModal }
        guard asColumn ? snapshot.presentations.isEmpty :
            snapshot.presentations.filter({ !$0.isColumn }).count < Self.maximumPresentations else { throw Failure.interactionBlocked }
        let root = snapshot.presentations.last?.root ?? snapshot.selection
        guard let rootPath = snapshot.stacks[root] else { throw Failure.invalidDocument }
        let presenterPath = snapshot.presentations.last?.pages ?? rootPath
        let presentation = Presentation(id: UUID(), modalID: modalID, root: root, isColumn: asColumn, pages: [], presenterPath: presenterPath)
        snapshot.presentations.append(presentation)
        return presentation.id
    }

    /// Dismisses this presentation and anything presented above it, without changing its parent path.
    public func dismiss(presentationID: UUID) throws {
        guard let index = snapshot.presentations.firstIndex(where: { $0.id == presentationID }) else {
            throw Failure.unknownPresentation
        }
        snapshot.presentations.removeSubrange(index...)
    }

    // MARK: - Publication reconciliation

    /// Keeps paths and presentation identities when their configured destinations still exist.
    ///
    /// A removed page truncates the path at that page; it never skips over a missing ancestor.
    /// A changed tab root resets only that tab. Account/document changes require a fresh navigator.
    /// Reconciles only after preparation and guards have approved the candidate publication.
    public func apply(catalog destinations: ServerUINavigationCatalog) throws {
        guard destinations.documentID == snapshot.documentID else { throw Failure.differentDocument }
        let next = try Catalog(destinations)
        guard snapshot.presentations.filter({ !$0.isColumn }).count <= Self.maximumPresentations else { throw Failure.interactionBlocked }
        var stacks = next.rootStacks
        for (root, fresh) in stacks {
            if let previous = snapshot.stacks[root], previous.first == fresh.first {
                stacks[root] = Array(previous.prefix(while: { next.pages.contains($0) }))
            }
        }
        var presentations: [Presentation] = []
        for var presentation in snapshot.presentations {
            guard next.modals.contains(presentation.modalID),
                  let parentPath = presentations.last?.pages ?? stacks[presentation.root],
                  parentPath.starts(with: presentation.presenterPath) else { break }
            presentation.pages = Array(presentation.pages.prefix(while: { next.pages.contains($0) }))
            presentations.append(presentation)
        }
        let selection = stacks[snapshot.selection] == nil ? next.initialSelection : snapshot.selection
        let updated = Snapshot(documentID: destinations.documentID, tabs: destinations.tabs,
                               selection: selection, stacks: stacks, presentations: presentations)
        catalog = next
        if updated != snapshot { snapshot = updated }
    }

    // MARK: - Destination catalog

    private struct Catalog {
        let pages: Set<String>
        let modals: Set<String>
        let tabRoots: [String: String]
        let initialSelection: Root
        let rootStacks: [Root: [String]]

        init(_ document: ServerUINavigationCatalog) throws {
            let pages = Set(document.pageIDs)
            let modals = Set(document.modalIDs)
            let tabs = document.tabs
            guard pages.count == document.pageIDs.count,
                  modals.count == document.modalIDs.count, pages.isDisjoint(with: modals),
                  Set(tabs.map(\.id)).count == tabs.count,
                  pages.contains(document.initialPageID),
                  tabs.allSatisfy({ pages.contains($0.pageId) }),
                  document.initialTabID.map({ id in tabs.contains { $0.id == id && $0.pageId == document.initialPageID } }) ?? true else {
                throw Failure.invalidDocument
            }
            self.pages = pages
            self.modals = modals
            tabRoots = Dictionary(tabs.map { ($0.id, $0.pageId) }, uniquingKeysWith: { first, _ in first })
            initialSelection = document.initialTabID.map(Root.tab) ?? .initial
            var stacks: [Root: [String]] = [.initial: [document.initialPageID]]
            for tab in tabs { stacks[.tab(tab.id)] = [tab.pageId] }
            rootStacks = stacks
        }
    }
}
