import Observation
import Testing
import UIKit
@testable import FineUIKit

@MainActor
struct BindingScopeTests {
    @Observable
    final class CounterModel {
        var count = 0
        var isEnabled = true
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() { await Task.yield() }
    }

    @Test func eachObserveCallIsAnIndependentUpdateUnit() async throws {
        let model = CounterModel()
        let scope = BindingScope()
        let label = UILabel()
        let button = UIButton(type: .system)
        var log: [String] = []

        scope.observe {
            fineAssign(label.text, "\(model.count)") { label.text = $0; log.append("label") }
        }
        scope.observe {
            fineAssign(button.isEnabled, model.isEnabled) { button.isEnabled = $0; log.append("button") }
        }

        #expect(label.text == "0")
        #expect(log == ["label"]) // button.isEnabled already matched the default, so no write logged

        model.count = 1
        await waitUntil { label.text == "1" }

        // Only the closure that reads `count` re-ran.
        #expect(log == ["label", "label"])
        #expect(button.isEnabled == true)
    }

    @Test func sameValueWriteIsSkipped() async throws {
        let model = CounterModel()
        let scope = BindingScope()
        let label = UILabel()
        var writeCount = 0

        scope.observe {
            fineAssign(label.text, "\(model.count)") { label.text = $0; writeCount += 1 }
        }
        #expect(writeCount == 1)

        model.count = 0 // same value
        for _ in 0..<20 { await Task.yield() }

        #expect(writeCount == 1, "re-running for an unchanged value must not touch the view")
    }

    @Test func invalidateStopsFurtherReruns() async throws {
        let model = CounterModel()
        let scope = BindingScope()
        let label = UILabel()

        scope.observe {
            fineAssign(label.text, "\(model.count)") { label.text = $0 }
        }
        scope.invalidate()

        model.count = 42
        for _ in 0..<20 { await Task.yield() }

        #expect(label.text == "0", "an invalidated scope must not apply further updates")
    }
}
