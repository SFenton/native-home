import Foundation

// MARK: - Bound controls

extension ServerUICompositionDocument {
    /// A control whose value is read from Home Assistant and whose changes are authored service calls (`sh.bound-control@1`).
    ///
    /// It is the same canonical control a local control shows (switch, stepper, slider, segmented or menu choice, button),
    /// with the shown value coming from entity state and `send` running a ``ServerUICallService``. The control keeps no copy
    /// of its value: after a request it shows what Home Assistant reports (or the optimistic value the call declared).
    public struct BoundControl: Equatable, Sendable {
        /// The authored kind choices.
        public enum Kind: String, Sendable, CaseIterable { case toggle, stepper, slider, choice, button }
        /// Where a toggle sits: a list row with a switch, or a glass tile.
        public enum Surface: String, Sendable { case row, tile }

        /// A stepper's whole-number range (a slider is the canonical 0 to 100 in steps of 5).
        public struct Range: Equatable, Sendable {
            public let minimum: Int
            public let maximum: Int
            public let step: Int

            /// Creates a range.
            public init(minimum: Int, maximum: Int, step: Int) {
                self.minimum = minimum
                self.maximum = maximum
                self.step = step
            }
        }

        /// One option of a choice: shown selected while its predicate holds, sends its call when picked.
        public struct Option: Equatable, Sendable {
            public let id: String
            public let label: String
            public let selectedWhen: ServerUIPredicate
            public let action: ServerUICallService
        }

        public let node: Node
        public let icon: Symbol?
        public let kind: Kind
        public let surface: Surface
        /// Toggle: on while the predicate holds.
        public let isOn: ServerUIPredicate?
        /// Stepper and slider: the value shown (a slider reads a number from 0 to 100).
        public let value: ServerUIOperand?
        public let range: Range?
        /// Stepper: a pattern with a `{value}` hole for the label, or `nil` for the bare number.
        public let valueFormat: String?
        public let options: [Option]
        /// Toggle: the call that turns it on.
        public let onAction: ServerUICallService?
        /// Toggle: the call that turns it off.
        public let offAction: ServerUICallService?
        /// Stepper, slider and button: the call (`{control}` is the new number).
        public let action: ServerUICallService?
        /// Said while the value cannot be read.
        public let unavailableText: String
        /// A choice's options read from an entity's list, the authored ``options`` standing as the fallback (`sh.bound-options-read@1`).
        public var optionsFrom: ServerUIOptionsRead? = nil
        /// A toggle row's own parts and face (`sh.bound-row-parts@1`, `sh.check-face@1`).
        public var row = ServerUIRowParts()

        /// Every call the control can send.
        public var actions: [ServerUICallService] {
            [onAction, offAction, action].compactMap { $0 } + options.map(\.action) + [optionsFrom?.action].compactMap { $0 }
        }

        /// The source ids the shown value depends on (what an observation of the control tracks).
        public var sourceIds: Set<String> {
            var ids = isOn?.sourceIds ?? []
            ids.formUnion(value?.sourceIds ?? [])
            for option in options { ids.formUnion(option.selectedWhen.sourceIds) }
            if let optionsFrom { ids.formUnion(optionsFrom.sourceIds) }
            ids.formUnion(row.sourceIds)
            return ids
        }
    }
}
