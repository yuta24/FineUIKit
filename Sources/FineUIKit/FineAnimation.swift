//
//  FineAnimation.swift
//  FineUIKit
//
//  Created by nova on 2026/07/07.
//

import UIKit

public struct FineAnimation: Sendable {
    enum Timing: Sendable {
        case curve(Curve, duration: TimeInterval)
        case spring(duration: TimeInterval, bounce: CGFloat)
    }

    enum Curve: Sendable {
        case linear
        case easeIn
        case easeOut
        case easeInOut
    }

    var timing: Timing
    var delay: TimeInterval = 0

    public static let `default` = FineAnimation.easeInOut()

    public static func linear(duration: TimeInterval = 0.3) -> FineAnimation {
        .init(timing: .curve(.linear, duration: duration))
    }

    public static func easeIn(duration: TimeInterval = 0.3) -> FineAnimation {
        .init(timing: .curve(.easeIn, duration: duration))
    }

    public static func easeOut(duration: TimeInterval = 0.3) -> FineAnimation {
        .init(timing: .curve(.easeOut, duration: duration))
    }

    public static func easeInOut(duration: TimeInterval = 0.3) -> FineAnimation {
        .init(timing: .curve(.easeInOut, duration: duration))
    }

    public static func spring(duration: TimeInterval = 0.5, bounce: CGFloat = 0.15) -> FineAnimation {
        .init(timing: .spring(duration: duration, bounce: bounce))
    }

    public func delay(_ delay: TimeInterval) -> FineAnimation {
        var copy = self
        copy.delay = delay
        return copy
    }

    @MainActor
    func animate(_ changes: @MainActor @escaping () -> Void) {
        switch timing {
        case .curve(let curve, let duration):
            UIView.animate(
                withDuration: duration,
                delay: delay,
                options: curve.animationOptions,
                animations: changes
            )
        case .spring(let duration, let bounce):
            UIView.animate(
                springDuration: duration,
                bounce: bounce,
                initialSpringVelocity: 0,
                delay: delay,
                options: [],
                animations: changes
            )
        }
    }
}

@MainActor
@discardableResult
public func withFineAnimation<Result>(
    _ animation: FineAnimation? = .default,
    _ body: () throws -> Result
) rethrows -> Result {
    try FineTransactionContext.$current.withValue(
        animation.map { .animate($0) } ?? .disabled,
        operation: body
    )
}

enum FineTransactionValue: Sendable {
    case animate(FineAnimation)
    case disabled
}

enum FineTransactionContext {
    @TaskLocal static var current: FineTransactionValue?

    static func allowsDiffAnimation(inWindow: Bool) -> Bool {
        switch current {
        case .disabled:
            false
        default:
            inWindow
        }
    }
}

private extension FineAnimation.Curve {
    var animationOptions: UIView.AnimationOptions {
        switch self {
        case .linear:
            .curveLinear
        case .easeIn:
            .curveEaseIn
        case .easeOut:
            .curveEaseOut
        case .easeInOut:
            .curveEaseInOut
        }
    }
}
