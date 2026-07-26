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
/// updated?*
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
@MainActor
public enum FineDiagnostics {
    /// Whether view rebuilds are reported. Defaults to `FINEUIKIT_LOG_REUSE=1`
    /// in the process environment.
    public static var logsViewReuse =
        ProcessInfo.processInfo.environment["FINEUIKIT_LOG_REUSE"] == "1"

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

    static func reportRebuild(
        of view: UIView,
        for primitive: any FinePrimitiveRenderable,
        reason: RebuildReason
    ) {
        guard logsViewReuse else { return }

        handler("FineUIKit rebuilt \(type(of: view)) for \(type(of: primitive)): \(reason.message)")
    }
}
