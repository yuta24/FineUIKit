//
//  FineKeyed.swift
//  FineUIKit
//
//  Created by nova on 2026/07/06.
//

import UIKit

@MainActor
struct FineKeyed: FinePrimitiveRenderable {
    let key: AnyHashable
    let content: any Renderable

    func _makeView() -> UIView {
        FineRenderer.primitive(for: content)._makeView()
    }

    func _canUpdate(_ view: UIView) -> Bool {
        FineRenderer.primitive(for: content)._canUpdate(view)
    }

    func _update(_ view: UIView, context: FineRenderContext) {
        FineRenderer.primitive(for: content)._update(view, context: context)
    }

    var _modifierSignature: String {
        FineRenderer.primitive(for: content)._modifierSignature
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
