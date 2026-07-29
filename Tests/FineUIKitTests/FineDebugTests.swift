import Foundation
import Observation
import QuartzCore
import Testing
import UIKit
@testable import FineUIKit

/// Render counting, the debug description, the re-render highlight and the
/// injection toast: what the runtime says about itself.
///
/// Serialized because the highlight and toast switches are process-wide.
@MainActor
@Suite(.serialized)
struct FineDebugTests {
    @Test func countsRendersOfAReusedView() {
        let first = FineRenderer.render(FineLabel(text: "A"))
        #expect(first.fineNodeIfPresent?.renderCount == 1)

        let second = FineRenderer.render(FineLabel(text: "B"), reusing: first)
        #expect(second === first)
        #expect(first.fineNodeIfPresent?.renderCount == 2)
        #expect(first.fineNodeIfPresent?.rebuildCount == 0)
    }

    /// A rebuild makes a new view and a new node, so the counters have to move
    /// with the position — otherwise the churn they exist to expose resets
    /// itself every time it happens.
    @Test func carriesCountersOntoARebuiltView() {
        let first = FineRenderer.render(FineLabel(text: "A"))
        _ = FineRenderer.render(FineLabel(text: "B"), reusing: first)

        let rebuilt = FineRenderer.render(FineImage(image: UIImage()), reusing: first)

        #expect(rebuilt !== first)
        #expect(rebuilt.fineNodeIfPresent?.renderCount == 3)
        #expect(rebuilt.fineNodeIfPresent?.rebuildCount == 1)
    }

    @Test func countsNodeLocalRerenders() async {
        let model = DebugCounter()
        let container = UIView(frame: .init(x: 0, y: 0, width: 320, height: 480))
        var bodyEvaluationCount = 0

        let ui = FineUI(model) { model in
            bodyEvaluationCount += 1
            // `text` is an autoclosure, so the read happens while the label
            // node updates rather than while `body` is evaluated — which is
            // what puts the change in the node's own observation scope.
            return FineLabel(text: "\(model.count)")
        }
        ui.build(to: container)

        let label = try? #require(container.subviews.first)
        #expect(label?.fineNodeIfPresent?.renderCount == 1)

        model.count = 1
        for _ in 0..<200 where (label?.fineNodeIfPresent?.renderCount ?? 0) < 2 {
            await Task.yield()
        }

        // A node-local re-render: no new view, and `body` was never
        // re-evaluated. It reaches the update without passing the reuse
        // decision, so counting there would miss it entirely.
        #expect(bodyEvaluationCount == 1)
        #expect(label?.fineNodeIfPresent?.renderCount == 2)
        #expect(label?.fineNodeIfPresent?.rebuildCount == 0)
        #expect(container.subviews.first === label)
        _ = ui
    }

    /// The component, not the modifier that wrapped it: `.backgroundColor()`
    /// and `.key()` render into the label's own view, so naming them here
    /// would answer a question nobody asked — and the modifier they applied is
    /// already in the signature.
    @Test func describesTheDescriptionBehindAView() {
        let view = FineRenderer.render(FineLabel(text: "A").backgroundColor(.red).key("k"))
        let description = view.fineDebugDescription

        #expect(description.hasPrefix("FineLabel → UILabel"))
        #expect(description.contains("renders 1"))
        #expect(description.contains("key k"))
        #expect(description.contains("modifiers"))
        #expect(description.contains("backgroundColor"))
    }

    /// Every modifier that renders into its content's view has to look through
    /// itself, or the view it shares gets named after whichever one happened to
    /// be outermost.
    @Test func looksThroughEveryModifierThatSharesAView() {
        let cases: [(String, any Renderable)] = [
            ("backgroundColor", FineLabel(text: "A").backgroundColor(.red)),
            ("key", FineLabel(text: "A").key("k")),
            ("onTap", FineLabel(text: "A").onTap {}),
            ("width", FineLabel(text: "A").width(10)),
            ("constraints", FineLabel(text: "A").constraints(id: "c") { _ in [] }),
            ("environment", FineLabel(text: "A").environment(\.traitCollection, .current)),
        ]

        for (name, description) in cases {
            let view = FineRenderer.render(description)
            #expect(
                view.fineDebugDescription.hasPrefix("FineLabel → UILabel"),
                "\(name) named \(view.fineDebugDescription)"
            )
        }
    }

    /// A modifier that makes its own view is a node of its own, and says so.
    @Test func namesModifiersThatOwnAView() {
        let view = FineRenderer.render(FineLabel(text: "A").padding(.init(top: 8, leading: 8, bottom: 8, trailing: 8)))
        let lines = view.fineDumpTree().split(separator: "\n")

        #expect(lines.first?.hasPrefix("FinePadded → FinePaddingView") == true)
        #expect(lines.dropFirst().first?.hasPrefix("  FineLabel → UILabel") == true)
    }

    @Test func marksViewsItDoesNotManage() {
        #expect(UIView().fineDebugDescription.contains("unmanaged"))
    }

    @Test func dumpsTheTreeWithNesting() {
        let view = FineRenderer.render(
            FineStack.vertical {
                FineLabel(text: "A")
                FineLabel(text: "B")
            }
        )
        let dump = view.fineDumpTree()
        let lines = dump.split(separator: "\n", omittingEmptySubsequences: false)

        #expect(lines.count == 3)
        #expect(lines.first?.hasPrefix("FineStack → UIStackView") == true)
        #expect(lines.dropFirst().allSatisfy { $0.hasPrefix("  FineLabel → UILabel") })
    }

    // The highlight and the toast are compiled out of release builds, and so
    // are the tests that reach for them.
    #if DEBUG
    @Test func highlightsRenderedViewsOnlyWhenEnabled() {
        let previous = FineDiagnostics.highlightsRenders
        defer { FineDiagnostics.highlightsRenders = previous }

        FineDiagnostics.highlightsRenders = false
        let quiet = FineRenderer.render(FineLabel(text: "A"))
        #expect(FineDebugHighlight.existingOverlay(in: quiet) == nil)

        FineDiagnostics.highlightsRenders = true
        let lit = FineRenderer.render(FineLabel(text: "A"))
        let overlay = FineDebugHighlight.existingOverlay(in: lit)

        #expect(overlay != nil)
        #expect((overlay?.sublayers?.first as? CATextLayer)?.string as? String == "1")
    }

    /// A view that renders repeatedly gets one overlay, not a stack of them.
    @Test func reusesTheHighlightOverlay() {
        let previous = FineDiagnostics.highlightsRenders
        defer { FineDiagnostics.highlightsRenders = previous }
        FineDiagnostics.highlightsRenders = true

        let view = FineRenderer.render(FineLabel(text: "A"))
        _ = FineRenderer.render(FineLabel(text: "B"), reusing: view)

        let overlays = view.layer.sublayers?.filter { $0.name == FineDebugHighlight.layerName } ?? []
        #expect(overlays.count == 1)
        #expect((overlays.first?.sublayers?.first as? CATextLayer)?.string as? String == "2")
    }

    @Test func announcesAnInjectionReload() async {
        let previous = FineDiagnostics.showsInjectionToast
        defer { FineDiagnostics.showsInjectionToast = previous }
        FineDiagnostics.showsInjectionToast = true

        let window = UIWindow(frame: .init(x: 0, y: 0, width: 320, height: 480))
        let container = UIView()
        window.addSubview(container)

        let ui = FineUI(DebugCounter()) { model in
            FineLabel(text: "\(model.count)")
        }
        // An instance-specific name keeps this post from re-rendering every
        // live FineUI in concurrently running tests.
        let notificationName = Notification.Name("FineUIKitTests.toast.\(UUID().uuidString)")
        ui.injectionNotificationName = notificationName
        ui.build(to: container)

        NotificationCenter.default.post(name: notificationName, object: nil)

        for _ in 0..<200 where !window.subviews.contains(where: { $0 is FineDebugToast }) {
            await Task.yield()
        }

        let toast = try? #require(window.subviews.compactMap { $0 as? FineDebugToast }.first)
        #expect(toast?.alpha == 1)
        // A banner that ate a tap would be worse than no banner.
        #expect(toast?.isUserInteractionEnabled == false)
        _ = ui
    }

    /// Every live tree re-renders on the same notification, so the banner has
    /// to count them rather than stack one per controller.
    @Test func coalescesOneToastForEveryTreeThatReloaded() async {
        let previous = FineDiagnostics.showsInjectionToast
        defer { FineDiagnostics.showsInjectionToast = previous }
        FineDiagnostics.showsInjectionToast = true

        let window = UIWindow(frame: .init(x: 0, y: 0, width: 320, height: 480))
        let notificationName = Notification.Name("FineUIKitTests.toast.\(UUID().uuidString)")

        let trees = (0..<3).map { _ -> FineUI<DebugCounter> in
            let container = UIView()
            window.addSubview(container)

            let ui = FineUI(DebugCounter()) { model in
                FineLabel(text: "\(model.count)")
            }
            ui.injectionNotificationName = notificationName
            ui.build(to: container)
            return ui
        }

        NotificationCenter.default.post(name: notificationName, object: nil)

        for _ in 0..<200 where !window.subviews.contains(where: { $0 is FineDebugToast }) {
            await Task.yield()
        }
        for _ in 0..<50 {
            await Task.yield()
        }

        let toasts = window.subviews.compactMap { $0 as? FineDebugToast }
        #expect(toasts.count == 1)
        #expect(toasts.first?.message == "FineUIKit reloaded ×3")
        _ = trees
    }

    @Test func staysSilentWhenTheToastIsDisabled() async {
        let previous = FineDiagnostics.showsInjectionToast
        defer { FineDiagnostics.showsInjectionToast = previous }
        FineDiagnostics.showsInjectionToast = false

        let window = UIWindow(frame: .init(x: 0, y: 0, width: 320, height: 480))
        let container = UIView()
        window.addSubview(container)

        let ui = FineUI(DebugCounter()) { model in
            FineLabel(text: "\(model.count)")
        }
        let notificationName = Notification.Name("FineUIKitTests.toast.\(UUID().uuidString)")
        ui.injectionNotificationName = notificationName
        ui.build(to: container)

        NotificationCenter.default.post(name: notificationName, object: nil)
        for _ in 0..<50 {
            await Task.yield()
        }

        #expect(!window.subviews.contains { $0 is FineDebugToast })
        _ = ui
    }
    #endif
}

@Observable
private final class DebugCounter {
    var count = 0
}
