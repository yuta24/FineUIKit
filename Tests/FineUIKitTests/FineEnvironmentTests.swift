import Observation
import Testing
import UIKit
@testable import FineUIKit

private struct TestThemeEnvironmentKey: FineEnvironmentKey {
    static let defaultValue = "light"
}

private extension FineEnvironmentValues {
    var theme: String {
        get { self[TestThemeEnvironmentKey.self] }
        set { self[TestThemeEnvironmentKey.self] = newValue }
    }
}

@MainActor
struct FineEnvironmentTests {
    @Observable
    final class ThemeState {
        var theme = "light"
    }

    @Observable
    final class CounterState {
        var counter = 0
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

    @Test func readerUsesDefaultValue() throws {
        let view = FineRenderer.render(
            FineEnvironmentReader { environment in
                FineLabel(text: environment.theme)
            }
        )
        let label = try #require(firstLabel(in: view))

        #expect(label.text == "light")
    }

    @Test func writerInjectsValueIntoReader() throws {
        let view = FineRenderer.render(
            FineEnvironmentReader { environment in
                FineLabel(text: environment.theme)
            }
            .environment(\.theme, "dark")
        )
        let label = try #require(firstLabel(in: view))

        #expect(label.text == "dark")
    }

    @Test func nestedWriterOverridesOuterValue() throws {
        let view = FineRenderer.render(
            FineEnvironmentReader { environment in
                FineLabel(text: environment.theme)
            }
            .environment(\.theme, "b")
            .environment(\.theme, "a")
        )
        let label = try #require(firstLabel(in: view))

        #expect(label.text == "b")
    }

    @Test func observableWriterValueUpdatesReader() async throws {
        let state = ThemeState()
        let container = UIView()
        let fineUI = FineUI(state) { state in
            FineEnvironmentReader { environment in
                FineLabel(text: environment.theme)
            }
            .environment(\.theme, state.theme)
        }
        fineUI.build(to: container)

        let root = try #require(container.subviews.first)
        let label = try #require(firstLabel(in: root))
        #expect(label.text == "light")

        state.theme = "dark"

        for _ in 0..<10 where label.text != "dark" {
            await Task.yield()
        }

        #expect(label.text == "dark")
    }

    @Test func nodeLocalRerenderPreservesInjectedEnvironment() async throws {
        let state = CounterState()
        let container = UIView()
        let fineUI = FineUI(state) { state in
            FineEnvironmentReader { environment in
                FineLabel(text: "\(environment.theme)-\(state.counter)")
            }
            .environment(\.theme, "injected")
        }
        fineUI.build(to: container)

        let root = try #require(container.subviews.first)
        let label = try #require(firstLabel(in: root))
        #expect(label.text == "injected-0")

        state.counter += 1

        for _ in 0..<10 where label.text != "injected-1" {
            await Task.yield()
        }

        #expect(label.text == "injected-1")
    }
}

/// `FineEnvironmentStorage` is what carries a list's environment to its cells.
/// Both properties tested here are load-bearing: cells must not re-render for
/// an unchanged environment, and the list must not become an observer of the
/// storage it writes to.
@MainActor
struct FineEnvironmentStorageTests {
    @MainActor
    final class Fires {
        var count = 0
    }

    private func values(theme: String) -> FineEnvironmentValues {
        var values = FineEnvironmentValues()
        values.theme = theme
        return values
    }

    @Test func republishesOnlyWhenTheEnvironmentDiffers() async throws {
        let storage = FineEnvironmentStorage()
        storage.update(values(theme: "light"))

        let fires = Fires()
        withObservationTracking {
            _ = storage.values
        } onChange: {
            Task { @MainActor in fires.count += 1 }
        }

        // Same values: observers must not be woken.
        storage.update(values(theme: "light"))
        for _ in 0..<20 { await Task.yield() }
        #expect(fires.count == 0)

        storage.update(values(theme: "dark"))
        for _ in 0..<200 where fires.count == 0 { await Task.yield() }
        #expect(fires.count == 1)
        #expect(storage.values.theme == "dark")
    }

    @Test func updatingDoesNotRegisterTheCallerAsAnObserver() async throws {
        let storage = FineEnvironmentStorage()
        storage.update(values(theme: "light"))

        let fires = Fires()
        // A list calls update(_:) from inside its own tracked render. If that
        // registered a read, the next publish would re-render the list, which
        // would publish again.
        withObservationTracking {
            storage.update(values(theme: "dark"))
        } onChange: {
            Task { @MainActor in fires.count += 1 }
        }

        storage.update(values(theme: "sepia"))
        for _ in 0..<20 { await Task.yield() }

        #expect(fires.count == 0)
    }
}
