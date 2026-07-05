//
//  FineImage.swift
//  FineUIKit
//
//  Created by nova on 2026/07/05.
//

import UIKit

@MainActor
public struct FineImage: Renderable {
    private let image: UIImage

    public init(image: UIImage) {
        self.image = image
    }

    public func _makeView() -> UIView {
        UIImageView(frame: .zero)
    }

    public func _canUpdate(_ view: UIView) -> Bool {
        view is UIImageView
    }

    public func _update(_ view: UIView) {
        guard let imageView = view as? UIImageView else { return }

        imageView.image = image
    }
}
