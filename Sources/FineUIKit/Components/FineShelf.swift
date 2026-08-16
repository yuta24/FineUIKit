//
//  FineShelf.swift
//  FineUIKit
//
//  Created by nova on 2026/08/16.
//

import UIKit

/// How wide one item on a shelf is.
public enum FineShelfItemWidth: Equatable {
    /// A number of points, whatever the shelf's own width.
    case fixed(CGFloat)
    /// A fraction of the shelf's width. Values below 1 leave the next item
    /// showing at the edge, which is what tells a reader the shelf scrolls.
    case fractional(CGFloat)
}

/// A horizontal run of items that scrolls on its own, inside a screen that
/// scrolls the other way.
///
/// The shape every media and store app has a row of — "continue watching",
/// "recently played". There was no way to say it: `FineGrid` is vertical,
/// `FineScrollView` scrolls horizontally but recycles nothing and diffs
/// nothing, so a long shelf built from it holds every item's views at once.
///
/// ```swift
/// FineStack.vertical(spacing: 16) {
///     FineLabel(text: "Continue watching")
///     FineShelf(episodes, itemWidth: .fixed(160)) { FineEpisodeCard($0) }
///         .height(200)
/// }
/// ```
///
/// A shelf has no height of its own, the same way a `UICollectionView` does
/// not: give it one with `.height(_:)` or `.frame(height:)`. Items are as tall
/// as the shelf.
@MainActor
public struct FineShelf<Element: Identifiable>: FinePrimitiveRenderable where Element.ID: Sendable {
    private let elements: [Element]
    private let itemWidth: FineShelfItemWidth
    private let spacing: CGFloat
    private let content: @MainActor (Element) -> any Renderable
    private var onSelect: (@MainActor (Element) -> Void)?
    private var onPrefetch: (@MainActor ([Element]) -> Void)?
    private var onCancelPrefetch: (@MainActor ([Element]) -> Void)?
    private var reconfiguresAllItems = false

    public var body: any Renderable {
        fatalError("Primitive Renderable body should not be evaluated")
    }

    public init(
        _ elements: [Element],
        itemWidth: FineShelfItemWidth = .fixed(140),
        spacing: CGFloat = 12,
        content: @escaping @MainActor (Element) -> any Renderable
    ) {
        self.elements = elements
        self.itemWidth = itemWidth
        self.spacing = spacing
        self.content = content
    }

    public func onSelect(_ handler: @escaping @MainActor (Element) -> Void) -> FineShelf {
        var copy = self
        copy.onSelect = handler
        return copy
    }

    /// Reports items that are about to be needed.
    ///
    /// A shelf is the shape this was made for: the items to either side of the
    /// visible run are one flick away, and each of them is usually an image.
    /// See `FineGrid.onPrefetch(_:)`.
    public func onPrefetch(_ handler: @escaping @MainActor ([Element]) -> Void) -> FineShelf {
        var copy = self
        copy.onPrefetch = handler
        return copy
    }

    /// An opportunity to stop work started in `onPrefetch(_:)`.
    public func onCancelPrefetch(_ handler: @escaping @MainActor ([Element]) -> Void) -> FineShelf {
        var copy = self
        copy.onCancelPrefetch = handler
        return copy
    }

    /// Re-runs item content for every surviving item on each render, instead of
    /// only for items whose element changed.
    public func reconfiguringAllItems() -> FineShelf {
        var copy = self
        copy.reconfiguresAllItems = true
        return copy
    }

    func _makeView() -> UIView {
        let shelfView = FineShelfView(frame: .zero, collectionViewLayout: Self.makeLayout())
        let layout = Self.makeLayout { [weak shelfView] in
            (shelfView?.coordinator as? Coordinator)?.layoutConfiguration ?? .init()
        }
        shelfView.setCollectionViewLayout(layout, animated: false)
        shelfView.backgroundColor = .clear
        shelfView.showsHorizontalScrollIndicator = false
        shelfView.alwaysBounceHorizontal = true
        // A shelf is laid out by the tree around it, not by the screen. Left to
        // adjust, it would subtract the window's safe area from its own height
        // and lay out items shorter than the height it was given — wrong
        // anywhere, and absurd for a shelf sitting in the middle of a screen.
        shelfView.contentInsetAdjustmentBehavior = .never
        return shelfView
    }

    func _canUpdate(_ view: UIView) -> Bool {
        guard let shelfView = view as? FineShelfView else { return false }
        return shelfView.coordinator == nil || shelfView.coordinator is Coordinator
    }

    func _update(_ view: UIView, context: FineRenderContext) {
        guard let shelfView = view as? FineShelfView else { return }

        let coordinator: Coordinator
        if let existing = shelfView.coordinator as? Coordinator {
            coordinator = existing
        } else {
            coordinator = .init(collectionView: shelfView)
            shelfView.coordinator = coordinator
        }

        coordinator.content = content
        coordinator.onSelect = onSelect
        coordinator.onPrefetch = onPrefetch
        coordinator.onCancelPrefetch = onCancelPrefetch
        coordinator.environmentStorage.update(context.environment)
        coordinator.renderGate = context.renderGate
        fineUpdatePrefetching(on: shelfView, with: coordinator)

        // The layout reads these back through the coordinator, so a change to
        // either has to make it run again.
        let configuration = LayoutConfiguration(itemWidth: itemWidth, spacing: spacing)
        if coordinator.layoutConfiguration != configuration {
            coordinator.layoutConfiguration = configuration
            shelfView.collectionViewLayout.invalidateLayout()
        }

        coordinator.apply(
            elements,
            reconfiguresAll: reconfiguresAllItems,
            name: "FineShelf",
            in: shelfView
        )
    }

    private static func makeLayout(
        configuration: (@MainActor () -> LayoutConfiguration)? = nil
    ) -> UICollectionViewCompositionalLayout {
        let layoutConfiguration = UICollectionViewCompositionalLayoutConfiguration()
        layoutConfiguration.scrollDirection = .horizontal

        return UICollectionViewCompositionalLayout(
            sectionProvider: { _, _ in
                let resolved = configuration?() ?? .init()
                let width: NSCollectionLayoutDimension
                switch resolved.itemWidth {
                case .fixed(let points):
                    width = .absolute(max(points, 1))
                case .fractional(let fraction):
                    width = .fractionalWidth(min(max(fraction, 0.01), 1))
                }

                // The group carries the width; the item fills it. Giving both
                // the same fractional width would multiply the two — a shelf
                // asked for 0.8 would lay out items at 0.64.
                let item = NSCollectionLayoutItem(
                    layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .fractionalHeight(1))
                )
                let group = NSCollectionLayoutGroup.horizontal(
                    layoutSize: .init(widthDimension: width, heightDimension: .fractionalHeight(1)),
                    subitems: [item]
                )

                let section = NSCollectionLayoutSection(group: group)
                section.interGroupSpacing = resolved.spacing
                // A shelf is as tall as the tree said, not as tall as what is
                // left after the screen's safe area. Without this a shelf under
                // the status bar lays out items shorter than the height it was
                // given — and unlike overriding the view's `safeAreaInsets`,
                // this leaves the real insets readable by the content inside.
                section.contentInsetsReference = .none
                return section
            },
            configuration: layoutConfiguration
        )
    }
}

extension FineShelf {
    struct LayoutConfiguration: Equatable {
        var itemWidth: FineShelfItemWidth = .fixed(140)
        var spacing: CGFloat = 12
    }

    @MainActor
    final class Coordinator: FineFlatCollectionCoordinator<Element> {
        var layoutConfiguration = LayoutConfiguration()
    }
}

@MainActor
final class FineShelfView: FineCollectionHostView {}
