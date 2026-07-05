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
                FineButton(title: "Add") {
                    viewModel.items.append(.init(title: "Task \(viewModel.items.count + 1)"))
                },
                FineList(viewModel.items) { item in
                    FineLabel(text: item.title)
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
