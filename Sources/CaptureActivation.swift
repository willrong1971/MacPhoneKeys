import Foundation

/// Tracks one request while app activation, key-window, and responder events arrive.
/// Readiness is supplied by the UI each time; old events cannot start a new request.
struct CaptureActivation {
    struct Request: Equatable {
        let id: UUID
        let fromHotKey: Bool
    }
    private(set) var pending: Request?

    mutating func begin(fromHotKey: Bool) -> Request {
        let request = Request(id: UUID(), fromHotKey: fromHotKey)
        pending = request
        return request
    }

    mutating func completeIfReady(_ request: Request, appActive: Bool,
                                  panelKey: Bool, responderReady: Bool) -> Request? {
        guard isCurrent(request), appActive, panelKey, responderReady else { return nil }
        pending = nil
        return request
    }

    @discardableResult mutating func cancel(_ request: Request? = nil) -> Bool {
        guard let current = pending, request == nil || request == current else { return false }
        pending = nil
        return true
    }

    func isCurrent(_ request: Request) -> Bool { pending == request }
}
