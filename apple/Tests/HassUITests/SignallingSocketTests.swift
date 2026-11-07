import Foundation
import HassTelemetry
@testable import HassUI
import Testing

/// The camera signalling sockets are released with their streams: the resume-stutter lane found four tasks (about
/// 170 KB each) left allocated per background and foreground, one per camera.
@MainActor
@Suite(.serialized) // The live count is process-wide.
struct SignallingSocketTests {
    /// A port nothing listens on: the socket connects, fails and reports it, like a camera that is unreachable.
    private let url = URL(string: "ws://127.0.0.1:1/api/webrtc/ws")!

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<300 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
    }

    @Test func cancelledSocketsAreReleasedAndTheCountStaysFlatOverResumes() async {
        let baseline = SignallingSocket.liveCount
        for _ in 0..<6 { // Six resumes of four cameras.
            var sockets: [SignallingSocket] = []
            for _ in 0..<4 {
                let socket = SignallingSocket(url: url)
                socket.resume()
                socket.receive { _ in }
                sockets.append(socket)
            }
            #expect(SignallingSocket.liveCount == baseline + 4)
            for socket in sockets { socket.cancel() }
            sockets.removeAll()
            await waitUntil { SignallingSocket.liveCount == baseline }
            #expect(SignallingSocket.liveCount == baseline, "Every socket's session ended with it")
        }
    }

    @Test func cancellingTwiceIsHarmless() async {
        let baseline = SignallingSocket.liveCount
        let socket = SignallingSocket(url: url)
        socket.resume()
        socket.cancel()
        socket.cancel()
        await waitUntil { SignallingSocket.liveCount == baseline }
        #expect(SignallingSocket.liveCount == baseline)
    }

    @Test func aSocketDroppedWithoutCancellingStillEndsItsSession() async {
        let baseline = SignallingSocket.liveCount
        do {
            let socket = SignallingSocket(url: url)
            socket.resume()
            socket.receive { _ in }
        }
        await waitUntil { SignallingSocket.liveCount == baseline }
        #expect(SignallingSocket.liveCount == baseline)
    }

    @Test func theCensusReportsTheLiveSockets() {
        let socket = SignallingSocket(url: url)
        #expect(ResourceCensus.shared.counts()["Camera.signallingSockets"] == SignallingSocket.liveCount)
        socket.cancel()
    }
}
