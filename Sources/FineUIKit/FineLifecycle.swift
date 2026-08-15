//
//  FineLifecycle.swift
//  FineUIKit
//
//  Created by nova on 2026/07/07.
//

import UIKit

/// A view holding state that belongs to what it is showing rather than to
/// itself, and has to let go of it when it is handed something else.
///
/// `FineNode.localState` covers the state the runtime owns. This covers the
/// state a view owns on the description's behalf, which only the view can wind
/// down — a running task, a lifecycle that has begun and must be allowed to end.
@MainActor
protocol FineIdentityScopedView: UIView {
    func discardIdentityState()
}

/// Hosts the lifecycle modifiers, and keeps two facts apart that look like one.
///
/// *On screen* is about the view, and UIKit reports it through the window.
/// *Appeared* is about the description the view is currently showing, and the
/// two come apart in both directions:
///
/// - A reused cell handed a different row never leaves the window, so nothing
///   would tell the previous row it was gone or the new one that it arrived —
///   the previous row's task would outlive it and the new one's would never
///   start.
/// - A view built during a scheduled render enters the hierarchy before its
///   description is applied, so the window transition happens while the
///   handlers are still unset, and the appearance would be lost.
///
/// So the handlers fire on `appeared`, which needs a window *and* a
/// description, and is given up when either one goes.
@MainActor
final class FineLifecycleView: UIView, FineIdentityScopedView {
    var hosted: UIView?

    var onAppear: (@MainActor () -> Void)?
    var onDisappear: (@MainActor () -> Void)?

    private var taskAction: (@MainActor () async -> Void)?
    private var taskID: AnyHashable?
    // nonisolated(unsafe): only written on the main actor; deinit reads it
    // when no other references remain.
    private nonisolated(unsafe) var runningTask: Task<Void, Never>?
    /// Whether the view is in a window.
    private var isInWindow = false
    /// Whether a description has been applied. A view is put into the hierarchy
    /// before the scheduled update reaches it, and until it does there is no
    /// handler to call and nothing to call it about.
    private var hasDescription = false
    /// Whether the description currently installed has been told it appeared.
    private(set) var isAppeared = false

    deinit {
        runningTask?.cancel()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()

        isInWindow = window != nil

        if isInWindow {
            notifyAppearIfNeeded()
        } else {
            notifyDisappearIfNeeded()
        }
    }

    /// Applies the description's lifecycle handlers, and reports an appearance
    /// the view was not yet able to report.
    func setLifecycle(
        onAppear: (@MainActor () -> Void)?,
        onDisappear: (@MainActor () -> Void)?,
        task: (@MainActor () async -> Void)?,
        taskID: AnyHashable?
    ) {
        self.onAppear = onAppear
        self.onDisappear = onDisappear
        hasDescription = true

        setTask(task, id: taskID)
        notifyAppearIfNeeded()
    }

    /// Gives up the state that belongs to what this view was showing, because
    /// it is about to show something else.
    ///
    /// The view stays where it is — reusing it is the point — so the previous
    /// content is told it disappeared here rather than by a window transition
    /// that is never going to come.
    func discardIdentityState() {
        notifyDisappearIfNeeded()
        hasDescription = false
        taskAction = nil
        taskID = nil
    }

    /// Stores the task configuration. While the content is appeared, a changed
    /// identity cancels the running task and starts a new one; the same
    /// identity keeps the running (or already finished) task untouched.
    private func setTask(_ action: (@MainActor () async -> Void)?, id: AnyHashable?) {
        let idChanged = taskID != id
        taskAction = action
        taskID = id

        guard isAppeared else { return }

        if action == nil {
            runningTask?.cancel()
            runningTask = nil
        } else if runningTask == nil || idChanged {
            runningTask?.cancel()
            startTask()
        }
    }

    private func notifyAppearIfNeeded() {
        guard isInWindow, hasDescription, !isAppeared else { return }

        isAppeared = true
        onAppear?()
        startTask()
    }

    private func notifyDisappearIfNeeded() {
        guard isAppeared else { return }

        isAppeared = false
        runningTask?.cancel()
        runningTask = nil
        onDisappear?()
    }

    private func startTask() {
        guard let taskAction else { return }

        runningTask = Task { @MainActor in
            await taskAction()
        }
    }
}

@MainActor
struct FineLifecycleModified: FinePrimitiveRenderable {
    let content: FineResolvedRenderable
    var onAppear: (@MainActor () -> Void)?
    var onDisappear: (@MainActor () -> Void)?
    var task: (@MainActor () async -> Void)?
    var taskID: AnyHashable?

    init(content: any Renderable) {
        self.content = FineResolvedRenderable(content)
    }

    func _makeView() -> UIView {
        FineLifecycleView(frame: .zero)
    }

    func _canUpdate(_ view: UIView) -> Bool {
        view is FineLifecycleView
    }

    func _update(_ view: UIView, context: FineRenderContext) {
        guard let lifecycleView = view as? FineLifecycleView else { return }

        let hosted = context.render(resolved: content.primitive, reusing: lifecycleView.hosted)

        if hosted !== lifecycleView.hosted {
            lifecycleView.hosted?.removeFromSuperview()
            lifecycleView.hosted = hosted

            hosted.translatesAutoresizingMaskIntoConstraints = false
            lifecycleView.addSubview(hosted)

            NSLayoutConstraint.activate([
                hosted.topAnchor.constraint(equalTo: lifecycleView.topAnchor),
                hosted.leadingAnchor.constraint(equalTo: lifecycleView.leadingAnchor),
                hosted.trailingAnchor.constraint(equalTo: lifecycleView.trailingAnchor),
                hosted.bottomAnchor.constraint(equalTo: lifecycleView.bottomAnchor),
            ])
        }

        // After the content, not before it: this call is what reports an
        // appearance, and being told that something appeared is only useful
        // once it is there to look at.
        lifecycleView.setLifecycle(
            onAppear: onAppear,
            onDisappear: onDisappear,
            task: task,
            taskID: taskID
        )
    }

    var _modifierSignature: String {
        "lifecycle"
    }

    var _key: AnyHashable? {
        content.primitive._key
    }
}

public extension Renderable {
    /// Runs `action` every time this content comes on screen.
    ///
    /// Usually that is the rendered view being attached to a window. Inside a
    /// list or grid row it is also the moment a cell already on screen is
    /// handed this row: the cell keeps its views, so no window changes, but the
    /// row arrived all the same.
    func onAppear(_ action: @escaping @MainActor () -> Void) -> any Renderable {
        var modified = _lifecycleModified
        modified.onAppear = action
        return modified
    }

    /// Runs `action` every time this content goes off screen — its view leaving
    /// the window, or the cell showing it being given a different row.
    func onDisappear(_ action: @escaping @MainActor () -> Void) -> any Renderable {
        var modified = _lifecycleModified
        modified.onDisappear = action
        return modified
    }

    /// Starts `action` when this content comes on screen and cancels it when it
    /// goes off screen. Re-renders do not restart a running task.
    ///
    /// A row's task is bound to the row rather than to the cell: handing a
    /// visible cell a different row cancels the previous row's task and starts
    /// this one's, so a request made for a row that has scrolled away does not
    /// go on running against the cell that replaced it.
    func task(_ action: @escaping @MainActor () async -> Void) -> any Renderable {
        var modified = _lifecycleModified
        modified.task = action
        modified.taskID = nil
        return modified
    }

    /// Like `task(_:)`, but also cancels and restarts the task whenever `id`
    /// changes while the content is on screen.
    func task(id: some Hashable, _ action: @escaping @MainActor () async -> Void) -> any Renderable {
        var modified = _lifecycleModified
        modified.task = action
        modified.taskID = AnyHashable(id)
        return modified
    }

    private var _lifecycleModified: FineLifecycleModified {
        self as? FineLifecycleModified ?? FineLifecycleModified(content: self)
    }
}
