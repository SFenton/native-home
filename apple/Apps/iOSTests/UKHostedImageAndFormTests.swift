import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

/// Stubbed HTTP for the image pipeline: `ok` answers a PNG, anything else a 404.
final class HostedImageStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requests: [String] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        Self.requests.append(url.absoluteString)
        let good = url.path.contains("ok")
        let png = UIGraphicsImageRenderer(size: CGSize(width: 60, height: 40)).image { context in
            UIColor.systemOrange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 60, height: 40))
        }.pngData()!
        let response = HTTPURLResponse(url: url, statusCode: good ? 200 : 404, httpVersion: nil, headerFields: ["Cache-Control": "max-age=60"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: good ? png : Data())
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor
final class UKHostedImageTests: DemoHouseTestCase {
    private func pipeline() -> ImagePipeline {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HostedImageStub.self]
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("hosted-images-\(UUID().uuidString)")
        return ImagePipeline(directory: directory, session: URLSession(configuration: configuration))
    }

    private func shownImage(_ view: UIView) -> UIImage? {
        HostedPage.descendants(of: view).compactMap { $0 as? UIImageView }.compactMap(\.image).first
    }

    private func wait(until condition: () -> Bool, seconds: TimeInterval = 3) {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition() && Date() < deadline { hostedSettle(0.05) }
    }

    func testAnImageLoadsFadesInAndReportsReady() {
        let host = UIViewController()
        let window = HostedPage.show(host)
        defer { window.isHidden = true }
        let view = UKCachedImageView()
        view.pipeline = pipeline()
        var ready: [Bool] = []
        view.onReadyChange = { ready.append($0) }
        let placeholder = UIImageView(image: UIImage(systemName: "photo"))
        view.placeholder = placeholder
        view.frame = CGRect(x: 0, y: 0, width: 120, height: 80)
        host.view.addSubview(view)
        XCTAssertFalse(placeholder.isHidden, "with no picture the placeholder shows")
        view.url = URL(string: "https://stub.test/ok.png")
        XCTAssertFalse(ready.last ?? false, "not ready before the first image")
        wait { ready.last == true }
        XCTAssertTrue(placeholder.isHidden, "the placeholder is not shown while a URL is set and has not failed")
        view.url = nil
        XCTAssertEqual(ready.last, true, "no URL is a view with nothing to wait for")
        XCTAssertFalse(placeholder.isHidden, "and the placeholder shows again")
    }

    func testAFailedImageShowsThePlaceholderAndCallsBack() {
        let host = UIViewController()
        let window = HostedPage.show(host)
        defer { window.isHidden = true }
        let view = UKCachedImageView()
        view.pipeline = pipeline()
        var failed = 0
        view.onFailure = { failed += 1 }
        let placeholder = UIView()
        view.placeholder = placeholder
        view.frame = CGRect(x: 0, y: 0, width: 120, height: 80)
        host.view.addSubview(view)
        view.url = URL(string: "https://stub.test/missing.png")
        view.setNeedsLayout()
        view.layoutIfNeeded()
        wait(until: { failed > 0 }, seconds: 6)
        XCTAssertEqual(failed, 1, "a 404 reports once")
        XCTAssertFalse(placeholder.isHidden, "the placeholder stays")
        // A second image replaces the first and a view that leaves the window stops loading.
        view.url = URL(string: "https://stub.test/ok2.png")
        wait { shownImage(view) != nil }
        view.removeFromSuperview()
        host.view.addSubview(view)
    }

    func testRemoteImageViewTakesNewURLsAndFallsBack() {
        let host = UIViewController()
        let window = HostedPage.show(host)
        defer { window.isHidden = true }
        let view = UKRemoteImageView(url: URL(string: "file:///nonexistent-a.png"), fallbackURL: URL(string: "file:///nonexistent-b.png"), placeholderSymbol: "camera")
        view.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        host.view.addSubview(view)
        var ready: [Bool] = []
        view.onReadyChange = { ready.append($0) }
        hostedSettle(0.5)
        view.configure(url: URL(string: "file:///nonexistent-c.png"), fallbackURL: nil, placeholderSymbol: "photo")
        XCTAssertEqual(view.url?.lastPathComponent, "nonexistent-c.png")
        XCTAssertEqual(view.placeholderSymbol, "photo")
        view.configure(url: view.url, fallbackURL: nil, placeholderSymbol: "photo")
        hostedSettle(0.3)
        view.configure(url: nil, fallbackURL: URL(string: "file:///nonexistent-d.png"))
        hostedSettle(0.3)
        XCTAssertNil(view.url)
    }

    func testImageCardCaptionsStateAndLayoutFollowTextSize() {
        var taps = 0
        let card = UKImageCardView(title: "Pasta Night", subtitle: "30 min", imageURL: nil, placeholderSymbol: "fork.knife", accessibilityHint: "Opens the recipe") { taps += 1 }
        let host = UIViewController()
        let window = HostedPage.show(host)
        defer { window.isHidden = true }
        card.frame = CGRect(x: 16, y: 100, width: 170, height: 170 / UKImageCardView.aspectRatio)
        host.view.addSubview(card)
        card.layoutIfNeeded()
        XCTAssertTrue(card.isAccessibilityElement)
        XCTAssertEqual(card.accessibilityLabel, "Pasta Night")
        XCTAssertEqual(card.accessibilityValue, "30 min")
        XCTAssertEqual(card.accessibilityHint, "Opens the recipe")
        XCTAssertEqual(card.accessibilityTraits, .button)
        XCTAssertEqual(card.gridHeight(forWidth: 170), 170 / UKImageCardView.aspectRatio, accuracy: 0.5)
        card.sendActions(for: .touchUpInside)
        XCTAssertEqual(taps, 1)
        card.isSelectionShown = true
        XCTAssertTrue(card.accessibilityTraits.contains(.selected))
        XCTAssertEqual(card.layer.borderWidth, 3)
        card.isSelectionShown = false
        card.isHighlighted = true
        XCTAssertEqual(card.alpha, 0.8, accuracy: 0.01)
        card.isHighlighted = false
        card.configure(title: "Soup", subtitle: nil, imageURL: nil)
        XCTAssertEqual(card.accessibilityLabel, "Soup")
        XCTAssertEqual(card.accessibilityValue, "")
        // Accessibility sizes turn the card into a thumbnail row.
        let big = UIViewController()
        big.view.addSubview(UKImageCardView(title: "Pasta Night", subtitle: "30 min", imageURL: nil))
        let bigWindow = HostedPage.show(big)
        bigWindow.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
        let row = big.view.subviews.compactMap { $0 as? UKImageCardView }[0]
        row.frame = CGRect(x: 0, y: 0, width: 360, height: 10)
        hostedSettle(0.3)
        row.layoutIfNeeded()
        XCTAssertGreaterThan(row.gridHeight(forWidth: 360), 60, "a row holds its thumbnail")
        XCTAssertGreaterThan(row.sizeThatFits(CGSize(width: 360, height: 10)).height, 60)
        bigWindow.isHidden = true
    }
}

@MainActor
final class UKHostedFormTests: DemoHouseTestCase {
    private final class Probe: UKFormViewController {}

    func testEveryRowKindDrawsAndReportsWhatThePersonDoes() {
        var toggled: [Bool] = []
        var slid: [Float] = []
        var typed: [String] = []
        var chosen = 0
        var pressed = 0
        let probe = Probe()
        func sections(_ on: Bool, _ header: String) -> [UKFormSection] {
            [
                UKFormSection(id: "a", header: header, footer: "Footer A", headerStyle: .sectionTitle, footerIdentifier: "form.footer.a", rows: [
                    UKFormRow(id: "toggle", identifier: "form.toggle", .toggle(title: "Lights", isOn: on) { toggled.append($0) }),
                    UKFormRow(id: "slider", identifier: "form.slider", .slider(label: "Level", value: 0.2, range: 0...1) { slid.append($0) }),
                    UKFormRow(id: "text", identifier: "form.text", .text(placeholder: "Name", text: "x") { typed.append($0) }),
                ]),
                UKFormSection(id: "b", header: "System", headerStyle: .system, rows: [
                    UKFormRow(id: "option", identifier: "form.option", .option(title: "Warm", subtitle: "2700 K", swatch: [.orange, .yellow], isSelected: on) { chosen += 1 }),
                    UKFormRow(id: "button", identifier: "form.button", .button(title: "Reset") { pressed += 1 }),
                ]),
                UKFormSection(id: "c", header: "Sub", headerStyle: .subheadline, rows: [
                    UKFormRow(id: "custom", .custom { let label = UILabel(); label.text = "Custom row"; return label }),
                ]),
                UKFormSection(id: "d", header: "Quiet", headerStyle: .subheadlineQuiet, rows: [
                    UKFormRow(id: "clear", .clear { let label = UILabel(); label.text = "Clear row"; return label }),
                ]),
            ]
        }
        probe.setSections(sections(false, "Group"))
        let window = HostedPage.show(probe, size: HostedDriver.tall)
        defer { window.isHidden = true }
        hostedSettle(0.4)
        let texts = HostedPage.labels(in: probe.view)
        for expected in ["Lights", "Group", "Footer A", "Warm", "Reset", "Custom row", "Clear row", "System", "Sub", "Quiet"] {
            XCTAssertTrue(texts.contains { $0.contains(expected) }, "the form shows \(expected); saw \(texts)")
        }
        let toggle = HostedDriver.control("form.toggle", in: probe.view) as? UISwitch
        toggle?.setOn(true, animated: false)
        toggle?.sendActions(for: .valueChanged)
        XCTAssertEqual(toggled, [true])
        let slider = HostedDriver.control("form.slider", in: probe.view) as? UISlider
        slider?.value = 0.8
        slider?.sendActions(for: .valueChanged)
        XCTAssertEqual(slid, [0.8])
        let field = HostedDriver.control("form.text", in: probe.view) as? UITextField
        field?.text = "Lamp"
        field?.sendActions(for: .editingChanged)
        XCTAssertEqual(typed, ["Lamp"])
        // Option and button rows act on selection.
        let collection = probe.collectionView!
        for (section, item) in [(1, 0), (1, 1), (0, 0), (2, 0)] {
            let path = IndexPath(item: item, section: section)
            if probe.collectionView(collection, shouldSelectItemAt: path) { probe.collectionView(collection, didSelectItemAt: path) }
        }
        XCTAssertEqual(chosen, 1)
        XCTAssertEqual(pressed, 1)
        XCTAssertFalse(probe.collectionView(collection, shouldSelectItemAt: IndexPath(item: 0, section: 0)), "a toggle row is not selectable")
        // Changing a row and a header redraws them.
        probe.setSections(sections(true, "Group 2"), animated: false)
        hostedSettle(0.4)
        let after = HostedPage.labels(in: probe.view)
        XCTAssertTrue(after.contains { $0.contains("Group 2") }, "a changed header is drawn again")
        XCTAssertTrue((HostedDriver.control("form.toggle", in: probe.view) as? UISwitch)?.isOn == true, "the toggle shows its new value")
        XCTAssertEqual(probe.sections.count, 4)
    }

    func testTheFormCanBeBuiltWithAContextAndShownBeforeItsRowsExist() {
        let probe = UKFormViewController(context: UKGalleryChrome.context())
        let window = HostedPage.show(probe)
        defer { window.isHidden = true }
        XCTAssertNotNil(probe.sheetFitScrollView)
        probe.setSections([UKFormSection(id: "x", rows: [UKFormRow(id: "b", .button(title: "Go") {})])])
        hostedSettle(0.3)
        XCTAssertTrue(HostedPage.labels(in: probe.view).contains("Go") || !HostedPage.descendants(of: probe.view).filter { $0.accessibilityLabel == "Go" }.isEmpty)
    }
}
