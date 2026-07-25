//
//  FineEquality.swift
//  FineUIKit
//
//  Created by nova on 2026/07/25.
//

/// Compares two values whose static types are not known to be `Equatable`.
///
/// Returns `nil` when equality cannot be decided — the dynamic type does not
/// conform to `Equatable`, or the two values have different types — so callers
/// pick their own conservative fallback.
func fineDynamicEquals(_ lhs: Any, _ rhs: Any) -> Bool? {
    guard let lhs = lhs as? any Equatable else { return nil }
    return lhs.fineIsEqual(to: rhs)
}

/// Whether `value` is a class instance.
///
/// Equality cannot detect changes to a mutated reference: both sides of the
/// comparison are the same instance, so any `==` reports them equal. Callers
/// that compare a previous value against a current one use this to stay
/// conservative. `type(of:)` is checked instead of `is AnyObject`, which is also
/// true for bridgeable value types.
func fineIsReference(_ value: Any) -> Bool {
    type(of: value) is AnyClass
}

extension Equatable {
    /// Compares against `other` when it has the same concrete type.
    func fineIsEqual(to other: Any) -> Bool {
        guard let other = other as? Self else { return false }
        return self == other
    }
}
