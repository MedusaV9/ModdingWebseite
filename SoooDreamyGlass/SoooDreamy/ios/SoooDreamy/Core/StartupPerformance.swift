import Foundation
import OSLog

/// Signposts the user-visible cold-start path for Instruments and CI metrics.
/// The interval ends after cached state is rendered and bootstrap completes.
enum StartupPerformance {
    private static let log = OSLog(
        subsystem: Bundle.main.bundleIdentifier ?? "app.sooodreamy.ios",
        category: .pointsOfInterest
    )
    private static let id = OSSignpostID(log: log)

    static func begin() {
        os_signpost(.begin, log: log, name: "ColdStartToDashboard", signpostID: id)
    }

    static func end() {
        os_signpost(.end, log: log, name: "ColdStartToDashboard", signpostID: id)
    }
}
