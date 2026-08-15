//
//  UIView+FineDebug.swift
//  FineUIKit
//
//  Created by nova on 2026/07/29.
//

import UIKit

/// Names the description behind a view, which is the one thing Xcode's view
/// debugger cannot know: it sees a `UILabel`, not the `FineLabel` that made it,
/// nor the key and modifier composition that decide whether the next render
/// reuses it.
///
/// These are meant for the debugger. Neither reads observable state, so calling
/// them from a breakpoint does not disturb the render loop:
///
/// ```
/// (lldb) po view.fineDumpTree()
/// (lldb) po someLabel.fineDebugDescription
/// ```
@MainActor
extension UIView {
    /// One line describing this view's role in the tree: the component that
    /// rendered it, the UIKit class it became, and the counters and identity
    /// the reconciler decided with.
    ///
    /// Reads `unmanaged` for a view FineUIKit did not make — a cell's content
    /// view, a container UIKit inserted, anything the app added itself.
    public var fineDebugDescription: String {
        guard let node = fineNodeIfPresent, node.primitiveType != nil else {
            return "\(type(of: self)) (unmanaged)"
        }

        var parts = ["\(node.primitiveName) → \(type(of: self))"]
        parts.append("renders \(node.renderCount)")
        if node.rebuildCount > 0 {
            parts.append("rebuilds \(node.rebuildCount)")
        }
        // The two questions the counters raise and cannot answer: who asked for
        // the last render, and what did it cost.
        //
        // The cost is this node's own. Under the runtime a container's update
        // hands its children to the scheduler and returns, and they are timed
        // when their turn comes — so the figures down a branch are independent
        // rather than nested, and are not meant to add up.
        if let reason = node.lastUpdateReason {
            parts.append("because \(reason.message)")
        }
        if let duration = node.lastUpdateDuration {
            parts.append(fineFormatted(duration))
        }
        if let key = node.key {
            parts.append("key \(key.base)")
        }
        if !node.modifierSignature.isEmpty {
            parts.append("modifiers \"\(node.modifierSignature)\"")
        }
        if node.localState != nil {
            parts.append("state")
        }
        // The two states behind most "my view isn't showing" questions, and
        // both are free to read here.
        if isHidden {
            parts.append("hidden")
        }
        if bounds.isEmpty {
            parts.append("zero size")
        }

        return parts.joined(separator: "  ")
    }

    /// The view subtree as indented text, one line per view.
    ///
    /// Flutter's `debugDumpApp()` for this runtime: the answer to "what did my
    /// description actually build, and which parts of it are re-rendering" in a
    /// form that pastes into an issue. Unmanaged views are listed too, because
    /// leaving them out would misrepresent the nesting.
    public func fineDumpTree() -> String {
        var lines: [String] = []
        appendDumpLines(to: &lines, depth: 0)
        return lines.joined(separator: "\n")
    }

    private func appendDumpLines(to lines: inout [String], depth: Int) {
        lines.append(String(repeating: "  ", count: depth) + fineDebugDescription)
        for subview in subviews {
            subview.appendDumpLines(to: &lines, depth: depth + 1)
        }
    }
}
