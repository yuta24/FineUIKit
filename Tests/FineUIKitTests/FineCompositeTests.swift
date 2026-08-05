import Testing
import UIKit
@testable import FineUIKit

/// A description composed from user-defined `Renderable` types is resolved by
/// walking `body` to a primitive. These fix what survives that walk: the
/// composite types are part of the view's identity, so swapping one for
/// another rebuilds the view rather than writing into it.
@MainActor
struct FineCompositeTests {
    struct Header: Renderable {
        let text: String

        var body: any Renderable {
            FineLabel(text: text)
        }
    }

    struct Footer: Renderable {
        let text: String

        var body: any Renderable {
            FineLabel(text: text)
        }
    }

    struct Wrapper: Renderable {
        let text: String

        var body: any Renderable {
            Header(text: text)
        }
    }

    @Test func sameCompositeTypeUpdatesInPlace() throws {
        let first = FineRenderer.render(Header(text: "one"))
        let label = try #require(first as? UILabel)

        #expect(label.text == "one")

        let second = FineRenderer.render(Header(text: "two"), reusing: first)

        #expect(second === first)
        #expect(label.text == "two")
    }

    @Test func differentCompositeTypesDoNotShareViews() {
        let first = FineRenderer.render(Header(text: "same"))
        let second = FineRenderer.render(Footer(text: "same"), reusing: first)

        #expect(second !== first)
    }

    /// The primitive both sides resolve to is identical, so only the composite
    /// that wrapped it can tell them apart.
    @Test func nestingDepthIsPartOfIdentity() {
        let first = FineRenderer.render(Wrapper(text: "same"))
        let second = FineRenderer.render(Header(text: "same"), reusing: first)

        #expect(second !== first)
    }

    /// A modifier that renders into its content's own view folds the composite
    /// into its signature, so the swap shows at the top.
    @Test func compositeIdentityReachesPassThroughModifiers() {
        let first = FineRenderer.render(Header(text: "same").backgroundColor(.red))
        let second = FineRenderer.render(Footer(text: "same").backgroundColor(.red), reusing: first)

        #expect(second !== first)
    }

    /// A modifier with a view of its own keeps that view — its signature is
    /// its own — and rebuilds what it hosts.
    @Test func compositeIdentityAppliesInsideAModifierWithItsOwnView() throws {
        let first = FineRenderer.render(Header(text: "same").padding(8))
        let paddingView = try #require(first as? FinePaddingView)
        let hosted = try #require(paddingView.hosted)

        let second = FineRenderer.render(Footer(text: "same").padding(8), reusing: first)

        #expect(second === first)
        #expect(paddingView.hosted !== hosted)
    }

    /// A tree of built-in components alone passes through no composite, so it
    /// carries no composite signature and keeps reusing views as before.
    @Test func builtInComponentsCarryNoCompositeSignature() {
        let primitive = FineRenderer.primitive(for: FineLabel(text: "plain"))

        #expect(!(primitive is FineComposite))
        #expect(!primitive._modifierSignature.contains("composite."))
    }

    @Test func compositeSignatureRecordsTheTypesPassedThrough() {
        let primitive = FineRenderer.primitive(for: Wrapper(text: "x"))
        let signature = primitive._modifierSignature

        #expect(signature.contains("Wrapper"))
        #expect(signature.contains("Header"))
    }

    /// `FineState` is held by the node, and the node goes with the view: a
    /// composite swap that rebuilds the view discards the state too. Asserted
    /// on the value, not only on the view identity — the discarded state is
    /// what makes the rebuild worth forcing.
    @Test func stateIsDiscardedWhenTheCompositeTypeChanges() throws {
        struct Counting: Renderable {
            var body: any Renderable {
                FineState(0) { count in
                    FineButton(title: "\(count.value)") { count.value += 1 }
                }
            }
        }

        struct OtherCounting: Renderable {
            var body: any Renderable {
                FineState(0) { count in
                    FineButton(title: "\(count.value)") { count.value += 1 }
                }
            }
        }

        let first = FineRenderer.render(Counting())
        let button = try #require(firstButton(in: first))
        button.sendActions(for: .primaryActionTriggered)

        // Rendering directly carries no scheduler, so a state change reaches
        // the view on the next render rather than on its own.
        let refreshed = FineRenderer.render(Counting(), reusing: first)
        #expect(firstButton(in: refreshed)?.currentTitle == "1")

        let second = FineRenderer.render(OtherCounting(), reusing: refreshed)

        #expect(second !== refreshed)
        #expect(firstButton(in: second)?.currentTitle == "0")
    }

    /// The same swap between *identical* composite types keeps the state, so
    /// the assertion above is about the type change and not about rendering
    /// twice.
    @Test func stateSurvivesWhenTheCompositeTypeIsUnchanged() throws {
        struct Counting: Renderable {
            var body: any Renderable {
                FineState(0) { count in
                    FineButton(title: "\(count.value)") { count.value += 1 }
                }
            }
        }

        let first = FineRenderer.render(Counting())
        let button = try #require(firstButton(in: first))
        button.sendActions(for: .primaryActionTriggered)

        let second = FineRenderer.render(Counting(), reusing: first)

        #expect(second === first)
        #expect(firstButton(in: second)?.currentTitle == "1")
    }

    private func firstButton(in view: UIView) -> UIButton? {
        if let button = view as? UIButton {
            return button
        }

        for subview in view.subviews {
            if let button = firstButton(in: subview) {
                return button
            }
        }

        return nil
    }
}
