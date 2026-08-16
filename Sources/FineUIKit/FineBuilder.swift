//
//  FineBuilder.swift
//  FineUIKit
//
//  Created by nova on 2026/07/07.
//

/// Builds a flat list of renderable UI descriptions for multi-child containers.
///
/// `FineBuilder` preserves FineUIKit's existing child representation:
/// containers receive `[any Renderable]` directly, and the renderer applies the
/// same positional and keyed reconciliation rules as before.
///
/// Children a conditional or a loop produced additionally carry a **structural
/// slot** (`FineStructural`) naming their position in the builder's static
/// structure. Straight-line children carry nothing and keep matching by
/// position — but because slotted children are matched by their slot instead,
/// an `if` that stops producing a child no longer shifts the position its
/// siblings are matched at. See `FineStructural` for what that used to cost.
///
/// The builder is `@MainActor` because it now builds descriptions rather than
/// only forwarding them, and `Renderable` is `@MainActor`. Every entry point
/// that takes one — `FineStack.vertical(content:)` and friends — already takes
/// a `@MainActor` closure, so this is not a restriction at any call site.
@MainActor
@resultBuilder
public enum FineBuilder {
    /// Wraps a single renderable expression as one child.
    public static func buildExpression(_ expression: any Renderable) -> [any Renderable] {
        [expression]
    }

    /// Passes through an expression that already produces children.
    public static func buildExpression(_ expression: [any Renderable]) -> [any Renderable] {
        expression
    }

    /// Flattens child groups in source order, naming each group's position so
    /// two conditionals in one builder cannot land on the same slot.
    ///
    /// Only children that already carry a slot are prefixed. A straight-line
    /// child stays unslotted, because its position among the other unslotted
    /// children is fixed by the source and needs no help.
    public static func buildBlock(_ components: [any Renderable]...) -> [any Renderable] {
        var children: [any Renderable] = []
        children.reserveCapacity(components.reduce(0) { $0 + $1.count })

        for (position, component) in components.enumerated() {
            for child in component {
                guard let structural = child as? FineStructural else {
                    children.append(child)
                    continue
                }

                children.append(structural.prefixed(by: "\(position)"))
            }
        }

        return children
    }

    /// Emits children from an `if` branch, or no children when absent.
    public static func buildOptional(_ component: [any Renderable]?) -> [any Renderable] {
        guard let component else { return [] }
        return slotted(component, in: "?")
    }

    /// Emits children from the first branch of a conditional.
    public static func buildEither(first: [any Renderable]) -> [any Renderable] {
        slotted(first, in: "|")
    }

    /// Emits children from the second branch of a conditional.
    ///
    /// Deliberately the same slot as `first`: a branch change that resolves to
    /// a compatible view keeps updating that view in place, which is the
    /// behaviour `FineStack` has always had. The slot exists to stop a branch
    /// from moving its *siblings*, not to separate the branches from each other.
    public static func buildEither(second: [any Renderable]) -> [any Renderable] {
        slotted(second, in: "|")
    }

    /// Flattens children produced by a `for` loop in source order, recording
    /// which iteration produced each one so a shorter loop does not shift what
    /// follows it.
    ///
    /// The iteration is recorded as a *position*, not as part of the slot, so a
    /// child that carries a `.key(_:)` still follows its item across a reorder
    /// instead of being pinned to the index it first appeared at.
    public static func buildArray(_ components: [[any Renderable]]) -> [any Renderable] {
        var children: [any Renderable] = []
        children.reserveCapacity(components.reduce(0) { $0 + $1.count })

        for (iteration, component) in components.enumerated() {
            var unslottedPosition = 0

            for child in component {
                guard let structural = child as? FineStructural else {
                    children.append(
                        FineStructural(path: "*", position: [iteration, unslottedPosition], content: child)
                    )
                    unslottedPosition += 1
                    continue
                }

                children.append(structural.positioned(at: iteration))
            }
        }

        return children
    }

    /// Passes through children from an availability-limited branch.
    public static func buildLimitedAvailability(_ component: [any Renderable]) -> [any Renderable] {
        component
    }

    /// Gives `children` that have no slot yet one named `component`.
    ///
    /// A child that already has a slot is passed through untouched rather than
    /// nested inside this one. A `switch` and an `else if` chain reach here as
    /// *nested* `buildEither` calls, and nesting a slot per level would make the
    /// first case shallower than the rest — so changing between two cases would
    /// rebuild the view while changing between two others updated it in place.
    /// Uniqueness does not depend on the nesting: `buildBlock` prefixes every
    /// slot with its statement's position, which is what keeps two conditionals
    /// in one builder apart.
    ///
    /// Children assigned here are numbered among themselves rather than by their
    /// position in the flattened branch. A conditional nested in the same branch
    /// changes how many children precede them, and numbering by flattened
    /// position would let that change move them — the very thing slots exist to
    /// prevent, reappearing one level down.
    private static func slotted(_ children: [any Renderable], in component: String) -> [any Renderable] {
        var unslottedPosition = 0

        return children.map { child in
            guard !(child is FineStructural) else { return child }

            let slotted = FineStructural(path: component, position: [unslottedPosition], content: child)
            unslottedPosition += 1
            return slotted
        }
    }
}
