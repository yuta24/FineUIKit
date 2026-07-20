//
//  BindingScope.swift
//  FineUIKit
//
//  Part of the ground-up redesign (see redesign/positioning-and-rebuild).
//  This is the ONLY update mechanism the redesigned library provides: there
//  is no body, no Renderable tree, and no framework-owned identity layer.
//  A UIView is built once, by hand, and BindingScope wires specific
//  @Observable reads to specific property writes on that already-existing
//  view. The update granularity is exactly the set of `observe` closures the
//  caller writes -- never an implicit function of where a read happens.

import Observation

/// Runs a closure under `withObservationTracking` and re-subscribes after
/// each change, so it keeps tracking whichever `@Observable` properties it
/// reads on its *latest* run.
///
/// A `BindingScope` owns zero or more independent `observe` registrations.
/// Each one is its own update unit: a change to a property read only inside
/// closure A never re-runs closure B, even if both closures were registered
/// on the same scope. Splitting or merging `observe` calls is the only way
/// update granularity changes -- it is visible in the call site, not implied
/// by argument-passing style.
@MainActor
public final class BindingScope {
    private var isInvalidated = false

    public init() {}

    /// Registers a binding. Runs `action` synchronously once, then re-runs it
    /// whenever an `@Observable` property read during its last run changes.
    ///
    /// `action` is expected to write to UIKit view properties, typically
    /// guarded by ``fineAssign(_:_:_:)`` so re-running the closure for an
    /// unrelated change (or a write of an equal value) does not touch the
    /// view when nothing actually changed.
    public func observe(_ action: @escaping @MainActor () -> Void) {
        guard !isInvalidated else { return }

        withObservationTracking {
            action()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, !self.isInvalidated else { return }
                self.observe(action)
            }
        }
    }

    /// Stops all future re-subscription. A binding mid-flight when this is
    /// called still finishes its current run, but never re-subscribes
    /// afterward. Call this from the owning view's `deinit` or
    /// `prepareForReuse`.
    public func invalidate() {
        isInvalidated = true
    }
}
