import HassCore
import HassDesign
import os
import SwiftUI

private let viewerLog = Logger(subsystem: "com.sfenton.home", category: "Rooms")

@MainActor
struct RoomPageContent {
    /// Where opening a card goes: the shared remote sheet for remote cards, a device lane's sheet when one is wired
    /// (``RoomDeviceModal``), else the room sheet.
    static func opening(_ card: RoomCard, controller: RoomController, hasConnection: Bool = false,
                        fans: [String: BathroomFanController] = [:], bedroom: BedroomDevices? = nil) -> RoomCardOpening {
        switch controller.sheet(for: card) {
        case let .mediaRemote(id):
            if let shared = controller.remote(id) { return .remote(shared) }
        case let .device(device):
            if let modal = RoomDeviceModal.resolve(device, hasConnection: hasConnection, fan: { fans[$0] }, bedroom: bedroom) {
                return .device(modal)
            }
        default:
            break
        }
        return .sheet
    }
}


/// Where a room card opens (``RoomPageContent/opening(_:controller:hasConnection:fans:bedroom:)``).
enum RoomCardOpening {
    case remote(MediaRemoteController)
    case device(RoomDeviceModal)
    case sheet
}


// MARK: - Sections

/// One titled section and its cards in the web's section layouts (`RoomGrid`, `DashboardViewPage.tsx:284`).
struct RoomSectionView {
    var controller: RoomController
    var section: RoomSection
    var imageServer: HassServer?
    var fans: [String: BathroomFanController] = [:]
    /// The Master Bedroom's beds, so their cards read each side's level and power.
    var bedroom: BedroomDevices?
    var onOpen: (RoomCard) -> Void

    /// Whether a lead row's lead card joins the two-column grid instead of spanning the page: a bathroom fan at regular
    /// width (owner, 2026-10-17: a 1,300 pt tile on iPad). On a phone the fan keeps its full-width lead row, which is
    /// what gives its text, two buttons and chevron room.
    static func leadJoinsGrid(_ section: RoomSection, regularWidth: Bool) -> Bool {
        regularWidth && section.cards.first?.control == .bathroomFan
    }

    /// App launchers, and a page's only section, span both section columns (web `ResponsiveSectionItem span`).
    static func isFullWidth(_ section: RoomSection, sectionCount: Int) -> Bool {
        if case .appLaunch = section.layout { return true }
        return sectionCount == 1
    }

    /// Three or more cards after a lead card switch to two filling columns (web `leadRowFollowUpLayout`).
    static func followUpColumns(_ count: Int) -> Int? { count > 2 ? 2 : nil }



}
