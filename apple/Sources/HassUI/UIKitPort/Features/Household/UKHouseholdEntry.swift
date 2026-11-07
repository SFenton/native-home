#if os(iOS)
import HassCore
import UIKit

// Owned by the Household lane (household topics, Your Summary, Vacation, Location).
extension UKScreens {
    /// A pushed household topic (`HouseholdSettingsDestination`).
    static func destination(for page: HouseholdSettingsPage, context: UKContext) -> UIViewController {
        UKHouseholdSettingsViewController.make(page: page, context: context)
    }

    /// The Profile button's sheet (Your Summary): a full-height modal navigation controller the section stack presents as it is.
    static func yourSummary(_ context: UKContext) -> UIViewController {
        UKYourSummary.make(context: context, models: UKSummaryModels(chores: nil, inventory: context.connection.flatMap { connection in
            context.sessionModels?.inventory(for: connection)
        }))
    }

    /// Settings → Vacation (`VacationRoute`): the chooser between Vacation Mode and Solo Trip, or straight to the engaged one.
    /// The Settings lane calls this for `SettingsRoute.vacation`.
    static func vacation(_ context: UKContext) -> UIViewController {
        UKVacationViewController.make(context: context)
    }
}
#endif
