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

    /// What `.animation(_:)` asked for at or above this position, if anything.
    ///
    /// It has to travel with the context rather than in a scope around the
    /// update, because a container's update does not perform its children's:
    /// it hands them to the scheduler and returns, and they run once it has.
    /// A block opened around the container would be closed again long before
    /// the children it was meant for were written to.
    ///
    /// Carried on the context also means a node keeps it — `FineNode.context`
    /// is what a node-local re-render replays — so a value that changes on its
    /// own still animates the way the description said it would.
    var animation: FineTransactionValue?

    init(
        nodeScheduler: FineNodeScheduler? = nil,
        renderGate: FineRenderGate? = nil,
        environment: FineEnvironmentValues = .init(),
        animation: FineTransactionValue? = nil
    ) {
        self.nodeScheduler = nodeScheduler
        self.renderGate = renderGate
        self.environment = environment
        self.animation = animation
    }

    func withEnvironment(_ transform: (inout FineEnvironmentValues) -> Void) -> FineRenderContext {
        var environment = self.environment
        transform(&environment)
        return FineRenderContext(
            nodeScheduler: nodeScheduler,
            renderGate: renderGate,
            environment: environment,
            animation: animation
        )
    }

    func withAnimation(_ animation: FineTransactionValue?) -> FineRenderContext {
        FineRenderContext(
            nodeScheduler: nodeScheduler,
            renderGate: renderGate,
            environment: environment,
            animation: animation
        )
    }

    func render(_ node: any Renderable, reusing existing: UIView?) -> UIView {
        render(resolved: FineRenderer.primitive(for: node), reusing: existing)
    }

    /// Renders a description whose primitive the caller already resolved, so a
    /// caller that had to inspect the primitive first does not pay for a second
    /// walk through `body`.
    func render(resolved primitive: any FinePrimitiveRenderable, reusing existing: UIView?) -> UIView {
        if let nodeScheduler {
            return nodeScheduler.renderChild(resolved: primitive, reusing: existing, context: self)
        }

        return FineRenderer.render(resolved: primitive, reusing: existing, context: self)
    }
}
