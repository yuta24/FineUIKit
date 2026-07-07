//
//  FineRenderContext.swift
//  FineUIKit
//
//  Created by nova on 2026/07/07.
//

import UIKit

@MainActor
public struct FineRenderContext {
    let nodeScheduler: FineNodeScheduler?

    init(nodeScheduler: FineNodeScheduler? = nil) {
        self.nodeScheduler = nodeScheduler
    }

    func render(_ node: any Renderable, reusing existing: UIView?) -> UIView {
        if let nodeScheduler {
            return nodeScheduler.renderChild(node, reusing: existing, context: self)
        }

        return FineRenderer.render(node, reusing: existing, context: self)
    }
}
