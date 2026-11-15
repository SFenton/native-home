#if os(iOS)
import HassCore
import HassDesign
import Observation
import UIKit

// MARK: - Canonical scan lifecycle behind the generic form

@MainActor @Observable
final class UKServerUIScanForm: ServerUISteppedFormSession {
    let identity: ServerUIDraft.Identity
    let model: ScanItemModel
    let camera: ScanCameraController
    private let added: () async throws -> Void
    private var submitted = false
    private var closed = false
    private var failure: String?
    private var saving = false

    init(sourceID: String, model: ScanItemModel, camera: ScanCameraController,
         added: @escaping () async throws -> Void) {
        identity = .init(ownerId: sourceID, recordId: UUID().uuidString)
        self.model = model; self.camera = camera; self.added = added
    }
    var hasChanges: Bool { !submitted && model.hasDraft }
    var isBusy: Bool { saving || model.isProcessing || model.addStatus == .adding || model.lookupStatus == .resolving || model.expiryStatus == .reading }
    var canSave: Bool { !closed && !isBusy && ((model.step == .review && model.canAdd) || (submitted && failure != nil)) }
    var canReset: Bool { false }
    var needsRefresh: Bool { submitted && failure != nil }
    var error: String? { failure ?? model.addError ?? (model.statusIsError ? model.statusMessage : nil) }
    var progress: ServerUIFormProgress {
        .init(subtitle: model.subtitle,
              forwardTitle: model.step == .barcode ? model.barcodeForwardTitle : model.step == .expiry ? model.expiryForwardTitle : nil,
              forwardEnabled: !isBusy && (model.step == .barcode ? !model.barcodeForwardDisabled : !model.expiryForwardDisabled),
              hasPrevious: model.step == .expiry || model.step == .review, canSubmit: model.step == .review || (submitted && failure != nil))
    }
    var groups: [ServerUIFormGroup] {
        if model.isProcessing { return [] }
        let cameraVisible = model.step == .barcode ? !model.barcodeCameraHidden : model.step == .expiry && !model.expiryCameraHidden
        var camera = ServerUIFormValue.text("camera", "Scan", "", control: .scanCamera)
        camera.visible = cameraVisible
        var name = ServerUIFormValue.text("name", "Name", model.name, required: true)
        name.visible = (model.step == .barcode && model.barcodeCameraHidden) || model.step == .review
        var quantity = ServerUIFormValue.number("quantity", "How Many", Double(model.quantityText) ?? 1, minimum: 1, maximum: InventoryCatalog.maxQuantity)
        quantity.visible = model.step == .review
        let expiryVisible = (model.step == .expiry && model.expiryCameraHidden) || model.step == .review
        var hasExpiry = ServerUIFormValue.toggle("hasExpiry", "Expiration Date", !model.expiryDate.isEmpty)
        hasExpiry.visible = expiryVisible
        var expiry = ServerUIFormValue.text("expiry", "Expires", model.expiryDate, control: .date)
        expiry.visible = expiryVisible && !model.expiryDate.isEmpty
        var quick = ServerUIFormValue.choice("quickExpiry", "Quick Expiration Dates", model.selectedQuickExpiry?.rawValue ?? "",
            ScanItemModel.QuickExpiry.allCases.map { .init($0.title, $0.rawValue) }, control: .options)
        quick.visible = model.step == .expiry && model.expiryCameraHidden
        var prepared = ServerUIFormValue.toggle("prepared", "Prepared Food", model.preparedFood)
        prepared.visible = model.step == .review
        var location = ServerUIFormValue.choice("location", "Where should it be stored?", model.location.rawValue,
            StorageLocation.allCases.map { .init($0.title, $0.rawValue) }, control: .options)
        location.visible = model.step == .review
        return [
            .init(id: "camera", fields: [camera]),
            .init(id: "details", title: model.step == .expiry ? "When does it expire?" : "What item are you adding?",
                  footer: model.step == .review
                    ? (model.quantityError.map { $0 + "\n" } ?? "") + InventoryEditorModel.preparedFoodNote : "",
                  fields: [name, quantity, hasExpiry, expiry, prepared]),
            .init(id: "quick", title: "Quick Expiration Dates", fields: [quick]),
            .init(id: "location", title: "Where should it be stored?", footer: model.locationHint, fields: [location]),
        ].filter { $0.fields.contains(where: \.visible) }
    }

    func set(_ value: ServerUICompositionDocument.LocalValue, group: String, field: String) throws {
        guard !isBusy, !closed else { throw ServerUIRecordFailure.busy }
        guard let descriptor = groups.first(where: { $0.id == group })?.fields.first(where: { $0.key == field }),
              descriptor.visible, descriptor.accepts(value) else { throw ServerUIRecordFailure.invalidField }
        switch (field, value) {
        case ("name", .string(let value)): model.setName(value)
        case ("quantity", .number(let value)): model.setQuantityText(String(Int(value)))
        case ("hasExpiry", .boolean(let value)): model.setExpiryDate(value ? model.calendar.isoString(model.calendar.today) : "")
        case ("expiry", .string(let value)):
            guard InventoryCalendar.isValidInput(value) else { throw ServerUIRecordFailure.invalidValue }
            model.setExpiryDate(value)
        case ("quickExpiry", .string(let value)):
            guard let quick = ScanItemModel.QuickExpiry(rawValue: value) else { throw ServerUIRecordFailure.invalidValue }
            model.selectQuickExpiry(quick)
        case ("prepared", .boolean(let value)):
            if model.preparedFood != value { model.togglePreparedFood() }
        case ("location", .string(let value)):
            guard let location = StorageLocation(rawValue: value) else { throw ServerUIRecordFailure.invalidValue }
            model.selectLocation(location)
        default: throw ServerUIRecordFailure.invalidField
        }
    }
    func advance() throws {
        guard progress.forwardEnabled, !closed else { throw ServerUIRecordFailure.busy }
        if model.step == .barcode { model.goToExpiryStep() }
        else if model.step == .expiry { model.goToReviewStep() }
        else { throw ServerUIRecordFailure.invalidValue }
    }
    func retreat() throws {
        guard !isBusy, progress.hasPrevious, !closed else { throw ServerUIRecordFailure.busy }
        model.goBack()
    }
    func save() async throws {
        guard canSave else { throw ServerUIRecordFailure.invalidValue }
        saving = true
        defer { saving = false }
        if !submitted {
            await model.add()
            guard model.addStatus == .added else { throw ServerUIRecordFailure.unavailable(model.addError ?? "Unable to add this item.") }
            submitted = true
        }
        camera.stop()
        do { try await added(); failure = nil }
        catch { failure = "Item added, but the inventory refresh failed."; throw error }
    }
    func reset() throws { throw ServerUIRecordFailure.invalidValue }
    func discard() throws {
        guard !isBusy else { throw ServerUIRecordFailure.busy }
        camera.stop()
        closed = true
    }

    static func factory(sourceID: String, makeModel: @escaping () -> ScanItemModel,
                        makeCamera: @escaping () -> ScanCameraController = { ScanCameraController() },
                        added: @escaping () async throws -> Void) -> UKServerUIFormFactory {
        .init(fields: ["camera": .scanCamera, "name": .text, "quantity": .number, "hasExpiry": .toggle,
                       "expiry": .date, "quickExpiry": .options, "prepared": .toggle, "location": .options],
              selectionOnly: false) {
            UKServerUIScanForm(sourceID: sourceID, model: makeModel(), camera: makeCamera(), added: added)
        }
    }
}

// MARK: - Camera atoms, not a feature controller

@MainActor
final class UKServerUIScanCamera: UIView {
    private let session: UKServerUIScanForm
    private let stack = UIStackView()
    private let barcode = UKScanViewfinder(symbol: "barcode.viewfinder", label: "Live item scan camera feed", step: .barcode)
    private let expiry = UKScanViewfinder(symbol: "camera", label: "Live expiration date camera feed", step: .expiry)
    private let bag = UKObservationBag()
    private var cameraTask: Task<Void, Never>?
    private var cameraKey = ""
    private var shownStep: ScanItemModel.Step?

    init(_ session: UKServerUIScanForm) {
        self.session = session
        super.init(frame: .zero)
        stack.axis = .vertical
        addSubview(stack); stack.ukPin(to: self)
        barcode.onManual = { [session] in session.model.enterNameManually() }
        expiry.onManual = { [session] in session.model.enterExpiryManually() }
        for finder in [barcode, expiry] {
            finder.onSimulate = { [session] in Task { await session.camera.simulate(on: session.model) } }
        }
        bag.observe { [weak self] in self?.update() }
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { cameraTask?.cancel(); session.camera.stop(); cameraKey = "" }
        else { update() }
    }
    private func update() {
        let model = session.model, camera = session.camera
        let key = "\(model.step.rawValue)|\(model.wantedCamera?.rawValue ?? "-")"
        if window != nil, cameraKey != key {
            cameraKey = key
            cameraTask?.cancel()
            cameraTask = Task { await camera.sync(with: model) }
        }
        barcode.update(model: model, camera: camera)
        expiry.update(model: model, camera: camera)
        guard shownStep != model.step else { return }
        shownStep = model.step
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let finder = model.step == .barcode ? barcode : expiry
        stack.addArrangedSubview(finder.row)
        stack.addArrangedSubview(UKScanManualButton(title: model.step == .barcode ? "Manually Enter Name" : "Manually Enter Expiration Date",
            identifier: model.step == .barcode ? "scan.manualName" : "scan.manualExpiry") { finder.onManual() })
    }
}
#endif
