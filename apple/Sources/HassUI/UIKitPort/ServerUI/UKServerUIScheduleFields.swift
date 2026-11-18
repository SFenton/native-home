#if os(iOS)
import HassCore
import HassDesign
import UIKit

// MARK: - Draft-owned schedule fields

/// Epoch seconds are values in the retained form, not immediate service calls from a date picker.
@MainActor
final class UKServerUIScheduleFields: UKServerUIFittingView {
    private var native: UKScheduleDateFields?
    private var keys: [String] = []

    func apply(_ values: [ServerUIFormValue], enabled: Bool, change: @escaping (String, Double) -> Void) throws {
        let fields = try values.map { value -> ScheduleDateField in
            guard value.control == .scheduleDateTime, value.isValidDescriptor,
                  case .number(let seconds) = value.value,
                  case .number(let minimum, let maximum, _) = value.rule else { throw ServerUIRecordFailure.invalidField }
            return ScheduleDateField(label: value.label, part: .dateAndTime, value: Date(timeIntervalSince1970: seconds),
                identifier: value.key) { date in change(value.key, date.timeIntervalSince1970.rounded()) }
                .limited(from: Date(timeIntervalSince1970: minimum), to: Date(timeIntervalSince1970: maximum))
        }
        let next = values.map(\.key)
        if native == nil || keys != next {
            keys = next
            native?.removeFromSuperview()
            let native = UKScheduleDateFields(fields: fields)
            self.native = native
            addSubview(native); native.ukPin(to: self)
            ukRemeasureContainers(includingSelf: true)
        }
        native?.update(fields: fields, enabled: values.map { enabled && $0.enabled })
    }

    override func gridHeight(forWidth width: CGFloat) -> CGFloat {
        native?.bounds.size.width = width
        native?.setNeedsLayout()
        native?.layoutIfNeeded()
        return super.gridHeight(forWidth: width)
    }
}
#endif
