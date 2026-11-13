import HassCore
import UIKit
import XCTest
@testable import HassUI

/// The Home weather card on a first sign-in (no house document yet) and on a server that rejects the forecast call
/// (`.agents/patterns/state-message.md`): it waits with placeholders, starts its fetch when the document arrives with the
/// document's weather entity, and never draws or exposes Home Assistant's own error text.
@MainActor
final class UKHostedWeatherForecastEntityTests: DemoHouseTestCase {
    /// Records the `entity_id` of each forecast call and answers with the fixture forecasts, or fails with a server schema message.
    @MainActor private final class Recorder: WeatherForecastCalling {
        struct Schema: LocalizedError { var errorDescription: String? { "expected 'all' or 'none' at 'entity_id'" } }
        var entityIds: [String] = []
        let fails: Bool
        init(fails: Bool = false) { self.fails = fails }

        func callServiceForResponse(_ domain: String, _ service: String, data: [String: any Sendable]) async throws -> JSONValue {
            entityIds.append(data["entity_id"] as? String ?? "<missing>")
            if fails { throw Schema() }
            let kind = WeatherForecastKind(rawValue: data["type"] as? String ?? "") ?? .daily
            return WeatherFixtures.response(kind == .daily ? WeatherFixtures.daily() : WeatherFixtures.hourly())
        }
    }

    private func card(_ recorder: Recorder, category: UIContentSizeCategory = .large, width: CGFloat = 390, hasDocument: Bool = true) -> (UKWeatherCardView, UIWindow) {
        // The entity store is filled while the demo document is installed, so it holds the demo weather entity either way.
        let context = UKGalleryChrome.context(store: HomeFixtures.store(environment: [:]))
        // A first sign-in: the card is built and shown before the document exists.
        if !hasDocument { GalleryHouse.uninstall() }
        let view = UKWeatherCardView(context: context, store: nil, caller: recorder, isNarrow: false, startsOpen: false, present: { _ in })
        let host = UIViewController()
        host.view.addSubview(view)
        host.traitOverrides.preferredContentSizeCategory = category
        let size = CGSize(width: width, height: 900)
        let window = HostedPage.show(host, size: size)
        view.frame = CGRect(origin: .zero, size: view.sizeThatFits(CGSize(width: width, height: 0)))
        host.view.layoutIfNeeded()
        return (view, window)
    }

    /// What the card tells assistive technology: each element's label, else its text.
    private func spoken(_ view: UIView) -> [String] {
        view.layoutIfNeeded()
        return (view.accessibilityElements ?? []).compactMap { element in
            let object = element as AnyObject
            if let label = object.accessibilityLabel ?? nil, !label.isEmpty { return label }
            return (element as? UILabel)?.text
        }
    }

    private func assertNoServerText(_ view: UIView, _ note: String, file: StaticString = #filePath, line: UInt = #line) {
        let all = spoken(view) + HostedPage.descendants(of: view).compactMap { ($0 as? UILabel)?.text }
        XCTAssertFalse(all.contains { $0.contains("entity_id") || $0.contains("expected 'all'") }, "\(note): no raw server text in \(all)", file: file, line: line)
    }

    // MARK: - No document yet

    func testWithNoDocumentTheCardShowsPlaceholdersAndSendsNothingThenFetchesWithTheDocumentsEntity() {
        let recorder = Recorder()
        let (view, window) = card(recorder, hasDocument: false)
        defer { window.isHidden = true }
        HostedPage.wait(0.6)
        XCTAssertTrue(recorder.entityIds.isEmpty, "no call while the id is empty, got \(recorder.entityIds)")
        XCTAssertTrue(spoken(view).contains("Loading 24-hour weather forecast"), "placeholders: \(spoken(view))")
        assertNoServerText(view, "pending")

        GalleryHouse.install()
        XCTAssertTrue(HostedPage.until(8) { !recorder.entityIds.isEmpty }, "the document arriving starts the fetch")
        XCTAssertEqual(Set(recorder.entityIds), [WeatherEntities.weather])
        XCTAssertFalse(recorder.entityIds.contains(""), "never an empty entity id")
        XCTAssertTrue(HostedPage.until(8) { !spoken(view).contains("Loading 24-hour weather forecast") }, "the forecast replaces the placeholders")
    }

    // MARK: - A rejected call

    func testARejectedCallShowsTheDeckLineAndExposesNoServerText() {
        for category in [UIContentSizeCategory.large, .accessibilityExtraExtraExtraLarge] {
            let recorder = Recorder(fails: true)
            let (view, window) = card(recorder, category: category, width: 320)
            defer { window.isHidden = true }
            XCTAssertTrue(HostedPage.until(8) { spoken(view).contains(WeatherCopy.forecastFailure(.hourly)) }, "\(category.rawValue): the deck line is the element: \(spoken(view))")
            assertNoServerText(view, category.rawValue)
            let label = HostedPage.descendants(of: view).compactMap { $0 as? UILabel }.first { $0.accessibilityIdentifier == "home.weather.hourlyMessage" }
            XCTAssertEqual(label?.text, WeatherCopy.forecastFailure(.hourly))
            XCTAssertEqual(label?.numberOfLines, 0, "the line wraps rather than truncating")
            if let label {
                view.frame.size = view.sizeThatFits(CGSize(width: 320, height: 0))
                view.layoutIfNeeded()
                XCTAssertTrue(view.bounds.insetBy(dx: -0.5, dy: -0.5).contains(label.frame), "\(category.rawValue): the line sits inside the card")
            }
            let button = HostedPage.descendants(of: view).first { $0.accessibilityIdentifier == "home.weather.card" }
            XCTAssertGreaterThanOrEqual(button?.bounds.height ?? 0, 44, "\(category.rawValue): the card button is a 44 pt target")
            XCTAssertEqual(button?.accessibilityTraits.contains(.button), true)
        }
    }
}
