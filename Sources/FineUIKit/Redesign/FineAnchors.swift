//
//  FineAnchors.swift
//  FineUIKit
//
//  Part of the ground-up redesign (see redesign/positioning-and-rebuild).
//  A one-time constraint-activation helper for initial view construction.
//  Deliberately NOT a reconciled layout description: it activates
//  NSLayoutConstraints once and hands the caller the constraints it made, so
//  later constant changes go through the caller's own stored reference
//  (typically via `fineAssign`) instead of a framework-owned diffing pass.

import UIKit

@MainActor
public struct FineAnchorProxy {
    public let view: UIView
    fileprivate var constraints: [NSLayoutConstraint] = []

    /// Adds a constraint to be activated. Does not activate it itself, so
    /// callers can freely inspect/reorder before `fineAnchors` activates the
    /// whole batch together.
    public mutating func pin(_ constraint: NSLayoutConstraint) {
        constraints.append(constraint)
    }

    /// Pins all four edges to `view.superview`. Asserts if the view has not
    /// been added to a superview yet.
    public mutating func pinToSuperview(insets: NSDirectionalEdgeInsets = .zero) {
        guard let superview = view.superview else {
            assertionFailure("fineAnchors: pinToSuperview requires the view to already have a superview")
            return
        }

        pin(view.topAnchor.constraint(equalTo: superview.topAnchor, constant: insets.top))
        pin(view.leadingAnchor.constraint(equalTo: superview.leadingAnchor, constant: insets.leading))
        pin(superview.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: insets.trailing))
        pin(superview.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: insets.bottom))
    }
}

public extension UIView {
    /// Builds and activates a batch of constraints for this view exactly
    /// once. Sets `translatesAutoresizingMaskIntoConstraints = false`.
    ///
    /// Returns the activated constraints so the caller can hold onto the
    /// ones it will later update (e.g. inside a ``BindingScope/observe(_:)``
    /// closure via ``fineAssign(_:_:_:)`` on `.constant`). There is no
    /// signature/identity tracking here -- calling this again on the same
    /// view activates a second, independent batch.
    @discardableResult
    @MainActor
    func fineAnchors(_ build: (inout FineAnchorProxy) -> Void) -> [NSLayoutConstraint] {
        translatesAutoresizingMaskIntoConstraints = false

        var proxy = FineAnchorProxy(view: self)
        build(&proxy)
        NSLayoutConstraint.activate(proxy.constraints)
        return proxy.constraints
    }
}
