import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

/// Stills of the map card with its corner buttons and flips, for the evidence set. Writes `$MAPCTL_DIR/<case>-<light|dark>.png`; does nothing
/// without the directory.
@MainActor
final class UKHostedMapControlsShotsTests: DemoHouseTestCase {
    private var vacuum: VacuumConfig { Vacuums.all.first { $0.areaCleaning != nil } ?? Vacuums.all[0] }

    private func items(_ symbols: [String], prefix: String) -> [UKMapControlItem] {
        symbols.enumerated().map { index, symbol in
            UKMapControlItem(id: "\(prefix)\(index)", symbol: symbol, label: "Button \(index + 1)", hint: nil, value: nil,
                             identifier: "map.control.\(prefix)\(index)")
        }
    }

    private func card(flip: MapOrientation?, groups: [UKMapControlGroup], size: CGSize, style: UIUserInterfaceStyle) throws -> UIWindow {
        var config = vacuum
        config.mapOrientation = flip
        let loader = VacuumFixtures.loader(config, scenario: .docked)
        let state = VacuumMapState(vacuum: config, loader: loader)
        state.refresh()
        let deadline = Date().addingTimeInterval(3)
        while !state.isReady && Date() < deadline { hostedSettle(0.1) }
        let scene = try XCTUnwrap(state.scene)
        let host = UIViewController()
        host.overrideUserInterfaceStyle = style
        let card = UIView(frame: CGRect(origin: .zero, size: size))
        card.backgroundColor = UKValetudoMapView.color(ValetudoMapScene.Palette.ground)
        card.layer.cornerRadius = HassTokens.Radius.module
        card.layer.masksToBounds = true
        let map = UKValetudoMapView()
        let height = size.height - 2 * HassTokens.Spacing.m
        map.frame = CGRect(x: (size.width - height * scene.aspectRatio) / 2, y: HassTokens.Spacing.m, width: height * scene.aspectRatio, height: height)
        map.scene = scene
        card.addSubview(map)
        let controls = UKMapControlsView()
        controls.frame = card.bounds
        card.addSubview(controls)
        host.view.backgroundColor = .systemBackground
        host.view.addSubview(card)
        card.frame.origin = CGPoint(x: 16, y: 16)
        let window = HostedPage.show(host, size: HostedPage.inScene(CGSize(width: size.width + 32, height: size.height + 32)))
        controls.apply(groups)
        window.layoutIfNeeded()
        hostedSettle(0.3)
        return window
    }

    private func still(_ window: UIWindow, to url: URL) throws {
        window.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        try XCTUnwrap(image.pngData()).write(to: url)
    }

    func testWriteStills() throws {
        guard let path = ProcessInfo.processInfo.environment["MAPCTL_DIR"] else { return }
        let out = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let width = min(HostedPage.inScene(CGSize(width: 800, height: 900)).width, 800) - 32
        let size = CGSize(width: width, height: 300)
        let locate = [UKMapControlItem(id: "locate", symbol: "scope", label: "Locate", hint: nil, value: nil, identifier: "vacuum.locate")]
        let cases: [(String, MapOrientation?, [UKMapControlGroup], CGSize)] = [
            ("default", nil, [.init(corner: .topLeading, axis: .column, items: locate)], size),
            ("row-top-trailing", nil, [.init(corner: .topLeading, axis: .column, items: locate),
                                       .init(corner: .topTrailing, axis: .row, items: items(["lightbulb", "fan", "bolt"], prefix: "r"))], size),
            ("column-bottom-leading", nil, [.init(corner: .topLeading, axis: .column, items: locate),
                                            .init(corner: .bottomLeading, axis: .column, items: items(["lightbulb", "fan"], prefix: "c"))], size),
            ("flip-h", MapOrientation(flipHorizontal: true, flipVertical: false), [.init(corner: .topLeading, axis: .column, items: locate)], size),
            ("flip-v", MapOrientation(flipHorizontal: false, flipVertical: true), [.init(corner: .topLeading, axis: .column, items: locate)], size),
            ("flip-hv", MapOrientation(flipHorizontal: true, flipVertical: true), [.init(corner: .topLeading, axis: .column, items: locate)], size),
            ("more-closed", nil, [.init(corner: .topTrailing, axis: .column,
                items: items(["lightbulb", "fan", "bolt", "moon", "sun.max", "wind", "drop", "leaf"], prefix: "m"))], CGSize(width: width, height: 200)),
        ]
        for (name, flip, groups, cardSize) in cases {
            for style in [UIUserInterfaceStyle.light, .dark] {
                let window = try card(flip: flip, groups: groups, size: cardSize, style: style)
                try still(window, to: out.appendingPathComponent("\(name)-\(style == .dark ? "dark" : "light").png"))
                window.isHidden = true
            }
        }
    }
}
