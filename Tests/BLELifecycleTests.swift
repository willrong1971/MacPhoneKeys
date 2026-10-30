import Foundation

@main enum BLELifecycleTests {
    static func main() {
        var checks = 0
        func expect(_ condition: Bool, _ message: String) {
            checks += 1
            guard condition else { fatalError(message) }
        }
        func register(_ model: inout BLELifecycle) -> Int {
            _ = model.start()
            let token = model.generation
            _ = model.radioChanged(.poweredOn)
            return token
        }
        func advertised(_ model: inout BLELifecycle) -> Int {
            let token = register(&model)
            for service in 0..<3 { _ = model.didAddService(service, generation: token, succeeded: true) }
            _ = model.didStartAdvertising(generation: token, succeeded: true, isAdvertising: true)
            return token
        }
        let cleanup: [BLELifecycle.Action] = [.cancelDeadline, .resetInput, .clearPublishedObjects]
        let failureCleanup: [BLELifecycle.Action] = [.cancelDeadline, .resetInput, .retirePublication, .clearPublishedObjects]

        // A radio initially off or unknown does not cause manager recreation
        // loops. Commands to publish are deferred until poweredOn.
        var initial = BLELifecycle()
        let start = initial.start()
        expect(start == cleanup + [.replaceManager(generation: 1)], "start creates one owned manager")
        expect(initial.start().isEmpty, "repeated start is idempotent")
        expect(initial.radioChanged(.unknown) == [.resetInput], "initial unknown does not recreate manager")
        expect(initial.radioChanged(.poweredOff) == [.resetInput], "initial off waits without radio commands")
        expect(initial.generation == 1 && initial.phase == .waitingForRadio, "initial wait retains its generation")
        expect(initial.radioChanged(.poweredOn) == [.publish(generation: 1), .registrationDeadline(generation: 1)],
               "first power-on starts exactly one publication and deadline")
        expect(initial.radioChanged(.poweredOn).isEmpty, "duplicate powered-on callback cannot republish")

        // All six service-completion orders must wait for all three services;
        // duplicate callbacks cannot inflate readiness or repeat advertising.
        for order in [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]] {
            var model = BLELifecycle()
            let token = register(&model)
            for (position, service) in order.enumerated() {
                let actions = model.didAddService(service, generation: token, succeeded: true)
                expect(model.registeredServiceCount == position + 1, "count unique current services")
                expect(actions.contains(.advertise(generation: token)) == (position == 2), "advertise only after all mandatory services")
                expect(model.didAddService(service, generation: token, succeeded: true).isEmpty, "ignore duplicate service callback")
            }
            expect(model.phase == .advertising, "registration transitions to advertising")
            expect(model.didStartAdvertising(generation: token, succeeded: true, isAdvertising: false) == [.cancelDeadline],
                   "current success cancels deadline even if pairing has already paused advertising")
            expect(model.phase == .ready, "pairing confirmation may wait indefinitely without an input subscription")
            expect(model.didStartAdvertising(generation: token, succeeded: true, isAdvertising: true).isEmpty,
                   "duplicate success does not revive an expired stage")
            expect(model.phase == .ready, "publisher is ready without requiring a subscriber")
            expect(model.registrationTimedOut(generation: token).isEmpty, "old registration timeout cannot restart a ready publisher")
            expect(model.advertisingTimedOut(generation: token, isAdvertising: false).isEmpty,
                   "no subscription or later advertising pause never triggers a ready-stage recovery")
            expect(model.didStartAdvertising(generation: token, succeeded: false, isAdvertising: false).isEmpty,
                   "late advertising error cannot tear down a ready publisher")
        }

        // Even a tokenless advertising callback is contained by its manager's
        // generation; the adapter replaces managers for every publication.
        var cycle = BLELifecycle()
        let old = advertised(&cycle)
        let off = cycle.radioChanged(.poweredOff)
        expect(off == cleanup, "off clears input and invalidates local service identities")
        expect(cycle.phase == .waitingForRadio && cycle.registeredServiceCount == 0, "off is never connected/ready")
        expect(!cycle.acceptsCurrentPublication(old), "old publication invalidated immediately")
        expect(cycle.didSubscribe(generation: old).isEmpty, "late encrypted subscription while off cannot restore readiness")
        expect(cycle.didAddService(0, generation: old, succeeded: true).isEmpty, "late registration while off ignored")
        expect(cycle.didStartAdvertising(generation: old, succeeded: true, isAdvertising: true).isEmpty,
               "late advertising callback while off ignored")
        let restored = cycle.radioChanged(.poweredOn)
        let fresh = cycle.generation
        expect(restored == cleanup + [.replaceManager(generation: fresh)], "power-on first retires old manager, not blindly adds services")
        expect(fresh != old, "power recovery has a fresh manager generation")
        expect(cycle.phase == .waitingForRadio, "wait for replacement manager's own powered-on callback")
        expect(cycle.radioChanged(.unknown) == [.resetInput], "replacement initial state does not recreate again")
        expect(cycle.radioChanged(.poweredOn) == [.publish(generation: fresh), .registrationDeadline(generation: fresh)],
               "replacement manager publishes only when its own radio is ready")
        expect(cycle.didAddService(1, generation: old, succeeded: true).isEmpty, "old manager's queued success cannot count toward new services")
        expect(cycle.registeredServiceCount == 0, "fresh publication has no inherited successes")

        for interruption in [BLELifecycle.RadioState.poweredOff, .resetting, .unauthorized, .unsupported, .unknown] {
            var model = BLELifecycle()
            let interrupted = register(&model)
            _ = model.didAddService(0, generation: interrupted, succeeded: true)
            expect(model.radioChanged(interruption) == cleanup, "partially registered state invalidates on every unusable radio state")
            expect(model.didAddService(1, generation: interrupted, succeeded: true).isEmpty, "late partial completion is discarded")
            _ = model.radioChanged(.poweredOn)
            let replacement = model.generation
            _ = model.radioChanged(.poweredOn)
            expect(model.registeredServiceCount == 0 && model.phase == .registering, "interrupted services must all be registered again")
            expect(model.acceptsCurrentPublication(replacement), "new radio publication is accepted")
        }

        // Recoveries are bounded across fresh managers and successful stage
        // transitions; duplicate state callbacks cannot skip the backoff.
        var failures = BLELifecycle()
        var token = register(&failures)
        for attempt in 1...2 {
            let actions = failures.registrationTimedOut(generation: token)
            let retryToken = failures.generation
            expect(failures.phase == .recovering && failures.recoveryAttempt == attempt, "each timeout spends one retry")
            expect(actions == failureCleanup + [.retryDeadline(generation: retryToken, delay: TimeInterval(attempt))], "retry retires failed GATT and has bounded backoff")
            expect(failures.radioChanged(.poweredOn).isEmpty, "duplicate on cannot bypass retry delay")
            expect(failures.retryDue(generation: token).isEmpty, "old timer cannot recover new generation")
            let retry = failures.retryDue(generation: retryToken)
            token = failures.generation
            expect(retry == cleanup + [.replaceManager(generation: token)], "retry owns a distinct manager")
            _ = failures.radioChanged(.unknown)
            _ = failures.radioChanged(.poweredOn)
            expect(failures.recoveryAttempt == attempt, "new manager does not reset retry budget")
        }
        expect(failures.didAddService(0, generation: token, succeeded: false) == failureCleanup,
               "third failure retires advertising and services even though no retry will follow")
        expect(failures.phase == .failed && failures.recoveryCount == 2, "automatic recovery stops at configured limit")
        expect(failures.radioChanged(.poweredOn).isEmpty, "failed publisher cannot spin on on-notifications")
        let manual = failures.recover()
        expect(failures.recoveryAttempt == 0 && failures.phase == .waitingForRadio, "explicit recovery grants a new bounded budget")
        expect(manual.contains(.replaceManager(generation: failures.generation)), "explicit recovery creates one fresh manager")

        var advertising = BLELifecycle()
        let adToken = register(&advertising)
        for service in 0..<3 { _ = advertising.didAddService(service, generation: adToken, succeeded: true) }
        _ = advertising.advertisingTimedOut(generation: adToken, isAdvertising: false)
        expect(advertising.lastFailure == .advertisingTimeout && advertising.phase == .recovering,
               "missing advertising callback is recoverable within the same budget")
        var error = BLELifecycle()
        let errorToken = register(&error)
        for service in 0..<3 { _ = error.didAddService(service, generation: errorToken, succeeded: true) }
        _ = error.didStartAdvertising(generation: errorToken, succeeded: false, isAdvertising: false)
        expect(error.lastFailure == .advertising && error.recoveryAttempt == 1, "advertising error also spends the bounded budget")
        var subscribed = BLELifecycle()
        let subToken = register(&subscribed)
        for service in 0..<3 { _ = subscribed.didAddService(service, generation: subToken, succeeded: true) }
        expect(subscribed.didSubscribe(generation: subToken) == [.cancelDeadline], "current input subscription is stronger than an advertising callback")
        expect(subscribed.advertisingTimedOut(generation: subToken, isAdvertising: false).isEmpty,
               "newly connected central cannot be disconnected by old advertising deadline")
        var reading = BLELifecycle()
        let readToken = register(&reading)
        for service in 0..<3 { _ = reading.didAddService(service, generation: readToken, succeeded: true) }
        expect(reading.didReceiveATT(generation: readToken) == [.cancelDeadline],
               "actual use of published GATT cancels a missing advertising callback deadline")
        expect(reading.advertisingTimedOut(generation: readToken, isAdvertising: false).isEmpty,
               "waiting for encrypted input after ATT use is not an advertising startup failure")

        // A stop cancels both recovery timers and any pending radio work. There
        // is no event for 'no subscriber' that could restart the publisher.
        var stopped = BLELifecycle()
        let stopToken = register(&stopped)
        _ = stopped.registrationTimedOut(generation: stopToken)
        let pendingRetry = stopped.generation
        expect(stopped.stop() == cleanup + [.discardManager], "stop invalidates every publication and deadline")
        expect(stopped.retryDue(generation: pendingRetry).isEmpty, "stop blocks delayed recovery")
        expect(stopped.radioChanged(.poweredOn).isEmpty, "stop blocks later radio callbacks")
        expect(stopped.didSubscribe(generation: stopToken).isEmpty, "stop blocks later subscription callbacks")
        expect(stopped.stop().isEmpty, "repeated stop is idempotent")

        print("PASS: \(checks) BLE lifecycle/recovery checks")
    }
}
