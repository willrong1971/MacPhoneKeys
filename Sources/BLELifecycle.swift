import Foundation

/// Pure decisions for the app-owned GATT publisher. No radio or timers are
/// created here. Every new publication uses a fresh manager generation, so even
/// advertising callbacks (which have no request identifier) have an owner.
struct BLELifecycle {
    enum RadioState: String { case unknown, resetting, unsupported, unauthorized, poweredOff, poweredOn }
    enum Phase: String { case stopped, waitingForRadio, registering, advertising, ready, recovering, failed }
    enum Failure: String { case registration, registrationTimeout, advertising, advertisingTimeout }
    enum Action: Equatable {
        case cancelDeadline
        case resetInput
        case clearPublishedObjects
        case retirePublication
        case replaceManager(generation: Int)
        case discardManager
        case publish(generation: Int)
        case advertise(generation: Int)
        case registrationDeadline(generation: Int)
        case advertisingDeadline(generation: Int)
        case retryDeadline(generation: Int, delay: TimeInterval)
    }

    let requiredServiceCount = 3
    let recoveryLimit: Int
    private(set) var running = false
    private(set) var phase: Phase = .stopped
    private(set) var radioState: RadioState = .unknown
    private(set) var generation = 0
    private(set) var recoveryAttempt = 0
    private(set) var recoveryCount = 0
    private(set) var lastFailure: Failure?
    private var registeredServices = Set<Int>()
    private var publicationStarted = false
    private var needsFreshManager = false

    init(recoveryLimit: Int = 2) { self.recoveryLimit = max(0, recoveryLimit) }

    var registeredServiceCount: Int { registeredServices.count }
    var servicesReady: Bool { phase == .advertising || phase == .ready }

    mutating func start() -> [Action] {
        guard !running else { return [] }
        running = true
        recoveryAttempt = 0
        lastFailure = nil
        return freshManager()
    }

    mutating func stop() -> [Action] {
        guard running else { return [] }
        running = false
        generation += 1
        phase = .stopped
        radioState = .unknown
        registeredServices.removeAll()
        publicationStarted = false
        needsFreshManager = false
        return [.cancelDeadline, .resetInput, .clearPublishedObjects, .discardManager]
    }

    /// One explicit recovery gives the new attempt its own bounded retry budget.
    mutating func recover() -> [Action] {
        if !running { return start() }
        recoveryAttempt = 0
        lastFailure = nil
        return freshManager()
    }

    /// State callbacks from the current manager remain useful after its old
    /// publication was invalidated: they tell us when cleanup is legal again.
    mutating func radioChanged(_ state: RadioState) -> [Action] {
        guard running else { return [] }
        radioState = state
        guard state == .poweredOn else {
            // A newly created manager may initially report unknown or off. It
            // has no published objects to invalidate, and must not recreate in
            // a loop each time its initial powered-on callback arrives.
            guard publicationStarted || phase == .recovering || phase == .failed else {
                return [.resetInput]
            }
            generation += 1
            phase = .waitingForRadio
            registeredServices.removeAll()
            publicationStarted = false
            needsFreshManager = true
            recoveryAttempt = 0
            return [.cancelDeadline, .resetInput, .clearPublishedObjects]
        }
        guard phase != .recovering, phase != .failed else { return [] }
        if needsFreshManager {
            // Never guess whether poweredOff retained the GATT database. The
            // adapter clears its services while on before replacing the manager.
            return freshManager()
        }
        guard phase == .waitingForRadio, !publicationStarted else { return [] }
        publicationStarted = true
        phase = .registering
        return [.publish(generation: generation), .registrationDeadline(generation: generation)]
    }

    mutating func didAddService(_ service: Int, generation token: Int, succeeded: Bool) -> [Action] {
        guard accepts(token, phase: .registering), (0..<requiredServiceCount).contains(service) else { return [] }
        guard succeeded else { return fail(.registration) }
        guard registeredServices.insert(service).inserted,
              registeredServices.count == requiredServiceCount else { return [] }
        phase = .advertising
        return [.cancelDeadline, .advertise(generation: generation), .advertisingDeadline(generation: generation)]
    }

    mutating func didStartAdvertising(generation token: Int, succeeded: Bool, isAdvertising: Bool) -> [Action] {
        guard accepts(token, phase: .advertising) else { return [] }
        // The current manager owns this callback. Advertising may already be
        // paused for an incoming connection while a person confirms pairing;
        // its instantaneous flag must not start a timer that tears pairing down.
        if succeeded || isAdvertising { return becomeReady() }
        return fail(.advertising)
    }

    /// A valid current encrypted input subscription proves the publisher is
    /// operational, even if the advertising callback is delayed or advertising
    /// has already paused for the new connection.
    mutating func didSubscribe(generation token: Int) -> [Action] {
        guard accepts(token, phase: .advertising) else { return [] }
        return becomeReady()
    }

    mutating func didReceiveATT(generation token: Int) -> [Action] {
        guard accepts(token, phase: .advertising) else { return [] }
        return becomeReady()
    }

    mutating func registrationTimedOut(generation token: Int) -> [Action] {
        guard accepts(token, phase: .registering) else { return [] }
        return fail(.registrationTimeout)
    }

    mutating func advertisingTimedOut(generation token: Int, isAdvertising: Bool) -> [Action] {
        guard accepts(token, phase: .advertising) else { return [] }
        return isAdvertising ? becomeReady() : fail(.advertisingTimeout)
    }

    mutating func retryDue(generation token: Int) -> [Action] {
        guard running, phase == .recovering, radioState == .poweredOn, generation == token else { return [] }
        return freshManager()
    }

    func acceptsCurrentPublication(_ token: Int) -> Bool {
        running && generation == token && radioState == .poweredOn && publicationStarted
            && (phase == .registering || servicesReady)
    }

    private func accepts(_ token: Int, phase expected: Phase) -> Bool {
        acceptsCurrentPublication(token) && phase == expected
    }

    private mutating func freshManager() -> [Action] {
        generation += 1
        phase = .waitingForRadio
        radioState = .unknown
        registeredServices.removeAll()
        publicationStarted = false
        needsFreshManager = false
        return [.cancelDeadline, .resetInput, .clearPublishedObjects, .replaceManager(generation: generation)]
    }

    private mutating func becomeReady() -> [Action] {
        phase = .ready
        return [.cancelDeadline]
    }

    private mutating func fail(_ failure: Failure) -> [Action] {
        lastFailure = failure
        generation += 1 // Invalidate services, callbacks and the old deadline now.
        registeredServices.removeAll()
        publicationStarted = false
        needsFreshManager = true
        // Keep the manager only as a radio observer after exhaustion. It must
        // not keep advertising services whose old-generation ATT is rejected.
        let cleanup: [Action] = [.cancelDeadline, .resetInput, .retirePublication, .clearPublishedObjects]
        guard recoveryAttempt < recoveryLimit else {
            phase = .failed
            return cleanup
        }
        recoveryAttempt += 1
        recoveryCount += 1
        phase = .recovering
        return cleanup + [.retryDeadline(generation: generation, delay: TimeInterval(recoveryAttempt))]
    }
}
