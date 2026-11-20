import Foundation

// MARK: - Index

/// The subjects a question may be about, with their names, rooms, floors and groups.
///
/// Built once from ``AskHouse``. A subject is an entity the *configuration* names (the house document's references plus the
/// overlay in ``AskConfiguration``) that is not a helper domain, hidden, disabled or diagnostic. The registry supplies names,
/// areas and floors for those entities only. An entity that exists in Home Assistant and is not configured is kept apart in
/// ``outsiders``, with names but no use: the resolver recognises a question about one and answers "not set up", and its
/// state is never read. Rebuild the index when the registry, the house document or the overlay changes; reading states for a
/// line goes through ``refreshing(states:now:)``, which keeps the names.
public struct AskableIndex: Sendable {
    /// The configuration the index was built with.
    public let configuration: AskConfiguration
    /// The moment answers are relative to.
    public let now: Date
    /// The home's display name.
    public let houseName: String
    /// The home's time zone.
    public let timeZone: TimeZone
    /// Every indexed entity: askable subjects and the entities a document room group names.
    public private(set) var entries: [String: AskEntry]
    /// The rooms by key.
    public let rooms: [String: AskRoom]
    /// The floors by id.
    public let floors: [String: AskFloorInfo]
    /// How each room's document groups list their members.
    public let documentGroups: [String: DocumentRoomGroups]
    /// The Home Assistant restart moment, when a restart cluster exists in the states.
    public let restartTime: Date?
    /// Whether the registry was present.
    public let hadRegistry: Bool
    /// Every entity id the configuration names: the document's references and the overlay's.
    public let configuredIds: Set<String>
    /// Entities that exist in Home Assistant but are not configured, for recognising a question about one. Names only;
    /// their states are never read and they are never refreshed.
    public let outsiders: [String: AskEntry]
    /// Entity lists the document keeps by kind (the garage doors, the locks, the cameras).
    public let deviceLists: [AskKind: [String]]
    /// The document's house-wide contact-sensor list (doors and windows).
    public let houseContactIds: [String]
    /// The words every spoken name and room uses, for near-miss matching.
    public let vocabulary: Set<String>
    /// Names (normalised) shared by more than one askable entity, with the entities.
    public let duplicateNames: [String: [String]]
    /// The house document's referenced ids.
    public let documentReferenced: Set<String>
    /// The thermostat the house document names as the main one.
    public let primaryThermostatId: String?
    /// The weather entity the house document names.
    public let primaryWeatherId: String?
    /// Annotator entities by the subject they explain.
    public let annotators: [String: [AskAnnotatorHit]]

    /// A room's document groups, by entity id.
    public struct DocumentRoomGroups: Sendable, Hashable {
        /// The room's lights (a group entity of its own is in ``lightGroupEntity``).
        public var lights: [String] = []
        /// The room's light group entity, when the document names one.
        public var lightGroupEntity: String?
        /// The room's temperature sensors.
        public var temperatures: [String] = []
        /// The room's occupancy sensors.
        public var occupancy: [String] = []
        /// The room's door and window sensors, with their kind and how many openings one sensor stands for.
        public var contacts: [Contact] = []
        /// The room's vents.
        public var vents: [String] = []

        /// A door or window sensor.
        public struct Contact: Sendable, Hashable {
            /// The sensor's entity id.
            public var entityId: String
            /// Door or window.
            public var kind: AskKind
            /// How many openings it stands for.
            public var count: Int
        }
    }

    // MARK: Build

    /// Builds the index from the house inputs and a configuration.
    public init(house: AskHouse, configuration: AskConfiguration = AskConfiguration()) {
        self.configuration = configuration
        now = house.now
        houseName = house.name
        timeZone = house.timeZone
        hadRegistry = house.registry != nil
        documentReferenced = house.document.referencedEntityIds
        configuredIds = house.document.referencedEntityIds.union(configuration.overlayEntityIds)
        deviceLists = house.document.deviceLists
        houseContactIds = house.document.houseContactIds
        primaryThermostatId = house.document.primaryThermostatId
        primaryWeatherId = house.document.primaryWeatherId
        let syn = configuration.synonyms

        // Floors and rooms.
        var floorInfos: [String: AskFloorInfo] = [:]
        for f in house.floors {
            var phrases = [AskText.words(f.name, synonyms: syn)] + f.aliases.map { AskText.words($0, synonyms: syn) }
            phrases += (configuration.floorNicknames.first { AskText.normalize($0.key) == AskText.normalize(f.name) }?.value ?? [])
                .map { AskText.words($0, synonyms: syn) }
            floorInfos[f.id] = AskFloorInfo(id: f.id, name: f.name, phrases: phrases.filter { !$0.isEmpty }, level: f.level)
        }
        floors = floorInfos
        var roomMap: [String: AskRoom] = [:]
        let areaNames = Set(house.areas.map { AskText.normalize($0.name) })
        var areaToRoom: [String: String] = [:]
        for a in house.areas {
            let key = AskText.normalize(a.name)
            var phrases = [AskText.words(a.name, synonyms: syn)]
            // An area alias equal to another area's name is dropped: the area name wins.
            for alias in a.aliases where !areaNames.contains(AskText.normalize(alias)) || AskText.normalize(alias) == key {
                phrases.append(AskText.words(alias, synonyms: syn))
            }
            if var existing = roomMap[key] {
                existing.areaIds.append(a.id)
                roomMap[key] = existing
            } else {
                roomMap[key] = AskRoom(key: key, title: a.name, areaIds: [a.id], floorId: a.floorId, phrases: phrases)
            }
            areaToRoom[a.id] = key
        }
        for title in house.document.roomTitles {
            let key = AskText.normalize(title)
            if roomMap[key] != nil { continue }
            // A title that is an alias of one area resolves to that area's room.
            if let host = house.areas.first(where: { $0.aliases.contains { AskText.normalize($0) == key } }),
               let hostKey = areaToRoom[host.id], var room = roomMap[hostKey]
            {
                room.phrases.append(AskText.words(title, synonyms: syn))
                roomMap[hostKey] = room
                roomMap[key] = room
                continue
            }
            roomMap[key] = AskRoom(key: key, title: title, phrases: [AskText.words(title, synonyms: syn)], documentOnly: true)
        }
        for (title, nicknames) in configuration.roomNicknames {
            let key = AskText.normalize(title)
            guard var room = roomMap[key] else { continue }
            room.phrases += nicknames.map { AskText.words($0, synonyms: syn) }
            roomMap[key] = room
        }
        for (key, room) in roomMap { roomMap[key]?.phrases = room.phrases.filter { !$0.isEmpty } }
        rooms = roomMap

        // Document groups by room.
        var groups: [String: DocumentRoomGroups] = [:]
        func roomKey(_ title: String) -> String {
            let key = AskText.normalize(title)
            if let room = roomMap[key] { return room.key }
            return key
        }
        for g in house.document.lightGroups {
            let k = roomKey(g.room)
            groups[k, default: .init()].lights += g.items.map(\.entityId)
            if let id = g.entityId { groups[k, default: .init()].lightGroupEntity = id }
        }
        for g in house.document.climateGroups {
            groups[roomKey(g.room), default: .init()].temperatures += g.items.map(\.entityId).filter { $0.hasPrefix("sensor.") }
            groups[roomKey(g.room), default: .init()].vents += g.items.map(\.entityId).filter { $0.hasPrefix("cover.") || $0.hasPrefix("fan.") }
        }
        for g in house.document.occupancyGroups { groups[roomKey(g.room), default: .init()].occupancy += g.items.map(\.entityId) }
        for g in house.document.contactGroups {
            for item in g.items {
                let kind = AskKind.fromContact(item)
                groups[roomKey(g.room), default: .init()].contacts.append(.init(entityId: item.entityId, kind: kind, count: max(1, item.contactCount)))
            }
        }
        for (title, ids) in house.document.ventEntityIds { groups[roomKey(title), default: .init()].vents += ids }
        documentGroups = groups

        // Registry lookups.
        var regById: [String: AskRegistryEntity] = [:]
        for r in house.registry ?? [] { regById[r.entityId] = r }
        let deviceById = Dictionary(house.devices.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var docTitles: [String: [(title: String, room: String?)]] = [:]
        for g in house.document.lightGroups + house.document.climateGroups + house.document.occupancyGroups + house.document.contactGroups {
            for item in g.items { docTitles[item.entityId, default: []].append((item.title, g.room)) }
        }
        for (id, list) in house.document.entityTitles { for t in list { docTitles[id, default: []].append((t, nil)) } }
        var docRoomOf: [String: String] = [:]
        for (key, g) in groups {
            for id in g.lights + g.temperatures + g.occupancy + g.vents + g.contacts.map(\.entityId) where docRoomOf[id] == nil { docRoomOf[id] = key }
        }
        let namePatterns = configuration.excludedNamePatterns.compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }
        let roomPhraseList: [(phrase: [String], key: String)] = roomMap.values
            .flatMap { room in room.phrases.map { (phrase: $0, key: room.key) } }
            .sorted { $0.phrase.count > $1.phrase.count }

        // Entries.
        // A room's light group entity stands for the room's lights, unless the room lists it as one of them (a one-light room).
        let listedLights = Set(groups.values.flatMap(\.lights))
        let roomLightGroups = Set(groups.values.compactMap(\.lightGroupEntity)).subtracting(listedLights)
        let roomPhraseSets = Set(roomMap.values.flatMap { $0.phrases.map { Set($0) } })
        var built: [String: AskEntry] = [:]
        var outside: [String: AskEntry] = [:]
        var vocab = Set<String>()
        var hits: [String: [AskAnnotatorHit]] = [:]
        for state in house.states {
            for rule in configuration.annotators where state.domain == rule.domain {
                let platformOK = regById[state.entityId].map { $0.platform == rule.platform } ?? (house.registry == nil)
                if platformOK, let subject = state.attributes[rule.subjectAttribute]?.string, subject.contains(".") {
                    hits[subject, default: []].append(AskAnnotatorHit(rule: rule, state: state))
                }
            }
        }
        annotators = hits
        for state in house.states {
            let id = state.entityId
            let domain = state.domain
            let reg = regById[id]
            let docRef = documentReferenced.contains(id)
            let isConfigured = configuredIds.contains(id)
            if !isConfigured, docRoomOf[id] == nil, !Self.isKnownOutside(state: state, reg: reg, configuration: configuration, namePatterns: namePatterns) { continue }
            let friendly = state.attributes["friendly_name"]?.string ?? String(id.drop { $0 != "." }.dropFirst()).replacingOccurrences(of: "_", with: " ")

            // Room: entity area, device area, document group, name prefix.
            var areaId: String?
            var source = AskEntry.RoomSource.none
            if let a = reg?.areaId, areaToRoom[a] != nil { areaId = a; source = .area }
            else if let d = reg?.deviceId, let a = deviceById[d]?.areaId, areaToRoom[a] != nil { areaId = a; source = .deviceArea }
            var key: String? = areaId.flatMap { areaToRoom[$0] }
            if key == nil, let k = docRoomOf[id] { key = k; source = .document }
            let friendlyWords = AskText.words(friendly, synonyms: syn)
            if key == nil {
                for (phrase, k) in roomPhraseList where friendlyWords.starts(with: phrase) && friendlyWords.count > phrase.count {
                    key = k; source = .namePrefix
                    break
                }
            }
            let room = key.flatMap { roomMap[$0] }

            // Names. The house document's own title is a name source ahead of a hardware-style friendly name: when the friendly
            // name does not already carry the title's words, the title (with its room) is what the house calls the thing.
            var display = friendly
            let titled = isConfigured ? (docTitles[id] ?? []) : []
            if let t = titled.first(where: { !Set(AskText.words($0.title, synonyms: syn)).isSubset(of: Set(friendlyWords)) }) {
                let tw = Set(AskText.words(t.title, synonyms: syn))
                var name = t.title
                if let r = t.room, !tw.isSuperset(of: Set(AskText.words(r, synonyms: syn))) { name = r + " " + t.title }
                display = name
            }
            // A name the household gave it is the name to speak back ("Sam", not the account's full name).
            if let spoken = configuration.entityNames[id]?.first, !spoken.isEmpty {
                display = spoken.split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
            }
            var shortName = display
            if let room {
                let t = room.title.lowercased()
                if display.lowercased().hasPrefix(t + " "), display.count > t.count + 1 { shortName = String(display.dropFirst(t.count + 1)) }
            }
            var variants: [Set<String>] = [Set(friendlyWords)]
            var own: [String] = [AskText.normalize(friendly)]
            let shortWords = AskText.words(shortName, synonyms: syn)
            if shortName != friendly { variants.append(Set(shortWords)) }
            for extra in [reg?.name, reg?.originalName, reg?.deviceId.flatMap { deviceById[$0]?.nameByUser }]
            where extra != nil && !(extra ?? "").isEmpty {
                variants.append(Set(AskText.words(extra ?? "", synonyms: syn)))
            }
            for alias in (reg?.aliases ?? []) + (configuration.entityNames[id] ?? []) { variants.append(Set(AskText.words(alias, synonyms: syn))); own.append(AskText.normalize(alias)) }
            for extra in [reg?.name, reg?.originalName] where extra != nil && !(extra ?? "").isEmpty { own.append(AskText.normalize(extra ?? "")) }
            for role in isConfigured ? (house.document.roleTitles[id] ?? []) : [] {
                let w = AskText.words(role, synonyms: syn)
                if !roomPhraseSets.contains(Set(w)) { variants.append(Set(w)) }
            }
            for t in titled {
                let w = AskText.words(t.title, synonyms: syn)
                // A title that is only a place ("Master Bedroom" on a room's switch) names the room, not the entity.
                if roomPhraseSets.contains(Set(w)) { continue }
                variants.append(Set(w))
                if let room { variants.append(Set(w).union(AskText.words(room.title, synonyms: syn))) }
            }
            variants = variants.filter { !$0.isEmpty }
            var unique: [Set<String>] = []
            for v in variants where !unique.contains(v) { unique.append(v) }

            let devClass = state.attributes["device_class"]?.string ?? reg?.deviceClass
            let nameWordSet = Set(friendlyWords)
            let kind = AskKind.of(domain: domain, deviceClass: devClass, nameWords: nameWordSet)
            let exposed = reg?.exposed ?? false
            let askable = isConfigured && Self.isAskable(state: state, reg: reg, configuration: configuration, namePatterns: namePatterns, friendly: friendly)
            let memberIds: [String] = state.attributes["entity_id"]?.array?.compactMap(\.string) ?? []
            let isGroup = !memberIds.isEmpty || roomLightGroups.contains(id)
            let sens = configuration.sensitivity.classify(domain: domain, deviceClass: devClass, platform: reg?.platform, nameWords: nameWordSet)
            let colour = friendly.range(of: #"color|colour"#, options: [.regularExpression, .caseInsensitive]) != nil && domain == "light" && !isGroup
            let entry = AskEntry(
                id: id, deviceClass: devClass, platform: reg?.platform, deviceId: reg?.deviceId, state: state, displayName: display,
                shortName: shortName, nameVariants: unique, ownNames: own.filter { !$0.isEmpty }, roomWords: Set(room.map { AskText.words($0.title, synonyms: syn) } ?? []),
                roomKey: key, roomSource: source, floorId: room?.floorId, kind: kind, askable: askable, exposed: exposed,
                documentReferenced: docRef, sensitivity: sens, isGroup: isGroup, members: memberIds, excludedFromAggregates: isGroup || colour
            )
            if askable || (isConfigured && (docRef || docRoomOf[id] != nil)) {
                built[id] = entry
                if askable { for v in unique { vocab.formUnion(v) } }
            } else if !isConfigured {
                outside[id] = entry
            }
        }
        for room in roomMap.values { for p in room.phrases { vocab.formUnion(p) } }
        for f in floorInfos.values { for p in f.phrases { vocab.formUnion(p) } }
        // Parent groups.
        for (id, e) in built where e.isGroup {
            for m in e.members { built[m]?.parentGroups.append(id) }
        }
        entries = built
        outsiders = outside
        vocabulary = vocab

        // Duplicate names.
        var byName: [String: [String]] = [:]
        for e in built.values where e.askable { byName[AskText.normalize(e.displayName), default: []].append(e.id) }
        duplicateNames = byName.filter { $0.value.count > 1 }

        restartTime = AskRestartGuard.detect(states: house.states, configuration: configuration)
    }

    /// Applies new states without rebuilding names or rooms (a live change costs one entry update).
    public func refreshing(states: [EntityState], now: Date) -> AskableIndex {
        var copy = self
        for s in states { copy.entries[s.entityId]?.state = s }
        return copy.withNow(now)
    }

    private func withNow(_ now: Date) -> AskableIndex {
        AskableIndex(copying: self, now: now)
    }

    private init(copying other: AskableIndex, now: Date) {
        configuration = other.configuration
        self.now = now
        houseName = other.houseName
        timeZone = other.timeZone
        entries = other.entries
        rooms = other.rooms
        floors = other.floors
        documentGroups = other.documentGroups
        restartTime = other.restartTime
        hadRegistry = other.hadRegistry
        configuredIds = other.configuredIds
        outsiders = other.outsiders
        deviceLists = other.deviceLists
        houseContactIds = other.houseContactIds
        vocabulary = other.vocabulary
        duplicateNames = other.duplicateNames
        documentReferenced = other.documentReferenced
        primaryThermostatId = other.primaryThermostatId
        primaryWeatherId = other.primaryWeatherId
        annotators = other.annotators
    }

    // MARK: Rule

    /// Whether a configured entity is a subject: not a helper domain, platform or name, and (with a registry row) not hidden,
    /// disabled or diagnostic. Being configured is decided by the caller.
    static func isAskable(
        state: EntityState, reg: AskRegistryEntity?, configuration c: AskConfiguration, namePatterns: [NSRegularExpression], friendly: String
    ) -> Bool {
        let domain = state.domain
        if c.neverDomains.contains(domain) { return false }
        if let platform = reg?.platform {
            if c.excludedPlatforms.contains(platform) { return false }
            if c.excludedPlatformDomains[platform]?.contains(domain) == true { return false }
        }
        let range = NSRange(friendly.startIndex..., in: friendly)
        if namePatterns.contains(where: { $0.firstMatch(in: friendly, range: range) != nil }) { return false }
        if let reg, reg.disabledBy != nil || reg.hiddenBy != nil || reg.entityCategory != nil { return false }
        return true
    }

    /// Whether an entity that is *not* configured is still a thing a person could name: the same quality rule, so a helper or
    /// a hidden entity is never reported as "not set up".
    static func isKnownOutside(
        state: EntityState, reg: AskRegistryEntity?, configuration c: AskConfiguration, namePatterns: [NSRegularExpression]
    ) -> Bool {
        let friendly = state.attributes["friendly_name"]?.string ?? state.entityId
        return isAskable(state: state, reg: reg, configuration: c, namePatterns: namePatterns, friendly: friendly)
    }

    // MARK: Lookup

    /// The askable entries, in id order.
    public var askable: [AskEntry] { entries.values.filter(\.askable).sorted { $0.id < $1.id } }

    /// One entry by entity id.
    public func entry(_ id: String) -> AskEntry? { entries[id] }

    /// Whether `entry` sits in `scope`: the house, a floor, or a room (by area, document group or name prefix).
    public func contains(_ scope: AskScope, _ entry: AskEntry) -> Bool {
        switch scope {
        case .house: return true
        case .floor(let id): return entry.floorId == id
        case .room(let key): return entry.roomKey == key
        }
    }

    /// The title to show for a room key.
    public func roomTitle(_ key: String?) -> String? { key.flatMap { rooms[$0]?.title } }
}

extension AskKind {
    /// The kind of a house-document contact item: its authored kind, else inferred from its title and entity id.
    static func fromContact(_ item: RoomGroupItem) -> AskKind {
        if let kind = item.contactKind { return kind == .door ? .door : .window }
        let words = AskText.words(item.title + " " + item.entityId.replacingOccurrences(of: "_", with: " "))
        return words.contains("window") ? .window : .door
    }
}

// MARK: - Annotator hit

/// An annotator entity and the rule that links it to its subject.
public struct AskAnnotatorHit: Sendable {
    /// The rule that matched.
    public let rule: AskAnnotatorRule
    /// The annotator entity's current state.
    public let state: EntityState
}
