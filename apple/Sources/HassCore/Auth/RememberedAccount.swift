import Foundation

/// Who last signed in on this phone: the account name and the person's name, kept so a rejected session can say
/// "Welcome back, Alex" and ask for the password alone (`.agents/platforms/apple/auth.md`, "Session expired").
///
/// Never the password, and nothing secret: the username is what the person types in the first field, and the name is the
/// display name the profile button already shows.
public struct RememberedAccount: Equatable, Sendable {
    /// The Home Assistant username, as signed in with.
    public var username: String
    /// The person's display name, when the app has read it.
    public var name: String?

    /// Creates an account.
    public init(username: String, name: String? = nil) {
        self.username = username
        self.name = name
    }

    /// The name people are greeted by: the short form of the display name ("Alex" from "Alex Morgan"), read with
    /// `PersonNameComponentsFormatter` so a name that does not split into first and last ("Ng", "Mary Ann") stays right.
    /// The username when there is no name.
    public var firstName: String {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return username }
        let formatter = PersonNameComponentsFormatter()
        formatter.style = .short
        guard let components = formatter.personNameComponents(from: trimmed) else { return trimmed }
        let short = formatter.string(from: components)
        return short.isEmpty ? trimmed : short
    }
}

/// Reads and writes the remembered account in `UserDefaults` (not the Keychain: neither value is a secret).
public struct RememberedAccountStore: @unchecked Sendable {
    /// The key for the last username.
    public static let usernameKey = "signin.lastUsername"
    /// The key for the person's display name. The profile button keeps its name here too (`ShellNavigator.profileName`), so
    /// the name is current without a second write.
    public static let nameKey = "shell.profileName"

    /// The key for the last server signed in to, as a URL string.
    public static let serverKey = "signin.lastServer"

    private let defaults: UserDefaults

    /// Creates a store over `defaults`.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The last username typed on a successful sign-in, if any.
    public var username: String? {
        let value = defaults.string(forKey: Self.usernameKey)
        return value?.isEmpty == false ? value : nil
    }

    /// The remembered account: nil until a username is known.
    public var account: RememberedAccount? {
        guard let username else { return nil }
        let name = defaults.string(forKey: Self.nameKey)
        return RememberedAccount(username: username, name: name?.isEmpty == false ? name : nil)
    }

    /// Remembers the username after a successful sign-in.
    public func remember(username: String) {
        defaults.set(username, forKey: Self.usernameKey)
    }

    /// The last server signed in to successfully, if any. Not a secret, so `UserDefaults`.
    public var server: HassServer? {
        guard let value = defaults.string(forKey: Self.serverKey), !value.isEmpty, let url = URL(string: value) else { return nil }
        return HassServer(baseURL: url)
    }

    /// Remembers the server after a successful sign-in.
    public func remember(server: HassServer) {
        defaults.set(server.baseURL.absoluteString, forKey: Self.serverKey)
    }

    /// Forgets the server (the UI-test reset only: a sign-out and Use a Different Account both keep it).
    public func forgetServer() {
        defaults.removeObject(forKey: Self.serverKey)
    }

    /// Forgets the username (Use a Different Account) and the name that went with it. The server stays.
    public func forget() {
        defaults.removeObject(forKey: Self.usernameKey)
        defaults.removeObject(forKey: Self.nameKey)
    }
}
