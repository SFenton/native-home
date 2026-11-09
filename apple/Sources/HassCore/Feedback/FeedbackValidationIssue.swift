import Foundation

/// Why Submit is unavailable.
public enum FeedbackValidationIssue: Sendable, Equatable {
    case missingTitle
    case titleTooLong
    case missingDescription
    case textTooLong

    /// Short guidance shown under the form while Submit is disabled.
    public var message: String {
        switch self {
        case .missingTitle: "Add a title after the prefix."
        case .titleTooLong: "Shorten the title to \(FeedbackLimits.titleCharacters) characters."
        case .missingDescription: "Add a description."
        case .textTooLong: "Shorten each box to \(FeedbackLimits.bodyCharacters.formatted()) characters."
        }
    }
}
