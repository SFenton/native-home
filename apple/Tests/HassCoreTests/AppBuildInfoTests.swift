import Foundation
@testable import HassCore
import Testing

// MARK: - AppBuildInfo

struct AppBuildInfoTests {
    private let base: [String: Any] = ["CFBundleShortVersionString": "0.1.0", "CFBundleVersion": "42"]

    private func info(sha: String?) -> [String: Any] {
        var info = base
        info[AppBuildInfo.gitSHAKey] = sha
        return info
    }

    @Test func aStampedCommitAppendsItsFirstSevenCharacters() {
        let text = AppBuildInfo.versionText(info(sha: "abcdabcdabcdabcdabcdabcdabcdabcdabcdabcd"))
        #expect(text == "0.1.0 (42) · abcdabc")
    }

    @Test func missingDevAndEmptyCommitsShowOnlyVersionAndBuild() {
        #expect(AppBuildInfo.versionText(base) == "0.1.0 (42)")
        #expect(AppBuildInfo.versionText(info(sha: "dev")) == "0.1.0 (42)")
        #expect(AppBuildInfo.versionText(info(sha: "")) == "0.1.0 (42)")
        #expect(AppBuildInfo.versionText(info(sha: "  ")) == "0.1.0 (42)")
    }

    @Test func nonHexValuesSuchAsAnUnexpandedBuildSettingAreIgnored() {
        #expect(AppBuildInfo.shortCommit("$(HASS_GIT_SHA)") == nil)
        #expect(AppBuildInfo.shortCommit("DEV") == nil)
        #expect(AppBuildInfo.shortCommit("main") == nil)
    }

    @Test func shortAndUpperCaseShasAreNormalised() {
        #expect(AppBuildInfo.shortCommit("ABC12") == "abc12")
        #expect(AppBuildInfo.shortCommit(" ABCDABCFF\n") == "abcdabc")
    }

    @Test func aReleaseVersionTagReadsAsVersionBuildAndCommit() {
        let stamped: [String: Any] = [
            "CFBundleShortVersionString": "2610.26.01",
            "CFBundleVersion": "57",
            AppBuildInfo.gitSHAKey: "abcdabcdabcdabcdabcdabcdabcdabcdabcdabcd",
        ]
        #expect(AppBuildInfo.versionText(stamped) == "2610.26.01 (57) · abcdabc")
        #expect(AppBuildInfo.spokenVersionText(stamped) == "2610.26.01, build 57, commit abcdabc")
    }

    @Test func voiceOverReadsEachPartByName() {
        #expect(AppBuildInfo.spokenVersionText(info(sha: "abcdabcdabcdabcdabcdabcdabcdabcdabcdabcd"))
            == "0.1.0, build 42, commit abcdabc")
        #expect(AppBuildInfo.spokenVersionText(info(sha: "dev")) == "0.1.0, build 42")
        #expect(AppBuildInfo.spokenVersionText(info(sha: "$(HASS_GIT_SHA)")) == "0.1.0, build 42")
        #expect(AppBuildInfo.spokenVersionText(nil) == "Unknown")
        #expect(AppBuildInfo.spokenVersionText(["CFBundleVersion": "7"]) == "Unknown, build 7")
        #expect(AppBuildInfo.spokenVersionText(["CFBundleShortVersionString": "2.1", AppBuildInfo.gitSHAKey: "ABCDEF0123"])
            == "2.1, commit abcdef0")
    }

    @Test func versionAndBuildFallbacks() {
        #expect(AppBuildInfo.versionText(nil) == "—")
        #expect(AppBuildInfo.versionText(["CFBundleShortVersionString": "2.1"]) == "2.1")
        #expect(AppBuildInfo.versionText(["CFBundleVersion": "7"]) == "— (7)")
        #expect(AppBuildInfo.versionText(["CFBundleShortVersionString": "2.1", AppBuildInfo.gitSHAKey: "abcdef0123"])
            == "2.1 · abcdef0")
    }
}

// MARK: - Release stamping

/// Guards the path from a version tag to the app's Info.plist: release builds pass `MARKETING_VERSION`,
/// `CURRENT_PROJECT_VERSION` and `HASS_GIT_SHA` on the `xcodebuild` command line
/// (`tools/release/versioning.py build-settings`), so every app and extension must read those settings.
struct ReleaseVersionStampingTests {
    /// The `apple/project.yml` target blocks, keyed by target name (each block runs from its `  Name:` line up
    /// to the next two-space-indented key or top-level key).
    private func targetBlocks() throws -> [String: String] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("project.yml")
        let lines = try String(contentsOf: url, encoding: .utf8).components(separatedBy: "\n")
        guard let targets = lines.firstIndex(of: "targets:") else { return [:] }
        var blocks: [String: String] = [:]
        var name: String?
        var body: [String] = []
        func flush() {
            if let name { blocks[name] = body.joined(separator: "\n") }
        }
        for line in lines[(targets + 1)...] {
            if !line.hasPrefix(" "), !line.isEmpty { break }
            let isTargetKey = line.hasPrefix("  ") && !line.hasPrefix("   ") && line.hasSuffix(":")
                && !line.trimmingCharacters(in: .whitespaces).hasPrefix("#")
            if isTargetKey {
                flush()
                name = String(line.dropFirst(2).dropLast())
                body = [line]
            } else {
                body.append(line)
            }
        }
        flush()
        return blocks
    }

    @Test func theAppAndEveryExtensionReadTheVersionAndBuildSettings() throws {
        let blocks = try targetBlocks()
        for target in ["FentonHome", "FentonHomeNotificationService", "FentonHomeNotificationContent",
                       "FentonHomeWidgets"] {
            let block = try #require(blocks[target], "\(target) is missing from apple/project.yml")
            #expect(block.contains("CFBundleShortVersionString: $(MARKETING_VERSION)"), "\(target)")
            #expect(block.contains("CFBundleVersion: $(CURRENT_PROJECT_VERSION)"), "\(target)")
        }
    }

    @Test func theAppTakesTheCommitFromTheReleaseBuildSettingAndLocalBuildsKeepDev() throws {
        let project = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("project.yml"), encoding: .utf8)
        let app = try #require(try targetBlocks()["FentonHome"])
        #expect(app.contains("\(AppBuildInfo.gitSHAKey): $(HASS_GIT_SHA)"))
        #expect(project.contains("HASS_GIT_SHA: dev"), "local builds must keep the dev default (no commit shown)")
    }

    @Test func theWatchAppSharesTheProjectVersion() throws {
        // The watch app uses a generated Info.plist, which takes MARKETING_VERSION and CURRENT_PROJECT_VERSION from
        // the project-wide settings; it must not override them, or the pair would ship with different versions.
        let watch = try #require(try targetBlocks()["FentonHomeWatch"])
        #expect(!watch.contains("MARKETING_VERSION"))
        #expect(!watch.contains("CURRENT_PROJECT_VERSION"))
    }
}
