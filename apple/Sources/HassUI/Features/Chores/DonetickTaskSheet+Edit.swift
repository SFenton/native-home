import HassCore
import HassDesign
import SwiftUI

// MARK: - Editing a task

extension DonetickTaskSheet {


}

extension DonetickTaskSheet.Mode {
    var editTarget: DonetickEditTarget? {
        if case let .edit(target) = self { return target }
        return nil
    }
}
