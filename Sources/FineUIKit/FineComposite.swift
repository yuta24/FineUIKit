//
//  FineComposite.swift
//  FineUIKit
//
//  Created by nova on 2026/08/05.
//

import UIKit

/// Carries the identity of the `Renderable` types a description was composed
/// from, so two of them that happen to resolve to the same primitive do not
/// update each other's views.
///
/// Resolution walks `body` until it reaches a primitive, which discards
/// everything it passed through. Without this, `struct Header: Renderable` and
/// `struct Footer: Renderable` — both resolving to a `FineLabel` — would look
/// identical to reconciliation: the view would be reused across a swap, and
/// with it whatever `FineState` the node holds.
///
/// Only descriptions that actually pass through a composite are wrapped, so a
/// tree of built-in components alone carries no extra signature and no extra
/// allocation.
@MainActor
struct FineComposite: FinePrimitiveRenderable {
    /// The composite types passed through, outermost first, joined by `>`.
    let types: String
    let primitive: any FinePrimitiveRenderable

    func _makeView() -> UIView {
        primitive._makeView()
    }

    func _canUpdate(_ view: UIView) -> Bool {
        primitive._canUpdate(view)
    }

    func _update(_ view: UIView, context: FineRenderContext) {
        primitive._update(view, context: context)
    }

    var _modifierSignature: String {
        "composite.\(types)|" + primitive._modifierSignature
    }

    var _key: AnyHashable? {
        primitive._key
    }

    var _viewProvider: any FinePrimitiveRenderable {
        primitive._viewProvider
    }
}

/// The name recorded for a composite type.
///
/// Cached per type: `String(reflecting:)` demangles at runtime, and the
/// signature this feeds is compared on every render.
@MainActor
func fineCompositeName(of value: any Renderable) -> String {
    let type = type(of: value)
    let key = ObjectIdentifier(type)
    if let cached = fineCompositeNames[key] {
        return cached
    }

    let name = String(reflecting: type)
    fineCompositeNames[key] = name
    return name
}

@MainActor
private var fineCompositeNames: [ObjectIdentifier: String] = [:]
