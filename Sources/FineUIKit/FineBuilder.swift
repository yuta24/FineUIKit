//
//  FineBuilder.swift
//  FineUIKit
//
//  Created by nova on 2026/07/07.
//

/// Builds a flat list of renderable UI descriptions for multi-child containers.
///
/// `FineBuilder` preserves FineUIKit's existing child representation:
/// containers receive `[any Renderable]` directly, and the renderer applies
/// the same positional and keyed reconciliation rules as before.
@resultBuilder
public enum FineBuilder {
    /// Wraps a single renderable expression as one child.
    public nonisolated static func buildExpression(_ expression: any Renderable) -> [any Renderable] {
        [expression]
    }

    /// Passes through an expression that already produces children.
    public nonisolated static func buildExpression(_ expression: [any Renderable]) -> [any Renderable] {
        expression
    }

    /// Flattens child groups in source order.
    public nonisolated static func buildBlock(_ components: [any Renderable]...) -> [any Renderable] {
        components.flatMap { $0 }
    }

    /// Emits children from an `if` branch, or no children when absent.
    public nonisolated static func buildOptional(_ component: [any Renderable]?) -> [any Renderable] {
        component ?? []
    }

    /// Emits children from the first branch of a conditional.
    public nonisolated static func buildEither(first: [any Renderable]) -> [any Renderable] {
        first
    }

    /// Emits children from the second branch of a conditional.
    public nonisolated static func buildEither(second: [any Renderable]) -> [any Renderable] {
        second
    }

    /// Flattens children produced by a `for` loop in source order.
    public nonisolated static func buildArray(_ components: [[any Renderable]]) -> [any Renderable] {
        components.flatMap { $0 }
    }

    /// Passes through children from an availability-limited branch.
    public nonisolated static func buildLimitedAvailability(_ component: [any Renderable]) -> [any Renderable] {
        component
    }
}
