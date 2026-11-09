#if os(iOS)
import FentonActivityModel
import HassCore
import HassDesign
import HassTelemetry
import UIKit

/// Native username/password sign-in through Home Assistant's login flow (owner design, 2026-10-17;
/// `.agents/platforms/apple/auth.md`, "Sign-in screen"): the UIKit counterpart of ``LoginView``.
///
/// Always dark, on a radial glow. The screen is a bare house-and-heart mark, the name, one line, a glass module with the server,
/// username and password rows, and the Sign In capsule. A session that ended shows the welcome back variant instead: the person's
/// monogram, the server and account read-only, only the password to type. Errors are plain sentences, inline (a
/// bad address or an address that is not Home Assistant also outlines the Server row and moves focus to it); a server that cannot
/// be reached gets a card with the raw reason one tap away. On iPad and the unfolded Duo the form is a centred column no wider than
/// ``SignInStyle/columnWidth``, kept off the hinge.
///
/// `playsIntro` runs the launch sequence (the glow fades up, the mark springs in, the title and then the form rise) for a cold
/// launch only; Reduce Motion cross-fades the same pieces. It shares ``LoginModel`` with the SwiftUI screen.
final class UKLoginViewController: UIViewController, UITextFieldDelegate {
    private let model: LoginModel
    private let playsIntro: Bool
    private let onIntroPlayed: () -> Void
    private let onUseDifferentAccount: () -> Void
    private let onSignedIn: @MainActor @Sendable (HassServer, AuthTokens) throws -> Void
    private weak var environment: UKShellEnvironment?
    private let icon = SignInStyle.savedIcon()
    private let bag = UKObservationBag()

    private let ground = UKSignInGroundView()
    private let scroll = UIScrollView()
    private let content = UIView()
    private let column = UIStackView()
    private let headerHolder = UIView()
    private let formHolder = UIStackView()
    private let fields = UKLoginFieldsModule()
    private let submit = UKPrimaryButton("") {}
    private let differentAccount = UIButton(type: .custom)
    private let footnote = UILabel()
    private var markView: UIView?
    private var titleViews: [UIView] = []
    private var cardView: UIView?
    private var errorView: UIView?
    private var columnLeading: NSLayoutConstraint!
    private var columnWidth: NSLayoutConstraint!
    private var shownMode: LoginModel.Mode?
    private var lastFailure: LoginModel.Failure?
    private var didAppearOnce = false
    private var introPending: Bool
    private var markScale: CGFloat = 1

    init(model: LoginModel, playsIntro: Bool, environment: UKShellEnvironment?, onIntroPlayed: @escaping () -> Void,
         onUseDifferentAccount: @escaping () -> Void, onSignedIn: @escaping @MainActor @Sendable (HassServer, AuthTokens) throws -> Void) {
        self.model = model
        self.playsIntro = playsIntro
        self.environment = environment
        self.onIntroPlayed = onIntroPlayed
        self.onUseDifferentAccount = onUseDifferentAccount
        self.onSignedIn = onSignedIn
        introPending = playsIntro
        super.init(nibName: nil, bundle: nil)
        // Dark throughout, like the app it opens.
        overrideUserInterfaceStyle = .dark
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: View

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(rgb: SignInStyle.base)
        ground.frame = view.bounds
        ground.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        ground.glowAlpha = playsIntro ? 0 : 1
        view.addSubview(ground)

        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.keyboardDismissMode = .interactive
        scroll.alwaysBounceVertical = false
        scroll.contentInsetAdjustmentBehavior = .always
        view.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: view.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
        ])
        content.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
            content.heightAnchor.constraint(greaterThanOrEqualTo: scroll.safeAreaLayoutGuide.heightAnchor),
        ])
        buildColumn()
        wireFields()
        bindModel()
        // The screen is one named group for assistive technologies; its controls keep their own labels.
        content.accessibilityContainerType = .semanticGroup
        content.accessibilityLabel = "Sign in"
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didAppearOnce else { return }
        didAppearOnce = true
        model.prefillForDebugTesting()
        syncFieldsFromModel()
        signInByItself()
        playIntro()
    }

    // MARK: Layout

    private func buildColumn() {
        column.axis = .vertical
        column.alignment = .fill
        column.spacing = 0
        column.isLayoutMarginsRelativeArrangement = true
        column.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: HassTokens.Spacing.xl, bottom: HassTokens.Spacing.l, trailing: HassTokens.Spacing.xl)
        column.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(column)
        columnLeading = column.leadingAnchor.constraint(equalTo: content.leadingAnchor)
        columnWidth = column.widthAnchor.constraint(equalToConstant: SignInStyle.columnWidth)
        NSLayoutConstraint.activate([
            columnLeading, columnWidth,
            // Centred when the content is shorter than the screen (`frame(minHeight:)` centres the column), scrolling when taller.
            column.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            column.topAnchor.constraint(greaterThanOrEqualTo: content.topAnchor),
            column.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor),
        ])

        let top = UIView()
        top.translatesAutoresizingMaskIntoConstraints = false
        top.heightAnchor.constraint(equalToConstant: HassTokens.Spacing.xl).isActive = true
        column.addArrangedSubview(top)
        headerHolder.translatesAutoresizingMaskIntoConstraints = false
        column.addArrangedSubview(headerHolder)
        let gap = UIView()
        gap.translatesAutoresizingMaskIntoConstraints = false
        gap.heightAnchor.constraint(equalToConstant: HassTokens.Spacing.xl + HassTokens.Spacing.s).isActive = true
        column.addArrangedSubview(gap)

        // The form, then a flexible space and the footnote; the two flexible spaces share what is left equally.
        formHolder.axis = .vertical
        formHolder.spacing = HassTokens.Spacing.l
        formHolder.alignment = .fill
        column.addArrangedSubview(formHolder)
        let middle = UIView()
        middle.translatesAutoresizingMaskIntoConstraints = false
        middle.heightAnchor.constraint(equalToConstant: HassTokens.Spacing.xl).isActive = true
        let spacerSpacing = UIView()
        spacerSpacing.translatesAutoresizingMaskIntoConstraints = false
        spacerSpacing.heightAnchor.constraint(equalToConstant: HassTokens.Spacing.l).isActive = true
        let footnoteGap = UIView()
        footnoteGap.translatesAutoresizingMaskIntoConstraints = false
        footnoteGap.heightAnchor.constraint(equalToConstant: HassTokens.Spacing.l).isActive = true
        column.addArrangedSubview(spacerSpacing)
        column.addArrangedSubview(middle)
        column.addArrangedSubview(footnoteGap)
        footnote.text = LoginCopy.footnote
        footnote.textColor = UIColor(rgb: HassTokens.Palette.secondaryLabel, alpha: 0.85)
        footnote.textAlignment = .center
        footnote.numberOfLines = 0
        footnote.adjustsFontForContentSizeCategory = true
        footnote.font = UKShellFont.preferred(.footnote)
        footnote.accessibilityIdentifier = "login.footnote"
        column.addArrangedSubview(footnote)

        submit.action = { [weak self] in self?.submitTapped() }
        submit.accessibilityIdentifier = "login.submit"
        differentAccount.setTitle(LoginCopy.differentAccount, for: .normal)
        differentAccount.setTitleColor(UIColor(rgb: SignInStyle.link), for: .normal)
        differentAccount.titleLabel?.font = UKShellFont.preferred(.body)
        differentAccount.titleLabel?.adjustsFontForContentSizeCategory = true
        differentAccount.titleLabel?.numberOfLines = 0
        differentAccount.accessibilityIdentifier = "login.differentAccount"
        differentAccount.heightAnchor.constraint(greaterThanOrEqualToConstant: HassTokens.minTarget).isActive = true
        differentAccount.addAction(UIAction { [weak self] _ in self?.useDifferentAccount() }, for: .touchUpInside)
        formHolder.addArrangedSubview(fields)
        formHolder.addArrangedSubview(submit)
        formHolder.addArrangedSubview(differentAccount)
        [formHolder, footnote].forEach { $0.alpha = playsIntro ? 0 : 1 }
        if playsIntro, !reduceMotion {
            [formHolder, footnote].forEach { $0.transform = CGAffineTransform(translationX: 0, y: MotionTokens.Intro.formRise) }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Centred, and moved off the hinge only where it crosses the form (unfolded Duo, landscape).
        let width = content.bounds.width
        let columnWidth = min(SignInStyle.columnWidth, width)
        let hinge = environment?.windowHinge
        let band = HingeAvoidance.band(in: view.convert(view.bounds, to: nil), hinge: hinge)
        let place = HingeAvoidance.placement(objectWidth: columnWidth, containerWidth: width, band: band)
        self.columnWidth.constant = place.width
        columnLeading.constant = place.x
    }

    // MARK: Header

    private func rebuildHeader(mode: LoginModel.Mode) {
        headerHolder.subviews.forEach { $0.removeFromSuperview() }
        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = HassTokens.Spacing.s
        stack.translatesAutoresizingMaskIntoConstraints = false
        headerHolder.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: headerHolder.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: headerHolder.trailingAnchor),
            stack.topAnchor.constraint(equalTo: headerHolder.topAnchor),
            stack.bottomAnchor.constraint(equalTo: headerHolder.bottomAnchor),
        ])
        let mark: UIView
        let titleText: String
        let subtitle: String
        switch mode {
        case .fresh:
            mark = UKSignInMarkView(icon: icon)
            titleText = LoginCopy.appName
            subtitle = LoginCopy.subtitle
        case let .welcomeBack(account):
            mark = UKSignInMonogramView(name: account.name, icon: icon)
            titleText = LoginCopy.welcomeBack(account.firstName)
            subtitle = LoginCopy.welcomeSubtitle
        }
        markView = mark
        let markHolder = UIView()
        markHolder.translatesAutoresizingMaskIntoConstraints = false
        markHolder.addSubview(mark)
        mark.centerXAnchor.constraint(equalTo: markHolder.centerXAnchor).isActive = true
        mark.topAnchor.constraint(equalTo: markHolder.topAnchor).isActive = true
        mark.bottomAnchor.constraint(equalTo: markHolder.bottomAnchor, constant: -HassTokens.Spacing.m).isActive = true
        stack.addArrangedSubview(markHolder)
        let title = UILabel()
        title.text = titleText
        title.textColor = .white
        title.textAlignment = .center
        title.numberOfLines = 0
        title.adjustsFontForContentSizeCategory = true
        title.font = UKShellFont.preferred(.largeTitle, weight: .bold)
        title.accessibilityTraits = .header
        title.accessibilityIdentifier = "login.title"
        if case .fresh = mode { title.accessibilityLabel = AppBranding.spokenName }
        let line = UILabel()
        line.text = subtitle
        line.textColor = UIColor(rgb: HassTokens.Palette.secondaryLabel, alpha: 0.85)
        line.textAlignment = .center
        line.numberOfLines = 0
        line.adjustsFontForContentSizeCategory = true
        line.font = UKShellFont.preferred(.body)
        stack.addArrangedSubview(title)
        stack.addArrangedSubview(line)
        titleViews = [title, line]
        stack.accessibilityContainerType = .semanticGroup
        if introPending {
            mark.alpha = 0
            mark.transform = CGAffineTransform(scaleX: MotionTokens.Intro.markStart, y: MotionTokens.Intro.markStart)
            titleViews.forEach { $0.alpha = 0; $0.transform = CGAffineTransform(translationX: 0, y: reduceMotion ? 0 : MotionTokens.Intro.titleRise) }
        }
    }

    private var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }

    // MARK: Fields

    private func wireFields() {
        fields.serverField.delegate = self
        fields.serverField.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            if self.model.serverText != (self.fields.serverField.text ?? "") { self.model.serverText = self.fields.serverField.text ?? "" }
        }, for: .editingChanged)
        fields.usernameField.delegate = self
        fields.passwordField.delegate = self
        fields.usernameField.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            if self.model.username != (self.fields.usernameField.text ?? "") { self.model.username = self.fields.usernameField.text ?? "" }
        }, for: .editingChanged)
        fields.passwordField.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            if self.model.password != (self.fields.passwordField.text ?? "") { self.model.password = self.fields.passwordField.text ?? "" }
        }, for: .editingChanged)
    }

    /// Return order: Server, Username, Password, Go. A welcome back has no editable Server or Username, so only Password is left.
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField === fields.serverField {
            let next = model.mode == .fresh ? fields.usernameField : fields.passwordField
            next.becomeFirstResponder()
        } else if textField === fields.usernameField {
            fields.passwordField.becomeFirstResponder()
        } else {
            submitTapped()
        }
        return false
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        guard textField === fields.serverField else { return }
        model.normalizeServerText()
    }

    private func syncFieldsFromModel() {
        if fields.serverField.text != model.serverText { fields.serverField.text = model.serverText }
        if fields.usernameField.text != model.username { fields.usernameField.text = model.username }
        if fields.passwordField.text != model.password { fields.passwordField.text = model.password }
    }

    // MARK: Binding

    private func bindModel() {
        bag.observe { [weak self] in
            guard let self else { return }
            let mode = self.model.mode
            let username = self.model.username
            let server = self.model.serverDisplay
            if self.shownMode != mode {
                let first = self.shownMode == nil
                self.shownMode = mode
                self.rebuildHeader(mode: mode)
                if !first { self.fields.usernameField.text = username; self.fields.passwordField.text = "" }
            }
            self.fields.configure(mode: mode, username: username, server: server)
            if case .welcomeBack = mode { self.differentAccount.isHidden = false } else { self.differentAccount.isHidden = true }
        }
        bag.observe { [weak self] in
            guard let self else { return }
            // The model clears and fills these (a wrong password, a different account, a debug prefill).
            let server = self.model.serverText, username = self.model.username, password = self.model.password
            if self.fields.serverField.text != server { self.fields.serverField.text = server }
            if self.fields.usernameField.text != username { self.fields.usernameField.text = username }
            if self.fields.passwordField.text != password { self.fields.passwordField.text = password }
        }
        bag.observe { [weak self] in
            guard let self else { return }
            let working = self.model.isWorking
            let enabled = self.model.canSubmit || working
            // A turning arc keeps XCUITest from ever seeing the app idle, so journeys hold it still; the label still says busy.
            self.submit.holdsSpinnerStill = ProcessInfo.processInfo.environment["FENTON_UITEST_RESET"] == "1"
            self.submit.title = self.model.buttonTitle
            self.submit.isBusy = working
            self.submit.isEnabled = enabled
            self.submit.accessibilityValue = self.model.busyValue
            // The fields dim while the request is out (owner, 2026-10-17: 50%).
            UIView.animate(withDuration: MotionTokens.quickDuration, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
                self.fields.alpha = working ? 0.5 : 1
            }
            self.fields.isUserInteractionEnabled = !working
            self.fields.serverField.isEnabled = !working
            self.fields.usernameField.isEnabled = !working
            self.fields.passwordField.isEnabled = !working
        }
        bag.observe { [weak self] in
            guard let self else { return }
            self.showFailure(self.model.failure)
        }
        bag.observe { [weak self] in
            guard let self else { return }
            let token = self.model.serverFocusToken
            guard self.didAppearOnce, token > 0 else { return }
            // Back to the address that is wrong, with its text kept.
            DispatchQueue.main.async { [weak self] in
                self?.fields.serverField.isEnabled = true
                self?.fields.serverField.becomeFirstResponder()
            }
        }
        bag.observe { [weak self] in
            guard let self else { return }
            let token = self.model.passwordFocusToken
            guard self.didAppearOnce, token > 0 else { return }
            // The fields are off while the request is out: focus once they are back.
            DispatchQueue.main.async { [weak self] in
                self?.fields.passwordField.isEnabled = true
                self?.fields.passwordField.becomeFirstResponder()
            }
        }
    }

    private func showFailure(_ failure: LoginModel.Failure?) {
        let changed = failure != lastFailure
        let hadFailure = lastFailure != nil
        lastFailure = failure
        fields.setPasswordRefused(failure == .wrongCredentials)
        fields.setServerRefused(failure?.refusesServer ?? false)
        guard changed else { return }
        cardView?.removeFromSuperview()
        errorView?.removeFromSuperview()
        cardView = nil
        errorView = nil
        if let failure, let title = failure.cardTitle, let message = failure.cardBody {
            let card = UKLoginFailureCardView(title: title, message: message, detail: failure.detail)
            formHolder.insertArrangedSubview(card, at: 0)
            cardView = card
        }
        if let failure, let message = failure.inlineMessage {
            let error = UKLoginInlineErrorView(message: message)
            formHolder.insertArrangedSubview(error, at: formHolder.arrangedSubviews.firstIndex(of: fields).map { $0 + 1 } ?? 1)
            errorView = error
        }
        if didAppearOnce {
            UIView.animate(withDuration: MotionTokens.quickDuration, delay: 0, options: .curveEaseOut) { self.view.layoutIfNeeded() }
        }
        if let failure {
            Announcer.announce(failure.announcement)
            // A refused password plays the error pattern too (owner, 2026-10-24).
            if !hadFailure { UINotificationFeedbackGenerator().notificationOccurred(.error) }
        }
    }

    // MARK: Actions

    private func submitTapped() {
        view.endEditing(true)
        let signedIn = onSignedIn
        model.submit { server, tokens in try signedIn(server, tokens) }
    }

    private func useDifferentAccount() {
        UIView.animate(withDuration: MotionTokens.quickDuration, delay: 0, options: .curveEaseOut) {
            self.model.useDifferentAccount()
        }
        onUseDifferentAccount()
    }

    /// Debug builds only: `FENTON_AUTOSIGNIN=1` presses Sign In by itself once the prefilled fields are in (after
    /// `FENTON_AUTOSIGNIN_DELAY` seconds, 2.5 by default), so a launch cost run signs in with no test driving the app.
    private func signInByItself() {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        guard environment["FENTON_AUTOSIGNIN"] == "1" else { return }
        let delay = environment["FENTON_AUTOSIGNIN_DELAY"].flatMap(Double.init) ?? 2.5
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            self?.submitTapped()
        }
        #endif
    }

    // MARK: Intro

    /// The launch sequence, about 1.2 s (owner, 2026-10-17): the glow fades up, the mark springs in (0.86 to 1.03 to 1), the
    /// title and subtitle fade up 10 pt, then the form rises 28 pt. Reduce Motion shows the same pieces in one 0.35 s
    /// cross-fade. No keyboard comes up by itself.
    private func playIntro() {
        guard playsIntro, introPending else { return }
        introPending = false
        onIntroPlayed()
        Telemetry.beginTracked(Telemetry.Name.intro)
        let mark = markView
        let titles = titleViews
        let form = [formHolder, footnote]
        if reduceMotion {
            UIView.animate(withDuration: MotionTokens.crossFadeDuration, delay: 0, options: .curveEaseInOut, animations: {
                self.ground.glowAlpha = 1
                mark?.alpha = 1
                mark?.transform = .identity
                titles.forEach { $0.alpha = 1; $0.transform = .identity }
                form.forEach { $0.alpha = 1; $0.transform = .identity }
            }, completion: { _ in Telemetry.endTracked(Telemetry.Name.intro) })
            return
        }
        // One timeline, each piece delayed on its own animation; the mark settles when its rise completes.
        UIView.animate(withDuration: 0.5, delay: 0, options: .curveEaseOut) { self.ground.glowAlpha = 1 }
        UIView.animate(withDuration: MotionTokens.Intro.markRiseDuration, delay: MotionTokens.Intro.markDelay, options: .curveEaseOut, animations: {
            mark?.alpha = 1
            mark?.transform = CGAffineTransform(scaleX: MotionTokens.Intro.markPeak, y: MotionTokens.Intro.markPeak)
        }, completion: { _ in
            UIView.animate(springDuration: 0.5, bounce: 0.2) { mark?.transform = .identity }
        })
        UIView.animate(withDuration: 0.4, delay: MotionTokens.Intro.titleDelay, options: .curveEaseOut) {
            titles.forEach { $0.alpha = 1; $0.transform = .identity }
        }
        UIView.animate(withDuration: 0.45, delay: MotionTokens.Intro.formDelay, options: .curveEaseOut, animations: {
            form.forEach { $0.alpha = 1; $0.transform = .identity }
        }, completion: { _ in Telemetry.endTracked(Telemetry.Name.intro) })
    }
}
#endif
