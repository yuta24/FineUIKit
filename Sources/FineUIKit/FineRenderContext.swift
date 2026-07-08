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
    var environment: FineEnvironmentValues

    init(nodeScheduler: FineNodeScheduler? = nil, environment: FineEnvironmentValues = .init()) {
        self.nodeScheduler = nodeScheduler
        self.environment = environment
    }

    func withEnvironment(_ transform: (inout FineEnvironmentValues) -> Void) -> FineRenderContext {
        var environment = self.environment
        transform(&environment)
        return FineRenderContext(nodeScheduler: nodeScheduler, environment: environment)
    }

    func render(_ node: any Renderable, reusing existing: UIView?) -> UIView {
        if let nodeScheduler {
            return nodeScheduler.renderChild(node, reusing: existing, context: self)
        }

        return FineRenderer.render(node, reusing: existing, context: self)
    }
}
