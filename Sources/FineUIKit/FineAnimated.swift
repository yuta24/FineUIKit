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
        let node = view.fineNode
        let hasSomethingToAnimateFrom = node.hasBeenUpdated && view.window != nil
        node.hasBeenUpdated = true

        guard let animation else {
            // Not "say nothing and pass it on": an enclosing
            // `withFineAnimation` has already opened a block, and a write made
            // inside it animates whether or not this subtree wanted it to.
            // Opting out means saying so to UIKit.
            UIView.performWithoutAnimation {
                FineTransactionContext.$current.withValue(.disabled) {
                    content.primitive._update(view, context: context)
                }
            }
            return
        }

        // Nothing to animate from, and nowhere to show it: a view still being
        // built holds only defaults, and one outside a window has no viewer.
        guard hasSomethingToAnimateFrom else {
            content.primitive._update(view, context: context)
            return
        }

        animation.animate {
            // Set for the subtree as well as applied here, so a list inside it
            // animates its own diff to the same curve rather than to whatever
            // the mutation site happened to say.
            FineTransactionContext.$current.withValue(.animate(animation)) {
                content.primitive._update(view, context: context)
            }
            view.layoutIfNeeded()
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
