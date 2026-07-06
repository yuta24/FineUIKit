//
//  FineKeyed.swift
//  FineUIKit
//
//  Created by nova on 2026/07/06.
//

import UIKit

@MainActor
struct FineKeyed: Renderable {
    let key: AnyHashable
    let content: any Renderable

    func _makeView() -> UIView {
        content._makeView()
    }

    func _canUpdate(_ view: UIView) -> Bool {
        content._canUpdate(view)
    }

    func _update(_ view: UIView) {
        content._update(view)
    }

    var _modifierSignature: String {
        content._modifierSignature
    }

    var _key: AnyHashable? {
        key
    }
}

@MainActor
public func FineForEach<Element: Identifiable>(
    _ elements: [Element],
    content: @MainActor (Element) -> any Renderable
) -> [any Renderable] {
    elements.map { element in
        FineKeyed(key: AnyHashable(element.id), content: content(element))
    }
}
