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
}
