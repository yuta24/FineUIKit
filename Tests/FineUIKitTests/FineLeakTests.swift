//
//  FineLeakTests.swift
//  FineUIKit
//
//  Created by nova on 2026/08/02.
//

import Observation
import Testing
import UIKit
@testable import FineUIKit

private struct LeakRow: Identifiable, Equatable {
    let id: Int
    var title: String
}

@Observable
@MainActor
private final class LeakStore {
    var title = "title"
    var rows = [LeakRow(id: 1, title: "one")]
}

/// A representable whose adapter holds a closure, which is the retention path
/// a wrapped `UIView` adds.
private struct CapturingRepresentable: FineViewRepresentable {
    let onUpdate: @MainActor () -> Void

    func makeView() -> UIView {
        UIView(frame: .zero)
    }

    func updateView(_ view: UIView, environment: FineEnvironmentValues) {
        onUpdate()
    }
}

/// Captures `self` from every shape the runtime keeps a closure in: a builder,
/// a button action, a tap gesture, lifecycle hooks, a bar button, a list's and
/// a grid's cell content and row callbacks, an environment reader, a
/// `FineState` subtree, and a representable's adapter.
///
/// Off a window a list builds no cells, so the callbacks a coordinator holds
/// are covered here while the cell subtrees themselves are covered by the
/// windowed test below, which lays out and therefore materialises them.
@MainActor
@Observable
private final class CapturingScreen: FineScreen {
    @ObservationIgnored let store: LeakStore
    var taps = 0
    var appearances = 0

    init(store: LeakStore) {
        self.store = store
    }

    func body() -> any Renderable {
        FineStack.vertical {
            FineLabel(text: self.store.title)
            FineButton(title: "Tap") { self.taps += 1 }
            FineLabel(text: "\(self.taps)")
                .onTap { self.taps += 1 }
            FineEnvironmentReader { _ in
                FineLabel(text: "\(self.taps)")
            }
            FineState(false) { isOn in
                FineButton(title: "\(isOn.value)") {
                    self.taps += 1
                    isOn.value.toggle()
                }
            }
            CapturingRepresentable { self.taps += 0 }
            FineList(self.store.rows) { row in
                FineLabel(text: "\(row.title) \(self.taps)")
            }
            .onSelect { _ in self.taps += 1 }
            .onDelete { _ in self.taps += 1 }
            .onRefresh { self.taps += 1 }
            FineGrid(self.store.rows, columns: .count(2), spacing: 4) { row in
                FineLabel(text: "\(row.title) \(self.taps)")
            }
            .onSelect { _ in self.taps += 1 }
            .onRefresh { self.taps += 1 }
        }
        .onAppear { self.appearances += 1 }
        .onDisappear { self.appearances -= 1 }
        .task { self.appearances += 1 }
    }

    func navigation() -> FineNavigation? {
        FineNavigation(title: store.title)
            .trailing(FineBarButton(title: "Add") { self.taps += 1 })
    }
}

/// The same shape without the lifecycle modifiers, so the rendered root is the
/// stack itself rather than the wrapper `.onAppear` and friends install.
@MainActor
@Observable
private final class PlainScreen: FineScreen {
    var title = "title"

    func body() -> any Renderable {
        FineStack.vertical {
            FineLabel(text: self.title)
        }
    }
}

/// The one shape that still closes a cycle: a screen that reaches its
/// controller strongly.
@MainActor
private final class ControllerHoldingScreen: FineScreen {
    var controller: UIViewController?
    var taps = 0

    func body() -> any Renderable {
        FineButton(title: "Tap") { self.taps += 1 }
    }
}

/// A screen that reports outward the way the library recommends: through a weak
/// delegate, so the reference that would close the cycle is weak by declaration
/// rather than by everyone remembering a capture list.
@MainActor
private protocol RoutingScreenDelegate: AnyObject {
    func routingScreenDidSelect()
}

@MainActor
private final class RoutingScreen: FineScreen {
    weak var delegate: (any RoutingScreenDelegate)?

    func body() -> any Renderable {
        FineButton(title: "Go") { self.delegate?.routingScreenDidSelect() }
    }
}

@MainActor
private final class RoutingController: FineScreenController, RoutingScreenDelegate {
    var selections = 0

    func routingScreenDidSelect() {
        selections += 1
    }
}

/// What the render tree keeps alive after the objects that built it go away.
///
/// The runtime attaches a `FineNode` to every managed view and holds the
/// primitive that last rendered it (`FineNodeScheduler.renderChild`), and list
/// and grid coordinators hold their content and row callbacks besides. Every
/// closure a description carries therefore lives for as long as the view does,
/// and the views belong to the hosting controller.
///
/// That is why a description must not capture the *controller*: the cycle
/// controller → view → node → closure → controller has nothing to break it.
/// Capturing the *screen* is a different matter — the controller owns the
/// screen and the tree, and the screen owns neither — and these tests pin down
/// that the difference holds for every shape the runtime retains.
@MainActor
@Suite(.serialized)
struct FineLeakTests {
    /// Renders a controller's tree, drops it, and reports what went away.
    ///
    /// `loadViewIfNeeded()` is enough to render: `FineScreenController` builds
    /// in `viewDidLoad`. Staying off a window keeps UIKit from holding a
    /// reference of its own, so a survivor means the tree held it.
    private func releases(_ make: () -> (UIViewController, AnyObject)) -> (controller: Bool, screen: Bool) {
        weak var releasedController: UIViewController?
        weak var releasedScreen: AnyObject?

        autoreleasepool {
            let (controller, screen) = make()
            controller.loadViewIfNeeded()
            releasedController = controller
            releasedScreen = screen
        }

        return (releasedController == nil, releasedScreen == nil)
    }

    /// Every retained handler shape captures the screen strongly, and both the
    /// controller and the screen still go away.
    @Test func aScreenCapturingItselfEverywhereIsReleased() {
        let released = releases {
            let screen = CapturingScreen(store: LeakStore())
            return (FineScreenController(screen), screen)
        }

        #expect(released.controller)
        #expect(released.screen)
    }

    /// The recommended shape for reporting outward keeps the delegate weak, so
    /// pointing a screen at its own controller does not retain it.
    @Test func aWeakDelegatePointingAtTheControllerIsReleased() {
        let released = releases {
            let screen = RoutingScreen()
            let controller = RoutingController(screen)
            screen.delegate = controller
            return (controller, screen)
        }

        #expect(released.controller)
        #expect(released.screen)
    }

    /// The boundary, stated as a test so it cannot drift unnoticed.
    ///
    /// The controller holds its screen, so a screen that holds the controller
    /// back is a cycle on its own — controller → screen → controller — before
    /// any view exists. Nothing is rendered here on purpose: the rule is about
    /// the reference, not about which handler captured it, and rendering would
    /// only add a longer path to a cycle that already closed.
    @Test func aScreenHoldingItsControllerLeaks() {
        weak var releasedController: UIViewController?

        autoreleasepool {
            let screen = ControllerHoldingScreen()
            let controller = FineScreenController(screen)
            screen.controller = controller
            releasedController = controller
        }

        #expect(releasedController != nil)
    }

    /// The views a controller rendered must not outlive it. A view held past
    /// its controller keeps its node, its local state, and its handlers alive
    /// with it.
    @Test func renderedViewsDoNotOutliveTheirController() throws {
        weak var releasedRoot: UIView?
        weak var releasedLabel: UIView?

        try autoreleasepool {
            let controller = FineScreenController(PlainScreen())
            controller.loadViewIfNeeded()

            // Required, not expected: a tree that never rendered would leave
            // both references nil and pass the release checks for free.
            let root = try #require(controller.view.subviews.first as? UIStackView)
            releasedRoot = root
            releasedLabel = try #require(root.arrangedSubviews.first as? UILabel)
        }

        #expect(releasedRoot == nil)
        #expect(releasedLabel == nil)
    }

    /// A controller suspended while off screen must not be kept alive by the
    /// catch-up work the gate recorded for it.
    @Test func aSuspendedControllerIsReleased() {
        weak var releasedController: UIViewController?
        weak var releasedScreen: AnyObject?

        autoreleasepool {
            let store = LeakStore()
            let screen = CapturingScreen(store: store)
            let controller = FineScreenController(screen)
            controller.loadViewIfNeeded()
            controller.suspendRendering()

            // Recorded while suspended, so the gate owes a catch-up render.
            store.title = "changed"

            releasedController = controller
            releasedScreen = screen
        }

        #expect(releasedController == nil)
        #expect(releasedScreen == nil)
    }

    /// `FineUI` holds the tree it built, so releasing it has to release the
    /// views too.
    @Test func fineUIReleasesTheTreeItBuilt() throws {
        let store = LeakStore()
        weak var releasedRoot: UIView?
        weak var releasedFineUI: AnyObject?

        try autoreleasepool {
            let container = UIView(frame: .init(x: 0, y: 0, width: 320, height: 480))
            let fineUI = FineUI(store) { store in
                FineStack.vertical {
                    FineLabel(text: store.title)
                    FineButton(title: "Tap") { store.rows = [] }
                }
            }
            fineUI.build(to: container)
            container.layoutIfNeeded()

            releasedRoot = try #require(container.subviews.first as? UIStackView)
            releasedFineUI = fineUI
        }

        #expect(releasedFineUI == nil)
        #expect(releasedRoot == nil)
    }

    /// A controller that has appeared and disappeared goes through the
    /// suspend/resume path, the lifecycle hooks, and the trait registration in
    /// `build(to:)`. None of them may keep it alive once its window lets go.
    ///
    /// Release is not immediate here, and that is not a leak: `.task` starts a
    /// `Task` that captures the screen, and a task scheduled but not yet run
    /// holds what it captured until it does. So this yields until the screen
    /// goes rather than asserting on the same turn — a screen that a task kept
    /// alive forever would still fail, which is the property worth pinning.
    @Test func controllerShownInAWindowIsReleasedAfterTheWindowLetsGo() async {
        weak var releasedController: UIViewController?
        weak var releasedScreen: AnyObject?

        autoreleasepool {
            let window = UIWindow(frame: .init(x: 0, y: 0, width: 320, height: 480))
            let screen = CapturingScreen(store: LeakStore())
            let controller = FineScreenController(screen)
            window.rootViewController = controller
            window.makeKeyAndVisible()
            window.layoutIfNeeded()

            releasedController = controller
            releasedScreen = screen
            window.rootViewController = nil
            window.isHidden = true
        }

        for _ in 0..<50 where releasedScreen != nil {
            await Task.yield()
        }

        #expect(releasedController == nil)
        #expect(releasedScreen == nil)
    }
}
