//
//  FineFramed.swift
//  FineUIKit
//
//  Created by nova on 2026/07/06.
//

import UIKit

public enum FineAlignment {
    case center
    case leading
    case trailing
    case top
    case bottom
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing
    case fill
}

@MainActor
final class FineFrameView: UIView {
    var hosted: UIView?
    var hostConstraints: [NSLayoutConstraint] = []
    var widthConstraint: NSLayoutConstraint?
    var heightConstraint: NSLayoutConstraint?
}

@MainActor
struct FineFramed: Renderable {
    let content: any Renderable
    let width: CGFloat?
    let height: CGFloat?
    let alignment: FineAlignment

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
            NSLayoutConstraint.deactivate(frameView.hostConstraints)
            frameView.hosted?.removeFromSuperview()
            frameView.hosted = hosted

            hosted.translatesAutoresizingMaskIntoConstraints = false
            frameView.addSubview(hosted)

            frameView.hostConstraints = makeHostConstraints(hosted: hosted, in: frameView)
            NSLayoutConstraint.activate(frameView.hostConstraints)
        }

        updateDimension(&frameView.widthConstraint, on: frameView.widthAnchor, value: width)
        updateDimension(&frameView.heightConstraint, on: frameView.heightAnchor, value: height)
    }

    var _modifierSignature: String {
        "frame.\(alignment.fineKey)"
    }

    var _key: AnyHashable? {
        content._key
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

    private func makeHostConstraints(hosted: UIView, in frameView: FineFrameView) -> [NSLayoutConstraint] {
        guard alignment != .fill else {
            return [
                hosted.topAnchor.constraint(equalTo: frameView.topAnchor),
                hosted.leadingAnchor.constraint(equalTo: frameView.leadingAnchor),
                frameView.bottomAnchor.constraint(equalTo: hosted.bottomAnchor),
                frameView.trailingAnchor.constraint(equalTo: hosted.trailingAnchor),
            ]
        }

        var constraints = [
            hosted.topAnchor.constraint(greaterThanOrEqualTo: frameView.topAnchor),
            hosted.leadingAnchor.constraint(greaterThanOrEqualTo: frameView.leadingAnchor),
            frameView.bottomAnchor.constraint(greaterThanOrEqualTo: hosted.bottomAnchor),
            frameView.trailingAnchor.constraint(greaterThanOrEqualTo: hosted.trailingAnchor),
        ]

        switch alignment {
        case .center:
            constraints.append(hosted.centerXAnchor.constraint(equalTo: frameView.centerXAnchor))
            constraints.append(hosted.centerYAnchor.constraint(equalTo: frameView.centerYAnchor))
        case .leading:
            constraints.append(hosted.leadingAnchor.constraint(equalTo: frameView.leadingAnchor))
            constraints.append(hosted.centerYAnchor.constraint(equalTo: frameView.centerYAnchor))
        case .trailing:
            constraints.append(frameView.trailingAnchor.constraint(equalTo: hosted.trailingAnchor))
            constraints.append(hosted.centerYAnchor.constraint(equalTo: frameView.centerYAnchor))
        case .top:
            constraints.append(hosted.topAnchor.constraint(equalTo: frameView.topAnchor))
            constraints.append(hosted.centerXAnchor.constraint(equalTo: frameView.centerXAnchor))
        case .bottom:
            constraints.append(frameView.bottomAnchor.constraint(equalTo: hosted.bottomAnchor))
            constraints.append(hosted.centerXAnchor.constraint(equalTo: frameView.centerXAnchor))
        case .topLeading:
            constraints.append(hosted.topAnchor.constraint(equalTo: frameView.topAnchor))
            constraints.append(hosted.leadingAnchor.constraint(equalTo: frameView.leadingAnchor))
        case .topTrailing:
            constraints.append(hosted.topAnchor.constraint(equalTo: frameView.topAnchor))
            constraints.append(frameView.trailingAnchor.constraint(equalTo: hosted.trailingAnchor))
        case .bottomLeading:
            constraints.append(frameView.bottomAnchor.constraint(equalTo: hosted.bottomAnchor))
            constraints.append(hosted.leadingAnchor.constraint(equalTo: frameView.leadingAnchor))
        case .bottomTrailing:
            constraints.append(frameView.bottomAnchor.constraint(equalTo: hosted.bottomAnchor))
            constraints.append(frameView.trailingAnchor.constraint(equalTo: hosted.trailingAnchor))
        case .fill:
            break
        }

        return constraints
    }
}

private extension FineAlignment {
    var fineKey: String {
        switch self {
        case .center:
            "center"
        case .leading:
            "leading"
        case .trailing:
            "trailing"
        case .top:
            "top"
        case .bottom:
            "bottom"
        case .topLeading:
            "topLeading"
        case .topTrailing:
            "topTrailing"
        case .bottomLeading:
            "bottomLeading"
        case .bottomTrailing:
            "bottomTrailing"
        case .fill:
            "fill"
        }
    }
}
