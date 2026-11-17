import Foundation

// MARK: - Stack (`sh.stack@1`)

/// A container that lays its children in a row or a column, with optional spacing, padding, lines between, a surface, a tap and one
/// accessibility element (`sh.stack@1`).
///
/// The document says how the children are arranged, never how wide anything is: ``ServerUIStackLayout`` chooses between the arrangement
/// the stack is written in and the collapsed one a horizontal stack falls back to, from the widths the draw measures.
public struct ServerUIStack: Equatable, Sendable {

    /// The direction the children run.
    public enum Axis: String, CaseIterable, Sendable { case horizontal, vertical }
    /// Where a child sits across the axis, or along its group's.
    public enum Align: String, CaseIterable, Sendable { case start, center, end }
    /// How the children share the room along the axis: at their natural size, or with the room between them.
    public enum Distribution: String, CaseIterable, Sendable { case natural, spread }
    /// What makes a horizontal stack lay itself out vertically.
    public enum Trigger: String, CaseIterable, Sendable {
        /// The text size is an accessibility size.
        case accessibilitySize = "accessibility-size"
        /// The children that must fit beside each other do not.
        case overflow
    }

    /// One group of a stack's children: the children it holds, by id, laid out along the stack's other axis.
    public struct Group: Equatable, Sendable {
        /// The ids of the children the group holds, in order.
        public var children: [String]
        /// The points between the group's children, or `nil` for the stack's.
        public var spacing: ServerUICompositionDocument.Space?
        /// How the group's children spread along its own axis.
        public var distribution: Distribution
        /// How the group's children line up across its own axis.
        public var align: Align
        /// Whether the group takes the room the others leave.
        public var grow: Bool

        /// Creates a group with the defaults the document gives: natural, start, no growth.
        public init(children: [String], spacing: ServerUICompositionDocument.Space? = nil, distribution: Distribution = .natural, align: Align = .start, grow: Bool = false) {
            self.children = children
            self.spacing = spacing
            self.distribution = distribution
            self.align = align
            self.grow = grow
        }
    }

    /// When and how a horizontal stack lays itself out vertically instead.
    public struct Collapse: Equatable, Sendable {
        /// The reasons the stack collapses, in the order the document lists them.
        public var when: [Trigger]
        /// The children the overflow rule counts, or none to count the ones that cannot shrink.
        public var fits: [String]
        /// The points between groups once collapsed, or `nil` for the stack's.
        public var spacing: ServerUICompositionDocument.Space?
        /// The groups once collapsed, or `nil` to keep the stack's.
        public var groups: [Group]?

        /// Creates a collapse rule.
        public init(when: [Trigger], fits: [String] = [], spacing: ServerUICompositionDocument.Space? = nil, groups: [Group]? = nil) {
            self.when = when
            self.fits = fits
            self.spacing = spacing
            self.groups = groups
        }
    }

    /// A line: its colour and its width in points.
    public struct Line: Equatable, Sendable {
        /// The colour of a line.
        public var ink: ServerUIInk
        /// The thickness of a line, in points.
        public var width: Double

        /// Creates a line.
        public init(ink: ServerUIInk, width: Double) {
            self.ink = ink
            self.width = width
        }
    }

    /// How dense the module surface under a stack is.
    public enum Density: String, CaseIterable, Sendable { case thin, dense }

    /// What the stack sits on.
    public enum Surface: Equatable, Sendable {
        /// The module surface the app draws under a card.
        case module(density: Density)
        /// The stack's own fill with an optional border and radius; no radius is the tile's own.
        case fill(ServerUIInk, border: Line?, radius: Double?)
    }

    /// What an assistive technology makes of the stack.
    public struct Accessibility: Equatable, Sendable {
        /// The element the stack presents.
        public enum Element: String, CaseIterable, Sendable {
            /// One element named by the label (and value and hint).
            case group
            /// The children as they are.
            case children
            /// Nothing: the stack and its children are removed.
            case hidden
        }
        /// The role a group presents.
        public enum Role: String, CaseIterable, Sendable { case button, header, text }

        /// What the stack presents to assistive technology: one group, its children, or nothing.
        public var element: Element
        /// The role a group announces, or `nil` for the one its action gives.
        public var role: Role?
        /// The words VoiceOver reads for a group.
        public var label: ServerUICompositionDocument.StringValue?
        /// The value VoiceOver reads after the label.
        public var value: ServerUICompositionDocument.StringValue?
        /// The hint VoiceOver reads after the value.
        public var hint: String?

        /// Creates the accessibility description of a stack.
        public init(element: Element, role: Role? = nil, label: ServerUICompositionDocument.StringValue? = nil, value: ServerUICompositionDocument.StringValue? = nil, hint: String? = nil) {
            self.element = element
            self.role = role
            self.label = label
            self.value = value
            self.hint = hint
        }
    }

    /// The node's id, title and layout.
    public let node: ServerUICompositionDocument.Node
    /// The axis the groups run along.
    public var axis: Axis
    /// The points between groups.
    public var spacing: ServerUICompositionDocument.Space
    /// The room inside the stack's edge, or `nil` for none.
    public var padding: ServerUICompositionDocument.Insets?
    /// How the groups line up across the stack's axis.
    public var align: Align
    /// How the groups spread along the stack's axis.
    public var distribution: Distribution
    /// The groups the children are partitioned into, or `nil` for each child on its own.
    public var groups: [Group]?
    /// How the stack changes arrangement, or `nil` when it never does.
    public var collapse: Collapse?
    /// The lines between groups, or `nil` for none.
    public var dividers: Line?
    /// What draws under the children, or `nil` for nothing.
    public var surface: Surface?
    /// What a tap runs, or `nil` when the stack is not a button.
    public var action: ServerUICompositionDocument.Action?
    /// The accessibility description, or `nil` for the default.
    public var accessibility: Accessibility?
    /// The children, in document order.
    public var children: [ServerUICompositionDocument.Component]

    /// How many lines the stack draws between groups when `shown` children are shown.
    ///
    /// A line sits between two groups in the row and in the collapsed column, so the larger of the two group counts sizes it; none when the stack has
    /// no `dividers`.
    public func dividerCount(shown: Int) -> Int {
        guard dividers != nil else { return 0 }
        return max(0, max(groups?.count ?? shown, collapse?.groups?.count ?? 0) - 1)
    }

    /// Creates a stack.
    init(node: ServerUICompositionDocument.Node, axis: Axis, spacing: ServerUICompositionDocument.Space, children: [ServerUICompositionDocument.Component]) {
        self.node = node
        self.axis = axis
        self.spacing = spacing
        self.align = .start
        self.distribution = .natural
        self.children = children
    }
}

// MARK: - Shape part (`sh.stack@1`)

/// A plain shape: a capsule, a rectangle or a circle of one colour. It is decoration, so assistive technologies skip it.
public struct ServerUIShapePart: Equatable, Sendable {
    /// The outline.
    public enum Form: String, CaseIterable, Sendable { case capsule, rect, circle }

    /// The node's id, title and layout.
    public let node: ServerUICompositionDocument.Node
    /// The form of the shape.
    public var form: Form
    /// The width, in points.
    public var width: Double
    /// The height, in points.
    public var height: Double
    /// The colour of the shape.
    public var fill: ServerUIInk

    init(node: ServerUICompositionDocument.Node, form: Form, width: Double, height: Double, fill: ServerUIInk) {
        self.node = node
        self.form = form
        self.width = width
        self.height = height
        self.fill = fill
    }
}

// MARK: - Symbol part (`sh.symbol-part@1`)

/// One symbol drawn on its own: a symbol, or one chosen by a rule or an entity's text, with a size that scales with Dynamic Type, a
/// rendering, a tint for a monochrome one, the trim of its leading ink and a turn in degrees.
public struct ServerUISymbolPart: Equatable, Sendable {

    /// The size: points at the default text size, scaled like a text style up to `maxScale` times.
    public struct Size: Equatable, Sendable {
        /// The size, in points, at the default text size.
        public var points: Double
        /// The text size the symbol grows with, or `nil` for a fixed size.
        public var relativeTo: ServerUITextSize?
        /// How many times the size the symbol may grow, or `nil` for no cap.
        public var maxScale: Double?

        /// Creates a size.
        public init(points: Double, relativeTo: ServerUITextSize? = nil, maxScale: Double? = nil) {
            self.points = points
            self.relativeTo = relativeTo
            self.maxScale = maxScale
        }
    }
    /// How the symbol takes colour.
    public enum Rendering: String, CaseIterable, Sendable { case multicolor, monochrome }
    /// Whether the empty space before the symbol's ink is removed so symbols of different widths line up.
    public enum Trim: String, CaseIterable, Sendable { case none, leading }
    /// What an assistive technology makes of the symbol.
    public enum Accessibility: Equatable, Sendable {
        /// Nothing: the symbol is decoration.
        case hidden
        /// An image with this label.
        case image(label: ServerUICompositionDocument.StringValue)
    }

    /// The node's id, title and layout.
    public let node: ServerUICompositionDocument.Node
    /// The symbol drawn when no rule applies: the exact symbol, or the rule's `otherwise` or fallback.
    public var symbol: ServerUICompositionDocument.Symbol
    /// The rule that picks the symbol from state, or `nil` for the exact one.
    public var rule: ServerUIDynamicLook<ServerUICompositionDocument.Symbol>?
    /// The size of the symbol.
    public var size: Size
    /// How the symbol takes its colours.
    public var rendering: Rendering
    /// The colour of a monochrome symbol, or `nil` for the label colour.
    public var tint: ServerUIInk?
    /// Whether the empty space before the glyph is trimmed.
    public var trim: Trim
    /// The turn in degrees, clockwise, as an operand that gives a number.
    public var rotate: ServerUIOperand?
    /// Whether the symbol is an image with a label or hidden from assistive technology.
    public var accessibility: Accessibility

    init(node: ServerUICompositionDocument.Node, symbol: ServerUICompositionDocument.Symbol, size: Size, rendering: Rendering, accessibility: Accessibility) {
        self.node = node
        self.symbol = symbol
        self.size = size
        self.rendering = rendering
        self.trim = .none
        self.accessibility = accessibility
    }
}
