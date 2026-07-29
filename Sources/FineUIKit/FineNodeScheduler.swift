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
        state.primitiveType = type(of: primitive._viewProvider)
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
                      view.fineNodeIfPresent?.generation == generation,
                      renderGate?.allowsObservedWork() != false
                else { return }

                let transaction = FineTransactionContext.current
                if case .animate(let animation) = transaction {
                    animation.animate {
                        self.enqueueExisting(view)
                        self.drain()
                        view.layoutIfNeeded()
                    }
                } else {
                    self.enqueueExisting(view)
                    self.drain()
                }
            }
        }
        signposter.endInterval("node", interval)

        FineDiagnostics.recordRender(of: view, as: kind)
    }
}
