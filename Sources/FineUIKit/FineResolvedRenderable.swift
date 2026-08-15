//
//  FineResolvedRenderable.swift
//  FineUIKit
//
//  Created by nova on 2026/08/15.
//

import UIKit

/// A description together with the primitive it resolves to, resolved once.
///
/// Resolving walks `body`, and `body` is application code: a `Renderable` that
/// composes other `Renderable`s pays for that walk every time it is asked. A
/// pass-through wrapper is asked up to five times in one render — for the
/// modifier signature, the key, the reuse check, the update, and the debug
/// provider — so a wrapper that resolves on each question rebuilds the
/// description it wraps once per question instead of once per render.
///
/// `FineRenderer.render(resolved:)` and `FineStack` already avoid the second
/// walk by handing a resolved primitive along; this is the same rule applied
/// inside the wrappers, which are the one place that still broke it.
///
/// A description is a value the runtime rebuilds on every render, so a box made
/// with one lives exactly one render pass: nothing is remembered across a state
/// change.
@MainActor
final class FineResolvedRenderable {
    /// The description as it was written, kept so a wrapper can rewrap it
    /// without forcing the walk.
    let description: any Renderable

    private var resolved: (any FinePrimitiveRenderable)?

    init(_ description: any Renderable) {
        self.description = description
    }

    /// The primitive this description resolves to.
    ///
    /// The walk happens in whichever observation scope asks first, which is the
    /// scope reconciling the description — a container's node, or the root.
    /// That is the scope `Renderable.body` documents its reads as belonging to,
    /// and resolving once is what makes it *one* scope rather than every scope
    /// that happened to ask.
    var primitive: any FinePrimitiveRenderable {
        if let resolved { return resolved }

        let primitive = FineRenderer.primitive(for: description)
        resolved = primitive
        return primitive
    }
}
