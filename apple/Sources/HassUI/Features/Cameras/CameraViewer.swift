import HassCore
import HassDesign
import ImageIO
import SwiftUI
#if canImport(Photos)
import Photos
#endif
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Controls layout



/// What the Snapshot button shows (web `snapshotPulse`, here with the save's outcome).
enum CameraSnapshotFeedback: Equatable {
    case idle, saving, saved, failed

    var title: String {
        switch self {
        case .idle, .saving: "Snapshot"
        case .saved: "Saved"
        case .failed: "Not Saved"
        }
    }

    var symbol: String {
        switch self {
        case .idle, .saving: "camera.fill"
        case .saved: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    var accessibilityValue: String {
        switch self {
        case .idle: ""
        case .saving: "Saving"
        case .saved: "Saved to Photos"
        case .failed: "Couldn't save the snapshot"
        }
    }
}

// MARK: - Saving

/// Saves a camera snapshot to the photo library (web `saveScreenshot` downloads a JPEG).
enum CameraSnapshotSaver {
    enum Result: Equatable { case saved, denied, failed }

    /// Saves the live frame, or the camera's Home Assistant still when no frame is playing.
    static func save(frame: CGImage?, fallbackURL: URL?) async -> Result {
        var data = frame.flatMap(jpeg)
        if data == nil, let fallbackURL,
           let (still, response) = try? await URLSession.shared.data(from: fallbackURL),
           (response as? HTTPURLResponse)?.statusCode == 200 {
            data = still
        }
        guard let data else { return .failed }
        #if canImport(Photos) && canImport(UIKit)
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { return .denied }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
            }
            return .saved
        } catch {
            return .failed
        }
        #else
        return .failed
        #endif
    }

    /// JPEG data for an image.
    static func jpeg(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}

// MARK: - Layout

/// When the viewer splits video and controls (owner's split rules, `.agents/design/apple/split-view.md`).
enum CameraViewerLayout {
    /// The narrowest sheet that holds the video beside the controls.
    static let minimumSplitWidth: CGFloat = 640

    static func usesSplit(window: CGSize, isRegularWidth: Bool, container: CGSize) -> Bool {
        SplitPolicy.allowsSplit(size: window, isRegularWidth: isRegularWidth) && container.width >= minimumSplitWidth
    }
}



#if canImport(UIKit)
extension WindowMetrics {
    /// The key window's size and width class now, or empty before there is a window.
    @MainActor static var current: WindowMetrics {
        let windows = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.windows }.flatMap { $0 }
        guard let window = windows.first(where: \.isKeyWindow) ?? windows.first else { return WindowMetrics() }
        return WindowMetrics(size: window.bounds.size, isRegularWidth: window.traitCollection.horizontalSizeClass == .regular)
    }
}
#else
extension WindowMetrics {
    @MainActor static var current: WindowMetrics { WindowMetrics() }
}
#endif
