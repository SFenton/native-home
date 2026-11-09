import Foundation

/// A notification button from an automation's `data.actions` (contract v1, rule 3).
public struct PushAction: Equatable, Sendable {
    /// How a button opens.
    public enum ActivationMode: String, Sendable {
        /// Opens the app.
        case foreground
        /// Runs without opening the app.
        case background
    }

    /// The action id fired back as `mobile_app_notification_action`.
    public var action: String
    /// Button title.
    public var title: String
    /// A link the button opens in the app instead of firing an event.
    public var uri: String?
    /// SF Symbol name, from `sfsymbols:<name>`.
    public var symbol: String?
    /// Needs the device unlocked.
    public var authenticationRequired: Bool
    /// Shown as destructive.
    public var destructive: Bool
    /// Opens the app or runs in the background.
    public var activationMode: ActivationMode
    /// A text reply (`behavior: textInput`).
    public var isTextInput: Bool
    /// The reply field's send button.
    public var textInputButtonTitle: String?
    /// The reply field's placeholder.
    public var textInputPlaceholder: String?

    /// Creates an action.
    public init(action: String, title: String, uri: String? = nil, symbol: String? = nil,
                authenticationRequired: Bool = false, destructive: Bool = false,
                activationMode: ActivationMode = .background, isTextInput: Bool = false,
                textInputButtonTitle: String? = nil, textInputPlaceholder: String? = nil) {
        self.action = action
        self.title = title
        self.uri = uri
        self.symbol = symbol
        self.authenticationRequired = authenticationRequired
        self.destructive = destructive
        self.activationMode = activationMode
        self.isTextInput = isTextInput
        self.textInputButtonTitle = textInputButtonTitle
        self.textInputPlaceholder = textInputPlaceholder
    }

    /// Reads one entry of `fenton.actions`; an entry without an id or title is dropped.
    init?(json: JSONValue) {
        guard let action = json["action"]?.string, !action.isEmpty,
              let title = json["title"]?.string, !title.isEmpty else { return nil }
        let uri = json["uri"]?.string.flatMap { $0.isEmpty ? nil : $0 }
        let icon = json["icon"]?.string
        self.init(
            action: action,
            title: title,
            uri: uri,
            symbol: icon.flatMap(Self.symbol(fromIcon:)),
            authenticationRequired: json["authenticationRequired"]?.bool ?? false,
            destructive: json["destructive"]?.bool ?? false,
            // A link must open the app to show its page.
            activationMode: uri != nil ? .foreground : (json["activationMode"]?.string.flatMap(ActivationMode.init(rawValue:)) ?? .background),
            isTextInput: json["behavior"]?.string?.lowercased() == "textinput",
            textInputButtonTitle: json["textInputButtonTitle"]?.string,
            textInputPlaceholder: json["textInputPlaceholder"]?.string
        )
    }

    /// The SF Symbol in an `sfsymbols:<name>` icon; other icon sets have no native symbol.
    static func symbol(fromIcon icon: String) -> String? {
        let prefix = "sfsymbols:"
        guard icon.lowercased().hasPrefix(prefix) else { return nil }
        let name = String(icon.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }
}
