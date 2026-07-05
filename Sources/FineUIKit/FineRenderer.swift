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
        if let existing, node._canUpdate(existing) {
            node._update(existing)
            return existing
        }

        let view = node._makeView()
        node._update(view)
        return view
    }
}
