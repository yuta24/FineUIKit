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

/// Captures `self` strongly from a handler, with no builder in between, so the
/// only capture in play is the handler's own.
@MainActor
private final class StrongSelfWithoutBuilderController: FineViewController<LeakModel> {
    var taps = 0

    override func body(_ state: LeakModel) -> any Renderable {
        FineButton(title: "Tap") { self.taps += 1 }
    }
}

/// The escape hatch the README used to prescribe — `[weak self]` on the handler
/// — written inside a builder, which is how a real screen is shaped.
@MainActor
private final class WeakSelfInsideBuilderController: FineViewController<LeakModel> {
    var taps = 0

    override func body(_ state: LeakModel) -> any Renderable {
        // `[self]` on the builder is exactly what writing nothing there already
        // means. It is spelled out because the two are the same capture to the
        // compiler — its own diagnostic calls the implicit form an
        // "implicitly-captured strong reference" — and writing it silences the
        // `#ImplicitStrongCapture` warning the mismatch would otherwise raise
        // in test code.
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
/// ToDo example was written in.
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

/// `[weak self]` on the builder, and nothing on the handler inside: weakening
/// the outermost closure that captures `self` is enough, because what the
/// handler then captures is already the weak binding.
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

/// Captures `self` strongly from a navigation button rather than from the tree.
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
///
/// The shapes that currently leak are written as the release they ought to
/// achieve and marked `withKnownIssue`, so closing the cycle in the runtime
/// reports the known issue as no longer occurring rather than passing quietly.
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

    /// The capture that does work through a builder: weaken the builder too.
    @Test func weakSelfOnTheBuilderReleasesTheController() {
        #expect(!controllerSurvivesRelease { WeakSelfOnBuilderController(state: LeakModel()) })
    }

    /// A handler that reaches the controller strongly cannot release it: the
    /// view the runtime keeps the handler on is the controller's own view.
    ///
    /// No builder stands between the handler and `body` here, so this pins the
    /// handler's capture on its own rather than a builder's.
    @Test func aHandlerCapturingSelfStronglyReleasesTheController() {
        withKnownIssue("The node holds the primitive, and the primitive holds the handler that holds the controller.") {
            #expect(!controllerSurvivesRelease { StrongSelfWithoutBuilderController(state: LeakModel()) })
        }
    }

    /// `[weak self]` on the handler is not enough once a builder stands between
    /// the handler and `body`.
    ///
    /// A builder's content closure is `@escaping` and is stored on the
    /// description (`FineStack.vertical`), because a node-local re-render has to
    /// be able to evaluate it again. Mentioning `self` anywhere inside it —
    /// even only to weakly capture it further in — makes the builder itself
    /// capture `self` strongly, and the builder is what the node holds.
    @Test func weakSelfInsideABuilderReleasesTheController() {
        withKnownIssue("The builder captures the controller strongly, whatever ownership the handler inside asks for.") {
            #expect(!controllerSurvivesRelease { WeakSelfInsideBuilderController(state: LeakModel()) })
        }
    }

    /// `unowned` fares no better. What holds the controller is the builder's
    /// capture, so the ownership the handler inside asks for cannot help.
    @Test func unownedSelfInsideABuilderReleasesTheController() {
        withKnownIssue("The builder captures the controller strongly, whatever ownership the handler inside asks for.") {
            #expect(!controllerSurvivesRelease { UnownedSelfInsideBuilderController(state: LeakModel()) })
        }
    }

    /// Navigation reaches the controller by a route of its own, and it is not
    /// the node's.
    ///
    /// `FineObservedScope` holds only its body closure, which
    /// `FineViewController.viewDidLoad` gives `[unowned self]`, and it keeps
    /// neither the `FineNavigation` value nor the bar button once `apply(to:)`
    /// has run. What retains the controller is UIKit's own item:
    /// controller → `navigationItem` → `UIBarButtonItem` → `primaryAction`
    /// (`FineNavigation.update(_:)`) → handler → controller.
    @Test func aBarButtonCapturingSelfStronglyReleasesTheController() {
        withKnownIssue("The navigation item holds the bar button whose action holds the controller.") {
            #expect(!controllerSurvivesRelease { NavigationCapturingController(state: LeakModel()) })
        }
    }

    /// The views a controller rendered must not outlive it. A view held past
    /// its controller keeps its node, its local state, and its handlers alive
    /// with it.
    @Test func renderedViewsDoNotOutliveTheirController() throws {
        weak var releasedRoot: UIView?
        weak var releasedLabel: UIView?

        try autoreleasepool {
            let controller = StateCapturingController(state: LeakModel())
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

    /// `FineUI` holds the tree it built, so releasing it has to release the
    /// views too.
    @Test func fineUIReleasesTheTreeItBuilt() throws {
        let model = LeakModel()
        weak var releasedRoot: UIView?
        weak var releasedFineUI: AnyObject?

        try autoreleasepool {
            let container = UIView(frame: .init(x: 0, y: 0, width: 320, height: 480))
            let fineUI = FineUI(model) { model in
                FineStack.vertical {
                    FineLabel(text: model.title)
                    FineButton(title: "Tap") { model.taps += 1 }
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
