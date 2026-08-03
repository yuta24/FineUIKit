//
//  ToDoList.swift
//  ToDo
//
//  Created by nova on 2026/07/04.
//

import Observation
import UIKit
import SwiftUI
import FineUIKit

// Environment sample: an ambient accent color injected near the top of the
// tree and read further down by `FineEnvironmentReader`, without threading it
// through every `body` argument.
private struct AccentColorKey: FineEnvironmentKey {
    static let defaultValue: UIColor = .systemBlue
}

extension FineEnvironmentValues {
    var accentColor: UIColor {
        get { self[AccentColorKey.self] }
        set { self[AccentColorKey.self] = newValue }
    }
}

// The screen owns its state and describes its own view tree. Handlers capture
// `self` freely: the hosting controller owns this object and the views alike,
// so nothing here closes a cycle. The one rule is that a screen must not hold
// its controller — which is why it has no reason to know about one.
@Observable
final class ToDoList: FineNavigating {
    var draft: String = ""
    var showsGrid: Bool = false
    var usesAlternateAccent: Bool = false
    var items: [ToDo] = []

    func addTask() {
        let title = draft.isEmpty ? "Task \(items.count + 1)" : draft
        items.append(.init(title: title))
        draft = ""
    }

    func navigation() -> FineNavigation? {
        FineNavigation(title: "ToDo (\(items.count))")
            .trailing(
                FineBarButton(systemItem: .add) { self.addTask() }
                    .enabled(!draft.isEmpty)
            )
    }

    func body() -> any Renderable {
        let activeItems = items.filter { !$0.completed }
        let completedItems = items.filter { $0.completed }
        var listSections = [
            FineListSection(id: "active", header: "Active", items: activeItems),
        ]
        if !completedItems.isEmpty {
            listSections.append(.init(id: "completed", header: "Completed", items: completedItems))
        }

        return FineStack.vertical(spacing: 8) {
            // Environment sample. The count badge is nested inside a
            // `FineEnvironmentReader` and colors itself with the injected
            // `accentColor`. Flipping the "Pink accent" switch changes the
            // value injected by `.environment(_:_:)`, and the badge follows.
            FineStack.horizontal(spacing: 8, alignment: .center) {
                FineEnvironmentReader { environment in
                    FineLabel(text: "\(self.items.count)")
                        .textColor(.white)
                        .textAlignment(.center)
                        .padding(.init(top: 2, leading: 10, bottom: 2, trailing: 10))
                        .backgroundColor(environment.accentColor)
                        .cornerRadius(11)
                }
                FineLabel(text: "items")
                    .textColor(.secondaryLabel)
                FineSpacer()
                FineLabel(text: "Pink accent")
                    .textColor(.secondaryLabel)
                FineToggle(isOn: .init(self, \.usesAlternateAccent))
                    .hugging(.defaultHigh, axis: .horizontal)
            }
            .padding(.init(top: 8, leading: 16, bottom: 0, trailing: 16))
            .environment(\.accentColor, self.usesAlternateAccent ? .systemPink : .systemBlue)

            // Local-state sample. The expand/collapse flag lives in the view
            // tree (FineNode.localState via FineState), not in the view model.
            // It survives the full re-renders that adding or completing tasks
            // trigger, and animates with withFineAnimation.
            FineState(false) { isExpanded in
                FineStack.vertical(spacing: 4) {
                    FineStack.horizontal(spacing: 0) {
                        FineButton(title: isExpanded.value ? "▼ Tips" : "▶ Tips") {
                            withFineAnimation {
                                isExpanded.value.toggle()
                            }
                        }
                        .hugging(.defaultHigh, axis: .horizontal)
                        FineSpacer()
                    }
                    if isExpanded.value {
                        FineLabel(text: "Swipe a row to delete. Toggle Grid view to switch between list and grid.")
                            .numberOfLines(0)
                            .textColor(.secondaryLabel)
                    }
                }
                .padding(.init(top: 0, leading: 16, bottom: 0, trailing: 16))
            }

            FineStack.horizontal(spacing: 8) {
                FineTextField(text: .init(self, \.draft), placeholder: "New task")
                    .onSubmit { self.addTask() }
                    .accessibilityIdentifier("draft-field")
                FineButton(title: "Add") {
                    self.addTask()
                }
                .configuration(.filled())
                .hugging(.defaultHigh, axis: .horizontal)
                .accessibilityLabel("Add task")
                .accessibilityHint("Adds a new task to the list")
            }
            .padding(.init(top: 8, leading: 16, bottom: 0, trailing: 16))
            FineStack.horizontal(spacing: 8) {
                FineLabel(text: "Grid view")
                FineToggle(isOn: .init(self, \.showsGrid))
            }
            .padding(.init(top: 0, leading: 16, bottom: 0, trailing: 16))
            if self.showsGrid {
                FineGrid(self.items, columns: .count(2), spacing: 8) { item in
                    FineLabel(text: item.title)
                        .padding(8)
                        .backgroundColor(.secondarySystemBackground)
                        .cornerRadius(8)
                }
                .onSelect { item in
                    self.items.removeAll { $0.id == item.id }
                }
            } else {
                FineList(sections: listSections) { item in
                    FineStack.horizontal(spacing: 8) {
                        FineToggle(isOn: .init(item, \.completed))
                        FineLabel(text: item.title)
                    }
                }
                .onDelete { item in
                    self.items.removeAll { $0.id == item.id }
                }
                .keyboardDismissMode(.onDrag)
            }
        }
    }
}

struct TodoListWrapper: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UINavigationController {
        UINavigationController(rootViewController: FineContentController(ToDoList()))
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {
    }
}
