import Foundation

/// The server's reply to `fenton_home/house_config`: `{"schema": 1, "hash": "…", "config": {…}}` when a house is
/// configured, `{"configured": false}` when it is not.
///
/// `schema` sits beside `config` in the reply, while ``HouseConfig/decode(_:)`` reads the document with its own
/// `schema` inside; ``decode(_:)`` reassembles the two so the same schema rules apply.
public struct HouseConfigEnvelope: Equatable, Sendable {
    /// The configured house, or `nil` when the server has none.
    public var config: HouseConfig?
    /// The server's hash of the document, or `nil` when none is configured. Equal hashes mean an unchanged house.
    public var hash: String?

    /// Creates an envelope.
    public init(config: HouseConfig?, hash: String?) {
        self.config = config
        self.hash = hash
    }

    /// Reads the server reply.
    /// - Parameter data: The reply's JSON.
    /// - Throws: ``HouseConfig/DecodeError``, including `unsupportedSchema` for a newer schema.
    public static func decode(_ data: Data) throws -> HouseConfigEnvelope {
        let reply: Reply
        do {
            reply = try JSONDecoder().decode(Reply.self, from: data)
        } catch {
            throw HouseConfig.DecodeError.malformed(String(describing: error))
        }
        guard reply.configured != false else { return HouseConfigEnvelope(config: nil, hash: nil) }
        guard let schema = reply.schema, case var .object(document)? = reply.config else {
            throw HouseConfig.DecodeError.malformed("reply has no schema and config")
        }
        document["schema"] = .number(Double(schema))
        do {
            return HouseConfigEnvelope(config: try HouseConfig.decode(JSONEncoder().encode(JSONValue.object(document))), hash: reply.hash)
        } catch let error as HouseConfig.DecodeError {
            throw error
        } catch {
            throw HouseConfig.DecodeError.malformed(String(describing: error))
        }
    }

    /// The reply's shape before the document is judged.
    private struct Reply: Decodable {
        var configured: Bool?
        var schema: Int?
        var hash: String?
        var config: JSONValue?
    }
}
