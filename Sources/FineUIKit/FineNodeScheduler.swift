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
        let primitive = FineRenderer.primitive(for: node)
        let view: UIView

        if let existing,
           primitive._canUpdate(existing),
           existing.fineModifierSignature == primitive._modifierSignature,
           existing.fineKey == primitive._key {
            view = existing
        } else {
            existing?.fineNodeIfPresent?.generation += 1
            view = primitive._makeView()
        }

        view.fineModifierSignature = primitive._modifierSignature
        view.fineKey = primitive._key

        let state = view.fineNode
        state.primitive = primitive
        state.context = context
        state.generation += 1

        enqueue(view: view, generation: state.generation, primitive: primitive, context: context)
        return view
    }

    func drain() {
        guard !isDraining else { return }

        isDraining = true
        defer { isDraining = false }

        while !queue.isEmpty {
            let job = queue.removeFirst()
            run(job)
        }
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
        withObservationTracking {
            job.primitive._update(view, context: job.context)
        } onChange: { [weak self, weak view] in
            Task { @MainActor in
                guard let self,
                      let view,
                      view.fineNodeIfPresent?.generation == generation
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
    }
}
