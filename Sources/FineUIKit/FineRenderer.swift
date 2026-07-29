//
//  FineRenderer.swift
//  FineUIKit
//
//  Created by nova on 2026/07/05.
//

import UIKit

@MainActor
public enum FineRenderer {
    /// Returns a view representing `node`, updating `existing` in place when
    /// the description is compatible with it, or creating a new view otherwise.
    public static func render(_ node: any Renderable, reusing existing: UIView? = nil) -> UIView {
        render(node, reusing: existing, context: FineRenderContext())
    }

    static func render(_ node: any Renderable, reusing existing: UIView? = nil, context: FineRenderContext) -> UIView {
        render(resolved: primitive(for: node), reusing: existing, context: context)
    }

    /// Renders a description whose primitive the caller already resolved.
    ///
    /// Resolving walks `body`, so a caller that had to look at the primitive
    /// anyway — `FineStack`, for a child's key — hands it over instead of
    /// making the renderer rebuild the same subtree.
    static func render(
        resolved node: any FinePrimitiveRenderable,
        reusing existing: UIView? = nil,
        context: FineRenderContext
    ) -> UIView {
        if let nodeScheduler = context.nodeScheduler {
            return nodeScheduler.renderChild(resolved: node, reusing: existing, context: context)
        }

        // Read once and reuse: both are computed properties that walk `body`
        // down to the content primitive, so asking twice re-evaluates the
        // description.
        let signature = node._modifierSignature
        let key = node._key

        if let existing, reuses(existing, for: node, signature: signature, key: key) {
            node._update(existing, context: context)
            existing.fineModifierSignature = signature
            existing.fineKey = key
            existing.fineNode.primitiveType = type(of: node._viewProvider)
            FineDiagnostics.recordRender(of: existing, as: .updated)
            return existing
        }

        let view = node._makeView()
        // Before the update, so the counters the render is about to add to are
        // the ones the replaced view accumulated.
        FineDiagnostics.carryCounters(from: existing, to: view)
        node._update(view, context: context)
        view.fineModifierSignature = signature
        view.fineKey = key
        view.fineNode.primitiveType = type(of: node._viewProvider)
        FineDiagnostics.recordRender(of: view, as: existing == nil ? .created : .rebuilt)
        return view
    }

    /// Whether `existing` can be updated in place for `primitive`, rather than
    /// replaced: the view type must match, and so must the modifier
    /// composition and the key, or a removed modifier would leave its effect
    /// behind and a moved item would keep another item's view.
    ///
    /// The single place both render paths decide this, so `FineDiagnostics`
    /// sees every rebuild. `signature` and `key` are passed in rather than read
    /// here: the caller installs them on the view afterwards and would
    /// otherwise re-evaluate the description to get the same values.
    static func reuses(
        _ existing: UIView,
        for primitive: any FinePrimitiveRenderable,
        signature: String,
        key: AnyHashable?
    ) -> Bool {
        guard primitive._canUpdate(existing) else {
            FineDiagnostics.reportRebuild(of: existing, for: primitive, reason: .viewType)
            return false
        }

        guard existing.fineModifierSignature == signature else {
            FineDiagnostics.reportRebuild(
                of: existing,
                for: primitive,
                reason: .modifierSignature(previous: existing.fineModifierSignature, current: signature)
            )
            return false
        }

        guard existing.fineKey == key else {
            FineDiagnostics.reportRebuild(
                of: existing,
                for: primitive,
                reason: .key(previous: existing.fineKey, current: key)
            )
            return false
        }

        return true
    }

    static func primitive(for node: any Renderable) -> any FinePrimitiveRenderable {
        var current = node
        for _ in 0..<64 {
            if let primitive = current as? any FinePrimitiveRenderable {
                return primitive
            }
            current = current.body
        }
        if let primitive = current as? any FinePrimitiveRenderable {
            return primitive
        }

        assertionFailure("Renderable body nesting exceeded 64 levels")
        guard let primitive = current as? any FinePrimitiveRenderable else {
            fatalError("Renderable body did not resolve to a primitive")
        }
        return primitive
    }
}
