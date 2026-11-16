import Foundation

// MARK: - App state

/// The `app-state@1` source (`sh.app-state@1`): facts about the app and its window that no Home Assistant entity holds, readable by a
/// slot `read`, an operand or a condition like any model field. One source per topic; the topic is a closed list and the source takes
/// no other input.
///
/// Window geometry is offered, the kind of device is not: layout follows geometry, and device-specific chrome stays in the renderers.
/// Every topic also has `phase` (`ready` or `loading`).
///
/// The app updates a topic on a transition, never per frame: the window on a size or trait change, the clock once a minute and only
/// while something reads it, the notification state at activation, the preferences on change. This type holds the values and answers
/// reads; ``UKServerUIAppStateSource`` (UIKit) gathers them. A topic that has not been gathered yet reads `loading`, so a node that waits
/// on it keeps what it showed.
public struct ServerUIAppState: Equatable, Sendable {
    /// The closed list of topics.
    public enum Topic: String, Sendable, CaseIterable {
        case window, clock, os, notifications, preferences
    }

    /// A window dimension as a size class.
    public enum SizeClass: String, Sendable { case compact, regular }

    /// The window the app is drawn in: geometry only.
    public struct Window: Equatable, Sendable {
        public var widthClass: SizeClass
        public var heightClass: SizeClass
        public var width: Double
        public var height: Double

        /// Creates a window.
        public init(widthClass: SizeClass, heightClass: SizeClass, width: Double, height: Double) {
            self.widthClass = widthClass
            self.heightClass = heightClass
            self.width = width
            self.height = height
        }

        /// `portrait` when the window is at least as tall as it is wide, else `landscape`.
        public var orientation: String { height >= width ? "portrait" : "landscape" }
    }

    /// The system the app runs on.
    public struct OS: Equatable, Sendable {
        public var major: Int
        public var supportsAlternateIcons: Bool
        public var reduceMotion: Bool
        public var reduceTransparency: Bool
        public var canSendMail: Bool

        /// Creates the facts.
        public init(major: Int, supportsAlternateIcons: Bool, reduceMotion: Bool, reduceTransparency: Bool, canSendMail: Bool) {
            self.major = major
            self.supportsAlternateIcons = supportsAlternateIcons
            self.reduceMotion = reduceMotion
            self.reduceTransparency = reduceTransparency
            self.canSendMail = canSendMail
        }
    }

    /// Where the person stands on notification permission.
    public struct Notifications: Equatable, Sendable {
        /// `not-determined`, `denied`, `authorized`, `provisional` or `ephemeral`.
        public var permission: String
        /// `not-supported`, `disabled` or `enabled`.
        public var timeSensitive: String

        /// Creates the facts.
        public init(permission: String, timeSensitive: String) {
            self.permission = permission
            self.timeSensitive = timeSensitive
        }
    }

    /// The person's app preferences.
    public struct Preferences: Equatable, Sendable {
        public var showCountOnIcon: Bool
        public var notificationBannerDismissed: Bool

        /// Creates the preferences.
        public init(showCountOnIcon: Bool, notificationBannerDismissed: Bool) {
            self.showCountOnIcon = showCountOnIcon
            self.notificationBannerDismissed = notificationBannerDismissed
        }
    }

    public var window: Window?
    public var clock: ServerUIClock?
    public var os: OS?
    public var notifications: Notifications?
    public var preferences: Preferences?

    /// Creates the state; a topic that is `nil` has not been gathered and reads `loading`.
    public init(window: Window? = nil, clock: ServerUIClock? = nil, os: OS? = nil, notifications: Notifications? = nil,
                preferences: Preferences? = nil) {
        self.window = window
        self.clock = clock
        self.os = os
        self.notifications = notifications
        self.preferences = preferences
    }

    // MARK: The read vocabulary

    /// The read fields of each topic and the kind each reads as. Each is `since: 1`; a later field would need `sh.app-state@2`.
    public static func fields(_ topic: Topic) -> [String: ServerUICompositionDocument.ScalarKind] {
        switch topic {
        case .window:
            ["widthClass": .string, "heightClass": .string, "width": .number, "height": .number, "orientation": .string, "phase": .string]
        case .clock:
            ["hour": .number, "minute": .number, "weekday": .number, "minuteOfDay": .number, "today": .string, "phase": .string]
        case .os:
            ["major": .number, "supportsAlternateIcons": .boolean, "reduceMotion": .boolean, "reduceTransparency": .boolean,
             "canSendMail": .boolean, "phase": .string]
        case .notifications: ["permission": .string, "timeSensitive": .string, "phase": .string]
        case .preferences: ["showCountOnIcon": .boolean, "notificationBannerDismissed": .boolean, "phase": .string]
        }
    }

    /// What reading `field` of `topic` gives: its value, `loading` while the topic has not been gathered, or `unavailable` for a field the
    /// topic does not have (the compiler refuses such a read, so this guards a hand-made path).
    public func read(_ topic: Topic, field: String) -> ServerUIReadResult {
        guard Self.fields(topic)[field] != nil else { return .unavailable }
        if field == "phase" { return .value(.string(isGathered(topic) ? "ready" : "loading")) }
        switch topic {
        case .window:
            guard let window else { return .loading }
            switch field {
            case "widthClass": return .value(.string(window.widthClass.rawValue))
            case "heightClass": return .value(.string(window.heightClass.rawValue))
            case "width": return .value(.number(window.width))
            case "height": return .value(.number(window.height))
            default: return .value(.string(window.orientation))
            }
        case .clock:
            guard let clock, let parts = Self.parts(of: clock) else { return clock == nil ? .loading : .unavailable }
            switch field {
            case "hour": return .value(.number(Double(parts.hour)))
            case "minute": return .value(.number(Double(parts.minute)))
            case "weekday": return .value(.number(Double(parts.weekday)))
            case "minuteOfDay": return .value(.number(Double(parts.hour * 60 + parts.minute)))
            default: return .value(.string(parts.today))
            }
        case .os:
            guard let os else { return .loading }
            switch field {
            case "major": return .value(.number(Double(os.major)))
            case "supportsAlternateIcons": return .value(.bool(os.supportsAlternateIcons))
            case "reduceMotion": return .value(.bool(os.reduceMotion))
            case "reduceTransparency": return .value(.bool(os.reduceTransparency))
            default: return .value(.bool(os.canSendMail))
            }
        case .notifications:
            guard let notifications else { return .loading }
            return .value(.string(field == "permission" ? notifications.permission : notifications.timeSensitive))
        case .preferences:
            guard let preferences else { return .loading }
            return .value(.bool(field == "showCountOnIcon" ? preferences.showCountOnIcon : preferences.notificationBannerDismissed))
        }
    }

    /// Whether the topic has been gathered.
    public func isGathered(_ topic: Topic) -> Bool {
        switch topic {
        case .window: window != nil
        case .clock: clock != nil
        case .os: os != nil
        case .notifications: notifications != nil
        case .preferences: preferences != nil
        }
    }

    // MARK: The clock

    /// The clock for `date` in `timeZone`: the wall time and its offset from UTC in whole minutes.
    public static func clock(at date: Date, timeZone: TimeZone = .current) -> ServerUIClock {
        let offsetSeconds = timeZone.secondsFromGMT(for: date)
        let local = Int((date.timeIntervalSince1970).rounded(.down)) + offsetSeconds
        let days = ServerUIDates.floorDivide(local, 86_400)
        let seconds = local - days * 86_400
        let (year, month, day) = ServerUIDates.civil(fromDays: days)
        func two(_ value: Int) -> String { value < 10 ? "0\(value)" : "\(value)" }
        let now = "\(String(format: "%04d", year))-\(two(month))-\(two(day))T\(two(seconds / 3_600)):\(two(seconds / 60 % 60)):\(two(seconds % 60))"
        return ServerUIClock(now: now, utcOffsetMinutes: offsetSeconds / 60)
    }

    /// The seconds from `date` to the start of the next minute, for a tick that fires on the minute and not before.
    public static func secondsToNextMinute(from date: Date) -> TimeInterval {
        let whole = date.timeIntervalSince1970
        return 60 - whole.truncatingRemainder(dividingBy: 60)
    }

    private static func parts(of clock: ServerUIClock) -> (hour: Int, minute: Int, weekday: Int, today: String)? {
        guard let time = ServerUIDates.time(of: clock), let today = ServerUIDates.today(of: clock) else { return nil }
        // 1970-01-01 was a Thursday; the weekday is 1 for Monday to 7 for Sunday.
        let weekday = ((time.days + 3) % 7 + 7) % 7 + 1
        return (time.seconds / 3_600, time.seconds / 60 % 60, weekday, today)
    }
}
