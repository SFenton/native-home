import AppIntents
import HassCore

/// The pages an App Shortcut can open: the app's five root sections.
enum AppPageOption: String, AppEnum {
    case home, security, climate, chores, settings

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Page")

    static let caseDisplayRepresentations: [AppPageOption: DisplayRepresentation] = [
        .home: DisplayRepresentation(title: "Home", image: .init(systemName: "house.fill")),
        .security: DisplayRepresentation(title: "Security", image: .init(systemName: "shield.fill")),
        .climate: DisplayRepresentation(title: "Climate", image: .init(systemName: "thermometer.medium")),
        .chores: DisplayRepresentation(title: "Chores", image: .init(systemName: "list.clipboard.fill")),
        .settings: DisplayRepresentation(title: "Settings", image: .init(systemName: "gearshape.fill")),
    ]

    /// The section this option opens.
    var destination: PushDestination {
        switch self {
        case .home: .section(.home)
        case .security: .section(.security)
        case .climate: .section(.climate)
        case .chores: .section(.chores)
        case .settings: .section(.settings)
        }
    }
}
