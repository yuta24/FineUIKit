//
//  FineNodeScheduler.swift
//  FineUIKit
//
//  Created by nova on 2026/07/07.
//

import Observation
import UIKit

@MainActor
final class FineNodeScheduler {
    private struct Job {
        weak var view: UIView?
        let generation: Int
        let primitive: any FinePrimitiveRenderable
        let context: FineRenderContext
    }

    private var queue: [Job] = []
    private var isDraining = false
    private var isInvalidated = false

    /// Runs after a change re-rendered one of this scheduler's nodes on its
    /// own. A list or grid cell uses it to re-measure: a node-local update
    /// never passes through the host, which is what normally notices that the
    /// row no longer fits its height.
    var onObservedUpdate: (@MainActor () -> Void)?

    /// Whether a change that arrives while the tree is suspended must be
    /// recovered by this scheduler rather than by the catch-up render.
    ///
    /// `false` for the scheduler that belongs to the view tree: `resume()`
    /// renders it whole, and that walk re-registers every scope it passes.
    /// `true` for a cell's, which that walk only reaches if the row happens to
    /// be reconfigured — an unchanged element is not, and the row would stay
    /// stale with its observation gone.
    var recoversSuspendedWork = false

    /// Stops this scheduler's nodes from acting on changes.
    ///
    /// A recycled cell keeps its views for the next row, and the scopes
    /// registered for the previous one are still armed. Invalidating the
    /// scheduler retires all of them at once, rather than walking the subtree
    /// to bump every node's generation.
    func invalidate() {
        isInvalidated = true
    }

    func renderChild(_ node: any Renderable, reusing existing: UIView?, context: FineRenderContext) -> UIView {
        renderChild(resolved: FineRenderer.primitive(for: node), reusing: existing, context: context)
    }

    func renderChild(
        resolved primitive: any FinePrimitiveRenderable,
        reusing existing: UIView?,
        context: FineRenderContext
    ) -> UIView {
        // Read once and reuse: both walk `body` down to the content primitive,
        // so asking twice re-evaluates the description.
        let signature = primitive._modifierSignature
        let key = primitive._key
        let view: UIView
        let kind: FineDiagnostics.RenderKind

        if let existing, FineRenderer.reuses(existing, for: primitive, signature: signature, key: key) {
            view = existing
            kind = .updated
        } else {
            existing?.fineNodeIfPresent?.generation += 1
            view = primitive._makeView()
            FineDiagnostics.carryCounters(from: existing, to: view)
            kind = existing == nil ? .created : .rebuilt
        }

        view.fineModifierSignature = signature
        view.fineKey = key

        let state = view.fineNode
        state.primitive = primitive
        state.noteRender(of: primitive)
        state.context = context
        state.generation += 1
        // The update this enqueues does the counting, because a node-local
        // re-render reaches it without passing through here.
        state.pendingRenderKind = kind

        enqueue(view: view, generation: state.generation, primitive: primitive, context: context)
        return view
    }

    func drain() {
        guard !isDraining else { return }

        isDraining = true
        defer { isDraining = false }

        // Reading through the queue instead of removing from its front: a job
        // enqueues its children as it runs, so the queue grows while it is
        // consumed, and repeated `removeFirst()` would shift the remainder on
        // every step.
        var readIndex = 0
        while readIndex < queue.count {
            let job = queue[readIndex]
            readIndex += 1
            run(job)
        }
        queue.removeAll(keepingCapacity: true)
    }

    private func enqueue(
        view: UIView,
        generation: Int,
        primitive: any FinePrimitiveRenderable,
        context: FineRenderContext
    ) {
        queue.append(.init(view: view, generation: generation, primitive: primitive, context: context))
    }

    private func enqueueExisting(_ view: UIView) {
        guard let state = view.fineNodeIfPresent,
              let primitive = state.primitive,
              let context = state.context
        else { return }

        state.generation += 1
        enqueue(view: view, generation: state.generation, primitive: primitive, context: context)
    }

    private func run(_ job: Job) {
        guard let view = job.view,
              view.fineNodeIfPresent?.generation == job.generation
        else { return }

        let generation = job.generation
        let renderGate = job.context.renderGate
        let kind = view.fineNodeIfPresent?.takePendingRenderKind() ?? .updated

        let signposter = FineSignpost.signposter
        let interval = signposter.beginInterval(
            "node",
            id: signposter.makeSignpostID(),
            "\(view.fineNodeIfPresent?.primitiveName ?? "unknown", privacy: .public)"
        )
        withObservationTracking {
            job.primitive._update(view, context: job.context)
        } onChange: { [weak self, weak view] in
            Task { @MainActor in
                guard let self,
                      let view,
                      !self.isInvalidated,
                      view.fineNodeIfPresent?.generation == generation
                else { return }

                guard let renderGate, renderGate.isSuspended else {
                    self.applyObservedUpdate(to: view)
                    return
                }

                self.deferObservedUpdate(to: view, generation: generation, gate: renderGate)
            }
        }
        signposter.endInterval("node", interval)

        FineDiagnostics.recordRender(of: view, as: kind)
    }

    /// Holds a change that arrived while the tree is off screen.
    ///
    /// A scheduler that belongs to the view tree only records that a flush is
    /// owed: the catch-up render walks the tree and re-registers this scope
    /// along with everything else. One that has to recover for itself hands in
    /// its own work instead — and deliberately does not ask for the whole-tree
    /// render, which a change confined to one cell has no use for.
    private func deferObservedUpdate(to view: UIView, generation: Int, gate: FineRenderGate) {
        guard recoversSuspendedWork else {
            _ = gate.allowsObservedWork()
            return
        }

        gate.deferObservedWork { [weak self, weak view] in
            guard let self,
                  let view,
                  !self.isInvalidated,
                  view.fineNodeIfPresent?.generation == generation
            else { return }

            self.applyObservedUpdate(to: view)
        }
    }

    private func applyObservedUpdate(to view: UIView) {
        if case .animate(let animation) = FineTransactionContext.current {
            animation.animate {
                self.enqueueExisting(view)
                self.drain()
                view.layoutIfNeeded()
            }
        } else {
            enqueueExisting(view)
            drain()
        }

        onObservedUpdate?()
    }
}
