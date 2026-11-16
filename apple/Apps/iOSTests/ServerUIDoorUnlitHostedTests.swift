import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

// MARK: - A door state that is not active draws the unlit face

/// The Security fixture's lock and garage tiles, state by state, at the iPhone, folded Duo and iPad widths. A state that is not `active`
/// draws the unlit face and uses its authored colour as the ink of the disc's glyph; a state that is active draws the colour as the
/// face (`.agents/design/state-styled-tile.md`: the fill is drawn only when `active`). The state words and what VoiceOver reads do not
/// depend on the colour, so this changes nothing for a person who cannot see it.
@MainActor
final class ServerUIDoorUnlitHostedTests: XCTestCase {
    /// The iPhone, the folded Duo and the iPad portrait widths (a simulator narrower than a width draws it at the simulator's own).
    private static let widths: [CGFloat] = [393, 466, 834]

    override func tearDown() async throws {
        HostedPage.hideTracked()
        HostedPage.resetGlobals()
        try await super.tearDown()
    }

    private struct Case {
        let tile: String
        let entity: String
        let state: String
        let words: String
        /// The authored colour of the state, as `0xRRGGBB`.
        let colour: UInt32
        let active: Bool
    }

    /// The fixture's authored states: locked and closed rest unlit; unlocked and open are lit red; locking is lit blue; unavailable is the grey.
    private static let cases: [Case] = [
        Case(tile: "demo-lock-control", entity: "lock.demo_unit", state: "locked", words: "Locked", colour: 0x43A047, active: false),
        Case(tile: "demo-lock-control", entity: "lock.demo_unit", state: "unlocked", words: "Unlocked", colour: 0xE53935, active: true),
        Case(tile: "demo-lock-control", entity: "lock.demo_unit", state: "locking", words: "Locking", colour: 0x1E88E5, active: true),
        Case(tile: "demo-lock-control", entity: "lock.demo_unit", state: "unavailable", words: "Unavailable", colour: 0x546E7A, active: false),
        Case(tile: "demo-garage-control", entity: "cover.demo_unit", state: "closed", words: "Closed", colour: 0x43A047, active: false),
        Case(tile: "demo-garage-control", entity: "cover.demo_unit", state: "open", words: "Open", colour: 0xE53935, active: true),
        Case(tile: "demo-garage-control", entity: "cover.demo_unit", state: "closing", words: "Closing", colour: 0x1E88E5, active: true),
        Case(tile: "demo-garage-control", entity: "cover.demo_unit", state: "unavailable", words: "Unavailable", colour: 0x546E7A, active: false),
    ]

    private func tile(_ host: UKServerUIRenderer, _ id: String) throws -> UKGlassTileView {
        let page = try ServerUIRendererFixture.root(host)
        return try XCTUnwrap(page.nodes[id]?.view as? UKGlassTileView, id)
    }

    /// Applies `state` and waits until the tile says `words`.
    private func show(_ item: Case, in host: UKServerUIRenderer, _ view: UKGlassTileView) async {
        host.pageContext.store.apply([EntityState(entityId: item.entity, state: item.state)])
        let landed = await HostedPage.settle { (view.accessibilityValue ?? "").hasPrefix(item.words) }
        XCTAssertTrue(landed, "\(item.tile) never read \(item.words) for \(item.state); read \(view.accessibilityValue ?? "nil")")
    }

    // MARK: UX

    func testAStateThatIsNotActiveDrawsTheUnlitFaceAndInksTheDiscGlyphAtEveryFamilyWidth() async throws {
        for width in Self.widths {
            let (host, window, _) = try ServerUISecurityHostedFixture.host(size: CGSize(width: width, height: 852))
            defer { window.isHidden = true }
            for item in Self.cases {
                let view = try tile(host, item.tile)
                await show(item, in: host, view)
                let model = view.model
                let name = "\(item.tile) \(item.state) at \(width)"
                XCTAssertEqual(model.isActive, item.active, name)
                if item.active {
                    XCTAssertEqual(model.fillRGB, item.colour, "\(name): a lit state draws its colour as the face")
                    XCTAssertNil(model.discGlyphTint, "\(name): and leaves the disc's own ink")
                } else {
                    XCTAssertNil(model.fillRGB, "\(name): an unlit state draws no face fill")
                    XCTAssertEqual(model.discGlyphTint, AppearanceFill(item.colour), "\(name): its colour inks the disc's glyph")
                }
            }
        }
    }

    func testALockedLockAndAClosedGarageShowTheUnlitFaceAndUnlockedAndOpenShowTheFill() async throws {
        for width in Self.widths {
            let (host, window, _) = try ServerUISecurityHostedFixture.host(size: CGSize(width: width, height: 852))
            defer { window.isHidden = true }
            let lock = try tile(host, "demo-lock-control"), garage = try tile(host, "demo-garage-control")
            for (view, rest, lit, entity) in [(lock, "locked", "unlocked", "lock.demo_unit"), (garage, "closed", "open", "cover.demo_unit")] {
                let item = Self.cases.first { $0.entity == entity && $0.state == rest }!
                await show(item, in: host, view)
                XCTAssertNil(view.model.fillRGB, "\(rest) shows the unlit face at \(width)")
                XCTAssertNotNil(view.model.discGlyphTint, "\(rest) shows a coloured glyph at \(width)")
                let moved = Self.cases.first { $0.entity == entity && $0.state == lit }!
                await show(moved, in: host, view)
                XCTAssertNotNil(view.model.fillRGB, "\(lit) shows the fill at \(width)")
                XCTAssertNil(view.model.discGlyphTint, "\(lit) leaves the disc glyph's own ink at \(width)")
            }
        }
    }

    // MARK: Accessibility

    /// The colour is never the only cue: the state words, the disc's verb and what VoiceOver reads are the same whether the face is
    /// filled or unlit, and the disc keeps its 44 pt target.
    func testTheWordsAndTheDiscKeepTheirMeaningWhateverTheFaceAtEveryFamilyWidth() async throws {
        for width in Self.widths {
            let (host, window, _) = try ServerUISecurityHostedFixture.host(size: CGSize(width: width, height: 852))
            defer { window.isHidden = true }
            for item in Self.cases {
                let view = try tile(host, item.tile)
                await show(item, in: host, view)
                HostedPage.layoutTracked()
                let name = "\(item.tile) \(item.state) at \(width)"
                XCTAssertEqual(view.accessibilityLabel, view.model.title, name)
                XCTAssertTrue((view.accessibilityValue ?? "").hasPrefix(item.words), "\(name): VoiceOver reads the state, not the colour")
                XCTAssertEqual(view.model.subtitle, item.words, name)
                XCTAssertEqual(view.model.actions.count, 1, "\(name): the disc stays")
                XCTAssertFalse(view.model.actions[0].verb.isEmpty, "\(name): and keeps its verb")
                for disc in HostedPage.descendants(of: view).compactMap({ $0 as? UKTileActionDisc }) {
                    XCTAssertGreaterThanOrEqual(disc.bounds.width, 43.5, "\(name): the disc is a 44 pt target")
                }
            }
        }
    }
}
