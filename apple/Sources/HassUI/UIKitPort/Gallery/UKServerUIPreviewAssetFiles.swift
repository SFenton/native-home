#if os(iOS) && DEBUG
import Foundation
import HassCore

/// The debug preview's asset source: files named by SHA-256 in a local directory, standing in for the integration's asset route.
/// The stager still verifies size, hash, type and dimensions, so a wrong file fails exactly as a wrong download would.
struct UKServerUIPreviewAssetFiles: ServerUIAssetFetching {
    let directory: URL

    func download(_ asset: ServerUICompositionDocument.Asset) async throws -> Data {
        guard asset.sha256.utf8.count == 64, asset.sha256.utf8.allSatisfy({ ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x61 && $0 <= 0x66) }) else {
            throw ServerUIAssetError.assetOrigin
        }
        do { return try Data(contentsOf: directory.appendingPathComponent(asset.sha256)) }
        catch { throw ServerUIAssetError.missing }
    }
}
#endif
