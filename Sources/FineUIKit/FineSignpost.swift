//
//  FineSignpost.swift
//  FineUIKit
//
//  Created by nova on 2026/07/29.
//

import OSLog

/// Signpost intervals for the three render loops, so Instruments answers the
/// timing questions instead of a hand-written profiler.
///
/// Recorded under Points of Interest, which the standard Time Profiler and
/// Animation Hitches templates already show — no custom template needed. Start
/// a recording, and each interval names the description that was rendered:
///
/// - `render` — a root render: `body(_:)` re-evaluated and the tree re-diffed
/// - `node` — one node's update, including the node-local ones that a change
///   read during an update triggers on their own
/// - `cell` — a list or grid cell's hosted subtree
///
/// Nothing is emitted unless a tool is recording, so these stay in release
/// builds: the cost of an unobserved signpost is the enabled check.
enum FineSignpost {
    static let signposter = OSSignposter(
        logHandle: OSLog(subsystem: "FineUIKit", category: .pointsOfInterest)
    )
}
