//
//  FineFramed.swift
//  FineUIKit
//
//  Created by nova on 2026/07/06.
//

import UIKit

@MainActor
final class FineFrameView: UIView {
    var hosted: UIView?
    var topConstraint: NSLayoutConstraint?
    var leadingConstraint: NSLayoutConstraint?
    var bottomConstraint: NSLayoutConstraint?
    var trailingConstraint: NSLayoutConstraint?
    var widthConstraint: NSLayoutConstraint?
    var heightConstraint: NSLayoutConstraint?
}

@MainActor
struct FineFramed: Renderable {
    let content: any Renderable
    let width: CGFloat?
    let height: CGFloat?

    func _makeView() -> UIView {
        FineFrameView(frame: .zero)
    }

    func _canUpdate(_ view: UIView) -> Bool {
        view is FineFrameView
    }

    func _update(_ view: UIView) {
        guard let frameView = view as? FineFrameView else { return }

        let hosted = FineRenderer.render(content, reusing: frameView.hosted)

        if hosted !== frameView.hosted {
            NSLayoutConstraint.deactivate([
                frameView.topConstraint,
                frameView.leadingConstraint,
                frameView.bottomConstraint,
                frameView.trailingConstraint,
            ].compactMap { $0 })
            frameView.hosted?.removeFromSuperview()
            frameView.hosted = hosted

            hosted.translatesAutoresizingMaskIntoConstraints = false
            frameView.addSubview(hosted)

            frameView.topConstraint = hosted.topAnchor.constraint(equalTo: frameView.topAnchor)
            frameView.leadingConstraint = hosted.leadingAnchor.constraint(equalTo: frameView.leadingAnchor)
            frameView.bottomConstraint = frameView.bottomAnchor.constraint(equalTo: hosted.bottomAnchor)
            frameView.trailingConstraint = frameView.trailingAnchor.constraint(equalTo: hosted.trailingAnchor)

            NSLayoutConstraint.activate([
                frameView.topConstraint,
                frameView.leadingConstraint,
                frameView.bottomConstraint,
                frameView.trailingConstraint,
            ].compactMap { $0 })
        }

        updateDimension(&frameView.widthConstraint, on: frameView.widthAnchor, value: width)
        updateDimension(&frameView.heightConstraint, on: frameView.heightAnchor, value: height)
    }

    var _modifierSignature: String {
        "frame"
    }

    private func updateDimension(_ constraint: inout NSLayoutConstraint?, on anchor: NSLayoutDimension, value: CGFloat?) {
        guard let value else {
            constraint?.isActive = false
            return
        }

        if let constraint {
            constraint.constant = value
            constraint.isActive = true
        } else {
            constraint = anchor.constraint(equalToConstant: value)
            constraint?.isActive = true
        }
    }
}
