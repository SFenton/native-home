#if os(iOS) && DEBUG
import FentonActivityModel
import FentonActivityViews
import HassDesign
import SwiftUI
import UIKit

/// Gallery page for the Live Activity cards (`.agents/platforms/apple/live-activities-per-job.md` §11): the Lock Screen
/// card, the Dynamic Island presentations and the small family, drawn by the same views the widget extension uses over
/// fixture content, with buttons that behave like the real ones (a press shows "Stopping…") and record their press.
///
/// `FENTON_GALLERY_SCENARIO` picks the content:
/// - a fixture name (`HomeActivityFixtures.allNames`): that card plus every island presentation and the small family;
/// - a group (`HomeActivityFixtures.groups`: `stack`, `jobs`, `vacuums`, `hotflash`, `complete`, `states`, `problems`,
///   `problems-flipped`): every card in it, one under the other, each named `liveactivity.card.<fixture>`;
/// - `catalog`: every card of every group, group after group (a fixture in two groups appears twice), so a test can count the
///   whole catalog in one launch;
/// - `island-widths`: the expanded island for a long `H:MM:SS` value on the narrowest, a standard and the widest camera
///   regions, to check nothing clips;
/// - `compact-widths`: the compact island for an `MM:SS` time, an `H:MM:SS` time and two vacuum words, each beside a probe of
///   its hidden template, to check the trailing side's width is the template's and not the width the island offers.
///
/// Launch with `FENTON_GALLERY=live-activity`; the default scenario is `stack` (four cards, the cap).
struct LiveActivityGallery: View {
    /// A screen and camera the island stand-in is drawn for.
    struct IslandSize: Identifiable {
        var id: String
        var screen: CGFloat
        var camera: CGFloat
    }

    /// The camera widths of canvas board 7: the widest camera on an older Pro, a narrower camera, and the Pro Max.
    static let islandSizes = [
        IslandSize(id: "older-pro", screen: 393, camera: 126),
        IslandSize(id: "narrow-camera", screen: 402, camera: 104),
        IslandSize(id: "pro-max", screen: 440, camera: 126),
    ]

    @State private var fixtures: [ActivityFixture]
    @State private var lastAction = "none"
    private let isGroup: Bool
    private let showsIslandWidths: Bool
    private let showsCompactWidths: Bool

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        let name = environment["FENTON_GALLERY_SCENARIO"] ?? "stack"
        showsIslandWidths = name == "island-widths"
        showsCompactWidths = name == "compact-widths"
        isGroup = HomeActivityFixtures.groups[name] != nil || name == "catalog"
        let loaded = if name == "catalog" {
            HomeActivityFixtures.groups.keys.sorted().flatMap { HomeActivityFixtures.fixtures(fromLaunchValue: $0) }
        } else if showsIslandWidths {
            [HomeActivityFixtures.fixture("fan-long")].compactMap { $0 }
        } else if showsCompactWidths {
            ["dishwasher", "dishwasher-long", "vacuum", "vacuum-long"].compactMap { HomeActivityFixtures.fixture($0) }
        } else {
            HomeActivityFixtures.fixtures(fromLaunchValue: name)
        }
        _fixtures = State(initialValue: loaded.isEmpty ? HomeActivityFixtures.fixtures(fromLaunchValue: "stack") : loaded)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HassTokens.Spacing.l) {
                if !GalleryEnvironment.isClean {
                    Text("Last action: \(lastAction)")
                        .font(.caption.monospaced())
                        .foregroundStyle(HassTokens.Ink.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("gallery.lastCall")
                }
                if showsIslandWidths, let fixture = fixtures.first {
                    ForEach(Self.islandSizes) { size in
                        section("Dynamic Island, expanded, \(Int(size.screen)) pt screen, \(Int(size.camera)) pt camera") {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HomeActivityIslandPreview(card: fixture.card(), kind: .expanded, screenWidth: size.screen, cameraWidth: size.camera)
                                    .accessibilityIdentifier("liveactivity.islandsize.\(size.id)")
                            }
                            // The same value at its natural 32 pt width: the journey checks it fits beside the buttons without elision.
                            Text("1:04:42")
                                .font(.system(size: 32, weight: .semibold))
                                .monospacedDigit()
                                .fixedSize()
                                .foregroundStyle(HassTokens.Ink.secondary)
                                .accessibilityIdentifier("liveactivity.probe.\(size.id)")
                        }
                    }
                } else if showsCompactWidths {
                    ForEach(fixtures) { fixture in
                        section(fixture.name) {
                            HomeActivityIslandPreview(card: fixture.card(), kind: .compact, exposesCompactBounds: true)
                        }
                    }
                    section("Template widths") {
                        HStack(spacing: HassTokens.Spacing.l) {
                            ForEach(["00:00", "0:00:00"], id: \.self) { template in
                                Text(template)
                                    .font(ActivityStyle.compactTimeFont)
                                    .fixedSize()
                                    .foregroundStyle(HassTokens.Ink.secondary)
                                    .accessibilityIdentifier("liveactivity.probe.compact.\(template.count == 5 ? "short" : "hours")")
                            }
                        }
                    }
                } else if isGroup {
                    ForEach(Array(fixtures.enumerated()), id: \.offset) { _, fixture in
                        section(fixture.name) { lockScreen(fixture, identifier: "liveactivity.card.\(fixture.name)") }
                    }
                } else if let fixture = fixtures.first {
                    section("Lock Screen") { lockScreen(fixture, identifier: "liveactivity.lockscreen") }
                    section("Dynamic Island, compact") { HomeActivityIslandPreview(card: fixture.card(), kind: .compact) }
                    section("Dynamic Island, minimal") { HomeActivityIslandPreview(card: fixture.card(), kind: .minimal) }
                    section("Dynamic Island, expanded") { HomeActivityIslandPreview(card: fixture.card(), kind: .expanded) }
                    section("Small (Smart Stack, CarPlay)") {
                        HomeActivitySmallView(card: fixture.card())
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.black))
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier("liveactivity.small")
                    }
                }
            }
            .padding(HassTokens.Spacing.l)
        }
        .environment(\.activityActions, actions)
        // The system draws a time ring only inside a Live Activity; here it is the fraction elapsed when drawn.
        .environment(\.activityStaticTimerRing, true)
        .navigationTitle("Live Activity")
    }

    /// One Lock Screen card on the system's ground (the activity's background tint over black), as the widget draws it.
    private func lockScreen(_ fixture: ActivityFixture, identifier: String) -> some View {
        let card = fixture.card()
        let shape = RoundedRectangle(cornerRadius: ActivityStyle.cornerRadius, style: .continuous)
        return HomeActivityLockScreenView(card: card)
            // The Lock Screen's width on a phone (a tablet shows 425 or 500 pt).
            .frame(maxWidth: 370)
            .background(shape.fill(ActivityStyle.ground(for: card)))
            .background(shape.fill(Color.black))
            .containerShape(shape)
            .clipShape(shape)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(identifier)
    }

    /// Buttons like the intent: a press shows the card as pending until "Home Assistant" answers (never, here).
    private var actions: ActivityActions {
        ActivityActions(control: { tag, control, label in
            AnyView(Button(action: { press(control, tag: tag) }) { label }.buttonStyle(.plain))
        })
    }

    private func press(_ control: ActivityControl, tag: String) {
        lastAction = "\(control.id) \(tag)"
        guard let index = fixtures.firstIndex(where: { $0.attributes.tag == tag }) else { return }
        fixtures[index].state = fixtures[index].state.awaiting(control: control.id, now: Date())
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: HassTokens.Spacing.s) {
            Text(title)
                .font(HassTokens.Typography.footnoteEmphasis)
                .foregroundStyle(HassTokens.Ink.secondary)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }
}

// MARK: - UIKit lane

/// `FENTON_GALLERY=live-activity`: the Live Activity cards are SwiftUI (ActivityKit's widget views, `FentonActivityViews`), so the
/// UIKit app hosts the page in a hosting controller; nothing of the app's own screens is SwiftUI.
extension UKGallery {
    static func liveActivity(_ page: ComponentGallery.Page) -> UIViewController? {
        guard page == .liveActivity else { return nil }
        let host = UIHostingController(rootView: LiveActivityGallery())
        host.overrideUserInterfaceStyle = .dark
        host.view.backgroundColor = UKGalleryGround.color
        return host
    }
}
#endif
