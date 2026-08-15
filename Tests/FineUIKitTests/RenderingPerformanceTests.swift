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

    func testListInsertionFineUIKitChangedRowsOnly() {
        let window = makeWindow()
        let baseItems = Self.listItems(startID: 0, count: 1_000)
        let view = FineRenderer.render(Self.fineListChangedRowsOnly(items: baseItems))
        _ = install(view, in: window)
        window.layoutIfNeeded()

        var iteration = 0
        measureRendering {
            let inserted = Self.listItems(startID: 10_000 + iteration * 10, count: 10)

            // Same scenario as testListInsertionFineUIKit, with opt-in row
            // equality filtering enabled for surviving IDs.
            _ = FineRenderer.render(Self.fineListChangedRowsOnly(items: inserted + baseItems), reusing: view)
            window.layoutIfNeeded()

            _ = FineRenderer.render(Self.fineListChangedRowsOnly(items: baseItems), reusing: view)
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

    /// Scrolls a list of rows that each hold several nodes, so the measurement
    /// is dominated by configuring cells rather than by applying a snapshot.
    ///
    /// This is the cost side of giving cells their own `FineNodeScheduler`:
    /// per-node observation means one tracking scope and one queued job per
    /// node in a row instead of one per row, and every dequeued cell pays it.
    func testHeavyCellScrollingFineUIKit() throws {
        let window = makeWindow()
        let models = Self.rowModels(count: 300)
        let view = FineRenderer.render(Self.heavyList(models: models))
        install(view, in: window)
        window.layoutIfNeeded()

        let tableView = try XCTUnwrap(Self.firstTableView(in: view))
        var offset: CGFloat = 0

        measureRendering {
            for _ in 0..<20 {
                let limit = max(0, tableView.contentSize.height - tableView.bounds.height)
                offset = offset + 600 > limit ? 0 : offset + 600
                tableView.setContentOffset(.init(x: 0, y: offset), animated: false)
                tableView.layoutIfNeeded()
            }
        }
    }

    /// The same rows, reconfigured in place rather than scrolled.
    ///
    /// The elements are a reference type, which the list conservatively treats
    /// as always changed, so every render re-runs the row content for every
    /// visible row — synchronously, through the cell provider. That is the
    /// other path a cell's subtree is built on, and it pays the same per-node
    /// cost.
    func testHeavyCellReconfigurationFineUIKit() {
        let window = makeWindow()
        let models = Self.rowModels(count: 300)
        let view = FineRenderer.render(Self.heavyList(models: models))
        install(view, in: window)
        window.layoutIfNeeded()

        measureRendering {
            _ = FineRenderer.render(Self.heavyList(models: models), reusing: view)
            window.layoutIfNeeded()
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

    private static func fineListChangedRowsOnly(items: [PerformanceItem]) -> some Renderable {
        FineList(items) { item in
            FineLabel(text: item.title)
        }
        .reconfiguringOnlyChangedRows()
    }

    private static func listItems(startID: Int, count: Int) -> [PerformanceItem] {
        (0..<count).map { offset in
            let id = startID + offset
            return .init(id: id, title: "Row \(id)")
        }
    }

    private static func rowModels(count: Int) -> [PerformanceRowModel] {
        (0..<count).map { PerformanceRowModel(id: $0) }
    }

    private static func heavyList(models: [PerformanceRowModel]) -> some Renderable {
        FineList(models) { model in
            PerformanceHeavyRow(model: model)
        }
    }

    private static func firstTableView(in view: UIView) -> UITableView? {
        if let tableView = view as? UITableView {
            return tableView
        }

        for subview in view.subviews {
            if let tableView = firstTableView(in: subview) {
                return tableView
            }
        }

        return nil
    }
}

@MainActor
@Observable
private final class PerformanceRowModel: Identifiable {
    let id: Int
    var title: String

    init(id: Int) {
        self.id = id
        self.title = "Row \(id)"
    }
}

/// A row shaped like a feed card: one node reads observable state, the rest do
/// not. What a cell-local change costs depends on how much of this the runtime
/// has to write again.
@MainActor
private struct PerformanceHeavyRow: Renderable {
    static let coldNodeCount = 7

    let model: PerformanceRowModel

    var body: any Renderable {
        FineStack.vertical {
            FineLabel(text: self.model.title)
            for index in 0..<Self.coldNodeCount {
                FineLabel(text: "Detail \(index)")
            }
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
