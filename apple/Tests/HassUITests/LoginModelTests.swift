import Foundation
import HassCore
@testable import HassUI
import Testing

/// What the sign-in model does with the Server field: when Sign In is allowed, what the field starts with, a bad address that
/// never reaches the network, how login-flow errors read, and what welcome back keeps.
@MainActor
struct LoginModelTests {
    private let defaults = UserDefaults(suiteName: "LoginModelTests-\(UUID().uuidString)")!

    private var store: RememberedAccountStore { RememberedAccountStore(defaults: defaults) }

    /// A model whose flow answers from the debug stub; `flows` counts the flows it made (one per request that reached the network).
    private func model(stub: String = "success", mode: LoginModel.Mode = .fresh, defaultServer: String? = nil,
                       environment: [String: String] = [:], flows: FlowCounter = FlowCounter()) -> LoginModel {
        LoginModel(mode: mode, store: store, defaultServer: defaultServer, environment: environment, makeFlow: { server in
            flows.count += 1
            flows.lastServer = server
            return HassLoginFlow(server: server, session: DebugSignInStub.session(["FENTON_SIGNIN_STUB": stub]) ?? .shared)
        })
    }

    /// Waits (at most five seconds) for the request to finish.
    private func finish(_ model: LoginModel) async {
        let deadline = ContinuousClock.now + .seconds(5)
        while model.isWorking, ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(20)) }
    }

    private func fill(_ model: LoginModel, server: String = "ha.example.com") {
        model.serverText = server
        model.username = "alex"
        model.password = "secret"
    }

    // MARK: Sign In is allowed

    @Test func signInNeedsAllThreeFields() {
        let model = model()
        #expect(!model.canSubmit)
        model.serverText = "ha.example.com"
        model.username = "alex"
        #expect(!model.canSubmit, "a password is needed too")
        model.password = "secret"
        #expect(model.canSubmit)
        model.serverText = "   "
        #expect(!model.canSubmit, "a blank server is no server")
        model.serverText = "ha.example.com"
        model.username = " "
        #expect(!model.canSubmit)
    }

    // MARK: Prefill

    @Test func prefillIsTheRememberedServerThenTheBuildDefaultThenEmpty() {
        #expect(model().serverText.isEmpty)
        #expect(model(defaultServer: "https://default.example.com").serverText == "https://default.example.com")
        store.remember(server: HassServer(baseURL: URL(string: "http://homeassistant.local:8123")!))
        #expect(model(defaultServer: "https://default.example.com").serverText == "http://homeassistant.local:8123",
                "the remembered server beats the build's")
    }

    @Test func theLaunchEnvironmentBeatsBothInDebugBuilds() {
        store.remember(server: HassServer(baseURL: URL(string: "https://remembered.example.com")!))
        let model = model(defaultServer: "https://default.example.com", environment: ["FENTON_HASS_SERVER": "http://192.0.2.10:8123"])
        #expect(model.serverText == "http://192.0.2.10:8123")
        let plain = self.model(defaultServer: "https://default.example.com", environment: ["FENTON_HASS_SERVER": ""])
        #expect(plain.serverText == "https://remembered.example.com", "an empty variable changes nothing")
    }

    @Test func welcomeBackWithOnlyTheDebugServerKeepsTheWelcomeBackForm() {
        let account = RememberedAccount(username: "alex", name: "Alex")
        let model = model(mode: .welcomeBack(account), environment: ["FENTON_HASS_SERVER": "https://ha.example.com"])
        #expect(model.mode == .welcomeBack(account))
        #expect(model.serverText == "https://ha.example.com")
        #expect(model.serverDisplay == "ha.example.com")
    }

    @Test func theBuildDefaultComesFromTheInfoPlistKey() {
        #expect(HassServer.buildDefault(info: ["HASS_DEFAULT_SERVER": "https://ha.example.com/"])?.baseURL.absoluteString == "https://ha.example.com")
        #expect(HassServer.buildDefault(info: ["HASS_DEFAULT_SERVER": ""]) == nil, "an unset variable leaves the field blank")
        #expect(HassServer.buildDefault(info: ["HASS_DEFAULT_SERVER": "not a url"]) == nil)
        #expect(HassServer.buildDefault(info: ["HASS_DEFAULT_SERVER": "ha.example.com"])?.baseURL.absoluteString == "https://ha.example.com",
                "no scheme: the sign-in field's own rule")
        #expect(HassServer.buildDefault(info: ["HASS_DEFAULT_SERVER": "https://ha.example.com\n"])?.baseURL.absoluteString == "https://ha.example.com",
                "a trailing newline from the variable")
        #expect(HassServer.buildDefault(info: [:]) == nil)
        #expect(HassServer.buildDefault(info: nil) == nil)
    }

    @Test func aBuildWithNoDefaultStartsWithABlankServerField() {
        let fromBuild = HassServer.buildDefault(info: ["HASS_DEFAULT_SERVER": ""])?.baseURL.absoluteString
        let text = model(defaultServer: fromBuild).serverText
        #expect(text.isEmpty)
    }

    // MARK: Normalising and a bad address

    @Test func endingEditingNormalisesTheTextInPlace() {
        let model = model()
        model.serverText = "  HomeAssistant.local:8123/lovelace "
        model.normalizeServerText()
        #expect(model.serverText == "http://homeassistant.local:8123")
        #expect(model.failure == nil)
    }

    @Test func endingEditingWithABadAddressShowsTheLineAndAsksForFocusOnce() {
        let model = model()
        model.serverText = "http://ha.example.com"
        model.normalizeServerText()
        #expect(model.failure == .badAddress)
        #expect(model.failure?.inlineMessage == LoginCopy.badAddress)
        #expect(model.failure?.refusesServer == true)
        #expect(model.serverText == "http://ha.example.com", "the text is kept")
        #expect(model.serverFocusToken == 1)
        model.normalizeServerText()
        #expect(model.serverFocusToken == 1, "the same failure does not steal focus again")
        model.serverText = "ha.example.com"
        model.normalizeServerText()
        #expect(model.failure == nil, "a good address clears the line")
    }

    @Test func anEmptyServerEndsEditingQuietly() {
        let model = model()
        model.normalizeServerText()
        #expect(model.failure == nil)
    }

    @Test func aBadAddressMakesNoRequest() {
        let flows = FlowCounter()
        let model = model(flows: flows)
        fill(model, server: "ha example")
        #expect(model.submit { _, _ in } == nil)
        #expect(flows.count == 0, "nothing left the phone")
        #expect(!model.isWorking)
        #expect(model.failure == .badAddress)
        #expect(model.serverFocusToken == 1)
        #expect(model.buttonTitle == LoginCopy.signInTitle)
    }

    @Test func plainHTTPToARemoteHostIsABadAddress() {
        let flows = FlowCounter()
        let model = model(flows: flows)
        fill(model, server: "http://ha.example.com")
        #expect(model.submit { _, _ in } == nil)
        #expect(model.failure == .badAddress && flows.count == 0)
    }

    // MARK: Signing in

    @Test func signingInUsesTheNormalisedServerAndRemembersIt() async {
        let flows = FlowCounter()
        let model = model(flows: flows)
        fill(model, server: "homeassistant.local")
        var signedInTo: HassServer?
        model.submit { server, _ in signedInTo = server }
        await finish(model)
        #expect(flows.lastServer?.baseURL.absoluteString == "http://homeassistant.local")
        #expect(signedInTo?.baseURL.absoluteString == "http://homeassistant.local")
        #expect(store.server == signedInTo)
        #expect(store.username == "alex")
        #expect(model.serverText == "http://homeassistant.local", "the field shows the normalised address")
    }

    @Test func aFailedSignInDoesNotRememberTheServer() async {
        let model = model(stub: "wrong")
        fill(model)
        model.submit { _, _ in }
        await finish(model)
        #expect(model.failure == .wrongCredentials)
        #expect(store.server == nil)
        #expect(model.serverFocusToken == 0)
        #expect(model.failure?.refusesServer == false)
    }

    @Test func anAnswerThatIsNotHomeAssistantRefusesTheServer() async {
        let model = model(stub: "nothomeassistant")
        fill(model)
        model.submit { _, _ in }
        await finish(model)
        #expect(model.failure == .notHomeAssistant)
        #expect(model.failure?.inlineMessage == LoginCopy.notHomeAssistant)
        #expect(model.failure?.refusesServer == true)
        #expect(model.failure?.cardTitle == nil)
        #expect(model.serverFocusToken == 1)
        #expect(model.password == "secret", "only a refused password is cleared")
        #expect(store.server == nil)
    }

    @Test func unreachableKeepsTheCardWithoutAServerHairline() async {
        let model = model(stub: "unreachable")
        fill(model)
        model.submit { _, _ in }
        await finish(model)
        guard case .unreachable = model.failure else { Issue.record("expected unreachable, got \(String(describing: model.failure))"); return }
        #expect(model.failure?.refusesServer == false)
        #expect(model.failure?.cardTitle == "Can't reach Home Assistant")
        #expect(model.failure?.cardBody == LoginCopy.unreachableBody)
        #expect(model.buttonTitle == LoginCopy.retryTitle)
        #expect(model.serverFocusToken == 0)
    }

    // MARK: Error mapping

    @Test func loginFlowErrorsMapToFailures() {
        #expect(LoginModel.failure(for: HassLoginFlow.LoginError.invalidCredentials) == .wrongCredentials)
        #expect(LoginModel.failure(for: HassLoginFlow.LoginError.notHomeAssistant) == .notHomeAssistant)
        #expect(LoginModel.failure(for: HassLoginFlow.LoginError.network("offline")) == .unreachable(detail: "offline"))
        #expect(LoginModel.failure(for: HassLoginFlow.LoginError.unexpectedResponse("x")) == .failed(detail: "x"))
        #expect(LoginModel.failure(for: HassLoginFlow.LoginError.invalidCode) == .failed(detail: "invalid code"))
    }

    @Test func theAddressFailuresAreAnnouncedAsTheirLine() {
        #expect(LoginModel.Failure.badAddress.announcement == LoginCopy.badAddress)
        #expect(LoginModel.Failure.notHomeAssistant.announcement == LoginCopy.notHomeAssistant)
        #expect(LoginModel.Failure.badAddress.detail == nil && LoginModel.Failure.notHomeAssistant.cardBody == nil)
    }

    // MARK: Welcome back

    @Test func welcomeBackStartsWithTheRememberedServerAndUsername() {
        store.remember(server: HassServer(baseURL: URL(string: "https://ha.example.com:8443")!))
        let model = model(mode: .welcomeBack(RememberedAccount(username: "alex", name: "Alex")))
        #expect(model.serverText == "https://ha.example.com:8443")
        #expect(model.username == "alex")
        #expect(model.serverDisplay == "ha.example.com:8443", "the read-only row shows host and port without the scheme")
        model.password = "secret"
        #expect(model.canSubmit, "only the password is left to type")
    }

    @Test func welcomeBackWithNoUsableServerFallsBackToTheEditableForm() {
        let model = model(mode: .welcomeBack(RememberedAccount(username: "alex", name: "Alex")))
        #expect(model.mode == .fresh, "an empty read-only Server row could never be filled")
        #expect(model.serverText.isEmpty)
        #expect(model.username == "alex", "the username is still filled in")
        model.serverText = "ha.example.com"
        model.password = "secret"
        #expect(model.canSubmit)
        let withDefault = LoginModel(mode: .welcomeBack(RememberedAccount(username: "alex")), store: store,
                                     defaultServer: "https://default.example.com")
        #expect(withDefault.mode == .welcomeBack(RememberedAccount(username: "alex")), "a build default is usable")
    }

    @Test func aDifferentAccountKeepsTheServerAndClearsTheUsername() {
        store.remember(username: "alex")
        store.remember(server: HassServer(baseURL: URL(string: "https://ha.example.com")!))
        let model = model(mode: .welcomeBack(RememberedAccount(username: "alex")))
        model.password = "secret"
        model.useDifferentAccount()
        #expect(model.mode == .fresh)
        #expect(model.serverText == "https://ha.example.com")
        #expect(model.username.isEmpty && model.password.isEmpty)
        #expect(store.server?.baseURL.absoluteString == "https://ha.example.com")
        #expect(store.username == nil)
    }

    @Test func theServerRowReadsHostAndPortOrTheTypedText() {
        let model = model()
        model.serverText = "https://ha.example.com/"
        #expect(model.serverDisplay == "ha.example.com")
        model.serverText = "not an address"
        #expect(model.serverDisplay == "not an address")
    }
}

/// Counts the login flows a model builds, and keeps the last server it was given.
@MainActor
final class FlowCounter {
    var count = 0
    var lastServer: HassServer?
}
