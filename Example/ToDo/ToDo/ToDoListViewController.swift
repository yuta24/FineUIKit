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
                FineLabel(text: "\(viewModel.items.count) items"),
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
                },
                FineList(viewModel.items) { item in
                    FineStack.horizontal(spacing: 8) {
                        [
                            FineToggle(isOn: .init(item, \.completed)),
                            FineLabel(text: item.title),
                        ]
                    }
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
