//
//  RenderingPerformanceTests.swift
//  FineUIKit
//
//  Created by nova on 2026/07/07.
//

import XCTest
import SwiftUI
import Observation
@testable import FineUIKit

/// Simulator measurements are intended for trend observation only, not absolute
/// conclusions. The SwiftUI measurements are approximations that force pending
/// work by hosting views in UIKit and calling `layoutIfNeeded()`.
@MainActor
final class RenderingPerformanceTests: XCTestCase {
    private let windowSize = CGSize(width: 390, height: 844)

    func testInitialRenderFineUIKit() {
        let window = makeWindow()

        measureRendering {
            window.subviews.forEach { $0.removeFromSuperview() }

            let view = FineRenderer.render(Self.fineStack(changedIndex: nil, token: 0))
            let constraints = self.install(view, in: window)
            window.layoutIfNeeded()

            NSLayoutConstraint.deactivate(constraints)
            view.removeFromSuperview()
        }
    }

    func testInitialRenderSwiftUI() {
        let window = makeWindow()

        measureRendering {
            window.subviews.forEach { $0.removeFromSuperview() }

            // Controller creation is part of the measured initial construction
            // cost, matching FineUIKit's fresh render path above.
            let controller = UIHostingController(rootView: PerformanceStackView(texts: Self.stackTexts(token: 0)))
            let constraints = self.install(controller.view, in: window)
            window.layoutIfNeeded()

            NSLayoutConstraint.deactivate(constraints)
            controller.view.removeFromSuperview()
        }
    }

    func testIncrementalUpdateFineUIKit() {
        let window = makeWindow()
        let view = FineRenderer.render(Self.fineStack(changedIndex: nil, token: 0))
        _ = install(view, in: window)
        window.layoutIfNeeded()

        var iteration = 0
        measureRendering {
            let index = iteration % 100
            _ = FineRenderer.render(Self.fineStack(changedIndex: index, token: iteration), reusing: view)
            window.layoutIfNeeded()
            iteration += 1
        }
    }

    func testIncrementalUpdateSwiftUI() {
        let window = makeWindow()
        let model = PerformanceTextModel(texts: Self.stackTexts(token: 0))
        let controller = UIHostingController(rootView: PerformanceObservedStackView(model: model))
        _ = install(controller.view, in: window)
        window.layoutIfNeeded()

        var iteration = 0
        measureRendering {
            let index = iteration % model.texts.count
            model.texts[index] = "Updated \(index)-\(iteration)"
            window.layoutIfNeeded()
            iteration += 1
        }
    }

    func testListInsertionFineUIKit() {
        let window = makeWindow()
        let baseItems = Self.listItems(startID: 0, count: 1_000)
        let view = FineRenderer.render(Self.fineList(items: baseItems))
        _ = install(view, in: window)
        window.layoutIfNeeded()

        var iteration = 0
        measureRendering {
            let inserted = Self.listItems(startID: 10_000 + iteration * 10, count: 10)

            // UITableViewDiffableDataSource application can involve asynchronous
            // animation internals. Both this and SwiftUI's List build only the
            // currently visible cells, so this is a visible-list approximation.
            _ = FineRenderer.render(Self.fineList(items: inserted + baseItems), reusing: view)
            window.layoutIfNeeded()

            _ = FineRenderer.render(Self.fineList(items: baseItems), reusing: view)
            window.layoutIfNeeded()
            iteration += 1
        }
    }

    func testListInsertionSwiftUI() {
        let window = makeWindow()
        let baseItems = Self.listItems(startID: 0, count: 1_000)
        let model = PerformanceItemModel(items: baseItems)
        let controller = UIHostingController(rootView: PerformanceListView(model: model))
        _ = install(controller.view, in: window)
        window.layoutIfNeeded()

        var iteration = 0
        measureRendering {
            let inserted = Self.listItems(startID: 10_000 + iteration * 10, count: 10)

            // SwiftUI List also virtualizes off-screen rows; layoutIfNeeded()
            // gives a practical synchronous boundary rather than an exact one.
            model.items.insert(contentsOf: inserted, at: 0)
            window.layoutIfNeeded()

            model.items = baseItems
            window.layoutIfNeeded()
            iteration += 1
        }
    }

    private func measureRendering(_ block: @escaping @MainActor () -> Void) {
        let options = XCTMeasureOptions()
        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()], options: options) {
            MainActor.assumeIsolated {
                block()
            }
        }
    }

    private func makeWindow() -> UIWindow {
        let window = UIWindow(frame: .init(origin: .zero, size: windowSize))
        window.isHidden = false
        return window
    }

    @discardableResult
    private func install(_ view: UIView, in window: UIWindow) -> [NSLayoutConstraint] {
        view.translatesAutoresizingMaskIntoConstraints = false
        window.addSubview(view)

        let constraints = [
            view.topAnchor.constraint(equalTo: window.topAnchor),
            view.leadingAnchor.constraint(equalTo: window.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: window.trailingAnchor),
            view.bottomAnchor.constraint(equalTo: window.bottomAnchor),
        ]
        NSLayoutConstraint.activate(constraints)
        return constraints
    }

    private static func fineStack(changedIndex: Int?, token: Int) -> some Renderable {
        FineStack.vertical {
            for index in 0..<100 {
                FineLabel(text: changedIndex == index ? "Updated \(index)-\(token)" : "Row \(index)")
            }
        }
    }

    private static func stackTexts(token: Int) -> [String] {
        (0..<100).map { "Row \($0)-\(token)" }
    }

    private static func fineList(items: [PerformanceItem]) -> some Renderable {
        FineList(items) { item in
            FineLabel(text: item.title)
        }
    }

    private static func listItems(startID: Int, count: Int) -> [PerformanceItem] {
        (0..<count).map { offset in
            let id = startID + offset
            return .init(id: id, title: "Row \(id)")
        }
    }
}

private struct PerformanceItem: Identifiable, Hashable {
    let id: Int
    let title: String
}

@MainActor
@Observable
private final class PerformanceTextModel {
    var texts: [String]

    init(texts: [String]) {
        self.texts = texts
    }
}

@MainActor
@Observable
private final class PerformanceItemModel {
    var items: [PerformanceItem]

    init(items: [PerformanceItem]) {
        self.items = items
    }
}

private struct PerformanceStackView: View {
    let texts: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(texts.indices, id: \.self) { index in
                Text(texts[index])
            }
        }
    }
}

private struct PerformanceObservedStackView: View {
    let model: PerformanceTextModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(model.texts.indices, id: \.self) { index in
                Text(model.texts[index])
            }
        }
    }
}

private struct PerformanceListView: View {
    let model: PerformanceItemModel

    var body: some View {
        List {
            ForEach(model.items) { item in
                Text(item.title)
            }
        }
    }
}
