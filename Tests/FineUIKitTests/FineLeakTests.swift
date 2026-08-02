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

@Observable
@MainActor
private final class LeakModel {
    var title = "title"
    var taps = 0
}

/// Captures only the state object, which is the shape the README asks for.
@MainActor
private final class StateCapturingController: FineViewController<LeakModel> {
    override func body(_ state: LeakModel) -> any Renderable {
        FineStack.vertical {
            FineLabel(text: state.title)
            FineButton(title: "Tap") { state.taps += 1 }
        }
    }
}

/// Captures `self` strongly, which is the shape the README warns about.
@MainActor
private final class SelfCapturingController: FineViewController<LeakModel> {
    var taps = 0

    override func body(_ state: LeakModel) -> any Renderable {
        FineStack.vertical {
            FineLabel(text: state.title)
            FineButton(title: "Tap") { self.taps += 1 }
        }
    }
}

/// The escape hatch the README prescribes — `[weak self]` on the handler —
/// written inside a builder, which is how a real screen is shaped.
@MainActor
private final class WeakSelfInsideBuilderController: FineViewController<LeakModel> {
    var taps = 0

    override func body(_ state: LeakModel) -> any Renderable {
        // `[self]` on the builder is what writing nothing there already means;
        // it is spelled out so the capture under test is visible, and so the
        // compiler stops reporting the mismatch it would otherwise warn about.
        FineStack.vertical { [self] in
            FineLabel(text: state.title)
            FineButton(title: "Tap") { [weak self] in self?.taps += 1 }
        }
    }
}

/// The same handler with no builder between it and `body`, which isolates the
/// handler's own capture from the builder's.
@MainActor
private final class WeakSelfWithoutBuilderController: FineViewController<LeakModel> {
    var taps = 0

    override func body(_ state: LeakModel) -> any Renderable {
        FineButton(title: "Tap") { [weak self] in self?.taps += 1 }
    }
}

/// `[unowned self]` on the handler inside a builder, which is the shape the
/// ToDo example is written in.
@MainActor
private final class UnownedSelfInsideBuilderController: FineViewController<LeakModel> {
    var taps = 0

    override func body(_ state: LeakModel) -> any Renderable {
        FineStack.vertical { [self] in
            FineLabel(text: state.title)
            FineButton(title: "Tap") { [unowned self] in taps += 1 }
        }
    }
}

/// `[weak self]` on the builder as well as on the handler.
@MainActor
private final class WeakSelfOnBuilderController: FineViewController<LeakModel> {
    var taps = 0

    override func body(_ state: LeakModel) -> any Renderable {
        FineStack.vertical { [weak self] in
            FineLabel(text: state.title)
            FineButton(title: "Tap") { self?.taps += 1 }
        }
    }
}

/// Captures `self` strongly from a navigation button rather than from the
/// tree. Navigation runs in its own observation scope, so it is a second way
/// into the same cycle.
@MainActor
private final class NavigationCapturingController: FineViewController<LeakModel> {
    var taps = 0

    override func body(_ state: LeakModel) -> any Renderable {
        FineLabel(text: state.title)
    }

    override func navigation(_ state: LeakModel) -> FineNavigation? {
        FineNavigation(title: state.title)
            .trailing(FineBarButton(title: "Add") { self.taps += 1 })
    }
}

/// What the render tree keeps alive after the object that built it goes away.
///
/// The runtime attaches a `FineNode` to every managed view and holds the
/// primitive that last rendered it (`FineNodeScheduler.renderChild`), so a
/// handler closure lives on the view for as long as the view does. A closure
/// that captures the controller therefore closes the cycle
/// controller → view → node → primitive → closure → controller. These tests
/// pin down which shapes pay that cost and which do not.
@MainActor
@Suite(.serialized)
struct FineLeakTests {
    /// Renders a controller's tree, drops it, and reports whether it went away.
    ///
    /// `loadViewIfNeeded()` is enough to render: `FineViewController` builds in
    /// `viewDidLoad`. Staying off a window keeps UIKit from holding a reference
    /// of its own, so a surviving controller means the tree held it.
    private func controllerSurvivesRelease(_ make: () -> UIViewController) -> Bool {
        weak var released: UIViewController?

        autoreleasepool {
            let controller = make()
            controller.loadViewIfNeeded()
            released = controller
        }

        return released != nil
    }

    @Test func treeCapturingOnlyItsStateReleasesTheController() {
        #expect(!controllerSurvivesRelease { StateCapturingController(state: LeakModel()) })
    }

    @Test func weakSelfInAHandlerReleasesTheController() {
        #expect(!controllerSurvivesRelease { WeakSelfWithoutBuilderController(state: LeakModel()) })
    }

    /// `[weak self]` on the handler is not enough once a builder stands between
    /// the handler and `body`.
    ///
    /// A builder's content closure is `@escaping` and is stored on the
    /// description (`FineStack.vertical`), because a node-local re-render has to
    /// be able to evaluate it again. Mentioning `self` anywhere inside it —
    /// even only to weakly capture it further in — makes the builder itself
    /// capture `self` strongly, and the builder is what the node holds.
    ///
    /// This is the gap between the runtime and the advice in the README, which
    /// prescribes `[weak self]` on the handler without saying that the builder
    /// needs it too. Asserting the leak keeps the two in step: closing the
    /// cycle, or making the capture unnecessary, fails here.
    @Test func weakSelfInsideABuilderStillLeaksTheController() {
        #expect(controllerSurvivesRelease { WeakSelfInsideBuilderController(state: LeakModel()) })
    }

    /// `unowned` fares no better. What holds the controller is the builder's
    /// capture, so the ownership the handler inside asks for cannot help.
    @Test func unownedSelfInsideABuilderStillLeaksTheController() {
        #expect(controllerSurvivesRelease { UnownedSelfInsideBuilderController(state: LeakModel()) })
    }

    /// The capture that does work through a builder: weaken the builder too.
    @Test func weakSelfOnTheBuilderReleasesTheController() {
        #expect(!controllerSurvivesRelease { WeakSelfOnBuilderController(state: LeakModel()) })
    }

    /// Records the known cost documented in the README: a handler that captures
    /// `self` strongly leaks the controller, because the view the runtime keeps
    /// the handler on is the controller's own view.
    ///
    /// This asserts the leak rather than the absence of one, so that closing
    /// the cycle in the runtime fails here and gets the promise updated in the
    /// README and in this suite together.
    @Test func strongSelfInAHandlerLeaksTheController() {
        #expect(controllerSurvivesRelease { SelfCapturingController(state: LeakModel()) })
    }

    /// Navigation reaches the same cycle by a different route: the scope that
    /// applies `navigation(_:)` holds the bar button's handler.
    @Test func strongSelfInABarButtonLeaksTheController() {
        #expect(controllerSurvivesRelease { NavigationCapturingController(state: LeakModel()) })
    }

    /// The views a controller rendered must not outlive it. A view held past
    /// its controller keeps its node, its local state, and its handlers alive
    /// with it.
    @Test func renderedViewsDoNotOutliveTheirController() {
        weak var releasedRoot: UIView?
        weak var releasedLabel: UIView?

        autoreleasepool {
            let controller = StateCapturingController(state: LeakModel())
            controller.loadViewIfNeeded()

            let root = controller.view.subviews.first
            releasedRoot = root
            releasedLabel = (root as? UIStackView)?.arrangedSubviews.first
        }

        #expect(releasedRoot == nil)
        #expect(releasedLabel == nil)
    }

    /// `FineUI` holds the tree it built, so releasing it has to release the
    /// views — including after the tree has re-rendered and replaced them.
    @Test func fineUIReleasesTheTreeItBuilt() {
        let model = LeakModel()
        weak var releasedRoot: UIView?
        weak var releasedFineUI: AnyObject?

        autoreleasepool {
            let container = UIView(frame: .init(x: 0, y: 0, width: 320, height: 480))
            let fineUI = FineUI(model) { model in
                FineStack.vertical {
                    FineLabel(text: model.title)
                    FineButton(title: "Tap") { model.taps += 1 }
                }
            }
            fineUI.build(to: container)
            container.layoutIfNeeded()

            releasedRoot = container.subviews.first
            releasedFineUI = fineUI
        }

        #expect(releasedFineUI == nil)
        #expect(releasedRoot == nil)
    }

    /// A controller that has appeared and disappeared goes through the
    /// suspend/resume path and the trait registration in `build(to:)`. Neither
    /// may keep it alive once its window lets go.
    @Test func controllerShownInAWindowIsReleasedAfterTheWindowLetsGo() {
        weak var released: UIViewController?

        autoreleasepool {
            let window = UIWindow(frame: .init(x: 0, y: 0, width: 320, height: 480))
            let controller = StateCapturingController(state: LeakModel())
            window.rootViewController = controller
            window.makeKeyAndVisible()
            window.layoutIfNeeded()

            released = controller
            window.rootViewController = nil
            window.isHidden = true
        }

        #expect(released == nil)
    }
}
