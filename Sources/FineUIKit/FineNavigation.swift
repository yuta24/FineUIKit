//
//  FineNavigation.swift
//  FineUIKit
//
//  Created by nova on 2026/07/07.
//

import UIKit
import ObjectiveC

@MainActor
public struct FineNavigation {
    private var title: String?
    private var prompt: String?
    private var largeTitleDisplayMode: UINavigationItem.LargeTitleDisplayMode = .automatic
    private var hidesBackButton = false
    private var leadingButtons: [FineBarButton] = []
    private var trailingButtons: [FineBarButton] = []

    public init(title: String? = nil) {
        self.title = title
    }

    /// Sets the prompt displayed above the title.
    public func prompt(_ prompt: String) -> FineNavigation {
        var copy = self
        copy.prompt = prompt
        return copy
    }

    /// Sets how the navigation item participates in large-title display.
    public func largeTitleDisplayMode(_ mode: UINavigationItem.LargeTitleDisplayMode) -> FineNavigation {
        var copy = self
        copy.largeTitleDisplayMode = mode
        return copy
    }

    /// Sets whether the back button is hidden.
    public func hidesBackButton(_ hides: Bool = true) -> FineNavigation {
        var copy = self
        copy.hidesBackButton = hides
        return copy
    }

    /// Sets leading bar buttons in visual order.
    public func leading(_ buttons: FineBarButton...) -> FineNavigation {
        var copy = self
        copy.leadingButtons = buttons
        return copy
    }

    /// Sets trailing bar buttons in visual order. The last button is rightmost.
    public func trailing(_ buttons: FineBarButton...) -> FineNavigation {
        var copy = self
        copy.trailingButtons = buttons
        return copy
    }

    /// Applies this description to a navigation item.
    public func apply(to navigationItem: UINavigationItem) {
        if navigationItem.title != title {
            navigationItem.title = title
        }
        if navigationItem.prompt != prompt {
            navigationItem.prompt = prompt
        }
        if navigationItem.largeTitleDisplayMode != largeTitleDisplayMode {
            navigationItem.largeTitleDisplayMode = largeTitleDisplayMode
        }
        if navigationItem.hidesBackButton != hidesBackButton {
            navigationItem.hidesBackButton = hidesBackButton
        }

        apply(leadingButtons, to: navigationItem, placement: .leading)
        apply(trailingButtons, to: navigationItem, placement: .trailing)
    }

    private enum Placement {
        case leading
        case trailing
    }

    private func apply(_ buttons: [FineBarButton], to navigationItem: UINavigationItem, placement: Placement) {
        let desiredButtons = placement == .trailing ? Array(buttons.reversed()) : buttons
        let currentItems = items(for: navigationItem, placement: placement)
        let desiredSignatures = desiredButtons.map(\.signature)
        let currentSignatures = currentItems.map(\.fineBarButtonSignature)

        guard desiredSignatures == currentSignatures else {
            let newItems = desiredButtons.enumerated().map { index, button in
                button.makeItem(reusing: currentItems.indices.contains(index) ? currentItems[index] : nil)
            }
            set(newItems, on: navigationItem, placement: placement)
            return
        }

        for (button, item) in zip(desiredButtons, currentItems) {
            button.update(item)
        }
    }

    private func items(for navigationItem: UINavigationItem, placement: Placement) -> [UIBarButtonItem] {
        switch placement {
        case .leading:
            navigationItem.leftBarButtonItems ?? []
        case .trailing:
            navigationItem.rightBarButtonItems ?? []
        }
    }

    private func set(_ items: [UIBarButtonItem], on navigationItem: UINavigationItem, placement: Placement) {
        switch placement {
        case .leading:
            navigationItem.leftBarButtonItems = items
        case .trailing:
            navigationItem.rightBarButtonItems = items
        }
    }
}

@MainActor
public struct FineBarButton {
    private enum Kind {
        case title(String)
        case image(UIImage)
        case systemItem(UIBarButtonItem.SystemItem)

        var signatureKey: String {
            switch self {
            case .title:
                "title"
            case .image:
                "image"
            case let .systemItem(systemItem):
                "system.\(systemItem.rawValue)"
            }
        }
    }

    private var kind: Kind
    private var style: UIBarButtonItem.Style = .plain
    private var isEnabled = true
    private var action: @MainActor () -> Void

    public init(title: String, action: @escaping @MainActor () -> Void) {
        self.kind = .title(title)
        self.action = action
    }

    public init(image: UIImage, action: @escaping @MainActor () -> Void) {
        self.kind = .image(image)
        self.action = action
    }

    public init(systemItem: UIBarButtonItem.SystemItem, action: @escaping @MainActor () -> Void) {
        self.kind = .systemItem(systemItem)
        self.action = action
    }

    /// Sets the bar button style.
    public func style(_ style: UIBarButtonItem.Style) -> FineBarButton {
        var copy = self
        copy.style = style
        return copy
    }

    /// Sets whether the bar button is enabled.
    public func enabled(_ isEnabled: Bool) -> FineBarButton {
        var copy = self
        copy.isEnabled = isEnabled
        return copy
    }

    fileprivate var signature: String {
        "\(kind.signatureKey).style.\(style.rawValue)"
    }

    fileprivate func makeItem(reusing item: UIBarButtonItem?) -> UIBarButtonItem {
        if let item, item.fineBarButtonSignature == signature {
            update(item)
            return item
        }

        let box = FineBarButtonHandlerBox(handler: action)
        let item: UIBarButtonItem
        switch kind {
        case let .title(title):
            item = .init(title: title, style: style, target: box, action: #selector(FineBarButtonHandlerBox.invoke(_:)))
        case let .image(image):
            item = .init(image: image, style: style, target: box, action: #selector(FineBarButtonHandlerBox.invoke(_:)))
        case let .systemItem(systemItem):
            item = .init(barButtonSystemItem: systemItem, target: box, action: #selector(FineBarButtonHandlerBox.invoke(_:)))
            if item.style != style {
                item.style = style
            }
        }

        item.fineBarButtonSignature = signature
        item.fineBarButtonHandlerBox = box
        update(item)
        return item
    }

    fileprivate func update(_ item: UIBarButtonItem) {
        item.fineBarButtonSignature = signature
        item.fineBarButtonHandlerBox?.handler = action
        item.target = item.fineBarButtonHandlerBox
        item.action = #selector(FineBarButtonHandlerBox.invoke(_:))

        switch kind {
        case let .title(title):
            if item.title != title {
                item.title = title
            }
            if item.image != nil {
                item.image = nil
            }
        case let .image(image):
            if item.image !== image {
                item.image = image
            }
            if item.title != nil {
                item.title = nil
            }
        case .systemItem:
            break
        }

        if item.isEnabled != isEnabled {
            item.isEnabled = isEnabled
        }
    }
}

@MainActor
private final class FineBarButtonHandlerBox: NSObject {
    var handler: @MainActor () -> Void

    init(handler: @escaping @MainActor () -> Void) {
        self.handler = handler
    }

    @objc func invoke(_ sender: UIBarButtonItem) {
        handler()
    }
}

@MainActor
private extension UIBarButtonItem {
    nonisolated(unsafe) static var fineBarButtonSignatureKey: UInt8 = 0
    nonisolated(unsafe) static var fineBarButtonHandlerBoxKey: UInt8 = 0

    var fineBarButtonSignature: String {
        get {
            objc_getAssociatedObject(self, &Self.fineBarButtonSignatureKey) as? String ?? ""
        }
        set {
            objc_setAssociatedObject(self, &Self.fineBarButtonSignatureKey, newValue, .OBJC_ASSOCIATION_COPY_NONATOMIC)
        }
    }

    var fineBarButtonHandlerBox: FineBarButtonHandlerBox? {
        get {
            objc_getAssociatedObject(self, &Self.fineBarButtonHandlerBoxKey) as? FineBarButtonHandlerBox
        }
        set {
            objc_setAssociatedObject(self, &Self.fineBarButtonHandlerBoxKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
}
