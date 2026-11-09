#if os(iOS)
import HassDesign
import UIKit

/// The bar buttons of sheets (`SheetCloseItem`, `SheetCancelItem`, `SheetConfirmItem`, `SheetBackItem`) as `UIBarButtonItem`s,
/// with the SwiftUI identifiers, labels and discard guard.
///
/// A viewing sheet carries Close, trailing (an x in a glass circle on iOS 26, an `xmark` earlier). A create or edit sheet
/// carries Cancel leading and Confirm trailing (a checkmark on the filled `#0071E3` action fill), disabled until there is
/// something to confirm (``SheetEditState``).
///
/// ```swift
/// page.navigationItem.leftBarButtonItem = UKSheetItems.cancel(hasChanges: draft.hasChanges, presenter: page) { dismiss() }
/// let confirm = UKSheetConfirmItem("Save") { save() }
/// page.navigationItem.rightBarButtonItem = confirm.barButtonItem
/// confirm.update(isEnabled: SheetEditState.canConfirm(isValid: …, hasChanges: …))
/// ```
@MainActor
enum UKSheetItems {
    /// The Close button every viewing sheet carries.
    /// - Parameters:
    ///   - identifier: Accessibility identifier; sheets keep their existing one so journeys stay stable.
    ///   - hasChanges: The page holds an edited draft: Close asks "Discard changes?" first (needs `presenter`).
    ///   - isEnabled: Off while the sheet must stay (a sign-out waiting on the server).
    static func close(identifier: String = "sheet.close", hasChanges: Bool = false, isEnabled: Bool = true,
                      presenter: UIViewController? = nil, action: @escaping () -> Void) -> UIBarButtonItem {
        let item = glyphItem(label: "Close", identifier: identifier, ios26: .close, fallbackSymbol: "xmark", hasChanges: hasChanges, presenter: presenter, action: action)
        item.isEnabled = isEnabled
        return item
    }

    /// The leading Cancel of a create or edit sheet: drops the draft.
    static func cancel(identifier: String = "sheet.cancel", isEnabled: Bool = true, hasChanges: Bool = false,
                       presenter: UIViewController? = nil, action: @escaping () -> Void) -> UIBarButtonItem {
        let item = glyphItem(label: "Cancel", identifier: identifier, ios26: .close, fallbackSymbol: "xmark", hasChanges: hasChanges, presenter: presenter, action: action)
        item.isEnabled = isEnabled
        return item
    }

    /// The leading Back of a pushed form page that asks before dropping its draft. Also set `hidesBackButton` on the page
    /// (``UKHassModal/hidesSystemBack(_:)``): the system Back and its edge swipe would bypass the guard.
    static func back(identifier: String = "sheet.back", hasChanges: Bool, isEnabled: Bool = true,
                     presenter: UIViewController, action: @escaping () -> Void) -> UIBarButtonItem {
        let item = UIBarButtonItem(image: UIImage(systemName: "chevron.backward"), style: .plain, target: nil, action: nil)
        item.title = "Back"
        item.accessibilityLabel = "Back"
        item.accessibilityIdentifier = identifier
        item.isEnabled = isEnabled
        item.primaryAction = UIAction(image: UIImage(systemName: "chevron.backward")) { [weak presenter] tapped in
            guard let presenter else { return }
            UKDiscardGuard.leave(from: presenter, source: (tapped.sender as? UIBarButtonItem).map(UKPopoverSource.barButton) ?? .none, hasChanges: hasChanges, leave: action)
        }
        return item
    }

    private static func glyphItem(label: String, identifier: String, ios26: UIBarButtonItem.SystemItem, fallbackSymbol: String,
                                  hasChanges: Bool, presenter: UIViewController?, action: @escaping () -> Void) -> UIBarButtonItem {
        let item: UIBarButtonItem
        let handler = UIAction { [weak presenter] tapped in
            if hasChanges, let presenter {
                UKDiscardGuard.leave(from: presenter, source: (tapped.sender as? UIBarButtonItem).map(UKPopoverSource.barButton) ?? .none, hasChanges: true, leave: action)
            } else {
                action()
            }
        }
        if #available(iOS 26.0, *) {
            item = UIBarButtonItem(systemItem: ios26, primaryAction: handler)
        } else {
            item = UIBarButtonItem(image: UIImage(systemName: fallbackSymbol), primaryAction: handler)
        }
        item.title = label
        item.accessibilityLabel = label
        item.accessibilityIdentifier = identifier
        return item
    }
}

/// The trailing confirm on a create or edit sheet (`SheetConfirmItem`): a checkmark on G's filled `#0071E3` circle, dimmed and
/// unpressable until there is something to confirm. While the save is in flight it shows an inline arc and is spoken as the
/// action in progress ("Saving").
@MainActor
final class UKSheetConfirmItem {
    let barButtonItem: UIBarButtonItem
    private let title: String
    private let busyTitle: String?
    private let action: () -> Void
    private var isBusy = false
    private var isEnabled: Bool

    /// - Parameters:
    ///   - title: What the check does, spoken by VoiceOver: "Save", "Add", "Create" or "Apply".
    ///   - busyTitle: Spoken while busy ("Saving"); defaults to the title.
    ///   - identifier: Accessibility identifier; default `sheet.confirm`.
    init(_ title: String, isEnabled: Bool = true, busyTitle: String? = nil, identifier: String = "sheet.confirm", action: @escaping () -> Void) {
        self.title = title
        self.busyTitle = busyTitle
        self.action = action
        self.isEnabled = isEnabled
        let handler = UIAction { _ in action() }
        let item: UIBarButtonItem
        if #available(iOS 26.0, *) {
            item = UIBarButtonItem(image: UIImage(systemName: "checkmark"), style: .prominent, target: nil, action: nil)
            item.primaryAction = UIAction(image: UIImage(systemName: "checkmark")) { _ in action() }
            item.tintColor = UKDesignInk.actionFill
        } else {
            let button = UIButton(type: .system)
            button.setImage(UIImage(systemName: "checkmark", withConfiguration: UIImage.SymbolConfiguration(font: .ukFont(.body, weight: .semibold))), for: .normal)
            button.tintColor = .white
            button.backgroundColor = UKDesignInk.actionFill
            button.layer.cornerRadius = 15
            button.frame = CGRect(x: 0, y: 0, width: 30, height: 30)
            button.addAction(handler, for: .touchUpInside)
            item = UIBarButtonItem(customView: button)
            item.menuRepresentation = UIAction(title: title, image: UIImage(systemName: "checkmark")) { _ in action() }
        }
        item.title = title
        item.accessibilityLabel = title
        item.accessibilityIdentifier = identifier
        barButtonItem = item
        update(isEnabled: isEnabled)
    }

    /// Enables the check (``SheetEditState/canConfirm(isValid:hasChanges:isBusy:)``) and/or shows the busy arc.
    func update(isEnabled: Bool, isBusy: Bool = false) {
        let wasBusy = self.isBusy
        self.isEnabled = isEnabled
        self.isBusy = isBusy
        if isBusy {
            if !wasBusy {
                let spinner = UKArcSpinnerView(.inline, label: busyTitle ?? title)
                spinner.color = .white
                spinner.backgroundColor = UKDesignInk.actionFill
                spinner.translatesAutoresizingMaskIntoConstraints = false
                let holder = UIView(frame: CGRect(x: 0, y: 0, width: 28, height: 28))
                holder.backgroundColor = UKDesignInk.actionFill
                holder.layer.cornerRadius = 14
                holder.addSubview(spinner)
                spinner.backgroundColor = .clear
                NSLayoutConstraint.activate([spinner.centerXAnchor.constraint(equalTo: holder.centerXAnchor), spinner.centerYAnchor.constraint(equalTo: holder.centerYAnchor)])
                holder.isAccessibilityElement = true
                holder.accessibilityLabel = busyTitle ?? title
                barButtonItem.customView = holder
                // The busy item is disabled and not interactive, so VoiceOver may skip it: say it once.
                Announcer.announce(busyTitle ?? title)
            }
            barButtonItem.isEnabled = false
        } else {
            barButtonItem.isEnabled = isEnabled
            if wasBusy { barButtonItem.customView = nil }
        }
    }
}

/// The one-line subtitle under a sheet's centred title (`sheetSubtitle(_:)`): "3 of 12 On" under Lights. iOS 26 and later draw
/// the system navigation subtitle; earlier systems show the title alone. Check ``SheetSubtitle/isShown`` where the subtitle
/// carries a figure the sheet shows nowhere else.
enum UKSheetSubtitle {
    @MainActor
    static func apply(_ subtitle: String?, to navigationItem: UINavigationItem) {
        if #available(iOS 26.0, *) {
            navigationItem.subtitle = subtitle?.isEmpty == false ? subtitle : nil
        }
    }
}
#endif
