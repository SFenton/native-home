// clip_frames.swift CLIP OUTDIR T1_MS T2_MS ... [--width W]
// Writes OUTDIR/f<ms>.png: the frame on screen at each time, that is the last frame whose PTS <= t (times in ms of the clip timeline,
// 0 = the first sample). Decodes sequentially with AVAssetReader, so a P-frame is never replaced by an earlier key frame
// (AVAssetImageGenerator with a tolerance does exactly that). Prints "<t> actualMs=<pts of the frame written>".
import AVFoundation
import AppKit
import CoreImage
import Foundation

var args = Array(CommandLine.arguments.dropFirst())
let clip = args.removeFirst(); let outDir = args.removeFirst()
var width = 0.0
var times: [Double] = []
var i = 0
while i < args.count {
    if args[i] == "--width" { width = Double(args[i + 1])!; i += 2 } else { times.append(Double(args[i])!); i += 1 }
}
times.sort()
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
let asset = AVURLAsset(url: URL(fileURLWithPath: clip))
let ci = CIContext()
func write(_ pb: CVPixelBuffer, _ name: String) {
    var img = CIImage(cvPixelBuffer: pb)
    if width > 0 { let s = width / img.extent.width; img = img.transformed(by: CGAffineTransform(scaleX: s, y: s)) }
    guard let cg = ci.createCGImage(img, from: img.extent) else { return }
    let rep = NSBitmapImageRep(cgImage: cg)
    try? rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: name))
}
let sem = DispatchSemaphore(value: 0)
Task {
    let track = try! await asset.loadTracks(withMediaType: .video).first!
    let reader = try! AVAssetReader(asset: asset)
    let out = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
    reader.add(out); reader.startReading()
    var first = -1.0
    var prev: (pb: CVPixelBuffer, t: Double)? = nil
    var k = 0
    while let s = out.copyNextSampleBuffer() {
        guard let pb = CMSampleBufferGetImageBuffer(s) else { continue }
        let t = CMSampleBufferGetPresentationTimeStamp(s).seconds * 1000
        if first < 0 { first = t }
        let rel = t - first
        while k < times.count, rel > times[k] {
            if let p = prev { write(p.pb, "\(outDir)/f\(Int(times[k])).png"); print("\(Int(times[k])) actualMs=\(Int(p.t.rounded()))") }
            k += 1
        }
        // keep a copy: the reader recycles buffers
        var copy: CVPixelBuffer?
        CVPixelBufferCreate(nil, CVPixelBufferGetWidth(pb), CVPixelBufferGetHeight(pb), CVPixelBufferGetPixelFormatType(pb), nil, &copy)
        if let copy {
            CVPixelBufferLockBaseAddress(pb, .readOnly); CVPixelBufferLockBaseAddress(copy, [])
            memcpy(CVPixelBufferGetBaseAddress(copy), CVPixelBufferGetBaseAddress(pb), CVPixelBufferGetBytesPerRow(pb) * CVPixelBufferGetHeight(pb))
            CVPixelBufferUnlockBaseAddress(copy, []); CVPixelBufferUnlockBaseAddress(pb, .readOnly)
            prev = (copy, rel)
        }
        if k >= times.count { break }
    }
    while k < times.count { if let p = prev { write(p.pb, "\(outDir)/f\(Int(times[k])).png"); print("\(Int(times[k])) actualMs=\(Int(p.t.rounded())) (last frame)") }; k += 1 }
    reader.cancelReading()
    sem.signal()
}
sem.wait()
