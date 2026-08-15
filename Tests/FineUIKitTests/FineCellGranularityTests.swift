import Observation
import Testing
import UIKit
@testable import FineUIKit

/// Counts writes to views, per node, so a test can say how much of a row the
/// runtime touched — not only whether the right thing ended up on screen.
@MainActor
private final class WorkCounter {
    var updates: [String: Int] = [:]

    func record(_ tag: String) {
        updates[tag, default: 0] += 1
    }

    var total: Int {
        updates.values.reduce(0, +)
    }

    func reset() {
        updates.removeAll()
    }
}

@MainActor
private struct ProbeLabel: FineViewRepresentable {
    let counter: WorkCounter
    let tag: String
    let text: @MainActor () -> String

    func makeView() -> UILabel {
        UILabel()
    }

    func updateView(_ view: UILabel, environment: FineEnvironmentValues) {
        counter.record(tag)
        view.text = text()
    }
}

@Observable
@MainActor
private final class CellModel {
    var title = "A"
}

private struct RowItem: Identifiable, Equatable {
    let id: Int
}

/// A row with one node that reads observable state and several that do not —
/// the shape of a feed row, where a title changes and the rest of the card does
/// not.
@MainActor
private struct HeavyRow: Renderable {
    static let coldNodeCount = 7

    let model: CellModel
    let counter: WorkCounter

    var body: any Renderable {
        FineStack.vertical {
            ProbeLabel(counter: counter, tag: "hot") { self.model.title }
            for index in 0..<Self.coldNodeCount {
                ProbeLabel(counter: counter, tag: "cold\(index)") { "static \(index)" }
            }
        }
    }
}

/// How much of a row a cell-local state change costs.
///
/// `FineNodeHost` renders a cell's subtree with no scheduler in the context, so
/// the whole row shares one observation scope: a value read by one label
/// invalidates the row and every node in it is written again. Measured here so
/// the decision about giving cells their own `FineNodeScheduler` rests on a
/// number rather than on an argument.
@MainActor
@Suite(.serialized)
struct FineCellGranularityTests {
    private func waitTicks(_ count: Int = 40) async {
        for _ in 0..<count {
            await Task.yield()
        }
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<400 where !condition() {
            await Task.yield()
        }
    }

    /// The node that reads the changed value is written. The nodes that do not
    /// read it should not be.
    @Test func cellLocalChangeWritesOnlyTheNodesThatReadIt() async throws {
        let counter = WorkCounter()
        let model = CellModel()
        let container = UIView(frame: .init(x: 0, y: 0, width: 320, height: 640))
        let window = UIWindow(frame: container.frame)
        window.addSubview(container)
        window.isHidden = false

        let ui = FineUI(state: model) { model in
            FineList([RowItem(id: 1)]) { _ in
                HeavyRow(model: model, counter: counter)
            }
        }
        ui.build(to: container)
        window.layoutIfNeeded()
        await waitTicks()

        // The row was rendered at least once; only what follows is measured.
        try #require(counter.updates["hot", default: 0] >= 1)
        counter.reset()

        model.title = "B"
        await waitUntil { counter.updates["hot", default: 0] >= 1 }

        #expect(counter.updates["hot"] == 1)
        #expect(counter.total == 1)
        _ = window
    }

    /// A value read while *building* the row belongs to the cell host's scope,
    /// not to a node's, and that scope has its own recovery path for changes
    /// that arrive while the tree is off screen. The node-level recovery does
    /// not stand in for it: a change read here re-runs the whole row.
    ///
    /// Every other suspend/resume test reads through a component's autoclosure,
    /// which is a node scope — so without this one the host's `deferObservedWork`
    /// could stop working and nothing would notice.
    @Test func suspendedHostScopeChangeRecoversOnResume() async throws {
        let counter = WorkCounter()
        let model = CellModel()
        let container = UIView(frame: .init(x: 0, y: 0, width: 320, height: 640))
        let window = UIWindow(frame: container.frame)
        window.addSubview(container)
        window.isHidden = false

        let ui = FineUI(state: model) { model in
            FineList([RowItem(id: 1)]) { _ in
                // Read while building the description, so it registers on the
                // host's scope rather than on any node's.
                let title = model.title
                return FineStack.vertical {
                    ProbeLabel(counter: counter, tag: "host") { title }
                }
            }
        }
        ui.build(to: container)
        window.layoutIfNeeded()
        await waitTicks()

        try #require(counter.updates["host", default: 0] >= 1)
        counter.reset()

        ui.suspend()
        model.title = "B"
        await waitTicks()
        #expect(counter.total == 0)

        ui.resume()
        await waitUntil { counter.updates["host", default: 0] >= 1 }

        #expect(counter.updates["host"] == 1)
        _ = window
    }

    /// The same question outside a list, where the runtime already answers it:
    /// the node scheduler gives each `_update` its own scope, so a change
    /// reaches one node. This is the behaviour the cell path is measured
    /// against.
    @Test func nodeLocalChangeOutsideAListWritesOnlyTheNodeThatReadsIt() async throws {
        let counter = WorkCounter()
        let model = CellModel()
        let container = UIView(frame: .init(x: 0, y: 0, width: 320, height: 640))

        let ui = FineUI(state: model) { model in
            HeavyRow(model: model, counter: counter)
        }
        ui.build(to: container)
        container.layoutIfNeeded()
        await waitTicks()

        try #require(counter.updates["hot", default: 0] >= 1)
        counter.reset()

        model.title = "B"
        await waitUntil { counter.updates["hot", default: 0] >= 1 }

        #expect(counter.updates["hot"] == 1)
        #expect(counter.total == 1)
    }
}
