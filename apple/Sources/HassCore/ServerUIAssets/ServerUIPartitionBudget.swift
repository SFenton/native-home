import Darwin
import Foundation

// MARK: - Shared asset, render and publication budget

/// Counts all private partition files, including hidden files and atomic-write reservations.
enum ServerUIPartitionBudget {
    static func check(_ root: URL, reserving bytes: Int = 0) throws {
        let maximum = ServerUIAssetStager.maximumPartitionBytes
        guard bytes >= 0, bytes <= maximum else { throw ServerUIAssetError.assetBudget }
        var remaining = maximum - bytes
        func visit(_ directory: URL) throws {
            var directoryInfo = stat()
            guard lstat(directory.path, &directoryInfo) == 0,
                  (directoryInfo.st_mode & S_IFMT) == S_IFDIR else { throw ServerUIAssetError.storage }
            let contents: [URL]
            do { contents = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) }
            catch { throw ServerUIAssetError.storage }
            for file in contents {
                var info = stat()
                guard lstat(file.path, &info) == 0 else { throw ServerUIAssetError.storage }
                switch info.st_mode & S_IFMT {
                case S_IFDIR: try visit(file)
                case S_IFREG:
                    guard info.st_size >= 0, info.st_size <= remaining else { throw ServerUIAssetError.assetBudget }
                    remaining -= Int(info.st_size)
                default: throw ServerUIAssetError.storage
                }
            }
        }
        try visit(root)
    }
}
