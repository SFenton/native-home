import CryptoKit
import Foundation

// MARK: - Shared acceptance

/// The acceptance rules that depend only on the document, kept in `HassCore` so the app's UIKit preflight, the preview and the
/// draft compile tool (`tools/parity_loop/draft.py`) call the same functions.
///
/// What is not here needs a device or a provider: providers, records, the shell header, assets and the symbols an OS draws.
public enum ServerUIAcceptance {
    private typealias D = ServerUICompositionDocument

    /// A refusal: the diagnostic code and the JSON pointer of the first thing the document refuses.
    public struct Refusal: Error, Equatable, Sendable {
        /// `unsupported_capability`, the code `UKServerUIRendererError.Code.unsupportedPolicy` carries.
        public let code: String
        /// Where in the envelope the refusal is.
        public let pointer: String
    }

    /// The envelope's bytes could not become a `published` event (too large, not an object, or no integer revision).
    public struct EnvelopeError: Error, Equatable, Sendable {}

    /// The checks the shared rules cannot run, for the tool to report on success.
    public static let uncheckedOnDevice = ["providers", "records", "shell header", "assets", "symbols the OS lacks"]

    /// The largest envelope the preview reads.
    public static let maximumEnvelopeBytes = 2_162_688

    // MARK: Event

    /// The `published` event the integration would send for the envelope in `bytes`, judged by the same code the app uses.
    /// - Throws: ``EnvelopeError`` when the bytes are not an envelope with an integer revision.
    public static func publishedEvent(envelope bytes: Data) throws -> ServerUIPublicationEvent {
        guard bytes.count <= maximumEnvelopeBytes,
              let envelope = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              let revision = envelope["revision"] as? Int else { throw EnvelopeError() }
        let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        guard let reply = try? JSONSerialization.data(withJSONObject: [
            "state": "published", "epoch": "preview", "revision": revision, "envelopeSha256": hash, "envelope": envelope,
        ] as [String: Any]) else { throw EnvelopeError() }
        return ServerUIPublicationEvent.judge(.success(reply))
    }

    // MARK: Document

    /// The first thing the document refuses on its own, in the order the UIKit preflight reports it.
    public static func refusal(in document: ServerUICompositionDocument) -> Refusal? {
        if document.theme.appearance != .dark { return .init(code: code, pointer: "/document/theme/appearance") }
        if case .downloaded(_, _, _, let scrim, _, _) = document.theme.background, scrim != .canonical {
            return .init(code: code, pointer: "/document/theme/background/scrim")
        }
        if let found = groups(document.navigation.chrome.groups, at: "/document/navigation/chrome/groups") { return found }
        if document.navigation.tabs.count > 5 { return .init(code: code, pointer: "/document/navigation/tabs") }
        if document.navigation.initialTabId == nil, !document.navigation.tabs.isEmpty {
            return .init(code: code, pointer: "/document/navigation/initialTabId")
        }
        for (index, page) in document.pages.enumerated() {
            if let found = surface(page.surface, at: "/document/pages/\(index)") { return found }
        }
        for (index, modal) in document.modals.enumerated() {
            if let found = surface(modal.surface, at: "/document/modals/\(index)") { return found }
        }
        for (index, level) in document.levels.enumerated() {
            if let found = surface(level.surface, at: "/document/levels/\(index)") { return found }
        }
        return nil
    }

    /// Whether a chip's appearance can be read: white text keeps 4.5:1 on the fill, also under the chip's highlight, and the glyph
    /// 3:1 on the fill and on the lifted fill, for the light and the dark colour alike (`ChipTint`, `.agents/patterns/status-rail.md`).
    /// - Parameters:
    ///   - value: The fallback or state appearance.
    ///   - pointer: Where it is, without a trailing slash.
    public static func refusal(of value: ServerUICompositionDocument.StatusAppearance, at pointer: String) -> Refusal? {
        guard let fill = value.fill.appearances else { return nil }
        let white = ServerUIRGB(packed: 0xFFFFFF)
        let glyphs = value.glyph.flatMap(\.appearances) ?? (light: white, dark: white)
        for (rgb, glyph) in [(fill.light, glyphs.light), (fill.dark, glyphs.dark)] {
            let lifted = ServerUIColorText.liftedFill(rgb.packed)
            if ServerUIColorText.contrast(0xFFFFFF, lifted) < ServerUIColorText.textContrast {
                return .init(code: code, pointer: pointer + "/fill")
            }
            if min(ServerUIColorText.contrast(glyph.packed, rgb.packed), ServerUIColorText.contrast(glyph.packed, lifted))
                < ServerUIColorText.glyphContrast { return .init(code: code, pointer: pointer + "/glyph") }
        }
        return nil
    }

    /// The first unreadable appearance of a chip, its fallback then its states.
    /// - Parameter pointer: The chip's `props` pointer.
    public static func refusal(of chip: ServerUICompositionDocument.StatusChip, at pointer: String) -> Refusal? {
        if let found = refusal(of: chip.fallback, at: pointer + "/fallback") { return found }
        for (index, state) in chip.states.enumerated() {
            if let found = refusal(of: state.appearance, at: pointer + "/states/\(index)/appearance") { return found }
        }
        return nil
    }

    // MARK: Walk

    private static let code = "unsupported_capability"

    /// A side with more than one horizontal policy cannot be drawn.
    private static func groups(_ groups: [D.ChromeGroup], at pointer: String) -> Refusal? {
        for placement in [D.Placement.leading, .trailing]
        where Set(groups.filter { $0.placement == placement }.map(\.horizontal)).count > 1 {
            return .init(code: code, pointer: pointer)
        }
        return nil
    }

    private static func surface(_ surface: D.Surface, at pointer: String) -> Refusal? {
        if case .replace(let value) = surface.toolbar, let found = groups(value, at: pointer + "/toolbar/groups") { return found }
        return components(surface.components, at: pointer + "/components")
    }

    private static func components(_ components: [D.Component], at pointer: String) -> Refusal? {
        for (index, component) in components.enumerated() {
            let path = pointer + "/\(index)"
            let found: Refusal?
            switch component {
            case .statusRail(let rail): found = self.components(rail.children, at: path + "/children")
            case .statusChip(let chip): found = refusal(of: chip, at: path + "/props")
            case .roomOverviewTile(let tile): found = refusal(of: tile.chip, at: path + "/props")
            case .grid, .section, .pagedRow, .overlay: found = self.components(component.childComponents, at: path + "/children")
            case .roomSection(let section): found = self.components(section.children, at: path + "/children")
            case .localTabs(let tabs):
                found = tabs.tabs.enumerated().lazy.compactMap { self.components($0.element.children, at: path + "/tabs/\($0.offset)/children") }.first
                    ?? tabs.areas.enumerated().lazy.compactMap { self.components($0.element.children, at: path + "/blocks/\($0.offset)/children") }.first
            default: found = nil
            }
            if let found { return found }
        }
        return nil
    }
}
