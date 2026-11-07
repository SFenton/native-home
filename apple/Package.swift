// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FentonHomeApple",
    // `.macOS` exists only so `swift test` runs on the host Mac. macOS is not a supported product platform.
    platforms: [.iOS(.v17), .watchOS(.v10), .macOS(.v14)],
    products: [
        .library(name: "HassTelemetry", targets: ["HassTelemetry"]),
        .library(name: "HassCore", targets: ["HassCore"]),
        .library(name: "HassDesign", targets: ["HassDesign"]),
        .library(name: "HassUI", targets: ["HassUI"]),
        // DEBUG-only synthetic house; the hosted app tests import it (a Release build links an empty module).
        .library(name: "HassDemoHouse", targets: ["HassDemoHouse"]),
        // Live Activity: the dependency-free model (attributes, content state, job logic) and its SwiftUI views.
        // The widget extension links these two and nothing else (`.agents/platforms/apple/live-activities.md` §9).
        .library(name: "FentonActivityModel", targets: ["FentonActivityModel"]),
        .library(name: "FentonActivityViews", targets: ["FentonActivityViews"]),
    ],
    dependencies: [
        .package(url: "https://github.com/home-assistant/HAKit", from: "0.4.19"),
        // HAKit's websocket engine. 4.0.10 stops compressing control frames: 4.0.9 set RSV1 on the heartbeat pong
        // and Home Assistant (aiohttp) dropped the connection every minute. Tests check the frames directly.
        .package(url: "https://github.com/bgoncal/Starscream", from: "4.0.10"),
        // Prebuilt Google WebRTC for live camera video (go2rtc); iOS only so `swift test` on macOS skips it.
        .package(url: "https://github.com/stasel/WebRTC", from: "137.0.0"),
    ],
    targets: [
        // Signposts and the in-app performance log; every other module reports into it.
        .target(name: "HassTelemetry"),
        .target(name: "FentonActivityModel"),
        .target(name: "FentonActivityViews", dependencies: ["FentonActivityModel", "HassDesign"]),
        .target(
            name: "HassCore",
            dependencies: ["HassTelemetry", "FentonActivityModel", .product(name: "HAKit", package: "HAKit")]
        ),
        .target(name: "HassDesign", dependencies: ["HassTelemetry"]),
        .target(
            name: "HassUI",
            dependencies: [
                "HassCore",
                "HassDesign",
                "HassTelemetry",
                "FentonActivityModel",
                "FentonActivityViews",
                "HassDemoHouse",
                .product(name: "WebRTC", package: "WebRTC", condition: .when(platforms: [.iOS])),
            ]
        ),
        // The synthetic demo house (`DemoHouse`) for the DEBUG gallery and tests; the whole module is `#if DEBUG`, so Release links nothing.
        .target(name: "HassDemoHouse", dependencies: ["HassCore"]),
        // Test doubles every test target shares (callers, schedulers); never linked into the app. Re-exports `HassDemoHouse`.
        .target(name: "HassTestSupport", dependencies: ["HassCore", "FentonActivityModel", "HassDemoHouse"], path: "Tests/HassTestSupport"),
        .testTarget(
            name: "HassCoreTests",
            dependencies: [
                "HassCore",
                "FentonActivityModel",
                "HassTestSupport",
                .product(name: "HAKit+Mocks", package: "HAKit"),
                .product(name: "Starscream", package: "Starscream"),
            ]
        ),
        .testTarget(name: "HassDesignTests", dependencies: ["HassDesign"]),
        .testTarget(name: "FentonActivityModelTests", dependencies: ["FentonActivityModel"]),
        .testTarget(name: "HassTelemetryTests", dependencies: ["HassTelemetry"]),
        .testTarget(
            name: "HassUITests",
            dependencies: ["HassUI", "HassCore", "HassTestSupport", "FentonActivityModel", "FentonActivityViews", .product(name: "HAKit+Mocks", package: "HAKit")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
