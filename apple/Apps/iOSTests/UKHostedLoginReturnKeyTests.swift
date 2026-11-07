import HassCore
import UIKit
import XCTest
@testable import HassUI

/// The Return key on the sign-in form: on the username it moves to the password, on the password it signs in.
@MainActor
final class UKHostedLoginReturnKeyTests: XCTestCase {
    func testReturnMovesToThePasswordThenSignsIn() {
        var signedIn = false
        let defaults = UserDefaults(suiteName: "hosted.login.return.\(UUID().uuidString)")!
        let model = LoginModel(mode: .fresh, store: RememberedAccountStore(defaults: defaults), defaultServer: "https://ha.example.com", makeFlow: { server in
            HassLoginFlow(server: server, session: DebugSignInStub.session(["FENTON_SIGNIN_STUB": "success"]) ?? .shared)
        })
        let page = UKLoginViewController(model: model, playsIntro: false, environment: nil, onIntroPlayed: {}, onUseDifferentAccount: {},
                                         onSignedIn: { _, _ in signedIn = true })
        let window = HostedPage.show(page, size: CGSize(width: 393, height: 852))
        defer { window.isHidden = true }
        hostedSettle(0.4)
        func field(_ id: String) -> UITextField? { HostedPage.descendants(of: page.view).first { $0.accessibilityIdentifier == id } as? UITextField }
        let server = field("login.server")
        let username = field("login.username")
        let password = field("login.password")
        username?.text = "alex"
        username?.sendActions(for: .editingChanged)
        password?.text = "secret"
        password?.sendActions(for: .editingChanged)
        XCTAssertTrue(model.canSubmit)

        let serverReturn = server.flatMap { page.textFieldShouldReturn($0) }
        XCTAssertEqual(serverReturn, false, "Return is handled by the form")
        XCTAssertTrue(username?.isFirstResponder ?? false, "Return on the server moves to the username")

        let usernameReturn = username.flatMap { page.textFieldShouldReturn($0) }
        XCTAssertEqual(usernameReturn, false, "Return is handled by the form, not typed into the field")
        XCTAssertFalse(signedIn, "Return on the username does not sign in")
        XCTAssertTrue(password?.isFirstResponder ?? false, "it moves on to the password")

        _ = password.flatMap { page.textFieldShouldReturn($0) }
        hostedSettle(1.5)
        XCTAssertTrue(signedIn, "Return on the password signs in")
    }
}
