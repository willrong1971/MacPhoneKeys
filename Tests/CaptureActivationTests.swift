import Foundation

@main enum CaptureActivationTests {
    static func main() {
        var checks = 0
        func expect(_ condition: Bool, _ message: String) {
            checks += 1
            guard condition else { fatalError(message) }
        }

        // A closed settings window leaves the app inactive. The shortcut must
        // retain its request while the compact panel is gaining focus.
        var activation = CaptureActivation()
        let shortcut = activation.begin(fromHotKey: true)
        expect(activation.pending == shortcut, "inactive app retains the shortcut request")
        expect(activation.completeIfReady(shortcut, appActive: false, panelKey: false, responderReady: false) == nil,
               "showing a panel is not sufficient to begin input")
        expect(activation.isCurrent(shortcut), "not-ready must not discard the request")
        expect(activation.completeIfReady(shortcut, appActive: false, panelKey: true, responderReady: true) == nil,
               "key-window event may arrive before application activation")
        expect(activation.completeIfReady(shortcut, appActive: true, panelKey: true, responderReady: true) == shortcut,
               "later application activation completes the pending shortcut")
        expect(activation.pending == nil, "completed request is consumed")
        expect(activation.completeIfReady(shortcut, appActive: true, panelKey: true, responderReady: true) == nil,
               "duplicate notifications cannot begin capture twice")

        // Cover every event order, including active-before-key and key-before-active.
        let orders = [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]]
        for order in orders {
            let request = activation.begin(fromHotKey: false)
            var ready = [false, false, false] // application, panel, first responder
            for (position, event) in order.enumerated() {
                ready[event] = true
                let completed = activation.completeIfReady(request, appActive: ready[0], panelKey: ready[1], responderReady: ready[2])
                expect(completed == (position == 2 ? request : nil), "capture starts only after all focus events: \(order)")
                expect(activation.isCurrent(request) == (position < 2), "request persists until the final focus event: \(order)")
            }
        }

        // Being active and key is still unsafe if the keyboard surface did not
        // become first responder. A subsequent stop/focus loss cancels that wait.
        let missingResponder = activation.begin(fromHotKey: true)
        expect(activation.completeIfReady(missingResponder, appActive: true, panelKey: true, responderReady: false) == nil,
               "wrong first responder must never start relaying keys")
        expect(activation.isCurrent(missingResponder), "wait for the responder instead of hiding the panel")
        expect(activation.cancel(), "stop or focus loss cancels pending activation")
        expect(!activation.cancel(), "cancelling an idle state reports no request")
        expect(activation.completeIfReady(missingResponder, appActive: true, panelKey: true, responderReady: true) == nil,
               "late responder events after stopping must not restart input")

        // An old timeout belongs to its own request, never to the current attempt.
        let oldRequest = activation.begin(fromHotKey: true)
        let newRequest = activation.begin(fromHotKey: false)
        expect(oldRequest.id != newRequest.id, "each activation has a distinct token")
        expect(!activation.cancel(oldRequest), "old timeout must not cancel a newer request")
        expect(activation.pending == newRequest, "new request survives the old timeout")
        expect(activation.completeIfReady(oldRequest, appActive: true, panelKey: true, responderReady: true) == nil,
               "old focus event cannot complete or consume a new request")
        expect(activation.pending == newRequest, "ignoring stale completion preserves current activation")
        let completed = activation.completeIfReady(newRequest, appActive: true, panelKey: true, responderReady: true)
        expect(completed == newRequest && completed?.fromHotKey == false, "completion preserves the new request's origin")

        // A rapid start/stop/start sequence must not resurrect the first shortcut
        // when its queued activation or cancellation arrives after the second.
        let firstToggle = activation.begin(fromHotKey: true)
        expect(activation.cancel(firstToggle), "second toggle cancels its own pending start")
        let thirdToggle = activation.begin(fromHotKey: true)
        expect(!activation.cancel(firstToggle), "first start's delayed timeout cannot cancel the third toggle")
        expect(activation.completeIfReady(firstToggle, appActive: true, panelKey: true, responderReady: true) == nil,
               "first toggle cannot activate after it was stopped")
        expect(activation.isCurrent(thirdToggle), "latest rapid toggle remains current")
        expect(activation.completeIfReady(thirdToggle, appActive: true, panelKey: true, responderReady: true) == thirdToggle,
               "latest rapid toggle activates exactly once")
        expect(!activation.isCurrent(thirdToggle), "completed third toggle is no longer pending")

        print("PASS: \(checks) capture activation/focus-order regression checks")
    }
}
