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
        if let nodeScheduler = context.nodeScheduler {
            return nodeScheduler.renderChild(node, reusing: existing, context: context)
        }

        let node = primitive(for: node)

        if let existing, reuses(existing, for: node) {
            node._update(existing, context: context)
            existing.fineModifierSignature = node._modifierSignature
            existing.fineKey = node._key
            return existing
        }

        let view = node._makeView()
        node._update(view, context: context)
        view.fineModifierSignature = node._modifierSignature
        view.fineKey = node._key
        return view
    }

    /// Whether `existing` can be updated in place for `primitive`, rather than
    /// replaced: the view type must match, and so must the modifier
    /// composition and the key, or a removed modifier would leave its effect
    /// behind and a moved item would keep another item's view.
    ///
    /// The single place both render paths decide this, so `FineDiagnostics`
    /// sees every rebuild.
    static func reuses(_ existing: UIView, for primitive: any FinePrimitiveRenderable) -> Bool {
        guard primitive._canUpdate(existing) else {
            FineDiagnostics.reportRebuild(of: existing, for: primitive, reason: .viewType)
            return false
        }

        let signature = primitive._modifierSignature
        guard existing.fineModifierSignature == signature else {
            FineDiagnostics.reportRebuild(
                of: existing,
                for: primitive,
                reason: .modifierSignature(previous: existing.fineModifierSignature, current: signature)
            )
            return false
        }

        let key = primitive._key
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
