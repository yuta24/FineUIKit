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

@Observable
final class ToDoListViewModel {
    var draft: String = ""
    var showsGrid: Bool = false
    var items: [ToDo] = []
}

final class ToDoListViewController: FineViewController<ToDoListViewModel> {
    init() {
        super.init(state: .init())
    }

    override func body(_ viewModel: ToDoListViewModel) -> any Renderable {
        func addTask() {
            let title = viewModel.draft.isEmpty
                ? "Task \(viewModel.items.count + 1)"
                : viewModel.draft
            viewModel.items.append(.init(title: title))
            viewModel.draft = ""
        }

        let activeItems = viewModel.items.filter { !$0.completed }
        let completedItems = viewModel.items.filter { $0.completed }
        var listSections = [
            FineListSection(id: "active", header: "Active", items: activeItems),
        ]
        if !completedItems.isEmpty {
            listSections.append(.init(id: "completed", header: "Completed", items: completedItems))
        }

        return FineStack.vertical(spacing: 8) {
            FineLabel(text: "\(viewModel.items.count) items")
                .padding(.init(top: 8, leading: 16, bottom: 0, trailing: 16))
            FineStack.horizontal(spacing: 8) {
                FineTextField(text: .init(viewModel, \.draft), placeholder: "New task")
                    .onSubmit { addTask() }
                    .accessibilityIdentifier("draft-field")
                FineButton(title: "Add") {
                    addTask()
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
            }
        }
    }
}

struct TodoListWrapper: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> ToDoListViewController {
        .init()
    }

    func updateUIViewController(_ uiViewController: UIViewControllerType, context: Context) {
    }
}
