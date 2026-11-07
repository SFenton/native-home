import Foundation
@testable import HassCore
import HassTestSupport
import Testing

// MARK: - Draft

@Suite("Feedback draft")
struct FeedbackDraftTests {
    @Test func prefixIsKept() {
        var draft = FeedbackDraft(kind: .bug)
        #expect(draft.title == "[Bug] ")
        draft.setTitle("[Bug] Lights flicker")
        #expect(draft.title == "[Bug] Lights flicker")
        draft.setTitle("[Bug]")
        #expect(draft.title == "[Bug] ")
        draft.setTitle("[Bu")
        #expect(draft.title == "[Bug] ")
        draft.setTitle("Typed over")
        #expect(draft.title == "[Bug] Typed over")
        draft.setTitle("[Bug]Squashed")
        #expect(draft.title == "[Bug] Squashed")
        #expect(FeedbackDraft.prefixedTitle("   spaced", kind: .feature) == "[Feature] spaced")
    }

    @Test func validationOrder() {
        var draft = FeedbackDraft(kind: .bug)
        #expect(draft.validationIssue == .missingTitle)
        #expect(!draft.hasTypedInput)
        draft.setTitle("[Bug] X")
        #expect(draft.hasTypedInput)
        #expect(draft.validationIssue == .missingDescription)
        draft.description = "  "
        #expect(draft.validationIssue == .missingDescription)
        draft.description = "Broken"
        #expect(draft.validationIssue == nil)
        draft.reproSteps = String(repeating: "a", count: FeedbackLimits.bodyCharacters + 1)
        #expect(draft.validationIssue == .textTooLong)
        draft.reproSteps = ""
        draft.setTitle("[Bug] " + String(repeating: "t", count: FeedbackLimits.titleCharacters))
        #expect(draft.validationIssue == .titleTooLong)
    }

    @Test func featureIgnoresReproBoxes() {
        var draft = FeedbackDraft(kind: .feature)
        draft.setTitle("[Feature] Idea")
        draft.description = "More"
        draft.reproSteps = String(repeating: "a", count: FeedbackLimits.bodyCharacters + 1)
        #expect(draft.validationIssue == nil)
        #expect(!FeedbackDraft(kind: .feature).hasTypedInput)
        var expected = FeedbackDraft(kind: .bug)
        expected.expectedBehavior = "x"
        #expect(expected.hasTypedInput)
    }

    @Test func messagesAndKindCopy() {
        for issue in [FeedbackValidationIssue.missingTitle, .titleTooLong, .missingDescription, .textTooLong] {
            #expect(!issue.message.isEmpty)
        }
        #expect(FeedbackKind.bug.formTitle == "Report an Issue")
        #expect(FeedbackKind.feature.formTitle == "Request a Feature")
        #expect(FeedbackKind.bug.label == "Bug" && FeedbackKind.feature.label == "Feature")
        #expect(FeedbackKind.bug.noun == "report" && FeedbackKind.feature.noun == "request")
        #expect(FeedbackKind.bug.symbol == "ladybug" && FeedbackKind.feature.symbol == "lightbulb")
        #expect(FeedbackKind.bug.includesReproduction && !FeedbackKind.feature.includesReproduction)
        #expect(FeedbackKind.allCases.allSatisfy { !$0.rowSubtitle.isEmpty && $0.id == $0.rawValue })
    }
}

// MARK: - Platform, attachments

@Suite("Feedback platform and attachments")
struct FeedbackAttachmentTests {
    @Test func platformPrecedence() {
        #expect(FeedbackPlatform.resolve(isPad: false, hasHinge: false) == .ios)
        #expect(FeedbackPlatform.resolve(isPad: true, hasHinge: false) == .ipados)
        #expect(FeedbackPlatform.resolve(isPad: false, hasHinge: true) == .iphoneDuo)
        #expect(FeedbackPlatform.resolve(isPad: true, hasHinge: true) == .iphoneDuo)
        #expect(FeedbackPlatform.allCases.map(\.label) == ["iOS", "iPadOS", "iPhone Duo"])
    }

    @Test func mediaClassification() {
        #expect(FeedbackAttachmentPolicy.media(forFilename: "a.png")?.isVideo == false)
        #expect(FeedbackAttachmentPolicy.media(forFilename: "a.PNG")?.mimeType == "image/png")
        #expect(FeedbackAttachmentPolicy.media(forFilename: "clip.mov")?.isVideo == true)
        #expect(FeedbackAttachmentPolicy.media(forFilename: "clip.mp4")?.mimeType == "video/mp4")
        #expect(FeedbackAttachmentPolicy.media(forFilename: "notes.txt") == nil)
        #expect(FeedbackAttachmentPolicy.media(forFilename: "noext") == nil)
    }

    @Test func filenamesAreSanitized() {
        #expect(FeedbackAttachmentPolicy.sanitizedFilename("dir/IMG 1.png") == "IMG 1.png")
        #expect(FeedbackAttachmentPolicy.sanitizedFilename("a\"b:c[d](e)<f>.jpg") == "abcdef.jpg")
        #expect(FeedbackAttachmentPolicy.sanitizedFilename("  \n ") == "attachment")
        let long = FeedbackAttachmentPolicy.sanitizedFilename(String(repeating: "x", count: 200) + ".mov")
        #expect(long.count == 120 && long.hasSuffix(".mov"))
        #expect(FeedbackAttachmentPolicy.sanitizedFilename(String(repeating: "y", count: 130)).count == 120)
    }

    @Test func admissionLimits() {
        let one = attachment()
        #expect(FeedbackAttachmentPolicy.rejection(byteCount: 10, filename: "a", existing: []) == nil)
        #expect(FeedbackAttachmentPolicy.rejection(byteCount: FeedbackLimits.attachmentBytes + 1, filename: "a", existing: []) == .fileTooLarge("a"))
        let full = Array(repeating: one, count: FeedbackLimits.attachments)
        #expect(FeedbackAttachmentPolicy.rejection(byteCount: 1, filename: "a", existing: full) == .tooMany)
        for rejection in [FeedbackAttachmentRejection.tooMany, .fileTooLarge("a"), .unsupportedType("a"), .unreadable, .locationNotRemoved("a")] {
            #expect(rejection.errorDescription?.isEmpty == false)
        }
    }

    @Test func accessibilityLabel() {
        let photo = attachment(name: "shot.png", bytes: 2_000_000, video: false)
        #expect(photo.accessibilityLabel(position: 1).hasPrefix("Photo 1, shot.png, "))
        #expect(attachment(name: "clip.mov", video: true).accessibilityLabel(position: 2).hasPrefix("Video 2, clip.mov"))
    }

    func attachment(name: String = "a.png", bytes: Int64 = 10, video: Bool = false) -> FeedbackAttachment {
        FeedbackAttachment(fileURL: URL(fileURLWithPath: "/tmp/\(name)"), filename: name,
                           mimeType: video ? "video/quicktime" : "image/png", byteCount: bytes, isVideo: video)
    }
}

// MARK: - Report

@Suite("Feedback report")
struct FeedbackReportTests {
    static let diagnostics = FeedbackDiagnostics(
        app: "0.1.0 (1)", system: "iOS 27.1", device: "iPhone (iPhone18,1)", window: "402 × 874 pt, compact width, portrait",
        homeAssistant: "2026.10.1, connected", accessibility: "Text large, VoiceOver off, Reduce Motion off, Light",
        locale: "en_US, America/Los_Angeles"
    )

    @Test func bugReport() throws {
        var draft = FeedbackDraft(kind: .bug)
        draft.setTitle("[Bug] Garage stuck")
        draft.description = "  It broke \n"
        draft.reproSteps = "1. Open"
        draft.expectedBehavior = " "
        let photo = FeedbackAttachment(fileURL: URL(fileURLWithPath: "/tmp/a.png"), filename: "a.png", mimeType: "image/png", byteCount: 1, isVideo: false)
        let video = FeedbackAttachment(fileURL: URL(fileURLWithPath: "/tmp/b.mov"), filename: "b.mov", mimeType: "video/quicktime", byteCount: 1, isVideo: true)
        let report = FeedbackReport(draft: draft, platform: .iphoneDuo, diagnostics: Self.diagnostics, media: [
            (photo, URL(string: "https://github.com/user-attachments/assets/1")!),
            (video, URL(string: "https://github.com/user-attachments/assets/2")!),
        ])
        #expect(report.kind == "bug" && report.platform == "iphone-duo")
        #expect(report.title == "[Bug] Garage stuck" && report.description == "It broke")
        #expect(report.repro == "1. Open" && report.expected == nil)
        #expect(report.diagnostics.first == ["App", "0.1.0 (1)"] && report.diagnostics.count == 7)
        #expect(report.media == [.init(name: "a.png", url: "https://github.com/user-attachments/assets/1", video: false),
                                 .init(name: "b.mov", url: "https://github.com/user-attachments/assets/2", video: true)])
        let json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(report)) as? [String: Any])
        #expect(json["kind"] as? String == "bug")
        #expect(json["expected"] == nil, "Empty optional boxes are left out")
        #expect((json["diagnostics"] as? [[String]])?.last == ["Locale", "en_US, America/Los_Angeles"])
    }

    @Test func featureReportDropsBugBoxes() {
        var draft = FeedbackDraft(kind: .feature)
        draft.setTitle("[Feature] Dark mode")
        draft.description = "Please"
        draft.reproSteps = "ignored"
        let report = FeedbackReport(draft: draft, platform: .ios, diagnostics: Self.diagnostics, media: [])
        #expect(report.kind == "feature" && report.repro == nil && report.media.isEmpty)
    }

    @Test func diagnosticsFormatting() {
        #expect(FeedbackDiagnostics.appVersion(["CFBundleShortVersionString": "1.2", "CFBundleVersion": "7"]) == "1.2 (7)")
        #expect(FeedbackDiagnostics.appVersion(nil) == "? (?)")
        let date = Date(timeIntervalSince1970: 1_791_900_000)
        #expect(FeedbackDiagnostics.appVersion(["CFBundleShortVersionString": "1", "CFBundleVersion": "2"], buildDate: date).hasPrefix("1 (2), built 2026-"))
        #expect(FeedbackDiagnostics.windowText(width: 402, height: 874.4, regularWidth: false) == "402 × 874 pt, compact width, portrait")
        #expect(FeedbackDiagnostics.windowText(width: 1210, height: 834, regularWidth: true) == "1210 × 834 pt, regular width, landscape")
        #expect(Self.diagnostics.rows.map(\.label) == ["App", "System", "Device", "Window", "Home Assistant", "Accessibility", "Locale"])
        #expect(FiledIssue(number: 3, url: URL(string: "https://x")!).number == 3)
    }
}

// MARK: - Home Assistant client

@Suite("Home Assistant feedback client")
struct HomeAssistantFeedbackClientTests {
    let server = HassServer(baseURL: URL(string: "https://ha.example.com")!)

    func client(_ transport: StubHTTPTransport, token: String = "ha-token") -> HomeAssistantFeedbackClient {
        HomeAssistantFeedbackClient(server: server, accessToken: { token }, transport: transport)
    }

    func attachment(_ data: Data = Data([1, 2, 3])) throws -> FeedbackAttachment {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("upload-\(UUID().uuidString).png")
        try data.write(to: file)
        return FeedbackAttachment(fileURL: file, filename: "shot one.png", mimeType: "image/png", byteCount: Int64(data.count), isVideo: false)
    }

    @Test func statusReadsAvailability() async throws {
        let transport = StubHTTPTransport([(200, #"{"available":true}"#), (200, #"{"available":false}"#), (404, "")])
        let filer = client(transport)
        #expect(try await filer.isAvailable())
        #expect(try await !filer.isAvailable())
        #expect(try await !filer.isAvailable(), "No integration answers 404")
        #expect(transport.requests[0].url?.absoluteString == "https://ha.example.com/api/fenton_feedback/status")
        #expect(transport.requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer ha-token")
        await #expect(throws: FeedbackFilingError.signedOut) {
            try await client(StubHTTPTransport([(401, "")])).isAvailable()
        }
    }

    @Test func uploadSendsOneRawFile() async throws {
        let file = try attachment()
        defer { try? FileManager.default.removeItem(at: file.fileURL) }
        let transport = StubHTTPTransport([(200, #"{"url":"https://github.com/user-attachments/assets/abc"}"#)])
        let url = try await client(transport).upload(file)
        #expect(url.absoluteString == "https://github.com/user-attachments/assets/abc")
        let request = try #require(transport.requests.first)
        #expect(request.httpMethod == "POST" && request.url?.path == "/api/fenton_feedback/media")
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(query.contains(URLQueryItem(name: "name", value: "shot one.png")))
        #expect(query.contains(URLQueryItem(name: "content_type", value: "image/png")))
        #expect(request.httpBody == Data([1, 2, 3]))
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/octet-stream")
    }

    @Test func uploadFailures() async throws {
        let file = try attachment()
        defer { try? FileManager.default.removeItem(at: file.fileURL) }
        await #expect(throws: FeedbackFilingError.attachmentRejected("shot one.png")) {
            try await client(StubHTTPTransport([(422, #"{"code":"attachment_rejected"}"#)])).upload(file)
        }
        await #expect(throws: FeedbackFilingError.notConfigured) {
            try await client(StubHTTPTransport([(503, #"{"code":"not_configured"}"#)])).upload(file)
        }
        await #expect(throws: FeedbackFilingError.unexpectedResponse) {
            try await client(StubHTTPTransport([(200, #"{"url":"http://insecure"}"#)])).upload(file)
        }
        let missing = FeedbackAttachment(fileURL: URL(fileURLWithPath: "/nonexistent/x.png"), filename: "x.png", mimeType: "image/png", byteCount: 1, isVideo: false)
        await #expect(throws: FeedbackFilingError.attachmentRejected("x.png")) {
            try await client(StubHTTPTransport([])).upload(missing)
        }
    }

    @Test func submitPostsTheReport() async throws {
        var draft = FeedbackDraft(kind: .bug)
        draft.setTitle("[Bug] X")
        draft.description = "Y"
        let report = FeedbackReport(draft: draft, platform: .ios, diagnostics: FeedbackReportTests.diagnostics, media: [])
        let transport = StubHTTPTransport([(201, #"{"number":7,"url":"https://github.com/example/requests/issues/7"}"#)])
        let filed = try await client(transport).submit(report)
        #expect(filed.number == 7)
        let request = try #require(transport.requests.first)
        #expect(request.url?.path == "/api/fenton_feedback/report" && request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let json = try #require(try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
        #expect(json["title"] as? String == "[Bug] X")
        await #expect(throws: FeedbackFilingError.githubProblem) {
            try await client(StubHTTPTransport([(502, #"{"code":"github_token_rejected"}"#)])).submit(report)
        }
        await #expect(throws: FeedbackFilingError.unexpectedResponse) {
            try await client(StubHTTPTransport([(201, #"{"number":7}"#)])).submit(report)
        }
    }

    @Test func transportAndTokenFailures() async {
        let offline = StubHTTPTransport([])
        offline.error = URLError(.notConnectedToInternet)
        await #expect(throws: FeedbackFilingError.network) { try await client(offline).isAvailable() }
        let cancelled = StubHTTPTransport([])
        cancelled.error = CancellationError()
        await #expect(throws: CancellationError.self) { try await client(cancelled).isAvailable() }
        let typed = StubHTTPTransport([])
        typed.error = FeedbackFilingError.rateLimited
        await #expect(throws: FeedbackFilingError.rateLimited) { try await client(typed).isAvailable() }
        let noToken = HomeAssistantFeedbackClient(server: server, accessToken: { throw URLError(.userAuthenticationRequired) },
                                                  transport: StubHTTPTransport([]))
        await #expect(throws: FeedbackFilingError.signedOut) { try await noToken.isAvailable() }
        let cancelledToken = HomeAssistantFeedbackClient(server: server, accessToken: { throw CancellationError() },
                                                         transport: StubHTTPTransport([]))
        await #expect(throws: CancellationError.self) { try await cancelledToken.isAvailable() }
    }

    @Test func errorMapping() {
        let map = FeedbackFilingError.forResponse
        #expect(map(503, "not_configured", nil) == .notConfigured)
        #expect(map(429, "rate_limited", nil) == .rateLimited)
        #expect(map(413, "payload_too_large", nil) == .tooLarge)
        #expect(map(415, "unsupported_media", nil) == .unsupportedMedia)
        #expect(map(422, "attachment_rejected", nil) == .attachmentRejected("An attachment"))
        #expect(map(502, "github_no_issue_access", nil) == .githubProblem)
        #expect(map(400, "title_required", nil) == .invalidReport)
        #expect(map(401, nil, nil) == .signedOut)
        #expect(map(404, nil, nil) == .notConfigured)
        #expect(map(413, nil, nil) == .tooLarge)
        #expect(map(415, nil, nil) == .unsupportedMedia)
        #expect(map(429, nil, nil) == .rateLimited)
        #expect(map(400, nil, nil) == .invalidReport)
        #expect(map(503, nil, nil) == .githubProblem)
        #expect(map(418, nil, nil) == .unexpectedResponse)
        let all: [FeedbackFilingError] = [.notConfigured, .githubProblem, .invalidReport, .attachmentRejected("a"), .tooLarge,
                                          .unsupportedMedia, .rateLimited, .signedOut, .network, .unexpectedResponse]
        #expect(all.allSatisfy { $0.errorDescription?.isEmpty == false })
    }
}

// MARK: - Fixture

@Suite("Feedback fixture")
struct FeedbackFixtureTests {
    @Test func fixtureAnswers() async throws {
        let fixture = FeedbackFixtureFiler()
        #expect(try await fixture.isAvailable())
        let attachment = FeedbackAttachment(fileURL: URL(fileURLWithPath: "/tmp/a.png"), filename: "a.png", mimeType: "image/png", byteCount: 1, isVideo: false)
        #expect(try await fixture.upload(attachment).absoluteString.hasSuffix("fixture-1"))
        var draft = FeedbackDraft(kind: .bug)
        draft.setTitle("[Bug] ok")
        draft.description = "d"
        let ok = FeedbackReport(draft: draft, platform: .ios, diagnostics: FeedbackReportTests.diagnostics, media: [])
        #expect(try await fixture.submit(ok).number == 1)
        #expect(fixture.submittedReports.count == 1)
        draft.setTitle("[Bug] fixture-failed")
        await #expect(throws: FeedbackFilingError.githubProblem) {
            try await fixture.submit(FeedbackReport(draft: draft, platform: .ios, diagnostics: FeedbackReportTests.diagnostics, media: []))
        }
        draft.setTitle("[Bug] fixture-limited")
        await #expect(throws: FeedbackFilingError.rateLimited) {
            try await fixture.submit(FeedbackReport(draft: draft, platform: .ios, diagnostics: FeedbackReportTests.diagnostics, media: []))
        }
        let missing = FeedbackFixtureFiler(available: false)
        #expect(try await !missing.isAvailable())
        await #expect(throws: FeedbackFilingError.notConfigured) { try await missing.upload(attachment) }
        await #expect(throws: FeedbackFilingError.notConfigured) { try await missing.submit(ok) }
    }
}
