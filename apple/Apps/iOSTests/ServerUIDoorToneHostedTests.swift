import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

// MARK: - A door's open face takes the tone its state map authors

/// The Right Door's "Open" face (Verifier finding `door-open`): red in the candidate, dark green in the reference, for the same entity state.
///
/// **Cause.** Not the renderer. A lowered `door-tile` draws the colour its state authored as the face while the state is `active`
/// (`ServerUIDoorLowering`, `.agents/design/state-styles.md`); the owner-draft house authors `open` as the web's danger red
/// (`ha-sfenton-react-dash@7c4ebf9:src/components/hass/SecurityDashboard.tsx:63-66`, `open` and `opening` give the `danger` tone), where the
/// shipped app draws the Doors and windows family (`4fe28061:apple/Sources/HassUI/UIKitPort/Features/Security/UKSecurityTiles.swift:85-86`,
/// "Direction G: the contact family, filled while the door is open or moving, and the red error face after a failed command") and the owner
/// decided that in `.agents/design/direction-g.md`, "Security Doors are tiles". The renderer draws what the map says, for any entity.
///
/// These tests prove that: one entity state, two authored tones, two faces, and the tone follows the map and never the entity. They run at the
/// iPhone, folded Duo and iPad widths (clamped to the scene they run in, as the other door tests do).
@MainActor
final class ServerUIDoorToneHostedTests: XCTestCase {
    private static let widths: [CGFloat] = [393, 466, 834]
    /// The Doors and windows family's fill, the web's soft green (`direction-g.md`, family table): the tone the shipped app fills an open door with.
    private static let contactFill: UInt32 = 0x3B523E
    private static let dangerRed: UInt32 = 0xE53935

    override func tearDown() async throws {
        HostedPage.hideTracked()
        HostedPage.resetGlobals()
        try await super.tearDown()
    }

    // MARK: Fixtures

    private func rgb(_ value: UInt32) -> JSONValue {
        .object(["type": .string("solid-rgb"), "red": .number(Double(value >> 16 & 0xFF)),
                 "green": .number(Double(value >> 8 & 0xFF)), "blue": .number(Double(value & 0xFF))])
    }

    /// The Security fixture with `tones` authored for the states of the door tile `id` (`state` to `0xRRGGBB`).
    private func json(authoring tones: [String: [String: UInt32]]) throws -> JSONValue {
        var root = try ServerUISecurityHostedFixture.json()
        let components = try XCTUnwrap(root["document"]?["pages"]?.array?[0]["components"]?.array)
        for (id, states) in tones {
            let tile = try XCTUnwrap(components.firstIndex { $0["id"]?.string == id }, id)
            let authored = try XCTUnwrap(components[tile]["props"]?["states"]?.array)
            for (state, colour) in states {
                let index = try XCTUnwrap(authored.firstIndex { $0["state"]?.string == state }, "\(id) \(state)")
                root = try ServerUIRendererFixture.changing(
                    root, path: "/document/pages/0/components/\(tile)/props/states/\(index)/appearance/fill", to: rgb(colour))
            }
        }
        return root
    }

    private func host(_ json: JSONValue, width: CGFloat) throws -> (UKServerUIRenderer, UIWindow) {
        let store = EntityStore()
        store.replaceAll([
            EntityState(entityId: "alarm_control_panel.demo_unit", state: "armed_home"),
            EntityState(entityId: "lock.demo_unit", state: "locked"),
            EntityState(entityId: "cover.demo_unit", state: "closed"),
        ])
        let renderer = try UKServerUIRenderer(publication: ServerUIRendererFixture.publication(json),
                                              context: UKContext(store: store, caller: HostedCaller()), backdrop: ServerUIRendererFixture.backdrop())
        let window = HostedPage.show(renderer, size: HostedPage.inScene(CGSize(width: width, height: 852)))
        HostedPage.wait(0.1)
        return (renderer, window)
    }

    private func tile(_ renderer: UKServerUIRenderer, _ id: String) throws -> UKGlassTileView {
        try XCTUnwrap(ServerUIRendererFixture.root(renderer).nodes[id]?.view as? UKGlassTileView, id)
    }

    private func show(_ state: String, entity: String, words: String, in renderer: UKServerUIRenderer, _ view: UKGlassTileView) async {
        renderer.pageContext.store.apply([EntityState(entityId: entity, state: state)])
        let landed = await HostedPage.settle { (view.accessibilityValue ?? "").hasPrefix(words) }
        XCTAssertTrue(landed, "\(entity) never read \(words); read \(view.accessibilityValue ?? "nil")")
        await HostedPage.pump(passes: 30)
    }

    /// The face's colour in the window's pixels, 55% across the tile and half way down, where no text or disc is drawn.
    private func facePixel(_ view: UKGlassTileView, in window: UIWindow) throws -> (red: Int, green: Int, blue: Int) {
        window.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let frame = window.convert(view.bounds, from: view)
        let point = CGPoint(x: frame.minX + frame.width * 0.55, y: frame.midY)
        let cg = try XCTUnwrap(image.cgImage)
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = try XCTUnwrap(CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(cg, in: CGRect(x: -point.x, y: point.y - CGFloat(cg.height), width: CGFloat(cg.width), height: CGFloat(cg.height)))
        return (Int(pixel[0]), Int(pixel[1]), Int(pixel[2]))
    }

    // MARK: UX

    /// The same entity in the same state ("open"), two authored tones: the face is red under the danger tone and dark green under the Doors and
    /// windows tone, and the model carries the authored colour in both. The reference's Right Door face measures (58, 74, 58).
    func testAnOpenDoorsFaceIsTheToneItsStateMapAuthorsAtEveryFamilyWidth() async throws {
        for width in Self.widths {
            let (red, redWindow) = try host(json(authoring: [:]), width: width)
            defer { redWindow.isHidden = true }
            let redTile = try tile(red, "demo-garage-control")
            await show("open", entity: "cover.demo_unit", words: "Open", in: red, redTile)
            XCTAssertEqual(redTile.model.fillRGB, Self.dangerRed, "the fixture's own map: danger red (\(width))")
            let danger = try facePixel(redTile, in: redWindow)
            XCTAssertGreaterThan(danger.red, 140, "red face (\(width))")
            XCTAssertLessThan(danger.green, 90)

            let (green, greenWindow) = try host(json(authoring: ["demo-garage-control": ["open": Self.contactFill]]), width: width)
            defer { greenWindow.isHidden = true }
            let greenTile = try tile(green, "demo-garage-control")
            await show("open", entity: "cover.demo_unit", words: "Open", in: green, greenTile)
            XCTAssertEqual(greenTile.model.fillRGB, Self.contactFill, "the authored Doors and windows tone (\(width))")
            XCTAssertTrue(greenTile.model.isActive, "still lit: the door is open")
            let contact = try facePixel(greenTile, in: greenWindow)
            XCTAssertGreaterThan(contact.green, contact.red + 8, "dark green face (\(width))")
            XCTAssertGreaterThan(contact.green, contact.blue + 5)
            XCTAssertLessThan(contact.red, 100, "dark, not the bright green of a disarm button")
            XCTAssertEqual(greenTile.model.subtitle, "Open", "the words are the same whatever the tone")
        }
    }

    /// The tone is the map's, never the entity's: the lock tile authored the same way draws the same face for "unlocked", and a state the
    /// map leaves red (a jammed lock, an error) stays red beside it.
    func testTheToneFollowsTheMapForAnyEntityAndAnErrorStaysRed() async throws {
        let authored = ["demo-lock-control": ["unlocked": Self.contactFill], "demo-garage-control": ["open": Self.contactFill]]
        let (renderer, window) = try host(json(authoring: authored), width: 393)
        defer { window.isHidden = true }
        let lock = try tile(renderer, "demo-lock-control"), garage = try tile(renderer, "demo-garage-control")
        await show("unlocked", entity: "lock.demo_unit", words: "Unlocked", in: renderer, lock)
        await show("open", entity: "cover.demo_unit", words: "Open", in: renderer, garage)
        XCTAssertEqual(lock.model.fillRGB, garage.model.fillRGB, "two entities, one authored tone, one face")
        let a = try facePixel(lock, in: window), b = try facePixel(garage, in: window)
        XCTAssertEqual(a.green, b.green, accuracy: 6)
        XCTAssertEqual(a.red, b.red, accuracy: 6)
        await show("jammed", entity: "lock.demo_unit", words: "Jammed", in: renderer, lock)
        XCTAssertTrue(lock.model.isError, "jammed is an error")
        XCTAssertEqual(lock.model.fillRGB, Self.dangerRed, "the map left it red, so it is red")
    }

    // MARK: Accessibility

    /// The tone is never the only cue: the state words, the disc's verb and VoiceOver's value are the same under either tone.
    func testTheWordsAndTheDiscAreTheSameUnderEitherToneAtEveryFamilyWidth() async throws {
        for width in Self.widths {
            var spoken: [String] = []
            for authored in [[String: [String: UInt32]](), ["demo-garage-control": ["open": Self.contactFill]]] {
                let (renderer, window) = try host(json(authoring: authored), width: width)
                defer { window.isHidden = true }
                let view = try tile(renderer, "demo-garage-control")
                await show("open", entity: "cover.demo_unit", words: "Open", in: renderer, view)
                spoken.append("\(view.accessibilityLabel ?? "")|\(view.accessibilityValue ?? "")|\(view.model.subtitle ?? "")|\(view.model.actions.map(\.verb))")
                XCTAssertEqual(view.model.actions.count, 1, "the disc stays (\(width))")
                for disc in HostedPage.descendants(of: view).compactMap({ $0 as? UKTileActionDisc }) {
                    XCTAssertGreaterThanOrEqual(disc.bounds.width, 43.5, "a 44 pt target")
                }
            }
            XCTAssertEqual(spoken.count, 2)
            XCTAssertEqual(spoken[0], spoken[1], "VoiceOver hears the same door (\(width))")
        }
    }
}
