//
//  FineRenderContext.swift
//  FineUIKit
//
//  Created by nova on 2026/07/07.
//

import UIKit

@MainActor
struct FineRenderContext {
    let nodeScheduler: FineNodeScheduler?
    /// Gates observation-driven re-renders for the tree this context belongs to.
    /// `nil` for one-off renders that nobody suspends (tests, direct
    /// `FineRenderer.render` calls).
    let renderGate: FineRenderGate?
    var environment: FineEnvironmentValues

    init(
        nodeScheduler: FineNodeScheduler? = nil,
        renderGate: FineRenderGate? = nil,
        environment: FineEnvironmentValues = .init()
    ) {
        self.nodeScheduler = nodeScheduler
        self.renderGate = renderGate
        self.environment = environment
    }

    func withEnvironment(_ transform: (inout FineEnvironmentValues) -> Void) -> FineRenderContext {
        var environment = self.environment
        transform(&environment)
        return FineRenderContext(nodeScheduler: nodeScheduler, renderGate: renderGate, environment: environment)
    }

    func render(_ node: any Renderable, reusing existing: UIView?) -> UIView {
        if let nodeScheduler {
            return nodeScheduler.renderChild(node, reusing: existing, context: self)
        }

        return FineRenderer.render(node, reusing: existing, context: self)
    }
}
