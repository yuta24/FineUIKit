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
    nonisolated(unsafe) static var fineNodeKey: UInt8 = 0
    nonisolated(unsafe) static var fineInstalledConstraintsKey: UInt8 = 0
    nonisolated(unsafe) static var fineCustomConstraintsKey: UInt8 = 0

    var fineNodeIfPresent: FineNode? {
        objc_getAssociatedObject(self, &Self.fineNodeKey) as? FineNode
    }

    var fineNode: FineNode {
        if let existing = fineNodeIfPresent { return existing }

        let node = FineNode()
        objc_setAssociatedObject(self, &Self.fineNodeKey, node, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return node
    }

    var fineModifierSignature: String {
        get {
            fineNodeIfPresent?.modifierSignature ?? ""
        }
        set {
            fineNode.modifierSignature = newValue
        }
    }

    var fineKey: AnyHashable? {
        get {
            fineNodeIfPresent?.key
        }
        set {
            fineNode.key = newValue
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
}
