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
///
/// Conform to it to split a long description into named pieces. A struct suits
/// it: the type takes what it needs as properties and returns a description,
/// and lives for one render.
///
/// ```swift
/// struct ToDoRow: Renderable {
///     let item: ToDo
///     let onToggle: @MainActor () -> Void
///
///     var body: any Renderable {
///         FineStack.horizontal(spacing: 8) {
///             FineButton(title: self.item.isDone ? "☑" : "☐") { self.onToggle() }
///             FineLabel(text: self.item.title)
///         }
///     }
/// }
/// ```
///
/// Code injection replaces this `body` like any other symbol, so splitting a
/// description up costs no hot reload.
///
/// Two things to know about what the runtime does with the split:
///
/// - **The type is part of the view's identity.** Resolution walks `body` to a
///   primitive, and the types it passed through go into the modifier
///   signature — so swapping one `Renderable` for another rebuilds the view,
///   and the node's `FineState` with it, even when both resolve to the same
///   primitive.
/// - **Observation is not narrowed by the split.** This `body` runs where the
///   description is resolved, so an observable read here belongs to whatever
///   scope did the resolving — a container's node, or the root — and a change
///   re-runs that scope, not this type alone. To scope a read to one node,
///   read it inside a component that takes its value as an `@autoclosure`
///   (`FineLabel(text:)`) or inside a container's builder. Taking values as
///   properties, as above, sidesteps the question: the read then happens at
///   the call site.
///
/// State and methods belong to nested content — an `@Observable` class the
/// parent holds — not here.
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
    var _transformSpec: FineTransformSpec? { get }
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

    /// The transform this description asks of the view it renders into, if any.
    ///
    /// Read rather than applied by whoever finally writes it, because `.scale`
    /// and `.offset` are two asks about one `UIView.transform` and can be
    /// written far apart — with a `.backgroundColor` between them, or a
    /// `.key(_:)`. Each would otherwise assign the property and the last one
    /// would win, quietly dropping the others.
    ///
    /// Transparent wrappers pass their content's answer through, the same way
    /// they do for `_viewProvider`. A wrapper that makes a view of its own does
    /// not: the transform belongs to the view the description names, not to a
    /// container put around it.
    var _transformSpec: FineTransformSpec? {
        nil
    }
}
