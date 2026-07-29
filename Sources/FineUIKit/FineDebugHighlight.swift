//
//  FineDebugHighlight.swift
//  FineUIKit
//
//  Created by nova on 2026/07/29.
//

#if DEBUG
import QuartzCore
import UIKit

/// Outlines views as they re-render, so a change that should have touched one
/// label but repainted the screen is visible without reading a log.
///
/// Green means the view was updated in place, red that it had to be rebuilt —
/// the distinction `FineDiagnostics.logsViewReuse` reports in words. The number
/// is the view's running render count, which is what makes a view that
/// re-renders on every keystroke stand out from one that rendered once.
///
/// The outline is a sublayer rather than the view's own border, so a view that
/// styles its border keeps it, and it never participates in hit testing.
/// Enabled by `FineDiagnostics.highlightsRenders`; DEBUG builds only.
@MainActor
enum FineDebugHighlight {
    /// Marks the overlay so a second flash finds and reuses it instead of
    /// stacking layers on a view that re-renders repeatedly.
    static let layerName = "FineUIKit.debugHighlight"

    private static let duration: CFTimeInterval = 0.6

    static func flash(_ view: UIView, kind: FineDiagnostics.RenderKind, count: Int) {
        let color: UIColor = switch kind {
        case .updated: .systemGreen
        case .created, .rebuilt: .systemRed
        }

        let overlay = existingOverlay(in: view) ?? makeOverlay(in: view)
        overlay.frame = view.bounds
        overlay.borderColor = color.cgColor

        if let label = overlay.sublayers?.first as? CATextLayer {
            // Sized from the text so a flash on a small view does not cover it.
            label.string = "\(count)"
            label.foregroundColor = color.cgColor
            label.contentsScale = max(view.traitCollection.displayScale, 1)
            label.frame = CGRect(x: 1, y: 1, width: 28, height: 9)
        }

        // A restarted animation replaces the running one, so the overlay of a
        // view rendering in a tight loop stays lit rather than strobing.
        overlay.removeAnimation(forKey: "fade")
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.duration = duration
        fade.fillMode = .forwards
        fade.isRemovedOnCompletion = false
        overlay.add(fade, forKey: "fade")

        // The first render of a view usually precedes its layout, so its bounds
        // are still empty here and the outline would have nothing to draw.
        // Re-reading them once the turn is over catches that case, which is
        // exactly the `created` flash the counts start from.
        if view.bounds.isEmpty {
            Task { @MainActor [weak view] in
                guard let view, overlay.superlayer === view.layer else { return }

                overlay.frame = view.bounds
            }
        }
    }

    /// Whether `view` currently carries an overlay. Exists for tests: the
    /// overlay is otherwise invisible to anything but the render server.
    static func existingOverlay(in view: UIView) -> CALayer? {
        view.layer.sublayers?.first { $0.name == layerName }
    }

    private static func makeOverlay(in view: UIView) -> CALayer {
        let overlay = CALayer()
        overlay.name = layerName
        overlay.borderWidth = 1
        // Above the view's own content, including any layer it manages itself.
        overlay.zPosition = .greatestFiniteMagnitude

        let label = CATextLayer()
        label.fontSize = 8
        label.alignmentMode = .left
        overlay.addSublayer(label)

        view.layer.addSublayer(overlay)
        return overlay
    }
}
#endif
