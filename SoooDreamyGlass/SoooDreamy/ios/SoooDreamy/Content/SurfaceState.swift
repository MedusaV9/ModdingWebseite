import Foundation

enum SurfacePhase: String, Equatable {
    case loading
    case content
    case empty
    case offline
    case failed
}

enum SurfaceState {
    /// One precedence table shared by server-backed screens. Existing content
    /// wins over transient transport errors; a failed request wins over an
    /// empty state; offline is distinct from an empty server response.
    static func resolve(
        loading: Bool,
        hasContent: Bool,
        connected: Bool,
        requestFailed: Bool
    ) -> SurfacePhase {
        if hasContent { return .content }
        if loading { return .loading }
        if requestFailed { return .failed }
        if !connected { return .offline }
        return .empty
    }
}
