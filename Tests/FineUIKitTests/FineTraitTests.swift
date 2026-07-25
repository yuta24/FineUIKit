import Observation
import Testing
import UIKit
@testable import FineUIKit

@MainActor
private final class TraitRenderCounts {
    var counts: [String: Int] = [:]
}

@MainActor
private let traitRenderCounts = TraitRenderCounts()

@MainActor
private struct TraitCountingProbe: FineViewRepresentable {
    let tag: String

    func makeView() -> UILabel {
        UILabel()
    }

    func updateView(_ view: UILabel, environment: FineEnvironmentValues) {
        traitRenderCounts.counts[tag, default: 0] += 1
    }
}

@Observable
private final class TraitState {
    var value = 0
}

private struct TraitRow: Identifiable, Equatable {
    let id: Int
}

/// Trait changes re-evaluate the description, and the traits themselves are
/// readable from it.
@MainActor
@Suite(.serialized)
struct FineTraitTests {
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

    private func makeWindow() -> (UIWindow, UIView) {
        let window = UIWindow(frame: .init(x: 0, y: 0, width: 320, height: 600))
        window.isHidden = false
        let container = UIView(frame: window.bounds)
        window.addSubview(container)
        return (window, container)
    }

    private func firstLabel(in view: UIView) -> UILabel? {
        if let label = view as? UILabel {
            return label
        }

        for subview in view.subviews {
            if let label = firstLabel(in: subview) {
                return label
            }
        }

        return nil
    }

    // MARK: - Dynamic Type

    @Test func labelFollowsContentSizeCategory() async throws {
        let (window, container) = makeWindow()
        let ui = FineUI(TraitState()) { _ in
            FineLabel(text: "Hello")
                .font(.preferredFont(forTextStyle: .body))
        }
        ui.build(to: container)
        window.layoutIfNeeded()
        await waitTicks()

        let label = try #require(firstLabel(in: container))
        let before = label.font.pointSize

        window.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraLarge
        window.layoutIfNeeded()
        await waitUntil { label.font.pointSize > before }

        #expect(label.font.pointSize > before)
        _ = ui
    }

    /// The description resolves a preferred font when it is built, so it has to
    /// be rebuilt — otherwise the next unrelated update writes the old size back.
    @Test func rerenderKeepsTheScaledFont() async throws {
        let (window, container) = makeWindow()
        let state = TraitState()
        let ui = FineUI(state) { state in
            FineStack.vertical {
                FineLabel(text: "\(state.value)")
                    .font(.preferredFont(forTextStyle: .body))
            }
        }
        ui.build(to: container)
        window.layoutIfNeeded()
        await waitTicks()

        let label = try #require(firstLabel(in: container))
        let before = label.font.pointSize

        window.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraLarge
        window.layoutIfNeeded()
        await waitUntil { label.font.pointSize > before }
        let scaled = label.font.pointSize

        // An unrelated change re-runs the label's update with a freshly built
        // description.
        state.value += 1
        await waitUntil { label.text == "1" }

        #expect(label.font.pointSize == scaled)
        _ = ui
    }

    // MARK: - traits in the environment

    @Test func descriptionReadsTraitsFromEnvironment() async throws {
        let (window, container) = makeWindow()
        window.traitOverrides.userInterfaceStyle = .light

        let ui = FineUI(TraitState()) { _ in
            FineEnvironmentReader { environment in
                FineLabel(text: environment.traitCollection.userInterfaceStyle == .dark ? "dark" : "light")
            }
        }
        ui.build(to: container)
        window.layoutIfNeeded()
        await waitTicks()

        #expect(firstLabel(in: container)?.text == "light")

        window.traitOverrides.userInterfaceStyle = .dark
        window.layoutIfNeeded()
        await waitUntil { self.firstLabel(in: container)?.text == "dark" }

        #expect(firstLabel(in: container)?.text == "dark")
        _ = ui
    }

    @Test func traitChangeRerendersTheTree() async throws {
        let (window, container) = makeWindow()
        let ui = FineUI(TraitState()) { _ in
            FineStack.vertical {
                TraitCountingProbe(tag: "trait-tree")
            }
        }
        ui.build(to: container)
        window.layoutIfNeeded()
        await waitTicks()

        let base = traitRenderCounts.counts["trait-tree", default: 0]
        window.traitOverrides.horizontalSizeClass = .regular
        window.layoutIfNeeded()
        await waitUntil { traitRenderCounts.counts["trait-tree", default: 0] > base }

        #expect(traitRenderCounts.counts["trait-tree", default: 0] > base)
        _ = ui
    }

    /// Trait changes reach rows through the environment, so an unchanged
    /// element does not keep a cell on the old traits.
    @Test func traitChangeReachesVisibleCells() async throws {
        let (window, container) = makeWindow()
        window.traitOverrides.userInterfaceStyle = .light

        let ui = FineUI(TraitState()) { _ in
            FineList([TraitRow(id: 1)]) { _ in
                FineEnvironmentReader { environment in
                    FineLabel(text: environment.traitCollection.userInterfaceStyle == .dark ? "dark" : "light")
                }
            }
        }
        ui.build(to: container)
        window.layoutIfNeeded()
        await waitTicks()

        func cellText() -> String? {
            guard let tableView = container.subviews.compactMap({ $0 as? UITableView }).first else { return nil }
            tableView.layoutIfNeeded()
            guard let cell = tableView.cellForRow(at: .init(row: 0, section: 0)) else { return nil }
            return firstLabel(in: cell)?.text
        }

        await waitUntil { cellText() == "light" }
        #expect(cellText() == "light")

        window.traitOverrides.userInterfaceStyle = .dark
        window.layoutIfNeeded()
        await waitUntil { cellText() == "dark" }

        #expect(cellText() == "dark")
        _ = ui
    }

    /// A hidden screen defers trait work like any other observed change.
    @Test func traitChangeWhileSuspendedIsDeferred() async throws {
        let (window, container) = makeWindow()
        let ui = FineUI(TraitState()) { _ in
            FineStack.vertical {
                TraitCountingProbe(tag: "trait-suspended")
            }
        }
        ui.build(to: container)
        window.layoutIfNeeded()
        await waitTicks()

        let base = traitRenderCounts.counts["trait-suspended", default: 0]
        ui.suspend()
        window.traitOverrides.legibilityWeight = .bold
        window.layoutIfNeeded()
        await waitTicks()
        #expect(traitRenderCounts.counts["trait-suspended", default: 0] - base == 0)

        ui.resume()
        await waitUntil { traitRenderCounts.counts["trait-suspended", default: 0] - base == 1 }
        #expect(traitRenderCounts.counts["trait-suspended", default: 0] - base == 1)
    }
}
