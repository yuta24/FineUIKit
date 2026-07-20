//
//  FineAssign.swift
//  FineUIKit
//
//  Part of the ground-up redesign (see redesign/positioning-and-rebuild).

/// Writes `new` through `write` only when it differs from `current`.
///
/// This is the single shared helper for the "write only if different" guard
/// that every ``BindingScope/observe(_:)`` closure needs (re-running on an
/// unrelated change must not re-touch a UIKit property whose setter can be
/// expensive or disruptive -- e.g. resetting a UITextField's cursor).
/// Deliberately the only such helper: bindings do not get a second,
/// competing way to skip redundant writes.
@MainActor
public func fineAssign<Value: Equatable>(
    _ current: @autoclosure () -> Value,
    _ new: Value,
    _ write: (Value) -> Void
) {
    guard current() != new else { return }
    write(new)
}
