//
//  FineScreen.swift
//  FineUIKit
//
//  Created by nova on 2026/08/03.
//

/// An object that describes a view tree and owns the state that tree reads.
///
/// Conform an `@Observable final class` to it and return a description from
/// `body()`. Whatever `body()` reads is tracked, so mutating the screen's own
/// state re-renders — at the granularity of the read, not of the screen: a value
/// read inside a builder updates that node alone and never re-evaluates
/// `body()`.
///
/// ```swift
/// @MainActor
/// @Observable
/// final class ToDoScreen: FineScreen {
///     var items: [ToDo] = []
///     var isEditing = false
///
///     func addTask(_ title: String) { items.append(.init(title: title)) }
///
///     func body() -> any Renderable {
///         FineStack.vertical {
///             FineLabel(text: "\(items.count) items")
///             FineButton(title: "Add") { self.addTask("New") }
///         }
///     }
/// }
/// ```
///
/// ## Why a class, and why capturing `self` here is safe
///
/// The runtime keeps every closure a description carries for as long as the
/// view lives, and the views belong to the hosting controller. A handler that
/// captured *the controller* would therefore close a cycle nothing could break.
/// A handler that captures the screen does not: the controller owns the screen
/// and the tree, and the screen owns neither, so the graph stays acyclic.
///
/// That holds only while the screen does not reach back. **A screen must not
/// hold its controller strongly.** Anything the screen needs to tell the
/// outside world — including that the user asked to go somewhere — belongs on a
/// `weak var delegate`, so the reference that would close the cycle is weak by
/// declaration rather than by everyone remembering a capture list.
///
/// ```swift
/// protocol ToDoScreenDelegate: AnyObject {
///     func toDoScreen(_ screen: ToDoScreen, didSelect item: ToDo)
/// }
///
/// @Observable
/// final class ToDoScreen: FineScreen {
///     @ObservationIgnored weak var delegate: (any ToDoScreenDelegate)?
/// }
/// ```
///
/// ## Scope
///
/// A screen is a mount, not a component: its state lives for as long as it is
/// mounted, which is what "screen" names here — the lifetime, not the pixels.
/// Nesting works by ordinary composition (hold a child screen and splice
/// `child.body()` into your own), but the runtime does not manage a child's
/// identity: the parent owns it, and the parent decides when it is replaced.
///
/// Navigation is not a screen's job. A screen says what happened; something
/// outside it decides where that leads.
@MainActor
public protocol FineScreen: AnyObject {
    /// The description of this screen's view tree.
    func body() -> any Renderable

    /// The navigation bar description, or `nil` to leave `navigationItem`
    /// untouched so it can be managed manually.
    ///
    /// This is chrome, not flow: it says what the bar shows, and a bar button's
    /// action reports an intent the same way any other handler does.
    ///
    /// It is tracked in its own observation scope, separate from `body()`, so a
    /// value read only here — a title, a button's enabled state — updates
    /// `navigationItem` without re-evaluating or re-diffing the tree.
    func navigation() -> FineNavigation?
}

public extension FineScreen {
    func navigation() -> FineNavigation? { nil }
}
