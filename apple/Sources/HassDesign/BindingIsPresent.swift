import SwiftUI

public extension Binding {
    /// A `Bool` binding that is true while the optional is non-nil and clears it when set to false.
    ///
    /// The one place a presenter's `isPresented:` is derived from an optional, so views do not hand-build
    /// `Binding(get:set:)` in their bodies. Prefer `sheet(item:)` and `alert(item:)` where the item itself is shown.
    func isPresent<Wrapped>() -> Binding<Bool> where Value == Wrapped? {
        Binding<Bool>(
            get: { wrappedValue != nil },
            set: { if !$0 { wrappedValue = nil } }
        )
    }
}

public extension Binding where Value: SetAlgebra, Value.Element: Hashable {
    /// A `Bool` binding that is true while the set holds `element`; setting it inserts or removes the element.
    ///
    /// For a toggle per member (a weekday, a bed), so a view does not hand-build `Binding(get:set:)` over the set.
    func contains(_ element: Value.Element) -> Binding<Bool> {
        Binding<Bool>(
            get: { wrappedValue.contains(element) },
            set: { if $0 { wrappedValue.insert(element) } else { wrappedValue.remove(element) } }
        )
    }
}

public extension Binding {
    /// A binding to another representation of the same stored value: `read` projects it for display and `write` folds an
    /// edit back into the stored value (an `HH:MM` string as a `Date`, a text field with a length limit).
    ///
    /// Declared where the conversion is a named property of the model or view, not inline in a body.
    func projected<Projection>(read: @escaping (Value) -> Projection,
                               write: @escaping (Value, Projection) -> Value) -> Binding<Projection> {
        Binding<Projection>(get: { read(wrappedValue) }, set: { wrappedValue = write(wrappedValue, $0) })
    }
}
