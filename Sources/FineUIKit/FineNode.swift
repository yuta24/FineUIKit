//
//  FineNode.swift
//  FineUIKit
//
//  Created by nova on 2026/07/08.
//

import UIKit

/// Persistent per-view element that owns all reconciliation state for the
/// view: its modifier signature, key, and node-local scheduling state.
/// One `FineNode` is attached to each Fine-managed view (Flutter's Element).
@MainActor
final class FineNode {
    var modifierSignature: String = ""
    var key: AnyHashable?

    /// Identity-scoped local state owned by this element (e.g. FineState).
    /// Persists for as long as the element (and its view) is reused, and is
    /// re-created fresh when a new element/view is made for a changed identity.
    var localState: AnyObject?

    // Node-local scheduling state (previously FineNodeState).
    var primitive: (any FinePrimitiveRenderable)?
    var generation = 0
    // Carries the environment resolved for this element at its last update;
    // node-local re-renders reuse it, so environment survives without a
    // separate copy on the node.
    var context: FineRenderContext?

    /// The component that makes this view, kept as a metatype rather than a
    /// name so the debug description costs nothing to keep current. Held
    /// separately from `primitive`, which only the scheduled path sets.
    var primitiveType: (any FinePrimitiveRenderable.Type)?

    /// The outermost description `primitiveType` was resolved from, so the
    /// resolution is not repeated for a description this node has already seen.
    private var providerResolvedFrom: ObjectIdentifier?

    /// Renders applied at this position in the tree, and how many of them had
    /// to make a new view instead of updating one. Carried onto a replacement
    /// view by `FineDiagnostics.carryCounters(from:to:)`.
    var renderCount = 0
    var rebuildCount = 0

    /// How the view about to be updated came about. The scheduled path decides
    /// this when it reconciles, and the update it enqueues consumes it; a
    /// node-local re-render finds it empty and counts as an update.
    var pendingRenderKind: FineDiagnostics.RenderKind?

    /// Why this node last rendered, and how long writing the description into
    /// the view took.
    ///
    /// Kept for the question a diff-based runtime is worst at answering from
    /// the code alone: *this view is being written to — who asked, and what is
    /// it costing?* One enum and one duration per node, written once per
    /// render.
    var lastUpdateReason: FineDiagnostics.UpdateReason?
    var lastUpdateDuration: Duration?

    /// Set by the scope that asked for the render, and taken by the render
    /// that answers it. Empty means the node is being rendered because
    /// something above it was.
    var pendingUpdateReason: FineDiagnostics.UpdateReason?

    /// The component that last rendered this view, or `nil` for a view
    /// FineUIKit does not manage.
    var primitiveName: String {
        primitiveType.map { "\($0)" } ?? "unknown"
    }

    /// Reads and clears the kind recorded by the last reconciliation.
    func takePendingRenderKind() -> FineDiagnostics.RenderKind? {
        defer { pendingRenderKind = nil }
        return pendingRenderKind
    }

    /// Reads and clears the reason recorded for the render now finishing.
    func takePendingUpdateReason() -> FineDiagnostics.UpdateReason? {
        defer { pendingUpdateReason = nil }
        return pendingUpdateReason
    }

    /// Records which component makes this view, looking through modifiers that
    /// render into their content's view.
    ///
    /// That lookup walks `body`, which is not free — the runtime already goes
    /// out of its way to resolve a description once per render — so the answer
    /// is cached against the description it came from. A description whose type
    /// changed forces a rebuild and a fresh node, so the cache is only ever
    /// consulted for the description that filled it.
    ///
    /// One case keeps a stale answer: the same modifier type over different
    /// content that makes the same view class, such as `.backgroundColor()`
    /// applied to two components that both build a `UILabel`. Walking `body`
    /// on every render of every view to catch it would cost the whole tree
    /// more than the debug label is worth.
    func noteRender(of primitive: any FinePrimitiveRenderable) {
        let outer = ObjectIdentifier(type(of: primitive))
        guard providerResolvedFrom != outer else { return }

        providerResolvedFrom = outer
        primitiveType = type(of: primitive._viewProvider)
    }
}
