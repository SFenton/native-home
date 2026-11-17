// clip_pts.swift CLIP.mov|mp4  -> JSON: track size, nominal fps, sample count, PTS list (ms), gap statistics.
// Reads the compressed samples in passthrough (no decode), so it costs almost no CPU. Stands in for ffprobe, which is not installed.
import AVFoundation
import Foundation

// MARK: - Arguments

/// The clip to read (a `.mov` or `.mp4`).
let path = CommandLine.arguments[1]
let asset = AVURLAsset(url: URL(fileURLWithPath: path))
/// Signalled when the reading task finishes, so the process waits for it.
let sem = DispatchSemaphore(value: 0)
/// The JSON object printed at the end: size, rates, gap statistics and the timestamp list.
var out: [String: Any] = [:]

// MARK: - Reading

Task {
    do {
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else { print("{\"error\":\"no video track\"}"); sem.signal(); return }
        let size = try await track.load(.naturalSize)
        let nominal = try await track.load(.nominalFrameRate)
        let duration = try await asset.load(.duration).seconds
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(output)
        reader.startReading()
        var pts: [Double] = []
        while let sample = output.copyNextSampleBuffer() {
            let t = CMSampleBufferGetPresentationTimeStamp(sample).seconds * 1000
            if t.isFinite && CMSampleBufferGetNumSamples(sample) > 0 { pts.append(t) } else { out["invalidBuffers"] = ((out["invalidBuffers"] as? Int) ?? 0) + 1 }
        }
        pts.sort()
        var gaps: [Double] = []
        for i in 1..<max(pts.count, 1) { gaps.append(pts[i] - pts[i - 1]) }
        let sorted = gaps.sorted()
        /// The gap at fraction `p` of the sorted gaps (0 when there are none).
        func pct(_ p: Double) -> Double { sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * p))] }
        let span = (pts.last ?? 0) - (pts.first ?? 0)
        out["file"] = path
        out["width"] = Int(size.width); out["height"] = Int(size.height)
        out["nominalFps"] = nominal.isFinite ? Double(nominal) : -1
        out["durationSec"] = duration.isFinite ? duration : -1
        out["samples"] = pts.count
        out["firstPtsMs"] = pts.first ?? 0
        out["spanMs"] = span
        out["meanFps"] = span > 0 ? Double(pts.count - 1) / (span / 1000) : 0
        out["gapMedianMs"] = pct(0.5); out["gapP95Ms"] = pct(0.95); out["gapMaxMs"] = sorted.last ?? 0
        out["gapOver20ms"] = gaps.filter { $0 > 20 }.count
        out["gapOver25ms"] = gaps.filter { $0 > 25 }.count
        out["gapOver34ms"] = gaps.filter { $0 > 34 }.count
        out["ptsMs"] = pts.map { (($0 * 100).rounded() / 100) }
    } catch { out["error"] = "\(error)" }
    for (k, v) in out { if let d = v as? Double, !d.isFinite { out[k] = -1 } }
    let data = try! JSONSerialization.data(withJSONObject: out, options: [.sortedKeys])
    print(String(data: data, encoding: .utf8)!)
    sem.signal()
}
sem.wait()
