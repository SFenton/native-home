import Foundation

// MARK: - Lowering `vacuum-control` onto generic parts

/// Rewrites the `vacuum-control` kinds the generic parts can draw into those parts, once, as the document is compiled.
///
/// The node type and its capabilities stay decodable and the capability closure is unchanged: the compiler has already checked the
/// document as the Studio wrote it. This pass runs after that check, so the renderer never meets a lowered kind and carries no
/// Swift for it. What a kind lowers to is what the configurator can author with the same parts:
///
/// | Kind | Lowers to |
/// |---|---|
/// | `card` | `state-tile` over a `robot` style that carries the robot's purple (`sh.state-style-fills@1`), with tile parts (subtitle, progress, two discs whose glyph and label follow the state and name the tile, the sheet as its action) and tile look; the grid around it keeps two columns (`sh.grid-min-columns@1`) |
/// | `choice` (`autoClean`) | `bound-control` toggle on a tile |
/// | `auto-clean` | `bound-control` toggle on a row, with its glyph, its Enabled or Paused subtitle, hint and failure caption (`sh.bound-row-parts@1`) |
///
/// **Stays native** (it needs the controller, the map, or the glass tile and sheet atoms the generic parts do not yet draw): `status`,
/// `consumable`, every `command`, `map`, `area-editor`, `outcomes`, `notices`, `report`, `target`, `clear-area`, `settings` and the
/// `rooms` choice.
///
/// The entities a lowered node reads become `ha-entity` sources named `lowered.<entity id>`, added once to the document.
enum ServerUIVacuumLowering {
    typealias D = ServerUICompositionDocument

    /// The document with every lowerable `vacuum-control` replaced by generic parts; a document without a vacuum source is returned as is.
    static func lower(_ document: D) -> D {
        var descriptors: [String: ServerUIVacuumDescriptor] = [:]
        for case .vacuum(let id, let descriptor) in document.dataSources { descriptors[id] = descriptor }
        guard !descriptors.isEmpty else { return document }
        let context = Context(existing: Set(document.dataSources.map(\.id)))
        func lowered(_ surface: D.Surface) -> D.Surface {
            var surface = surface
            surface.components = surface.components.map { component in
                component.mapped { value in
                    if case .grid(var grid) = value, grid.holdsRobotTiles, grid.maxColumns >= Reads.robotsAcross {
                        grid.minimumColumns = Reads.robotsAcross
                        return .grid(grid)
                    }
                    guard case .vacuum(let control) = value, let descriptor = descriptors[control.sourceId],
                          let replacement = lower(control, descriptor: descriptor, context: context) else { return value }
                    return replacement
                }
            }
            return surface
        }
        var result = document
        result.pages = document.pages.map { var page = $0; page.surface = lowered(page.surface); return page }
        result.modals = document.modals.map { var modal = $0; modal.surface = lowered(modal.surface); return modal }
        result.levels = document.levels.map { var level = $0; level.surface = lowered(level.surface); return level }
        result.dataSources += context.added
        if !context.styles.isEmpty {
            result.stateStyles = ServerUIStateStyleLibrary(entries: (document.stateStyles?.entries ?? []) + context.styles)
        }
        return result
    }

    /// The generic parts for one control, or `nil` for a kind that stays native.
    static func lower(_ control: D.VacuumControl, descriptor: ServerUIVacuumDescriptor, context: Context) -> D.Component? {
        let reads = Reads(descriptor: descriptor, context: context)
        let node = control.node
        switch control.primitive {
        case .card(let icon, let commands, let destination):
            return .stateTile(reads.card(node: node, icon: icon, commands: commands, destination: destination))
        case .choice(let entityId, .autoClean):
            return .boundControl(reads.autoCleanRoom(node: node, entityId: entityId))
        case .autoClean:
            guard let control = descriptor.autoCleanControl else { return nil }
            return .boundControl(reads.autoCleanSwitch(node: node, control: control))
        default:
            return nil
        }
    }

    // MARK: - Sources the lowered nodes read

    /// The `ha-entity` sources a pass adds, in the order they were first needed.
    final class Context {
        private(set) var added: [D.Source] = []
        /// The saved styles the lowered tiles name, added to the document's library once.
        private(set) var styles: [ServerUIStateStyleLibrary.Entry] = []
        private var known: Set<String>

        init(existing: Set<String>) { known = existing }

        /// Adds `entry` to the library the first time its style is asked for.
        func use(_ entry: ServerUIStateStyleLibrary.Entry) {
            if !styles.contains(where: { $0.style.id == entry.style.id }) { styles.append(entry) }
        }

        /// The source id for `entityId`, adding the source the first time.
        func source(for entityId: String) -> String {
            let id = "lowered." + entityId
            if known.insert(id).inserted { added.append(.haEntity(id: id, entityId: .literal(entityId))) }
            return id
        }
    }
}

extension ServerUICompositionDocument.Grid {
    /// Whether a robot tile the lowering made sits directly in this grid.
    fileprivate var holdsRobotTiles: Bool {
        children.contains { if case .stateTile(let tile) = $0 { tile.binding.styleId == ServerUIVacuumLowering.Reads.robotStyleId } else { false } }
    }
}
