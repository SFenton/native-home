// clip_gray.swift CLIP OUT.bin [WIDTH]  : every frame of a screen recording reduced to a small luma image, for motion analysis.
// OUT.bin = little-endian: uint32 frameCount, uint32 width, uint32 height, then per frame float64 ptsMs (0 = the first sample)
// followed by width*height uint8 luma. Each output pixel is the mean of a 3x3 sample grid of its source block (0...255, mean of
// R, G, B). Decodes sequentially with AVAssetReader (never AVAssetImageGenerator, which returns stale key frames).
// Replaces the spike's clip_motion (stride-7 sampling): the frame differences are computed in Python from these images.
import AVFoundation
import Foundation

// MARK: - Arguments

/// The program arguments: clip, output file, optional output width.
let args = CommandLine.arguments
/// The clip being read.
let asset = AVURLAsset(url: URL(fileURLWithPath: args[1]))
/// Where the binary frame dump is written.
let outPath = args[2]
/// Width in pixels of each reduced frame (120 by default); the height keeps the clip's aspect ratio.
let outW = args.count > 3 ? Int(args[3])! : 120
/// Signalled when the decoding task finishes, so the process waits for it.
let sem = DispatchSemaphore(value: 0)

// MARK: - Sequential decode and reduction

Task {
    let track = try! await asset.loadTracks(withMediaType: .video).first!
    let reader = try! AVAssetReader(asset: asset)
    let out = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
    reader.add(out); reader.startReading()
    var data = Data()
    var count: UInt32 = 0, w: UInt32 = 0, h: UInt32 = 0
    var first = -1.0
    while let s = out.copyNextSampleBuffer() {
        guard let pb = CMSampleBufferGetImageBuffer(s) else { continue }
        let t = CMSampleBufferGetPresentationTimeStamp(s).seconds * 1000
        if first < 0 { first = t }
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        let sw = CVPixelBufferGetWidth(pb), sh = CVPixelBufferGetHeight(pb), bpr = CVPixelBufferGetBytesPerRow(pb)
        let base = CVPixelBufferGetBaseAddress(pb)!.assumingMemoryBound(to: UInt8.self)
        let ow = outW, oh = Int((Double(sh) / Double(sw) * Double(outW)).rounded())
        if count == 0 { w = UInt32(ow); h = UInt32(oh) }
        var pts = (t - first)
        data.append(Data(bytes: &pts, count: 8))
        var row = [UInt8](repeating: 0, count: ow)
        for oy in 0..<oh {
            for ox in 0..<ow {
                var sum = 0
                for dy in 0..<3 { for dx in 0..<3 {
                    let sx = min(sw - 1, (ox * sw + (dx * 2 + 1) * sw / 6) / ow), sy = min(sh - 1, (oy * sh + (dy * 2 + 1) * sh / 6) / oh)
                    let p = base + sy * bpr + sx * 4
                    sum += Int(p[0]) + Int(p[1]) + Int(p[2])
                } }
                row[ox] = UInt8(sum / 27)
            }
            data.append(contentsOf: row)
        }
        CVPixelBufferUnlockBaseAddress(pb, .readOnly)
        count += 1
    }
    var header = Data()
    for v in [count, w, h] { var x = v.littleEndian; header.append(Data(bytes: &x, count: 4)) }
    try! (header + data).write(to: URL(fileURLWithPath: outPath))
    sem.signal()
}
sem.wait()
