import Observation
import Testing
import UIKit
@testable import FineUIKit

@Observable
private final class DiagnosticsState {
    var isRounded = false
}

/// A uniquely named view type, so an assertion on an asynchronous test cannot
/// match a rebuild reported by a suite running in parallel.
private final class DiagnosticsMarkerView: UILabel {}

@MainActor
private struct DiagnosticsMarker: FineViewRepresentable {
    func makeView() -> DiagnosticsMarkerView {
        DiagnosticsMarkerView()
    }

    func updateView(_ view: DiagnosticsMarkerView, environment: FineEnvironmentValues) {}
}

/// Rebuild reporting: the reconciler explains why a view could not be reused.
@MainActor
@Suite(.serialized)
struct FineDiagnosticsTests {
    /// Captures messages for the duration of `body`, restoring the previous
    /// settings afterwards so other suites are unaffected.
    private func captureMessages(_ body: () -> Void) -> [String] {
        let previousHandler = FineDiagnostics.handler
        let previousFlag = FineDiagnostics.logsViewReuse
        defer {
            FineDiagnostics.handler = previousHandler
            FineDiagnostics.logsViewReuse = previousFlag
        }

        var messages: [String] = []
        FineDiagnostics.handler = { messages.append($0) }
        FineDiagnostics.logsViewReuse = true
        body()
        return messages
    }

    @Test func reportsModifierCompositionChange() {
        let messages = captureMessages {
            let first = FineRenderer.render(FineLabel(text: "A").backgroundColor(.red))
            _ = FineRenderer.render(
                FineLabel(text: "A").backgroundColor(.red).cornerRadius(8),
                reusing: first
            )
        }

        let report = try? #require(messages.first)
        #expect(messages.count == 1)
        // The component that made the view, not the modifier that wrapped it.
        #expect(report?.contains("UILabel for FineLabel") == true)
        #expect(report?.contains("modifier composition changed") == true)
        #expect(report?.contains("cornerRadius") == true)
    }

    @Test func reportsIncompatibleViewType() {
        let messages = captureMessages {
            let first = FineRenderer.render(FineLabel(text: "A"))
            _ = FineRenderer.render(FineImage(image: UIImage()), reusing: first)
        }

        #expect(messages.count == 1)
        #expect(messages.first?.contains("view type is incompatible") == true)
    }

    @Test func reportsKeyChange() {
        let messages = captureMessages {
            let first = FineRenderer.render(FineLabel(text: "A").key("a"))
            _ = FineRenderer.render(FineLabel(text: "A").key("b"), reusing: first)
        }

        #expect(messages.count == 1)
        #expect(messages.first?.contains("key changed (a → b)") == true)
    }

    @Test func reportsNothingWhenTheViewIsReused() {
        let messages = captureMessages {
            let first = FineRenderer.render(FineLabel(text: "A").backgroundColor(.red))
            _ = FineRenderer.render(FineLabel(text: "B").backgroundColor(.blue), reusing: first)
        }

        #expect(messages.isEmpty)
    }

    @Test func reportsNothingWhileDisabled() {
        let previousFlag = FineDiagnostics.logsViewReuse
        let previousHandler = FineDiagnostics.handler
        defer {
            FineDiagnostics.logsViewReuse = previousFlag
            FineDiagnostics.handler = previousHandler
        }

        var messages: [String] = []
        FineDiagnostics.handler = { messages.append($0) }
        FineDiagnostics.logsViewReuse = false

        let first = FineRenderer.render(FineLabel(text: "A"))
        _ = FineRenderer.render(FineImage(image: UIImage()), reusing: first)

        #expect(messages.isEmpty)
    }

    /// Renders that reuse their view report nothing to the rebuild log, which
    /// is the question `logsRenders` exists to answer instead.
    @Test func reportsEveryRenderWhenAskedTo() {
        let previousHandler = FineDiagnostics.handler
        let previousFlag = FineDiagnostics.logsRenders
        defer {
            FineDiagnostics.handler = previousHandler
            FineDiagnostics.logsRenders = previousFlag
        }

        var messages: [String] = []
        FineDiagnostics.handler = { messages.append($0) }
        FineDiagnostics.logsRenders = true

        let first = FineRenderer.render(DiagnosticsMarker())
        _ = FineRenderer.render(DiagnosticsMarker(), reusing: first)
        FineDiagnostics.logsRenders = false

        let reports = messages.filter { $0.contains("DiagnosticsMarkerView") }
        #expect(reports.count == 2)
        #expect(reports.first?.contains("created") == true)
        #expect(reports.last?.contains("updated") == true)
        #expect(reports.last?.contains("render #2") == true)
    }

    /// The scheduler path decides reuse through the same helper, so rebuilds
    /// are reported there too.
    @Test func reportsRebuildsOnTheScheduledPath() async {
        let container = UIView(frame: .init(x: 0, y: 0, width: 320, height: 480))
        var messages: [String] = []

        let previousHandler = FineDiagnostics.handler
        let previousFlag = FineDiagnostics.logsViewReuse
        defer {
            FineDiagnostics.handler = previousHandler
            FineDiagnostics.logsViewReuse = previousFlag
        }
        FineDiagnostics.handler = { messages.append($0) }
        FineDiagnostics.logsViewReuse = true

        let state = DiagnosticsState()
        let ui = FineUI(state) { state in
            FineStack.vertical {
                state.isRounded
                    ? DiagnosticsMarker().backgroundColor(.red).cornerRadius(8)
                    : DiagnosticsMarker().backgroundColor(.red)
            }
        }
        ui.build(to: container)
        messages.removeAll()

        // Changing the modifier composition rebuilds the child through the
        // scheduler, not through FineRenderer's synchronous path.
        state.isRounded = true
        for _ in 0..<200 where !messages.contains(where: { $0.contains("DiagnosticsMarkerView") }) {
            await Task.yield()
        }

        #expect(messages.contains { $0.contains("DiagnosticsMarkerView") && $0.contains("modifier composition changed") })
        _ = ui
    }
}
