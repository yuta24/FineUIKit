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

final class ToDoListViewController: UIViewController {
    @Observable
    final class ViewModel {
        var items: [ToDo] = []
    }

    let viewModel: ViewModel = .init()

    private var fineUI: FineUI<ViewModel>?

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground

        let fineUI = FineUI(viewModel) { viewModel in
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
        fineUI.build(to: view)

        self.fineUI = fineUI
    }
}

struct TodoListWrapper: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> ToDoListViewController {
        .init()
    }

    func updateUIViewController(_ uiViewController: UIViewControllerType, context: Context) {
    }
}
