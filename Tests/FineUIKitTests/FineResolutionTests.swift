import Observation
import Testing
import UIKit
@testable import FineUIKit

@MainActor
private final class BodyCounter {
    var count = 0
}

/// Counts its own resolutions. `Renderable.body` is required to be free of side
/// effects; this one breaks that rule deliberately, which is the only way to
/// observe how often the runtime asks for it.
@MainActor
private struct CountingComposite: Renderable {
    let counter: BodyCounter
    var text: String = "x"

    var body: any Renderable {
        counter.count += 1
        return FineLabel(text: text)
    }
}

@Observable
@MainActor
private final class TitleState {
    var title = "A"
}

/// Reads state in `body` itself rather than through a component's autoclosure,
/// so the read belongs to whichever scope resolved the description.
@MainActor
private struct EagerlyReadingComposite: Renderable {
    let state: TitleState

    var body: any Renderable {
        FineLabel(text: state.title)
            .textAlignment(.center)
    }
}

/// A description that a modifier wraps is resolved once per render.
///
/// Every pass-through wrapper used to answer each of the five questions the
/// reconciler asks — signature, key, reuse check, update, debug provider — by
/// walking `body` again, so a composite behind a modifier was rebuilt five
/// times to render it once.
@MainActor
struct FineResolutionTests {
    @Test func styledCompositeResolvesItsBodyOncePerRender() {
        let counter = BodyCounter()

        let view = FineRenderer.render(CountingComposite(counter: counter).backgroundColor(.red))
        #expect(counter.count == 1)

        counter.count = 0
        _ = FineRenderer.render(
            CountingComposite(counter: counter, text: "y").backgroundColor(.red),
            reusing: view
        )
        #expect(counter.count == 1)
    }

    @Test func chainedModifiersResolveTheirContentOncePerRender() {
        let counter = BodyCounter()

        func description(_ text: String) -> any Renderable {
            CountingComposite(counter: counter, text: text)
                .backgroundColor(.red)
                .padding(8)
                .cornerRadius(4)
        }

        let view = FineRenderer.render(description("x"))
        #expect(counter.count == 1)

        counter.count = 0
        _ = FineRenderer.render(description("y"), reusing: view)
        #expect(counter.count == 1)
    }

    @Test func keyedCompositeResolvesItsBodyOncePerRender() {
        let counter = BodyCounter()

        _ = FineRenderer.render(CountingComposite(counter: counter).key("a"))
        #expect(counter.count == 1)
    }

    /// The root's own reuse identity is asked for outside every observation
    /// scope, so the root render primes it inside its own. Without that, a
    /// modifier at the root would resolve its content unobserved and a value
    /// the content's `body` reads would update nothing.
    @Test func rootLevelModifierOverCompositeKeepsObservingItsBody() async {
        let state = TitleState()
        let container = UIView(frame: .init(x: 0, y: 0, width: 320, height: 480))
        let ui = FineUI(state: state) { state in
            EagerlyReadingComposite(state: state)
                .backgroundColor(.red)
        }
        ui.build(to: container)
        container.layoutIfNeeded()

        #expect(label(in: container)?.text == "A")

        state.title = "B"
        for _ in 0..<200 where label(in: container)?.text != "B" {
            await Task.yield()
        }

        #expect(label(in: container)?.text == "B")
    }

    private func label(in view: UIView) -> UILabel? {
        if let label = view as? UILabel, !(view.superview is UIButton) {
            return label
        }

        for subview in view.subviews {
            if let label = label(in: subview) {
                return label
            }
        }

        return nil
    }
}
