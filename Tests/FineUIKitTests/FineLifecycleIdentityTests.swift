import Observation
import Testing
import UIKit
@testable import FineUIKit

@MainActor
private final class LifecycleLog {
    var entries: [String] = []

    func record(_ entry: String) {
        entries.append(entry)
    }
}

@Observable
@MainActor
private final class ChildToggle {
    var showsSecond = false
}

/// `onAppear` / `onDisappear` / `task` describe the life of the thing being
/// shown, not of the `UIView` that happens to be showing it.
///
/// A reused cell keeps its views on purpose, so the window transitions that
/// normally drive these never happen when a visible cell is handed a different
/// row — the previous row's task kept running and the new row's never started.
@MainActor
struct FineLifecycleIdentityTests {
    private func waitTicks(_ count: Int = 40) async {
        for _ in 0..<count {
            await Task.yield()
        }
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<200 where !condition() {
            await Task.yield()
        }
    }

    /// Swapping the row a visible cell shows is a disappearance and an
    /// appearance, even though no view moved.
    @Test func changingWhatAVisibleCellShowsCyclesRowLifecycle() async throws {
        let log = LifecycleLog()
        let window = UIWindow(frame: .init(x: 0, y: 0, width: 320, height: 120))
        window.isHidden = false
        let cell = FineListHostCell(style: .default, reuseIdentifier: FineListHostCell.reuseIdentifier)
        cell.frame = window.bounds
        window.addSubview(cell)

        let environment = FineEnvironmentStorage()
        func row(_ id: Int) -> any Renderable {
            FineLabel(text: "row \(id)")
                .onAppear { log.record("appear \(id)") }
                .onDisappear { log.record("disappear \(id)") }
        }

        cell.render(identity: AnyHashable(1), environment: environment, renderGate: nil) { row(1) }
        window.layoutIfNeeded()
        await waitTicks()
        #expect(log.entries == ["appear 1"])

        cell.render(identity: AnyHashable(2), environment: environment, renderGate: nil) { row(2) }
        window.layoutIfNeeded()
        await waitTicks()

        #expect(log.entries == ["appear 1", "disappear 1", "appear 2"])
        _ = window
    }

    /// The same row rendering again is not a new appearance.
    @Test func rerenderingTheSameRowDoesNotCycleLifecycle() async throws {
        let log = LifecycleLog()
        let window = UIWindow(frame: .init(x: 0, y: 0, width: 320, height: 120))
        window.isHidden = false
        let cell = FineListHostCell(style: .default, reuseIdentifier: FineListHostCell.reuseIdentifier)
        cell.frame = window.bounds
        window.addSubview(cell)

        let environment = FineEnvironmentStorage()
        func row() -> any Renderable {
            FineLabel(text: "row")
                .onAppear { log.record("appear") }
                .onDisappear { log.record("disappear") }
        }

        cell.render(identity: AnyHashable(1), environment: environment, renderGate: nil, row)
        window.layoutIfNeeded()
        await waitTicks()

        cell.render(identity: AnyHashable(1), environment: environment, renderGate: nil, row)
        window.layoutIfNeeded()
        await waitTicks()

        #expect(log.entries == ["appear"])
        _ = window
    }

    /// The previous row's task must not outlive the row. A cell handed a
    /// different row while it is on screen never sees a window transition, so
    /// nothing else would cancel it.
    @Test func changingWhatAVisibleCellShowsCancelsThePreviousRowsTask() async throws {
        let log = LifecycleLog()
        let window = UIWindow(frame: .init(x: 0, y: 0, width: 320, height: 120))
        window.isHidden = false
        let cell = FineListHostCell(style: .default, reuseIdentifier: FineListHostCell.reuseIdentifier)
        cell.frame = window.bounds
        window.addSubview(cell)

        let environment = FineEnvironmentStorage()
        func row(_ id: Int) -> any Renderable {
            FineLabel(text: "row \(id)")
                .task {
                    log.record("start \(id)")
                    // Long enough that only cancellation ends it.
                    try? await Task.sleep(for: .seconds(30))
                    log.record("cancelled \(id)")
                }
        }

        cell.render(identity: AnyHashable(1), environment: environment, renderGate: nil) { row(1) }
        window.layoutIfNeeded()
        await waitUntil { log.entries.contains("start 1") }
        #expect(log.entries == ["start 1"])

        cell.render(identity: AnyHashable(2), environment: environment, renderGate: nil) { row(2) }
        window.layoutIfNeeded()
        await waitUntil { log.entries.contains("start 2") }

        #expect(log.entries.contains("cancelled 1"))
        #expect(log.entries.contains("start 2"))
        _ = window
    }

    /// A child added to a container that is already on screen appears too.
    ///
    /// The scheduled path installs a node's description after the view has been
    /// put into the hierarchy, so the window transition happens while the
    /// lifecycle handlers are still unset — and the appearance was lost.
    @Test func onAppearFiresForAChildAddedToAVisibleContainer() async throws {
        let log = LifecycleLog()
        let toggle = ChildToggle()
        let container = UIView(frame: .init(x: 0, y: 0, width: 320, height: 480))
        let window = UIWindow(frame: container.frame)
        window.addSubview(container)
        window.isHidden = false

        let ui = FineUI(state: toggle) { toggle in
            FineStack.vertical {
                FineLabel(text: "first")
                if toggle.showsSecond {
                    FineLabel(text: "second")
                        .onAppear { log.record("appear second") }
                }
            }
        }
        ui.build(to: container)
        window.layoutIfNeeded()
        await waitTicks()
        #expect(log.entries.isEmpty)

        toggle.showsSecond = true
        await waitUntil { !log.entries.isEmpty }
        window.layoutIfNeeded()

        #expect(log.entries == ["appear second"])
        _ = window
    }
}
