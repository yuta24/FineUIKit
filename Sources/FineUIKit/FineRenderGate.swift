//
//  FineRenderGate.swift
//  FineUIKit
//
//  Created by nova on 2026/07/25.
//

import UIKit

/// Decides whether observation-driven work may run right now.
///
/// A tree that is off screen still receives observation callbacks, and acting
/// on them re-diffs a hierarchy nobody can see. While suspended, the gate
/// swallows that work and records that a flush is owed; `resume()` performs one
/// render that brings the tree up to date with the current state.
///
/// Only observation-driven work passes through the gate. The initial render is
/// always performed, so a tree built into a detached view still has content.
@MainActor
final class FineRenderGate {
    private(set) var isSuspended = false
    private var needsFlush = false
    private var deferredWork: [@MainActor () -> Void] = []

    /// Performs the deferred catch-up render. Set by the owning runtime.
    var onFlush: (@MainActor () -> Void)?

    /// Whether observation-driven work may run now.
    ///
    /// Returns `false` while suspended, recording that `resume()` must flush.
    func allowsObservedWork() -> Bool {
        guard isSuspended else { return true }

        needsFlush = true
        return false
    }

    /// Records work that `resume()` must run in addition to the catch-up render.
    ///
    /// A suppressed scope is no longer registered for observation, and the
    /// catch-up render only re-establishes the scopes it walks. List and grid
    /// cells are not among them: their content re-runs only when the diffable
    /// data source reconfigures the row, which an unchanged element does not.
    /// Such a scope hands in its own recovery here.
    ///
    /// Recovery closures run after the catch-up render and must tolerate having
    /// become unnecessary in the meantime.
    func deferObservedWork(_ work: @escaping @MainActor () -> Void) {
        deferredWork.append(work)
    }

    func suspend() {
        isSuspended = true
    }

    /// Resumes work, rendering once if anything was skipped while suspended.
    func resume() {
        guard isSuspended else { return }

        isSuspended = false

        let flushes = needsFlush
        let work = deferredWork
        needsFlush = false
        deferredWork = []

        // Animating changes that happened off screen is not meaningful, and it
        // would be visible: a list applies its snapshot with animation whenever
        // no transaction says otherwise, so rows added while hidden would slide
        // in on the way back.
        // The catch-up render answers for a change observed while nobody was
        // looking, and says so: left to the default it would report that its
        // parent re-rendered, and there is nothing above the root.
        //
        // The recoveries handed in by scopes are not given one. Each already
        // knows why it is running — a node's tells its own node directly, and a
        // cell host's re-render declares itself — so a reason offered here
        // would go unclaimed by the node it was meant for and be picked up by
        // the first child it renders, which is there because its parent ran and
        // for no other reason.
        FineTransactionContext.$current.withValue(.disabled) {
            if flushes {
                FineDiagnostics.rendering(because: .observation) {
                    onFlush?()
                }
            }
            for item in work {
                item()
            }
        }
    }
}
