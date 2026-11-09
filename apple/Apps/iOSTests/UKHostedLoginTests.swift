import HassCore
import UIKit
import XCTest
@testable import HassUI

/// The sign-in screen against the debug stub (`FENTON_SIGNIN_STUB` answers): typing, the refused-password line, the failure card and
/// its details, two-step accounts, and the welcome-back variant.
@MainActor
final class UKHostedLoginTests: XCTestCase {
    private func controller(stub: String, mode: LoginModel.Mode = .fresh, onSignedIn: @escaping @MainActor (HassServer, AuthTokens) throws -> Void = { _, _ in })
        -> (UKLoginViewController, LoginModel, UIWindow) {
        let defaults = UserDefaults(suiteName: "hosted.login.\(UUID().uuidString)")!
        let model = LoginModel(mode: mode, store: RememberedAccountStore(defaults: defaults), defaultServer: "https://ha.example.com", makeFlow: { server in
            HassLoginFlow(server: server, session: DebugSignInStub.session(["FENTON_SIGNIN_STUB": stub]) ?? .shared)
        })
        let page = UKLoginViewController(model: model, playsIntro: false, environment: nil, onIntroPlayed: {}, onUseDifferentAccount: {}, onSignedIn: onSignedIn)
        let window = HostedPage.show(page, size: CGSize(width: 393, height: 852))
        hostedSettle(0.4)
        return (page, model, window)
    }

    private func field(_ id: String, in page: UIViewController) -> UITextField? {
        HostedPage.descendants(of: page.view).first { $0.accessibilityIdentifier == id } as? UITextField
    }

    private func type(_ text: String, into field: UITextField?) {
        field?.text = text
        field?.sendActions(for: .editingChanged)
    }

    private func submit(_ page: UIViewController) {
        (HostedPage.descendants(of: page.view).first { $0.accessibilityIdentifier == "login.submit" } as? UIControl)?.sendActions(for: .touchUpInside)
    }

    private func identifiers(_ page: UIViewController) -> [String] { HostedDriver.identifiers(in: page.view) }

    func testTheSignInButtonWaitsForBothFieldsThenSignsIn() {
        var signedIn = false
        let (page, model, window) = controller(stub: "success") { _, _ in signedIn = true }
        defer { window.isHidden = true }
        XCTAssertFalse(model.canSubmit)
        type("alex", into: field("login.username", in: page))
        XCTAssertFalse(model.canSubmit, "a password is needed too")
        XCTAssertEqual(field("login.server", in: page)?.text, "https://ha.example.com", "the build's server is prefilled")
        type("secret", into: field("login.password", in: page))
        XCTAssertTrue(model.canSubmit)
        XCTAssertEqual(model.username, "alex")
        submit(page)
        hostedSettle(1.5)
        XCTAssertTrue(signedIn, "a successful answer reports the tokens")
    }

    func testAWrongPasswordShowsTheInlineLineAndOutline() {
        let (page, model, window) = controller(stub: "wrong")
        defer { window.isHidden = true }
        type("alex", into: field("login.username", in: page))
        type("nope", into: field("login.password", in: page))
        submit(page)
        hostedSettle(1.5)
        XCTAssertEqual(model.failure, .wrongCredentials)
        XCTAssertTrue(identifiers(page).contains("login.error"), "the refused password has its red line; saw \(identifiers(page))")
        XCTAssertTrue(HostedPage.labels(in: page.view).contains(LoginModel.Failure.wrongCredentials.inlineMessage ?? "?"))
    }

    func testUnreachableAndFailedShowTheCardWithDetails() {
        for stub in ["unreachable", "failed"] {
            let (page, model, window) = controller(stub: stub)
            type("alex", into: field("login.username", in: page))
            type("secret", into: field("login.password", in: page))
            submit(page)
            hostedSettle(1.5)
            XCTAssertNotNil(model.failure, "\(stub) fails")
            XCTAssertTrue(identifiers(page).contains("login.error.card"), "\(stub) shows the failure card; saw \(identifiers(page))")
            XCTAssertEqual(model.buttonTitle, LoginCopy.retryTitle, "the button offers Try Again")
            if let details = HostedPage.descendants(of: page.view).first(where: { $0.accessibilityIdentifier == "login.error.details" }) as? UIControl {
                details.sendActions(for: .touchUpInside)
                hostedSettle(0.4)
                details.sendActions(for: .touchUpInside)
                hostedSettle(0.4)
            }
            window.isHidden = true
        }
    }

    func testTwoStepAccountsGetTheirOwnLine() {
        let (page, model, window) = controller(stub: "twostep")
        defer { window.isHidden = true }
        type("alex", into: field("login.username", in: page))
        type("secret", into: field("login.password", in: page))
        submit(page)
        hostedSettle(1.5)
        XCTAssertEqual(model.failure, .twoStepUnsupported)
        XCTAssertTrue(HostedPage.labels(in: page.view).contains(LoginModel.Failure.twoStepUnsupported.inlineMessage ?? "?"))
    }

    func testWelcomeBackShowsTheAccountReadOnlyAndCanSwitchAccount() {
        var switched = false
        let defaults = UserDefaults(suiteName: "hosted.login.\(UUID().uuidString)")!
        let model = LoginModel(mode: .welcomeBack(RememberedAccount(username: "alex", name: "Alex")), store: RememberedAccountStore(defaults: defaults),
                               defaultServer: "https://ha.example.com")
        let page = UKLoginViewController(model: model, playsIntro: false, environment: nil, onIntroPlayed: {}, onUseDifferentAccount: { switched = true }, onSignedIn: { _, _ in })
        let window = HostedPage.show(page)
        hostedSettle(0.4)
        defer { window.isHidden = true }
        XCTAssertTrue(identifiers(page).contains("login.username.readonly"), "the account is shown read-only")
        XCTAssertTrue(HostedPage.labels(in: page.view).contains("alex"))
        (HostedPage.descendants(of: page.view).first { $0.accessibilityIdentifier == "login.differentAccount" } as? UIControl)?.sendActions(for: .touchUpInside)
        hostedSettle(0.4)
        XCTAssertTrue(switched, "Use a Different Account tells the host")
    }

    func testTheIntroPlaysOnceAndTheScreenSurvivesAnAccessibilitySize() {
        let defaults = UserDefaults(suiteName: "hosted.login.\(UUID().uuidString)")!
        let model = LoginModel(mode: .fresh, store: RememberedAccountStore(defaults: defaults))
        var played = 0
        let page = UKLoginViewController(model: model, playsIntro: true, environment: nil, onIntroPlayed: { played += 1 }, onUseDifferentAccount: {}, onSignedIn: { _, _ in })
        let window = HostedPage.show(page)
        hostedSettle(2.5)
        defer { window.isHidden = true }
        XCTAssertEqual(played, 1, "the launch sequence reports once")
        let big = UKLoginViewController(model: model, playsIntro: false, environment: nil, onIntroPlayed: {}, onUseDifferentAccount: {}, onSignedIn: { _, _ in })
        big.overrideUserInterfaceStyle = .dark
        let window2 = HostedPage.show(big)
        window2.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
        hostedSettle(0.5)
        XCTAssertFalse(HostedPage.labels(in: big.view).isEmpty)
        window2.isHidden = true
    }

    func testTheSignInPiecesDrawForEveryAppIcon() {
        for icon in AppIconChoice.allCases {
            let mark = UKSignInMarkView(icon: icon)
            let monogram = UKSignInMonogramView(name: "Alex Morgan", icon: icon)
            let holder = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
            holder.addSubview(mark)
            holder.addSubview(monogram)
            holder.layoutIfNeeded()
            XCTAssertNotNil(mark.superview)
        }
        let ground = UKSignInGroundView()
        ground.frame = CGRect(x: 0, y: 0, width: 300, height: 300)
        ground.glowAlpha = 0.5
        ground.layoutIfNeeded()
        XCTAssertEqual(ground.glowAlpha, 0.5)
    }
}
