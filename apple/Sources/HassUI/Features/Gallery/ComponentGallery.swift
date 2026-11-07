import HassCore
import HassDesign
import SwiftUI

/// Debug-only component gallery: shows shared controls with fixture data and no server, so UI tests,
/// accessibility audits and screenshots can reach them signed out. Launch with `FENTON_GALLERY=<page>`.
public struct ComponentGallery {
    /// A gallery page.
    public enum Page: String, CaseIterable, Sendable {
        case food
        case mediaRemote = "media-remote"
        case thermostatDial = "thermostat-dial"
        case vacation
        case security
        case rooms
        case mediaPage = "media-page"
        case customLights = "custom-lights"
        case sprinklers
        case bedroom = "bedroom"
        case vacuums
        case roomDevices = "room-devices"
        case householdSettings = "household-settings"
        case climate
        case floatingActions = "floating-actions"
        case inventory
        case chores
        case settings
        case performance
        case weather
        case directionG = "direction-g"
        case location
        /// The after-sign-in Setup flow: Notifications, Time Sensitive and Location in one sheet.
        case setup
        /// Settings → Notifications in each state.
        case notificationSettings = "notification-settings"
        case systemAccessibility = "system-accessibility"
        case modalSizing = "modal-sizing"
        case liveActivity = "live-activity"
        case profile
        /// An empty page: only the wallpaper and its scrim (with `FENTON_BACKDROP_FIXTURE=1`), for screenshots.
        case backdrop
        case motion
        case shellHeader = "shell-header"
        case cameraViewer = "camera-viewer"
        case home
    }

    /// The page requested at launch, if any. Always `nil` in release builds.
    public static var requested: Page? {
        #if DEBUG
        ProcessInfo.processInfo.environment["FENTON_GALLERY"].flatMap(Page.init(rawValue:))
        #else
        nil
        #endif
    }

    public var page: Page

    /// Creates the gallery on `page`.
    public init(page: Page) { self.page = page }


}
