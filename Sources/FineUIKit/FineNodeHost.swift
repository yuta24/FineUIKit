//
//  FineNodeHost.swift
//  FineUIKit
//
//  Created by nova on 2026/07/12.
//

import Observation
import UIKit

/// Shared render loop for UIKit views that host a `Renderable` subtree under
/// local observation tracking: list/grid cells and their supplementary views.
///
/// Values read while rendering — including the coordinator's environment —
/// are tracked; when they change, only this host re-renders, honoring any
/// active `withFineAnimation` transaction. `onObservedRerender` runs after
/// such an observation-driven re-render (not the initial one) so the owner
/// can invalidate sizing.
@MainActor
final class FineNodeHost {
    private(set) var hostedView: UIView?
    private var makeNode: (@MainActor () -> any Renderable)?
    private var environment: FineEnvironmentStorage?
    private var generation = 0

    private weak var owner: UIView?
    private let attach: @MainActor (UIView) -> Void

    var onObservedRerender: (@MainActor () -> Void)?

    /// - Parameters:
    ///   - owner: The hosting view; laid out inside animated re-renders.
    ///   - attach: Adds a newly created hosted view into the owner's
    ///     hierarchy and installs its constraints.
    init(owner: UIView, attach: @escaping @MainActor (UIView) -> Void) {
        self.owner = owner
        self.attach = attach
    }

    /// Stops pending re-renders; the hosted view stays for reuse.
    func invalidate() {
        makeNode = nil
        generation += 1
    }

    /// Stops pending re-renders and tears down the hosted view, so a recycled
    /// host that is returned without a render shows no stale content.
    func reset() {
        invalidate()
        hostedView?.removeFromSuperview()
        hostedView = nil
    }

    func render(environment: FineEnvironmentStorage, _ makeNode: @escaping @MainActor () -> any Renderable) {
        self.makeNode = makeNode
        self.environment = environment
        renderTracked()
    }

    private func renderTracked() {
        generation += 1
        let expectedGeneration = generation
        guard let makeNode else { return }

        let transaction = FineTransactionContext.current
        let apply = { [self] in
            withObservationTracking {
                // Reading environment values inside the tracked scope
                // registers them, so an environment change re-renders this
                // host with the current values.
                let context = FineRenderContext(environment: environment?.values ?? .init())
                return context.render(makeNode(), reusing: self.hostedView)
            } onChange: { [weak self] in
                Task { @MainActor in
                    guard let self,
                          self.generation == expectedGeneration,
                          self.makeNode != nil
                    else { return }

                    self.renderTracked()
                    self.onObservedRerender?()
                }
            }
        }

        let view: UIView
        if case .animate(let animation) = transaction, hostedView != nil {
            var rendered: UIView!
            animation.animate {
                rendered = apply()
                self.owner?.layoutIfNeeded()
            }
            view = rendered
        } else {
            view = apply()
        }

        guard view !== hostedView else { return }

        hostedView?.removeFromSuperview()
        hostedView = view

        view.translatesAutoresizingMaskIntoConstraints = false
        attach(view)
    }
}
