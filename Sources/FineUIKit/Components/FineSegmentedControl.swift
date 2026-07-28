//
//  FineSegmentedControl.swift
//  FineUIKit
//
//  Created by nova on 2026/07/28.
//

import UIKit

@MainActor
public struct FineSegmentedControl: FinePrimitiveRenderable {
    private static let actionKey = "FineUIKit.FineSegmentedControl.valueChanged"

    /// What a single segment shows. A segment carries either a title or an
    /// image, mirroring `UISegmentedControl`.
    public enum Segment {
        case title(String)
        case image(UIImage)
    }

    private let segments: [Segment]
    private let selection: FineBinding<Int>
    private var isEnabled = true

    public var body: any Renderable {
        fatalError("Primitive Renderable body should not be evaluated")
    }

    public init(segments: [Segment], selection: FineBinding<Int>) {
        self.segments = segments
        self.selection = selection
    }

    public init(titles: [String], selection: FineBinding<Int>) {
        self.init(segments: titles.map(Segment.title), selection: selection)
    }

    /// Sets whether the control responds to user interaction.
    public func enabled(_ isEnabled: Bool = true) -> FineSegmentedControl {
        var copy = self
        copy.isEnabled = isEnabled
        return copy
    }

    func _makeView() -> UIView {
        UISegmentedControl(frame: .zero)
    }

    func _canUpdate(_ view: UIView) -> Bool {
        view is UISegmentedControl
    }

    func _update(_ view: UIView, context: FineRenderContext) {
        guard let control = view as? UISegmentedControl else { return }

        applySegments(to: control)

        // Selection is written after the segments: removing or inserting
        // segments shifts UIKit's own `selectedSegmentIndex`, and an index the
        // description no longer covers must read as "nothing selected" rather
        // than as whatever survived the shift.
        let index = segments.indices.contains(selection.value)
            ? selection.value
            : UISegmentedControl.noSegment
        if control.selectedSegmentIndex != index {
            control.selectedSegmentIndex = index
        }
        if control.isEnabled != isEnabled {
            control.isEnabled = isEnabled
        }

        control.fineSetHandler(Self.actionKey, for: .valueChanged) { [selection] control in
            guard let control = control as? UISegmentedControl else { return }
            selection.value = control.selectedSegmentIndex
        }
    }

    /// Reconciles the control's segments in place, so a reused control keeps
    /// its selection and its running animations when only a title changed.
    private func applySegments(to control: UISegmentedControl) {
        // Extra segments go from the tail, keeping the indices below stable.
        while control.numberOfSegments > segments.count {
            control.removeSegment(at: control.numberOfSegments - 1, animated: false)
        }

        for (index, segment) in segments.enumerated() {
            guard index < control.numberOfSegments else {
                switch segment {
                case let .title(title):
                    control.insertSegment(withTitle: title, at: index, animated: false)
                case let .image(image):
                    control.insertSegment(with: image, at: index, animated: false)
                }
                continue
            }

            // A segment holds a title or an image, never both, so the other
            // one is cleared first — otherwise a segment that changed kind
            // would keep showing what it had before.
            switch segment {
            case let .title(title):
                if control.imageForSegment(at: index) != nil {
                    control.setImage(nil, forSegmentAt: index)
                }
                if control.titleForSegment(at: index) != title {
                    control.setTitle(title, forSegmentAt: index)
                }
            case let .image(image):
                if control.titleForSegment(at: index) != nil {
                    control.setTitle(nil, forSegmentAt: index)
                }
                // Compared by value, like the title above: a description that
                // derives its image per render (`withTintColor`, a symbol
                // configuration, `UIImage(data:)`) hands over a fresh instance
                // every time, and re-setting it would re-run the control's
                // segment sizing on every render.
                if control.imageForSegment(at: index) != image {
                    control.setImage(image, forSegmentAt: index)
                }
            }
        }
    }
}
