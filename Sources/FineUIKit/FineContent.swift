//
//  FineContent.swift
//  FineUIKit
//
//  Created by nova on 2026/08/03.
//

/// An object that describes a view tree and owns the state that tree reads.
///
/// Conform an `@Observable final class` to it and return a description from
/// `body()`. Whatever `body()` reads is tracked, so mutating the object's own
/// state re-renders — at the granularity of the read, not of the object: a
/// value read inside a builder updates that node alone and never re-evaluates
/// `body()`.
///
/// ```swift
/// @MainActor
/// @Observable
/// final class ToDoList: FineContent {
///     var items: [ToDo] = []
///     var isEditing = false
///
///     func addTask(_ title: String) { items.append(.init(title: title)) }
///
///     func body() -> any Renderable {
///         FineStack.vertical {
///             FineLabel(text: "\(self.items.count) items")
///             FineButton(title: "Add") { self.addTask("New") }
///         }
///     }
/// }
/// ```
///
/// Hand it to `FineScreenController` to put it on screen. Content nested inside
/// other content needs no controller and no conformance at all — see *Scope*
/// below.
///
/// ## Why a class, and why capturing `self` here is safe
///
/// The runtime keeps every closure a description carries for as long as the
/// view lives, and the views belong to whoever mounted them. A handler that
/// captured *the mounting controller* would therefore close a cycle nothing
/// could break. A handler that captures this object does not: the controller
/// owns the content and the tree, and the content owns neither, so the graph
/// stays acyclic.
///
/// That holds only while the content does not reach back. **Content must not
/// hold its controller strongly.** Anything it needs to tell the outside world
/// — including that the user asked to go somewhere — belongs on a
/// `weak var delegate`, so the reference that would close the cycle is weak by
/// declaration rather than by everyone remembering a capture list.
///
/// ```swift
/// protocol ToDoListDelegate: AnyObject {
///     func toDoList(_ list: ToDoList, didSelect item: ToDo)
/// }
///
/// @Observable
/// final class ToDoList: FineContent {
///     @ObservationIgnored weak var delegate: (any ToDoListDelegate)?
/// }
/// ```
///
/// ## Scope
///
/// State lives for as long as the content is mounted. Nesting works by ordinary
/// composition — hold a child object and splice `child.body()` into your own —
/// and **a child conforms to nothing**: the runtime never sees it, so `body()`
/// on a plain `@Observable` class is all it takes. What the runtime does manage
/// is view and node identity, which is why a `FineState` inside a subtree that
/// goes away is discarded while the child object's own state, held by its
/// parent, is not.
///
/// Navigation is not content's job. Content says what happened; something
/// outside it decides where that leads.
@MainActor
public protocol FineContent: AnyObject {
    /// The description of this content's view tree.
    func body() -> any Renderable
}

/// Content that also describes a navigation bar, for when it is mounted as a
/// screen.
///
/// Separate from `FineContent` because `navigationItem` is a screen-level
/// concern: content rendered into a subview has no bar to describe, and would
/// otherwise be able to implement a method that silently does nothing.
///
/// This is chrome, not flow. It says what the bar shows, and a bar button's
/// action reports an intent the same way any other handler does.
///
/// It is tracked in its own observation scope, separate from `body()`, so a
/// value read only here — a title, a button's enabled state — updates
/// `navigationItem` without re-evaluating or re-diffing the tree.
@MainActor
public protocol FineNavigating: FineContent {
    /// The navigation bar description, or `nil` to leave `navigationItem`
    /// untouched so it can be managed manually.
    func navigation() -> FineNavigation?
}
