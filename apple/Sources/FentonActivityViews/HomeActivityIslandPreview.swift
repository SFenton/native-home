import FentonActivityModel
import SwiftUI

/// The three island presentations in a black capsule, for the gallery, the hosted tests and screenshots: the system
/// draws the real island, so this is a stand-in with the real regions inside it.
///
/// The expanded stand-in lays the regions out the way the canvas does (board 7): the leading and trailing regions are the
/// space beside the camera, `(island width − 36 − camera) / 2` each, and the title, value and buttons sit below in the full
/// width. Passing a narrow or wide `screenWidth` and `cameraWidth` reproduces every iPhone, which is how the journeys check
/// that an `H:MM:SS` value is not clipped. The compact stand-in exposes the trailing side's exact bounds, which the journeys
/// compare with the width of its hidden template (a rigid width, not the width the island offers).
public struct HomeActivityIslandPreview: View {
    /// Which presentation.
    public enum Kind: String, CaseIterable, Sendable {
        case compact, minimal, expanded
    }

    /// The width of one of the two regions beside the camera, for a screen and camera (the island is inset 11 pt on each
    /// side of the screen and 18 pt inside).
    public static func regionWidth(screenWidth: CGFloat, cameraWidth: CGFloat) -> CGFloat {
        ((screenWidth - 22) - 36 - cameraWidth) / 2
    }

    private let card: ActivityCard
    private let kind: Kind
    private let screenWidth: CGFloat
    private let cameraWidth: CGFloat
    private let exposesCompactBounds: Bool

    /// Creates the preview.
    /// - Parameters:
    ///   - card: The activity's card.
    ///   - kind: Which presentation.
    ///   - screenWidth: The screen the expanded island sits on (402 by default).
    ///   - cameraWidth: The camera cut-out between the two regions (126 by default; 104 on a narrower island).
    ///   - exposesCompactBounds: Add an accessibility element with the compact trailing side's exact bounds, for the journey that
    ///     compares it with its template. Off elsewhere: an element that small fails the accessibility audit's hit-area check.
    public init(card: ActivityCard, kind: Kind, screenWidth: CGFloat = 402, cameraWidth: CGFloat = 126, exposesCompactBounds: Bool = false) {
        self.exposesCompactBounds = exposesCompactBounds
        self.card = card
        self.kind = kind
        self.screenWidth = screenWidth
        self.cameraWidth = cameraWidth
    }

    public var body: some View {
        Group {
            switch kind {
            case .compact:
                HStack {
                    HomeActivityIsland.CompactLeading(card: card)
                    Spacer(minLength: 90)
                    HomeActivityIsland.CompactTrailing(card: card)
                        .background { if exposesCompactBounds { Self.bounds("liveactivity.compact.trailing.bounds") } }
                }
                .padding(.horizontal, 12)
                .frame(width: 250, height: 36)
                .background(Capsule().fill(Color.black))
            case .minimal:
                // The system draws the real minimal view at about 36 pt; the stand-in is 44 pt so its accessibility
                // element is a target a person could hit.
                HomeActivityIsland.Minimal(card: card)
                    .frame(width: ActivityStyle.minimumHit, height: ActivityStyle.minimumHit)
                    .background(Circle().fill(Color.black))
                    .contentShape(Circle())
            case .expanded:
                expanded
            }
        }
        // The island's regions are the system's size, so its text does not grow past xxxLarge (the Lock Screen's does).
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("liveactivity.island.\(kind.rawValue)")
    }

    private var expanded: some View {
        let region = Self.regionWidth(screenWidth: screenWidth, cameraWidth: cameraWidth)
        return VStack(spacing: 8) {
            HStack(spacing: 0) {
                HomeActivityIsland.ExpandedLeading(card: card)
                    .frame(width: region, height: 36, alignment: .leading)
                    .background { Self.bounds("liveactivity.island.leading.bounds") }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("liveactivity.island.leading")
                Color.clear.frame(width: cameraWidth, height: 36)
                HomeActivityIsland.ExpandedTrailing(card: card)
                    .frame(width: region, height: 36, alignment: .trailing)
                    .background { Self.bounds("liveactivity.island.trailing.bounds") }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("liveactivity.island.trailing")
            }
            HomeActivityIsland.ExpandedBottom(card: card)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("liveactivity.island.bottom")
        }
        .padding(EdgeInsets(top: 10, leading: 18, bottom: 14, trailing: 18))
        .frame(width: screenWidth - 22)
        .background(RoundedRectangle(cornerRadius: 42, style: .continuous).fill(Color.black))
        .background { Self.bounds("liveactivity.island.shape") }
    }

    /// An empty element with the exact bounds of the view it backs, so the journeys can measure a region or the island itself:
    /// a container's own accessibility frame is the union of its children, which hides how much room the region had.
    private static func bounds(_ identifier: String) -> some View {
        Color.clear.accessibilityElement().accessibilityLabel("Island stand-in region").accessibilityIdentifier(identifier)
    }
}
