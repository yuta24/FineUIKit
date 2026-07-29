//
//  FineDiagnostics.swift
//  FineUIKit
//
//  Created by nova on 2026/07/26.
//

import Foundation
import OSLog
import UIKit

/// Explains what the reconciler did, for the questions a diff-based runtime
/// makes hard to answer by reading code: *why was this view rebuilt instead of
/// updated?* and *was this view re-rendered at all?*
///
/// Rebuilding is not an error — it is how FineUIKit keeps a removed modifier
/// from leaving its effect behind — but an unintended rebuild loses first
/// responder status, scroll position and `FineState`, so it is worth seeing.
///
/// Enable it from the debugger, in code, or by setting `FINEUIKIT_LOG_REUSE=1`
/// in the scheme's environment:
///
/// ```swift
/// FineDiagnostics.logsViewReuse = true
/// ```
///
/// Render counts are always kept — they cost two integer increments per render
/// — so `fineDebugDescription` and `fineDumpTree()` answer for a view that was
/// rendered long before anyone thought to switch a flag on.
@MainActor
public enum FineDiagnostics {
    /// Whether view rebuilds are reported. Defaults to `FINEUIKIT_LOG_REUSE=1`
    /// in the process environment.
    public static var logsViewReuse =
        ProcessInfo.processInfo.environment["FINEUIKIT_LOG_REUSE"] == "1"

    /// Whether *every* render is reported, not only the ones that rebuilt a
    /// view. Defaults to `FINEUIKIT_LOG_RENDERS=1` in the process environment.
    ///
    /// Much noisier than `logsViewReuse` — a full render of the tree reports
    /// one line per view — but it answers what the rebuild log cannot: whether
    /// a view was re-rendered at all, and how often.
    public static var logsRenders =
        ProcessInfo.processInfo.environment["FINEUIKIT_LOG_RENDERS"] == "1"

    /// Whether re-rendered views flash an outline: green for an in-place
    /// update, red for a rebuild, labelled with the running render count.
    /// Defaults to `FINEUIKIT_HIGHLIGHT_RENDERS=1` in the process environment.
    ///
    /// DEBUG builds only: nothing draws in a release build, whatever this says.
    /// Turn it off before measuring frame rates — drawing the overlay costs
    /// more than most of what it is reporting on.
    public static var highlightsRenders =
        ProcessInfo.processInfo.environment["FINEUIKIT_HIGHLIGHT_RENDERS"] == "1"

    /// Whether a toast confirms that a code injection reached the runtime and
    /// re-rendered. Defaults to on; set `FINEUIKIT_INJECTION_TOAST=0` to
    /// silence it. DEBUG builds only.
    ///
    /// It separates the two failures that look identical on screen: the
    /// injection never arrived, or it arrived and the description did not
    /// change.
    public static var showsInjectionToast =
        ProcessInfo.processInfo.environment["FINEUIKIT_INJECTION_TOAST"] != "0"

    /// Receives diagnostic messages. Replace it to route them somewhere else —
    /// a test, a file, an in-app console. The default logs to `OSLog`.
    public static var handler: @MainActor (String) -> Void = { message in
        logger.debug("\(message, privacy: .public)")
    }

    private static let logger = Logger(subsystem: "FineUIKit", category: "reuse")

    /// Why an existing view could not be updated in place.
    enum RebuildReason {
        case viewType
        case modifierSignature(previous: String, current: String)
        case key(previous: AnyHashable?, current: AnyHashable?)

        var message: String {
            switch self {
            case .viewType:
                "view type is incompatible"
            case let .modifierSignature(previous, current):
                "modifier composition changed (\"\(previous)\" → \"\(current)\")"
            case let .key(previous, current):
                "key changed (\(Self.describe(previous)) → \(Self.describe(current)))"
            }
        }

        private static func describe(_ key: AnyHashable?) -> String {
            key.map { "\($0.base)" } ?? "none"
        }
    }

    /// How a view came to be rendered.
    enum RenderKind {
        /// A new view, with nothing in its place before it.
        case created
        /// A new view replacing one that could not be updated in place.
        case rebuilt
        /// An existing view updated in place.
        case updated

        var message: String {
            switch self {
            case .created: "created"
            case .rebuilt: "rebuilt"
            case .updated: "updated"
            }
        }
    }

    static func reportRebuild(
        of view: UIView,
        for primitive: any FinePrimitiveRenderable,
        reason: RebuildReason
    ) {
        guard logsViewReuse else { return }

        // The component, matching what the render log and the debug
        // description say about the same view. The modifier that wrapped it is
        // not lost: for the reason that names one, it is in the message.
        handler("FineUIKit rebuilt \(type(of: view)) for \(type(of: primitive._viewProvider)): \(reason.message)")
    }

    /// Moves the counters of a replaced view onto the view taking its place, so
    /// they describe the position in the tree rather than the object: a rebuild
    /// makes a new view and a new `FineNode`, and starting from zero there
    /// would hide the very churn the counts exist to expose.
    static func carryCounters(from previous: UIView?, to view: UIView) {
        guard let previous = previous?.fineNodeIfPresent else { return }

        let node = view.fineNode
        node.renderCount = previous.renderCount
        node.rebuildCount = previous.rebuildCount + 1
    }

    /// Counts a render that has just been applied to `view`, and reports it if
    /// asked to. Called from the update sites themselves rather than from the
    /// reuse decision, so a node-local re-render — which never revisits that
    /// decision — is counted like any other.
    static func recordRender(of view: UIView, as kind: RenderKind) {
        let node = view.fineNode
        node.renderCount += 1

        if logsRenders {
            handler(
                "FineUIKit \(kind.message) \(type(of: view)) for \(node.primitiveName)"
                    + " (render #\(node.renderCount), \(node.rebuildCount) rebuilt)"
            )
        }

        #if DEBUG
        if highlightsRenders {
            FineDebugHighlight.flash(view, kind: kind, count: node.renderCount)
        }
        #endif
    }
}
