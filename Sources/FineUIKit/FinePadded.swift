//
//  FinePadded.swift
//  FineUIKit
//
//  Created by nova on 2026/07/06.
//

import UIKit

@MainActor
final class FinePaddingView: UIView {
    var hosted: UIView?
    var topConstraint: NSLayoutConstraint?
    var leadingConstraint: NSLayoutConstraint?
    var bottomConstraint: NSLayoutConstraint?
    var trailingConstraint: NSLayoutConstraint?
}

@MainActor
struct FinePadded: Renderable {
    let content: any Renderable
    let insets: NSDirectionalEdgeInsets

    func _makeView() -> UIView {
        FinePaddingView(frame: .zero)
    }

    func _canUpdate(_ view: UIView) -> Bool {
        view is FinePaddingView
    }

    func _update(_ view: UIView) {
        guard let paddingView = view as? FinePaddingView else { return }

        let hosted = FineRenderer.render(content, reusing: paddingView.hosted)

        if hosted !== paddingView.hosted {
            NSLayoutConstraint.deactivate([
                paddingView.topConstraint,
                paddingView.leadingConstraint,
                paddingView.bottomConstraint,
                paddingView.trailingConstraint,
            ].compactMap { $0 })
            paddingView.hosted?.removeFromSuperview()
            paddingView.hosted = hosted

            hosted.translatesAutoresizingMaskIntoConstraints = false
            paddingView.addSubview(hosted)

            paddingView.topConstraint = hosted.topAnchor.constraint(equalTo: paddingView.topAnchor, constant: insets.top)
            paddingView.leadingConstraint = hosted.leadingAnchor.constraint(equalTo: paddingView.leadingAnchor, constant: insets.leading)
            paddingView.bottomConstraint = paddingView.bottomAnchor.constraint(equalTo: hosted.bottomAnchor, constant: insets.bottom)
            paddingView.trailingConstraint = paddingView.trailingAnchor.constraint(equalTo: hosted.trailingAnchor, constant: insets.trailing)

            NSLayoutConstraint.activate([
                paddingView.topConstraint,
                paddingView.leadingConstraint,
                paddingView.bottomConstraint,
                paddingView.trailingConstraint,
            ].compactMap { $0 })
        }

        paddingView.topConstraint?.constant = insets.top
        paddingView.leadingConstraint?.constant = insets.leading
        paddingView.bottomConstraint?.constant = insets.bottom
        paddingView.trailingConstraint?.constant = insets.trailing
    }

    var _modifierSignature: String {
        "padding"
    }

    var _key: AnyHashable? {
        content._key
    }
}
