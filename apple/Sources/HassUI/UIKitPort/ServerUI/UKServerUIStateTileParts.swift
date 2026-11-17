#if os(iOS)
import HassCore
import HassDesign
import UIKit

// MARK: - A state tile's own parts and look

/// Draws what the document adds to a `state-tile`: a subtitle, a progress fill, up to two round buttons and a destination
/// (`sh.tile-parts@1`), and the faces its conditions decide (`sh.tile-look@1`).
///
/// The parts ride on the tile the state style already drew: the style still owns the glyph, the words and the class, and the parts
/// replace only the line under the title, add a fill from the leading edge and add discs after the style's own. A tile that has a
/// destination shows the chevron, and a tap on its body opens it (HIG, Buttons: every disc is at least 44 by 44 pt, named for VoiceOver
/// by its label and never drawn as text).
@MainActor
enum UKServerUIStateTileParts {
    typealias D = ServerUICompositionDocument

    /// The item id of an authored disc, kept apart from the style's own action ids.
    static func itemID(_ disc: ServerUITileParts.Disc) -> String { "disc:" + disc.id }

    /// Applies the tile's parts and faces to `model`.
    /// - Parameters:
    ///   - tile: The authored tile.
    ///   - model: The model the state style produced.
    ///   - reader: What the tile's expressions read.
    ///   - subtitle: The subtitle's text once resolved, or `nil` to keep the style's words.
    ///   - unknown: Whether the entity cannot be read now (hidden, loading or unavailable): the faces and discs then stand down.
    ///   - busy: Whether a call from this tile is in flight.
    ///   - read: Reads a typed value for a disc's label that is a text slot.
    ///   - memory: What the tile's discs last showed: for `whenUnknown: keep`, and the symbol and words of a rule that is still loading.
    static func apply(_ tile: D.StateTile, to model: inout UKGlassTileModel, reader: some ServerUIReading, subtitle: String?, unknown: Bool,
                      busy: Bool, read: (D.Read) -> ServerUIReadResult = { _ in .unavailable }, memory: inout UKServerUILayoutMemory) {
        if let subtitle {
            model.subtitle = subtitle.isEmpty ? nil : subtitle
            model.stateCandidates.append(subtitle)
        }
        if tile.parts.progress != nil { model.progress = ServerUILayoutRules.progress(tile.parts.progress, in: reader) }
        var shown: [String: Bool] = [:]
        let discs = tile.parts.discs.filter { disc in
            let visible = disc.visibility?.isShown(reader, previous: memory.discs[disc.id]) ?? true
            shown[disc.id] = visible
            return visible
        }
        // A disc's `enabledWhen` (`sh.enabled-when@1`) dims it and stops its tap; `keep` repeats the answer remembered here.
        var allowed: [String: Bool] = [:]
        for disc in discs {
            let key = "enabled:" + disc.id
            let answer = ServerUIEnabledRule.allows(disc.enabledWhen, previous: memory.discs[key], in: reader)
            allowed[disc.id] = answer
            shown[key] = answer
        }
        memory.discs = shown
        model.actions += discs.map { disc in
            // A rule that is still loading keeps what the disc last showed; one that cannot answer shows its `otherwise` (the authored words).
            let symbol = disc.resolvedIcon(in: reader, keeping: memory.discSymbols[disc.id])
            let words = disc.resolvedLabel(read: read, in: reader, keeping: memory.discLabels[disc.id])
            memory.discSymbols[disc.id] = symbol
            memory.discLabels[disc.id] = words
            return TileActionItem(id: itemID(disc), verb: words, symbol: ServerUISymbolFallback.resolve(symbol.name),
                                  phase: unknown || allowed[disc.id] == false ? .unavailable : busy ? .inFlight : .ready, feedback: .momentary,
                                  // The tile's own title follows the words ("Start Main Floor"); otherwise the words are the whole label.
                                  label: disc.namesTile ? nil : words)
        }
        if tile.action != nil {
            model.behavior = .navigate
            model.kind = .navigate
        }
        guard !tile.look.isEmpty, !unknown else { return }
        let faces = ServerUILayoutRules.faces(tile.look, in: reader)
        if let active = faces.active {
            model.isActive = active
            model.look?.colour.isActive = active
        }
        // The dense filled face is the family's own fill (the lit face), as the Studio draws `filledWhen`.
        if faces.filled == true, !model.isError {
            model.family = .lights
            model.isActive = true
        }
        // A fault the conditions found makes the class an error, whatever the style says; a request in flight stays in progress.
        if faces.error == true, !busy {
            model.isError = true
            model.look?.stateClass = .error
            model.look?.colour.stateClass = .error
        }
    }
}
#endif
