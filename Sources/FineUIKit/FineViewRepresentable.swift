//
//  FineViewRepresentable.swift
//  FineUIKit
//
//  Created by nova on 2026/07/11.
//

import UIKit

/// A `Renderable` that wraps an arbitrary `UIView`, bridging UIKit views that
/// have no built-in Fine component into the declarative tree (SwiftUI's
/// `UIViewRepresentable` counterpart).
///
/// `makeView()` runs once when the renderer needs a fresh view; on later
/// renders the same view instance is passed to `updateView(_:environment:)`.
/// Write every property the description controls on each update (the view may
/// be reused after a different state), and prefer "write only when different"
/// guards for properties whose setters do work.
///
/// Reuse follows the same rules as built-in components: the view is reused
/// when the representable's concrete type, its modifier signature, and its
/// `.key(_:)` all match. Two representable types that share a `ViewType`
/// never reuse each other's views.
@MainActor
public protocol FineViewRepresentable: Renderable {
    associatedtype ViewType: UIView

    /// Creates the wrapped view. Called once per view identity.
    func makeView() -> ViewType

    /// Writes the current description into `view`. Called on every render,
    /// with the environment resolved at this position in the tree.
    func updateView(_ view: ViewType, environment: FineEnvironmentValues)
}

public extension FineViewRepresentable {
    /// Bridges the representable into the render pipeline through the normal
    /// `body` resolution — no renderer special case. Override `body` to
    /// compose other `Renderable`s instead of wrapping a view directly; the
    /// override wins.
    var body: any Renderable {
        FineRepresentableAdapter(representable: self)
    }
}

/// Bridges a `FineViewRepresentable` into the internal primitive contract.
@MainActor
struct FineRepresentableAdapter<R: FineViewRepresentable>: FinePrimitiveRenderable {
    let representable: R

    func _makeView() -> UIView {
        representable.makeView()
    }

    func _canUpdate(_ view: UIView) -> Bool {
        view is R.ViewType
    }

    func _update(_ view: UIView, context: FineRenderContext) {
        guard let view = view as? R.ViewType else { return }
        representable.updateView(view, environment: context.environment)
    }

    // The concrete representable type is part of the signature so two
    // representables sharing a ViewType never update each other's views.
    // Cached per type: String(reflecting:) demangles at runtime and the
    // signature is compared on every render.
    var _modifierSignature: String {
        let key = ObjectIdentifier(R.self)
        if let cached = fineRepresentableSignatures[key] {
            return cached
        }

        let signature = "representable.\(String(reflecting: R.self))"
        fineRepresentableSignatures[key] = signature
        return signature
    }
}

@MainActor
private var fineRepresentableSignatures: [ObjectIdentifier: String] = [:]
