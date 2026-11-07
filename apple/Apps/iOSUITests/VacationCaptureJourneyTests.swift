import XCTest

/// Screenshots of every Vacation page and sheet (a Capture plan class: no source rule selects it).
@MainActor
final class VacationCaptureJourneyTests: VacationJourneyTestCase {
    func testCaptureVacationChooser() { capture(.chooser) }
    func testCaptureVacationChecklist() { capture(.vacationChecklist) }
    func testCaptureVacationDates() { capture(.vacationDates) }
    func testCaptureVacationConfirmSheet() { capture(.confirmSheet) }
    func testCaptureVacationSoloTripIdle() { capture(.soloTripIdle) }
    func testCaptureVacationSoloTripEditor() { capture(.soloTripEditor) }
    func testCaptureVacationSoloTripActive() { capture(.soloTripActive) }
    func testCaptureVacationSoloTripRestore() { capture(.soloTripRestore) }

    /// One page or sheet in the current pose (iPad: both orientations), named `vacation-<page>-<orientation>`.
    private func capture(_ page: Page) {
        let orientations: [UIDeviceOrientation] = FentonHomeApp.family == .iPad ? [.portrait, .landscapeLeft] : [.unknown]
        for orientation in orientations {
            if orientation != .unknown { XCUIDevice.shared.orientation = orientation }
            let suffix = orientation == .landscapeLeft ? "landscape" : orientation == .portrait ? "portrait" : "current"
            let app = open(page, clean: true)
            settleScreen()
            keep("vacation-\(page.rawValue)-\(suffix)")
        }
    }

    private func keep(_ name: String) {
        // Upright: the raw capture stays portrait in landscape (see RenderedContrast).
        let shot = XCUIScreen.main.screenshot().image
        let format = UIGraphicsImageRendererFormat()
        format.scale = shot.scale
        let upright = UIGraphicsImageRenderer(size: shot.size, format: format).image { _ in shot.draw(at: .zero) }
        let attachment = XCTAttachment(image: upright)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        // The host captures the lit panel of an unfolded iPhone Duo (`<name>.ready` asks, `<name>.done` answers).
        guard let folder = ProcessInfo.processInfo.environment["FENTON_CAPTURE_DIR"], !folder.isEmpty else { return }
        let ready = URL(fileURLWithPath: folder).appendingPathComponent("\(name).ready")
        let done = URL(fileURLWithPath: folder).appendingPathComponent("\(name).done")
        FileManager.default.createFile(atPath: ready.path, contents: nil)
        let deadline = Date().addingTimeInterval(30)
        while !FileManager.default.fileExists(atPath: done.path), Date() < deadline { usleep(200_000) }
    }
}
