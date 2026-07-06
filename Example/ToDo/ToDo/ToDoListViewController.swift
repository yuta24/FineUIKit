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
        FineStack.vertical(spacing: 8) {
            let collection: any Renderable
            if viewModel.showsGrid {
                collection = FineGrid(viewModel.items, columns: .count(2), spacing: 8) { item in
                    FineLabel(text: item.title)
                        .padding(8)
                        .backgroundColor(.secondarySystemBackground)
                        .cornerRadius(8)
                }
                .onSelect { item in
                    viewModel.items.removeAll { $0.id == item.id }
                }
            } else {
                collection = FineList(viewModel.items) { item in
                    FineStack.horizontal(spacing: 8) {
                        [
                            FineToggle(isOn: .init(item, \.completed)),
                            FineLabel(text: item.title),
                        ]
                    }
                }
                .onDelete { item in
                    viewModel.items.removeAll { $0.id == item.id }
                }
            }

            return [
                FineLabel(text: "\(viewModel.items.count) items")
                    .padding(.init(top: 8, leading: 16, bottom: 0, trailing: 16)),
                FineStack.horizontal(spacing: 8) {
                    [
                        FineTextField(text: .init(viewModel, \.draft), placeholder: "New task"),
                        FineButton(title: "Add") {
                            let title = viewModel.draft.isEmpty
                                ? "Task \(viewModel.items.count + 1)"
                                : viewModel.draft
                            viewModel.items.append(.init(title: title))
                            viewModel.draft = ""
                        },
                    ]
                }
                .padding(.init(top: 8, leading: 16, bottom: 0, trailing: 16)),
                FineStack.horizontal(spacing: 8) {
                    [
                        FineLabel(text: "Grid view"),
                        FineToggle(isOn: .init(viewModel, \.showsGrid)),
                    ]
                }
                .padding(.init(top: 0, leading: 16, bottom: 0, trailing: 16)),
                collection,
            ]
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
