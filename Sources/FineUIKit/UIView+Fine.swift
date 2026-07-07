//
//  UIView+Fine.swift
//  FineUIKit
//
//  Created by nova on 2026/07/06.
//

import UIKit
import ObjectiveC

@MainActor
extension UIView {
    nonisolated(unsafe) static var fineModifierSignatureKey: UInt8 = 0
    nonisolated(unsafe) static var fineKeyKey: UInt8 = 0
    nonisolated(unsafe) static var fineInstalledConstraintsKey: UInt8 = 0
    nonisolated(unsafe) static var fineCustomConstraintsKey: UInt8 = 0
    nonisolated(unsafe) static var fineNodeStateKey: UInt8 = 0

    var fineModifierSignature: String {
        get {
            objc_getAssociatedObject(self, &Self.fineModifierSignatureKey) as? String ?? ""
        }
        set {
            objc_setAssociatedObject(self, &Self.fineModifierSignatureKey, newValue, .OBJC_ASSOCIATION_COPY_NONATOMIC)
        }
    }

    var fineKey: AnyHashable? {
        get {
            objc_getAssociatedObject(self, &Self.fineKeyKey) as? AnyHashable
        }
        set {
            objc_setAssociatedObject(self, &Self.fineKeyKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    var fineInstalledConstraints: [String: NSLayoutConstraint] {
        get {
            objc_getAssociatedObject(self, &Self.fineInstalledConstraintsKey) as? [String: NSLayoutConstraint] ?? [:]
        }
        set {
            objc_setAssociatedObject(self, &Self.fineInstalledConstraintsKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    var fineCustomConstraints: [String: [NSLayoutConstraint]] {
        get {
            objc_getAssociatedObject(self, &Self.fineCustomConstraintsKey) as? [String: [NSLayoutConstraint]] ?? [:]
        }
        set {
            objc_setAssociatedObject(self, &Self.fineCustomConstraintsKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    var fineNodeState: FineNodeState? {
        get {
            objc_getAssociatedObject(self, &Self.fineNodeStateKey) as? FineNodeState
        }
        set {
            objc_setAssociatedObject(self, &Self.fineNodeStateKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
}
