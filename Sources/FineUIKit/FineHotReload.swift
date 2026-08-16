//
//  FineHotReload.swift
//  FineUIKit
//
//  Created by nova on 2026/08/16.
//

#if DEBUG
import Foundation

/// What a hot-reload backend has to report.
///
/// One case today, and the type exists anyway: a backend that could only say
/// "something happened" would leave the runtime deciding what that meant from
/// which backend was installed, which is exactly the coupling this seam is for.
enum FineReloadEvent: Sendable {
    /// Replacement code landed in the process. Everything the runtime rebuilds
    /// by calling a symbol — `FineContent.body()`, a `Renderable`'s `body`,
    /// `navigation()` — may now do something different, so the tree renders
    /// again.
    case codeInjected
}

/// Where "the code changed" comes from.
///
/// The runtime knows a reload happened; it deliberately does not know who said
/// so. InjectionIII, InjectionNext and InjectionLite happen to agree on one
/// notification name today, but that is their convention rather than ours, and
/// the surrounding toolchain has broken often enough to be worth keeping at
/// arm's length (`docs/hot-reload.md`). Behind a protocol, adopting a different
/// mechanism is a new conformance instead of an edit to the render loop.
///
/// DEBUG only. A release build has nothing to reload, and no reason to carry
/// the machinery.
@MainActor
protocol FineHotReloadBackend: AnyObject {
    /// Begins watching for reloads.
    ///
    /// Must be idempotent: a tree built into a second container moves rather
    /// than mounts again, and calling `start()` twice must not make one reload
    /// arrive twice.
    func start()

    /// A stream of the reloads seen from now on.
    ///
    /// A function rather than a property because **every caller gets one of its
    /// own, and every reload reaches all of them**. One shared `AsyncStream`
    /// would not do: it hands each element to a single iterator, so two trees
    /// sharing a backend would divide the reloads between them and whichever
    /// one lost would go on running code that was just replaced — silently,
    /// which is the failure mode hot reload already has too much of.
    ///
    /// Call before `start()` so a backend that reports something immediately
    /// has somewhere to report it.
    func events() -> AsyncStream<FineReloadEvent>
}

/// The backend that ships: the notification the injection tools already post.
///
/// `INJECTION_BUNDLE_NOTIFICATION` is what InjectionIII, InjectionNext and
/// InjectionLite each post once they have loaded a rebuilt dylib. Nothing links
/// against any of them — the name is the whole contract — so an app with none
/// of them installed simply never hears anything, which is what a hot-reload
/// backend should do when there is no hot reload.
///
/// One instance per tree is the default, and sharing one across trees works:
/// each tree gets its own stream and every reload reaches all of them.
@MainActor
final class FineNotificationHotReloadBackend: FineHotReloadBackend {
    /// The name every current injection tool posts. Changing it silently turns
    /// hot reload off, so it is pinned by a test.
    static let injectionNotificationName = Notification.Name("INJECTION_BUNDLE_NOTIFICATION")

    private let center: NotificationCenter
    private let name: Notification.Name
    private var consumers: [UUID: AsyncStream<FineReloadEvent>.Continuation] = [:]

    // nonisolated(unsafe): only written on the main actor; deinit reads it when
    // no other reference to this object remains.
    private nonisolated(unsafe) var observer: (any NSObjectProtocol)?

    /// How many streams are still being consumed. A consumer that goes away
    /// has to take its registration with it, or a backend outliving a screen
    /// would accumulate one per screen that ever existed.
    var consumerCount: Int {
        consumers.count
    }

    /// - Parameter name: Overridable so a test can drive one backend instead of
    ///   broadcasting to every tree alive in the process.
    init(
        center: NotificationCenter = .default,
        name: Notification.Name = FineNotificationHotReloadBackend.injectionNotificationName
    ) {
        self.center = center
        self.name = name
    }

    deinit {
        if let observer {
            center.removeObserver(observer)
        }
    }

    func start() {
        guard observer == nil else { return }

        // `queue: .main` because everything downstream of a reload is main-actor
        // work, and the tools post from whichever thread finished the rebuild.
        // `assumeIsolated` rather than a hop through `Task { @MainActor }`:
        // delivery is already on the main thread, and an extra turn would put
        // more distance between the notification and the render than the code
        // this replaced had.
        observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.report(.codeInjected)
            }
        }
    }

    func events() -> AsyncStream<FineReloadEvent> {
        let id = UUID()
        let (stream, continuation) = AsyncStream.makeStream(of: FineReloadEvent.self)

        consumers[id] = continuation
        // Runs when the consumer's task is cancelled or its iteration ends,
        // which is how a released tree's registration is dropped here.
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in
                self?.consumers[id] = nil
            }
        }

        return stream
    }

    private func report(_ event: FineReloadEvent) {
        for continuation in consumers.values {
            continuation.yield(event)
        }
    }
}
#endif
