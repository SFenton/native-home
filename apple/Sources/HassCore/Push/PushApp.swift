import Foundation

/// The app's `mobile_app` identity (contract v1, rule 2).
public enum PushApp {
    /// `app_id` for the main app's bundle, the fallback when the running bundle has no identifier. A registration sends
    /// the running bundle's own id (``MobileAppDevice/appID``): a build with another bundle id (such as
    /// `com.sfenton.home.uikit`) used to claim this one, and its APNs token was then for the wrong topic.
    public static let appID = "com.sfenton.home"
    /// `app_name`.
    public static let appName = "Fenton Home"
    /// Suffix on every `device_name`, so Home Assistant names this app's notify service apart from the official
    /// companion app's on the same phone (`notify.mobile_app_<device>_<app>`).
    public static let deviceNameSuffix = " · Fenton"
}
