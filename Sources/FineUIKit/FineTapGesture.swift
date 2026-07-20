//
//  FineTapGesture.swift
//  FineUIKit
//
//  Created by nova on 2026/07/11.
//

import UIKit
import ObjectiveC

@MainActor
final class FineTapHandlerBox: NSObject {
    var handler: @MainActor () -> Void
    var recognizer: UITapGestureRecognizer?

    init(handler: @escaping @MainActor () -> Void) {
        self.handler = handler
    }

    @objc func invoke(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        handler()
    }
}

@MainActor
extension UIView {
    nonisolated(unsafe) static var fineTapHandlerKey: UInt8 = 0

    var fineTapHandlerBox: FineTapHandlerBox? {
        get {
            objc_getAssociatedObject(self, &Self.fineTapHandlerKey) as? FineTapHandlerBox
        }
        set {
            objc_setAssociatedObject(self, &Self.fineTapHandlerKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    /// Installs one tap recognizer per view and replaces only the stored
    /// handler afterwards. Passing `nil` removes the recognizer.
    func fineSetTapHandler(_ handler: (@MainActor () -> Void)?) {
        guard let handler else {
            if let box = fineTapHandlerBox {
                if let recognizer = box.recognizer {
                    removeGestureRecognizer(recognizer)
                }
                fineTapHandlerBox = nil
            }
            return
        }

        if let box = fineTapHandlerBox {
            box.handler = handler
            return
        }

        let box = FineTapHandlerBox(handler: handler)
        let recognizer = UITapGestureRecognizer(target: box, action: #selector(FineTapHandlerBox.invoke(_:)))
        // Keep delivering touches to the view so a tap handler on (or above)
        // a UIControl coexists with the control's own actions.
        recognizer.cancelsTouchesInView = false
        box.recognizer = recognizer
        fineTapHandlerBox = box

        addGestureRecognizer(recognizer)
        if !isUserInteractionEnabled {
            isUserInteractionEnabled = true
        }
    }
}

/// Transparent wrapper that installs a tap handler on the rendered view.
/// Chained `.onTap` calls merge into one wrapper and run in order.
@MainActor
struct FineTapModified: FinePrimitiveRenderable {
    let content: any Renderable
    var actions: [@MainActor () -> Void]

    func _makeView() -> UIView {
        FineRenderer.primitive(for: content)._makeView()
    }

    func _canUpdate(_ view: UIView) -> Bool {
        FineRenderer.primitive(for: content)._canUpdate(view)
    }

    func _update(_ view: UIView, context: FineRenderContext) {
        FineRenderer.primitive(for: content)._update(view, context: context)

        if actions.isEmpty {
            view.fineSetTapHandler(nil)
        } else {
            let actions = actions
            view.fineSetTapHandler {
                for action in actions {
                    action()
                }
            }
        }
    }

    var _modifierSignature: String {
        FineRenderer.primitive(for: content)._modifierSignature + "|onTap"
    }

    var _key: AnyHashable? {
        FineRenderer.primitive(for: content)._key
    }
}

public extension Renderable {
    /// Runs `action` when the rendered view is tapped.
    ///
    /// Enables user interaction on the view (labels and image views disable
    /// it by default). Touches are still delivered to the view, so a tap
    /// handler on a control runs alongside the control's own actions.
    /// Chained `.onTap` handlers all run, in source order. Pass `nil` to keep
    /// the view's identity while removing the handler (conditional taps);
    /// removing the modifier itself rebuilds the view like any other
    /// modifier.
    func onTap(_ action: (@MainActor () -> Void)?) -> any Renderable {
        if var modified = self as? FineTapModified {
            if let action {
                modified.actions.append(action)
            }
            return modified
        }

        return FineTapModified(content: self, actions: action.map { [$0] } ?? [])
    }
}
