//
//  ToDo.swift
//  ToDo
//
//  Created by nova on 2026/07/04.
//

final class ToDo: Identifiable {
    var title: String
    var completed: Bool = false

    init(title: String) {
        self.title = title
    }
}
