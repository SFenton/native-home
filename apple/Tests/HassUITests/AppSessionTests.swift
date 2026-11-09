import Foundation
import HassCore
import HassDemoHouse
@testable import HassUI
import Testing

/// What the signed-in session does with sign-in, a refused token and sign-out. Connections point at a closed local port, so
/// nothing leaves the machine.
@MainActor
@Suite(.serialized, .hosted)
struct AppSessionTests {
    private static let server = HassServer(baseURL: URL(string: "http://127.0.0.1:1")!)
    private static let tokens = AuthTokens(accessToken: "access", expiresAt: .distantFuture, refreshToken: "refresh")

    private let defaults: UserDefaults
    private let store = InMemoryTokenStore()
    private let houseURL = FileManager.default.temporaryDirectory.appending(path: "session-house-\(UUID()).json")

    init() {
        defaults = UserDefaults(suiteName: "AppSessionTests-\(UUID().uuidString)")!
    }

    private func session(store: (any TokenStore)? = nil, buildDefault: HassServer? = nil) -> AppSession {
        AppSession(tokenStore: store ?? self.store,
                   snapshotCache: EntitySnapshotCache(fileURL: FileManager.default.temporaryDirectory.appending(path: "session-\(UUID()).json")),
                   houseConfigCache: HouseConfigCache(fileURL: houseURL),
                   motion: MotionPolicy(reduceMotion: { false }),
                   remembered: RememberedAccountStore(defaults: defaults),
                   buildDefault: buildDefault)
    }

    @Test func startsSignedOutWithNothingSaved() {
        let session = session()
        #expect(!session.isSignedIn && session.tokens == nil && session.expiredAccount == nil)
        #expect(!session.motion.hasPlayed(.signInArrival))
    }

    @Test func aSavedSignInResumesWithoutPlayingTheArrival() throws {
        try store.save(StoredCredentials(server: Self.server, refreshToken: "saved"))
        let session = session()
        #expect(session.isSignedIn && session.tokens != nil)
        #expect(session.motion.hasPlayed(.signInArrival), "Nothing introduces the app to someone already in it")
        session.signOut()
    }

    /// Fails if: a session with a saved sign-in starts on the build's server instead of the Keychain's (the build default is
    /// injected into the session, so the wrong source would show in the connection's server).
    @Test func aSavedSignInKeepsItsServerEvenWhenTheBuildNamesAnotherServer() throws {
        let stored = HassServer(baseURL: URL(string: "http://127.0.0.1:2")!)
        try store.save(StoredCredentials(server: stored, refreshToken: "saved"))
        let buildDefault = HassServer.buildDefault(info: ["HASS_DEFAULT_SERVER": "http://127.0.0.1:3"])
        #expect(buildDefault != nil && buildDefault != stored, "a build that names another server")
        let session = session(buildDefault: buildDefault)
        guard case let .signedIn(connection, _) = session.phase else { Issue.record("not signed in"); return }
        #expect(connection.server == stored && connection.server != buildDefault, "the Keychain server wins over the build's")
        #expect(store.load()?.server == stored)
        session.signOut()
    }

    @Test func signingInSavesTheRefreshTokenAndSigningOutClearsIt() throws {
        let session = session()
        try session.didSignIn(server: Self.server, tokens: Self.tokens)
        #expect(session.isSignedIn && session.tokens != nil)
        #expect(store.load() == StoredCredentials(server: Self.server, refreshToken: "refresh"))
        session.signOut()
        #expect(!session.isSignedIn && session.tokens == nil && store.load() == nil)
        #expect(session.motion.played.isEmpty, "A second sign-in plays its arrival again")
    }

    @Test func signingInStartsTheHouseConfigStoreAndSigningOutClearsItAndItsCache() throws {
        let session = session()
        #expect(session.houseConfig == nil)
        try session.didSignIn(server: Self.server, tokens: Self.tokens)
        let houseConfig = try #require(session.houseConfig)
        #expect(houseConfig.status == .loading)
        try HouseConfigCache(fileURL: houseURL).save(DemoHouse.config, hash: "h", server: Self.server)
        session.signOut()
        #expect(session.houseConfig == nil)
        #expect(houseConfig.status == .idle && houseConfig.current == nil)
        #expect(!FileManager.default.fileExists(atPath: houseURL.path))
    }

    @Test func aRefusedTokenEndsTheSessionAndRemembersWhoItWas() throws {
        RememberedAccountStore(defaults: defaults).remember(username: "alex")
        defaults.set("Alex Demo", forKey: RememberedAccountStore.nameKey)
        let session = session()
        try session.didSignIn(server: Self.server, tokens: Self.tokens)
        session.connectionStatusChanged(.connecting)
        #expect(session.isSignedIn, "Other statuses are the connection's own business")
        session.connectionStatusChanged(.rejected)
        #expect(!session.isSignedIn && store.load() == nil)
        #expect(session.expiredAccount == RememberedAccount(username: "alex", name: "Alex Demo"))
        #expect(session.motion.hasPlayed(.intro) && !session.motion.hasPlayed(.signInArrival))
    }

    @Test func useADifferentAccountForgetsTheExpiredOne() throws {
        RememberedAccountStore(defaults: defaults).remember(username: "alex")
        let session = session()
        try session.didSignIn(server: Self.server, tokens: Self.tokens)
        session.sessionExpired()
        #expect(session.expiredAccount?.username == "alex")
        session.forgetExpiredAccount()
        #expect(session.expiredAccount == nil && RememberedAccountStore(defaults: defaults).username == nil)
    }

    @Test func aRefusedTokenWithNoRememberedUsernameShowsThePlainSignIn() throws {
        let session = session()
        try session.didSignIn(server: Self.server, tokens: Self.tokens)
        session.sessionExpired()
        #expect(session.expiredAccount == nil)
    }

    @Test func signingInAgainClearsTheExpiredAccount() throws {
        RememberedAccountStore(defaults: defaults).remember(username: "alex")
        let session = session()
        try session.didSignIn(server: Self.server, tokens: Self.tokens)
        session.sessionExpired()
        try session.didSignIn(server: Self.server, tokens: Self.tokens)
        #expect(session.expiredAccount == nil && session.isSignedIn)
        session.signOut()
    }

    @Test func voiceOverIsToldWhyTheScreenChanged() {
        #expect(AppSession.expiredAnnouncement(RememberedAccount(username: "s", name: "Alex")) == "Your session ended. Welcome back, Alex. Sign in again to continue.")
        #expect(AppSession.expiredAnnouncement(RememberedAccount(username: "s", name: "")) == "Your session ended. Sign in again to continue.")
        #expect(AppSession.expiredAnnouncement(RememberedAccount(username: "s")) == "Your session ended. Sign in again to continue.")
        #expect(AppSession.expiredAnnouncement(nil) == "Your session ended. Sign in again to continue.")
    }

    @Test func aConfirmedSignOutWithoutPresenceLinkingSignsOut() async throws {
        let session = session()
        try session.didSignIn(server: Self.server, tokens: Self.tokens)
        try await session.confirmedSignOut()
        #expect(!session.isSignedIn)
        try await session.confirmedSignOut() // Already signed out: still fine.
    }

    @Test func pushRegistrationUsesTheSessionsAccessToken() async throws {
        let transport = StubHTTPTransport([(200, #"{"available":true,"push_url":"https://relay/api/fenton_home/apns","bundle_id":"com.sfenton.home"}"#),
                                           (201, #"{"webhook_id":"w1"}"#)])
        let push = PushCoordinator(platform: .inert, store: InMemoryMobileAppRegistrationStore(), transport: transport,
                                   defaults: defaults)
        let session = AppSession(tokenStore: store,
                                 snapshotCache: EntitySnapshotCache(fileURL: FileManager.default.temporaryDirectory.appending(path: "session-\(UUID()).json")),
                                 houseConfigCache: HouseConfigCache(fileURL: houseURL), push: push,
                                 motion: MotionPolicy(reduceMotion: { false }),
                                 remembered: RememberedAccountStore(defaults: defaults))
        try session.didSignIn(server: Self.server, tokens: Self.tokens)
        await push.didRegister(deviceToken: Data([0xAB]))
        await push.didConnect(userID: "u1")
        let first = try #require(transport.requests.first)
        #expect(first.value(forHTTPHeaderField: "Authorization") == "Bearer access", "Home Assistant is asked with the session's own token")
        session.signOut()
    }

    @Test func aFailedConfirmationLeavesTheSessionSignedIn() async throws {
        let session = session()
        try session.didSignIn(server: Self.server, tokens: Self.tokens)
        setenv("FENTON_SIGNOUT_FAIL", "1", 1)
        defer { unsetenv("FENTON_SIGNOUT_FAIL") }
        await #expect(throws: AppSession.SignOutFailure.self) { try await session.confirmedSignOut() }
        #expect(session.isSignedIn)
        unsetenv("FENTON_SIGNOUT_FAIL")
        session.signOut()
    }

    // MARK: Launch switches (Debug builds)

    private func withEnvironment(_ values: [String: String], _ body: () -> Void) async {
        await AsyncLock.launch.acquire()
        for (key, value) in values { setenv(key, value, 1) }
        body()
        for key in values.keys { unsetenv(key) }
        await AsyncLock.launch.release()
    }

    @Test func anUpgradeWithASavedSignInAndNoRememberedServerRemembersIt() throws {
        try store.save(StoredCredentials(server: Self.server, refreshToken: "saved"))
        #expect(RememberedAccountStore(defaults: defaults).server == nil)
        let session = session()
        #expect(RememberedAccountStore(defaults: defaults).server == Self.server)
        session.signOut()
        #expect(RememberedAccountStore(defaults: defaults).server == Self.server, "a sign-out keeps it for the next form")
    }

    @Test func aRememberedServerIsNotOverwrittenByTheSavedSignIn() throws {
        let other = HassServer(baseURL: URL(string: "https://other.example.com")!)
        RememberedAccountStore(defaults: defaults).remember(server: other)
        try store.save(StoredCredentials(server: Self.server, refreshToken: "saved"))
        let session = session()
        #expect(RememberedAccountStore(defaults: defaults).server == other)
        session.signOut()
    }

    @Test func theUITestResetSwitchStartsSignedOutEvenWithASavedSignIn() async throws {
        try store.save(StoredCredentials(server: Self.server, refreshToken: "saved"))
        RememberedAccountStore(defaults: defaults).remember(username: "alex")
        try HouseConfigCache(fileURL: houseURL).save(DemoHouse.config, hash: "h", server: Self.server)
        await withEnvironment(["FENTON_UITEST_RESET": "1"]) {
            let session = session()
            #expect(!session.isSignedIn && store.load() == nil)
            #expect(!FileManager.default.fileExists(atPath: houseURL.path))
            #expect(RememberedAccountStore(defaults: defaults).username == nil)
        }
    }

    @Test func anExpiredAccountSwitchShowsTheWelcomeBackSignInOnlyWhenSignedOut() async throws {
        await withEnvironment(["FENTON_EXPIRED_ACCOUNT": "alex|Alex Demo"]) {
            #expect(session().expiredAccount == RememberedAccount(username: "alex", name: "Alex Demo"))
        }
        await withEnvironment(["FENTON_EXPIRED_ACCOUNT": "alex"]) {
            #expect(session().expiredAccount == RememberedAccount(username: "alex", name: nil))
        }
        await withEnvironment(["FENTON_EXPIRED_ACCOUNT": "alex|"]) {
            #expect(session().expiredAccount?.name == nil)
        }
        try store.save(StoredCredentials(server: Self.server, refreshToken: "saved"))
        await withEnvironment(["FENTON_EXPIRED_ACCOUNT": "alex|S"]) {
            let signedIn = session()
            #expect(signedIn.isSignedIn && signedIn.expiredAccount == nil)
            signedIn.signOut()
        }
    }

    @Test func aLaunchTokenSignsInForThisLaunchOnlyAndIsNeverSaved() async {
        await withEnvironment(["FENTON_HASS_TOKEN": "long-lived", "FENTON_TEST_HONOURS_TOKEN": "1", "FENTON_HASS_SERVER": "http://127.0.0.1:1"]) {
            let session = session()
            #expect(session.isSignedIn && session.tokens != nil)
            #expect(session.motion.hasPlayed(.signInArrival))
            #expect(store.load() == nil, "The token is never saved")
            session.signOut()
        }
    }

    @Test func aShellTokenIsIgnoredByHostTests() async {
        await withEnvironment(["FENTON_HASS_TOKEN": "from-the-shell"]) {
            #expect(!session().isSignedIn)
        }
    }

    @Test func theHostTestRuleIsDecidedByTheProcessNameAndEnvironment() {
        #expect(AppSession.isHostTestProcess)
        #expect(!AppSession.isHostTestProcess(name: "FentonHome", environment: [:]))
        AppSession.beginLaunchMeasurement()
    }
}
