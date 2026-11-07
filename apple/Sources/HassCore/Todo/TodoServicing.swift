import Foundation
@preconcurrency import HAKit

/// What todo pages need from Home Assistant beyond plain service calls. ``HassConnection`` is the app's
/// implementation; tests and the debug gallery use fixtures, so automated runs never touch the house.
@MainActor
public protocol TodoServicing: EverShelfCalling {
    /// The items of a `todo` list (`todo/item/list`).
    func todoItems(entityId: String) async throws -> [TodoItem]
    /// Creates an admin to-do with images (multipart POST to ``ChoresConfig/adminTodoUploadPath``).
    func uploadAdminTodo(_ upload: AdminTodoUpload, accessToken: String) async throws
}

extension HassConnection: TodoServicing {
    public func todoItems(entityId: String) async throws -> [TodoItem] {
        let result = try await requestJSON("todo/item/list", data: ["entity_id": entityId])
        guard let items = result["items"]?.array else { throw UnexpectedResponse(command: "todo/item/list") }
        return items.compactMap(TodoItem.init(json:))
    }

    public func uploadAdminTodo(_ upload: AdminTodoUpload, accessToken: String) async throws {
        let request = upload.request(server: server, accessToken: accessToken)
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw UnexpectedResponse(command: ChoresConfig.adminTodoUploadPath)
        }
    }
}

/// An admin to-do with images, sent as `multipart/form-data` (web `CreateTodoItemSheet.tsx`).
public struct AdminTodoUpload: Sendable, Equatable {
    /// One attached image.
    public struct Image: Sendable, Equatable {
        public var data: Data
        public var filename: String
        /// `image/png`, `image/jpeg` or `image/webp`.
        public var mimeType: String

        public init(data: Data, filename: String, mimeType: String) {
            self.data = data
            self.filename = filename
            self.mimeType = mimeType
        }
    }

    public var entityId: String
    public var item: String
    public var images: [Image]
    /// Multipart boundary; fixed in tests.
    public var boundary: String

    public init(entityId: String, item: String, images: [Image], boundary: String = "FentonHome-\(UUID().uuidString)") {
        self.entityId = entityId
        self.item = item
        self.images = images
        self.boundary = boundary
    }

    /// Up to four images (web `MAX_IMAGES`).
    public static let maxImages = 4
    /// 10 MB each (web `MAX_IMAGE_BYTES`).
    public static let maxImageBytes = 10 * 1024 * 1024
    /// Accepted image types.
    public static let mimeTypes: Set<String> = ["image/jpeg", "image/png", "image/webp"]

    /// Why a selection can't be sent, in the web's words, or `nil` when it can.
    public static func validationError(count: Int, sizes: [Int], mimeTypes: [String]) -> String? {
        if count > maxImages { return "Select no more than four images." }
        if mimeTypes.contains(where: { !Self.mimeTypes.contains($0) }) { return "Select PNG, JPEG, or WebP images." }
        if sizes.contains(where: { $0 > maxImageBytes }) { return "Each image must be 10 MB or smaller." }
        return nil
    }

    /// The POST request with a bearer token.
    public func request(server: HassServer, accessToken: String) -> URLRequest {
        var request = URLRequest(url: server.url(ChoresConfig.adminTodoUploadPath))
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return request
    }

    /// The multipart body: `entity_id`, `item`, then each image as `images`.
    var body: Data {
        var body = Data()
        func append(_ string: String) { body.append(Data(string.utf8)) }
        for (name, value) in [("entity_id", entityId), ("item", item)] {
            append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n")
        }
        for image in images {
            let filename = image.filename.replacingOccurrences(of: "\"", with: "")
            append("--\(boundary)\r\nContent-Disposition: form-data; name=\"images\"; filename=\"\(filename)\"\r\n")
            append("Content-Type: \(image.mimeType)\r\n\r\n")
            body.append(image.data)
            append("\r\n")
        }
        append("--\(boundary)--\r\n")
        return body
    }
}
