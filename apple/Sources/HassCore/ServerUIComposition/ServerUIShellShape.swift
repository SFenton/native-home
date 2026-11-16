import Foundation

// MARK: - Negotiated shell grammar

extension ServerUICompositionShape {
    static let localField: Shape = {
        .variant("type", [
            "string": object(["id": id, "type": fixed("string"), "initial": .text(16_384, blank: true),
                              "maxLength": .number(1, 16_384, integer: true)]),
            "boolean": object(["id": id, "type": fixed("boolean"), "initial": .bool]),
            "number": object(["id": id, "type": fixed("number"), "initial": .number(-1_000_000, 1_000_000, integer: false),
                              "minimum": .number(-1_000_000, 1_000_000, integer: false),
                              "maximum": .number(-1_000_000, 1_000_000, integer: false),
                              "step": .number(0.000_001, 1_000_000, integer: false)]),
            "choice": object(["id": id, "type": fixed("choice"), "initial": id,
                              "options": array(object(["id": id, "label": label]), 12, minimum: 2)])
        ])
    }()

    static let localValue: Shape = {
        .variant("type", [
            "string": object(["type": fixed("string"), "value": .text(16_384, blank: true)]),
            "boolean": object(["type": fixed("boolean"), "value": .bool]),
            "number": object(["type": fixed("number"), "value": .number(-1_000_000, 1_000_000, integer: false)])
        ])
    }()

    static func shellNodes(base: [String: Shape]) -> [String: Shape] {
        func node(_ type: String, _ extra: [String: Shape]) -> Shape {
            object(base.merging(["type": fixed(type)]) { _, rhs in rhs }.merging(extra) { _, rhs in rhs })
        }
        return [
            "section": node("section", [
                "props": object(["header": .text(240, blank: true), "footer": .text(2_000, blank: true),
                                 "style": .choice(["plain", "module-list"]), "density": .choice(["thin", "dense"]),
                                 "hasGlyphs": .bool, "spacing": space, "presentationProviderId": .optional(id)]),
                "children": array(.component, 100)
            ]),
            "row": node("row", [
                "props": object(["primary": value(literal: .text(2_000, blank: false)),
                                 "secondary": value(literal: .text(2_000, blank: true)),
                                 "value": value(literal: .text(2_000, blank: true)),
                                 "icon": .optional(symbol), "accessory": .choice(["none", "disclosure"]),
                                 "loadingText": title, "unavailableText": title]),
                "action": .optional(action)
            ]),
            "local-tabs": node("local-tabs", [
                "props": object(["stateId": id, "transition": fixed("canonical-swap@1"), "resetOnPresentation": .optional(.bool), "pinned": .optional(.bool),
                                 "scopeProviderId": .optional(id), "showsSelector": .optional(.bool), "retainsAutomaticSelection": .optional(.bool),
                                 "automatic": .optional(array(object(["tabId": id, "selectedWhen": predicate]), 5)),
                                 "fallbackTabId": .optional(id), "tabBar": .optional(tabBar)]),
                "tabs": array(object(["id": id, "label": label, "children": array(.component, 100),
                                     "icon": .optional(symbol), "centerWhenFits": .optional(.bool)].merging(tabRule) { _, rhs in rhs }), 5, minimum: 2),
                "blocks": .optional(array(tabBlock, 40))
            ]),
            "overlay": node("overlay", overlayFields),
            "local-control": node("local-control", [
                "props": object(["stateId": id, "kind": .choice(["toggle", "stepper", "choice", "text-field", "segmented-choice"]),
                                 "placeholder": .text(240, blank: true)])
            ]),
            "bound-control": node("bound-control", [
                "icon": .optional(symbol),
                "props": object([
                    "kind": .choice(ServerUICompositionDocument.BoundControl.Kind.allCases.map(\.rawValue)),
                    "surface": .optional(.choice(["row", "tile"])),
                    "isOn": .optional(predicate), "value": .optional(operand),
                    "range": .optional(object(["min": .number(-1_000_000, 1_000_000, integer: true),
                                               "max": .number(-1_000_000, 1_000_000, integer: true),
                                               "step": .number(1, 1_000_000, integer: true)])),
                    "format": .optional(.text(240, blank: false)),
                    "options": .optional(array(object(["id": id, "label": label, "selectedWhen": predicate,
                                                        "action": callService]), 12)),
                    "unavailableText": title
                ]),
                "onAction": .optional(callService), "offAction": .optional(callService), "action": .optional(callService)
            ]),
            "primary-button": node("primary-button", ["props": object([:]), "icon": .optional(symbol), "action": action]),
            "row-collection": node("row-collection", [
                "props": object(["providerId": id, "loadingText": title, "emptyText": title,
                                 "unavailableText": title, "errorText": title, "staleText": title])
            ]),
            "collection": node("collection", [
                "props": object(["providerId": id, "template": .choice(["rows", "todo", "inventory", "recipes", "carousel"]),
                                 "loadingText": title, "emptyText": title, "pullToRefresh": .optional(.bool),
                                 "bedroomLinks": .optional(array(object(["side": .choice(["left", "right"]), "label": title,
                                                                          "action": navigationAction]), 2, minimum: 1))]),
                "selection": .optional(action)
            ]),
            "form": node("form", [
                "props": object(["providerId": id, "saveLabel": label, "selectionOnly": .bool,
                                 "fields": array(object(["key": id, "label": label,
                                    "control": .choice(["text", "multiline", "number", "toggle", "choice",
                                                        "date", "time", "weekdays", "attachment", "options", "percent", "segmented", "scan-camera", "schedule-date-time"])]), 32, minimum: 1)]),
                "success": .optional(action)
            ]),
            "recipe-part": node("recipe-part", [
                "props": object(["providerId": id, "part": .choice(["hero", "general", "ingredients", "instructions"])])
            ]),
            "pinned-actions": node("pinned-actions", [
                "props": object(["searchProviderId": .optional(id), "searchPrompt": label, "style": .optional(.choice(["floating", "form"])),
                                 "items": array(object(["id": id, "title": label, "icon": symbol,
                                     "prominent": .bool, "showsTitle": .bool, "action": action,
                                     "role": .optional(.choice(["sort", "filter", "create"])), "stateProviderId": .optional(id)]), 4)]),
                "children": .optional(array(.component, 1))
            ]),
            "info-box": .unsupported("sh.info-box@1"),
            "content-unavailable": .unsupported("sh.content-unavailable@1"),
            "arc-spinner": .unsupported("sh.arc-spinner@1"),
            "pending-value-bar": .unsupported("sh.pending-value-bar@1"),
            "modal-tab-bar": .unsupported("sh.modal-tab-bar@1"),
            "sheet-edit-toolbar": .unsupported("sh.forms@1"),
            "floating-action-bar": .unsupported("sh.floating-action-bar@1"),
            "schedule-date-fields": .unsupported("sh.schedule-date-fields@1"),
            "paged-row": .unsupported("sh.paged-row@1"),
            "content-image": .unsupported("sh.content-image@1")
        ]
    }
}
