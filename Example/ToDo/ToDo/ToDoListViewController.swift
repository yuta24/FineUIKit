//
//  ToDoListViewController.swift
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

@Observable
final class ToDoListViewModel {
    var draft: String = ""
    var showsGrid: Bool = false
    var usesAlternateAccent: Bool = false
    var items: [ToDo] = []
}

final class ToDoListViewController: FineViewController<ToDoListViewModel> {
    init() {
        super.init(state: .init())
    }

    private func addTask(_ viewModel: ToDoListViewModel) {
        let title = viewModel.draft.isEmpty
            ? "Task \(viewModel.items.count + 1)"
            : viewModel.draft
        viewModel.items.append(.init(title: title))
        viewModel.draft = ""
    }

    override func navigation(_ viewModel: ToDoListViewModel) -> FineNavigation? {
        FineNavigation(title: "ToDo (\(viewModel.items.count))")
            .trailing(
                FineBarButton(systemItem: .add) { [unowned self] in
                    addTask(viewModel)
                }
                .enabled(!viewModel.draft.isEmpty)
            )
    }

    override func body(_ viewModel: ToDoListViewModel) -> any Renderable {
        let activeItems = viewModel.items.filter { !$0.completed }
        let completedItems = viewModel.items.filter { $0.completed }
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
                    FineLabel(text: "\(viewModel.items.count)")
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
                FineToggle(isOn: .init(viewModel, \.usesAlternateAccent))
                    .hugging(.defaultHigh, axis: .horizontal)
            }
            .padding(.init(top: 8, leading: 16, bottom: 0, trailing: 16))
            .environment(\.accentColor, viewModel.usesAlternateAccent ? .systemPink : .systemBlue)

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
                FineTextField(text: .init(viewModel, \.draft), placeholder: "New task")
                    .onSubmit { [unowned self] in addTask(viewModel) }
                    .accessibilityIdentifier("draft-field")
                FineButton(title: "Add") { [unowned self] in
                    addTask(viewModel)
                }
                .configuration(.filled())
                .hugging(.defaultHigh, axis: .horizontal)
                .accessibilityLabel("Add task")
                .accessibilityHint("Adds a new task to the list")
            }
            .padding(.init(top: 8, leading: 16, bottom: 0, trailing: 16))
            FineStack.horizontal(spacing: 8) {
                FineLabel(text: "Grid view")
                FineToggle(isOn: .init(viewModel, \.showsGrid))
            }
            .padding(.init(top: 0, leading: 16, bottom: 0, trailing: 16))
            if viewModel.showsGrid {
                FineGrid(viewModel.items, columns: .count(2), spacing: 8) { item in
                    FineLabel(text: item.title)
                        .padding(8)
                        .backgroundColor(.secondarySystemBackground)
                        .cornerRadius(8)
                }
                .onSelect { item in
                    viewModel.items.removeAll { $0.id == item.id }
                }
            } else {
                FineList(sections: listSections) { item in
                    FineStack.horizontal(spacing: 8) {
                        FineToggle(isOn: .init(item, \.completed))
                        FineLabel(text: item.title)
                    }
                }
                .onDelete { item in
                    viewModel.items.removeAll { $0.id == item.id }
                }
                .keyboardDismissMode(.onDrag)
            }
        }
    }
}

struct TodoListWrapper: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UINavigationController {
        UINavigationController(rootViewController: ToDoListViewController())
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {
    }
}
