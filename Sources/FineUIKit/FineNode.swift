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

    /// The description that last rendered this view, kept as a metatype rather
    /// than a name: assigning it is a pointer store, so the debug description
    /// can name the component without formatting a string on every render.
    /// Held separately from `primitive`, which only the scheduled path sets.
    var primitiveType: (any FinePrimitiveRenderable.Type)?

    /// Renders applied at this position in the tree, and how many of them had
    /// to make a new view instead of updating one. Carried onto a replacement
    /// view by `FineDiagnostics.carryCounters(from:to:)`.
    var renderCount = 0
    var rebuildCount = 0

    /// How the view about to be updated came about. The scheduled path decides
    /// this when it reconciles, and the update it enqueues consumes it; a
    /// node-local re-render finds it empty and counts as an update.
    var pendingRenderKind: FineDiagnostics.RenderKind?

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
}
