#if DEBUG
import Observation
import Testing
import UIKit
@testable import FineUIKit

@Observable
@MainActor
private final class Caption {
    var text = "A"
}

/// Reads its state in `makeView()`, which is the mistake.
@MainActor
private struct ReadsWhileCreating: FineViewRepresentable {
    let caption: Caption

    func makeView() -> UILabel {
        let label = UILabel()
        label.text = caption.text
        return label
    }

    func updateView(_ view: UILabel, environment: FineEnvironmentValues) {}
}

/// Reads its state in both places. The `makeView()` read is redundant rather
/// than broken — `updateView` keeps the label current — but it is still a read
/// that does nothing, and the runtime cannot tell the two cases apart.
@MainActor
private struct ReadsWhileCreatingAndUpdating: FineViewRepresentable {
    let caption: Caption

    func makeView() -> UILabel {
        let label = UILabel()
        label.text = caption.text
        return label
    }

    func updateView(_ view: UILabel, environment: FineEnvironmentValues) {
        view.text = caption.text
    }
}

/// Reads its state where it belongs.
@MainActor
private struct ReadsWhileUpdating: FineViewRepresentable {
    let caption: Caption

    func makeView() -> UILabel {
        UILabel()
    }

    func updateView(_ view: UILabel, environment: FineEnvironmentValues) {
        view.text = caption.text
    }
}

/// `makeView()` runs once per view identity and outside every observation
/// scope, so a value read there is never tracked and changing it later does
/// nothing at all. The view keeps showing what the value was the first time,
/// with no error and no rebuild — which is the worst way for it to be wrong.
///
/// Serialized because the diagnostics handler is process-wide.
@MainActor
@Suite(.serialized)
struct FineMakeViewObservationTests {
    private func captureMessages(_ body: @MainActor () async -> Void) async -> [String] {
        let previous = FineDiagnostics.handler
        defer { FineDiagnostics.handler = previous }

        // The box outlives the handler assignment, so a message that arrives on
        // a later turn is still collected.
        let messages = Messages()
        FineDiagnostics.handler = { messages.all.append($0) }
        await body()
        return messages.all
    }

    @MainActor
    private final class Messages {
        var all: [String] = []
    }

    private func waitTicks(_ count: Int = 40) async {
        for _ in 0..<count {
            await Task.yield()
        }
    }

    @Test func aValueReadWhileCreatingAViewIsReportedWhenItChanges() async {
        let caption = Caption()

        let messages = await captureMessages {
            let view = FineRenderer.render(ReadsWhileCreating(caption: caption))
            #expect((view as? UILabel)?.text == "A")

            caption.text = "B"
            await waitTicks()

            // The silent part: nothing re-reads it, so the label still says "A".
            #expect((view as? UILabel)?.text == "A")
        }

        let report = messages.first { $0.contains("ReadsWhileCreating") }
        #expect(report != nil)
        #expect(report?.contains("makeView") == true)
        #expect(report?.contains("updateView") == true)
    }

    /// Reading in both places is reported too, and the view is fine.
    ///
    /// The runtime sees a read it knows will not apply the change; it cannot
    /// see that another read elsewhere will. So this is a hint about a pointless
    /// read rather than a report of a broken view — which is why it is a
    /// message and not an assertion, and why the wording says what the read did
    /// rather than what the view will do.
    @Test func readingInBothPlacesIsStillReportedButStillWorks() async {
        let caption = Caption()
        let container = UIView()

        let messages = await captureMessages {
            let ui = FineUI(state: caption) { caption in
                ReadsWhileCreatingAndUpdating(caption: caption)
            }
            ui.build(to: container)
            await waitTicks()

            caption.text = "B"
            await waitTicks()

            #expect((container.subviews.first as? UILabel)?.text == "B")
            _ = ui
        }

        #expect(messages.contains { $0.contains("ReadsWhileCreatingAndUpdating") })
    }

    @Test func aValueReadWhileUpdatingIsNotReported() async {
        let caption = Caption()

        let messages = await captureMessages {
            let view = FineRenderer.render(ReadsWhileUpdating(caption: caption))
            #expect((view as? UILabel)?.text == "A")

            caption.text = "B"
            await waitTicks()
        }

        #expect(messages.allSatisfy { !$0.contains("makeView") })
    }

    /// The same, through the path a real tree takes.
    ///
    /// `FineRenderer.render` is the synchronous path tests use; a mounted tree
    /// creates its views through the scheduler, and a check that only covered
    /// one of the two would miss every app.
    @Test func theSchedulerPathReportsItToo() async {
        let caption = Caption()
        let container = UIView()

        let messages = await captureMessages {
            let ui = FineUI(state: caption) { caption in
                ReadsWhileCreating(caption: caption)
            }
            ui.build(to: container)
            await waitTicks()

            caption.text = "B"
            await waitTicks()
            _ = ui
        }

        #expect(messages.contains { $0.contains("ReadsWhileCreating") && $0.contains("makeView") })
    }

    /// A description that reads nothing while creating registers nothing, so
    /// the check costs a tree of plain components nothing at all.
    @Test func aTreeThatReadsNothingWhileCreatingSaysNothing() async {
        let caption = Caption()

        let messages = await captureMessages {
            _ = FineRenderer.render(FineStack.vertical {
                FineLabel(text: caption.text)
                FineButton(title: "Action") {}
            })

            caption.text = "B"
            await waitTicks()
        }

        #expect(messages.allSatisfy { !$0.contains("makeView") })
    }
}
#endif
