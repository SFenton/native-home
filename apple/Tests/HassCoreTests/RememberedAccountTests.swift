import Foundation
@testable import HassCore
import Testing

/// The last username and the person's name, kept for the session-expired sign-in.
struct RememberedAccountTests {
    private func store() throws -> (RememberedAccountStore, UserDefaults) {
        let defaults = try #require(UserDefaults(suiteName: "remembered.tests.\(UUID())"))
        return (RememberedAccountStore(defaults: defaults), defaults)
    }

    @Test func nothingIsRememberedUntilAUsernameIsSaved() throws {
        let (store, defaults) = try store()
        #expect(store.username == nil && store.account == nil)
        defaults.set("Alex Demo", forKey: RememberedAccountStore.nameKey)
        #expect(store.account == nil, "a name alone is not an account to welcome back")
        defaults.set("", forKey: RememberedAccountStore.usernameKey)
        #expect(store.username == nil, "an empty username is nothing")
    }

    @Test func rememberingKeepsTheUsernameAndPicksUpTheName() throws {
        let (store, defaults) = try store()
        store.remember(username: "alex")
        #expect(store.account == RememberedAccount(username: "alex", name: nil))
        defaults.set("Alex Demo", forKey: RememberedAccountStore.nameKey)
        #expect(store.account == RememberedAccount(username: "alex", name: "Alex Demo"))
        defaults.set("", forKey: RememberedAccountStore.nameKey)
        #expect(store.account?.name == nil, "an empty name is no name")
    }

    @Test func forgettingClearsBoth() throws {
        let (store, defaults) = try store()
        store.remember(username: "alex")
        defaults.set("Alex Demo", forKey: RememberedAccountStore.nameKey)
        store.forget()
        #expect(store.account == nil)
        #expect(defaults.string(forKey: RememberedAccountStore.nameKey) == nil)
    }

    @Test func theServerRoundTripsAsAURLString() throws {
        let (store, defaults) = try store()
        #expect(store.server == nil)
        let server = HassServer(baseURL: URL(string: "http://homeassistant.local:8123")!)
        store.remember(server: server)
        #expect(store.server == server)
        #expect(defaults.string(forKey: RememberedAccountStore.serverKey) == "http://homeassistant.local:8123")
        defaults.set("", forKey: RememberedAccountStore.serverKey)
        #expect(store.server == nil, "an empty server is nothing")
    }

    @Test func theServerIsKeptWhenTheAccountIsForgottenAndClearedOnItsOwn() throws {
        let (store, _) = try store()
        let server = HassServer(baseURL: URL(string: "https://ha.example.com")!)
        store.remember(username: "alex")
        store.remember(server: server)
        store.forget()
        #expect(store.account == nil && store.server == server, "Use a Different Account and sign-out keep the server")
        store.forgetServer()
        #expect(store.server == nil)
    }

    @Test func theFirstNameIsTheFirstWordOrTheUsername() {
        #expect(RememberedAccount(username: "ad", name: "Alex Demo").firstName == "Alex")
        #expect(RememberedAccount(username: "ad", name: "  Alex  ").firstName == "Alex")
        #expect(RememberedAccount(username: "ad", name: nil).firstName == "ad")
        #expect(RememberedAccount(username: "ad", name: "   ").firstName == "ad")
        // Names that do not split into first and last stay whole.
        #expect(RememberedAccount(username: "ad", name: "Ng").firstName == "Ng")
        #expect(RememberedAccount(username: "ad", name: "Mary Ann Smith").firstName == "Mary Ann")
    }
}
