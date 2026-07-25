import Observation
import Testing
import UIKit
@testable import FineUIKit

/// Counts how many times the runtime writes to a view, so tests can assert on
/// the *amount* of work a change causes, not only on its result.
@MainActor
private final class RenderCounts {
    var counts: [String: Int] = [:]
}

@MainActor
private let renderCounts = RenderCounts()

/// Records the transaction in effect while the runtime writes to it.
@MainActor
private final class TransactionLog {
    var disabledFlags: [Bool] = []
}

@MainActor
private let transactionLog = TransactionLog()

@MainActor
private struct TransactionProbe: FineViewRepresentable {
    func makeView() -> UILabel {
        UILabel()
    }

    func updateView(_ view: UILabel, environment: FineEnvironmentValues) {
        if case .disabled = FineTransactionContext.current {
            transactionLog.disabledFlags.append(true)
        } else {
            transactionLog.disabledFlags.append(false)
        }
    }
}

@MainActor
private struct CountingProbe: FineViewRepresentable {
    let tag: String

    func makeView() -> UILabel {
        UILabel()
    }

    func updateView(_ view: UILabel, environment: FineEnvironmentValues) {
        renderCounts.counts[tag, default: 0] += 1
    }
}

@Observable
private final class ObservableRow: Identifiable {
    let id = 1
    var title = "A"
}

/// Equality covers `id` only, which is what an app writes for a row whose
/// mutable data lives in an observable model.
private struct KeyedRow: Identifiable, Equatable {
    let id: Int
}

@Observable
private final class RowModel {
    var title = "A"
}

private struct TitledRow: Identifiable, Equatable {
    let id: Int
    var title: String
}

@Observable
private final class RowListState {
    var rows: [TitledRow] = [.init(id: 1, title: "R1")]
    let model = RowModel()
}

@Observable
private final class ScopeState {
    var title = "T0"
    var bodyValue = 0
}

/// `navigation(_:)` and `body(_:)` are tracked separately, and rendering pauses
/// while a controller is off screen.
@MainActor
@Suite(.serialized)
struct FineRenderScopeTests {
    private final class ScopedViewController: FineViewController<ScopeState> {
        let tag: String
        var suspends = true

        init(state: ScopeState, tag: String) {
            self.tag = tag
            super.init(state: state)
        }

        override var suspendsWhenDisappeared: Bool {
            suspends
        }

        override func body(_ state: ScopeState) -> any Renderable {
            FineStack.vertical {
                // Eager read: registers on the container's scope, so any
                // body-scope invalidation re-diffs these children.
                FineLabel(text: "body")
                    .backgroundColor(state.bodyValue % 2 == 0 ? .red : .blue)
                CountingProbe(tag: self.tag)
            }
        }

        override func navigation(_ state: ScopeState) -> FineNavigation? {
            FineNavigation(title: state.title)
        }
    }

    /// Reads state in `body(_:)` itself, so the read registers on the root
    /// scope rather than on the enclosing container's node.
    private final class RootScopeViewController: FineViewController<ScopeState> {
        let tag: String

        init(state: ScopeState, tag: String) {
            self.tag = tag
            super.init(state: state)
        }

        override func body(_ state: ScopeState) -> any Renderable {
            let value = state.bodyValue
            return FineStack.vertical {
                FineLabel(text: "\(value)")
                CountingProbe(tag: self.tag)
            }
        }
    }

    /// Waits for work that must not happen: there is no condition to poll, so
    /// this yields a fixed number of times and lets the assertion follow.
    private func waitTicks(_ count: Int = 40) async {
        for _ in 0..<count {
            await Task.yield()
        }
    }

    /// Waits for an expected outcome with a bound, instead of assuming a fixed
    /// number of turns is enough on a loaded machine.
    private func waitUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<200 where !condition() {
            await Task.yield()
        }
    }

    private func rewrites(_ tag: String, since base: Int) -> Int {
        renderCounts.counts[tag, default: 0] - base
    }

    @discardableResult
    private func present(_ controller: UIViewController) -> UIWindow {
        let window = UIWindow(frame: .init(x: 0, y: 0, width: 320, height: 600))
        window.rootViewController = controller
        window.isHidden = false
        window.layoutIfNeeded()
        return window
    }

    // MARK: - navigation scope

    @Test func navigationOnlyChangeDoesNotRerenderBody() async throws {
        let state = ScopeState()
        let controller = ScopedViewController(state: state, tag: "nav-only")
        let window = present(controller)
        await waitTicks()

        let base = renderCounts.counts["nav-only", default: 0]
        #expect(controller.navigationItem.title == "T0")

        state.title = "T1"
        await waitUntil { controller.navigationItem.title == "T1" }

        #expect(controller.navigationItem.title == "T1")
        #expect(rewrites("nav-only", since: base) == 0)
        _ = window
    }

    @Test func nodeScopeChangeStillRerendersBody() async throws {
        let state = ScopeState()
        let controller = ScopedViewController(state: state, tag: "body-change")
        let window = present(controller)
        await waitTicks()

        let base = renderCounts.counts["body-change", default: 0]
        state.bodyValue += 1
        await waitTicks()

        #expect(rewrites("body-change", since: base) == 1)
        _ = window
    }

    @Test func navigationKeepsUpdatingAfterRepeatedChanges() async throws {
        let state = ScopeState()
        let controller = ScopedViewController(state: state, tag: "nav-repeat")
        let window = present(controller)
        await waitTicks()

        for index in 1...3 {
            state.title = "T\(index)"
            await waitUntil { controller.navigationItem.title == "T\(index)" }
            #expect(controller.navigationItem.title == "T\(index)")
        }
        _ = window
    }

    // MARK: - root body scope

    @Test func rootScopeChangeRerendersBody() async throws {
        let state = ScopeState()
        let controller = RootScopeViewController(state: state, tag: "root-scope")
        let window = present(controller)
        await waitTicks()

        let base = renderCounts.counts["root-scope", default: 0]
        state.bodyValue += 1
        await waitTicks()

        #expect(rewrites("root-scope", since: base) == 1)
        _ = window
    }

    @Test func suspendedRootScopeChangeIsDeferredAndFlushed() async throws {
        let state = ScopeState()
        let container = UIView(frame: .init(x: 0, y: 0, width: 320, height: 480))
        let ui = FineUI(state) { state in
            // Read in the root body itself: this registers on `FineUI`'s own
            // scope, which is a different gate call site than a node's.
            let value = state.bodyValue
            return FineStack.vertical {
                FineLabel(text: "\(value)")
                CountingProbe(tag: "root-suspend")
            }
        }
        ui.build(to: container)
        container.layoutIfNeeded()
        await waitTicks()

        let base = renderCounts.counts["root-suspend", default: 0]
        ui.suspend()
        state.bodyValue += 1
        await waitTicks()
        #expect(rewrites("root-suspend", since: base) == 0)

        ui.resume()
        await waitUntil { self.rewrites("root-suspend", since: base) == 1 }
        #expect(rewrites("root-suspend", since: base) == 1)
        #expect(firstLabel(in: container)?.text == "1")
    }

    // MARK: - visibility gate

    @Test func coveredControllerStopsRenderingAndCatchesUpOnReappear() async throws {
        let state = ScopeState()
        let covered = ScopedViewController(state: state, tag: "covered")
        let navigationController = UINavigationController(rootViewController: covered)
        let window = present(navigationController)
        await waitTicks()

        let top = ScopedViewController(state: state, tag: "top")
        navigationController.pushViewController(top, animated: false)
        window.layoutIfNeeded()
        await waitTicks()

        let coveredBase = renderCounts.counts["covered", default: 0]
        let topBase = renderCounts.counts["top", default: 0]

        state.bodyValue += 1
        await waitTicks()

        // The covered screen skips the work; the visible one does it.
        #expect(rewrites("covered", since: coveredBase) == 0)
        #expect(rewrites("top", since: topBase) == 1)

        navigationController.popViewController(animated: false)
        window.layoutIfNeeded()
        await waitUntil { self.rewrites("covered", since: coveredBase) == 1 }

        // Reappearing flushes exactly one catch-up render.
        #expect(rewrites("covered", since: coveredBase) == 1)
        _ = window
    }

    @Test func reappearingControllerShowsCurrentState() async throws {
        let state = ScopeState()
        let covered = ScopedViewController(state: state, tag: "catch-up")
        let navigationController = UINavigationController(rootViewController: covered)
        let window = present(navigationController)
        await waitTicks()

        navigationController.pushViewController(UIViewController(), animated: false)
        window.layoutIfNeeded()
        await waitTicks()

        state.bodyValue += 1
        await waitTicks()

        navigationController.popViewController(animated: false)
        window.layoutIfNeeded()
        await waitTicks()

        let label = firstLabel(in: covered.view)
        #expect(label?.backgroundColor == .blue)
        _ = window
    }

    @Test func controllerExposesManualSuspendAndResume() async throws {
        let state = ScopeState()
        let controller = ScopedViewController(state: state, tag: "manual-controller")
        let window = present(controller)
        await waitTicks()

        let base = renderCounts.counts["manual-controller", default: 0]
        // The remedy documented for presentations UIKit reports no
        // disappearance for must be reachable from the controller itself.
        controller.suspendRendering()
        state.bodyValue += 1
        await waitTicks()
        #expect(rewrites("manual-controller", since: base) == 0)

        controller.resumeRendering()
        await waitUntil { self.rewrites("manual-controller", since: base) == 1 }
        #expect(rewrites("manual-controller", since: base) == 1)
        _ = window
    }

    @Test func suspendsWhenDisappearedFalseKeepsRendering() async throws {
        let state = ScopeState()
        let covered = ScopedViewController(state: state, tag: "no-suspend")
        covered.suspends = false
        let navigationController = UINavigationController(rootViewController: covered)
        let window = present(navigationController)
        await waitTicks()

        navigationController.pushViewController(UIViewController(), animated: false)
        window.layoutIfNeeded()
        await waitTicks()

        let base = renderCounts.counts["no-suspend", default: 0]
        state.bodyValue += 1
        await waitTicks()

        #expect(rewrites("no-suspend", since: base) == 1)
        _ = window
    }

    @Test func suspendedRuntimeDefersWorkUntilResume() async throws {
        let state = ScopeState()
        let container = UIView(frame: .init(x: 0, y: 0, width: 320, height: 480))
        let ui = FineUI(state) { state in
            FineStack.vertical {
                FineLabel(text: "body")
                    .backgroundColor(state.bodyValue % 2 == 0 ? .red : .blue)
                CountingProbe(tag: "manual-suspend")
            }
        }
        ui.build(to: container)
        container.layoutIfNeeded()
        await waitTicks()

        let base = renderCounts.counts["manual-suspend", default: 0]
        ui.suspend()
        state.bodyValue += 1
        await waitTicks()
        #expect(rewrites("manual-suspend", since: base) == 0)

        ui.resume()
        await waitUntil { self.rewrites("manual-suspend", since: base) == 1 }
        #expect(rewrites("manual-suspend", since: base) == 1)
        #expect(firstLabel(in: container)?.backgroundColor == .blue)
    }

    @Test func resumeWithoutPendingChangeDoesNoWork() async throws {
        let state = ScopeState()
        let container = UIView(frame: .init(x: 0, y: 0, width: 320, height: 480))
        let ui = FineUI(state) { _ in
            FineStack.vertical {
                CountingProbe(tag: "idle-resume")
            }
        }
        ui.build(to: container)
        container.layoutIfNeeded()
        await waitTicks()

        let base = renderCounts.counts["idle-resume", default: 0]
        ui.suspend()
        ui.resume()
        await waitTicks()

        #expect(rewrites("idle-resume", since: base) == 0)
    }

    @Test func manyChangesWhileSuspendedFlushOnce() async throws {
        let state = ScopeState()
        let container = UIView(frame: .init(x: 0, y: 0, width: 320, height: 480))
        let ui = FineUI(state) { state in
            FineStack.vertical {
                FineLabel(text: "body")
                    .backgroundColor(state.bodyValue % 2 == 0 ? .red : .blue)
                CountingProbe(tag: "coalesced-flush")
            }
        }
        ui.build(to: container)
        container.layoutIfNeeded()
        await waitTicks()

        let base = renderCounts.counts["coalesced-flush", default: 0]
        ui.suspend()
        for _ in 0..<5 {
            state.bodyValue += 2
            await waitTicks(5)
        }
        #expect(rewrites("coalesced-flush", since: base) == 0)

        ui.resume()
        await waitUntil { self.rewrites("coalesced-flush", since: base) == 1 }
        #expect(rewrites("coalesced-flush", since: base) == 1)
    }

    // MARK: - list cells inside a suspended tree

    @Test func suspendedTreeStopsCellLocalRerendersForNonComparableElements() async throws {
        let row = ObservableRow()
        let container = UIView(frame: .init(x: 0, y: 0, width: 320, height: 480))
        let window = UIWindow(frame: container.frame)
        window.addSubview(container)
        window.isHidden = false

        let ui = FineUI(row) { row in
            FineList([row]) { row in
                FineStack.horizontal {
                    FineLabel(text: row.title)
                    CountingProbe(tag: "suspended-cell")
                }
            }
        }
        ui.build(to: container)
        window.layoutIfNeeded()
        await waitTicks()

        let base = renderCounts.counts["suspended-cell", default: 0]
        ui.suspend()
        row.title = "B"
        await waitTicks()
        #expect(rewrites("suspended-cell", since: base) == 0)

        ui.resume()
        await waitUntil {
            window.layoutIfNeeded()
            return self.rewrites("suspended-cell", since: base) >= 1
        }
        #expect(rewrites("suspended-cell", since: base) >= 1)
        _ = window
    }

    /// The row's element is `Equatable` and unchanged, so the catch-up render
    /// does not reconfigure it. The cell's own suppressed scope must recover, or
    /// the row stays stale forever — its observation is gone too.
    @Test func suspendedCellCatchesUpWhenElementIsUnchanged() async throws {
        let model = RowModel()
        let container = UIView(frame: .init(x: 0, y: 0, width: 320, height: 480))
        let window = UIWindow(frame: container.frame)
        window.addSubview(container)
        window.isHidden = false

        let ui = FineUI(model) { model in
            FineList([KeyedRow(id: 1)]) { _ in
                FineLabel(text: model.title)
            }
        }
        ui.build(to: container)
        window.layoutIfNeeded()
        await waitTicks()
        #expect(cellText(in: container) == "A")

        ui.suspend()
        model.title = "B"
        await waitTicks()
        window.layoutIfNeeded()
        #expect(cellText(in: container) == "A")

        ui.resume()
        await waitUntil { self.cellText(in: container) == "B" }
        #expect(cellText(in: container) == "B")

        // The recovered scope must be registered again, not one-shot.
        model.title = "C"
        await waitUntil { self.cellText(in: container) == "C" }
        #expect(cellText(in: container) == "C")
        _ = window
    }

    @Test func suspendedCellCatchesUpOnControllerReappearance() async throws {
        final class ListViewController: FineViewController<RowModel> {
            override func body(_ state: RowModel) -> any Renderable {
                FineList([KeyedRow(id: 1)]) { _ in
                    FineLabel(text: state.title)
                }
            }
        }

        let model = RowModel()
        let controller = ListViewController(state: model)
        let navigationController = UINavigationController(rootViewController: controller)
        let window = present(navigationController)
        await waitTicks()
        window.layoutIfNeeded()
        #expect(cellText(in: controller.view) == "A")

        navigationController.pushViewController(UIViewController(), animated: false)
        window.layoutIfNeeded()
        await waitTicks()

        model.title = "B"
        await waitTicks()

        navigationController.popViewController(animated: false)
        window.layoutIfNeeded()
        await waitUntil { self.cellText(in: controller.view) == "B" }

        #expect(cellText(in: controller.view) == "B")
        _ = window
    }

    /// The catch-up render reconfigures the row (its element changed) *and* a
    /// recovery closure is pending for the same host. The generation guard must
    /// keep that from rendering the cell twice.
    @Test func catchUpAndDeferredRecoveryDoNotBothRenderTheCell() async throws {
        let state = RowListState()
        let container = UIView(frame: .init(x: 0, y: 0, width: 320, height: 480))
        let window = UIWindow(frame: container.frame)
        window.addSubview(container)
        window.isHidden = false

        let ui = FineUI(state) { state in
            FineList(state.rows) { row in
                FineStack.horizontal {
                    FineLabel(text: "\(row.title)-\(state.model.title)")
                    CountingProbe(tag: "double-render")
                }
            }
        }
        ui.build(to: container)
        window.layoutIfNeeded()
        await waitTicks()

        let base = renderCounts.counts["double-render", default: 0]
        ui.suspend()
        // Invalidates the cell's own scope…
        state.model.title = "B"
        await waitTicks()
        // …and makes the element unequal, so the catch-up render reconfigures it.
        state.rows = [TitledRow(id: 1, title: "R2")]
        await waitTicks()
        #expect(rewrites("double-render", since: base) == 0)

        ui.resume()
        await waitUntil {
            window.layoutIfNeeded()
            return self.rewrites("double-render", since: base) >= 1
        }
        window.layoutIfNeeded()

        #expect(rewrites("double-render", since: base) == 1)
        #expect(cellText(in: container) == "R2-B")
        _ = window
    }

    /// A cell-local change is exactly what per-cell observation exists to keep
    /// cheap, so it must not escalate into a whole-tree render at `resume()`.
    @Test func cellOnlyChangeWhileSuspendedDoesNotForceFullRender() async throws {
        let model = RowModel()
        let container = UIView(frame: .init(x: 0, y: 0, width: 320, height: 480))
        let window = UIWindow(frame: container.frame)
        window.addSubview(container)
        window.isHidden = false

        let ui = FineUI(model) { model in
            FineStack.vertical {
                CountingProbe(tag: "outside-list")
                FineList([KeyedRow(id: 1)]) { _ in
                    FineLabel(text: model.title)
                }
            }
        }
        ui.build(to: container)
        window.layoutIfNeeded()
        await waitTicks()

        let base = renderCounts.counts["outside-list", default: 0]
        ui.suspend()
        model.title = "B"
        await waitTicks()

        ui.resume()
        await waitUntil { self.cellText(in: container) == "B" }

        #expect(cellText(in: container) == "B")
        // Nothing outside the cell changed, so nothing outside the cell re-ran.
        #expect(rewrites("outside-list", since: base) == 0)
        _ = window
    }

    /// A cell recycled while work is pending must not have the old row's
    /// recovery applied to it.
    @Test func deferredRecoveryIsDroppedWhenTheCellIsRecycled() async throws {
        let model = RowModel()
        let container = UIView(frame: .init(x: 0, y: 0, width: 320, height: 480))
        let window = UIWindow(frame: container.frame)
        window.addSubview(container)
        window.isHidden = false

        let ui = FineUI(model) { model in
            FineList([KeyedRow(id: 1)]) { _ in
                FineStack.horizontal {
                    FineLabel(text: model.title)
                    CountingProbe(tag: "recycled")
                }
            }
        }
        ui.build(to: container)
        window.layoutIfNeeded()
        await waitTicks()

        ui.suspend()
        model.title = "B"
        await waitTicks()

        let tableView = try #require(firstTableView(in: container))
        let cell = try #require(tableView.cellForRow(at: .init(row: 0, section: 0)))
        let base = renderCounts.counts["recycled", default: 0]
        // Recycling invalidates the host, which bumps its generation.
        cell.prepareForReuse()

        ui.resume()
        await waitTicks()

        // The stale recovery is a no-op; the row is re-rendered only when the
        // data source configures the recycled cell again.
        #expect(rewrites("recycled", since: base) == 0)
        _ = window
    }

    /// A list applies its snapshot with animation unless a transaction says
    /// otherwise, so the catch-up render must run with animations disabled —
    /// otherwise rows added while hidden slide in on the way back.
    @Test func catchUpRenderRunsWithAnimationsDisabled() async throws {
        let state = ScopeState()
        let container = UIView(frame: .init(x: 0, y: 0, width: 320, height: 480))
        let ui = FineUI(state) { state in
            let value = state.bodyValue
            return FineStack.vertical {
                FineLabel(text: "\(value)")
                TransactionProbe()
            }
        }
        ui.build(to: container)
        container.layoutIfNeeded()
        await waitTicks()

        transactionLog.disabledFlags.removeAll()
        ui.suspend()
        state.bodyValue += 1
        await waitTicks()
        ui.resume()
        await waitUntil { !transactionLog.disabledFlags.isEmpty }

        #expect(transactionLog.disabledFlags.allSatisfy { $0 })
    }

    private func cellText(in view: UIView) -> String? {
        guard let tableView = firstTableView(in: view) else { return nil }
        tableView.layoutIfNeeded()
        guard let cell = tableView.cellForRow(at: .init(row: 0, section: 0)) else { return nil }
        return firstLabel(in: cell)?.text
    }

    private func firstTableView(in view: UIView) -> UITableView? {
        if let tableView = view as? UITableView {
            return tableView
        }

        for subview in view.subviews {
            if let tableView = firstTableView(in: subview) {
                return tableView
            }
        }

        return nil
    }

    private func firstLabel(in view: UIView) -> UILabel? {
        if let label = view as? UILabel, !(view.superview is UIButton) {
            return label
        }

        for subview in view.subviews {
            if let label = firstLabel(in: subview) {
                return label
            }
        }

        return nil
    }
}
