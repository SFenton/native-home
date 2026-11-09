import Foundation
import Observation

/// Scan Item: barcode, then expiry date, then review, then add (web `ScanItemCameraSheet.tsx`).
///
/// The view owns the camera and reports what it sees (``didDetectBarcode(_:)``, ``readExpiry(jpeg:)``,
/// ``cameraDidFail(_:)``); this model owns every EverShelf call and the copy each step shows. Before inventory
/// is added the product is committed with `prepare_scanned_product`, which also lets EverShelf suggest where it
/// is stored; Add sends one `add_scanned_item` with an idempotency key that only changes when the item does.
@MainActor
@Observable
public final class ScanItemModel {
    // MARK: - Types

    /// The sheet's page (web `ScanItemStep`).
    public enum Step: String, Sendable { case barcode, expiry, review, adding }

    /// The camera, as the view reports it.
    public enum CameraStatus: Equatable, Sendable { case idle, starting, ready, failed(String) }

    /// Barcode lookup progress.
    public enum LookupStatus: Equatable, Sendable { case idle, scanning, resolving, found, notFound, failed(String) }

    /// Expiry reading progress.
    public enum ExpiryStatus: Equatable, Sendable { case idle, ready, reading, found(String), notFound, failed(String) }

    /// Add progress.
    public enum AddStatus: Equatable, Sendable { case idle, adding, added, failed(String) }

    /// Where the selected location came from (`LocationSuggestionStatus`).
    public enum LocationStatus: Equatable, Sendable { case fallback, checking, history, suggested, unknown, unavailable, manual }

    /// Quick expiry choices (`QUICK_EXPIRATION_OPTIONS`).
    public enum QuickExpiry: String, CaseIterable, Sendable, Identifiable {
        case threeDays = "3-days", oneWeek = "1-week", oneMonth = "1-month", sixMonths = "6-months", oneYear = "1-year"
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .threeDays: "In 3 Days"
            case .oneWeek: "In 1 Week"
            case .oneMonth: "In 1 Month"
            case .sixMonths: "In 6 Months"
            case .oneYear: "In 1 Year"
            }
        }
    }

    // MARK: - State

    /// Something has been scanned, typed or picked that closing the sheet would drop (the discard guard,
    /// ``Step``-independent). False before any input and once the item is added.
    public var hasDraft: Bool {
        guard addStatus != .added else { return false }
        return detectedBarcode != nil || !name.isEmpty || !brand.isEmpty || !expiryDate.isEmpty
            || quantityText != "1" || preparedFood
    }

    public private(set) var step: Step = .barcode
    /// The barcode camera was put away (a scan landed, or the name is typed instead).
    public private(set) var barcodeCameraHidden = false
    /// The expiry camera is put away; it starts hidden when a date is already known.
    public private(set) var expiryCameraHidden = true
    public private(set) var cameraStatus: CameraStatus = .idle
    public private(set) var lookupStatus: LookupStatus = .idle
    public private(set) var detectedBarcode: String?
    public private(set) var expiryStatus: ExpiryStatus = .idle
    public private(set) var hasSuccessfulExpiryRead = false
    /// A lookup or expiry read is running (the sheet shows Processing…).
    public private(set) var isProcessing = false

    public private(set) var name = ""
    public private(set) var brand = ""
    public private(set) var quantityText = "1"
    public private(set) var quantityError: String?
    public private(set) var location: StorageLocation
    public private(set) var locationStatus: LocationStatus = .fallback
    /// `YYYY-MM-DD` or empty.
    public private(set) var expiryDate = ""
    public private(set) var preparedFood = false
    public private(set) var addStatus: AddStatus = .idle

    /// The page's location (or the pantry) the location falls back to.
    public let fallbackLocation: StorageLocation
    /// Whether the fallback is the page's own location (changes the hint's wording).
    public let fallbackIsPageDefault: Bool

    @ObservationIgnored public var calendar: InventoryCalendar
    @ObservationIgnored public var makeIdempotencyKey: () -> String = { "scan-\(UUID().uuidString.lowercased())" }

    @ObservationIgnored private let client: EverShelfClient
    @ObservationIgnored private var lookupProduct: JSONValue?
    @ObservationIgnored private var lookupBarcode: String?
    @ObservationIgnored private var locationLookupMode: String?
    @ObservationIgnored private var lastScannedBarcode: String?
    @ObservationIgnored private var serviceGeneration = 0
    @ObservationIgnored private var preparedTouched = false
    @ObservationIgnored private var userSelectedLocation = false
    @ObservationIgnored private var locationGeneration = 0
    @ObservationIgnored private var locationIdentity = ""
    /// The last suggestion request, so tests can await it.
    @ObservationIgnored public private(set) var locationTask: Task<Void, Never>?
    // Product commit lineage (`prepareScannedProduct`).
    @ObservationIgnored private var lineage = 0
    @ObservationIgnored private var prepareGeneration = 0
    @ObservationIgnored private var prepareTask: Task<Void, Never>?
    @ObservationIgnored private var prepareTaskIdentity = ""
    @ObservationIgnored private var reusableProductId: Int?
    @ObservationIgnored private var preparedProduct: (identity: String, merged: Bool, fingerprint: String, productId: Int)?
    @ObservationIgnored private var prepareBlocking: (identity: String, message: String)?
    @ObservationIgnored private var addCommand: (fingerprint: String, key: String, productId: Int?)?

    static let commitFailure = "The barcode product could not be committed. Scan it again before adding inventory."

    // MARK: - Init

    /// Creates the flow for a page.
    public init(space: InventorySpace, client: EverShelfClient, calendar: InventoryCalendar = .current) {
        fallbackLocation = space.defaultScanLocation
        fallbackIsPageDefault = space.hasOwnScanLocation
        location = space.defaultScanLocation
        self.client = client
        self.calendar = calendar
    }

    // MARK: - Camera

    /// The camera the current page wants running, if any.
    public var wantedCamera: Step? {
        switch step {
        case .barcode where !barcodeCameraHidden: .barcode
        case .expiry where !expiryCameraHidden: .expiry
        default: nil
        }
    }

    /// The view started its camera.
    public func cameraDidStart() {
        cameraStatus = .ready
        if step == .barcode, detectedBarcode == nil, lookupStatus == .idle { lookupStatus = .scanning }
        if step == .expiry, expiryStatus == .idle { expiryStatus = .ready }
    }

    /// The view is starting its camera.
    public func cameraWillStart() { cameraStatus = .starting }

    /// The camera could not start (permission denied, none present, the simulator).
    public func cameraDidFail(_ message: String) { cameraStatus = .failed(message) }

    /// The view stopped its camera.
    public func cameraDidStop() { cameraStatus = .idle }

    // MARK: - Barcode step

    /// A barcode was read: the camera goes away and EverShelf looks it up.
    public func didDetectBarcode(_ raw: String) async {
        let barcode = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard step == .barcode, !barcode.isEmpty, barcode != lastScannedBarcode else { return }
        lastScannedBarcode = barcode
        barcodeCameraHidden = true
        isProcessing = true
        await resolve(barcode)
    }

    private func resolve(_ barcode: String) async {
        resetLineage()
        resetLocation()
        preparedTouched = false
        preparedFood = false
        locationLookupMode = "barcode"
        serviceGeneration += 1
        let generation = serviceGeneration
        detectedBarcode = barcode
        lookupStatus = .resolving
        lookupProduct = nil
        lookupBarcode = nil
        defer { if generation == serviceGeneration { isProcessing = false } }
        do {
            let payload = try await client.resolveBarcode(barcode)
            guard generation == serviceGeneration else { return }
            let found = payload["found"]?.bool == true
            lookupStatus = found ? .found : .notFound
            lookupBarcode = payload["barcode"]?.looseString
            guard found, let product = payload["product"], case .object = product else { return }
            lookupProduct = product
            preparedFood = product["prepared_food"].map(InventoryItem.isPreparedFlag) ?? false
            reusableProductId = product["id"]?.positiveInt
            let productName = Self.text(product["name"] ?? product["product_name"] ?? product["title"])
            if !productName.isEmpty { name = productName }
            brand = Self.text(product["brand"] ?? product["brands"])
            addStatus = .idle
        } catch {
            guard generation == serviceGeneration else { return }
            lookupStatus = .failed(ServiceErrorText.message(for: error, fallback: "Unable to resolve barcode."))
        }
    }

    /// Puts the camera away to type the product name.
    public func enterNameManually() {
        resetLineage()
        resetLocation()
        preparedTouched = false
        preparedFood = false
        locationLookupMode = "manual"
        barcodeCameraHidden = true
        cameraStatus = .idle
        if detectedBarcode == nil {
            lastScannedBarcode = nil
            lookupStatus = .idle
        }
    }

    /// Clears the scan and starts the barcode camera again.
    public func scanBarcodeAgain() {
        serviceGeneration += 1
        isProcessing = false
        resetLineage()
        resetLocation()
        preparedTouched = false
        preparedFood = false
        lastScannedBarcode = nil
        barcodeCameraHidden = false
        detectedBarcode = nil
        lookupProduct = nil
        lookupBarcode = nil
        lookupStatus = .idle
        cameraStatus = .idle
    }

    /// Edits the product name; a changed name needs a fresh product commit.
    public func setName(_ value: String) {
        if value.trimmingCharacters(in: .whitespaces) != name.trimmingCharacters(in: .whitespaces) { invalidatePrepared() }
        name = value
        if case .failed = addStatus { addStatus = .idle }
        if detectedBarcode == nil, locationLookupMode != "manual" { locationLookupMode = "manual" }
    }

    // MARK: - Expiry step

    /// Captured a frame of the printed date (JPEG); EverShelf reads it.
    public func readExpiry(jpeg: Data) async {
        serviceGeneration += 1
        let generation = serviceGeneration
        isProcessing = true
        expiryCameraHidden = true
        cameraStatus = .idle
        expiryStatus = .reading
        defer { if generation == serviceGeneration { isProcessing = false } }
        do {
            let payload = try await client.readExpiryImage(dataURL: "data:image/jpeg;base64,\(jpeg.base64EncodedString())")
            guard generation == serviceGeneration else { return }
            let date = (payload["expiry_date"] ?? payload["date"])?.string ?? ""
            if (payload["success"]?.bool == true || payload["found"]?.bool == true) && !date.isEmpty {
                expiryStatus = .found(date)
                expiryDate = date
                hasSuccessfulExpiryRead = true
                addStatus = .idle
            } else if let error = payload["error"], error != .null {
                expiryStatus = .failed(Self.expiryReadMessage(error.looseString ?? "", httpCode: payload["http_code"]))
            } else {
                expiryStatus = .notFound
            }
        } catch {
            guard generation == serviceGeneration else { return }
            expiryStatus = .failed(Self.expiryReadMessage(ServiceErrorText.message(for: error, fallback: ""), httpCode: nil))
        }
    }

    /// Puts the camera away to type or pick the date.
    public func enterExpiryManually() {
        expiryCameraHidden = true
        cameraStatus = .idle
        if expiryDate.isEmpty { expiryStatus = .idle }
    }

    /// Starts the expiry camera again.
    public func readExpiryAgain() {
        serviceGeneration += 1
        isProcessing = false
        expiryCameraHidden = false
        expiryStatus = .idle
        cameraStatus = .idle
    }

    /// Sets or clears the date (`YYYY-MM-DD` or empty).
    public func setExpiryDate(_ value: String) {
        expiryDate = value
        if case .failed = addStatus { addStatus = .idle }
        switch expiryStatus {
        case .failed, .notFound: expiryStatus = .idle
        default: break
        }
    }

    /// The date a quick choice means today.
    public func date(for quick: QuickExpiry) -> String {
        let today = calendar.today
        let target: Date = switch quick {
        case .threeDays: calendar.calendar.date(byAdding: .day, value: 3, to: today) ?? today
        case .oneWeek: calendar.calendar.date(byAdding: .day, value: 7, to: today) ?? today
        case .oneMonth: calendar.adding(months: 1, to: today)
        case .sixMonths: calendar.adding(months: 6, to: today)
        case .oneYear: calendar.adding(months: 12, to: today)
        }
        return calendar.isoString(target)
    }

    /// The quick choice matching the current date, if any.
    public var selectedQuickExpiry: QuickExpiry? { QuickExpiry.allCases.first { date(for: $0) == expiryDate } }

    /// Picks a quick choice.
    public func selectQuickExpiry(_ quick: QuickExpiry) { setExpiryDate(date(for: quick)) }

    // MARK: - Review step

    /// Edits the quantity text; it's validated on Add or when the field loses focus.
    public func setQuantityText(_ value: String) {
        quantityText = value
        quantityError = nil
        if case .failed = addStatus { addStatus = .idle }
    }

    /// Validates the quantity (whole number ≥ 1, decimals floored), showing the error inline.
    @discardableResult
    public func validateQuantity() -> Int? {
        guard let value = Double(quantityText.trimmingCharacters(in: .whitespaces)), value.isFinite, value >= 1 else {
            quantityError = "Quantity must be at least 1."
            return nil
        }
        let quantity = Int(value.rounded(.down))
        quantityText = String(quantity)
        quantityError = nil
        return quantity
    }

    /// The user chose where it goes; suggestions stop overriding it.
    public func selectLocation(_ value: StorageLocation) {
        locationGeneration += 1
        locationIdentity = ""
        userSelectedLocation = true
        location = value
        locationStatus = .manual
    }

    /// Flips the prepared-food flag; the product needs a fresh commit with it.
    public func togglePreparedFood() {
        invalidatePrepared()
        preparedTouched = true
        preparedFood.toggle()
        if case .failed = addStatus { addStatus = .idle }
    }

    // MARK: - Navigation

    /// Back from the expiry page.
    public func goToBarcodeStep() {
        serviceGeneration += 1
        step = .barcode
        isProcessing = false
        cameraStatus = .idle
        if detectedBarcode == nil {
            lastScannedBarcode = nil
            lookupStatus = .idle
        }
        if case .found = expiryStatus {} else { expiryStatus = .idle }
    }

    /// Next from the barcode page; commits the product in the background when a name is known.
    public func goToExpiryStep() {
        serviceGeneration += 1
        step = .expiry
        isProcessing = false
        cameraStatus = .idle
        expiryCameraHidden = !expiryDate.trimmingCharacters(in: .whitespaces).isEmpty || hasSuccessfulExpiryRead
        if detectedBarcode == nil { lookupStatus = .idle }
        if case .found = expiryStatus {} else { expiryStatus = .idle }
        if !name.trimmingCharacters(in: .whitespaces).isEmpty {
            Task { await self.prepareProduct() }
        }
    }

    /// Next from the expiry page.
    public func goToReviewStep() {
        serviceGeneration += 1
        step = .review
        isProcessing = false
        cameraStatus = .idle
    }

    /// The header's back action for the current page, if it has one.
    public func goBack() {
        switch step {
        case .expiry: goToBarcodeStep()
        case .review: goToExpiryStep()
        default: break
        }
    }

    // MARK: - Add

    /// Adds the item. On success the sheet shows "Added to …" with Done; on failure it returns to review.
    public func add() async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let quantity = validateQuantity()
        guard !trimmed.isEmpty else {
            addStatus = .failed("Product name is required before adding to \(location.title).")
            return
        }
        guard let quantity else {
            addStatus = .idle
            return
        }
        serviceGeneration += 1
        let generation = serviceGeneration
        addStatus = .adding
        step = .adding
        if let pending = prepareTask { await pending.value }
        guard generation == serviceGeneration else { return }
        await prepareProduct()
        guard generation == serviceGeneration else { return }

        let input = currentProduct()
        let prepared = preparedProduct?.identity == input.identity ? preparedProduct : nil
        if prepareBlocking?.identity == input.identity || (!input.barcode.isEmpty && prepared == nil) {
            addStatus = .failed(prepareBlocking?.message ?? Self.commitFailure)
            step = .review
            return
        }

        locationGeneration += 1
        locationLookupMode = nil
        var data = input.extras
        data["location"] = .string(location.rawValue)
        data["name"] = .string(trimmed)
        data["quantity"] = .number(Double(quantity))
        if !expiryDate.trimmingCharacters(in: .whitespaces).isEmpty {
            data["expiry_date"] = .string(expiryDate.trimmingCharacters(in: .whitespaces))
            data["expiry_user_set"] = .bool(true)
        }
        if preparedTouched { data["prepared_food"] = .bool(preparedFood) }
        let fingerprint = Self.fingerprint(data)
        if addCommand?.fingerprint != fingerprint {
            addCommand = (fingerprint, makeIdempotencyKey(), prepared?.productId)
        }
        if let productId = addCommand?.productId { data["product_id"] = .number(Double(productId)) }
        data["idempotency_key"] = .string(addCommand?.key ?? makeIdempotencyKey())

        do {
            try await client.addScannedItem(data, location: location)
            guard generation == serviceGeneration else { return }
            addStatus = .added
        } catch {
            guard generation == serviceGeneration else { return }
            addStatus = .failed(ServiceErrorText.message(for: error, fallback: "Unable to add this item to \(location.title)."))
            step = .review
        }
    }

    // MARK: - Product commit

    private struct ProductInput {
        var name: String
        var barcode: String
        var category: String
        var mode: String
        /// Everything but name, location, quantity and expiry, sent with the commit and the add.
        var extras: [String: JSONValue]
        var prepareData: [String: JSONValue]
        var identity: String
    }

    private func currentProduct() -> ProductInput {
        let product = lookupStatus == .found ? lookupProduct : nil
        let name = name.trimmingCharacters(in: .whitespaces)
        let barcode = detectedBarcode ?? lookupBarcode ?? Self.text(product?["barcode"])
        let brand = self.brand.trimmingCharacters(in: .whitespaces).isEmpty ? Self.text(product?["brand"] ?? product?["brands"]) : self.brand.trimmingCharacters(in: .whitespaces)
        let category = Self.text(product?["category"])
        var extras: [String: JSONValue] = [:]
        if !barcode.isEmpty { extras["barcode"] = .string(barcode) }
        if !brand.isEmpty { extras["brand"] = .string(brand) }
        if !category.isEmpty { extras["category"] = .string(category) }
        let image = Self.text(product?["image_url"] ?? product?["image"])
        if !image.isEmpty { extras["image_url"] = .string(image) }
        if let quantity = product?["default_quantity"]?.finiteNumber, quantity >= 0 { extras["default_quantity"] = .number(quantity) }
        for key in ["unit", "notes", "package_unit"] {
            let value = Self.text(product?[key])
            if !value.isEmpty { extras[key] = .string(value) }
        }
        if let nutriments = product?["nutriments"], case .object = nutriments { extras["nutriments"] = nutriments }
        var prepareData = extras
        prepareData["name"] = .string(name)
        if preparedTouched { prepareData["prepared_food"] = .bool(preparedFood) }
        return ProductInput(
            name: name, barcode: barcode, category: category,
            mode: locationLookupMode ?? (barcode.isEmpty ? "manual" : "barcode"),
            extras: extras, prepareData: prepareData, identity: Self.fingerprint(prepareData)
        )
    }

    /// Commits the product (`prepare_scanned_product`) once per distinct input, then asks for a location.
    public func prepareProduct() async {
        let input = currentProduct()
        guard !input.name.isEmpty, preparedProduct?.identity != input.identity else { return }
        if let task = prepareTask {
            if prepareTaskIdentity == input.identity {
                await task.value
                return
            }
            let (startLineage, startGeneration) = (lineage, prepareGeneration)
            await task.value
            guard lineage == startLineage, prepareGeneration == startGeneration, preparedProduct?.identity != input.identity else { return }
        }
        prepareGeneration += 1
        let generation = prepareGeneration
        prepareTaskIdentity = input.identity
        let task = Task { await self.commit(input, generation: generation, lineage: self.lineage) }
        prepareTask = task
        await task.value
        if prepareGeneration == generation {
            prepareTask = nil
            prepareTaskIdentity = ""
        }
    }

    private func commit(_ input: ProductInput, generation: Int, lineage startLineage: Int) async {
        if !userSelectedLocation {
            location = fallbackLocation
            locationStatus = .checking
        }
        var data = input.prepareData
        if let productId = reusableProductId ?? (lookupStatus == .found ? lookupProduct?["id"]?.positiveInt : nil) {
            data["product_id"] = .number(Double(productId))
        }
        func stale() -> Bool { prepareGeneration != generation || lineage != startLineage }
        do {
            let payload = try await client.prepareScannedProduct(data)
            let productId = payload["id"]?.positiveInt
            let fingerprint = payload["product_fingerprint"]?.string.flatMap { $0.count == 64 ? $0 : nil }
            let merged = payload["merged"]?.bool == true
            let success = payload["success"]?.bool != false && productId != nil && fingerprint != nil
            if success, !merged, lineage == startLineage { reusableProductId = productId }
            guard !stale() else { return }
            guard success, let productId, let fingerprint else {
                if !input.barcode.isEmpty || payload["error"]?.string == "barcode_already_used" {
                    prepareBlocking = (input.identity, payload["message"]?.string ?? Self.commitFailure)
                }
                fallBackLocation(.unavailable)
                return
            }
            prepareBlocking = nil
            if !preparedTouched, let flag = payload["prepared_food"] { preparedFood = InventoryItem.isPreparedFlag(flag) }
            preparedProduct = (input.identity, merged, fingerprint, productId)
            guard !userSelectedLocation else { return }
            locationTask = Task { await self.suggestLocation(for: input, productId: productId, fingerprint: fingerprint) }
        } catch {
            guard !stale() else { return }
            if !input.barcode.isEmpty { prepareBlocking = (input.identity, Self.commitFailure) }
            fallBackLocation(.unavailable)
        }
    }

    private func suggestLocation(for input: ProductInput, productId: Int, fingerprint: String) async {
        guard !userSelectedLocation else { return }
        let identity = [input.mode, input.barcode, input.name.lowercased(), input.category.lowercased(), String(productId), fingerprint].joined(separator: "\u{0}")
        guard locationIdentity != identity else { return }
        locationIdentity = identity
        locationGeneration += 1
        let generation = locationGeneration
        location = fallbackLocation
        locationStatus = .checking
        var data: [String: JSONValue] = [
            "mode": .string(input.mode), "name": .string(input.name),
            "product_fingerprint": .string(fingerprint), "product_id": .number(Double(productId)),
        ]
        if !input.barcode.isEmpty { data["barcode"] = .string(input.barcode) }
        if !input.category.isEmpty { data["category"] = .string(input.category) }
        do {
            let payload = try await client.suggestLocation(data)
            guard generation == locationGeneration, !userSelectedLocation else { return }
            if payload["success"]?.bool == false { return fallBackLocation(.unavailable) }
            let suggested = payload["location"]?.string
            if suggested == "unknown" { return fallBackLocation(.unknown) }
            guard let suggested, let value = StorageLocation(rawValue: suggested) else { return fallBackLocation(.unavailable) }
            location = value
            let source = payload["source"]?.string
            locationStatus = source == "history_barcode" || source == "history_name" ? .history : .suggested
        } catch {
            guard generation == locationGeneration, !userSelectedLocation else { return }
            fallBackLocation(.unavailable)
        }
    }

    private func fallBackLocation(_ status: LocationStatus) {
        guard !userSelectedLocation else { return }
        location = fallbackLocation
        locationStatus = status
    }

    private func invalidatePrepared() {
        prepareGeneration += 1
        prepareTaskIdentity = ""
        if preparedProduct?.merged == true { reusableProductId = nil }
        preparedProduct = nil
        prepareBlocking = nil
        locationGeneration += 1
        locationIdentity = ""
        fallBackLocation(.fallback)
    }

    private func resetLineage() {
        prepareGeneration += 1
        prepareTaskIdentity = ""
        prepareTask = nil
        lineage += 1
        reusableProductId = nil
        prepareBlocking = nil
        preparedProduct = nil
    }

    private func resetLocation() {
        locationGeneration += 1
        locationIdentity = ""
        userSelectedLocation = false
        location = fallbackLocation
        locationLookupMode = nil
        locationStatus = .fallback
    }

    // MARK: - Copy

    /// Header subtitle, e.g. `Scan Barcode · Step 1 of 3`.
    public var subtitle: String {
        switch step {
        case .barcode: "\(barcodeCameraHidden ? "Enter Product Name" : "Scan Barcode") · Step 1 of 3"
        case .expiry: "Expiration Date · Step 2 of 3"
        case .review: "Review Item · Step 3 of 3"
        case .adding: addStatus == .added ? "Item Added" : "Adding Item"
        }
    }

    /// The page's instructions.
    public var instructions: String {
        switch step {
        case .barcode:
            barcodeCameraHidden ? "Review or enter the product name before continuing."
                : "Use the product barcode to look up item details. Center the barcode inside the camera window and hold steady."
        case .expiry:
            if !expiryCameraHidden {
                "Take a clear photo of the printed expiration date. Center it inside the camera window and keep the label flat."
            } else if hasSuccessfulExpiryRead {
                "Review or adjust the expiration date before continuing."
            } else {
                "Enter the expiration date manually, or read it from the camera."
            }
        case .review: "Confirm the item details before adding it to your \(location.phrase)."
        case .adding: ""
        }
    }

    /// A lookup or read result worth showing under the camera or field, if any.
    public var statusMessage: String? {
        switch step {
        case .barcode:
            switch lookupStatus {
            case .notFound: detectedBarcode.map { "No barcode match found for \($0)." }
            case let .failed(message): message
            default: nil
            }
        case .expiry:
            switch expiryStatus {
            case .notFound: "No expiration date found in that image."
            case let .failed(message): message
            default: nil
            }
        default: nil
        }
    }

    /// Whether ``statusMessage`` is an error (vs. a no-match notice).
    public var statusIsError: Bool {
        switch (step, lookupStatus, expiryStatus) {
        case (.barcode, .failed, _), (.expiry, _, .failed): true
        default: false
        }
    }

    /// Forward button title on the barcode page.
    public var barcodeForwardTitle: String {
        barcodeCameraHidden || hasBarcodeValue ? "Next" : "Skip Barcode"
    }

    /// The barcode page has something to carry forward.
    public var hasBarcodeValue: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty || detectedBarcode != nil }

    /// Forward is unavailable while a lookup runs or with the field open and empty.
    public var barcodeForwardDisabled: Bool {
        lookupStatus == .resolving || (barcodeCameraHidden && name.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    /// `Scan Barcode` or `Scan Barcode Again`.
    public var scanBarcodeTitle: String { detectedBarcode == nil ? "Scan Barcode" : "Scan Barcode Again" }

    /// The expiry page has a date to carry forward.
    public var hasExpiryValue: Bool {
        if case .found = expiryStatus { return true }
        return !expiryDate.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Forward button title on the expiry page.
    public var expiryForwardTitle: String { expiryCameraHidden || hasExpiryValue ? "Next" : "Skip Expiration" }

    /// Forward is unavailable while reading or with the field open and empty.
    public var expiryForwardDisabled: Bool { expiryStatus == .reading || (expiryCameraHidden && !hasExpiryValue) }

    /// `Read Expiration Date` or `… Again`.
    public var readExpiryTitle: String { hasSuccessfulExpiryRead ? "Read Expiration Date Again" : "Read Expiration Date" }

    /// Capture is possible: the expiry camera is up and ready.
    public var canReadExpiry: Bool {
        addStatus != .added && step == .expiry && !expiryCameraHidden && cameraStatus == .ready && expiryStatus != .reading
    }

    /// Add is possible.
    public var canAdd: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && addStatus != .adding && expiryStatus != .reading }

    /// Where the location came from, under the location choices.
    public var locationHint: String {
        let fallback = fallbackIsPageDefault ? "current page default" : "app default"
        return switch locationStatus {
        case .checking: "Checking previous items and the best storage location…"
        case .history: "Selected from your previous EverShelf entries."
        case .suggested: "Suggested for this product by EverShelf."
        case .unknown: "No confident match; using the \(fallback)."
        case .unavailable: "Storage suggestion unavailable; using the \(fallback)."
        case .manual: "Location selected manually."
        case .fallback: "Using the \(fallback) until EverShelf finds a better match."
        }
    }

    /// The add error to show on the review page.
    public var addError: String? {
        if case let .failed(message) = addStatus { return message }
        return nil
    }

    // MARK: - Helpers

    static func text(_ value: JSONValue?) -> String {
        value?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// AI quota errors get a message that says to type the date (`expirationReadErrorMessage`).
    static func expiryReadMessage(_ message: String, httpCode: JSONValue?) -> String {
        let lower = message.lowercased()
        if httpCode?.finiteNumber == 429 || lower.contains("429") || lower.contains("too many requests")
            || lower.contains("quota") || lower.contains("rate limit") {
            return "AI-based expiration date parsing is unavailable. Please enter the expiration date manually or try again later."
        }
        return message.isEmpty ? "Unable to read expiration date." : message
    }

    static func fingerprint(_ data: [String: JSONValue]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(data)).map { String(decoding: $0, as: UTF8.self) } ?? ""
    }
}
