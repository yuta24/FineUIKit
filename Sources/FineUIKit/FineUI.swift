//
//  FineUI.swift
//  FineUIKit
//
//  Created by nova on 2026/07/05.
//

import Observation
import UIKit

/// Drives a `Renderable` tree from an observable state object.
///
/// `FineUI` re-evaluates `body` whenever an `@Observable` property read
/// inside it changes, and applies the new description to the existing view
/// hierarchy in place.
///
/// Keep a strong reference to this object (e.g. in your view controller);
/// releasing it stops the render loop.
@MainActor
public final class FineUI<State> {
    private let state: State
    private let body: (State) -> any Renderable

    private weak var container: UIView?
    private var rootView: UIView?

    #if DEBUG
    // nonisolated(unsafe): only written on the main actor; deinit reads it
    // when no other references remain.
    private nonisolated(unsafe) var injectionObserver: (any NSObjectProtocol)?
    #endif

    public init(_ state: State, body: @escaping @MainActor (State) -> any Renderable) {
        self.state = state
        self.body = body
    }

    deinit {
        #if DEBUG
        if let injectionObserver {
            NotificationCenter.default.removeObserver(injectionObserver)
        }
        #endif
    }

    /// Renders the tree into `container` and starts observing `state`.
    public func build(to container: UIView) {
        self.container = container
        render()

        #if DEBUG
        observeInjection()
        #endif
    }

    #if DEBUG
    /// Re-renders after a code injection (InjectionIII / InjectionNext /
    /// InjectionLite) so updated component implementations take effect.
    /// Note: `body` itself is a closure captured at init; to pick up changes
    /// to the body's source, recreate the `FineUI` from the injection
    /// notification in your view controller.
    private func observeInjection() {
        guard injectionObserver == nil else { return }

        injectionObserver = NotificationCenter.default.addObserver(
            forName: .init("INJECTION_BUNDLE_NOTIFICATION"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.render()
            }
        }
    }
    #endif

    private func render() {
        guard let container else { return }

        // Render inside the tracking closure: component content closures
        // (e.g. FineStack's children) read state lazily during _update, and
        // those reads must be tracked too.
        let view = withObservationTracking {
            FineRenderer.render(body(state), reusing: rootView)
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.render()
            }
        }
        guard view !== rootView else { return }

        rootView?.removeFromSuperview()
        rootView = view

        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)

        let guide = container.safeAreaLayoutGuide

        // Text-like content (hugging priority 251+) keeps its natural height;
        // views with no intrinsic height (lists, images) expand to fill.
        let fillBottom = view.bottomAnchor.constraint(equalTo: guide.bottomAnchor)
        fillBottom.priority = .defaultLow

        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: guide.topAnchor),
            view.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
            view.bottomAnchor.constraint(lessThanOrEqualTo: guide.bottomAnchor),
            fillBottom,
        ])
    }
}
