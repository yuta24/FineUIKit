//
//  FineImage.swift
//  FineUIKit
//
//  Created by nova on 2026/07/05.
//

import UIKit

@MainActor
public struct FineImage: FinePrimitiveRenderable {
    private let image: UIImage

    public var body: any Renderable {
        fatalError("Primitive Renderable body should not be evaluated")
    }

    public init(image: UIImage) {
        self.image = image
    }

    func _makeView() -> UIView {
        UIImageView(frame: .zero)
    }

    func _canUpdate(_ view: UIView) -> Bool {
        view is UIImageView
    }

    func _update(_ view: UIView, context: FineRenderContext) {
        guard let imageView = view as? UIImageView else { return }

        if imageView.image !== image {
            imageView.image = image
        }
    }
}
