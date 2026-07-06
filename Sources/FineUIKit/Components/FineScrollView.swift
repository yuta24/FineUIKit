//
//  FineScrollView.swift
//  FineUIKit
//
//  Created by nova on 2026/07/06.
//

import UIKit

@MainActor
final class FineScrollHostView: UIScrollView {
    var hosted: UIView?
    var hostConstraints: [NSLayoutConstraint] = []
}

@MainActor
public struct FineScrollView: Renderable {
    private let axis: NSLayoutConstraint.Axis
    private let content: @MainActor () -> any Renderable

    /// Creates a scroll container. Avoid nesting `FineList` or `FineGrid`
    /// inside it because those components already manage their own scrolling.
    public init(_ axis: NSLayoutConstraint.Axis = .vertical, content: @escaping @MainActor () -> any Renderable) {
        self.axis = axis
        self.content = content
    }

    public func _makeView() -> UIView {
        FineScrollHostView(frame: .zero)
    }

    public func _canUpdate(_ view: UIView) -> Bool {
        view is FineScrollHostView
    }

    public func _update(_ view: UIView) {
        guard let scrollView = view as? FineScrollHostView else { return }

        let hosted = FineRenderer.render(content(), reusing: scrollView.hosted)

        if hosted !== scrollView.hosted {
            NSLayoutConstraint.deactivate(scrollView.hostConstraints)
            scrollView.hosted?.removeFromSuperview()
            scrollView.hosted = hosted

            hosted.translatesAutoresizingMaskIntoConstraints = false
            scrollView.addSubview(hosted)

            var constraints = [
                hosted.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
                hosted.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
                hosted.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
                hosted.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            ]

            switch axis {
            case .horizontal:
                constraints.append(hosted.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor))
            case .vertical:
                constraints.append(hosted.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor))
            @unknown default:
                constraints.append(hosted.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor))
            }

            scrollView.hostConstraints = constraints
            NSLayoutConstraint.activate(constraints)
        }
    }

    public var _modifierSignature: String {
        switch axis {
        case .horizontal:
            "scroll.h"
        case .vertical:
            "scroll.v"
        @unknown default:
            "scroll.?"
        }
    }
}
