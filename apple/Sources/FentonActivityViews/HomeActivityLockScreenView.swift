import FentonActivityModel
import SwiftUI

/// The Lock Screen, banner and StandBy presentation of one activity (`.agents/platforms/apple/live-activities-per-job.md` §8):
/// the job card, or the problem card when the device needs help.
public struct HomeActivityLockScreenView: View {
    private let card: ActivityCard
    private let isFullscreen: Bool

    /// Creates the view.
    /// - Parameters:
    ///   - card: The activity's card.
    ///   - isFullscreen: StandBy: the corner mark goes and the system scales the rest.
    public init(card: ActivityCard, isFullscreen: Bool = false) {
        self.card = card
        self.isFullscreen = isFullscreen
    }

    public var body: some View {
        switch card.style {
        case .job:
            JobCardView(card: card, showsMark: !isFullscreen)
        case .problem:
            if let problem = card.problem {
                ProblemCardView(card: card, problem: problem, showsMark: !isFullscreen)
            }
        }
    }
}
