//
//  Renderable.swift
//  FineUIKit
//
//  Created by nova on 2026/07/05.
//

import UIKit

/// A value that describes a piece of UI.
///
/// A `Renderable` composes built-in components through `body`. `FineRenderer`
/// resolves that composition into primitive descriptions and turns them into
/// `UIView`s, reusing existing views when possible.
@MainActor
public protocol Renderable {
    /// Returns the composed UI description.
    ///
    /// Reconciling a description may evaluate `body` more than once — deciding
    /// whether a view can be reused reads through it, and so does rendering it
    /// — so it must be free of side effects and describe the same UI each time
    /// for the same state. It may of course describe something different after
    /// the state it reads has changed.
    var body: any Renderable { get }
}

/// The description a view is built and updated from.
///
/// `_modifierSignature` and `_key` must be free of side effects, and equivalent
/// across repeated evaluations for the same state: reconciliation may read them
/// more than once, and in no guaranteed order relative to `_canUpdate`,
/// `_makeView` and `_update`. Pass-through primitives resolve their content
/// through `body` to answer them, so the same requirement reaches whatever
/// `Renderable.body` they wrap.
@MainActor
protocol FinePrimitiveRenderable: Renderable {
    func _makeView() -> UIView
    func _canUpdate(_ view: UIView) -> Bool
    func _update(_ view: UIView, context: FineRenderContext)
    var _modifierSignature: String { get }
    var _key: AnyHashable? { get }
    var _viewProvider: any FinePrimitiveRenderable { get }
}

extension FinePrimitiveRenderable {
    var body: any Renderable {
        fatalError("Primitive Renderable body should not be evaluated")
    }

    var _modifierSignature: String {
        ""
    }

    var _key: AnyHashable? {
        nil
    }

    /// The description that makes the view this one renders into: itself, or
    /// for a modifier that renders into its content's view, whatever that
    /// content resolves to.
    ///
    /// Only the debug description reads this. Reconciliation works on the
    /// outermost primitive, because that is what decides reuse — but a reader
    /// looking at a `UILabel` wants the `FineLabel` that made it, not the
    /// `FineStyled` that tinted it. The modifier is not lost: it is what the
    /// reported modifier signature describes.
    var _viewProvider: any FinePrimitiveRenderable {
        self
    }
}
