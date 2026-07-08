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

    // Node-local scheduling state (previously FineNodeState).
    var primitive: (any FinePrimitiveRenderable)?
    var generation = 0
    var context: FineRenderContext?
}
