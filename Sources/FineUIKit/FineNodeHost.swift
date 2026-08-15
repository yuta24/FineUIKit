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
    private var renderGate: FineRenderGate?
    private var generation = 0
    /// Owns the observation scopes of the nodes in the hosted subtree, so they
    /// can all be retired at once when the host is recycled.
    private var scheduler: FineNodeScheduler?
    /// What the hosted view is currently showing — a row's element, a section's
    /// header. Compared on every render so a recycled host can tell "the same
    /// thing again" from "something else in the same cell".
    private var identity: AnyHashable?

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
        // The hosted subtree's nodes hold observation scopes of their own, and
        // a recycled cell must not have one of them write the previous row's
        // content into it after the fact.
        scheduler?.invalidate()
        scheduler = nil

        // The host no longer points at a description, so nothing may still be
        // running on its behalf. A cell is recycled before anyone knows what it
        // will show next — and it may be shown nothing at all, when the
        // provider's bail-out path returns it unconfigured. Left alone, the
        // previous row's task would run on against the cell that replaced it,
        // and putting the cell back in a window would report that row as
        // having appeared a second time.
        //
        // The state itself is kept: the same row coming back is the ordinary
        // case, and its `FineState` is expected to survive that.
        if let hostedView {
            Self.discardIdentityState(in: hostedView, keepingLocalState: true)
        }
    }

    /// Stops pending re-renders and tears down the hosted view, so a recycled
    /// host that is returned without a render shows no stale content.
    func reset() {
        invalidate()
        identity = nil
        hostedView?.removeFromSuperview()
        hostedView = nil
    }

    /// - Parameter identity: What the hosted subtree is about to show. A
    ///   recycled host renders a different row into the views the previous one
    ///   left behind, which is the point of cell reuse — but identity-scoped
    ///   state must not come along for the ride, so a change here discards it.
    ///   Passing `nil` says there is nothing to compare and discards nothing;
    ///   a caller that has an identity should always pass it.
    func render(
        identity: AnyHashable?,
        environment: FineEnvironmentStorage,
        renderGate: FineRenderGate?,
        _ makeNode: @escaping @MainActor () -> any Renderable
    ) {
        if let hostedView, let identity, self.identity != identity {
            Self.discardIdentityState(in: hostedView, keepingLocalState: false)
        }

        self.identity = identity
        self.makeNode = makeNode
        self.environment = environment
        self.renderGate = renderGate
        renderTracked()
    }

    /// Drops the state a subtree holds on behalf of what it was showing,
    /// because it is about to show something else.
    ///
    /// The views themselves stay: reusing them is what makes a cell cheap, and
    /// reconciliation writes the new description over them. What cannot stay is
    /// state keyed to the thing the cell used to show — `FineState`, which
    /// would otherwise put a row the user expanded back on whichever row lands
    /// in that cell next, and the lifecycle a view is in the middle of, whose
    /// window never changes here and so would never end on its own.
    /// - Parameter keepingLocalState: `true` while the host is only parked —
    ///   recycled, but not yet told what it shows next. Work stops either way;
    ///   the state is only given up once something else is actually taking the
    ///   subtree over.
    private static func discardIdentityState(in view: UIView, keepingLocalState: Bool) {
        if keepingLocalState {
            (view as? any FineIdentityScopedView)?.fineStopIdentityWork()
        } else {
            view.fineNodeIfPresent?.localState = nil
            (view as? any FineIdentityScopedView)?.fineDiscardIdentityState()
        }

        for subview in view.subviews {
            discardIdentityState(in: subview, keepingLocalState: keepingLocalState)
        }
    }

    private func renderTracked() {
        generation += 1
        let expectedGeneration = generation
        guard let makeNode else { return }

        let transaction = FineTransactionContext.current
        let apply = { [self] in
            let signposter = FineSignpost.signposter
            let interval = signposter.beginInterval(
                "cell",
                id: signposter.makeSignpostID(),
                "\(self.hostedView?.fineNodeIfPresent?.primitiveName ?? "new", privacy: .public)"
            )
            defer { signposter.endInterval("cell", interval) }

            // The scopes the previous render registered are superseded by the
            // ones about to be registered, so they are retired first: otherwise
            // a change held while the tree was suspended could be recovered by
            // both the old node scope and this render.
            self.scheduler?.invalidate()

            // Each node in the hosted subtree gets an observation scope of its
            // own, the way the root tree's nodes do. Without this the row
            // shares one scope, and a value read by a single label rewrites
            // every view in the card.
            let scheduler = FineNodeScheduler()
            scheduler.recoversSuspendedWork = true
            scheduler.onObservedUpdate = { [weak self] in
                self?.onObservedRerender?()
            }
            self.scheduler = scheduler

            let (description, environmentValues) = withObservationTracking {
                // Reading environment values inside the tracked scope
                // registers them, so an environment change re-renders this
                // host with the current values.
                let values = self.environment?.values ?? FineEnvironmentValues()
                let primitive = FineRenderer.primitive(for: makeNode())
                // The hosted root's own reuse identity is asked for by the
                // scheduler, which runs outside every scope. Same reason the
                // root render primes it: see `FineRenderer.prime(_:)`.
                FineRenderer.prime(primitive)
                return (primitive, values)
            } onChange: { [weak self] in
                Task { @MainActor in
                    guard let self,
                          self.generation == expectedGeneration,
                          self.makeNode != nil
                    else { return }

                    // Asking `isSuspended` rather than `allowsObservedWork()`
                    // deliberately does not ask for a catch-up render: this host
                    // recovers on its own below, and a cell-local change has no
                    // reason to re-diff the whole tree at `resume()`.
                    if let renderGate = self.renderGate, renderGate.isSuspended {
                        // This scope is now unregistered, and the catch-up
                        // render reaches a cell only when its row reconfigures,
                        // which an unchanged element does not. Recover here
                        // instead — unless something else re-rendered this host
                        // first, which the generation check detects.
                        renderGate.deferObservedWork { [weak self] in
                            guard let self,
                                  self.generation == expectedGeneration,
                                  self.makeNode != nil
                            else { return }

                            self.renderTracked()
                            self.onObservedRerender?()
                        }
                        return
                    }

                    self.renderTracked()
                    self.onObservedRerender?()
                }
            }

            let context = FineRenderContext(
                nodeScheduler: scheduler,
                renderGate: self.renderGate,
                environment: environmentValues
            )
            let rendered = context.render(resolved: description, reusing: self.hostedView)
            scheduler.drain()
            return rendered
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
