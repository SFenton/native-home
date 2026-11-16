#if os(iOS)
import HassCore
import Observation
import UIKit

// MARK: - Window-owned alarm selections

/// Captures complete alarm rows, not just IDs, before opening an authored editor.
@MainActor @Observable
final class UKServerUIBedroomSource {
    let session: ServerUIBedroomSession
    let providerID: String
    let alarms: ServerUIBedroomAlarms
    private var selected: ServerUIBedroomAlarms.Row?

    init(session: ServerUIBedroomSession, providerID: String, alarms: ServerUIBedroomAlarms) {
        self.session = session
        self.providerID = providerID
        self.alarms = alarms
    }

    func select(_ row: ServerUIBedroomAlarms.Row) throws {
        _ = try alarms.route(for: row)
        selected = row
    }

    func open(route: ServerUIBedroomAlarms.Route?, visitID: String) throws -> ServerUIBedroomDraft {
        let chosen: ServerUIBedroomAlarms.Route
        if let supplied = route { chosen = supplied }
        else {
            guard let selected else { throw ServerUIRecordFailure.staleSelection }
            chosen = try alarms.route(for: selected)
        }
        return try session.editor(providerId: providerID, route: chosen, visitId: visitID)
    }
}

// MARK: - Lazy editor admission

/// Admission checks the real owner and kind. A draft is created only for a particular page visit.
@MainActor
struct UKServerUIBedroomEditorFactory {
    let source: UKServerUIBedroomSource
    let kind: ServerUIBedroomControl.ProviderKind
    let route: ServerUIBedroomAlarms.Route?

    func open(visitID: String) throws -> ServerUIBedroomDraft {
        try source.open(route: route, visitID: visitID)
    }
}

/// Derived registrations share the same canonical controllers as tiles and alarm commands.
@MainActor
struct UKServerUIBedroomRegistry {
    let sources: [String: UKServerUIBedroomSource]
    let editors: [String: UKServerUIBedroomEditorFactory]
    let collections: [String: UKServerUIBedroomCollection]

    init(domain: ServerUIDeviceProviders, retaining old: Self? = nil) throws {
        var sources: [String: UKServerUIBedroomSource] = [:]
        var editors: [String: UKServerUIBedroomEditorFactory] = [:]
        var collections: [String: UKServerUIBedroomCollection] = [:]
        for session in domain.bedrooms.values {
            for (id, alarms) in session.alarms {
                guard sources[id] == nil else {
                    throw UKServerUIRendererError(code: .unavailableSource, pointer: "/document/dataSources")
                }
                let source = old?.sources[id].flatMap { $0.session === session ? $0 : nil }
                    ?? UKServerUIBedroomSource(session: session, providerID: id, alarms: alarms)
                sources[id] = source
                let isWake = id == session.descriptor.wakeProviderId
                let kind: ServerUIBedroomControl.ProviderKind = isWake ? .wakeDraft : .bedDraft
                editors[id + ".editor"] = .init(source: source, kind: kind, route: nil)
                editors[id + ".new-editor"] = .init(source: source, kind: kind, route: isWake ? .addWake : .addBed(nil))
                func collection(_ key: String, day: Weekday?) {
                    collections[key] = old?.collections[key].flatMap { $0.source === source ? $0 : nil }
                        ?? UKServerUIBedroomCollection(source: source, day: day)
                }
                collection(id + ".alarms", day: nil)
                if !isWake {
                    for day in Weekday.allCases {
                        let key = id + ".day." + day.rawValue
                        collection(key, day: day)
                        editors[key + ".new-editor"] = .init(source: source, kind: kind, route: .addBed(day))
                    }
                }
            }
        }
        self.sources = sources
        self.editors = editors
        self.collections = collections
    }

    func validate(_ definitions: [ServerUICompositionDocument.Source],
                  supplied: [String: UKServerUIBedroomProvider]) throws {
        for (index, definition) in definitions.enumerated() {
            guard case .bedroom(_, let id, let kind) = definition else { continue }
            guard supplied[id]?.kind == kind || (supplied[id] == nil && editors[id]?.kind == kind) else {
                throw UKServerUIRendererError(code: .unavailableSource, pointer: "/document/dataSources/\(index)/inputs/providerId")
            }
        }
    }

    func addingCollections(to records: UKServerUIRecords) throws -> UKServerUIRecords {
        var result = records
        for (id, collection) in collections {
            guard result.collections[id] == nil else {
                throw UKServerUIRendererError(code: .unavailableSource, pointer: "/document/dataSources")
            }
            result.collections[id] = collection
        }
        return result
    }
}

// MARK: - Authored alarm collections

/// Reuses the existing collection host while retaining full, revision-checked domain rows.
@MainActor @Observable
final class UKServerUIBedroomCollection: UKServerUICollectionSource {
    let source: UKServerUIBedroomSource
    let day: Weekday?
    let template = ServerUICompositionDocument.Collection.Template.rows
    var searchText = ""
    var showsSearch: Bool { false }
    private var visibleRows: [ServerUIBedroomAlarms.Row] {
        let rows = source.alarms.rows(day: day)
        guard day != nil else { return rows }
        return rows.sorted {
            guard case .bed(let a) = $0.alarm, case .bed(let b) = $1.alarm else { return false }
            return ClockTime.minutes(a.time) < ClockTime.minutes(b.time)
        }
    }
    var records: [UKServerUIRecord] { visibleRows.map { .bedroom($0, source) } }
    var loading: Bool { false }
    var error: String? { source.alarms.error ?? (source.alarms.available ? nil : "Alarms are unavailable.") }
    var hasPendingIntent: Bool {
        source.session.devices.wakeLight.hasPendingCommands || source.session.devices.beds.contains(where: \.hasPendingCommands)
    }
    var isPinned: Bool { source.session.protectsPublication }
    var hasMore: Bool { false }

    init(source: UKServerUIBedroomSource, day: Weekday?) {
        self.source = source
        self.day = day
    }

    func load() async throws {}
    func loadMore() async throws { throw ServerUIRecordFailure.invalidValue }
    func select(_ record: UKServerUIRecord) throws {
        guard case .bedroom(let row, let owner) = record, owner === source,
              visibleRows.contains(row) else { throw ServerUIRecordFailure.staleSelection }
        try source.select(row)
    }
}
#endif
