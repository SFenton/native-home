import HassCore
import UIKit
import XCTest
@testable import HassUI

/// The sign-in Server row (owner, 2026-11-06; `.agents/design/house-config-states.md`): its field settings and identifiers, the
/// label above the field at AX5, each error look, the read-only welcome back, and the accessibility rules (labels, reading
/// order, 52 pt rows, 44 pt links, nothing clipped). Every wait is bounded by `hostedSettle`.
@MainActor
final class UKHostedLoginServerTests: XCTestCase {
    private func show(stub: String = "success", mode: LoginModel.Mode = .fresh, server: String? = nil, size: CGSize = CGSize(width: 393, height: 852),
                      category: UIContentSizeCategory? = nil) -> (UKLoginViewController, LoginModel, UIWindow) {
        let defaults = UserDefaults(suiteName: "hosted.login.server.\(UUID().uuidString)")!
        let store = RememberedAccountStore(defaults: defaults)
        if let server, case let .success(parsed) = HassServerAddress.parse(server) { store.remember(server: parsed) }
        let model = LoginModel(mode: mode, store: store, defaultServer: nil, makeFlow: { server in
            HassLoginFlow(server: server, session: DebugSignInStub.session(["FENTON_SIGNIN_STUB": stub]) ?? .shared)
        })
        let page = UKLoginViewController(model: model, playsIntro: false, environment: nil, onIntroPlayed: {}, onUseDifferentAccount: {}, onSignedIn: { _, _ in })
        let window = HostedPage.show(page, size: size)
        if let category { window.traitOverrides.preferredContentSizeCategory = category }
        hostedSettle(0.5)
        return (page, model, window)
    }

    private func view(_ id: String, in page: UIViewController) -> UIView? {
        HostedPage.descendants(of: page.view).first { $0.accessibilityIdentifier == id }
    }

    private func module(in page: UIViewController) -> UKLoginFieldsModule? {
        HostedPage.descendants(of: page.view).compactMap { $0 as? UKLoginFieldsModule }.first
    }

    private func type(_ text: String, into id: String, in page: UIViewController) {
        let field = view(id, in: page) as? UITextField
        field?.text = text
        field?.sendActions(for: .editingChanged)
    }

    private func submit(_ page: UIViewController) {
        (view("login.submit", in: page) as? UIControl)?.sendActions(for: .touchUpInside)
    }

    // MARK: Row

    func testTheServerRowIsTheFirstRowWithTheKeyboardSettingsAndPlaceholder() throws {
        let (page, _, window) = show()
        defer { window.isHidden = true }
        let server = try XCTUnwrap(view("login.server", in: page) as? UITextField)
        XCTAssertEqual(server.keyboardType, .URL)
        XCTAssertEqual(server.textContentType, .URL)
        XCTAssertEqual(server.autocapitalizationType, .none)
        XCTAssertEqual(server.autocorrectionType, .no)
        XCTAssertEqual(server.spellCheckingType, .no)
        XCTAssertEqual(server.smartDashesType, .no)
        XCTAssertEqual(server.smartQuotesType, .no)
        XCTAssertEqual(server.returnKeyType, .next)
        XCTAssertEqual(server.clearButtonMode, .whileEditing)
        XCTAssertEqual(server.attributedPlaceholder?.string, "homeassistant.local:8123")
        XCTAssertEqual(server.accessibilityLabel, "Server address")
        let ids = HostedDriver.identifiers(in: page.view)
        XCTAssertTrue(ids.contains("login.server"))
        // Both Server rows are always in the module and `configure(mode:)` hides one (`UKLoginFieldsModule`), so "the editable row"
        // is a visibility check, as the welcome back test below reads it.
        XCTAssertEqual(view("login.server.readonly", in: page)?.isHidden, true, "a fresh sign-in has the editable row, not the read-only one")
        XCTAssertFalse(HostedPage.descendants(of: page.view).contains { $0.isHidden && server.isDescendant(of: $0) }, "and the editable row is shown")
        let username = try XCTUnwrap(view("login.username", in: page))
        XCTAssertLessThan(server.convert(server.bounds, to: page.view).minY, username.convert(username.bounds, to: page.view).minY)
        XCTAssertTrue(HostedPage.labels(in: page.view).contains("Server"), "the visible label")
    }

    func testTheServerLabelSitsBesideTheFieldAtTheDefaultSizeAndAboveItAtAX5() throws {
        let (page, _, window) = show()
        let row = try XCTUnwrap(HostedPage.descendants(of: page.view).compactMap { $0 as? UKLoginRowView }.first { $0.field === view("login.server", in: page) })
        let label = row.label
        let beside = label.convert(label.bounds, to: row)
        XCTAssertEqual(beside.midY, row.bounds.midY, accuracy: 2, "beside the field at the default size")
        window.isHidden = true

        let (big, _, bigWindow) = show(category: .accessibilityExtraExtraExtraLarge)
        defer { bigWindow.isHidden = true }
        let bigRow = try XCTUnwrap(HostedPage.descendants(of: big.view).compactMap { $0 as? UKLoginRowView }.first { $0.field === view("login.server", in: big) })
        let above = bigRow.label.convert(bigRow.label.bounds, to: bigRow)
        XCTAssertLessThan(above.midY, bigRow.bounds.midY, "above the field at AX5")
        XCTAssertGreaterThanOrEqual(above.minX, 0)
        XCTAssertLessThanOrEqual(above.maxX, bigRow.bounds.maxX + 0.5, "no clipping at AX5")
        XCTAssertLessThanOrEqual(above.maxY, bigRow.bounds.maxY + 0.5)
    }

    // MARK: Error looks

    func testABadAddressShowsTheLineAndTheServerHairlineAndMakesNoRequest() throws {
        let (page, model, window) = show()
        defer { window.isHidden = true }
        type("ha example", into: "login.server", in: page)
        type("alex", into: "login.username", in: page)
        type("secret", into: "login.password", in: page)
        submit(page)
        hostedSettle(0.6)
        XCTAssertEqual(model.failure, .badAddress)
        XCTAssertFalse(model.isWorking, "nothing was sent")
        XCTAssertTrue(HostedDriver.identifiers(in: page.view).contains("login.error"))
        XCTAssertTrue(HostedPage.labels(in: page.view).contains(LoginCopy.badAddress))
        XCTAssertEqual(module(in: page)?.showsServerOutline, true, "the hairline goes round the Server row")
        XCTAssertEqual(module(in: page)?.showsPasswordOutline, false)
        XCTAssertFalse(HostedDriver.identifiers(in: page.view).contains("login.error.card"))
    }

    func testFocusLandsInTheServerFieldAfterAnAddressError() throws {
        let (page, model, window) = show()
        defer { window.isHidden = true }
        let server = try XCTUnwrap(view("login.server", in: page) as? UITextField)
        type("alex", into: "login.username", in: page)
        type("secret", into: "login.password", in: page)
        (view("login.password", in: page) as? UITextField)?.becomeFirstResponder()
        type("ha example", into: "login.server", in: page)
        submit(page)
        hostedSettle(0.8)
        XCTAssertEqual(model.failure, .badAddress)
        XCTAssertTrue(server.isFirstResponder, "focus moves to the Server field")
    }

    func testEndingEditingNormalisesTheAddressInPlace() throws {
        let (page, model, window) = show()
        defer { window.isHidden = true }
        let server = try XCTUnwrap(view("login.server", in: page) as? UITextField)
        type("Homeassistant.local:8123/x", into: "login.server", in: page)
        page.textFieldDidEndEditing(server)
        hostedSettle(0.4)
        XCTAssertEqual(server.text, "http://homeassistant.local:8123")
        XCTAssertEqual(model.serverText, "http://homeassistant.local:8123")
        XCTAssertNil(model.failure)
    }

    func testAnAnswerThatIsNotHomeAssistantShowsTheLineAndTheServerHairline() {
        let (page, model, window) = show(stub: "nothomeassistant")
        defer { window.isHidden = true }
        type("ha.example.com", into: "login.server", in: page)
        type("alex", into: "login.username", in: page)
        type("secret", into: "login.password", in: page)
        submit(page)
        hostedSettle(1.5)
        XCTAssertEqual(model.failure, .notHomeAssistant)
        XCTAssertTrue(HostedPage.labels(in: page.view).contains(LoginCopy.notHomeAssistant))
        XCTAssertEqual(module(in: page)?.showsServerOutline, true)
        XCTAssertFalse(HostedDriver.identifiers(in: page.view).contains("login.error.card"))
    }

    func testUnreachableKeepsTheCardAndNoServerHairline() {
        let (page, _, window) = show(stub: "unreachable")
        defer { window.isHidden = true }
        type("ha.example.com", into: "login.server", in: page)
        type("alex", into: "login.username", in: page)
        type("secret", into: "login.password", in: page)
        submit(page)
        hostedSettle(1.5)
        XCTAssertTrue(HostedDriver.identifiers(in: page.view).contains("login.error.card"))
        // The card's title is drawn after a warning symbol (an attributed string), so its text ends with the words and its
        // accessibility label is the words alone (`UKLoginFailureCardView`).
        let title = HostedPage.descendants(of: page.view).compactMap { $0 as? UILabel }.first { $0.accessibilityLabel == LoginCopy.unreachableTitle }
        XCTAssertEqual(LoginCopy.unreachableTitle, "Can't reach Home Assistant")
        XCTAssertEqual(title?.text?.hasSuffix(LoginCopy.unreachableTitle), true, "the card is titled \(LoginCopy.unreachableTitle); saw \(HostedPage.labels(in: page.view))")
        XCTAssertEqual(module(in: page)?.showsServerOutline, false, "the address may be right")
    }

    // MARK: Welcome back

    func testWelcomeBackShowsTheServerAndUsernameReadOnlyAsOneElementEach() throws {
        let (page, _, window) = show(mode: .welcomeBack(RememberedAccount(username: "alex", name: "Alex")), server: "https://ha.example.com:8443")
        defer { window.isHidden = true }
        let ids = HostedDriver.identifiers(in: page.view)
        XCTAssertTrue(ids.contains("login.server.readonly") && ids.contains("login.username.readonly"))
        let serverRow = try XCTUnwrap(view("login.server.readonly", in: page))
        XCTAssertTrue(serverRow.isAccessibilityElement)
        XCTAssertEqual(serverRow.accessibilityLabel, "Server, ha.example.com:8443")
        XCTAssertEqual(view("login.username.readonly", in: page)?.accessibilityLabel, "Username, alex")
        XCTAssertFalse(serverRow.isHidden)
        let editable = try XCTUnwrap(view("login.server", in: page))
        XCTAssertTrue(editable.isHidden || editable.superview?.isHidden == true, "the editable row is out of the way")
        let label = HostedPage.descendants(of: serverRow).compactMap { $0 as? UILabel }.last
        XCTAssertEqual(label?.lineBreakMode, .byTruncatingMiddle, "a long address truncates in the middle")
    }

    // MARK: Accessibility

    func testReadingOrderIsServerUsernamePasswordSignIn() throws {
        let (page, _, window) = show()
        defer { window.isHidden = true }
        let order = ["login.server", "login.username", "login.password", "login.submit"]
        let frames = try order.map { id -> CGFloat in
            let target = try XCTUnwrap(view(id, in: page), id)
            return target.convert(target.bounds, to: page.view).minY
        }
        XCTAssertEqual(frames, frames.sorted(), "top to bottom is the reading order: \(order)")
        let ids = HostedDriver.identifiers(in: page.view).filter { order.contains($0) }
        XCTAssertEqual(ids, order, "and the view order agrees")
    }

    func testRowsAreAtLeast52PointsAndLinksAtLeast44() throws {
        let (page, _, window) = show(mode: .welcomeBack(RememberedAccount(username: "alex")), server: "https://ha.example.com")
        for id in ["login.server.readonly", "login.username.readonly", "login.password"] {
            let row = try XCTUnwrap(view(id, in: page), id)
            let rowView = (HostedPage.descendants(of: page.view).compactMap { $0 as? UKLoginRowView }.first { $0 === row || $0.field === row }) ?? row
            XCTAssertGreaterThanOrEqual(rowView.bounds.height, 51.5, "\(id) is a 52 pt row")
        }
        XCTAssertGreaterThanOrEqual(view("login.differentAccount", in: page)?.bounds.height ?? 0, 44)
        window.isHidden = true

        let (fresh, _, freshWindow) = show()
        defer { freshWindow.isHidden = true }
        XCTAssertGreaterThanOrEqual(view("login.server", in: fresh)?.bounds.height ?? 0, 51.5)
        XCTAssertGreaterThanOrEqual(view("login.submit", in: fresh)?.bounds.height ?? 0, 44)
    }

    func testNothingClipsAtAX5OnAnyFamilySize() throws {
        for size in [CGSize(width: 393, height: 852), CGSize(width: 390, height: 678), CGSize(width: 820, height: 1180)] {
            let (page, _, window) = show(size: size, category: .accessibilityExtraExtraExtraLarge)
            for row in HostedPage.descendants(of: page.view).compactMap({ $0 as? UKLoginRowView }) where !row.isHidden {
                let label = row.label.convert(row.label.bounds, to: row)
                XCTAssertLessThanOrEqual(label.maxX, row.bounds.maxX + 0.5, "the label fits its row at \(size)")
                XCTAssertLessThanOrEqual(label.maxY, row.bounds.maxY + 0.5)
                XCTAssertGreaterThanOrEqual(label.minY, -0.5)
            }
            window.isHidden = true
        }
    }
}
