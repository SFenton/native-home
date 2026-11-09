import ActivityKit
import AppIntents
import FentonActivityModel
import FentonActivityViews
import SwiftUI
import WidgetKit

/// The job Live Activity (`.agents/platforms/apple/live-activities-per-job.md` §8): the card on the Lock Screen and banner,
/// StandBy, the Dynamic Island (compact, minimal, expanded), and on iOS 18 the `.small` family for Apple Watch and CarPlay.
/// One activity is one job; a problem turns the same activity into a problem card.
///
/// All of the drawing is in `FentonActivityViews`; this file only places it, adds the buttons (the App Intent lives in
/// `Apps/Shared`, so the package cannot name it), reads the app group's icon choice, and sets the system chrome. The views
/// have no network and no Keychain.
struct HomeLiveActivity: Widget {
    var body: some WidgetConfiguration {
        if #available(iOS 18.0, *) {
            return configuration.supplementalActivityFamilies([.small])
        }
        return configuration
    }

    private var configuration: some WidgetConfiguration {
        ActivityConfiguration(for: HomeActivityAttributes.self) { context in
            let card = ActivityCard(attributes: context.attributes, state: context.state, isStale: context.isStale)
            HomeActivityFamilyView(card: card)
                .environment(\.activityActions, .intents)
                .activityBackgroundTint(ActivityStyle.ground(for: card))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(ActivityDeepLink.url(for: context.state))
        } dynamicIsland: { context in
            let card = ActivityCard(attributes: context.attributes, state: context.state, isStale: context.isStale)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { HomeActivityIsland.ExpandedLeading(card: card).dynamicTypeSize(...DynamicTypeSize.xxxLarge) }
                DynamicIslandExpandedRegion(.trailing) { HomeActivityIsland.ExpandedTrailing(card: card).dynamicTypeSize(...DynamicTypeSize.xxxLarge) }
                // The centre stays empty (spec §8): the system sizes the leading and trailing regions for each camera.
                DynamicIslandExpandedRegion(.bottom) {
                    HomeActivityIsland.ExpandedBottom(card: card).dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .environment(\.activityActions, .intents)
                }
            } compactLeading: {
                HomeActivityIsland.CompactLeading(card: card)
            } compactTrailing: {
                IslandCompactTrailing(card: card).dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            } minimal: {
                HomeActivityIsland.Minimal(card: card)
            }
            .widgetURL(ActivityDeepLink.url(for: context.state))
            .keylineTint(IslandKeyline.color(for: card))
        }
    }
}

/// The keyline around the island: the severity colour on a problem, the family accent otherwise.
private enum IslandKeyline {
    static func color(for card: ActivityCard) -> Color {
        if case let .problem(level) = card.style { return ActivityStyle.severity(level).circle }
        return ActivityStyle(tint: card.tint).accent
    }
}

/// The compact trailing side, which shows nothing when the system says the island is limited in width (iOS 27).
private struct IslandCompactTrailing: View {
    let card: ActivityCard

    var body: some View {
        if #available(iOS 27.0, *) {
            Limited(card: card)
        } else {
            HomeActivityIsland.CompactTrailing(card: card)
        }
    }

    @available(iOS 27.0, *)
    private struct Limited: View {
        let card: ActivityCard
        @Environment(\.isDynamicIslandLimitedInWidth) private var isLimited

        var body: some View {
            HomeActivityIsland.CompactTrailing(card: card, isLimitedWidth: isLimited)
        }
    }
}

/// Picks the presentation for the activity's family: the full Lock Screen view, or the small one for the Smart Stack
/// and CarPlay (iOS 18), where buttons do nothing until a device check says otherwise.
private struct HomeActivityFamilyView: View {
    let card: ActivityCard
    @Environment(\.isActivityFullscreen) private var isFullscreen

    var body: some View {
        if #available(iOS 18.0, *) {
            FamilyAwareView(card: card, isFullscreen: isFullscreen)
        } else {
            HomeActivityLockScreenView(card: card, isFullscreen: isFullscreen)
        }
    }
}

@available(iOS 18.0, *)
private struct FamilyAwareView: View {
    let card: ActivityCard
    let isFullscreen: Bool
    @Environment(\.activityFamily) private var family

    var body: some View {
        switch family {
        case .small:
            HomeActivitySmallView(card: card)
        default:
            HomeActivityLockScreenView(card: card, isFullscreen: isFullscreen)
        }
    }
}

extension ActivityActions {
    /// Buttons that run the App Intent in `Apps/Shared/LiveActivityIntents.swift`.
    static let intents = ActivityActions(
        control: { tag, control, label in
            AnyView(Button(intent: JobControlIntent(tag: tag, control: control.id)) { label }.buttonStyle(.plain))
        })
}
