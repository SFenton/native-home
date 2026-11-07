// Frames of a screen recording as one contact sheet, for motion evidence.
//   xcrun swift tools/video_frames.swift MOVIE OUT.png START END FPS [COLUMNS] [CELL_WIDTH]
// Samples MOVIE from START to END seconds at FPS frames per second and lays the frames out left to right, top to bottom, each labelled
// with its time. tools/motion_evidence.py calls it once per move, with the times the journey marked.
import AVFoundation
import AppKit

let args = CommandLine.arguments
guard args.count >= 6, let start = Double(args[3]), let end = Double(args[4]), let fps = Double(args[5]) else {
    FileHandle.standardError.write(Data("usage: video_frames.swift MOVIE OUT.png START END FPS [COLUMNS] [CELL_WIDTH]\n".utf8))
    exit(2)
}
let columns = args.count > 6 ? Int(args[6]) ?? 6 : 6
let cellWidth = args.count > 7 ? CGFloat(Double(args[7]) ?? 190) : 190
let asset = AVURLAsset(url: URL(fileURLWithPath: args[1]))
let generator = AVAssetImageGenerator(asset: asset)
generator.requestedTimeToleranceBefore = .zero
generator.requestedTimeToleranceAfter = .zero
generator.appliesPreferredTrackTransform = true
let duration = CMTimeGetSeconds(asset.duration)
var frames: [(Double, CGImage)] = []
var t = max(start, 0)
while t <= min(end, duration - 0.05) {
    if let image = try? generator.copyCGImage(at: CMTime(seconds: t, preferredTimescale: 600), actualTime: nil) { frames.append((t, image)) }
    t += 1 / fps
}
guard let first = frames.first else {
    FileHandle.standardError.write(Data("no frames between \(start) and \(end) (movie is \(duration) s)\n".utf8))
    exit(1)
}
let cellHeight = cellWidth * CGFloat(first.1.height) / CGFloat(first.1.width)
let label: CGFloat = 16
let rows = (frames.count + columns - 1) / columns
let size = CGSize(width: CGFloat(columns) * (cellWidth + 4) + 4, height: CGFloat(rows) * (cellHeight + label + 4) + 4)
let image = NSImage(size: size)
image.lockFocus()
NSColor(white: 0.08, alpha: 1).setFill()
NSRect(origin: .zero, size: size).fill()
for (index, frame) in frames.enumerated() {
    let col = index % columns, row = index / columns
    let x = 4 + CGFloat(col) * (cellWidth + 4)
    let y = size.height - 4 - CGFloat(row + 1) * (cellHeight + label + 4) + 4
    NSImage(cgImage: frame.1, size: .zero).draw(in: NSRect(x: x, y: y, width: cellWidth, height: cellHeight))
    let text = String(format: "%.2fs", frame.0) as NSString
    text.draw(at: NSPoint(x: x + 2, y: y + cellHeight + 1), withAttributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.white])
}
image.unlockFocus()
guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: args[2]))
print("\(frames.count) frames -> \(args[2])")
