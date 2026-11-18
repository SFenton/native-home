import Foundation

// MARK: - Closed schema-2 grammar

/// Shape validation is separate from semantic compilation so unknown/missing fields cannot be
/// lost by decoding, and shape diagnostics have deterministic JSON-pointer ordering.
enum ServerUICompositionShape {
    indirect enum Shape: Sendable {
        case object([String: Shape])
        case optional(Shape)
        case array(Shape, Int, Int)
        case text(Int, blank: Bool)
        case pattern(String, Int)
        case dictionary(Shape, Shape, Int)
        case identifier, hash, bool, nullableID
        /// A number between the bounds, or `null` (`sh.chart@1` literal points: a value not known).
        case nullableNumber(Double, Double)
        case number(Double, Double, integer: Bool)
        case choice([String])
        case variant(String, [String: Shape])
        /// As ``variant``, but a tag no variant takes is refused at the value itself (the whole choice is the wrong one), as a union is.
        case closedVariant(String, [String: Shape])
        case emptyObject(String, Int)
        case unsupported(String?)
        /// A text or an object, each checked by its own shape (a tone that is one word or a rule).
        case either(text: Shape, object: Shape)
        /// A rule that reports as one: any failure inside it is the slot not matching (`unknown_variant` at the slot), except an empty
        /// `cases`, which is a limit of its own. This is how the Studio reports a rule inside a union of plain and ruled forms.
        case collapsed(Shape)
        case component
        /// An authored operand, predicate or `call-service` action, checked by ``ServerUIExpressionParser``.
        case operand, predicate, callService
        /// The text `all`, or a list of one to `maximum` identifiers (`sh.tab-blocks@1`).
        case allOrIdentifiers(Int)
        /// An operand or a condition inside a Data Flow, where `item` and `param` may stand (`sh.pipeline@1`); the flow compiler types them.
        case flowOperand, flowPredicate
        /// A shape of the flow shape language (`sh.pipeline@1`).
        case flowShape
    }

    typealias Issue = ServerUICompositionError
    static let id = Shape.identifier
    static let label = Shape.text(80, blank: false)
    /// A route path, alias or link prefix: lower-case and hyphenated, like the authored `path`.
    static let routePath = Shape.pattern("^[a-z][a-z0-9-]{0,79}$", 80)
    static let title = Shape.text(240, blank: false)
    static func fixed(_ value: String) -> Shape { .choice([value]) }
    static func object(_ fields: [String: Shape]) -> Shape { .object(fields) }
    static func array(_ item: Shape, _ maximum: Int, minimum: Int = 0) -> Shape { .array(item, minimum, maximum) }
    static let arguments = Shape.emptyObject("sh.route-arguments@1", 32)
    static let operand = Shape.operand
    static let predicate = Shape.predicate
    static let callService = Shape.callService
    static let whenUnknown = Shape.choice(ServerUIVisibility.WhenUnknown.allCases.map(\.rawValue))

    static let publication: Shape = {
        object([
            "envelopeVersion": fixed("2.0"), "publisherId": id,
            "revision": .number(1, 9_007_199_254_740_991, integer: true),
            "updatedAt": .text(40, blank: false), "publishedAt": .text(40, blank: false),
            "capabilities": array(.text(160, blank: false), 1_000),
            "assetManifestSha256": .hash, "document": document
        ])
    }()
    static let document: Shape = {
        object([
            "schemaVersion": fixed("2.0"), "id": id, "name": title,
            "theme": object([
                "appearance": fixed("dark"), "tokens": fixed("canonical@1"),
                "typography": fixed("dynamic-type@1"), "background": background
            ]),
            "navigation": navigation,
            "pages": array(surface(modal: false), 256, minimum: 1),
            "modals": array(surface(modal: true), 256),
            "dataSources": array(source, 1_000),
            "variables": .emptyObject("sh.local-state@1", 100),
            "localState": .optional(array(localField, 100)),
            "assets": array(asset, 100),
            "liveActivities": array(activityPresentation, 16),
            "bootstrap": .optional(bootstrap),
            "extensions": .optional(extensionPresentation),
            "stateStyles": .optional(stateStyleLibrary),
            "componentLibrary": .optional(array(componentEntry, 100))
        ])
    }()
    static let bootstrap: Shape = {
        object([
            "type": fixed("native-bootstrap@1"),
            "arrivalAnnouncement": title,
            "recovery": object([
                "loadingTitle": title, "unavailableTitle": title,
                "unavailableMessage": .text(2_000, blank: false), "retryLabel": label
            ]),
            "setup": .array(object([
                "permission": .choice(["notifications", "time-sensitive", "location"]),
                "explanation": .optional(.text(2_000, blank: false))
            ]), 3, 3)
        ])
    }()
    static let activityPresentation: Shape = {
        object([
            "id": id, "jobId": id, "type": fixed("activity-presentation@1"), "title": .text(32, blank: false),
            "glyph": .choice(["fan", "dishwasher", "dryer", "washer", "vacuum", "hot_flash", "generic"]),
            "tint": .choice(["engine", "neutral", "air", "cleaning", "water", "cooling"]),
            "source": fixed("activity-engine@1"), "privacy": fixed("system-sensitive@1"),
            "updates": fixed("engine@1"), "intents": fixed("engine-safe@1")
        ])
    }()
    static let extensionPresentation: Shape = {
        object([
            "type": fixed("native-extensions@1"), "watch": fixed("stub@1"),
            "routes": array(object([
                "id": id, "path": label, "pageId": id, "title": label, "summary": title, "icon": label,
                "tabId": .optional(id),
                "anchors": .optional(array(object(["fragment": id, "modalId": id]), 32)),
                "aliases": .optional(array(routePath, 8)),
                "keywords": .optional(array(.text(40, blank: false), 12)),
                "siri": .optional(.bool),
                "visibleWhen": .optional(predicate)
            ]), 64),
            "linkPrefixes": .optional(array(routePath, 8, minimum: 1)),
            "cameras": array(object([
                "entityId": .text(160, blank: false), "title": label,
                "liveLabel": .text(40, blank: false), "unavailableLabel": label
            ]), 32)
        ])
    }()
    static let symbol: Shape = {
        .variant("type", ["sf-symbol": object([
            "type": fixed("sf-symbol"), "name": .text(80, blank: false),
            "rendering": fixed("canonical"), "unavailable": .choice(["fallback", "reject"])
        ])])
    }()
    static let space: Shape = {
        .variant("type", [
            "token": object(["type": fixed("token"), "name": .choice(["zero", "xs", "s", "m", "l", "xl", "section-header"])]),
            "points": object(["type": fixed("points"), "value": .number(0, 64, integer: false)])
        ])
    }()
    static let width: Shape = {
        .variant("type", [
            "unbounded": object(["type": fixed("unbounded")]),
            "points": object(["type": fixed("points"), "value": .number(320, 1_600, integer: false)])
        ])
    }()
    static let insets: Shape = object(["top": space, "leading": space, "bottom": space, "trailing": space])
    static let background: Shape = {
        .variant("type", [
            "solid": object(["type": fixed("solid"), "token": fixed("shell-base@1")]),
            "downloaded": object([
                "type": fixed("downloaded"), "assetId": id, "recipe": fixed("house-r3@1"),
                "blur": .variant("type", [
                    "fixed": object(["type": fixed("fixed"), "percent": .number(0, 100, integer: true)]),
                    "preference": object(["type": fixed("preference"), "key": fixed("backdrop-blur"),
                                          "initialPercent": .number(0, 100, integer: true)])
                ]),
                "scrim": .variant("type", [
                    "canonical@1": object(["type": fixed("canonical@1")]),
                    "gradient": object([
                        "type": fixed("gradient"), "increasedContrastBoost": .number(0, 0.1, integer: false),
                        "stops": array(object(["location": .number(0, 1, integer: false),
                                               "opacity": .number(0, 0.9, integer: false)]), 8, minimum: 2)
                    ])
                ]),
                "motion": fixed("stationary@1"), "reducedTransparency": fixed("canonical-base@1")
            ])
        ])
    }()
    static let navigation: Shape = {
        object([
            "initialPageId": id, "initialTabId": .nullableID, "initialArguments": arguments,
            "tabs": array(object(["id": id, "label": label, "icon": symbol, "pageId": id, "arguments": arguments,
                                  "visibleWhen": .optional(predicate), "whenUnknown": .optional(whenUnknown), "badge": .optional(badge)]), 8),
            "policy": object([
                "type": fixed("canonical-shell@1"), "tabSwitch": fixed("preserve-cut@1"),
                "reselect": fixed("pop-root-then-scroll@1"), "stackMotion": fixed("canonical-stack@1"),
                "restoration": fixed("scene@1"), "selectionWhileModal": fixed("reject")
            ]),
            "chrome": object(["groups": groups])
        ])
    }()
    static let groups: Shape = {
        array(object([
            "id": id, "placement": .choice(["leading", "trailing"]),
            "horizontal": .choice(["separate-circles@1", "shared@1"]),
            "vertical": .choice(["shared@1", "separate@1"]),
            "items": array(chromeItem, 12)
        ]), 3)
    }()
    static let chromeItem: Shape = {
        .variant("type", [
            "shell-menu": object([
                "id": id, "type": fixed("shell-menu"), "label": label, "icon": symbol,
                "visibility": fixed("root-when-menu-available")
            ]),
            "button": object([
                "id": id, "type": fixed("button"), "label": label, "menuLabel": label, "icon": symbol,
                "visibility": .choice(["always", "root-only"]), "priority": .choice(["required", "normal", "low"]),
                "rail": .choice(["eligible", "horizontal-only"]),
                "badge": .variant("type", ["none": object(["type": fixed("none")]),
                                          "count": .unsupported("sh.profile-count@1"),
                                          "value": object(["type": fixed("value"), "value": operand])]),
                "action": ruledAction
            ]),
            "shell-header": object([
                "id": id, "type": fixed("shell-header"), "visibility": .choice(["always", "root-only"]),
                "quickLinksAction": action, "profileAction": action
            ]),
            "profile": .unsupported(nil), "connection-status": .unsupported(nil)
        ])
    }()
    static let toolbar: Shape = {
        .variant("type", [
            "inherit": object(["type": fixed("inherit")]),
            "replace": object(["type": fixed("replace"), "groups": groups])
        ])
    }()
    static let body: Shape = {
        object([
            "type": fixed("column"), "padding": insets, "spacing": space, "maxWidth": width,
            "scroll": fixed("content-fit@1"), "chrome": fixed("canonical-page@1"), "ground": fixed("host")
        ])
    }()
    static func surface(modal: Bool) -> Shape {
        var fields: [String: Shape] = [
            "id": id, "title": title, "icon": symbol, "parameters": arguments,
            "layout": body, "toolbar": toolbar, "components": array(.component, 100),
            "titleSourceId": .optional(id)
        ]
        if modal {
            fields["presentation"] = sheet
        } else {
            fields["navigation"] = .variant("type", [
                "stack": object(["type": fixed("stack")]),
                "navigation-columns": object(["type": fixed("navigation-columns"), "placeholder": title, "standalone": .bool, "onDemand": .optional(.bool)])
            ])
        }
        return object(fields)
    }
    static let sheet: Shape = {
        .variant("type", [
            "sheet": object([
                "type": fixed("sheet"), "width": .choice(["form", "page"]),
                "adaptive": .optional(.bool), "fullScreen": .optional(.bool),
                "height": .variant("type", [
                    "full": object(["type": fixed("full")]),
                    "fitted": object([
                        "type": fixed("fitted"), "follows": .choice(["root", "top-page"]),
                        "firstOpen": fixed("canonical@1")
                    ])
                ]),
                "appearance": .choice(["system", "dark"]), "placement": fixed("canonical-sheet@1"),
                "grabber": fixed("canonical"), "navigation": fixed("local-stack@1"),
                "close": .variant("type", [
                    "close": object([
                        "type": fixed("close"), "visibility": .choice(["root-only", "all-depths"]),
                        "placement": fixed("trailing"), "rail": .choice(["automatic", "keep-horizontal-when-allowed"]),
                        "guard": .variant("type", [
                            "none": object(["type": fixed("none")]), "draft": .unsupported("sh.forms@1")
                        ])
                    ]),
                    "form-actions": .unsupported("sh.forms@1")
                ])
            ]),
            "fullscreen": .unsupported("sh.fullscreen@1")
        ])
    }()

    // MARK: - Values, source descriptors and actions

    static func value(literal: Shape) -> Shape { value(literal: literal, fallback: nil) }

    /// A text slot (`sh.rules@1`): a literal, a read or an `expr` operand, the last two with the text to draw while unavailable.
    static func textValue(_ literal: Shape) -> Shape { value(literal: literal, fallback: literal) }

    private static func value(literal: Shape, fallback: Shape?) -> Shape {
        var read: [String: Shape] = [
            "type": fixed("read"), "from": .variant("type", [
                "source": object([
                    "type": fixed("source"), "sourceId": id, "path": array(.text(160, blank: false), 8, minimum: 1)
                ]),
                "variable": .unsupported("sh.local-state@1"),
                "parameter": .unsupported("sh.route-arguments@1")
            ]),
            "as": .choice(["string", "number", "boolean", "entity-id"]), "missing": fixed("unavailable")
        ]
        var variants: [String: Shape] = ["literal": object(["type": fixed("literal"), "value": literal])]
        if let fallback {
            read["fallback"] = .optional(fallback)
            variants["expr"] = object(["type": fixed("expr"), "value": operand, "fallback": .optional(fallback)])
        }
        variants["read"] = object(read)
        return .variant("type", variants)
    }
    static let source: Shape = {
        .variant("kind", [
            "ha-entity": object(["id": id, "kind": fixed("ha-entity"), "entityId": value(literal: .text(160, blank: false))]),
            "model": .variant("model", [
                "home-status@1": homeStatusSource,
                "home-weather@1": homeWeatherSource,
                "home-light@1": homeLightSource,
                "climate@1": object([
                    "id": id, "kind": fixed("model"), "model": fixed("climate@1"), "inputs": climateInputs
                ]),
                "air-purifier@1": roomDeviceSource("air-purifier@1"),
                "bathroom-fan@1": roomDeviceSource("bathroom-fan@1"),
                "grill@1": roomDeviceSource("grill@1"),
                "humidifier@1": roomDeviceSource("humidifier@1"),
                "bedroom-provider@1": bedroomSource,
                "media-remote-config@1": deviceProviderSource("media-remote-config@1"),
                "bedroom-config@1": deviceProviderSource("bedroom-config@1"),
                "custom-lights@1": deviceProviderSource("custom-lights@1"),
                "sprinkler-controller@1": deviceProviderSource("sprinkler-controller@1"),
                "media-remote@1": remoteSource,
                "vacuum@1": object([
                    "id": id, "kind": fixed("model"), "model": fixed("vacuum@1"), "inputs": vacuumDescriptor
                ]),
                "camera-stream@1": cameraSource,
                "app-state@1": object([
                    "id": id, "kind": fixed("model"), "model": fixed("app-state@1"),
                    "inputs": object(["topic": .choice(ServerUIAppState.Topic.allCases.map(\.rawValue))])
                ]),
                "power-toggle@1": object([
                    "id": id, "kind": fixed("model"), "model": fixed("power-toggle@1"),
                    "inputs": object(["entityId": value(literal: .text(160, blank: false))])
                ]),
                "alarm-mode@1": object([
                    "id": id, "kind": fixed("model"), "model": fixed("alarm-mode@1"),
                    "inputs": object(["entityId": literalEntity])
                ]),
                "household-away-status@1": object([
                    "id": id, "kind": fixed("model"), "model": fixed("household-away-status@1"),
                    "inputs": object(["entityId": literalEntity])
                ]),
                "sprinkler-state@1": object([
                    "id": id, "kind": fixed("model"), "model": fixed("sprinkler-state@1"),
                    "inputs": object([
                        "title": title, "lowBatteryPercent": .number(0, 100, integer: false),
                        "stateEntityId": literalEntity, "modeEntityId": literalEntity,
                        "batteryEntityId": literalEntity, "faultEntityId": literalEntity,
                        "nextWateringEntityId": literalEntity, "hubConnectedEntityId": literalEntity,
                        "rainDelayEntityId": literalEntity, "smartWateringEntityId": literalEntity,
                        "zones": array(object([
                            "valveEntityId": literalEntity, "programEntityId": literalEntity,
                            "historyEntityId": literalEntity
                        ]), 32, minimum: 1)
                    ])
                ]),
                "security-door@1": object([
                    "id": id, "kind": fixed("model"), "model": fixed("security-door@1"),
                    "inputs": object(["entityId": literalEntity, "kind": .choice(["lock", "garage"])])
                ]),
                "profile-account@1": object([
                    "id": id, "kind": fixed("model"), "model": fixed("profile-account@1")
                ]),
                "settings-provider@1": object([
                    "id": id, "kind": fixed("model"), "model": fixed("settings-provider@1"),
                    "inputs": object(["providerId": id,
                                      "domain": .choice(ServerUISettingsSource.Domain.allCases.map(\.rawValue))])
                ]),
                "inventory-summary@1": object([
                    "id": id, "kind": fixed("model"), "model": fixed("inventory-summary@1"),
                    "inputs": object([
                        "totalEntityId": literalEntity, "expiringEntityId": .optional(literalEntity),
                        "spaceEntityIds": array(literalEntity, 64, minimum: 1),
                        "expiringLocation": .optional(.text(80, blank: false))
                    ]),
                    "labels": object([
                        "singular": label, "plural": label, "expiringSuffix": label,
                        "separator": .text(80, blank: true), "loadingText": title, "unavailableText": title
                    ])
                ]),
                "todo-counts@1": object([
                    "id": id, "kind": fixed("model"), "model": fixed("todo-counts@1"),
                    "inputs": object(["lists": array(object(["entityId": literalEntity, "overdue": .bool]), 64, minimum: 1)]),
                    "labels": object([
                        "openSuffix": label, "overdueSuffix": label, "separator": .text(80, blank: true),
                        "zeroText": title, "loadingText": title, "unavailableText": title
                    ])
                ]),
                "room-navigation@1": object([
                    "id": id, "kind": fixed("model"), "model": fixed("room-navigation@1"),
                    "ranking": .choice(["configured", "visits-descending-configured-ties@1"]),
                    "visitScriptEntityId": .optional(literalEntity),
                    "items": array(object([
                        "id": id, "title": title, "icon": symbol, "fill": solidFill,
                        "counterEntityId": .optional(literalEntity), "visibility": .optional(roomVisibility),
                        "visitKey": .optional(.text(80, blank: false)), "action": navigationAction,
                        "bodyHint": title
                    ]), 64)
                ]),
                "inventory-list@1": object([
                    "id": id, "kind": fixed("model"), "model": fixed("inventory-list@1"),
                    "inputs": object(["space": .choice(["all-food", "pantry", "fridge", "freezer", "spice-rack", "cabinet"])])
                ]),
                "todo-collection@1": todoCollectionSource,
                "pipeline@1": pipelineSource
            ])
        ])
    }()
    static let todoCollectionSource: Shape = {
        object([
            "id": id, "kind": fixed("model"), "model": fixed("todo-collection@1"),
            "inputs": object([
                "title": title,
                "lists": array(object([
                    "title": label, "entityId": literalEntity, "completionScript": .optional(literalEntity),
                    "hideCompleted": .bool, "hideWhenNoOpenItems": .bool,
                    "visibleWhen": .optional(predicate), "whenUnknown": .optional(whenUnknown)
                ]), 32, minimum: 1),
                "addAction": .variant("type", [
                    "task": object(["type": fixed("task"), "defaultAssignee": .text(160, blank: true)]),
                    "grocery": object(["type": fixed("grocery"), "entityId": literalEntity]),
                    "admin": object(["type": fixed("admin"), "entityId": literalEntity])
                ]),
                "hideListHeaders": .bool, "hiddenByVacation": .bool,
                "empty": object(["title": title, "description": .text(2000, blank: true)]),
                "personalization": .optional(object([
                    "residentId": id, "ownTitle": title, "otherTitle": title,
                    "ownEmptyDescription": .optional(.text(2000, blank: true))
                ]))
            ])
        ])
    }()
    static let literalEntity: Shape = {
        object(["type": fixed("literal"), "value": .text(160, blank: false)])
    }()
    static let roomVisibility: Shape = {
        object(["sourceId": id, "states": array(.text(160, blank: false), 32, minimum: 1)])
    }()
    static let roomCardProps: Shape = {
        object([
            "kind": .choice(RoomCardKind.allCases.map(\.rawValue)), "showState": .bool,
            "subtitleSourceIds": array(id, 16),
            "activeStates": array(.text(160, blank: false), 32),
            "disabledStates": array(.text(160, blank: false), 32),
            "stateLabels": array(object(["state": .text(160, blank: false), "label": title]), 64),
            "visibility": .optional(roomVisibility),
            "alternate": .optional(object(["when": roomVisibility, "sourceId": id, "showState": .bool,
                                           "subtitleSourceIds": array(id, 16)])),
            "chipSources": .optional(object(["aqiSourceId": .optional(id), "colorSourceId": .optional(id),
                                             "alarmSourceId": .optional(id), "homeAwaySourceId": .optional(id),
                                             "awaySourceIds": array(id, 16), "pluralContacts": .bool])),
            "personalization": .optional(object(["residentId": id, "ownTitle": title, "otherTitle": title])),
            "stateColors": .optional(array(object(["state": .text(160, blank: false), "fill": solidSlot]), 32)),
            "climateActionTone": .optional(.bool),
            "action": .optional(navigationAction), "power": .optional(powerAction)
        ])
    }()
    static let cameraSource: Shape = {
        object([
            "id": id, "kind": fixed("model"), "model": fixed("camera-stream@1"),
            "inputs": object([
                "entityId": literalEntity, "snapshotEntityId": literalEntity,
                "rtcStreamId": .text(160, blank: false), "aspectRatio": .number(0.25, 8, integer: false),
                "recording": .variant("type", [
                    "disabled": object(["type": fixed("disabled")]),
                    "script": object(["type": fixed("script"), "stateEntityId": literalEntity, "scriptEntityId": literalEntity])
                ])
            ]),
            "labels": object(Dictionary(uniqueKeysWithValues: [
                "loading", "unavailable", "hidden", "connecting", "live", "delayed", "snapshot", "retry",
                "recordFailed", "photosTitle", "photosMessage", "settings", "cancel"
            ].map { ($0, title) }))
        ])
    }()
    static let cameraControl: Shape = {
        object([
            "intent": .choice(["snapshot", "sound", "record"]), "title": title, "activeTitle": title,
            "busyTitle": title, "failureTitle": title, "icon": symbol, "activeIcon": symbol,
            "failureIcon": symbol, "tint": .choice(["action", "danger"])
        ])
    }()
    static let solidFill: Shape = {
        object(["type": fixed("solid-rgb"), "red": .number(0, 255, integer: true),
                "green": .number(0, 255, integer: true), "blue": .number(0, 255, integer: true)])
    }()
    static let standardFill = object(["type": fixed("standard")])
    /// A colour that differs by appearance (`sh.solid-appearance@1`): an exact colour for each of light and dark, both required. A member is a
    /// `solid-rgb`, so a standard member or a nested pair is refused at the member's first missing channel.
    static let solidAppearance: Shape = {
        object(["type": fixed("solid-appearance"), "light": solidFill, "dark": solidFill])
    }()
    /// An exact colour a slot may hold: one colour, or one for each appearance.
    static let exactSolid: Shape = .variant("type", ["solid-rgb": solidFill, "solid-appearance": solidAppearance])

    // MARK: Rules (`sh.rules@1`, `sh.enabled-when@1`)

    /// A rule's value: the first case whose condition holds gives `then`, else `otherwise`. Cases hold exact looks.
    static func conditional(_ then: Shape) -> Shape {
        object(["type": fixed("conditional"), "cases": array(object(["when": predicate, "then": then]), 16, minimum: 1),
                "otherwise": then])
    }
    /// A color named by an entity's text; the fallback is required.
    static func boundColor(_ fallback: Shape) -> Shape {
        object(["type": fixed("bound-color"), "value": operand, "fallback": fallback])
    }
    /// A fill that may follow a rule or an entity's color: standard or exact, a `conditional`, or a `bound-color`.
    static let fillSlot: Shape = {
        let both = Shape.variant("type", ["standard": standardFill, "solid-rgb": solidFill, "solid-appearance": solidAppearance])
        return .variant("type", ["standard": standardFill, "solid-rgb": solidFill, "solid-appearance": solidAppearance,
                                 "conditional": conditional(both), "bound-color": boundColor(both)])
    }()
    /// The same for a slot with no standard look: an exact color, a `conditional` of exact colors, or a `bound-color` with an exact fallback.
    static let solidSlot: Shape = {
        .variant("type", ["solid-rgb": solidFill, "solid-appearance": solidAppearance,
                          "conditional": conditional(exactSolid), "bound-color": boundColor(exactSolid)])
    }()
    /// A symbol that may follow a rule or an entity's text: exact, a `conditional`, or a `bound-symbol` with a fallback symbol.
    static let symbolSlot: Shape = {
        .variant("type", ["sf-symbol": symbol, "conditional": conditional(symbol),
                          "bound-symbol": object(["type": fixed("bound-symbol"), "value": operand, "fallback": symbol])])
    }()
    /// A readout tone: one word, or a rule whose cases each hold one.
    static let toneSlot: Shape = {
        let tone = Shape.choice(["neutral", "ok", "active", "warning", "danger", "unavailable"])
        return .either(text: tone, object: .collapsed(conditional(tone)))
    }()
    /// `enabledWhen`: a condition and what to do while it cannot be answered. Both are required.
    static let enabledWhen: Shape = {
        object(["condition": predicate, "whenUnknown": .choice(ServerUIEnabledUnknown.allCases.map(\.rawValue))])
    }()
    static let alarmAppearance: Shape = {
        object(["icon": symbol, "fill": solidFill, "text": title])
    }()
    static let alarmNavigation: Shape = {
        object([
            "sourceId": id, "projection": fixed("alarm-navigation@1"),
            "states": array(object([
                "state": .choice(["disarmed", "armed_home", "armed_away", "armed_night", "armed_vacation",
                                  "armed_custom_bypass", "triggered", "arming", "pending", "disarming"]),
                "appearance": alarmAppearance
            ]), 10),
            "fallback": alarmAppearance, "loadingText": title, "unavailableText": title,
            "errorText": title, "hiddenText": title
        ])
    }()
    static let push: Shape = {
        object(["type": fixed("push"), "pageId": id, "arguments": arguments,
                "origin": fixed("sender"), "duplicate": fixed("reuse-nearest")])
    }()
    static let confirmation: Shape = {
        .variant("type", [
            "policy": object(["type": fixed("policy")]),
            "additional": object([
                "type": fixed("additional"), "style": .choice(["alert", "dialog"]), "title": title,
                "message": .optional(.text(2_000, blank: true)), "confirmLabel": title,
                "cancelLabel": fixed("Cancel"), "destructive": .bool, "when": .optional(predicate)
            ])
        ])
    }()
    static let action: Shape = {
        action(allowing: nil)
    }()
    /// A power toggle on a data source.
    static let domainAction: Shape = {
        object(["type": fixed("domain"), "sourceId": id, "intent": fixed("power.toggle"),
                "feedback": fixed("policy"), "confirmation": confirmation])
    }()
    static let navigationAction: Shape = {
        action(allowing: ["push", "select-tab", "present", "dismiss-then-push", "set-local"])
    }()
    static let powerAction: Shape = {
        action(allowing: ["domain", "set-local"])
    }()
    /// The actions an action slot allows; `ruled` also allows the action chosen by rule (`sh.action-rules@1`).
    private static func action(allowing allowed: Set<String>?, ruled: Bool = false) -> Shape {
        let variants: [String: Shape] = [
            "push": push,
            "select-tab": object(["type": fixed("select-tab"), "tabId": id]),
            "present": object(["type": fixed("present"), "modalId": id, "arguments": arguments, "ifPresented": .choice(["reject", "replace"])]),
            "back": object(["type": fixed("back")]),
            "dismiss": object(["type": fixed("dismiss"), "scope": fixed("current-modal")]),
            "dismiss-then-push": object(["type": fixed("dismiss-then-push"), "destination": push]),
            "domain": domainAction,
            "set-local": object(["type": fixed("set-local"), "stateId": id, "value": localValue]),
            "call-service": .callService
        ]
        let plain = variants.filter { allowed?.contains($0.key) ?? true }
        guard ruled else { return .variant("type", plain) }
        // One level: a case holds a plain action, never another rule; `otherwise` may also be `none`.
        let choice = Shape.variant("type", plain.merging(["none": object(["type": fixed("none")])]))
        let rule = object(["type": fixed("conditional"),
                           "cases": array(object(["when": predicate, "then": .variant("type", plain)]), 16, minimum: 1),
                           "otherwise": choice])
        return .variant("type", plain.merging(["conditional": .collapsed(rule)]))
    }
    /// Any action, or any action chosen by rule.
    static let ruledAction: Shape = { action(allowing: nil, ruled: true) }()
    /// A navigation tile's action: any action (the compiler keeps it to navigation), or one chosen by rule.
    static let ruledNavigationAction: Shape = ruledAction
    static let component: Shape = {
        let base: [String: Shape] = [
            "id": id, "title": title, "layout": layoutSpan,
            "visibleWhen": .optional(predicate), "whenUnknown": .optional(whenUnknown)
        ]
        func node(_ type: String, _ extra: [String: Shape]) -> Shape {
            object(base.merging(["type": fixed(type)]).merging(extra))
        }
        return .variant("type", shellNodes(base: base).merging([
            "component-ref": componentRef,
            "status-chip": node("status-chip", ["props": object(statusProps), "action": .optional(ruledHomeNavigationAction), "badge": .optional(badge)]),
            "status-rail": node("status-rail", ["props": object([:]), "children": array(.component, 20)]),
            "room-overview-tile": node("room-overview-tile", [
                "props": object(statusProps.merging(["hidesContactSubtitle": .bool, "powerSourceId": .optional(id), "words": .optional(stateWords)])),
                "action": .optional(ruledHomeNavigationAction), "badge": .optional(badge)
            ]),
            "light-group-tile": node("light-group-tile", ["props": object(["sourceId": id, "swipe": .optional(tileSwipe), "words": .optional(stateWords)])]),
            "weather-panel": node("weather-panel", ["props": weatherProps, "action": .optional(homeNavigationAction)]),
            "alarm-panel": node("alarm-panel", ["props": alarmPanelProps]),
            "door-tile": node("door-tile", ["props": doorTileProps]),
            "climate-control": node("climate-control", ["props": climateProps, "action": .optional(homeNavigationAction)]),
            "room-device-control": roomDeviceControl,
            "humidifier-schedule-field": .unsupported("sh.humidifier-schedule-editor@1"),
            "humidifier-schedule-activities": .unsupported("sh.collections@1"),
            "remote-control": node("remote-control", [
                "binding": object(["sourceId": id]), "props": remoteControl, "feedback": remoteFeedback
            ]),
            "vacuum-control": node("vacuum-control", [
                "props": object(["sourceId": id, "primitive": vacuumPrimitive])
            ]),
            "camera-tile": node("camera-tile", [
                "props": object(["sourceId": id, "openHint": title]), "action": action
            ]),
            "camera-video": node("camera-video", ["props": object(["sourceId": id])]),
            "camera-controls": node("camera-controls", [
                "props": object(["sourceId": id, "controls": array(cameraControl, 3, minimum: 1)])
            ]),
            "camera-viewer": node("camera-viewer", [
                "props": object(["sourceId": id, "controls": array(cameraControl, 3, minimum: 1)])
            ]),
            "text": node("text", [
                "props": object([
                    "value": textValue(.text(16_384, blank: true)),
                    "style": .choice(ServerUICompositionDocument.TextStyle.allCases.map(\.rawValue)),
                    "unavailableText": .text(16_384, blank: false)
                ].merging(textLookFields) { _, rhs in rhs })
            ]),
            "account-header": node("account-header", [
                "binding": object(["sourceId": id, "projection": fixed("profile-account@1")]),
                "props": object([
                    "fallbackName": title, "loadingText": title, "unavailableText": title
                ])
            ]),
            "settings-control": node("settings-control", [
                "icon": symbol,
                "props": object([
                    "sourceId": id, "kind": .choice(ServerUISettingsControl.Kind.allCases.map(\.rawValue)),
                    "item": .text(160, blank: true), "subtitle": .text(2_000, blank: true),
                    "destination": .optional(navigationAction)
                ])
            ]),
            "settings-link": node("settings-link", [
                "icon": symbol,
                "props": object([
                    "subtitle": .text(2_000, blank: true),
                    "hint": .optional(.text(240, blank: false)),
                    "showsChevron": .bool
                ]),
                "action": action
            ]),
            "tile-grid": node("tile-grid", [
                "props": object([
                    "minimum": .choice(["tile@1", "tile-dynamic-type@1", "section-wide@1"]), "maxColumns": .number(1, 4, integer: true),
                    "spacing": space, "equalRowHeights": .bool, "shortRow": .choice(["share", "leading"]),
                    "fold": .choice(["page", "container"]), "minimumColumns": .optional(.number(2, 4, integer: true)), "groups": .optional(gridGroups)
                ]),
                "children": array(.component, 100)
            ]),
            "info-box": node("info-box", [
                "props": object(["message": textValue(.text(2_000, blank: true)), "tone": .choice(["neutral", "success"]),
                                 "unavailableText": label])
            ]),
            "status-pill": node("status-pill", [
                "icon": symbol, "props": object([
                    "value": textValue(.text(2_000, blank: true)), "detail": textValue(.text(2_000, blank: true)),
                    "tone": toneSlot, "unavailableText": label
                ])
            ]),
            "paged-row": node("paged-row", [
                "props": object(["perPage": .number(1, 8, integer: true), "pageLabel": label, "showsIndicator": .bool]),
                "children": array(.component, 100)
            ]),
            "navigation-tile": node("navigation-tile", [
                "icon": symbol, "props": object([
                    "family": .choice(["neutral", "lights", "groceries", "chore-resident-1", "chore-resident-2", "chore-unassigned", "chore-home"]),
                    "selected": .choice(["navigation-path", "none"]), "titleProviderId": .optional(id),
                    "subtitle": textValue(.text(2_000, blank: true)),
                    "alarm": .optional(alarmNavigation),
                    "roomVisibility": .optional(roomVisibility),
                    "presentation": .optional(object([
                        "layout": .choice(["standard", "anchored-bottom"]),
                        "titleLines": .number(0, 2, integer: true),
                        "fill": fillSlot,
                        "bodyHint": .optional(.text(240, blank: false))
                    ]))
                ]),
                "action": ruledNavigationAction, "badge": .optional(badge)
            ]),
            "bootstrap-message": node("bootstrap-message", [
                "icon": symbol, "props": object(["message": .text(2_000, blank: true)])
            ]),
            "notification-permission-banner": node("notification-permission-banner", [
                "props": object(["message": .text(2_000, blank: false), "enableLabel": label, "dismissLabel": label])
            ]),
            "state-tile": node("state-tile", ["icon": symbol, "props": tileParts, "binding": stateTileBinding,
                                              "enabledWhen": .optional(enabledWhen)].merging(stateTileFields)),
            "action-tile": node("action-tile", [
                "icon": symbol, "binding": object(["sourceId": id, "projection": fixed("power-tile@1")]),
                "props": object([
                    "family": .choice(["neutral", "lights", "occupancy"]), "bodyActionId": fixed("power"),
                    "actionOrder": .array(fixed("power"), 1, 1), "stateText": fixed("provider"), "feedback": fixed("policy"),
                    "powerLabels": .optional(object(["on": title, "off": title]))
                ]),
                "action": domainAction
            ]),
            "room-card": node("room-card", [
                "icon": symbol, "binding": object(["sourceId": id, "projection": fixed("room-state@1")]),
                "props": roomCardProps
            ]),
            "room-chip": node("room-chip", [
                "icon": symbol, "binding": object(["sourceId": id, "projection": fixed("room-state@1")]),
                "props": roomCardProps
            ]),
            "room-navigation-grid": node("room-navigation-grid", [
                "binding": object(["sourceId": id, "projection": fixed("room-navigation@1")]),
                "props": object([:])
            ]),
            "room-section": node("room-section", [
                "props": object([
                    "arrangement": .choice(["grid", "lead-row", "two-column-fill"]),
                    "leadJoinsAtRegularWidth": .bool, "visibility": .optional(roomVisibility)
                ]),
                "children": array(.component, 100)
            ]),
            "room-app-launch": .unsupported("sh.room-app-launch@1"),
            "bedroom-control": node("bedroom-control", ["props": bedroomControl]),
            "custom-light-control": deviceControlNode(base: base, domain: .lights),
            "sprinkler-control": deviceControlNode(base: base, domain: .sprinkler),
            "section-sides": .unsupported("sh.section-sides@1"),
            "content-panes": .unsupported("sh.content-panes@1")
        ]).merging(styleNodes(base: base)) { _, rhs in rhs }.merging(repeatNodes(base: base)) { _, rhs in rhs }.merging(chartNodes(base: base)) { _, rhs in rhs }.merging(dialNodes(base: base)) { _, rhs in rhs })
    }()
    static let asset: Shape = {
        object([
            "id": id, "role": .choice(["backdrop", "content-image"]),
            "source": .variant("type", [
                "publisher": object(["type": fixed("publisher"), "path": .text(100, blank: false)]),
                "public-https": .unsupported("sh.public-assets@1")
            ]),
            "sha256": .hash, "mimeType": .choice(["image/png", "image/jpeg"]),
            "byteLength": .number(1, 8_388_608, integer: true),
            "pixelWidth": .number(1, 8_192, integer: true), "pixelHeight": .number(1, 8_192, integer: true)
        ])
    }()

    // MARK: - Exhaustive shape diagnostics

    static func validate(_ value: JSONValue) throws -> [Issue] {
        var issues: [Issue] = []
        var unsupported: [Issue] = []
        walk(value, shape: publication, pointer: "", issues: &issues, unsupported: &unsupported)
        if let first = first(issues) { throw first }
        return unsupported
    }
    /// Every structural issue `value` has against one `shape`; empty when it conforms.
    static func issues(of value: JSONValue, against shape: Shape) -> [Issue] {
        var issues: [Issue] = []
        var unsupported: [Issue] = []
        walk(value, shape: shape, pointer: "", issues: &issues, unsupported: &unsupported)
        return issues
    }
    static func first(_ issues: [Issue]) -> Issue? {
        issues.sorted {
            if $0.pointer == $1.pointer { return $0.code.rawValue < $1.code.rawValue }
            return $0.pointer < $1.pointer
        }.first
    }
    static func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) == text.startIndex..<text.endIndex
    }
    static func validID(_ value: String) -> Bool {
        !ServerUICompositionJSON.reserved.contains(value) && matches(value, "^[A-Za-z0-9][A-Za-z0-9_.-]{0,79}$")
    }
    private static func walk(_ value: JSONValue, shape: Shape, pointer: String,
                             issues: inout [Issue], unsupported: inout [Issue]) {
        func issue(_ code: Issue.Code, _ at: String? = nil) { issues.append(Issue(code, at ?? pointer)) }
        switch shape {
        case .object(let fields):
            guard case .object(let object) = value else { issue(.invalidValue); return }
            for key in object.keys where fields[key] == nil { issue(.unknownField, ServerUICompositionJSON.pointer(pointer, key)) }
            for (key, field) in fields {
                let path = ServerUICompositionJSON.pointer(pointer, key)
                guard let child = object[key] else {
                    if case .optional = field {} else { issue(.missingRequired, path) }
                    continue
                }
                walk(child, shape: field, pointer: path, issues: &issues, unsupported: &unsupported)
            }
        case .optional(let field):
            walk(value, shape: field, pointer: pointer, issues: &issues, unsupported: &unsupported)
        case .array(let item, let minimum, let maximum):
            guard case .array(let array) = value else { issue(.invalidValue); return }
            if array.count < minimum || array.count > maximum { issue(.limitExceeded) }
            for (index, child) in array.enumerated() {
                walk(child, shape: item, pointer: "\(pointer)/\(index)", issues: &issues, unsupported: &unsupported)
            }
        case .text(let maximum, let blank):
            guard case .string(let text) = value else { issue(.invalidValue); return }
            if text.utf16.count > maximum { issue(.limitExceeded) }
            if !blank, text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { issue(.invalidValue) }
        case .pattern(let pattern, let maximum):
            guard case .string(let text) = value else { issue(.invalidValue); return }
            if text.utf16.count > maximum { issue(.limitExceeded) }
            if !matches(text, pattern) { issue(.invalidValue) }
        case .dictionary(let keyShape, let childShape, let maximum):
            guard case .object(let values) = value else { issue(.invalidValue); return }
            if values.count > maximum { issue(.limitExceeded) }
            for (key, child) in values {
                let path = ServerUICompositionJSON.pointer(pointer, key)
                walk(.string(key), shape: keyShape, pointer: path, issues: &issues, unsupported: &unsupported)
                walk(child, shape: childShape, pointer: path, issues: &issues, unsupported: &unsupported)
            }
        case .identifier:
            guard case .string(let text) = value, validID(text) else { issue(.invalidValue); return }
        case .nullableID:
            if value != .null { walk(value, shape: .identifier, pointer: pointer, issues: &issues, unsupported: &unsupported) }
        case .nullableNumber(let minimum, let maximum):
            if value != .null { walk(value, shape: .number(minimum, maximum, integer: false), pointer: pointer, issues: &issues, unsupported: &unsupported) }
        case .hash:
            guard case .string(let text) = value, matches(text, "^[0-9a-f]{64}$") else { issue(.invalidValue); return }
        case .bool:
            guard case .bool = value else { issue(.invalidValue); return }
        case .number(let minimum, let maximum, let integer):
            guard case .number(let number) = value, number.isFinite else { issue(.invalidValue); return }
            if integer, number.rounded() != number { issue(.invalidValue) }
            if number < minimum || number > maximum { issue(.limitExceeded) }
        case .choice(let choices):
            guard case .string(let text) = value else { issue(.invalidValue); return }
            if !choices.contains(text) { issue(.unknownVariant) }
        case .variant(let key, let variants):
            guard case .object(let object) = value else { issue(.invalidValue); return }
            let path = ServerUICompositionJSON.pointer(pointer, key)
            guard let tag = object[key] else { issue(.missingRequired, path); return }
            guard case .string(let text) = tag else { issue(.invalidValue, path); return }
            guard let variant = variants[text] else { issue(.unknownVariant, path); return }
            if case .unsupported(let capability) = variant {
                unsupported.append(Issue(.unsupportedCapability, path, capability: capability))
            } else {
                walk(value, shape: variant, pointer: pointer, issues: &issues, unsupported: &unsupported)
            }
        case .closedVariant(let key, let variants):
            guard case .object(let object) = value else { issue(.invalidValue); return }
            let path = ServerUICompositionJSON.pointer(pointer, key)
            guard let tag = object[key] else { issue(.missingRequired, path); return }
            guard case .string(let text) = tag else { issue(.invalidValue, path); return }
            guard let variant = variants[text] else { issue(.unknownVariant); return }
            walk(value, shape: variant, pointer: pointer, issues: &issues, unsupported: &unsupported)
        case .emptyObject(let capability, let maximum):
            guard case .object(let object) = value else { issue(.invalidValue); return }
            if object.count > maximum { issue(.limitExceeded) }
            for key in object.keys where !validID(key) { issue(.invalidValue, ServerUICompositionJSON.pointer(pointer, key)) }
            if !object.isEmpty { unsupported.append(Issue(.unsupportedCapability, pointer, capability: capability)) }
        case .unsupported(let capability):
            unsupported.append(Issue(.unsupportedCapability, pointer, capability: capability))
        case .collapsed(let inner):
            var inside: [Issue] = []
            walk(value, shape: inner, pointer: pointer, issues: &inside, unsupported: &unsupported)
            guard !inside.isEmpty else { break }
            if case .object(let object) = value, case .array(let cases)? = object["cases"], cases.isEmpty {
                issues.append(Issue(.limitExceeded, ServerUICompositionJSON.pointer(pointer, "cases")))
            } else { issue(.unknownVariant) }
        case .either(let text, let object):
            if case .string = value {
                walk(value, shape: text, pointer: pointer, issues: &issues, unsupported: &unsupported)
            } else {
                walk(value, shape: object, pointer: pointer, issues: &issues, unsupported: &unsupported)
            }
        case .component:
            walk(value, shape: component, pointer: pointer, issues: &issues, unsupported: &unsupported)
        case .operand:
            var parser = ServerUIExpressionParser(allowControl: true, scope: .lenient)
            _ = parser.operand(value, at: pointer)
            issues += parser.issues
        case .predicate:
            var parser = ServerUIExpressionParser(scope: .lenient)
            _ = parser.predicate(value, at: pointer)
            issues += parser.issues
        case .callService:
            var parser = ServerUIExpressionParser(allowControl: true, scope: .lenient)
            _ = parser.callService(value, at: pointer)
            issues += parser.issues
        case .flowOperand:
            var parser = ServerUIExpressionParser(flow: true)
            _ = parser.operand(value, at: pointer)
            issues += parser.issues
        case .flowPredicate:
            var parser = ServerUIExpressionParser(flow: true)
            _ = parser.predicate(value, at: pointer)
            issues += parser.issues
        case .flowShape:
            issues += ServerUIFlowShape.issues(in: value, at: pointer)
        case .allOrIdentifiers(let maximum):
            if value == .string("all") { return }
            walk(value, shape: .array(.identifier, 1, maximum), pointer: pointer, issues: &issues, unsupported: &unsupported)
        }
    }
}

private extension Dictionary where Key == String, Value == ServerUICompositionShape.Shape {
    func merging(_ other: Self) -> Self { merging(other) { _, rhs in rhs } }
}

// MARK: - State styles (`sh.state-style@1`)

extension ServerUICompositionShape {
    private static let serviceName = Shape.pattern("^[a-z][a-z0-9_]*$", 64)
    private static let entityId = Shape.pattern("^[a-z][a-z0-9_]*\\.[a-z0-9_]+$", 160)
    private static let word = Shape.text(80, blank: false)
    private static let stateAction: Shape = {
        object([
            "verb": label, "icon": word, "service": .optional(serviceName), "tappable": .optional(.bool),
            "confirmation": .optional(object(["title": title, "message": .text(2_000, blank: false), "confirmVerb": title])),
            "requiresFeature": .optional(.number(1, 65_535, integer: true)),
            "otherwise": .optional(object(["verb": label, "icon": word, "service": .optional(serviceName)]))
        ])
    }()
    private static let stateLook: [String: Shape] = [
        "class": .choice(StateClass.allCases.map(\.rawValue)), "active": .bool,
        "icon": .optional(word), "text": .optional(word),
        "indicator": .optional(.choice(StateIndicator.allCases.map(\.rawValue))),
        "colour": .optional(.choice(StateColour.allCases.map(\.rawValue))),
        "action": .optional(stateAction), "fill": .optional(exactSolid),
        "fillInk": .optional(.collapsed(.choice(StateFillInk.allCases.map(\.rawValue))))
    ]
    private static let stateRequest: Shape = {
        object([
            "lockoutSeconds": .number(0, 60, integer: true), "ackTimeoutSeconds": .number(1, 120, integer: true),
            "settleTimeoutSeconds": .number(0, 600, integer: true), "errorHoldSeconds": .number(0, 60, integer: true),
            "onTimeout": .choice(StateRequest.OnTimeout.allCases.map(\.rawValue)),
            "pendingWords": .optional(array(object(["service": serviceName, "text": word]), 8)),
            "errorWords": .optional(word), "script": .optional(entityId), "errorTimer": .optional(entityId)
        ])
    }()
    static let stateStyleLibrary: Shape = {
        object([
            "type": fixed("state-styles@1"),
            "styles": array(object([
                "id": id, "name": label, "base": .optional(.choice(StateStyle.builtIn.map(\.id))),
                "domain": .pattern("^[a-z][a-z0-9_]*$", 64), "actionId": .optional(id),
                "togglesDisc": .optional(.bool), "drawsErrorDisc": .optional(.bool), "hiddenWords": .optional(word),
                "rules": array(object(stateLook.merging(["states": array(word, 16, minimum: 1)]) { $1 }), 32, minimum: 1),
                "fallback": object(stateLook), "request": .optional(stateRequest)
            ]), 32)
        ])
    }()
    static let stateTileBinding: Shape = {
        object([
            "entityId": entityId, "styleId": .optional(id), "builtIn": .optional(.choice(StateStyle.builtIn.map(\.id))),
            "overrides": .optional(array(object([
                "state": word, "icon": .optional(word), "text": .optional(word),
                "indicator": .optional(.choice(StateIndicator.allCases.map(\.rawValue))),
                "colour": .optional(.choice(StateColour.allCases.map(\.rawValue)))
            ]), 32))
        ])
    }()
}
