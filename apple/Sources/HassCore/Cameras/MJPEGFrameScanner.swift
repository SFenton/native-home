import Foundation

/// Pulls whole JPEG frames out of a `multipart/x-mixed-replace` MJPEG stream (Home Assistant's
/// `/api/camera_proxy_stream/<entity_id>`).
///
/// Scans for the JPEG start (`FF D8`) and end (`FF D9`) markers instead of parsing part headers, so it works with
/// any boundary and with or without `Content-Length`. Bytes before a frame start are dropped; a partial frame waits
/// for more data, up to ``maxFrameBytes``.
public struct MJPEGFrameScanner: Sendable {
    /// A frame larger than this is dropped (and the scanner resynchronizes on the next start marker).
    public static let maxFrameBytes = 8_000_000

    private var buffer = Data()

    /// Creates a scanner.
    public init() {}

    /// Adds received bytes.
    /// - Returns: The complete frames they finish, oldest first.
    public mutating func append(_ data: Data) -> [Data] {
        buffer.append(data)
        var frames: [Data] = []
        while true {
            guard let start = buffer.range(of: Self.start) else {
                // Keep a trailing FF in case it begins the next start marker.
                buffer = buffer.last == 0xFF ? Data([0xFF]) : Data()
                break
            }
            if start.lowerBound > buffer.startIndex { buffer.removeSubrange(buffer.startIndex..<start.lowerBound) }
            guard let end = buffer.range(of: Self.end, in: (buffer.startIndex + 2)..<buffer.endIndex) else {
                if buffer.count > Self.maxFrameBytes { buffer.removeFirst(2) }
                break
            }
            frames.append(Data(buffer[buffer.startIndex..<end.upperBound]))
            buffer.removeSubrange(buffer.startIndex..<end.upperBound)
        }
        return frames
    }

    private static let start = Data([0xFF, 0xD8])
    private static let end = Data([0xFF, 0xD9])
}
