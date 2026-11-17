#if os(iOS)
import Foundation
import HassCore
import UIKit

// MARK: - Style parts (`sh.stack@1`, `sh.symbol-part@1`)

/// Binds the `stack`, `shape` and `symbol` nodes to their views: what each reads from state, and what a tap on a stack runs.
///
/// The views (``UKStackView``, ``UKShapeView``, ``UKSymbolPartView``) hold values and closures only; every read of an entity happens here, in an
/// observation that touches exactly the entities the node's rules name, so one entity change is one update of the view that reads it. A value
/// that is still loading keeps what the view showed.
@MainActor
enum UKServerUIStyleParts {
    typealias D = ServerUICompositionDocument

    /// The words of a text slot, or `fallback` while it has none.
    private static func words(_ slot: D.StringValue?, in renderer: UKServerUIRenderer, fallback: String?) -> String? {
        guard let slot else { return fallback }
        if case .ready(let text) = renderer.bindings.string(slot), !text.trimmingCharacters(in: .whitespaces).isEmpty { return text }
        return fallback
    }

    /// Draws a stack around the children that are shown, with the accessibility words its slots give now.
    static func apply(_ stack: ServerUIStack, to view: UKStackView, children: [(D.Component, UIView)], page: UKServerUIPage,
                      renderer: UKServerUIRenderer) {
        let shown = children.filter { renderer.componentVisible($0.0) }.map { UKStackView.Member(id: $0.0.node.id, view: $0.1) }
        let label = words(stack.accessibility?.label, in: renderer, fallback: stack.node.title)
        let value = words(stack.accessibility?.value, in: renderer, fallback: nil)
        let enabled = stack.action.map { renderer.isEnabled($0, from: page) && renderer.isEnabled(node: stack.node) } ?? false
        view.onActivate = { [weak page, weak view] in
            guard let page, let action = stack.action else { return }
            page.renderer?.activate(action, from: page, source: view)
        }
        view.apply(stack, members: shown, label: label, spokenValue: value, isEnabled: enabled)
    }

    /// Binds a symbol part: the symbol its rule picks from state (the last one while the rule loads), its turn and its label.
    static func bind(_ part: ServerUISymbolPart, view: UKSymbolPartView, entry: UKServerUINode, renderer: UKServerUIRenderer) {
        var shown: D.Symbol?
        entry.bag.observe { [weak view, weak renderer] in
            guard let view, let renderer else { return }
            let reader = renderer.reader()
            var symbol = part.symbol
            if let rule = part.rule {
                switch rule.resolve(base: part.symbol, in: reader) {
                case .value(let value): symbol = value
                case .loading: symbol = shown ?? part.symbol
                }
            }
            shown = symbol
            var label: String?
            if case .image(let slot) = part.accessibility { label = words(slot, in: renderer, fallback: part.node.title) }
            view.apply(part, label: label)
            view.show(name: ServerUISymbolFallback.resolve(symbol.name))
            if let rotate = part.rotate, case .value(.number(let degrees)) = rotate.evaluate(reader) { view.turn(by: degrees) }
            else if part.rotate != nil { view.turn(by: 0) }
        }
    }
}

// MARK: - Fitting views in a stack

/// A button, a row or a section inside a stack: its natural width is the width it takes compressed, not the unbounded width `sizeThatFits` gives.
extension UKServerUIFittingView: UKStackMeasuring {
    var stackNaturalWidth: CGFloat {
        ceil(systemLayoutSizeFitting(CGSize(width: UIView.layoutFittingCompressedSize.width, height: UIView.layoutFittingCompressedSize.height),
                                     withHorizontalFittingPriority: .fittingSizeLevel, verticalFittingPriority: .fittingSizeLevel).width)
    }
    var stackFillsWidth: Bool { true }
    var stackShrinks: Bool { false }
}
#endif
