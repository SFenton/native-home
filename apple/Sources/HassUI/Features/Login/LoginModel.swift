import Foundation
import HassCore
import HassTelemetry
import Observation

/// What the sign-in screen holds and does: the three fields, the in-flight state, what went wrong, and the Home Assistant login
/// flow behind Sign In (kept apart from ``LoginView`` so the flow is tested without a window).
///
/// The first field is the server address (owner, 2026-11-06; `.agents/design/house-config-states.md`, rules 1 to 9): what is typed
/// is normalised by ``HassServerAddress`` before it is used. There is no second step: an account with two-step sign-in turned on
/// is told to turn it off rather than shown a code field nobody has used.
@MainActor
@Observable
final class LoginModel {
    /// Which sign-in this is.
    enum Mode: Equatable {
        /// A new sign-in: username and password.
        case fresh
        /// The session ended: the account is known, so only the password is asked for.
        case welcomeBack(RememberedAccount)
    }

    /// What went wrong, in the words the screen uses.
    enum Failure: Equatable {
        /// Home Assistant said no to the username or password.
        case wrongCredentials
        /// The server could not be reached (offline, restarting, a gateway error). `detail` is the raw reason.
        case unreachable(detail: String)
        /// Anything else. `detail` is the raw reason.
        case failed(detail: String)
        /// The account asks for a second step, which the app does not do.
        case twoStepUnsupported
        /// The server address does not parse (or is plain `http://` to a host that is not local). Never reaches the network.
        case badAddress
        /// Something answered at the address, but it is not Home Assistant.
        case notHomeAssistant

        /// The red line under the fields, for the failures that sit beside them rather than in a card.
        var inlineMessage: String? {
            switch self {
            case .wrongCredentials: LoginCopy.wrongCredentials
            case .twoStepUnsupported: LoginCopy.twoStepUnsupported
            case .badAddress: LoginCopy.badAddress
            case .notHomeAssistant: LoginCopy.notHomeAssistant
            case .unreachable, .failed: nil
            }
        }

        /// Whether the red hairline goes round the Server row (the address is what is wrong). Unreachable does not: the
        /// address may be right.
        var refusesServer: Bool { self == .badAddress || self == .notHomeAssistant }

        /// The card's title, for the failures that get one.
        var cardTitle: String? {
            switch self {
            case .unreachable: LoginCopy.unreachableTitle
            case .failed: LoginCopy.failedTitle
            case .wrongCredentials, .twoStepUnsupported, .badAddress, .notHomeAssistant: nil
            }
        }

        /// The card's plain-words body.
        var cardBody: String? {
            switch self {
            case .unreachable: LoginCopy.unreachableBody
            case .failed: LoginCopy.failedBody
            case .wrongCredentials, .twoStepUnsupported, .badAddress, .notHomeAssistant: nil
            }
        }

        /// The raw reason behind a card, for its Details.
        var detail: String? {
            switch self {
            case let .unreachable(detail), let .failed(detail): detail.isEmpty ? nil : detail
            case .wrongCredentials, .twoStepUnsupported, .badAddress, .notHomeAssistant: nil
            }
        }

        /// What VoiceOver announces when the failure appears.
        var announcement: String {
            inlineMessage ?? [cardTitle, cardBody].compactMap { $0 }.joined(separator: ". ")
        }
    }

    /// Which sign-in this is; changes to ``Mode/fresh`` when the person picks a different account.
    private(set) var mode: Mode
    /// What the Server field holds: prefilled (see ``prefilledServer(store:defaultServer:)``), normalised once it ends editing.
    var serverText: String
    /// The account name.
    var username: String
    /// The password. Cleared once sign-in succeeds or is refused; never stored.
    var password = ""
    /// Whether a request is in flight.
    private(set) var isWorking = false
    /// What went wrong, for the screen to show.
    private(set) var failure: Failure?
    /// Bumped when the password field should take focus (after a refusal).
    private(set) var passwordFocusToken = 0
    /// Bumped when the Server field should take focus (after a bad address or an answer that is not Home Assistant).
    private(set) var serverFocusToken = 0

    @ObservationIgnored private let makeFlow: (HassServer) -> HassLoginFlow
    @ObservationIgnored private let store: RememberedAccountStore

    /// Creates the model.
    /// - Parameters:
    ///   - mode: A fresh sign-in, or a welcome back for an account whose session ended.
    ///   - store: Where the last username and server are kept; a fresh sign-in starts with them filled in.
    ///   - defaultServer: The build's `HASS_DEFAULT_SERVER`, used when no server is remembered; nil for none.
    ///   - environment: The launch environment; debug builds read `FENTON_HASS_SERVER` from it before the model decides welcome back or fresh.
    ///   - makeFlow: Builds the login flow for the server; tests pass one on a stubbed session.
    init(mode: Mode = .fresh, store: RememberedAccountStore = RememberedAccountStore(),
         defaultServer: String? = LoginModel.buildDefaultServer,
         environment: [String: String] = LaunchEnvironment.current,
         makeFlow: @escaping (HassServer) -> HassLoginFlow = LoginModel.defaultFlow) {
        self.store = store
        self.makeFlow = makeFlow
        let prefilled = Self.prefilledServer(store: store, defaultServer: defaultServer, environment: environment)
        serverText = prefilled
        switch mode {
        case let .welcomeBack(account) where Self.isUsable(server: prefilled):
            self.mode = mode
            username = account.username
        case let .welcomeBack(account):
            // The read-only Server row would be empty and Sign In could never turn on: show the editable form instead.
            self.mode = .fresh
            username = account.username
        case .fresh:
            self.mode = .fresh
            username = store.username ?? ""
        }
    }

    /// The server the build ships with (Info.plist `HASS_DEFAULT_SERVER`), if any.
    nonisolated static var buildDefaultServer: String? {
        HassServer.buildDefault().map { HassServerAddress.displayText(for: $0) }
    }

    /// The Server field's starting text: the last server signed in to, else the build's default, else empty. Debug builds put
    /// `FENTON_HASS_SERVER` above both.
    nonisolated static func prefilledServer(store: RememberedAccountStore, defaultServer: String?,
                                            environment: [String: String] = [:]) -> String {
        #if DEBUG
        if let value = environment["FENTON_HASS_SERVER"], !value.isEmpty { return value }
        #endif
        if let remembered = store.server { return HassServerAddress.displayText(for: remembered) }
        return defaultServer ?? ""
    }

    /// Whether a prefilled server can be shown read-only on welcome back.
    nonisolated static func isUsable(server text: String) -> Bool {
        if case .success = HassServerAddress.parse(text) { return true }
        return false
    }

    /// The flow for the real server; debug builds can ask for a canned one (`FENTON_SIGNIN_STUB`, see ``DebugSignInStub``).
    nonisolated static func defaultFlow(_ server: HassServer) -> HassLoginFlow {
        #if DEBUG
        if let session = DebugSignInStub.session() { return HassLoginFlow(server: server, session: session) }
        #endif
        return HassLoginFlow(server: server)
    }

    // MARK: Reading

    /// Whether Sign In can be pressed: all three fields are filled.
    var canSubmit: Bool {
        !isWorking && !serverText.trimmingCharacters(in: .whitespaces).isEmpty
            && !username.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty
    }

    /// The server as it reads in the read-only row: host and port, without the scheme. The typed text when it does not parse.
    var serverDisplay: String {
        guard case let .success(server) = HassServerAddress.parse(serverText) else { return serverText }
        return HassServerAddress.displayText(for: server, includesScheme: false)
    }

    /// The primary button's words: Sign In, Signing In… while a request is out, Try Again after the server could not be
    /// reached or the sign-in failed (the fields keep their values).
    var buttonTitle: String {
        if isWorking { return LoginCopy.busyTitle }
        switch failure {
        case .unreachable, .failed: return LoginCopy.retryTitle
        case .wrongCredentials, .twoStepUnsupported, .badAddress, .notHomeAssistant, nil: return LoginCopy.signInTitle
        }
    }

    /// What the primary button says is happening, for VoiceOver (the spinner is silent).
    var busyValue: String { isWorking ? "Signing In" : "" }

    // MARK: Actions

    /// Starts sign-in and returns the task, so a test can wait for it.
    /// - Parameter onSignedIn: Called with fresh tokens on success.
    @discardableResult
    func submit(onSignedIn: @escaping @MainActor (HassServer, AuthTokens) throws -> Void) -> Task<Void, Never>? {
        guard canSubmit else { return nil }
        guard case let .success(server) = HassServerAddress.parse(serverText) else {
            // A bad address never reaches the network.
            show(.badAddress)
            return nil
        }
        serverText = HassServerAddress.displayText(for: server)
        isWorking = true
        failure = nil
        Telemetry.beginTracked(Telemetry.Name.signIn)
        return Task { await run(server: server, onSignedIn: onSignedIn) }
    }

    /// The Server field ended editing: show the normalised address in place, or the bad-address line.
    func normalizeServerText() {
        let trimmed = serverText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            if failure == .badAddress { failure = nil }
            return
        }
        switch HassServerAddress.parse(trimmed) {
        case let .success(server):
            serverText = HassServerAddress.displayText(for: server)
            if failure == .badAddress { failure = nil }
        case .failure:
            serverText = trimmed
            show(.badAddress)
        }
    }

    /// Drops the remembered account and asks for a username as well (Use a Different Account). The server stays.
    func useDifferentAccount() {
        store.forget()
        mode = .fresh
        username = ""
        password = ""
        failure = nil
    }

    /// Shows a failure; the ones about the address also ask for focus in the Server field when they first appear.
    private func show(_ new: Failure) {
        let changed = failure != new
        failure = new
        if new.refusesServer, changed { serverFocusToken += 1 }
    }

    private func run(server: HassServer, onSignedIn: @MainActor (HassServer, AuthTokens) throws -> Void) async {
        defer { isWorking = false }
        let name = username.trimmingCharacters(in: .whitespaces)
        do {
            switch try await makeFlow(server).signIn(username: name, password: password) {
            case .needsMFACode:
                Telemetry.cancelTracked(Telemetry.Name.signIn)
                failure = .twoStepUnsupported
            case let .signedIn(tokens):
                Telemetry.endTracked(Telemetry.Name.signIn)
                password = ""
                store.remember(username: name)
                store.remember(server: server)
                // Home has until the end of the arrival animation (RootView ends it).
                Telemetry.beginTracked(Telemetry.Name.arrival)
                do {
                    try onSignedIn(server, tokens)
                } catch {
                    Telemetry.cancelTracked(Telemetry.Name.arrival)
                    failure = .failed(detail: error.localizedDescription)
                }
            }
        } catch {
            Telemetry.cancelTracked(Telemetry.Name.signIn)
            show(Self.failure(for: error))
            if failure == .wrongCredentials {
                // A wrong password is retyped from nothing; the username stays.
                password = ""
                passwordFocusToken += 1
            }
        }
    }

    /// How an error from the login flow reads on the screen.
    static func failure(for error: any Error) -> Failure {
        guard let error = error as? HassLoginFlow.LoginError else { return .failed(detail: error.localizedDescription) }
        switch error {
        case .invalidCredentials: return .wrongCredentials
        case let .network(detail): return .unreachable(detail: detail)
        case let .unexpectedResponse(detail): return .failed(detail: detail)
        case .invalidCode: return .failed(detail: "invalid code")
        case .notHomeAssistant: return .notHomeAssistant
        }
    }

    /// Debug builds only: prefill from launch environment so automated test runs can sign in without
    /// credentials in the repo. Set `FENTON_HASS_USERNAME` / `FENTON_HASS_PASSWORD` in a local,
    /// uncommitted scheme or via `simctl launch` environment. `FENTON_HASS_SERVER` points a journey at another server.
    func prefillForDebugTesting(_ environment: [String: String] = LaunchEnvironment.current) {
        #if DEBUG
        if let value = environment["FENTON_HASS_USERNAME"] { username = value }
        if let value = environment["FENTON_HASS_PASSWORD"] { password = value }
        #endif
    }
}
