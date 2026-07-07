//
//  UIControl+FineHandlers.swift
//  FineUIKit
//
//  Created by nova on 2026/07/07.
//

import UIKit
import ObjectiveC

@MainActor
final class FineControlHandlerBox {
    var handler: (UIControl) -> Void

    init(handler: @escaping (UIControl) -> Void) {
        self.handler = handler
    }
}

@MainActor
extension UIControl {
    nonisolated(unsafe) static var fineHandlersKey: UInt8 = 0

    private var fineHandlers: [String: FineControlHandlerBox] {
        get {
            objc_getAssociatedObject(self, &Self.fineHandlersKey) as? [String: FineControlHandlerBox] ?? [:]
        }
        set {
            objc_setAssociatedObject(self, &Self.fineHandlersKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    /// Registers one trampoline `UIAction` per key and replaces only the
    /// stored handler afterwards. Passing `nil` removes the action.
    func fineSetHandler(_ key: String, for event: UIControl.Event, handler: ((UIControl) -> Void)?) {
        guard let handler else {
            removeAction(identifiedBy: .init(key), for: event)
            var handlers = fineHandlers
            handlers[key] = nil
            fineHandlers = handlers
            return
        }

        var handlers = fineHandlers
        if let box = handlers[key] {
            box.handler = handler
            return
        }

        let box = FineControlHandlerBox(handler: handler)
        handlers[key] = box
        fineHandlers = handlers

        addAction(.init(identifier: .init(key), handler: { [box] action in
            guard let control = action.sender as? UIControl else { return }
            box.handler(control)
        }), for: event)
    }
}
