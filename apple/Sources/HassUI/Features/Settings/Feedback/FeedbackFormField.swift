import SwiftUI

/// The text boxes that take focus.
enum FeedbackFormField: Hashable {
    case title, description, repro, expected

    var identifier: String {
        switch self {
        case .title: "feedback.field.title"
        case .description: "feedback.field.description"
        case .repro: "feedback.field.repro"
        case .expected: "feedback.field.expected"
        }
    }
}
