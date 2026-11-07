import Foundation
@testable import HassCore
import Testing

/// Scan Item against the fixture server (and a stub for unusual answers): barcode, expiry, review and add.
/// "Today" is 2026-10-11 (UTC).
@MainActor
struct ScanItemModelTests {
    private let barcode = "0123456789012"
    private let rateLimited = "AI-based expiration date parsing is unavailable. Please enter the expiration date manually or try again later."
    private let fingerprint64 = String(repeating: "a", count: 64)

    private func makeModel(_ space: InventorySpace = .fridge, _ caller: (any EverShelfCalling)? = nil) -> (ScanItemModel, EverShelfFixtureServer) {
        let server = EverShelfFixtureServer(rows: [])
        let model = ScanItemModel(space: space, client: EverShelfClient(caller: caller ?? server), calendar: InventoryFixtures.calendar())
        model.makeIdempotencyKey = { "key-1" }
        return (model, server)
    }

    private func sleep(_ milliseconds: Int) async { try? await Task.sleep(for: .milliseconds(milliseconds)) }

    private func addCalls(_ server: EverShelfFixtureServer) -> [String] {
        server.calls.filter { $0.hasPrefix("evershelf.add_scanned_item") }
    }

    // MARK: Initial state

    @Test func hasNoDraftUntilSomethingIsEntered() {
        let (model, _) = makeModel()
        #expect(!model.hasDraft)
        model.setQuantityText("2")
        #expect(model.hasDraft)
        model.setQuantityText("1")
        #expect(!model.hasDraft)
        model.setName("Milk")
        #expect(model.hasDraft)
    }

    @Test func startsOnTheBarcodePage() {
        let (model, server) = makeModel()
        #expect(model.step == .barcode)
        #expect(model.location == .fridge)
        #expect(model.fallbackLocation == .fridge)
        #expect(model.fallbackIsPageDefault)
        #expect(model.locationStatus == .fallback)
        #expect(model.locationHint == "Using the current page default until EverShelf finds a better match.")
        #expect(model.subtitle == "Scan Barcode · Step 1 of 3")
        #expect(model.instructions
            == "Use the product barcode to look up item details. Center the barcode inside the camera window and hold steady.")
        #expect(model.wantedCamera == .barcode)
        #expect(model.barcodeForwardTitle == "Skip Barcode")
        #expect(!model.barcodeForwardDisabled)
        #expect(model.scanBarcodeTitle == "Scan Barcode")
        #expect(!model.hasBarcodeValue)
        #expect(!model.canAdd)
        #expect(!model.canReadExpiry)
        #expect(model.statusMessage == nil)
        #expect(!model.statusIsError)
        #expect(model.quantityText == "1")
        #expect(model.expiryDate == "")
        #expect(model.expiryCameraHidden)
        #expect(model.addError == nil)
        #expect(model.cameraStatus == .idle)
        #expect(server.calls.isEmpty)
    }

    @Test func allFoodFallsBackToThePantry() {
        let (model, _) = makeModel(.allFood)
        #expect(model.location == .pantry)
        #expect(!model.fallbackIsPageDefault)
        #expect(model.locationHint == "Using the app default until EverShelf finds a better match.")
    }

    // MARK: Camera

    @Test func cameraHooks() {
        let (model, _) = makeModel()
        model.cameraWillStart()
        #expect(model.cameraStatus == .starting)
        model.cameraDidStart()
        #expect(model.cameraStatus == .ready)
        #expect(model.lookupStatus == .scanning)
        model.cameraDidFail("No camera")
        #expect(model.cameraStatus == .failed("No camera"))
        model.cameraDidStop()
        #expect(model.cameraStatus == .idle)

        model.goToExpiryStep()
        #expect(model.lookupStatus == .idle)
        #expect(model.wantedCamera == .expiry)
        model.cameraDidStart()
        #expect(model.expiryStatus == .ready)
        #expect(model.canReadExpiry)
    }

    // MARK: Barcode

    @Test func barcodeFound() async {
        let (model, server) = makeModel()
        await model.didDetectBarcode(" \(barcode)\n")
        #expect(model.lookupStatus == .found)
        #expect(model.detectedBarcode == barcode)
        #expect(model.name == "Greek Yogurt")
        #expect(model.brand == "Fixture Dairy")
        #expect(!model.preparedFood)
        #expect(model.barcodeCameraHidden)
        #expect(!model.isProcessing)
        #expect(model.wantedCamera == nil)
        #expect(model.subtitle == "Enter Product Name · Step 1 of 3")
        #expect(model.instructions == "Review or enter the product name before continuing.")
        #expect(model.barcodeForwardTitle == "Next")
        #expect(!model.barcodeForwardDisabled)
        #expect(model.scanBarcodeTitle == "Scan Barcode Again")
        #expect(model.hasBarcodeValue)
        #expect(model.statusMessage == nil)
        #expect(model.canAdd)
        #expect(server.calls == ["evershelf.resolve_barcode barcode=\(barcode)"])

        await model.didDetectBarcode(barcode)
        await model.didDetectBarcode("   ")
        #expect(server.calls.count == 1, "Repeats and blanks are ignored")
    }

    @Test func cameraDidStartAfterAScanKeepsTheLookup() async {
        let (model, _) = makeModel()
        await model.didDetectBarcode(barcode)
        model.cameraDidStart()
        #expect(model.lookupStatus == .found)
    }

    @Test func barcodeNotFound() async {
        let (model, _) = makeModel()
        await model.didDetectBarcode("999")
        #expect(model.lookupStatus == .notFound)
        #expect(model.name == "")
        #expect(model.statusMessage == "No barcode match found for 999.")
        #expect(!model.statusIsError)
        #expect(model.hasBarcodeValue)
        #expect(model.barcodeForwardTitle == "Next")
        #expect(model.barcodeForwardDisabled, "The name field is open and empty")
    }

    @Test func barcodeLookupFails() async {
        let (model, server) = makeModel()
        server.failing = ["evershelf.resolve_barcode"]
        await model.didDetectBarcode(barcode)
        #expect(model.lookupStatus == .failed("EverShelf is unavailable"))
        #expect(model.statusMessage == "EverShelf is unavailable")
        #expect(model.statusIsError)
        #expect(!model.isProcessing)
    }

    @Test func barcodeProductFallbackKeys() async {
        let (model, server) = makeModel()
        server.products["222"] = ["product_name": .string(" Oats "), "brands": .string("Quaker"), "prepared_food": .number(1)]
        await model.didDetectBarcode("222")
        #expect(model.name == "Oats")
        #expect(model.brand == "Quaker")
        #expect(model.preparedFood)
    }

    @Test func barcodeFoundWithoutAProductObject() async {
        let stub = InventoryStubCaller()
        stub.responses["resolve_barcode"] = .object(["found": .bool(true), "barcode": .number(123)])
        let (model, _) = makeModel(.fridge, stub)
        await model.didDetectBarcode("123")
        #expect(model.lookupStatus == .found)
        #expect(model.name == "")
    }

    @Test func aStaleLookupIsIgnored() async {
        let (model, server) = makeModel()
        server.latency = .milliseconds(600)
        let lookup = Task { await model.didDetectBarcode(barcode) }
        #expect(await eventually { model.lookupStatus == .resolving })
        #expect(model.lookupStatus == .resolving)
        #expect(model.isProcessing)
        #expect(model.barcodeForwardDisabled)
        model.scanBarcodeAgain()
        await lookup.value
        #expect(model.lookupStatus == .idle)
        #expect(model.name == "")
        #expect(model.detectedBarcode == nil)
    }

    @Test func enterNameManually() async {
        let (model, _) = makeModel()
        model.cameraDidStart()
        model.enterNameManually()
        #expect(model.barcodeCameraHidden)
        #expect(model.lookupStatus == .idle)
        #expect(model.cameraStatus == .idle)
        #expect(model.wantedCamera == nil)
        #expect(model.barcodeForwardDisabled)
        model.setName("Milk")
        #expect(model.name == "Milk")
        #expect(!model.barcodeForwardDisabled)
        #expect(model.hasBarcodeValue)

        // After a scan, typing keeps the lookup.
        let (scanned, _) = makeModel()
        await scanned.didDetectBarcode(barcode)
        scanned.enterNameManually()
        #expect(scanned.lookupStatus == .found)
    }

    @Test func scanBarcodeAgain() async {
        let (model, server) = makeModel()
        await model.didDetectBarcode(barcode)
        model.scanBarcodeAgain()
        #expect(model.detectedBarcode == nil)
        #expect(model.lookupStatus == .idle)
        #expect(!model.barcodeCameraHidden)
        #expect(model.wantedCamera == .barcode)
        #expect(model.scanBarcodeTitle == "Scan Barcode")
        await model.didDetectBarcode(barcode)
        #expect(server.calls.count == 2, "The same barcode can be scanned again")
    }

    // MARK: Navigation and copy

    @Test func stepsAndCopy() {
        let (model, server) = makeModel()
        model.goToExpiryStep()
        #expect(model.step == .expiry)
        #expect(model.subtitle == "Expiration Date · Step 2 of 3")
        #expect(!model.expiryCameraHidden)
        #expect(model.wantedCamera == .expiry)
        #expect(model.instructions
            == "Take a clear photo of the printed expiration date. Center it inside the camera window and keep the label flat.")
        #expect(model.expiryForwardTitle == "Skip Expiration")
        #expect(!model.expiryForwardDisabled)
        #expect(model.readExpiryTitle == "Read Expiration Date")
        #expect(!model.hasExpiryValue)
        #expect(model.statusMessage == nil)

        model.enterExpiryManually()
        #expect(model.expiryCameraHidden)
        #expect(model.instructions == "Enter the expiration date manually, or read it from the camera.")
        #expect(model.expiryForwardTitle == "Next")
        #expect(model.expiryForwardDisabled)
        model.setExpiryDate("2026-10-20")
        #expect(model.hasExpiryValue)
        #expect(!model.expiryForwardDisabled)

        model.goToReviewStep()
        #expect(model.step == .review)
        #expect(model.subtitle == "Review Item · Step 3 of 3")
        #expect(model.instructions == "Confirm the item details before adding it to your fridge.")
        #expect(model.wantedCamera == nil)
        #expect(model.statusMessage == nil)
        #expect(!model.statusIsError)

        model.goBack()
        #expect(model.step == .expiry)
        #expect(model.expiryCameraHidden, "A known date keeps the camera away")
        model.goBack()
        #expect(model.step == .barcode)
        model.goBack()
        #expect(model.step == .barcode)
        #expect(server.calls.isEmpty, "No name, no product commit")
    }

    @Test func goingForwardWithANameCommitsTheProduct() async {
        let (model, server) = makeModel()
        model.setName("Milk")
        model.goToExpiryStep()
        #expect(await eventually { server.calls.contains { $0.hasPrefix("evershelf.suggest_location") } })
        #expect(server.calls.first == "evershelf.prepare_scanned_product name=Milk")
        #expect(server.calls.contains { $0.hasPrefix("evershelf.suggest_location") })
    }

    // MARK: Expiry reading

    @Test func readExpirySuccess() async {
        let (model, server) = makeModel()
        model.goToExpiryStep()
        model.cameraDidStart()
        await model.readExpiry(jpeg: Data([1, 2, 3]))
        #expect(server.calls.last == "evershelf.read_expiry_image image=data:image/jpeg;base64,AQID")
        #expect(model.expiryStatus == .found("2030-01-15"))
        #expect(model.expiryDate == "2030-01-15")
        #expect(model.hasSuccessfulExpiryRead)
        #expect(!model.isProcessing)
        #expect(model.expiryCameraHidden)
        #expect(model.cameraStatus == .idle)
        #expect(!model.canReadExpiry)
        #expect(model.instructions == "Review or adjust the expiration date before continuing.")
        #expect(model.readExpiryTitle == "Read Expiration Date Again")
        #expect(model.expiryForwardTitle == "Next")
        #expect(model.hasExpiryValue)

        model.readExpiryAgain()
        #expect(!model.expiryCameraHidden)
        #expect(model.expiryStatus == .idle)
        #expect(model.hasExpiryValue, "The date read earlier stays")

        model.goToBarcodeStep()
        model.goToExpiryStep()
        #expect(model.expiryCameraHidden)
    }

    @Test func foundExpirySurvivesGoingBack() async {
        let (model, _) = makeModel()
        model.goToExpiryStep()
        await model.readExpiry(jpeg: Data())
        model.goToBarcodeStep()
        #expect(model.expiryStatus == .found("2030-01-15"))
        model.goToExpiryStep()
        #expect(model.expiryStatus == .found("2030-01-15"))
    }

    @Test func readExpiryFromDateKey() async {
        let (model, server) = makeModel()
        server.expiryReading = .object(["found": .bool(true), "date": .string("2031-02-03")])
        model.goToExpiryStep()
        await model.readExpiry(jpeg: Data())
        #expect(model.expiryStatus == .found("2031-02-03"))
    }

    nonisolated static let notFoundReadings: [JSONValue] = [
        .object(["success": .bool(false)]),
        .object(["success": .bool(true), "expiry_date": .string("")]),
        .object(["success": .bool(false), "error": .null]),
    ]

    @Test(arguments: ScanItemModelTests.notFoundReadings)
    func readExpiryNotFound(reading: JSONValue) async {
        let (model, server) = makeModel()
        server.expiryReading = reading
        model.goToExpiryStep()
        await model.readExpiry(jpeg: Data())
        #expect(model.expiryStatus == .notFound)
        #expect(model.statusMessage == "No expiration date found in that image.")
        #expect(!model.statusIsError)
        #expect(!model.hasSuccessfulExpiryRead)
        model.setExpiryDate("")
        #expect(model.expiryStatus == .idle)
    }

    @Test func readExpiryRateLimited() async {
        let (model, server) = makeModel()
        server.expiryReading = .object(["success": .bool(false), "error": .string("upstream"), "http_code": .number(429)])
        model.goToExpiryStep()
        await model.readExpiry(jpeg: Data())
        #expect(model.expiryStatus == .failed(rateLimited))
        #expect(model.statusMessage == rateLimited)
        #expect(model.statusIsError)
    }

    @Test func readExpiryErrorMessages() async {
        let (model, server) = makeModel()
        model.goToExpiryStep()
        server.expiryReading = .object(["error": .string("Blurry photo")])
        await model.readExpiry(jpeg: Data())
        #expect(model.expiryStatus == .failed("Blurry photo"))
        server.expiryReading = .object(["error": .string("")])
        await model.readExpiry(jpeg: Data())
        #expect(model.expiryStatus == .failed("Unable to read expiration date."))
        model.setExpiryDate("2026-10-20")
        #expect(model.expiryStatus == .idle)
    }

    @Test func readExpiryThrows() async {
        let (model, server) = makeModel()
        server.failing = ["evershelf.read_expiry_image"]
        model.goToExpiryStep()
        await model.readExpiry(jpeg: Data())
        #expect(model.expiryStatus == .failed("EverShelf is unavailable"))
        #expect(!model.isProcessing)

        let stub = InventoryStubCaller()
        stub.errors["read_expiry_image"] = InventoryStubError()
        let (quiet, _) = makeModel(.fridge, stub)
        quiet.goToExpiryStep()
        await quiet.readExpiry(jpeg: Data())
        #expect(quiet.expiryStatus == .failed("Unable to read expiration date."))
    }

    @Test func aStaleReadIsIgnored() async {
        let (model, server) = makeModel()
        server.latency = .milliseconds(600)
        model.goToExpiryStep()
        let read = Task { await model.readExpiry(jpeg: Data()) }
        #expect(await eventually { model.expiryStatus == .reading })
        #expect(model.expiryStatus == .reading)
        #expect(model.isProcessing)
        #expect(model.expiryForwardDisabled)
        model.goToBarcodeStep()
        #expect(model.expiryStatus == .idle)
        #expect(!model.isProcessing)
        await read.value
        #expect(model.expiryStatus == .idle)
        #expect(model.expiryDate == "")
    }

    @Test func enterExpiryManuallyClearsAFailedRead() async {
        let (model, server) = makeModel()
        server.expiryReading = .object(["error": .string("Blurry")])
        model.goToExpiryStep()
        await model.readExpiry(jpeg: Data())
        model.enterExpiryManually()
        #expect(model.expiryStatus == .idle)
    }

    @Test func expiryReadMessage() {
        for message in ["Too Many Requests", "Quota exceeded", "rate limit hit", "HTTP 429"] {
            #expect(ScanItemModel.expiryReadMessage(message, httpCode: nil) == rateLimited)
        }
        #expect(ScanItemModel.expiryReadMessage("x", httpCode: .number(429)) == rateLimited)
        #expect(ScanItemModel.expiryReadMessage("x", httpCode: .string("429")) == rateLimited)
        #expect(ScanItemModel.expiryReadMessage("Blurry", httpCode: .number(500)) == "Blurry")
        #expect(ScanItemModel.expiryReadMessage("", httpCode: nil) == "Unable to read expiration date.")
    }

    // MARK: Quick expiry

    @Test func quickExpiryDates() {
        let (model, _) = makeModel()
        #expect(ScanItemModel.QuickExpiry.allCases.map { model.date(for: $0) }
            == ["2026-10-14", "2026-10-18", "2026-11-11", "2027-04-11", "2027-10-11"])
        #expect(model.selectedQuickExpiry == nil)
        model.selectQuickExpiry(.oneWeek)
        #expect(model.expiryDate == "2026-10-18")
        #expect(model.selectedQuickExpiry == .oneWeek)
        model.setExpiryDate("2026-10-19")
        #expect(model.selectedQuickExpiry == nil)
        #expect(ScanItemModel.QuickExpiry.allCases.map(\.title) == ["In 3 Days", "In 1 Week", "In 1 Month", "In 6 Months", "In 1 Year"])
        #expect(ScanItemModel.QuickExpiry.sixMonths.id == "6-months")
    }

    @Test func quickExpiryClampsToTheMonthEnd() {
        let model = ScanItemModel(
            space: .fridge, client: EverShelfClient(caller: EverShelfFixtureServer(rows: [])),
            calendar: InventoryFixtures.calendar(year: 2026, month: 1, day: 31)
        )
        #expect(ScanItemModel.QuickExpiry.allCases.map { model.date(for: $0) }
            == ["2026-02-03", "2026-02-07", "2026-02-28", "2026-07-31", "2027-01-31"])
    }

    // MARK: Quantity

    @Test func quantityValidation() {
        let (model, _) = makeModel()
        model.setQuantityText("2.7")
        #expect(model.validateQuantity() == 2)
        #expect(model.quantityText == "2")
        model.setQuantityText(" 3 ")
        #expect(model.validateQuantity() == 3)
        for bad in ["0", "0.5", "abc", "", "inf", "-2"] {
            model.setQuantityText(bad)
            #expect(model.validateQuantity() == nil)
            #expect(model.quantityError == "Quantity must be at least 1.")
        }
        model.setQuantityText("4")
        #expect(model.quantityError == nil)
    }

    // MARK: Location

    @Test func selectLocationIsManual() {
        let (model, _) = makeModel()
        model.selectLocation(.freezer)
        #expect(model.location == .freezer)
        #expect(model.locationStatus == .manual)
        #expect(model.locationHint == "Location selected manually.")
    }

    @Test func suggestionFromHistory() async {
        let (model, server) = makeModel(.allFood)
        model.setName("Milk")
        await model.prepareProduct()
        await model.locationTask?.value
        #expect(model.location == .fridge)
        #expect(model.locationStatus == .history)
        #expect(model.locationHint == "Selected from your previous EverShelf entries.")
        #expect(server.calls == [
            "evershelf.prepare_scanned_product name=Milk",
            "evershelf.suggest_location mode=manual name=Milk product_fingerprint=\(String(repeating: "a", count: 24))… product_id=901",
        ])

        // The same product is not committed or suggested twice.
        await model.prepareProduct()
        #expect(server.calls.count == 2)
    }

    @Test func checkingWhileTheCommitRuns() async {
        let (model, server) = makeModel(.allFood)
        server.latency = .milliseconds(600)
        model.setName("Milk")
        let prepare = Task { await model.prepareProduct() }
        #expect(await eventually { model.locationStatus == .checking })
        #expect(model.location == .pantry)
        #expect(model.locationStatus == .checking)
        #expect(model.locationHint == "Checking previous items and the best storage location…")
        await prepare.value
        await model.locationTask?.value
        #expect(model.locationStatus == .history)
    }

    @Test func suggestionForAScannedBarcodeSendsItsDetails() async throws {
        let (model, server) = makeModel(.allFood)
        await model.didDetectBarcode(barcode)
        await model.prepareProduct()
        await model.locationTask?.value
        #expect(server.calls.contains(
            "evershelf.prepare_scanned_product barcode=\(barcode) brand=Fixture Dairy category=Dairy name=Greek Yogurt product_id=501"
        ))
        let suggest = try #require(server.calls.last)
        #expect(suggest.hasPrefix("evershelf.suggest_location barcode=\(barcode) category=Dairy mode=barcode name=Greek Yogurt"))
        #expect(suggest.hasSuffix("product_id=501"))
    }

    private func suggested(_ suggestion: JSONValue) async -> ScanItemModel {
        let (model, server) = makeModel(.allFood)
        server.suggestion = suggestion
        model.setName("Milk")
        await model.prepareProduct()
        await model.locationTask?.value
        return model
    }

    @Test func suggestionVariants() async {
        let ai = await suggested(.object(["success": .bool(true), "location": .string("freezer"), "source": .string("ai")]))
        #expect(ai.location == .freezer)
        #expect(ai.locationStatus == .suggested)
        #expect(ai.locationHint == "Suggested for this product by EverShelf.")

        let byName = await suggested(.object(["location": .string("dispensa"), "source": .string("history_name")]))
        #expect(byName.location == .pantry)
        #expect(byName.locationStatus == .history)

        let unknown = await suggested(.object(["location": .string("unknown")]))
        #expect(unknown.location == .pantry)
        #expect(unknown.locationStatus == .unknown)
        #expect(unknown.locationHint == "No confident match; using the app default.")

        for unavailable in [JSONValue.object(["success": .bool(false), "location": .string("frigo")]), .object(["location": .string("garage")]), .null] {
            let model = await suggested(unavailable)
            #expect(model.location == .pantry)
            #expect(model.locationStatus == .unavailable)
            #expect(model.locationHint == "Storage suggestion unavailable; using the app default.")
        }
    }

    @Test func suggestionFailureFallsBack() async {
        let (model, server) = makeModel(.allFood)
        server.failing = ["evershelf.suggest_location"]
        model.setName("Milk")
        await model.prepareProduct()
        await model.locationTask?.value
        #expect(model.location == .pantry)
        #expect(model.locationStatus == .unavailable)
    }

    @Test func aChosenLocationIsNeverOverridden() async {
        let (model, server) = makeModel(.allFood)
        model.selectLocation(.cabinet)
        model.setName("Milk")
        await model.prepareProduct()
        #expect(model.locationTask == nil)
        #expect(model.location == .cabinet)
        #expect(model.locationStatus == .manual)
        #expect(server.calls == ["evershelf.prepare_scanned_product name=Milk"])
    }

    @Test func choosingWhileTheSuggestionRunsWins() async {
        let (model, server) = makeModel(.allFood)
        server.latency = .milliseconds(50)
        model.setName("Milk")
        await model.prepareProduct()
        let suggestion = model.locationTask
        model.selectLocation(.freezer)
        await suggestion?.value
        #expect(model.location == .freezer)
        #expect(model.locationStatus == .manual)
    }

    @Test func renamingDuringACommitRecommitsWithTheSameProduct() async {
        let (model, server) = makeModel(.allFood)
        server.latency = .milliseconds(600)
        model.setName("Milk")
        let first = Task { await model.prepareProduct() }
        #expect(await eventually { !server.calls.isEmpty }, "The first commit is in flight")
        model.setName("Oat Milk")
        await model.prepareProduct()
        await first.value
        await model.locationTask?.value
        let commits = server.calls.filter { $0.hasPrefix("evershelf.prepare_scanned_product") }
        #expect(commits == ["evershelf.prepare_scanned_product name=Milk", "evershelf.prepare_scanned_product name=Oat Milk product_id=901"])
        #expect(server.calls.last?.hasPrefix("evershelf.suggest_location mode=manual name=Oat Milk") == true)
        #expect(model.location == .fridge)
    }

    @Test func renamingResetsTheSuggestion() async {
        let (model, _) = makeModel(.allFood)
        model.setName("Milk")
        await model.prepareProduct()
        await model.locationTask?.value
        #expect(model.location == .fridge)
        model.setName("Milk ")
        #expect(model.location == .fridge, "Whitespace-only edits keep the commit")
        model.setName("Oat Milk")
        #expect(model.location == .pantry)
        #expect(model.locationStatus == .fallback)
    }

    // MARK: Prepared food

    @Test func preparedToggleIsSentWithTheCommitAndTheAdd() async {
        let (model, server) = makeModel()
        model.setName("Soup")
        model.togglePreparedFood()
        #expect(model.preparedFood)
        await model.prepareProduct()
        #expect(server.calls.first == "evershelf.prepare_scanned_product name=Soup prepared_food=true")
        await model.locationTask?.value
        await model.add()
        #expect(model.addStatus == .added)
        #expect(addCalls(server).first?.contains("prepared_food=true") == true)
        #expect(server.rows.first?.preparedFood == true)

        model.togglePreparedFood()
        #expect(!model.preparedFood)
    }

    // MARK: Add

    @Test func addSendsOneCommandWithTheItem() async {
        let (model, server) = makeModel()
        model.setName("Milk")
        model.setQuantityText("2")
        model.setExpiryDate("2026-10-20")
        model.goToReviewStep()
        await model.prepareProduct()
        await model.locationTask?.value
        await model.add()
        #expect(model.addStatus == .added)
        #expect(model.step == .adding)
        #expect(model.subtitle == "Item Added")
        #expect(model.instructions == "")
        #expect(model.addError == nil)
        #expect(server.calls.last
            == "evershelf.add_scanned_item expiry_date=2026-10-20 expiry_user_set=true idempotency_key=key-1 location=frigo name=Milk product_id=901 quantity=2")
        let row = server.rows.first
        #expect(row?.name == "Milk")
        #expect(row?.quantity == 2)
        #expect(row?.productId == 901)
        #expect(row?.expiryDate == "2026-10-20")
    }

    @Test func addFromABarcodeCommitsFirst() async {
        let (model, server) = makeModel()
        await model.didDetectBarcode(barcode)
        await model.add()
        #expect(model.addStatus == .added)
        #expect(server.calls.contains { $0.hasPrefix("evershelf.prepare_scanned_product") })
        #expect(addCalls(server) == [
            "evershelf.add_scanned_item barcode=\(barcode) brand=Fixture Dairy category=Dairy idempotency_key=key-1 location=frigo name=Greek Yogurt product_id=501 quantity=1",
        ])
    }

    @Test func addJoinsTheCommitAlreadyRunning() async {
        let (model, server) = makeModel()
        server.latency = .milliseconds(30)
        model.setName("Milk")
        model.goToExpiryStep()
        await model.add()
        #expect(model.addStatus == .added)
        #expect(server.calls.filter { $0.hasPrefix("evershelf.prepare_scanned_product") }.count == 1)
        #expect(addCalls(server).count == 1)
    }

    @Test func idempotencyKeyChangesOnlyWithTheItem() async {
        final class Counter { var value = 0 }
        let counter = Counter()
        let (model, server) = makeModel()
        model.makeIdempotencyKey = {
            counter.value += 1
            return "key-\(counter.value)"
        }
        model.setName("Milk")
        await model.add()
        await model.add()
        model.setQuantityText("3")
        await model.add()
        let keys = addCalls(server).map { call in call.split(separator: " ").first { $0.hasPrefix("idempotency_key=") }.map(String.init) }
        #expect(keys == ["idempotency_key=key-1", "idempotency_key=key-1", "idempotency_key=key-2"])
    }

    @Test func addIsBusyWhileRunning() async {
        let (model, server) = makeModel()
        model.setName("Milk")
        server.latency = .milliseconds(600)
        let add = Task { await model.add() }
        #expect(await eventually { model.step == .adding })
        #expect(model.step == .adding)
        #expect(model.addStatus == .adding)
        #expect(model.subtitle == "Adding Item")
        #expect(!model.canAdd)
        await add.value
        #expect(model.addStatus == .added)
    }

    @Test func addNeedsAName() async {
        let (model, server) = makeModel()
        await model.add()
        #expect(model.addStatus == .failed("Product name is required before adding to Fridge."))
        #expect(model.addError == "Product name is required before adding to Fridge.")
        #expect(server.calls.isEmpty)
        model.setName("Milk")
        #expect(model.addStatus == .idle)
    }

    @Test func addNeedsAValidQuantity() async {
        let (model, server) = makeModel()
        model.setName("Milk")
        model.setQuantityText("0")
        await model.add()
        #expect(model.addStatus == .idle)
        #expect(model.quantityError == "Quantity must be at least 1.")
        #expect(server.calls.isEmpty)
    }

    @Test func addFailureReturnsToReview() async {
        let (model, server) = makeModel()
        server.failing = ["evershelf.add_scanned_item"]
        model.setName("Milk")
        model.goToReviewStep()
        await model.add()
        #expect(model.addStatus == .failed("EverShelf is unavailable"))
        #expect(model.addError == "EverShelf is unavailable")
        #expect(model.step == .review)
        #expect(model.canAdd)

        model.setQuantityText("2")
        #expect(model.addStatus == .idle)
        await model.add()
        model.togglePreparedFood()
        #expect(model.addStatus == .idle)
        await model.add()
        model.setExpiryDate("2026-10-20")
        #expect(model.addStatus == .idle)
    }

    @Test func manualItemsAddEvenWhenTheCommitFails() async {
        let (model, server) = makeModel()
        server.failing = ["evershelf.prepare_scanned_product"]
        model.setName("Milk")
        await model.prepareProduct()
        #expect(model.locationStatus == .unavailable)
        #expect(model.locationHint == "Storage suggestion unavailable; using the current page default.")
        await model.add()
        #expect(model.addStatus == .added)
        #expect(server.calls.last == "evershelf.add_scanned_item idempotency_key=key-1 location=frigo name=Milk quantity=1")
    }

    @Test func barcodeItemsNeedACommittedProduct() async {
        let (model, server) = makeModel()
        await model.didDetectBarcode(barcode)
        server.failing = ["evershelf.prepare_scanned_product"]
        await model.add()
        #expect(model.addStatus == .failed(ScanItemModel.commitFailure))
        #expect(model.step == .review)
        #expect(addCalls(server).isEmpty)
    }

    @Test func barcodeAlreadyUsedBlocksTheAdd() async {
        let stub = InventoryStubCaller()
        stub.responses["prepare_scanned_product"] = .object([
            "success": .bool(false), "error": .string("barcode_already_used"), "message": .string("That barcode belongs to another product."),
        ])
        let (model, _) = makeModel(.fridge, stub)
        model.setName("Milk")
        await model.add()
        #expect(model.addStatus == .failed("That barcode belongs to another product."))
        #expect(model.step == .review)
        #expect(model.locationStatus == .unavailable)
        #expect(!stub.calls.contains { $0.name == "evershelf.add_scanned_item" })
    }

    @Test func commitAnswerCanMarkPreparedAndMerge() async {
        let stub = InventoryStubCaller()
        stub.responses["prepare_scanned_product"] = .object([
            "success": .bool(true), "id": .number(7), "product_fingerprint": .string(fingerprint64),
            "prepared_food": .bool(true), "merged": .bool(true),
        ])
        stub.responses["suggest_location"] = .object(["location": .string("frigo")])
        stub.responses["add_scanned_item"] = .object(["success": .bool(true)])
        let (model, _) = makeModel(.allFood, stub)
        model.setName("Stew")
        await model.prepareProduct()
        #expect(model.preparedFood)
        await model.locationTask?.value
        #expect(model.location == .fridge)
        #expect(model.locationStatus == .suggested)
        await model.add()
        #expect(model.addStatus == .added)
        let add = stub.calls.last
        #expect(add?.name == "evershelf.add_scanned_item")
        #expect(add?.data["product_id"] == .number(7))
        #expect(add?.data["prepared_food"] == nil)
        #expect(add?.data["location"] == .string("frigo"))

        model.setName("Stew Two")
        #expect(model.locationStatus == .fallback)
        #expect(model.location == .pantry)
    }

    @Test func malformedCommitAnswerIsTreatedAsUnavailable() async {
        let stub = InventoryStubCaller()
        stub.responses["prepare_scanned_product"] = .object(["success": .bool(true), "id": .number(7), "product_fingerprint": .string("short")])
        stub.responses["add_scanned_item"] = .object(["success": .bool(true)])
        let (model, _) = makeModel(.fridge, stub)
        model.setName("Stew")
        await model.add()
        #expect(model.addStatus == .added)
        #expect(model.locationStatus == .unavailable)
        #expect(stub.calls.last?.data["product_id"] == nil)
    }

    // MARK: Helpers

    @Test func fingerprintIsStableAndOrderIndependent() {
        let first = ScanItemModel.fingerprint(["b": .number(1), "a": .string("x")])
        let second = ScanItemModel.fingerprint(["a": .string("x"), "b": .number(1)])
        #expect(first == second)
        #expect(first.hasPrefix("{\"a\":\"x\""))
        #expect(first != ScanItemModel.fingerprint(["a": .string("y"), "b": .number(1)]))
        #expect(ScanItemModel.fingerprint([:]) == "{}")
    }

    @Test func textTrims() {
        #expect(ScanItemModel.text(.string("  x \n")) == "x")
        #expect(ScanItemModel.text(nil) == "")
        #expect(ScanItemModel.text(.number(1)) == "")
    }
}
