//
//  FineRenderer.swift
//  FineUIKit
//
//  Created by nova on 2026/07/05.
//

import UIKit
import ObjectiveC

@MainActor
public enum FineRenderer {
    /// Returns a view representing `node`, updating `existing` in place when
    /// the description is compatible with it, or creating a new view otherwise.
    public static func render(_ node: any Renderable, reusing existing: UIView? = nil) -> UIView {
        if let existing, node._canUpdate(existing), existing.fineModifierSignature == node._modifierSignature {
            node._update(existing)
            existing.fineModifierSignature = node._modifierSignature
            return existing
        }

        let view = node._makeView()
        node._update(view)
        view.fineModifierSignature = node._modifierSignature
        return view
    }
}

private extension UIView {
    nonisolated(unsafe) static var fineModifierSignatureKey: UInt8 = 0

    var fineModifierSignature: String {
        get {
            objc_getAssociatedObject(self, &Self.fineModifierSignatureKey) as? String ?? ""
        }
        set {
            objc_setAssociatedObject(self, &Self.fineModifierSignatureKey, newValue, .OBJC_ASSOCIATION_COPY_NONATOMIC)
        }
    }
}
