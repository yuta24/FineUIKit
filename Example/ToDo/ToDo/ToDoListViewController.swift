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
    var items: [ToDo] = []
}

final class ToDoListViewController: FineViewController<ToDoListViewModel> {
    init() {
        super.init(state: .init())
    }

    override func body(_ viewModel: ToDoListViewModel) -> any Renderable {
        FineStack.vertical(spacing: 8) {
            [
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
                FineList(viewModel.items) { item in
                    FineStack.horizontal(spacing: 8) {
                        [
                            FineToggle(isOn: .init(item, \.completed)),
                            FineLabel(text: item.title),
                        ]
                    }
                }
                .onDelete { item in
                    viewModel.items.removeAll { $0.id == item.id }
                },
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
