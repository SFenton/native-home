import HassCore
import UIKit
import XCTest
@testable import HassUI

/// Drives a hosted screen like a person: finds the controls that are on screen and uses them (flip a switch, step a stepper, move a
/// slider, pick a segment, press a button), so a test can assert the service calls and the state that follow.
@MainActor
enum HostedDriver {
    /// A tall window so list cells below the fold are built and reachable.
    static let tall = CGSize(width: 393, height: 2400)

    static func isShown(_ view: UIView) -> Bool {
        var node: UIView? = view
        while let current = node {
            if current.isHidden || current.alpha < 0.01 { return false }
            node = current.superview
        }
        return view.window != nil
    }

    /// Enabled, visible controls under `root` in tree order.
    static func controls(in root: UIView) -> [UIControl] {
        HostedPage.descendants(of: root).compactMap { $0 as? UIControl }.filter { $0.isEnabled && isShown($0) }
    }

    static func controls<T: UIControl>(_ type: T.Type, in root: UIView) -> [T] { controls(in: root).compactMap { $0 as? T } }

    /// Uses one control the way a touch would. Returns false for a control with nothing to do (a menu button, a text field).
    @discardableResult
    static func use(_ control: UIControl) -> Bool {
        switch control {
        case let toggle as UISwitch:
            toggle.setOn(!toggle.isOn, animated: false)
            toggle.sendActions(for: .valueChanged)
        case let stepper as UIStepper:
            stepper.value = min(stepper.maximumValue, stepper.value + stepper.stepValue)
            stepper.sendActions(for: .valueChanged)
        case let slider as UISlider:
            slider.value = slider.minimumValue + (slider.maximumValue - slider.minimumValue) * 0.6
            slider.sendActions(for: .valueChanged)
            slider.sendActions(for: .touchUpInside)
        case let segmented as UISegmentedControl:
            guard segmented.numberOfSegments > 1 else { return false }
            segmented.selectedSegmentIndex = (segmented.selectedSegmentIndex + 1) % segmented.numberOfSegments
            segmented.sendActions(for: .valueChanged)
        case let picker as UIDatePicker:
            picker.date = picker.date.addingTimeInterval(3600)
            picker.sendActions(for: .valueChanged)
        case is UITextField:
            return false
        case let button as UIButton where button.showsMenuAsPrimaryAction:
            return false
        default:
            control.sendActions(for: .primaryActionTriggered)
            control.sendActions(for: .touchUpInside)
        }
        return true
    }

    /// Uses every control that is shown now (the list is taken first, so a control that rebuilds the page does not cut it short),
    /// skipping any whose label or identifier contains one of `except` (Close, Done: they end the sheet). Returns how many it used.
    @discardableResult
    static func useAll(in root: UIView, except: [String] = ["close", "done", "dismiss"], settle: TimeInterval = 0.05) -> Int {
        var used = 0
        for control in controls(in: root) {
            let name = ((control.accessibilityLabel ?? "") + " " + (control.accessibilityIdentifier ?? "")).lowercased()
            if except.contains(where: { name.contains($0) }) { continue }
            if use(control) { used += 1 }
            hostedSettle(settle)
        }
        for collection in HostedPage.descendants(of: root).compactMap({ $0 as? UICollectionView }) where isShown(collection) {
            used += selectAll(in: collection, settle: settle)
        }
        return used
    }

    /// The first control whose identifier contains `fragment`.
    static func control(_ fragment: String, in root: UIView) -> UIControl? {
        controls(in: root).first { ($0.accessibilityIdentifier ?? "").contains(fragment) }
    }

    /// Every accessibility identifier under `root`.
    static func identifiers(in root: UIView) -> [String] {
        HostedPage.descendants(of: root).compactMap { $0.accessibilityIdentifier }.filter { !$0.isEmpty }
    }

    /// The topmost presented controller above `root` (or `root`).
    static func topmost(_ root: UIViewController) -> UIViewController {
        var top = root
        while let next = top.presentedViewController { top = next }
        return top
    }

    /// Selects every row of a collection view like a tap on it, in order, calling the delegate (rows with a push or choice action).
    @discardableResult
    static func selectAll(in collection: UICollectionView, settle: TimeInterval = 0.05) -> Int {
        var selected = 0
        for section in 0..<collection.numberOfSections {
            for item in 0..<collection.numberOfItems(inSection: section) {
                let path = IndexPath(item: item, section: section)
                if collection.delegate?.collectionView?(collection, shouldSelectItemAt: path) ?? true {
                    collection.delegate?.collectionView?(collection, didSelectItemAt: path)
                    selected += 1
                    hostedSettle(settle)
                }
            }
        }
        return selected
    }

    /// Picks the `index`th tab of a modal tab bar through whichever control it drew (native segments or badged segments).
    static func pickTab<Item>(_ bar: UKModalTabBar<Item>, _ index: Int) {
        if let segmented = controls(UISegmentedControl.self, in: bar).first {
            segmented.selectedSegmentIndex = index
            segmented.sendActions(for: .valueChanged)
        } else {
            let all = controls(in: bar)
            if index < all.count { all[index].sendActions(for: .touchUpInside) }
        }
        hostedSettle(0.1)
    }
}

/// A caller that logs every call as `domain.service` plus its data, and forwards to an inner responder so the gallery's echo still
/// answers like Home Assistant.
@MainActor
final class LoggingResponder: HassServiceResponding {
    var calls: [String] = []
    var data: [[String: any Sendable]] = []
    private let inner: (any HassServiceCalling)?
    init(_ inner: (any HassServiceCalling)? = nil) { self.inner = inner }
    func callService(_ domain: String, _ service: String, data: [String: any Sendable]) async throws {
        calls.append("\(domain).\(service)")
        self.data.append(data)
        try await inner?.callService(domain, service, data: data)
    }
    func callServiceWithResponse(_ domain: String, _ service: String, data: [String: any Sendable]) async throws -> JSONValue {
        calls.append("\(domain).\(service)")
        self.data.append(data)
        if let responding = inner as? any HassServiceResponding { return try await responding.callServiceWithResponse(domain, service, data: data) }
        return .object(["response": .object(["outcome": "accepted"])])
    }
}
