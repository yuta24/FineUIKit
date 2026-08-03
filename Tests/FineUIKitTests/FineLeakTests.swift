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

/// Captures only the state object, which is all a description normally needs.
@MainActor
private final class StateCapturingController: FineViewController<LeakModel> {
    override class func body(_ state: LeakModel, _ screen: FineScreen) -> any Renderable {
        FineStack.vertical {
            FineLabel(text: state.title)
            FineButton(title: "Tap") { state.taps += 1 }
        }
    }
}

/// Captures the `FineScreen` from inside a builder — the shape that used to
/// leak when the same reach for the controller was spelled `self`.
@MainActor
private final class ScreenCapturingController: FineViewController<LeakModel> {
    override class func body(_ state: LeakModel, _ screen: FineScreen) -> any Renderable {
        FineStack.vertical {
            FineLabel(text: state.title)
            FineButton(title: "Close") { screen.dismiss() }
            FineButton(title: "Edit") { screen.withController { $0.setEditing(true, animated: false) } }
        }
    }
}

/// Reaches the controller from a bar button, which `navigationItem` retains.
@MainActor
private final class NavigationCapturingController: FineViewController<LeakModel> {
    override class func body(_ state: LeakModel, _ screen: FineScreen) -> any Renderable {
        FineLabel(text: state.title)
    }

    override class func navigation(_ state: LeakModel, _ screen: FineScreen) -> FineNavigation? {
        FineNavigation(title: state.title)
            .trailing(FineBarButton(title: "Add") { screen.endEditing() })
    }
}

/// Overrides the pre-`FineScreen` instance method, which puts the controller
/// back in scope. Kept to pin down that the legacy path still carries the old
/// hazard, and that nothing else does.
@MainActor
private final class LegacyInstanceBodyController: FineViewController<LeakModel> {
    var taps = 0

    override func body(_ state: LeakModel) -> any Renderable {
        FineStack.vertical {
            FineLabel(text: state.title)
            FineButton(title: "Tap") { self.taps += 1 }
        }
    }
}

/// What the render tree keeps alive after the object that built it goes away.
///
/// The runtime attaches a `FineNode` to every managed view and holds the
/// primitive that last rendered it (`FineNodeScheduler.renderChild`), so a
/// handler closure lives on the view for as long as the view does. A closure
/// that captured the controller would therefore close the cycle
/// controller → view → node → primitive → closure → controller.
///
/// `body(_:_:)` and `navigation(_:_:)` are type methods, so that closure cannot
/// be written: the controller is not in scope, and `FineScreen` — the way back
/// to it — holds it weakly. These tests pin down that the shapes which remain
/// writable all release, and that the one route still able to capture the
/// controller is the deprecated instance override.
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

    /// `FineScreen` is the sanctioned route back to the controller, so a
    /// description that uses it — from inside a builder, which is where the
    /// old capture rule broke down — must still release.
    @Test func aTreeCapturingTheScreenReleasesTheController() {
        #expect(!controllerSurvivesRelease { ScreenCapturingController(state: LeakModel()) })
    }

    /// Navigation reaches the controller by a route of its own: controller →
    /// `navigationItem` → `UIBarButtonItem` → `primaryAction` → handler. A
    /// handler that can only hold the screen weakly cannot close it.
    @Test func aBarButtonCapturingTheScreenReleasesTheController() {
        #expect(!controllerSurvivesRelease { NavigationCapturingController(state: LeakModel()) })
    }

    /// The one shape that still leaks, and the reason the type method exists.
    ///
    /// Written as the release it ought to achieve and marked `withKnownIssue`,
    /// so retiring the instance override reports the known issue as no longer
    /// occurring rather than passing quietly.
    @Test func aLegacyInstanceBodyCapturingSelfReleasesTheController() {
        withKnownIssue("Overriding the instance method puts the controller back in scope, and the node holds what the description captured.") {
            #expect(!controllerSurvivesRelease { LegacyInstanceBodyController(state: LeakModel()) })
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
