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
}
