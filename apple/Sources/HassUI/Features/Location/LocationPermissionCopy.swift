import HassCore

/// The words on the location permission screen for each ``LocationPermission/Stage``
/// (`.agents/pages/settings/location.md`). Plain words, Title Case labels, no Home Assistant jargon beyond its name.
struct LocationPermissionCopy: Equatable {
    /// What the primary button does.
    enum Action: Equatable {
        /// Shows the system permission alert. Titled "Continue", never "Allow" (HIG Privacy, Pre-alert screens).
        case requestPermission
        /// Opens the app's page in Settings.
        case openSettings
    }

    /// The headline.
    var title: String
    /// The explanation under it.
    var message: String
    /// The primary button's action, or nil when there is nothing to do.
    var action: Action?
    /// What happens next, under the points; nil when nothing follows.
    var footnote: String?
    /// Whether the three "how it works" points show.
    var showsPoints: Bool

    /// The primary button's title.
    var actionTitle: String? {
        switch action {
        case .requestPermission: "Continue"
        case .openSettings: "Open Settings"
        case nil: nil
        }
    }

    /// Whether this stage is a pre-alert screen: it leads only to the system alert, so it has no Close and can't
    /// be swiped away (HIG Privacy: "Don't include additional actions").
    var isPreAlert: Bool { action == .requestPermission }

    /// - Parameters:
    ///   - stage: The permission's stage.
    ///   - canAskForAlways: Whether iOS will still show the Always alert. It shows it once; after the person keeps
    ///     While Using, the While Using stage sends them to Settings instead and can be closed.
    ///   - device: The device the copy names; an iPad is never linked to the person, so it promises no Away mode.
    @MainActor init(stage: LocationPermission.Stage, canAskForAlways: Bool = true, device: LocationDevice = .current) {
        let this = "this \(device.name)"
        let isPad = device == .iPad
        switch stage {
        case .notDetermined:
            title = "Know When You're Home"
            message = isPad
                ? "This iPad can tell Home Assistant when it arrives or leaves."
                : "This iPhone can tell Home Assistant when you arrive or leave, so Away mode and the thermostat follow you."
            action = .requestPermission
            footnote = "Next, iOS asks to use your location. Choose Allow While Using App."
            showsPoints = true
        case .whenInUse where !canAskForAlways:
            title = "Notice When You Leave"
            message = "Home Assistant only hears from \(this) while the app is open. To report arrivals and "
                + "departures with the app closed, choose Always in Settings."
            action = .openSettings
            footnote = nil
            showsPoints = false
        case .whenInUse:
            title = "Notice When You Leave"
            message = "Home Assistant only hears from \(this) while the app is open. To report arrivals and "
                + "departures with the app closed, location needs to be on all the time."
            action = .requestPermission
            footnote = "Next, iOS asks to change location access. Choose Change to Always Allow."
            showsPoints = true
        case .always:
            title = "Home and Away Are On"
            message = isPad
                ? "Home Assistant hears from this iPad when it arrives at or leaves a zone, and after it travels a long way."
                : "Home Assistant hears from this iPhone when you arrive at or leave a zone, and after you travel a long way."
            action = nil
            footnote = nil
            showsPoints = false
        case .denied:
            title = "Location Is Off"
            message = (isPad ? "Home Assistant can't tell where this iPad is. "
                       : "Home Assistant can't tell when you're home or away from this iPhone. ") + "In Settings, turn on "
                + "Location and choose Always."
            action = .openSettings
            footnote = nil
            showsPoints = false
        case .reducedAccuracy:
            title = "Precise Location Is Off"
            message = "Approximate location can be miles off, so Home Assistant can't tell whether "
                + (isPad ? "this iPad is home. " : "you're home. ") + "In Settings, turn on Precise Location."
            action = .openSettings
            footnote = nil
            showsPoints = false
        }
    }

    /// The status row's value: "While Using the App", "Always, Approximate".
    static func status(_ permission: LocationPermission) -> String {
        let access = switch permission.authorization {
        case .notDetermined: "Not Set"
        case .restricted: "Restricted"
        case .denied: "Off"
        case .whenInUse: "While Using the App"
        case .always: "Always"
        }
        return permission.isAuthorized && !permission.isPrecise ? "\(access), Approximate" : access
    }

    /// A point on the pre-alert screens: how reporting works.
    typealias Point = SetupPoint

    /// The three points, for an iPhone.
    static let points = points(for: .iPhone)

    /// The three points, naming the device.
    static func points(for device: LocationDevice) -> [Point] { [
        Point(symbol: "figure.walk.arrival", title: "Arrivals and Departures",
              detail: device == .iPad
                  ? "This iPad reports when it enters or leaves a zone set up in Home Assistant."
                  : "Your iPhone reports when you enter or leave a zone set up in Home Assistant."),
        Point(symbol: "lock.shield", title: "Only to Your Server",
              detail: "Your location goes only to your Home Assistant, never anywhere else."),
        Point(symbol: "battery.75percent", title: "Light on Battery",
              detail: "It listens for zone crossings and long moves instead of running GPS all the time."),
    ] }
}
