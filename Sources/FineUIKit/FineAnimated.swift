//
//  FineAnimated.swift
//  FineUIKit
//
//  Created by nova on 2026/08/16.
//

import UIKit

/// Declares that changes to what it wraps are animated, and leaves the
/// animating to UIKit.
///
/// `withFineAnimation` says it at the other end — at the mutation, for whatever
/// the change turns out to touch. This says it at the description, for one
/// subtree, and holds whatever changes it: a value the view model wrote, a
/// trait, an injected implementation.
///
/// What actually animates is UIKit's business. The update is performed inside
/// `UIView.animate`, so the properties UIKit animates do and the rest — text,
/// an image, a subview appearing — take effect at once, which is the behaviour
/// wanted anyway.
///
/// The first update a view receives is never animated. There is no previous
/// value to come from, and animating out of a default would show a fade or a
/// slide nobody described.
@MainActor
struct FineAnimated: FinePrimitiveRenderable {
    let content: FineResolvedRenderable
    /// `nil` turns animation off for the subtree, the way
    /// `withFineAnimation(nil)` does for a mutation.
    let animation: FineAnimation?

    init(content: any Renderable, animation: FineAnimation?) {
        self.content = FineResolvedRenderable(content)
        self.animation = animation
    }

    init(content: FineResolvedRenderable, animation: FineAnimation?) {
        self.content = content
        self.animation = animation
    }

    func _makeView() -> UIView {
        content.primitive._makeView()
    }

    func _canUpdate(_ view: UIView) -> Bool {
        content.primitive._canUpdate(view)
    }

    func _update(_ view: UIView, context: FineRenderContext) {
        let declared = Self.resolved(animation, at: view)
        // Handed down so descendants animate too. Their updates are separate
        // jobs the scheduler runs after this one returns, which is why a block
        // opened here could never have reached them.
        let childContext = context.withAnimation(declared)

        Self.performing(declared, on: view) {
            // Also set for the synchronous extent, so a list applying its diff
            // inside this update follows the same curve rather than whatever
            // the mutation site happened to say.
            FineTransactionContext.$current.withValue(declared ?? FineTransactionContext.current) {
                content.primitive._update(view, context: childContext)
            }
        }
    }

    /// What this node should actually do, given what it asked for and what is
    /// already in force.
    ///
    /// An enclosing `withFineAnimation(nil)` and the catch-up render after
    /// `resume()` both mean *not now* — the first because the caller said so,
    /// the second because animating changes that happened off screen would
    /// slide in things the viewer never saw leave. A description asking to
    /// animate does not get to overrule either.
    static func resolved(_ animation: FineAnimation?, at view: UIView) -> FineTransactionValue {
        let node = view.fineNode
        // Nothing to animate from, and nowhere to show it: a view still being
        // built holds only defaults, and one outside a window has no viewer.
        let hasSomethingToAnimateFrom = node.hasBeenUpdated && view.window != nil
        // Recorded before anything can return, because an update that was not
        // animated is still an update. A view that first appears during a
        // catch-up is written to with animation off, and if that did not count
        // it would go on believing it had never been written to — leaving the
        // next change, the first one anybody watches, to arrive as a first
        // render with no animation at all.
        node.hasBeenUpdated = true

        if case .disabled = FineTransactionContext.current {
            return .disabled
        }

        guard let animation, hasSomethingToAnimateFrom else { return .disabled }
        return .animate(animation)
    }

    /// Runs `update` under `animation`, which for `.disabled` means telling
    /// UIKit so rather than saying nothing: an enclosing block is already open,
    /// and a write made inside it animates whether this subtree wanted it or
    /// not.
    static func performing(
        _ animation: FineTransactionValue?,
        on view: UIView,
        _ update: @MainActor @escaping () -> Void
    ) {
        switch animation {
        case .animate(let animation):
            animation.animate {
                update()
                view.layoutIfNeeded()
            }
        case .disabled:
            UIView.performWithoutAnimation(update)
        case nil:
            update()
        }
    }

    var _modifierSignature: String {
        content.primitive._modifierSignature + "|animation"
    }

    var _key: AnyHashable? {
        content.primitive._key
    }

    var _viewProvider: any FinePrimitiveRenderable {
        content.primitive._viewProvider
    }

    var _transformSpec: FineTransformSpec? {
        content.primitive._transformSpec
    }
}

public extension Renderable {
    /// Animates changes to this description with `animation`.
    ///
    /// ```swift
    /// FineCard(movie)
    ///     .opacity(self.isVisible ? 1 : 0)
    ///     .scale(self.isFocused ? 1.08 : 1.0)
    ///     .animation(.spring())
    /// ```
    ///
    /// The description says what the view looks like for the current state, and
    /// this says that arriving at it is worth watching. Nothing at the mutation
    /// has to know: setting `isFocused` from a button, a gesture or a network
    /// response all animate the same.
    ///
    /// Pass `nil` to hold a subtree still while everything around it animates.
    ///
    /// The first render is never animated, and neither is a view that is not in
    /// a window — there is nothing to come from in the first case and nobody to
    /// see it in the second.
    func animation(_ animation: FineAnimation?) -> any Renderable {
        FineAnimated(content: self, animation: animation)
    }
}
