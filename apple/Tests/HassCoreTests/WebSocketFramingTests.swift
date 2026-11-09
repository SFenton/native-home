import Foundation
@preconcurrency import Starscream
import Testing

/// Guards the frames HAKit's websocket engine writes to Home Assistant.
///
/// On iOS HAKit connects through Starscream's `WSEngine` with `WSCompression` (permessage-deflate). Starscream
/// 4.0.9 compressed every frame it wrote, control frames included, so the pong it sends for Home Assistant's
/// 55-second heartbeat ping carried RSV1. aiohttp fails a connection on a control frame with RSV1
/// ("Received frame with non-zero reserved bits", RFC 7692 §6.1), so the app's connection dropped about once a
/// minute. Starscream 4.0.10 (via HAKit 0.4.19) compresses only text and binary frames.
struct WebSocketFramingTests {
    /// FIN bit of a frame's first byte.
    private static let fin: UInt8 = 0x80
    /// RSV1, the per-message compressed bit.
    private static let rsv1: UInt8 = 0x40

    /// Records the bytes the engine writes instead of opening a socket.
    private final class CapturingTransport: Transport, @unchecked Sendable {
        private let lock = NSLock()
        private var written: [Data] = []

        var frames: [Data] { lock.withLock { written } }
        var usingTLS: Bool { false }

        func register(delegate: TransportEventClient) {}
        func connect(url: URL, timeout: Double, certificatePinning: CertificatePinning?) {}
        func disconnect() {}

        func write(data: Data, completion: @escaping ((Error?) -> Void)) {
            lock.withLock { written.append(data) }
            completion(nil)
        }
    }

    /// Accepts any upgrade response (the handshake itself is not under test).
    private final class AcceptingValidator: HeaderValidator {
        func validate(headers: [String: String], key: String) -> Error? { nil }
    }

    /// An engine built the way HAKit builds it on iOS, upgraded with permessage-deflate negotiated.
    private func makeNegotiatedEngine() -> (WSEngine, CapturingTransport) {
        let transport = CapturingTransport()
        let engine = WSEngine(transport: transport, headerValidator: AcceptingValidator(), compressionHandler: WSCompression())
        engine.start(request: URLRequest(url: URL(string: "wss://home.example/api/websocket")!))
        // The upgrade response Home Assistant (aiohttp) sends when it accepts permessage-deflate.
        engine.didReceiveHTTP(event: .success(["Sec-WebSocket-Extensions": "permessage-deflate"]))
        return (engine, transport)
    }

    /// Waits for the engine's write queue to flush `count` frames.
    private func frames(_ transport: CapturingTransport, count: Int) async throws -> [Data] {
        for _ in 0..<500 where transport.frames.count < count { try await Task.sleep(for: .milliseconds(10)) }
        let frames = transport.frames
        try #require(frames.count == count)
        return frames
    }

    @Test func heartbeatPongIsNotCompressed() async throws {
        let (engine, transport) = makeNegotiatedEngine()
        // Home Assistant's heartbeat: an empty, unmasked ping from the server.
        engine.connectionChanged(state: .receive(Data([Self.fin | FrameOpCode.ping.rawValue, 0x00])))
        let pong = try await frames(transport, count: 1)[0]
        #expect(pong[0] == Self.fin | FrameOpCode.pong.rawValue)
    }

    @Test func controlFramesAreNotCompressed() async throws {
        let (engine, transport) = makeNegotiatedEngine()
        engine.write(data: Data(), opcode: .pong, completion: nil)
        engine.write(data: Data("ping".utf8), opcode: .ping, completion: nil)
        engine.write(data: Data([0x03, 0xE8]), opcode: .connectionClose, completion: nil)
        let firstBytes = try await frames(transport, count: 3).map { $0[0] }
        #expect(firstBytes == [
            Self.fin | FrameOpCode.pong.rawValue,
            Self.fin | FrameOpCode.ping.rawValue,
            Self.fin | FrameOpCode.connectionClose.rawValue,
        ])
    }

    @Test func messagesStayCompressed() async throws {
        let (engine, transport) = makeNegotiatedEngine()
        engine.write(string: #"{"id":1,"type":"subscribe_entities"}"#, completion: nil)
        let message = try await frames(transport, count: 1)[0]
        #expect(message[0] == Self.fin | Self.rsv1 | FrameOpCode.textFrame.rawValue)
    }
}
