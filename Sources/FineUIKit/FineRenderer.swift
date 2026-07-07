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

        if let existing,
           node._canUpdate(existing),
           existing.fineModifierSignature == node._modifierSignature,
           existing.fineKey == node._key {
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
