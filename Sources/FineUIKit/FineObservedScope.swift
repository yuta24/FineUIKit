//
//  FineObservedScope.swift
//  FineUIKit
//
//  Created by nova on 2026/07/25.
//

import Observation
import UIKit

/// Re-runs a closure under its own `withObservationTracking` scope.
///
/// `withObservationTracking` is one-shot, so the scope re-registers by
/// re-running itself after each change. Work that reads observable state but
/// does not belong to the view tree — applying `navigationItem` properties, for
/// example — gets its own scope this way, instead of riding along in the root
/// `body` scope where every read would invalidate the whole tree.
@MainActor
final class FineObservedScope {
    private let body: @MainActor () -> Void
    private var generation = 0

    init(_ body: @escaping @MainActor () -> Void) {
        self.body = body
    }

    /// Runs the closure and re-registers observation for the values it reads.
    func run() {
        generation += 1
        let expectedGeneration = generation

        withObservationTracking {
            body()
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self,
                      self.generation == expectedGeneration
                else { return }

                self.run()
            }
        }
    }
}
