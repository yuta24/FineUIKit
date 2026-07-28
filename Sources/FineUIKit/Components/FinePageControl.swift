//
//  FinePageControl.swift
//  FineUIKit
//
//  Created by nova on 2026/07/28.
//

import UIKit

@MainActor
public struct FinePageControl: FinePrimitiveRenderable {
    private static let actionKey = "FineUIKit.FinePageControl.valueChanged"

    private let numberOfPages: Int
    private let currentPage: FineBinding<Int>
    private var hidesForSinglePage: Bool?
    private var pageIndicatorTintColor: UIColor?
    private var currentPageIndicatorTintColor: UIColor?

    public var body: any Renderable {
        fatalError("Primitive Renderable body should not be evaluated")
    }

    public init(numberOfPages: Int, currentPage: FineBinding<Int>) {
        self.numberOfPages = numberOfPages
        self.currentPage = currentPage
    }

    /// Sets whether the control hides itself when there is a single page.
    public func hidesForSinglePage(_ hides: Bool = true) -> FinePageControl {
        var copy = self
        copy.hidesForSinglePage = hides
        return copy
    }

    public func pageIndicatorTintColor(_ color: UIColor) -> FinePageControl {
        var copy = self
        copy.pageIndicatorTintColor = color
        return copy
    }

    public func currentPageIndicatorTintColor(_ color: UIColor) -> FinePageControl {
        var copy = self
        copy.currentPageIndicatorTintColor = color
        return copy
    }

    func _makeView() -> UIView {
        UIPageControl(frame: .zero)
    }

    func _canUpdate(_ view: UIView) -> Bool {
        view is UIPageControl
    }

    func _update(_ view: UIView, context: FineRenderContext) {
        guard let pageControl = view as? UIPageControl else { return }

        let resolvedNumberOfPages = max(numberOfPages, 0)
        let resolvedHidesForSinglePage = hidesForSinglePage ?? false

        if pageControl.numberOfPages != resolvedNumberOfPages {
            pageControl.numberOfPages = resolvedNumberOfPages
        }

        // Written after the page count, which UIKit clamps the current page
        // against: an index the new count no longer covers would otherwise
        // stick around as the last valid one.
        let page = min(max(currentPage.value, 0), max(resolvedNumberOfPages - 1, 0))
        if pageControl.currentPage != page {
            pageControl.currentPage = page
        }
        // The state follows what is actually shown, so shrinking the page count
        // does not leave an index past the end in the app's own state — where a
        // sibling `pages[page]` would trap (same rule as `FineSlider`).
        //
        // Not while there are no pages at all: that is the shape of a list
        // still loading, and resetting the index there would throw away a
        // restored or deep-linked page before the data it belongs to arrives.
        if resolvedNumberOfPages > 0, currentPage.value != page {
            currentPage.value = page
        }

        if pageControl.hidesForSinglePage != resolvedHidesForSinglePage {
            pageControl.hidesForSinglePage = resolvedHidesForSinglePage
        }
        if pageControl.pageIndicatorTintColor != pageIndicatorTintColor {
            pageControl.pageIndicatorTintColor = pageIndicatorTintColor
        }
        if pageControl.currentPageIndicatorTintColor != currentPageIndicatorTintColor {
            pageControl.currentPageIndicatorTintColor = currentPageIndicatorTintColor
        }

        pageControl.fineSetHandler(Self.actionKey, for: .valueChanged) { [currentPage] control in
            guard let pageControl = control as? UIPageControl else { return }
            currentPage.value = pageControl.currentPage
        }
    }
}
