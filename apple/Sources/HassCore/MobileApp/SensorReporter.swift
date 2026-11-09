import Foundation

/// Registers the phone's sensors with Home Assistant and keeps their states current
/// (`.agents/platforms/apple/location.md`, "Sensors"), as the official app's `UpdateSensors` does.
///
/// - **Registration first.** The first update after a new registration (a different webhook id) or a new app
///   version sends `register_sensor` for every sensor the providers report, with their states; Home Assistant then
///   has the entities. Registering again after a 410 needs nothing special: the new registration has a new webhook
///   id. A sensor Home Assistant answers `not_registered` for (a provider that had no reading at registration, or
///   an entity the person deleted) is registered on the spot.
/// - **Unchanged payloads are skipped,** per sensor, against what Home Assistant last accepted. Nothing is sent when
///   nothing changed. A sensor disabled in Home Assistant is not sent again until the next Launch update.
/// - **One at a time, in order.** Updates form a first-in, first-out chain, so an older reading never lands after a newer one.
///
/// An actor, so the device reads and the HTTP exchanges never run on the main thread.
public actor SensorReporter {
    private let client: MobileAppWebhookClient
    private let source: any DeviceStatusSource
    private let providers: [any MobileAppSensorProvider]
    private let memory: SensorRegistrationMemory
    private let version: String
    private var lastSent: [String: MobileAppSensor] = [:]
    private var disabled: Set<String> = []
    private var tail: Task<Int, any Error>?
    /// Bumped by ``cancelPending()``; an update asked for under an older one never sends.
    private var epoch = 0


    /// Creates a reporter.
    /// - Parameters:
    ///   - client: Sends the webhook commands.
    ///   - source: Reads the device.
    ///   - providers: The sensors reported; defaults to the app's standard set.
    ///   - appVersion: The app version; sensors are registered again when it changes (names and icons may have).
    ///   - memory: Remembers which registration the sensors were registered for.
    public init(client: MobileAppWebhookClient, source: any DeviceStatusSource,
                providers: [any MobileAppSensorProvider] = MobileAppSensors.standard, appVersion: String = "",
                memory: SensorRegistrationMemory = SensorRegistrationMemory()) {
        self.client = client
        self.source = source
        self.providers = providers
        self.version = appVersion
        self.memory = memory
    }

    /// Reads the device and sends what changed, registering first when needed.
    /// - Returns: How many sensors were sent or registered; 0 when nothing changed.
    /// - Throws: ``MobileAppWebhookError`` when Home Assistant could not be reached or the registration is gone.
    ///   Nothing is remembered as sent then, so the next update carries it again.
    @discardableResult
    public func update(_ context: SensorContext) async throws -> Int {
        // First in, first out: each update waits for the one asked before it (the call order is fixed here, before
        // any suspension), so the last one asked is the last one sent.
        let previous = tail
        let asked = epoch
        let task = Task { () -> Int in
            _ = await previous?.result
            return try await self.send(context, epoch: asked)
        }
        tail = task
        return try await task.value
    }

    /// Voids every update asked for so far, running or queued: they send nothing more and throw
    /// `CancellationError`. Used when reporting stops (permission withdrawn, sign-out).
    public func cancelPending() { epoch += 1 }

    private func ensureCurrent(_ asked: Int) throws {
        if asked != epoch { throw CancellationError() }
    }

    private func send(_ context: SensorContext, epoch asked: Int) async throws -> Int {
        try ensureCurrent(asked)
        guard let webhookID = await client.currentWebhookID() else { throw MobileAppWebhookError.notRegistered }
        var status = await source.status(for: context)
        try ensureCurrent(asked)
        status.lastUpdateTrigger = context.trigger
        status.locationPermission = status.locationPermission ?? context.permission
        status.place?.zones = context.zoneNames
        let sensors = MobileAppSensors.sensors(for: status, providers: providers)
        if context.trigger == .launch { disabled = [] }

        let registration = "\(webhookID)|\(version)"
        if memory.registration != registration {
            lastSent = [:]
            disabled = []
            do {
                for sensor in sensors {
                    try ensureCurrent(asked)
                    try await client.registerSensor(sensor)
                }
            } catch {
                forgetRegistration(for: error)
                throw error
            }
            memory.registration = registration
            for sensor in sensors { lastSent[sensor.uniqueID] = sensor }
            return sensors.count
        }

        let changed = sensors.filter { !disabled.contains($0.uniqueID) && lastSent[$0.uniqueID] != $0 }
        guard !changed.isEmpty else { return 0 }
        let outcome: SensorUpdateOutcome
        try ensureCurrent(asked)
        do {
            outcome = try await client.updateSensorStates(changed)
        } catch {
            forgetRegistration(for: error)
            throw error
        }
        disabled.formUnion(outcome.disabled)
        for sensor in changed where !outcome.notRegistered.contains(sensor.uniqueID)
            && !outcome.disabled.contains(sensor.uniqueID) && outcome.failed[sensor.uniqueID] == nil {
            lastSent[sensor.uniqueID] = sensor
        }
        for sensor in changed where outcome.notRegistered.contains(sensor.uniqueID) {
            try ensureCurrent(asked)
            do {
                try await client.registerSensor(sensor)
            } catch {
                forgetRegistration(for: error)
                throw error
            }
            lastSent[sensor.uniqueID] = sensor
        }
        return changed.count
    }

    /// A gone registration took its sensors with it; whatever registers next starts clean.
    private func forgetRegistration(for error: any Error) {
        guard let failure = error as? MobileAppWebhookError, failure == .registrationGone else { return }
        memory.registration = nil
        lastSent = [:]
        disabled = []
    }
}

/// Which registration (webhook id and app version) the sensors were last registered for, kept across launches in
/// `UserDefaults` under `mobileapp.sensors.registered`.
public final class SensorRegistrationMemory: @unchecked Sendable {
    private let defaults: UserDefaults

    static let key = "mobileapp.sensors.registered"

    /// Creates a memory on `defaults`.
    public init(_ defaults: UserDefaults = .standard) { self.defaults = defaults }

    /// `<webhook id>|<app version>`, or nil when none is registered.
    var registration: String? {
        get { defaults.string(forKey: Self.key) }
        set { defaults.set(newValue, forKey: Self.key) }
    }
}
