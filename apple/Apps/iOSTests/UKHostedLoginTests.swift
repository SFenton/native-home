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

    // MARK: - Safe area and the split (`.agents/design/sign-in-layout.md`)

    /// A sign-in page in a window of `size`, with the side safe-area inset a Duo's system strip leaves, a size class, a layout
    /// direction, a text size and a hinge. The shell environment is returned so it stays alive (the page holds it weakly).
    private func hostedPage(size: CGSize, insets: UIEdgeInsets = .zero, regular: Bool = false, rtl: Bool = false,
                            category: UIContentSizeCategory? = nil, hinge: CGRect? = nil, mode: LoginModel.Mode = .fresh)
        -> (page: UKLoginViewController, window: UIWindow, environment: UKShellEnvironment) {
        let defaults = UserDefaults(suiteName: "hosted.login.\(UUID().uuidString)")!
        let model = LoginModel(mode: mode, store: RememberedAccountStore(defaults: defaults), defaultServer: "https://ha.example.com")
        let environment = UKShellEnvironment()
        environment.windowHinge = hinge
        let page = UKLoginViewController(model: model, playsIntro: false, environment: environment, onIntroPlayed: {}, onUseDifferentAccount: {}, onSignedIn: { _, _ in })
        page.additionalSafeAreaInsets = insets
        if rtl { page.view.semanticContentAttribute = .forceRightToLeft }
        let window = HostedPage.show(page, size: size)
        window.traitOverrides.horizontalSizeClass = regular ? .regular : .compact
        if rtl { window.traitOverrides.layoutDirection = .rightToLeft }
        if let category { window.traitOverrides.preferredContentSizeCategory = category }
        hostedSettle(0.4)
        page.view.layoutIfNeeded()
        neutraliseHostSideInsets(of: page, wanting: insets)
        return (page, window, environment)
    }

    /// The host can have side safe-area insets of its own (the folded Duo's 84 pt system strip), on top of the ones a test adds.
    /// The test states the side insets it wants in total, so the extra additional inset makes up the difference from what the host
    /// already gives; the invariants then read the same on every device family.
    private func neutraliseHostSideInsets(of page: UIViewController, wanting wanted: UIEdgeInsets = .zero, settle: Bool = true) {
        let current = page.view.safeAreaInsets, added = page.additionalSafeAreaInsets
        let hostLeft = current.left - added.left, hostRight = current.right - added.right
        guard hostLeft != 0 || hostRight != 0 else { return }
        page.additionalSafeAreaInsets = UIEdgeInsets(top: added.top, left: wanted.left - hostLeft, bottom: added.bottom, right: wanted.right - hostRight)
        if settle { hostedSettle(0.2) }
        page.view.layoutIfNeeded()
    }

    /// A landscape window each region of which clears the 360 pt minimum with the midpoint band (``SplitPolicy``).
    private static let wideSize = CGSize(width: 800, height: 520)

    private func scrollView(_ page: UIViewController) -> UIScrollView {
        HostedPage.descendants(of: page.view).compactMap { $0 as? UIScrollView }.first!
    }

    private func element(_ id: String, in page: UIViewController) -> UIView? {
        HostedPage.descendants(of: page.view).first { $0.accessibilityIdentifier == id }
    }

    private func frame(of view: UIView, in page: UIViewController) -> CGRect { view.convert(view.bounds, to: page.view) }

    /// The three fields' frames in the scroll view's content coordinates.
    private func fieldRects(_ page: UIViewController) -> [CGRect] {
        let scroll = scrollView(page)
        return ["login.server", "login.username", "login.password"].compactMap { element($0, in: page) }.map { $0.convert($0.bounds, to: scroll) }
    }

    /// The folded Duo (466 pt window, an 84 pt strip) gives the sign-in a 382 pt scroll view with no sideways range, fields inside the
    /// safe area and a full-bleed ground, with the strip on either side and in right to left.
    func testTheFoldedDuoFormStaysInsideTheSafeAreaWithNoSidewaysRange() {
        let size = CGSize(width: 466, height: 678)
        let cases: [(String, UIEdgeInsets, Bool)] = [
            ("strip trailing", UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 84), false),
            ("strip leading", UIEdgeInsets(top: 0, left: 84, bottom: 0, right: 0), false),
            ("right to left", UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 84), true),
        ]
        for (name, insets, rtl) in cases {
            let (page, window, _) = hostedPage(size: size, insets: insets, rtl: rtl)
            defer { window.isHidden = true }
            let scroll = scrollView(page)
            XCTAssertEqual(scroll.bounds.width, 382, accuracy: 0.5, "\(name): the scroll view is the safe width")
            HostedScrollInvariants.assertZeroHorizontalRange(scroll, reveal: fieldRects(page), name)
            let safe = page.view.safeAreaLayoutGuide.layoutFrame
            for id in ["login.server", "login.username", "login.password", "login.submit"] {
                guard let control = element(id, in: page) else { return XCTFail("\(name): \(id) missing") }
                let box = frame(of: control, in: page)
                XCTAssertGreaterThanOrEqual(box.minX, safe.minX - 0.5, "\(name): \(id) starts inside the safe area")
                XCTAssertLessThanOrEqual(box.maxX, safe.maxX + 0.5, "\(name): \(id) ends inside the safe area")
            }
            if let username = element("login.username", in: page) {
                XCTAssertEqual(frame(of: username, in: page).width, 334, accuracy: 0.5, "\(name): fields are 334 pt")
            }
            let ground = HostedPage.descendants(of: page.view).first { $0 is UKSignInGroundView }
            XCTAssertEqual(ground.map { frame(of: $0, in: page) }, page.view.bounds, "\(name): the ground fills the window")
        }
    }

    /// iPhone (402 pt) and iPad portrait (834 pt) have no side inset: their fields are where they were (354 pt at 24; 412 pt at 211).
    func testPhoneAndPadPortraitFramesAreUnchanged() {
        for (width, fieldWidth, minX) in [(CGFloat(402), CGFloat(354), CGFloat(24)), (834, 412, 211)] {
            let (page, window, _) = hostedPage(size: CGSize(width: width, height: 874), regular: width > 500)
            defer { window.isHidden = true }
            let box = element("login.username", in: page).map { frame(of: $0, in: page) } ?? .zero
            XCTAssertEqual(box.width, fieldWidth, accuracy: 0.5, "\(width) pt window")
            XCTAssertEqual(box.minX, minX, accuracy: 0.5, "\(width) pt window")
            HostedScrollInvariants.assertZeroHorizontalRange(scrollView(page), reveal: fieldRects(page), "\(width) pt")
        }
    }

    /// Wide and regular: the header is in the leading region, the form in the trailing one, the header and the block from the fields to
    /// Sign In on one line, and the footnote hangs outside the block.
    func testAWideWindowPutsTheHeaderBesideTheFormOnOneLine() {
        let size = Self.wideSize
        let (page, window, _) = hostedPage(size: size, regular: true)
        defer { window.isHidden = true }
        assertSplit(page, size: size, rtl: false)
    }

    /// The same, partly folded: the regions sit either side of the hinge band.
    func testThePartlyFoldedDuoSplitsEitherSideOfTheHinge() {
        let size = CGSize(width: 900, height: 600)
        let hinge = CGRect(x: 430, y: 0, width: 40, height: 600)
        let (page, window, _) = hostedPage(size: size, regular: true, hinge: hinge)
        defer { window.isHidden = true }
        assertSplit(page, size: size, rtl: false)
        let form = element("login.username", in: page).map { frame(of: $0, in: page) } ?? .zero
        XCTAssertGreaterThanOrEqual(form.minX, hinge.maxX, "the form starts after the band")
        let title = element("login.title", in: page).map { frame(of: $0, in: page) } ?? .zero
        XCTAssertLessThanOrEqual(title.maxX, hinge.minX, "the header ends before the band")
    }

    /// Right to left swaps the regions: the header takes the right region.
    func testTheSplitSwapsInRightToLeft() {
        let size = Self.wideSize
        let (page, window, _) = hostedPage(size: size, regular: true, rtl: true)
        defer { window.isHidden = true }
        assertSplit(page, size: size, rtl: true)
    }

    /// The midpoint between the mark's drawn top and the header's bottom, in the page's coordinates.
    private func opticalMid(of header: UIView, in page: UIViewController) -> CGFloat {
        let mark = HostedPage.descendants(of: header).first { $0 is UKSignInMarkView || $0 is UKSignInMonogramView }
        let inkTop = (mark as? UKSignInMarkView)?.inkTopInset ?? 0
        let top = mark.map { $0.convert(CGPoint(x: 0, y: inkTop), to: page.view).y } ?? 0
        return (top + frame(of: header, in: page).maxY) / 2
    }

    private func assertSplit(_ page: UKLoginViewController, size: CGSize, rtl: Bool, file: StaticString = #filePath, line: UInt = #line) {
        guard let title = element("login.title", in: page), let fields = element("login.fields", in: page),
              let submit = element("login.submit", in: page), let footnote = element("login.footnote", in: page),
              let header = title.superview else { return XCTFail("the sign-in pieces are missing", file: file, line: line) }
        let headerBox = frame(of: header, in: page), fieldsBox = frame(of: fields, in: page)
        let submitBox = frame(of: submit, in: page), footnoteBox = frame(of: footnote, in: page)
        let beside = rtl ? headerBox.minX > fieldsBox.maxX : headerBox.maxX < fieldsBox.minX
        XCTAssertTrue(beside, "the header is beside the form, on the \(rtl ? "right" : "left"): \(headerBox) \(fieldsBox)", file: file, line: line)
        let blockMid = (fieldsBox.minY + submitBox.maxY) / 2
        XCTAssertEqual(opticalMid(of: header, in: page), blockMid, accuracy: 0.5, "the drawn header and the block share a centre line", file: file, line: line)
        XCTAssertGreaterThanOrEqual(footnoteBox.minY, submitBox.maxY + 15.5, "the footnote hangs under Sign In, outside the block", file: file, line: line)
        // The safe height of the scroll view: a software keyboard (the Duo's simulator shows one for a focused field) shortens it.
        let safe = page.view.safeAreaLayoutGuide.layoutFrame.intersection(scrollView(page).convert(scrollView(page).bounds, to: page.view))
        XCTAssertEqual(blockMid, safe.midY, accuracy: 2, "the block is centred in the scroll view's safe height", file: file, line: line)
        let mark = HostedPage.descendants(of: header).first { $0 is UKSignInMarkView }
        if let mark { XCTAssertEqual(mark.bounds.width, 112, accuracy: 0.5, "the mark is 112 pt in the split", file: file, line: line) }
    }

    /// An accessibility text size keeps the column, whatever the window.
    func testAnAccessibilityTextSizeKeepsTheColumnInAWideWindow() {
        let size = Self.wideSize
        let (page, window, _) = hostedPage(size: size, regular: true, category: .accessibilityExtraExtraExtraLarge)
        defer { window.isHidden = true }
        guard let title = element("login.title", in: page), let username = element("login.username", in: page) else { return XCTFail("missing") }
        XCTAssertEqual(frame(of: title, in: page).midX, frame(of: username, in: page).midX, accuracy: 2, "the header is centred over the form")
        let mark = HostedPage.descendants(of: page.view).first { $0 is UKSignInMarkView }
        XCTAssertEqual(mark?.bounds.width ?? 0, 96, accuracy: 0.5, "the column keeps the 96 pt mark")
    }

    /// Rotating or folding moves the same views: text and focus survive the switch from the column to two regions.
    func testSwitchingLayoutKeepsTheSameViewsTextAndFocus() {
        let narrow = CGSize(width: 520, height: 800)
        let (page, window, _) = hostedPage(size: narrow, regular: true)
        defer { window.isHidden = true }
        guard let user = element("login.username", in: page) as? UITextField else { return XCTFail("no username") }
        user.becomeFirstResponder()
        type("alex", into: user)
        let before = frame(of: user, in: page)
        resize(window, page, to: Self.wideSize)
        hostedSettle(0.8)
        page.view.layoutIfNeeded()
        XCTAssertTrue(element("login.username", in: page) === user, "the same field instance")
        XCTAssertEqual(user.text, "alex")
        XCTAssertTrue(user.isFirstResponder, "focus is kept")
        XCTAssertNotEqual(frame(of: user, in: page).minX, before.minX, "the form moved to the trailing region")
        assertSplit(page, size: Self.wideSize, rtl: false)
    }

    /// Field minX is the same before focus, on each focus and after dismissing; the scroll view never moves sideways.
    func testFocusingEachFieldNeverMovesTheFormSideways() {
        let (page, window, _) = hostedPage(size: CGSize(width: 466, height: 678), insets: UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 84))
        defer { window.isHidden = true }
        let ids = ["login.server", "login.username", "login.password"]
        let rest = ids.map { element($0, in: page).map { frame(of: $0, in: page).minX } ?? -1 }
        for (index, id) in ids.enumerated() {
            (element(id, in: page) as? UITextField)?.becomeFirstResponder()
            hostedSettle(0.3)
            let now = ids.map { element($0, in: page).map { frame(of: $0, in: page).minX } ?? -1 }
            for (a, b) in zip(now, rest) { XCTAssertEqual(a, b, accuracy: 0.5, "focus on \(ids[index])") }
            XCTAssertEqual(scrollView(page).contentOffset.x, 0, accuracy: 0.5)
        }
        page.view.endEditing(true)
        hostedSettle(0.3)
        let after = ids.map { element($0, in: page).map { frame(of: $0, in: page).minX } ?? -1 }
        for (a, b) in zip(after, rest) { XCTAssertEqual(a, b, accuracy: 0.5, "after dismissing") }
    }

    /// A software keyboard shortens the scroll view, never the decision: a regular 1032 x 1376 window (iPad 13-inch portrait) is a column
    /// with the keyboard up as it is without, the fields keep their minX and no layout animation starts.
    func testAKeyboardInATallRegularWindowDoesNotFlipTheColumnToTwoRegions() {
        let (page, window, _) = hostedPage(size: CGSize(width: 1032, height: 1376), regular: true)
        defer { window.isHidden = true }
        let ids = ["login.server", "login.username", "login.password"]
        let rest = ids.map { element($0, in: page).map { frame(of: $0, in: page).minX } ?? -1 }
        guard let title = element("login.title", in: page), let fields = element("login.fields", in: page) else { return XCTFail("missing") }
        XCTAssertLessThan(frame(of: title, in: page).maxY, frame(of: fields, in: page).minY + 1, "at rest: the header is above the form")
        // The scroll view ends 400 pt above the bottom, where the keyboard layout guide leaves it with a 400 pt keyboard; the safe area keeps its height.
        let scroll = scrollView(page)
        guard let bottom = page.view.constraints.first(where: { $0.firstItem === scroll && $0.firstAttribute == .bottom }) else { return XCTFail("no bottom constraint") }
        bottom.isActive = false
        scroll.bottomAnchor.constraint(equalTo: page.view.bottomAnchor, constant: -400).isActive = true
        page.view.setNeedsLayout()
        page.view.layoutIfNeeded()
        XCTAssertEqual(scroll.frame.height, 976, accuracy: 1, "the keyboard shortened the scroll view to wider than tall")
        XCTAssertGreaterThan(scroll.frame.width, scroll.frame.height)
        for holder in holders(page) { XCTAssertTrue(holder.layer.animationKeys()?.isEmpty ?? true, "no layout animation starts") }
        let up = ids.map { element($0, in: page).map { frame(of: $0, in: page).minX } ?? -1 }
        for (a, b) in zip(up, rest) { XCTAssertEqual(a, b, accuracy: 0.5, "the fields keep their minX") }
        XCTAssertLessThan(frame(of: title, in: page).maxY, frame(of: fields, in: page).minY + 1, "with the keyboard up: still a column")
    }

    /// VoiceOver reads the header, the failure card, Server, Username, Password, the inline error, Sign In, Use a Different Account
    /// and the footnote, in the column and in two regions.
    func testVoiceOverOrderIsTheSameInBothLayouts() {
        for regular in [false, true] {
            let (page, window, _) = hostedPage(size: regular ? Self.wideSize : CGSize(width: 402, height: 874), regular: regular)
            defer { window.isHidden = true }
            let content = scrollView(page).subviews.first { $0.accessibilityElements != nil }
            let ids = (content?.accessibilityElements as? [UIView])?.map { $0.accessibilityIdentifier ?? "?" }
            XCTAssertEqual(ids, ["login.title", "login.line", "login.server", "login.username", "login.password", "login.submit", "login.footnote"], "regular \(regular)")
        }
        let account = RememberedAccount(username: "alex", name: "Alex")
        let (page, window, _) = hostedPage(size: Self.wideSize, regular: true, mode: .welcomeBack(account))
        defer { window.isHidden = true }
        let content = scrollView(page).subviews.first { $0.accessibilityElements != nil }
        let ids = (content?.accessibilityElements as? [UIView])?.map { $0.accessibilityIdentifier ?? "?" }
        XCTAssertEqual(ids, ["login.title", "login.line", "login.server.readonly", "login.username.readonly", "login.password", "login.submit", "login.differentAccount", "login.footnote"])
    }

    // MARK: - Optical centre, header width and motion (`.agents/design/sign-in-layout.md`)

    private static let padLandscape = CGSize(width: 1210, height: 834)

    /// The mark's drawn top is 12% of its side below its frame (13.4 pt at 112 pt); the monogram disc has none.
    func testTheMarkInkTopComesFromItsPath() {
        let mark = UKSignInMarkView(icon: SignInStyle.savedIcon(), size: 112)
        XCTAssertEqual(mark.inkTopInset, 13.44, accuracy: 0.1)
    }

    /// The header's drawn span (mark ink top to the line's bottom) is centred on the block from the fields to Sign In, fresh and
    /// welcome back, at rest and with the keyboard up (a shorter scroll frame, as the keyboard layout guide leaves it).
    func testTheDrawnHeaderIsCentredOnTheBlockAtRestAndWithTheKeyboardUp() {
        let account = RememberedAccount(username: "alex", name: "Alex")
        for (name, mode) in [("fresh", LoginModel.Mode.fresh), ("welcome back", .welcomeBack(account))] {
            for keyboardUp in [false, true] {
                let size = keyboardUp ? CGSize(width: Self.padLandscape.width, height: 834 - 200) : Self.padLandscape
                let (page, window, _) = hostedPage(size: size, regular: true, mode: mode)
                defer { window.isHidden = true }
                assertSplit(page, size: size, rtl: false)
                XCTAssertNotNil(element("login.title", in: page), "\(name), keyboard \(keyboardUp)")
            }
        }
    }

    /// The header is as wide as the form's text: 412 pt at most in the iPad's landscape window, so welcome back does not orphan a word.
    func testTheHeaderIsNoWiderThanTheFormInAnIPadLandscapeWindow() {
        let account = RememberedAccount(username: "alex", name: "Alex")
        for mode in [LoginModel.Mode.fresh, .welcomeBack(account)] {
            let (page, window, _) = hostedPage(size: Self.padLandscape, regular: true, mode: mode)
            defer { window.isHidden = true }
            guard let header = element("login.title", in: page)?.superview, let fields = element("login.fields", in: page) else { return XCTFail("missing") }
            XCTAssertLessThanOrEqual(frame(of: header, in: page).width, 412.5)
            XCTAssertEqual(frame(of: header, in: page).width, 412, accuracy: 0.5)
            XCTAssertEqual(frame(of: fields, in: page).width, 412, accuracy: 0.5)
        }
    }

    /// Resizes the window and lays the page out in the same turn, so a test reads the animations the switch just started.
    private func resize(_ window: UIWindow, _ page: UIViewController, to size: CGSize) {
        window.frame = CGRect(origin: .zero, size: size)
        page.view.frame = CGRect(origin: .zero, size: size)
        window.layoutIfNeeded()
        page.view.layoutIfNeeded()
        // Without a run-loop turn, so the animations the switch just started are still there to read.
        neutraliseHostSideInsets(of: page, settle: false)
    }

    /// The header and form holders (their layers are the ones the switch moves).
    private func holders(_ page: UIViewController) -> [UIView] {
        [element("login.title", in: page)?.superview?.superview, element("login.fields", in: page)?.superview].compactMap { $0 }
    }

    /// A window that has not yet appeared, in a regular narrow size; the switch to the wide size is then made without a run-loop turn.
    private func unappearedPage() -> (page: UKLoginViewController, window: UIWindow, environment: UKShellEnvironment) {
        let defaults = UserDefaults(suiteName: "hosted.login.\(UUID().uuidString)")!
        let model = LoginModel(mode: .fresh, store: RememberedAccountStore(defaults: defaults), defaultServer: "https://ha.example.com")
        let environment = UKShellEnvironment()
        let page = UKLoginViewController(model: model, playsIntro: false, environment: environment, onIntroPlayed: {}, onUseDifferentAccount: {}, onSignedIn: { _, _ in })
        let frame = CGRect(origin: .zero, size: CGSize(width: 520, height: 800))
        let window: UIWindow
        if let scene = HostedPage.scene { window = UIWindow(windowScene: scene); window.frame = frame } else { window = UIWindow(frame: frame) }
        HostedPage.track(window)
        window.traitOverrides.horizontalSizeClass = .regular
        window.rootViewController = page
        window.makeKeyAndVisible()
        page.loadViewIfNeeded()
        page.view.layoutIfNeeded()
        return (page, window, environment)
    }

    /// After the screen has appeared, a column-to-split switch leaves a position animation on the header and the form to settle.
    func testALayoutSwitchAfterAppearingAnimatesTheHeaderAndForm() {
        let (page, window, _) = hostedPage(size: CGSize(width: 520, height: 800), regular: true)
        defer { window.isHidden = true }
        resize(window, page, to: Self.wideSize)
        let held = holders(page)
        XCTAssertEqual(held.count, 2)
        for holder in held {
            XCTAssertFalse(holder.layer.animationKeys()?.isEmpty ?? true, "\(String(describing: holder.accessibilityIdentifier)) animates to its new place")
        }
        hostedSettle(1.0)
        for holder in held { XCTAssertTrue(holder.layer.animationKeys()?.isEmpty ?? true, "and settles") }
        assertSplit(page, size: Self.wideSize, rtl: false)
    }

    /// Reduce Motion still moves the same views, with the quick animation.
    func testALayoutSwitchUnderReduceMotionStillAnimatesQuickly() {
        let saved = UKMotion.reduceMotionOverride
        UKMotion.reduceMotionOverride = true
        defer { UKMotion.reduceMotionOverride = saved }
        let (page, window, _) = hostedPage(size: CGSize(width: 520, height: 800), regular: true)
        defer { window.isHidden = true }
        resize(window, page, to: Self.wideSize)
        for holder in holders(page) { XCTAssertFalse(holder.layer.animationKeys()?.isEmpty ?? true, "quick, not none") }
        hostedSettle(0.75)
        assertSplit(page, size: Self.wideSize, rtl: false)
    }

    /// Before the first appearance the switch is immediate: nothing animates, and the split is already in place.
    func testALayoutSwitchBeforeAppearingHasNoAnimation() {
        let (page, window, _) = unappearedPage()
        defer { window.isHidden = true }
        resize(window, page, to: Self.wideSize)
        for holder in holders(page) { XCTAssertTrue(holder.layer.animationKeys()?.isEmpty ?? true, "no animation before appearing") }
        assertSplit(page, size: Self.wideSize, rtl: false)
    }
}
