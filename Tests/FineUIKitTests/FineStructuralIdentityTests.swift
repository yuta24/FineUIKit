import Testing
import UIKit
@testable import FineUIKit

/// A child that a conditional or a loop produced must not be able to shift the
/// position its straight-line siblings are matched at.
///
/// Builder children with no key are reconciled by position among themselves, so
/// before structural slots a disappearing `if` moved every later sibling up one
/// place: the sibling was handed the conditional's old view, and — when the two
/// were not compatible — rebuilt, losing first responder status and `FineState`
/// for a change that had nothing to do with it.
@MainActor
struct FineStructuralIdentityTests {
    private final class Box<Value> {
        var value: Value?
    }

    private struct Item: Identifiable {
        let id: String
        let title: String
    }

    @Test func disappearingConditionalKeepsSiblingViewIdentity() throws {
        func tree(_ showsBanner: Bool) -> any Renderable {
            FineStack.vertical {
                if showsBanner {
                    FineLabel(text: "banner")
                }
                FineButton(title: "Action") {}
            }
        }

        let stack = FineRenderer.render(tree(true))
        let stackView = try #require(stack as? UIStackView)
        #expect(stackView.arrangedSubviews.count == 2)
        let button = try #require(stackView.arrangedSubviews[1] as? UIButton)

        _ = FineRenderer.render(tree(false), reusing: stack)

        #expect(stackView.arrangedSubviews.count == 1)
        #expect(stackView.arrangedSubviews[0] === button)
    }

    @Test func appearingConditionalKeepsSiblingViewIdentity() throws {
        func tree(_ showsBanner: Bool) -> any Renderable {
            FineStack.vertical {
                if showsBanner {
                    FineLabel(text: "banner")
                }
                FineButton(title: "Action") {}
            }
        }

        let stack = FineRenderer.render(tree(false))
        let stackView = try #require(stack as? UIStackView)
        let button = try #require(stackView.arrangedSubviews[0] as? UIButton)

        _ = FineRenderer.render(tree(true), reusing: stack)

        #expect(stackView.arrangedSubviews.count == 2)
        #expect(stackView.arrangedSubviews[1] === button)
    }

    /// The state a sibling owns is the thing an unintended rebuild silently
    /// throws away, so it is asserted on directly rather than through the view.
    @Test func disappearingConditionalKeepsSiblingLocalState() throws {
        let binding = Box<FineBinding<Int>>()

        func tree(_ showsBanner: Bool) -> any Renderable {
            FineStack.vertical {
                if showsBanner {
                    FineLabel(text: "banner")
                }
                FineState(0) { value in
                    binding.value = value
                    return FineLabel(text: "count \(value.value)")
                }
            }
        }

        let stack = FineRenderer.render(tree(true))
        let stackView = try #require(stack as? UIStackView)
        let reader = stackView.arrangedSubviews[1]

        try #require(binding.value).value = 5
        _ = FineRenderer.render(tree(true), reusing: stack)
        #expect(firstLabel(in: reader)?.text == "count 5")

        _ = FineRenderer.render(tree(false), reusing: stack)

        #expect(stackView.arrangedSubviews[0] === reader)
        #expect(firstLabel(in: reader)?.text == "count 5")
    }

    @Test func shrinkingLoopKeepsSiblingViewIdentity() throws {
        func tree(_ items: [String]) -> any Renderable {
            FineStack.vertical {
                for item in items {
                    FineLabel(text: item)
                }
                FineButton(title: "Footer") {}
            }
        }

        let stack = FineRenderer.render(tree(["A", "B", "C"]))
        let stackView = try #require(stack as? UIStackView)
        let footer = try #require(stackView.arrangedSubviews[3] as? UIButton)

        _ = FineRenderer.render(tree(["A"]), reusing: stack)

        #expect(stackView.arrangedSubviews.count == 2)
        #expect(stackView.arrangedSubviews[1] === footer)
    }

    /// Two conditionals in one builder occupy different slots, so the second one
    /// appearing must not adopt the view the first one left behind.
    @Test func separateConditionalsDoNotShareOneView() throws {
        func tree(_ showsFirst: Bool, _ showsSecond: Bool) -> any Renderable {
            FineStack.vertical {
                if showsFirst {
                    FineLabel(text: "first")
                }
                if showsSecond {
                    FineLabel(text: "second")
                }
            }
        }

        let stack = FineRenderer.render(tree(true, false))
        let stackView = try #require(stack as? UIStackView)
        let first = stackView.arrangedSubviews[0]

        _ = FineRenderer.render(tree(false, true), reusing: stack)

        #expect(stackView.arrangedSubviews.count == 1)
        #expect(stackView.arrangedSubviews[0] !== first)
        #expect((stackView.arrangedSubviews[0] as? UILabel)?.text == "second")
    }

    /// A key inside a conditional still decides identity within that slot, or
    /// `FineForEach` would stop following a reorder as soon as it was wrapped
    /// in an `if`.
    @Test func keyedChildrenInsideConditionalStillFollowReorder() throws {
        let a = Item(id: "a", title: "A")
        let b = Item(id: "b", title: "B")

        func tree(_ items: [Item]) -> any Renderable {
            FineStack.vertical {
                if !items.isEmpty {
                    FineForEach(items) { item in
                        FineLabel(text: item.title)
                    }
                }
            }
        }

        let stack = FineRenderer.render(tree([a, b]))
        let stackView = try #require(stack as? UIStackView)
        let viewA = stackView.arrangedSubviews[0]
        let viewB = stackView.arrangedSubviews[1]

        _ = FineRenderer.render(tree([b, a]), reusing: stack)

        #expect(stackView.arrangedSubviews[0] === viewB)
        #expect(stackView.arrangedSubviews[1] === viewA)
    }

    /// A key inside a `for` loop must follow its item across a reorder. The
    /// iteration index is where the child *appeared*, not which child it is, so
    /// it must stay out of a keyed child's identity.
    @Test func keyedChildrenInALoopFollowReorder() throws {
        let a = Item(id: "a", title: "A")
        let b = Item(id: "b", title: "B")

        func tree(_ items: [Item]) -> any Renderable {
            FineStack.vertical {
                for item in items {
                    FineLabel(text: item.title)
                        .key(item.id)
                }
            }
        }

        let stack = FineRenderer.render(tree([a, b]))
        let stackView = try #require(stack as? UIStackView)
        let viewA = stackView.arrangedSubviews[0]
        let viewB = stackView.arrangedSubviews[1]

        _ = FineRenderer.render(tree([b, a]), reusing: stack)

        #expect(stackView.arrangedSubviews[0] === viewB)
        #expect(stackView.arrangedSubviews[1] === viewA)
    }

    /// Local state follows the key too, which is the part a positional slot
    /// would silently throw away.
    @Test func keyedLocalStateInALoopFollowsReorder() throws {
        let bindings = Box<[String: FineBinding<Int>]>()
        bindings.value = [:]

        func tree(_ ids: [String]) -> any Renderable {
            FineStack.vertical {
                for id in ids {
                    FineState(0) { value in
                        bindings.value?[id] = value
                        return FineLabel(text: "\(id)=\(value.value)")
                    }
                    .key(id)
                }
            }
        }

        let stack = FineRenderer.render(tree(["a", "b"]))
        let stackView = try #require(stack as? UIStackView)

        try #require(bindings.value?["b"]).value = 5
        _ = FineRenderer.render(tree(["a", "b"]), reusing: stack)
        #expect(firstLabel(in: stackView.arrangedSubviews[1])?.text == "b=5")

        _ = FineRenderer.render(tree(["b", "a"]), reusing: stack)

        #expect(firstLabel(in: stackView.arrangedSubviews[0])?.text == "b=5")
        #expect(firstLabel(in: stackView.arrangedSubviews[1])?.text == "a=0")
    }

    /// Every branch of one conditional shares a slot, however the compiler
    /// spells it. A `switch` becomes nested `buildEither` calls, so a slot per
    /// nesting level would make the first case shallower than the rest — one
    /// transition rebuilding the view while another updated it in place.
    @Test func switchBranchesShareOneSlot() throws {
        enum Mode {
            case a, b, c
        }

        func tree(_ mode: Mode) -> any Renderable {
            FineStack.vertical {
                switch mode {
                case .a:
                    FineLabel(text: "A")
                case .b:
                    FineLabel(text: "B")
                case .c:
                    FineLabel(text: "C")
                }
            }
        }

        let stack = FineRenderer.render(tree(.a))
        let stackView = try #require(stack as? UIStackView)
        let label = stackView.arrangedSubviews[0]

        for mode in [Mode.b, .c, .a] {
            _ = FineRenderer.render(tree(mode), reusing: stack)
            #expect(stackView.arrangedSubviews.count == 1)
            #expect(stackView.arrangedSubviews[0] === label)
        }

        #expect((label as? UILabel)?.text == "A")
    }

    /// The same rule for an `else if` chain, which the compiler also nests.
    @Test func elseIfChainBranchesShareOneSlot() throws {
        func tree(_ value: Int) -> any Renderable {
            FineStack.vertical {
                if value == 0 {
                    FineLabel(text: "zero")
                } else if value == 1 {
                    FineLabel(text: "one")
                } else {
                    FineLabel(text: "many")
                }
                FineButton(title: "Footer") {}
            }
        }

        let stack = FineRenderer.render(tree(0))
        let stackView = try #require(stack as? UIStackView)
        let label = stackView.arrangedSubviews[0]
        let footer = stackView.arrangedSubviews[1]

        for value in [1, 2, 0] {
            _ = FineRenderer.render(tree(value), reusing: stack)
            #expect(stackView.arrangedSubviews[0] === label)
            #expect(stackView.arrangedSubviews[1] === footer)
        }
    }

    /// Nesting must not collapse two conditionals onto one slot.
    @Test func nestedConditionalsGetDistinctSlots() throws {
        func tree(_ outer: Bool, _ inner: Bool) -> any Renderable {
            FineStack.vertical {
                if outer {
                    if inner {
                        FineLabel(text: "inner")
                    }
                    FineButton(title: "outer") {}
                }
            }
        }

        let stack = FineRenderer.render(tree(true, true))
        let stackView = try #require(stack as? UIStackView)
        let button = try #require(stackView.arrangedSubviews[1] as? UIButton)

        _ = FineRenderer.render(tree(true, false), reusing: stack)

        #expect(stackView.arrangedSubviews.count == 1)
        #expect(stackView.arrangedSubviews[0] === button)
    }

    /// Two independently built child arrays each number their slots from their
    /// own start, so concatenating them in one builder statement can produce
    /// the same generated slot twice. The builder cannot see that they were
    /// joined and the caller has nothing to fix, so those children render
    /// without identity-based reuse rather than tripping an assertion.
    @Test func concatenatedBuilderResultsSurviveAGeneratedSlotCollision() throws {
        let stack = FineRenderer.render(FineStack.vertical {
            self.maybe(true, "A") + self.maybe(true, "B")
        })
        let stackView = try #require(stack as? UIStackView)

        #expect(stackView.arrangedSubviews.count == 2)
        #expect((stackView.arrangedSubviews[0] as? UILabel)?.text == "A")
        #expect((stackView.arrangedSubviews[1] as? UILabel)?.text == "B")
    }

    @FineBuilder
    private func maybe(_ flag: Bool, _ text: String) -> [any Renderable] {
        if flag {
            FineLabel(text: text)
        }
    }

    private func firstLabel(in view: UIView) -> UILabel? {
        if let label = view as? UILabel, !(view.superview is UIButton) {
            return label
        }

        for subview in view.subviews {
            if let label = firstLabel(in: subview) {
                return label
            }
        }

        return nil
    }
}
