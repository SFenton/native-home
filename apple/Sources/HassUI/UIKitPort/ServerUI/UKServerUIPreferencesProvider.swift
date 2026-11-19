#if os(iOS)
import HassCore
import HassDesign
import Observation
import UIKit

// MARK: - Device preferences

/// Reuses the backdrop preference, signed icon catalog and version model. Tests inject isolated stores.
@MainActor
@Observable
final class UKServerUIPreferencesProvider: UKServerUISettingsProvider {
    let definition: ServerUISettingsSource
    private(set) var blur: BackdropBlurSettings
    let icons: AppIconPickerModel
    let about: AboutSettingsModel
    private let defaults: UserDefaults
    private let current: () -> Bool
    private let blurChanged: (Int) -> Void
    var isCurrentSession: Bool { current() }
    var protectsPublication: Bool { icons.isChanging || icons.failureMessage != nil }

    init(id: String, blur: BackdropBlurSettings, icons: AppIconPickerModel, about: AboutSettingsModel,
         defaults: UserDefaults, isCurrentSession: @escaping () -> Bool,
         blurChanged: @escaping (Int) -> Void = { _ in }) {
        definition = .init(providerId: id, domain: .preferences)
        self.blur = blur
        self.icons = icons
        self.about = about
        self.defaults = defaults
        current = isCurrentSession
        self.blurChanged = blurChanged
    }

    /// Commit-time rebinding preserves the visible store's render callback throughout preparation.
    func adoptBlur(_ blur: BackdropBlurSettings) { self.blur = blur }

    func setBlur(_ percent: Int) throws {
        try requireCurrent()
        blur.set(percent)
        defaults.set(blur.percent, forKey: BackdropBlur.defaultsKey)
        blurChanged(blur.percent)
    }

    func accepts(_ control: ServerUISettingsControl) -> Bool {
        control.kind.domain == .preferences && (control.kind != .iconChoice || AppIconChoice(rawValue: control.item) != nil)
    }

    func make(_ control: ServerUISettingsControl, host: UKServerUISettingsAtom, page: UKServerUIPage) throws -> UIView {
        guard accepts(control) else { throw UKServerUIRendererError(code: .unavailableSource, pointer: "/document/dataSources") }
        switch control.kind {
        case .blur:
            host.settingsKind = .control
            // The slider row already pads its body 4 pt below (the form row's own padding), so the outer bottom gives that back: 10.5 pt in all.
            var insets = UKSettingsRowKind.control.contentInsets
            insets.bottom -= HassTokens.Spacing.xs
            let slider = UKPercentSliderRow(control.node.title, value: blur.sliderValue, identifier: control.node.id, insets: insets) { [weak self, weak host, weak page] value in
                guard let self, let host, let page else { return }
                host.perform(from: page) { try self.setBlur(Int(value.rounded())) }
            }
            host.bag.observe { [weak self, weak slider] in
                if let self { slider?.value = self.blur.sliderValue }
            }
            return slider
        case .badge:
            let toggle = UISwitch()
            toggle.isOn = defaults.object(forKey: AppIconBadgeSync.enabledKey) as? Bool ?? true
            toggle.accessibilityLabel = control.node.title
            toggle.accessibilityIdentifier = control.node.id
            toggle.addAction(UIAction { [weak self, weak host, weak page, weak toggle] _ in
                guard let self, let host, let page, let toggle else { return }
                host.perform(from: page) {
                    try self.requireCurrent()
                    self.defaults.set(toggle.isOn, forKey: AppIconBadgeSync.enabledKey)
                }
            }, for: .valueChanged)
            host.settingsKind = .control
            var content = UKRowContent(control.node.title, subtitle: control.subtitle, style: .form)
            content.outerInsets = UKSettingsRowKind.control.contentInsets
            return UKRowView(content, accessory: toggle)
        case .iconChoice:
            guard let choice = AppIconChoice(rawValue: control.item) else {
                throw UKServerUIRendererError(code: .unavailableSource, pointer: "/document/dataSources")
            }
            let art = UKAppIconPreviewView(choice: choice, side: 64)
            art.widthAnchor.constraint(equalToConstant: 64).isActive = true
            art.heightAnchor.constraint(equalToConstant: 64).isActive = true
            let row = UKRowButton(UKRowView(.init(control.node.title, subtitle: control.subtitle), accessory: art))
            row.onTap = { [weak self, weak host, weak page] in
                guard let self, let host, let page else { return }
                host.perform(from: page) {
                    try self.requireCurrent()
                    guard self.icons.isSupported else { throw HouseholdSettingsTarget.Failure.unavailable }
                    Task { [self] in
                        await icons.select(choice)
                        if let failure = icons.failureMessage, page.presentedViewController == nil {
                            let alert = UIAlertController(title: "Couldn't Change Icon", message: failure, preferredStyle: .alert)
                            alert.addAction(UIAlertAction(title: "OK", style: .cancel) { [weak self] _ in self?.icons.failureMessage = nil })
                            page.present(alert, animated: true)
                        }
                    }
                }
            }
            host.bag.observe { [weak self, weak row] in
                guard let self, let row else { return }
                row.isEnabled = self.isCurrentSession && self.icons.isSupported && !self.icons.isChanging
                row.accessibilityTraits = self.icons.isSelected(choice) ? [.button, .selected] : .button
                row.accessibilityValue = self.icons.isChanging ? "Changing Icon" : self.icons.isSelected(choice) ? "Selected" : ""
            }
            return row
        default:
            // Reset is a text button and Version the canonical Version row: neither pushes, so neither draws a chevron, and the node's
            // authored icon is ignored.
            let row = UKServerUIPreferenceRow(title: control.node.title, kind: control.kind == .version ? .value : .textButton,
                                              identifier: control.node.id)
            host.settingsKind = row.settingsRowKind
            row.onTap = { [weak self, weak host, weak page] in
                guard let self, let host, let page else { return }
                host.perform(from: page) {
                    try self.requireCurrent()
                    if control.kind == .resetBlur {
                        try self.setBlur(BackdropBlur.defaultPercent)
                    } else {
                        self.about.copy()
                        UKTapFeedback.confirmation()
                    }
                }
            }
            host.bag.observe { [weak self, weak row, weak host] in
                guard let self, let row else { return }
                row.value = control.kind == .version ? self.about.text : ""
                row.spokenValue = control.kind == .version ? self.about.spokenText : nil
                row.hint = control.kind == .version ? AboutSettingsModel.copyHint : control.subtitle
                row.isEnabled = self.isCurrentSession && (control.kind != .resetBlur || !self.blur.isDefault)
                host?.ukRemeasureContainers(includingSelf: true)
            }
            return row
        }
    }
}
#endif
