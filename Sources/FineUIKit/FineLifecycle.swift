//
//  FineLifecycle.swift
//  FineUIKit
//
//  Created by nova on 2026/07/07.
//

import UIKit

@MainActor
final class FineLifecycleView: UIView {
    var hosted: UIView?

    var onAppear: (@MainActor () -> Void)?
    var onDisappear: (@MainActor () -> Void)?

    private var taskAction: (@MainActor () async -> Void)?
    private var taskID: AnyHashable?
    // nonisolated(unsafe): only written on the main actor; deinit reads it
    // when no other references remain.
    private nonisolated(unsafe) var runningTask: Task<Void, Never>?
    private(set) var isAppeared = false

    deinit {
        runningTask?.cancel()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()

        if window != nil, !isAppeared {
            isAppeared = true
            onAppear?()
            startTask()
        } else if window == nil, isAppeared {
            isAppeared = false
            runningTask?.cancel()
            runningTask = nil
            onDisappear?()
        }
    }

    /// Stores the task configuration. While the view is on screen, a changed
    /// identity cancels the running task and starts a new one; the same
    /// identity keeps the running (or already finished) task untouched.
    func setTask(_ action: (@MainActor () async -> Void)?, id: AnyHashable?) {
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

    private func startTask() {
        guard let taskAction else { return }

        runningTask = Task { @MainActor in
            await taskAction()
        }
    }
}

@MainActor
struct FineLifecycleModified: Renderable {
    let content: any Renderable
    var onAppear: (@MainActor () -> Void)?
    var onDisappear: (@MainActor () -> Void)?
    var task: (@MainActor () async -> Void)?
    var taskID: AnyHashable?

    init(content: any Renderable) {
        self.content = content
    }

    func _makeView() -> UIView {
        FineLifecycleView(frame: .zero)
    }

    func _canUpdate(_ view: UIView) -> Bool {
        view is FineLifecycleView
    }

    func _update(_ view: UIView) {
        guard let lifecycleView = view as? FineLifecycleView else { return }

        lifecycleView.onAppear = onAppear
        lifecycleView.onDisappear = onDisappear
        lifecycleView.setTask(task, id: taskID)

        let hosted = FineRenderer.render(content, reusing: lifecycleView.hosted)

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
    }

    var _modifierSignature: String {
        "lifecycle"
    }

    var _key: AnyHashable? {
        content._key
    }
}

public extension Renderable {
    /// Runs `action` every time the rendered view is attached to a window.
    func onAppear(_ action: @escaping @MainActor () -> Void) -> any Renderable {
        var modified = _lifecycleModified
        modified.onAppear = action
        return modified
    }

    /// Runs `action` every time the rendered view is removed from its window.
    func onDisappear(_ action: @escaping @MainActor () -> Void) -> any Renderable {
        var modified = _lifecycleModified
        modified.onDisappear = action
        return modified
    }

    /// Starts `action` when the rendered view is attached to a window and
    /// cancels it when the view is removed. Re-renders do not restart a
    /// running task.
    func task(_ action: @escaping @MainActor () async -> Void) -> any Renderable {
        var modified = _lifecycleModified
        modified.task = action
        modified.taskID = nil
        return modified
    }

    /// Like `task(_:)`, but also cancels and restarts the task whenever `id`
    /// changes while the view is on screen.
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
