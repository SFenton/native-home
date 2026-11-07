import Foundation
import HassCore
@testable import HassUI
import SwiftUI
import Testing
import UniformTypeIdentifiers

/// What a report carries about the device, how a picked file is staged, and how Home Assistant's settings describe the server.
@MainActor
@Suite(.serialized, .hosted) // The staging folder is process-wide.
struct FeedbackSupportTests {
    private let traits = FeedbackDiagnosticsCollector.Traits(
        dynamicTypeSize: .accessibility3, colorScheme: .dark, regularWidth: true, voiceOver: true, reduceMotion: false
    )

    @Test func accessibilitySettingsAreListedInWords() {
        #expect(FeedbackDiagnosticsCollector.accessibilityText(traits) == "Text accessibility3, VoiceOver on, Reduce Motion off, Dark")
        var light = traits
        light.colorScheme = .light
        light.voiceOver = false
        light.reduceMotion = true
        #expect(FeedbackDiagnosticsCollector.accessibilityText(light) == "Text accessibility3, VoiceOver off, Reduce Motion on, Light")
    }

    @Test func eachPlatformNamesItsDeviceFamily() {
        #expect(FeedbackDiagnosticsCollector.familyName(.ios) == "iPhone")
        #expect(FeedbackDiagnosticsCollector.familyName(.ipados) == "iPad")
        #expect(FeedbackDiagnosticsCollector.familyName(.iphoneDuo) == "iPhone Duo")
    }

    @Test func theDiagnosticsTableCarriesTheServerTheDeviceAndTheTraits() {
        let table = FeedbackDiagnosticsCollector.diagnostics(platform: .ipados, traits: traits, homeAssistant: "2026.11, connected")
        #expect(table.homeAssistant == "2026.11, connected")
        #expect(table.device.hasPrefix("iPad (") && table.device.hasSuffix(")"))
        #expect(table.accessibility.contains("Dark"))
        #expect(table.locale.contains(TimeZone.current.identifier))
        #expect(!table.app.isEmpty && !table.system.isEmpty)
        #expect(table.window.contains("regular width"))
        #expect(!FeedbackDiagnosticsCollector.hardwareModel.isEmpty)
        #expect(FeedbackDiagnosticsCollector.systemVersion.contains(" "))
        #expect(FeedbackDiagnosticsCollector.windowSize == .zero, "No window on the host")
        _ = FeedbackDiagnosticsCollector.buildDate
    }

    @Test func collectingReadsTheConnectionStatusInWords() {
        let connection = HassConnection(server: .example, tokens: TokenManager(store: InMemoryTokenStore()), store: EntityStore())
        let collector = FeedbackDiagnosticsCollector(platform: .ios, traits: traits)
        #expect(collector.collect(connection: connection).homeAssistant == "Disconnected")
        #expect(collector.collect(connection: connection).device.hasPrefix("iPhone ("))
    }

    // MARK: Staging picked media

    @Test func aPickedFileIsCopiedIntoItsOwnFolderUnderASafeName() throws {
        let folder = try FeedbackUITestMedia.folder()
        let url = folder.appendingPathComponent("My Photo (1).png")
        try Data([1, 2, 3]).write(to: url)
        let staged = try FeedbackPickedMedia.stage(url)
        defer { FeedbackFormModel.purgeStagedMedia() }
        #expect(staged.url.lastPathComponent == "My Photo 1.png")
        #expect(staged.url.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL
            == FeedbackPickedMedia.stagingFolder.standardizedFileURL)
        #expect(try Data(contentsOf: staged.url) == Data([1, 2, 3]))
        #expect(try Data(contentsOf: url) == Data([1, 2, 3]), "The original stays untouched")
    }

    @Test func stagingAMissingFileThrows() {
        #expect(throws: (any Error).self) { try FeedbackPickedMedia.stage(URL(fileURLWithPath: "/nonexistent/x.png")) }
    }

    @Test func anItemProviderWithAnImageOrMovieIsStagedAndOtherTypesAreIgnored() async throws {
        let folder = try FeedbackUITestMedia.folder()
        let png = try FeedbackUITestMedia.image(in: folder, name: "pick.png", type: .png, gps: false)
        defer { FeedbackFormModel.purgeStagedMedia() }
        nonisolated(unsafe) let image = try #require(NSItemProvider(contentsOf: png))
        let staged = try #require(try await FeedbackPickedMedia.load(image))
        #expect(staged.url.pathExtension == "png")
        #expect(try Data(contentsOf: staged.url) == Data(contentsOf: png))

        nonisolated(unsafe) let text = NSItemProvider(item: "hello" as NSString, typeIdentifier: UTType.plainText.identifier)
        #expect(try await FeedbackPickedMedia.load(text) == nil)
    }

    // MARK: Home Assistant settings text

    @Test func theServerAndAccountReadAsPlainText() {
        let server = HassServer(baseURL: URL(string: "https://ha.example.com:8123")!)
        #expect(HomeAssistantSettingsView.displayedServer(server, redacting: false) == "ha.example.com:8123")
        #expect(HomeAssistantSettingsView.displayedServer(HassServer(baseURL: URL(string: "https://ha.example.com")!), redacting: false) == "ha.example.com")
        #expect(HomeAssistantSettingsView.displayedServer(server, redacting: true) == "Hidden for screenshot")
        #expect(HomeAssistantSettingsView.displayedName(HassUser(id: "1", name: "Alex", isOwner: false, isAdmin: true), redacting: false) == "Alex")
        #expect(HomeAssistantSettingsView.displayedName(HassUser(id: "1", name: "", isOwner: false, isAdmin: true), redacting: false) == "Unnamed user")
        #expect(HomeAssistantSettingsView.displayedName(HassUser(id: "1", name: nil, isOwner: false, isAdmin: true), redacting: false) == "Unnamed user")
        #expect(HomeAssistantSettingsView.displayedName(HassUser(id: "1", name: "S", isOwner: false, isAdmin: true), redacting: true) == "Hidden for screenshot")
    }

    @Test func theConnectionStatusIsDescribedAndOnlyAConnectedOneHasAVersion() {
        #expect(HomeAssistantSettingsView.statusText(.disconnected) == "Disconnected")
        #expect(HomeAssistantSettingsView.statusText(.connecting) == "Connecting…")
        #expect(HomeAssistantSettingsView.statusText(.connected(version: "1")) == "Connected")
        #expect(HomeAssistantSettingsView.statusText(.waitingToReconnect) == "Reconnecting…")
        #expect(HomeAssistantSettingsView.statusText(.rejected) == "Signed out by server")
        #expect(HomeAssistantSettingsView.statusText(.connected(version: "1"), isOffline: true) == "Offline")
        #expect(HomeAssistantSettingsView.version(.connected(version: "2026.11.0")) == "2026.11.0")
        #expect(HomeAssistantSettingsView.version(.connected(version: "")) == nil)
        #expect(HomeAssistantSettingsView.version(.connecting) == nil)
    }

    @Test func onlyAdministratorsSeeHomeAssistantSettings() {
        #expect(HomeAssistantSettingsView.webPages(for: nil) == HomeAssistantSettingsView.WebPage.listed)
        #expect(HomeAssistantSettingsView.webPages(for: HassUser(id: "1", name: "A", isOwner: false, isAdmin: true)) == HomeAssistantSettingsView.WebPage.listed)
        #expect(HomeAssistantSettingsView.webPages(for: HassUser(id: "2", name: "B", isOwner: false, isAdmin: false)) == [.profile])
        for page in HomeAssistantSettingsView.WebPage.allCases {
            #expect(!page.title.isEmpty && !page.symbol.isEmpty && !page.subtitle.isEmpty && page.id == page.rawValue)
        }
        #expect(HomeAssistantSettingsView.WebPage.settings.path == "/config" && HomeAssistantSettingsView.WebPage.profile.path == "/profile")
        #expect(HomeAssistantSettingsView.WebPage.integrations.path == "/config/integrations/dashboard")
        #expect(HomeAssistantSettingsView.WebPage.houseIntegration.path == "/config/integrations/integration/fenton_home")
        #expect(HomeAssistantSettingsView.WebPage.repairs.path == "/config/repairs")
        #expect(HomeAssistantSettingsView.WebPage.listed == [.settings, .profile], "Message-only pages are never listed in the modal")
        #expect(HomeAssistantSettingsView.linkTitle == "Home Assistant Settings")
        #expect(HomeAssistantSettingsView.linkSubtitle.hasPrefix("Access more"))
    }

    @Test func loadedUserKeepsTheKnownUserUnlessTheServerAnswers() async {
        let connection = HassConnection(server: .example, tokens: TokenManager(store: InMemoryTokenStore()), store: EntityStore())
        let user = HassUser(id: "1", name: "A", isOwner: false, isAdmin: true)
        let (kept, failed) = await HomeAssistantSettingsView.loadedUser(user, from: connection)
        #expect(kept == user && !failed)
        let (none, unknown) = await HomeAssistantSettingsView.loadedUser(nil, from: connection)
        #expect(none == nil && unknown, "Disconnected with no user: the load failed")
    }
}
