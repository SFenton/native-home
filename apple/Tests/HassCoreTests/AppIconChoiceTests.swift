import Foundation
@testable import HassCore
import Testing

/// The eight tinted-glass app icons: names, asset-catalog names (stable, an installed build remembers them) and the
/// colour table the art and its previews are drawn from (owner mockups of 2026-10-17, `Pairs.dc.html`).
struct AppIconChoiceTests {
    @Test func theNavyAndSkyIconIsTheDefaultAndFirst() {
        #expect(AppIconChoice.allCases.count == 8)
        #expect(AppIconChoice.allCases.first == .navySky)
        #expect(AppIconChoice.default == .navySky)
        #expect(AppIconChoice.allCases.filter(\.isDefault) == [.navySky])
        #expect(AppIconChoice.navySky.alternateIconName == nil, "The default is installed by passing nil")
        #expect(AppIconChoice.navySky.assetName == "AppIcon")
    }

    @Test func namesMatchTheMockups() {
        #expect(AppIconChoice.allCases.map(\.displayName) == [
            "Navy + Sky", "Teal + Mint", "Plum + Lilac", "Forest + Green", "Burgundy + Rose", "Indigo + Periwinkle",
            "Espresso + Amber", "Midnight + Gold",
        ])
        #expect(AppIconChoice.allCases.map(\.spokenName) == [
            "Navy and Sky", "Teal and Mint", "Plum and Lilac", "Forest and Green", "Burgundy and Rose",
            "Indigo and Periwinkle", "Espresso and Amber", "Midnight and Gold",
        ])
    }

    @Test func assetNamesAreStable() {
        // These names are in project.yml (ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES) and in installed builds.
        #expect(AppIconChoice.allCases.map(\.assetName) == [
            "AppIcon", "AppIcon-TealMint", "AppIcon-PlumLilac", "AppIcon-ForestGreen", "AppIcon-BurgundyRose",
            "AppIcon-IndigoPeriwinkle", "AppIcon-EspressoAmber", "AppIcon-MidnightGold",
        ])
        #expect(Set(AppIconChoice.allCases.map(\.assetName)).count == 8)
        #expect(AppIconChoice.allCases.dropFirst().allSatisfy { $0.alternateIconName == $0.assetName })
    }

    @Test(arguments: AppIconChoice.allCases)
    func theSystemNameRoundTrips(_ choice: AppIconChoice) {
        #expect(AppIconChoice(alternateIconName: choice.alternateIconName) == choice)
    }

    @Test func anUnknownOrMissingNameIsTheDefault() {
        #expect(AppIconChoice(alternateIconName: nil) == .navySky)
        #expect(AppIconChoice(alternateIconName: "AppIcon-Removed") == .navySky)
        #expect(AppIconChoice(alternateIconName: "AppIcon") == .navySky, "The default's asset name is not an alternate name")
    }

    @Test func colourPairsMatchTheMockups() {
        let expected: [(AppIconChoice, UInt32, UInt32)] = [
            (.navySky, 0x0E1E46, 0x7CC4FF), (.tealMint, 0x063A3E, 0x6EE7C8),
            (.plumLilac, 0x3A1648, 0xD3A8FF), (.forestGreen, 0x10301E, 0x9BE29B),
            (.burgundyRose, 0x48101E, 0xFF9EB0), (.indigoPeriwinkle, 0x221C5A, 0xA8B4FF),
            (.espressoAmber, 0x342014, 0xFFB35C), (.midnightGold, 0x101630, 0xFFD36B),
        ]
        for (choice, tint, glyph) in expected {
            #expect(choice.tint == tint, "\(choice) tint")
            #expect(choice.glyph == glyph, "\(choice) glyph")
        }
        #expect(AppIconChoice.tintOpacity == 0.86)
    }

    @Test func everyChoiceLooksDifferent() {
        #expect(Set(AppIconChoice.allCases.map(\.glyph)).count == 8)
        #expect(Set(AppIconChoice.allCases.map(\.tint)).count == 8)
    }

    @Test func idIsTheRawValue() {
        #expect(AppIconChoice.allCases.map(\.id) == AppIconChoice.allCases.map(\.rawValue))
    }
}
