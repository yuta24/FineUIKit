//
//  FineDatePicker.swift
//  FineUIKit
//
//  Created by nova on 2026/07/28.
//

import UIKit

@MainActor
public struct FineDatePicker: FinePrimitiveRenderable {
    private static let actionKey = "FineUIKit.FineDatePicker.valueChanged"

    private let selection: FineBinding<Date>
    private let range: ClosedRange<Date>?
    private var datePickerMode: UIDatePicker.Mode?
    private var preferredDatePickerStyle: UIDatePickerStyle?
    private var minuteInterval: Int?
    private var isEnabled = true

    public var body: any Renderable {
        fatalError("Primitive Renderable body should not be evaluated")
    }

    /// Creates a date picker bound to `selection`, optionally limited to
    /// `range`.
    public init(selection: FineBinding<Date>, in range: ClosedRange<Date>? = nil) {
        self.selection = selection
        self.range = range
    }

    /// Sets what the picker edits (date, time, both, or a countdown).
    public func datePickerMode(_ mode: UIDatePicker.Mode) -> FineDatePicker {
        var copy = self
        copy.datePickerMode = mode
        return copy
    }

    /// Sets the presentation style (compact, inline, wheels).
    public func preferredDatePickerStyle(_ style: UIDatePickerStyle) -> FineDatePicker {
        var copy = self
        copy.preferredDatePickerStyle = style
        return copy
    }

    /// Sets the granularity of the minute wheel. Must divide 60 evenly.
    public func minuteInterval(_ interval: Int) -> FineDatePicker {
        var copy = self
        copy.minuteInterval = interval
        return copy
    }

    /// Sets whether the picker responds to user interaction.
    public func enabled(_ isEnabled: Bool = true) -> FineDatePicker {
        var copy = self
        copy.isEnabled = isEnabled
        return copy
    }

    func _makeView() -> UIView {
        UIDatePicker(frame: .zero)
    }

    func _canUpdate(_ view: UIView) -> Bool {
        view is UIDatePicker
    }

    func _update(_ view: UIView, context: FineRenderContext) {
        guard let picker = view as? UIDatePicker else { return }

        let resolvedMode = datePickerMode ?? .dateAndTime
        let resolvedStyle = preferredDatePickerStyle ?? .automatic
        let resolvedMinuteInterval = resolveMinuteInterval()

        if picker.datePickerMode != resolvedMode {
            picker.datePickerMode = resolvedMode
        }
        if picker.preferredDatePickerStyle != resolvedStyle {
            picker.preferredDatePickerStyle = resolvedStyle
        }
        if picker.minuteInterval != resolvedMinuteInterval {
            picker.minuteInterval = resolvedMinuteInterval
        }

        // The bounds are written before the date, so a date the new range
        // clamps lands inside it rather than being clamped afterwards.
        if picker.minimumDate != range?.lowerBound {
            picker.minimumDate = range?.lowerBound
        }
        if picker.maximumDate != range?.upperBound {
            picker.maximumDate = range?.upperBound
        }

        // `.countDownTimer` drives `countDownDuration`, not `date`: UIKit
        // ignores writes to `date` there, so syncing would leave the guard
        // below permanently true and the write-back would overwrite the bound
        // date with the picker's own. A `Date` binding cannot express a
        // duration, so the mode is left unsupported rather than half-wired.
        if resolvedMode == .countDownTimer {
            assertionFailure("FineDatePicker does not support .countDownTimer; it binds a Date, not a duration")
        } else {
            // Only write when the value actually differs, so a re-render while
            // the wheels are spinning doesn't snap them back.
            if picker.date != selection.value {
                picker.date = selection.value
            }
            // UIKit clamps the written date to `minimumDate`/`maximumDate` and
            // rounds it to `minuteInterval`. The state follows what is actually
            // shown, so a date the picker cannot take is corrected once —
            // without this the guard above never holds again and every render
            // rewrites the date (same rule as `FineSlider`).
            if selection.value != picker.date {
                selection.value = picker.date
            }
        }

        if picker.isEnabled != isEnabled {
            picker.isEnabled = isEnabled
        }

        picker.fineSetHandler(Self.actionKey, for: .valueChanged) { [selection] control in
            guard let picker = control as? UIDatePicker else { return }
            selection.value = picker.date
        }
    }

    /// `UIDatePicker` silently keeps 1 when the interval does not divide 60, so
    /// an invalid one would be rewritten on every render. It is rejected here
    /// instead, and reported in debug builds.
    private func resolveMinuteInterval() -> Int {
        guard let minuteInterval else { return 1 }

        guard minuteInterval > 0, 60 % minuteInterval == 0 else {
            assertionFailure("FineDatePicker minuteInterval must divide 60 evenly, got \(minuteInterval)")
            return 1
        }

        return minuteInterval
    }
}
