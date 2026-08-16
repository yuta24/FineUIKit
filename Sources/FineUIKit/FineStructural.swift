//
//  FineStructural.swift
//  FineUIKit
//
//  Created by nova on 2026/08/15.
//

import UIKit

/// The identity a builder gives a child that a conditional or a loop produced.
///
/// `path` names the slot in the builder's *static* structure — which block
/// position, which `if`, how deeply nested — and is the same on every render.
/// It never contains a runtime index.
///
/// Exactly one of the other two is set. `user` defers to a `.key(_:)` the
/// description already carries, and `position` places a child that has no key:
/// which loop iteration produced it, and where it sits among its unkeyed
/// siblings in the same slot.
///
/// The split is what lets a key survive a reorder. Folding the loop iteration
/// into `path` would put it *inside* the identity of a keyed child, and moving
/// an item would then change its key even though the key is exactly what was
/// supposed to follow it.
struct FineStructuralKey: Hashable, CustomStringConvertible {
    let path: String
    let position: [Int]?
    let user: AnyHashable?

    var description: String {
        if let user {
            return "\(path)#\(user.base)"
        }
        return "\(path)#\(position?.map(String.init).joined(separator: ".") ?? "")"
    }
}

/// Whether `key` is one the builder made up, rather than one the caller wrote.
///
/// A `.key(_:)` inside a conditional or a loop arrives wrapped in a structural
/// key, so "is it structural" is not the question — "did anyone choose it" is.
/// A duplicate the caller chose is still the caller's mistake, wherever it sits.
func fineIsGeneratedSlot(_ key: AnyHashable) -> Bool {
    guard let structural = key.base as? FineStructuralKey else { return false }
    guard let user = structural.user else { return true }

    // A slot can end up nested inside another when a transparent modifier hides
    // the inner one from the builder — `helper().map { $0.backgroundColor(…) }`
    // wraps the helper's slot in a `FineStyled`, and the outer slot reads the
    // inner key through it as though a caller had chosen it. Asking the same
    // question of that key is what keeps a made-up slot from being reported as
    // the caller's mistake.
    return fineIsGeneratedSlot(user)
}

/// Gives a builder child a slot in the builder's static structure, so its
/// presence cannot decide where its siblings are matched.
///
/// `FineStack` reconciles children with no key by position among themselves.
/// A conditional that produces a child on one render and nothing on the next
/// therefore used to shift every later sibling by one place: the sibling was
/// handed the conditional's old view and — when the two were not compatible —
/// rebuilt, losing first responder status and the node's `FineState` for a
/// change that had nothing to do with it. Two conditionals in one builder had
/// the mirror problem, one adopting the view the other left behind.
///
/// The slot rides on `_key`, which the reconciler and `FineStack` already
/// handle, so nothing else in the runtime learns a new concept. Slotted
/// children are matched by key, which takes them out of the positional list —
/// and that is precisely what leaves their straight-line siblings' positions
/// alone.
///
/// Every branch of one conditional shares a slot on purpose: a description that
/// resolves to a compatible view keeps being updated in place across a branch
/// change, which is the behaviour `FineStack` has always had and which
/// `eitherBranchesUseExistingDiffRules` fixes. That holds for a `switch` and an
/// `else if` chain too, which the compiler expresses as *nested* `buildEither`
/// calls — the reason `FineBuilder` assigns a slot only to a child that does
/// not already have one, rather than nesting a slot inside a slot.
@MainActor
struct FineStructural: FinePrimitiveRenderable {
    /// What kind of structure produced this slot.
    ///
    /// A conditional's slot and a run's slot are wanted for different reasons,
    /// and `FineBuilder.slotted(_:in:)` has to tell them apart: it passes a
    /// branch slot through, because a `switch` reaches it as nested
    /// `buildEither` calls and nesting one slot per level would make the first
    /// case shallower than the rest — but it must *not* pass a run through, or
    /// `if flag { [a] } else { b }` would leave the two branches in different
    /// slots and rebuild the view on every swap.
    enum Kind {
        /// An `if`, an `if-else`, a `switch`.
        case branch
        /// A `for-in` or an array expression.
        case run
    }

    let kind: Kind
    /// The static structure this child came from, outermost first.
    let path: String
    /// Runtime placement within the slot, outermost first: loop iterations, and
    /// last the child's position among the unkeyed children assigned together.
    let position: [Int]
    let content: FineResolvedRenderable

    init(kind: Kind, path: String, position: [Int], content: any Renderable) {
        self.kind = kind
        self.path = path
        self.position = position
        self.content = FineResolvedRenderable(content)
    }

    private init(kind: Kind, path: String, position: [Int], content: FineResolvedRenderable) {
        self.kind = kind
        self.path = path
        self.position = position
        self.content = content
    }

    /// Nests this slot inside an enclosing one. The resolved content is carried
    /// over rather than re-boxed, so nesting costs no extra walk through `body`.
    func prefixed(by component: String) -> FineStructural {
        FineStructural(kind: kind, path: component + "." + path, position: position, content: content)
    }

    /// Records that an enclosing loop produced this child on its `iteration`.
    func positioned(at iteration: Int) -> FineStructural {
        FineStructural(kind: kind, path: path, position: [iteration] + position, content: content)
    }

    func _makeView() -> UIView {
        content.primitive._makeView()
    }

    func _canUpdate(_ view: UIView) -> Bool {
        content.primitive._canUpdate(view)
    }

    func _update(_ view: UIView, context: FineRenderContext) {
        content.primitive._update(view, context: context)
    }

    var _modifierSignature: String {
        content.primitive._modifierSignature
    }

    var _key: AnyHashable? {
        // A key the description carries wins inside the slot: the slot says
        // *where in the source* the child is, the key says *which* child it is.
        // Position is dropped entirely, or a keyed child in a loop would be
        // pinned to the iteration that first produced it.
        //
        // Only a key someone chose, though. A slot that a transparent modifier
        // hid from the builder arrives here looking like one, and deferring to
        // it would drop this slot's position — leaving two children of one
        // array with the same key, which is how they stopped being told apart.
        if let user = content.primitive._key, !fineIsGeneratedSlot(user) {
            return AnyHashable(FineStructuralKey(path: path, position: nil, user: user))
        }

        return AnyHashable(FineStructuralKey(path: path, position: position, user: nil))
    }

    var _viewProvider: any FinePrimitiveRenderable {
        content.primitive._viewProvider
    }

    var _transformSpec: FineTransformSpec? {
        content.primitive._transformSpec
    }
}
