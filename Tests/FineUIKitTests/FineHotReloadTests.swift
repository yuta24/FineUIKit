#if DEBUG
import Foundation
import Observation
import Testing
import UIKit
@testable import FineUIKit

@Observable
@MainActor
private final class ReloadCounter {
    var count = 0
}

/// A backend under the test's control, so a reload can be reported without an
/// injection tool, a notification, or anything else process-wide.
@MainActor
private final class FakeHotReloadBackend: FineHotReloadBackend {
    private(set) var startCount = 0
    private var consumers: [UUID: AsyncStream<FineReloadEvent>.Continuation] = [:]

    /// How many streams are still being consumed — what a released tree is
    /// supposed to decrement, and only the producer side can see.
    var consumerCount: Int {
        consumers.count
    }

    func start() {
        startCount += 1
    }

    func events() -> AsyncStream<FineReloadEvent> {
        let id = UUID()
        let (stream, continuation) = AsyncStream.makeStream(of: FineReloadEvent.self)

        consumers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in
                self?.consumers[id] = nil
            }
        }

        return stream
    }

    func report() {
        for continuation in consumers.values {
            continuation.yield(.codeInjected)
        }
    }
}

/// The seam between "code was replaced" and "render again".
///
/// The runtime is supposed to act on a reload without knowing who reported it,
/// so these drive it from a backend of the test's own and never post the
/// injection tools' notification — except in the one test that is about that
/// notification being what the shipped backend listens for.
@MainActor
@Suite
struct FineHotReloadTests {
    private func waitUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<200 where !condition() {
            await Task.yield()
        }
    }

    private func waitTicks(_ count: Int = 40) async {
        for _ in 0..<count {
            await Task.yield()
        }
    }

    @Test func rerendersWhenABackendReportsAReload() async {
        let container = UIView()
        var bodyEvaluations = 0

        let ui = FineUI(state: ReloadCounter()) { counter in
            bodyEvaluations += 1
            return FineLabel(text: "\(counter.count)")
        }
        let backend = FakeHotReloadBackend()
        ui.hotReloadBackend = backend
        ui.build(to: container)

        #expect(bodyEvaluations == 1)
        #expect(backend.startCount == 1)

        backend.report()
        await waitUntil { bodyEvaluations == 2 }

        #expect(bodyEvaluations == 2)
        _ = ui
    }

    /// Building into a second container moves the tree; it does not mount a
    /// second one. A backend started twice would report every reload twice.
    @Test func mountingAgainDoesNotSubscribeTwice() async {
        let container = UIView()
        let other = UIView()
        var bodyEvaluations = 0

        let ui = FineUI(state: ReloadCounter()) { counter in
            bodyEvaluations += 1
            return FineLabel(text: "\(counter.count)")
        }
        let backend = FakeHotReloadBackend()
        ui.hotReloadBackend = backend
        ui.build(to: container)
        ui.build(to: other)

        #expect(backend.startCount == 1)

        let before = bodyEvaluations
        backend.report()
        await waitUntil { bodyEvaluations > before }
        // A second delivery would land on a later turn, so counting right after
        // the first one would pass whether or not there is one.
        await waitTicks()

        #expect(bodyEvaluations == before + 1)
        _ = ui
    }

    /// The name is the entire contract with InjectionIII / InjectionNext /
    /// InjectionLite — nothing links against them — and getting it wrong fails
    /// silently, which is the failure hot reload already has too much of.
    @Test func theShippedBackendUsesTheInjectionToolsNotification() {
        #expect(
            FineNotificationHotReloadBackend.injectionNotificationName
                == Notification.Name("INJECTION_BUNDLE_NOTIFICATION")
        )
    }

    @Test func theShippedBackendReportsThatNotification() async {
        // An instance-specific name keeps this post from reloading every live
        // tree in concurrently running tests.
        let name = Notification.Name("FineUIKitTests.hotReload.\(UUID().uuidString)")
        let backend = FineNotificationHotReloadBackend(name: name)
        var reports = 0

        let events = backend.events()
        backend.start()
        let consumer = Task { @MainActor in
            for await _ in events {
                reports += 1
            }
        }
        defer { consumer.cancel() }

        NotificationCenter.default.post(name: name, object: nil)
        await waitUntil { reports == 1 }

        #expect(reports == 1)
    }

    /// A backend keeps a subscription alive, so a tree that went away has to
    /// take it down with it rather than keep re-rendering a detached view.
    @Test func aReleasedTreeStopsListening() async {
        let name = Notification.Name("FineUIKitTests.hotReload.\(UUID().uuidString)")
        let container = UIView()
        var bodyEvaluations = 0

        do {
            let ui = FineUI(state: ReloadCounter()) { counter in
                bodyEvaluations += 1
                return FineLabel(text: "\(counter.count)")
            }
            ui.hotReloadBackend = FineNotificationHotReloadBackend(name: name)
            ui.build(to: container)

            NotificationCenter.default.post(name: name, object: nil)
            await waitUntil { bodyEvaluations == 2 }
            #expect(bodyEvaluations == 2)
        }
        // Let the released tree's consumer observe its cancellation.
        await waitTicks()

        NotificationCenter.default.post(name: name, object: nil)
        await waitTicks()

        #expect(bodyEvaluations == 2)
    }

    /// A reload is news for every tree in the process, not for whichever one
    /// happened to ask first. Sharing one backend has to reload all of them —
    /// a stream handed to two consumers would divide the events between them,
    /// and the tree that lost the coin toss would silently keep running the
    /// code that was just replaced.
    @Test func oneBackendReloadsEveryTreeItDrives() async {
        let backend = FakeHotReloadBackend()
        var evaluations = [0, 0]
        // Held: `FineUI` keeps its container weakly, and a tree whose container
        // went away renders nothing, which would look exactly like the failure
        // this test is about.
        let containers = [UIView(), UIView()]

        let trees = (0..<2).map { index -> FineUI in
            let ui = FineUI(state: ReloadCounter()) { counter in
                evaluations[index] += 1
                return FineLabel(text: "\(counter.count)")
            }
            ui.hotReloadBackend = backend
            ui.build(to: containers[index])
            return ui
        }

        #expect(evaluations == [1, 1])

        backend.report()
        await waitUntil { evaluations == [2, 2] }

        #expect(evaluations == [2, 2])
        _ = trees
        _ = containers
    }

    /// The same property on the backend that ships, whose fan-out is its own
    /// code and not the fake's.
    @Test func theShippedBackendReloadsEveryTreeItDrives() async {
        let name = Notification.Name("FineUIKitTests.hotReload.\(UUID().uuidString)")
        let backend = FineNotificationHotReloadBackend(name: name)
        var evaluations = [0, 0]
        let containers = [UIView(), UIView()]

        let trees = (0..<2).map { index -> FineUI in
            let ui = FineUI(state: ReloadCounter()) { counter in
                evaluations[index] += 1
                return FineLabel(text: "\(counter.count)")
            }
            ui.hotReloadBackend = backend
            ui.build(to: containers[index])
            return ui
        }

        #expect(evaluations == [1, 1])
        #expect(backend.consumerCount == 2)

        NotificationCenter.default.post(name: name, object: nil)
        await waitUntil { evaluations == [2, 2] }

        #expect(evaluations == [2, 2])
        _ = trees
        _ = containers
    }

    /// The shipped backend is owned by the tree, so releasing the tree takes
    /// its subscription down as a side effect. A backend that outlives the tree
    /// — a shared one, or a test's own — does not, and the consumer would sit
    /// on the stream forever waiting for a reload nobody is left to apply.
    @Test func aReleasedTreeLetsGoOfABackendThatOutlivesIt() async {
        let backend = FakeHotReloadBackend()
        let container = UIView()

        do {
            let ui = FineUI(state: ReloadCounter()) { counter in
                FineLabel(text: "\(counter.count)")
            }
            ui.hotReloadBackend = backend
            ui.build(to: container)
            #expect(backend.consumerCount == 1)
        }
        await waitUntil { backend.consumerCount == 0 }

        #expect(backend.consumerCount == 0)
    }

    /// Same property, on the backend that actually ships: a shared one has to
    /// forget a screen that is gone rather than keep a registration per screen
    /// the app has ever shown.
    @Test func theShippedBackendForgetsAReleasedTree() async {
        let name = Notification.Name("FineUIKitTests.hotReload.\(UUID().uuidString)")
        let backend = FineNotificationHotReloadBackend(name: name)
        let container = UIView()

        do {
            let ui = FineUI(state: ReloadCounter()) { counter in
                FineLabel(text: "\(counter.count)")
            }
            ui.hotReloadBackend = backend
            ui.build(to: container)
            #expect(backend.consumerCount == 1)
        }
        await waitUntil { backend.consumerCount == 0 }

        #expect(backend.consumerCount == 0)
    }
}
#endif
