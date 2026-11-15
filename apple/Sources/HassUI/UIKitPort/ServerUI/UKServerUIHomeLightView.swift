#if os(iOS)
import HassCore
import UIKit

// MARK: - Canonical light tile binding

/// Keeps the existing brightness/power control and pins its configured source during service work.
@MainActor
final class UKServerUIHomeLightView: UIView, UKGridMeasuring {
    private let bag = UKObservationBag()
    private var tile: UKLightGroupTileView?
    private var attachment: ServerUICompositionDocument.HomeLightTile?
    private var boundEntityId: String?
    private let message = UILabel.uk(.subheadline, ink: UKDesignInk.primary)

    var sourceID: String? { attachment?.sourceId }
    var hasActiveInteraction: Bool {
        var focused = UIAccessibility.focusedElement(using: nil)
        while let element = focused as? UIAccessibilityElement { focused = element.accessibilityContainer }
        let ownsFocus = (focused as? UIView).map { $0 === self || $0.isDescendant(of: self) } ?? false
        func focusedOrTracking(_ view: UIView) -> Bool {
            view.isFirstResponder || view.accessibilityElementIsFocused() || (view as? UIControl)?.isTracking == true
                || view.subviews.contains(where: focusedOrTracking)
        }
        return ownsFocus || tile?.hasActiveInteraction == true || focusedOrTracking(self)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        message.text = "Unavailable"
        addSubview(message)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func bind(_ definition: ServerUICompositionDocument.HomeLightTile, bindings: UKServerUIBindings, context: UKContext,
              onError: @escaping (UKServerUIRendererError) -> Void) {
        guard let entityId = bindings.entityID(for: definition.sourceId).value else {
            onError(.init(code: .unavailableSource, pointer: "/document/dataSources"))
            return
        }
        if attachment != definition || boundEntityId != entityId {
            tile?.removeFromSuperview()
            let tile = UKLightGroupTileView(title: definition.node.title, entityId: entityId, identifier: definition.node.id,
                                            environment: UKTileEnvironment(context: context)) { command in
                do {
                    guard let model = bindings.lights[definition.sourceId] else { throw ServerUIHomeLightSource.Failure.unavailable }
                    try model.perform(command)
                } catch {
                    onError(.init(code: .unavailableSource, pointer: "/document/dataSources"))
                }
            }
            addSubview(tile)
            self.tile = tile
            attachment = definition
            boundEntityId = entityId
            message.isHidden = true
        }
        bag.removeAll()
        bag.observe { [weak self] in
            let source = bindings.lights[definition.sourceId]
            // No caller is an explicitly unavailable control, not a local-only successful toggle.
            self?.tile?.update(state: context.valuesPending || source == nil ? nil : source?.shown, isFailed: source?.isFailed == true)
            self?.ukRemeasureContainers(includingSelf: true)
        }
    }

    func gridHeight(forWidth width: CGFloat) -> CGFloat { tile?.gridHeight(forWidth: width) ?? message.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height }
    override func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: size.width, height: gridHeight(forWidth: size.width)) }
    override func layoutSubviews() { super.layoutSubviews(); tile?.frame = bounds; message.frame = bounds }
}
#endif
