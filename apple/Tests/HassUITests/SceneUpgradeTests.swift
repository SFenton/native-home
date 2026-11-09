@testable import HassUI
import Testing
import Foundation

struct SceneUpgradeTests {
    final class Ours: NSObject {}
    final class Foreign: NSObject {}

    @Test func foreignOrMissingDelegateIsAdopted() {
        #expect(UKSceneUpgrade.needsAdoption(sceneDelegate: Foreign(), ours: Ours.self))
        #expect(UKSceneUpgrade.needsAdoption(sceneDelegate: nil, ours: Ours.self))
    }

    @Test func ownDelegateIsLeftAlone() {
        #expect(!UKSceneUpgrade.needsAdoption(sceneDelegate: Ours(), ours: Ours.self))
    }

    @Test func configurationNameMatchesInfoPlist() {
        #expect(UKSceneUpgrade.configurationName == "Default")
    }
}
