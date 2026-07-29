//
//  FineDivider.swift
//  FineUIKit
//
//  Created by nova on 2026/07/28.
//

import UIKit

/// Hairline view whose thickness follows the display scale, so the line stays
/// one physical pixel wherever it is shown.
@MainActor
final class FineDividerView: UIView {
    /// The direction the line runs in: `.horizontal` is a line drawn across,
    /// which is the one that separates rows in a vertical stack.
    var lineAxis: NSLayoutConstraint.Axis = .horizontal {
        didSet {
            guard lineAxis != oldValue else { return }
            invalidateIntrinsicContentSize()
        }
    }

    /// Explicit thickness, or `nil` for a hairline.
    var thickness: CGFloat? {
        didSet {
            guard thickness != oldValue else { return }
            invalidateIntrinsicContentSize()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        backgroundColor = .separator
        // The line must not absorb the space a `.fill` stack hands out, and
        // must not be squeezed away either — but neither priority is required:
        // at 1000 the intrinsic thickness would outrank `.height(_:)`, whose
        // default is 999, and silently keep the divider a hairline. Hugging
        // above the 250 that ordinary content uses is enough to make the stack
        // stretch a sibling instead of this line.
        setContentHuggingPriority(.defaultHigh, for: .horizontal)
        setContentHuggingPriority(.defaultHigh, for: .vertical)
        setContentCompressionResistancePriority(.init(999), for: .horizontal)
        setContentCompressionResistancePriority(.init(999), for: .vertical)

        registerForTraitChanges([UITraitDisplayScale.self]) { (view: Self, _) in
            view.invalidateIntrinsicContentSize()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        let scale = traitCollection.displayScale
        let resolved = thickness ?? (scale > 0 ? 1 / scale : 1)

        return lineAxis == .horizontal
            ? CGSize(width: UIView.noIntrinsicMetric, height: resolved)
            : CGSize(width: resolved, height: UIView.noIntrinsicMetric)
    }
}

/// A separator line, sized to a hairline on its thin axis and stretched by its
/// container on the other one.
///
/// ```swift
/// FineStack.vertical(spacing: 8) {
///     FineLabel(text: "Account")
///     FineDivider()
///     FineLabel(text: "Privacy")
/// }
/// ```
@MainActor
public struct FineDivider: FinePrimitiveRenderable {
    private let axis: NSLayoutConstraint.Axis
    private var thickness: CGFloat?
    private var color: UIColor?

    public var body: any Renderable {
        fatalError("Primitive Renderable body should not be evaluated")
    }

    private init(axis: NSLayoutConstraint.Axis) {
        self.axis = axis
    }

    /// A line drawn across — the separator for a vertical stack.
    public init() {
        self.init(axis: .horizontal)
    }

    /// A line drawn down — the separator for a horizontal stack.
    public static func vertical() -> FineDivider {
        .init(axis: .vertical)
    }

    /// A line drawn across — the separator for a vertical stack.
    public static func horizontal() -> FineDivider {
        .init(axis: .horizontal)
    }

    /// Sets an explicit thickness. Without it the line is one physical pixel.
    public func thickness(_ thickness: CGFloat) -> FineDivider {
        var copy = self
        copy.thickness = thickness
        return copy
    }

    public func color(_ color: UIColor) -> FineDivider {
        var copy = self
        copy.color = color
        return copy
    }

    func _makeView() -> UIView {
        FineDividerView(frame: .zero)
    }

    func _canUpdate(_ view: UIView) -> Bool {
        view is FineDividerView
    }

    func _update(_ view: UIView, context: FineRenderContext) {
        guard let divider = view as? FineDividerView else { return }

        let resolvedColor = color ?? .separator

        divider.lineAxis = axis
        divider.thickness = resolveThickness()
        if divider.backgroundColor?.isEqual(resolvedColor) != true {
            divider.backgroundColor = resolvedColor
        }
    }

    /// `UIView.noIntrinsicMetric` is `-1`, so a negative thickness would not
    /// draw a thin line — it would read as "no intrinsic size on this axis" and
    /// let the line collapse or stretch. A NaN reaches Auto Layout and throws.
    /// Neither is a thickness anyone can mean, so both fall back to the
    /// hairline and are reported in debug builds.
    private func resolveThickness() -> CGFloat? {
        guard let thickness else { return nil }

        guard thickness.isFinite, thickness >= 0 else {
            assertionFailure("FineDivider thickness must be a non-negative finite value, got \(thickness)")
            return nil
        }

        return thickness
    }
}
