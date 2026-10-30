import Foundation

/// Connection evidence is deliberately separate from the result of the system
/// pairing panel and from a person's observation of text on their phone.
struct PairingFlow {
    struct Observation: Equatable {
        var running: Bool
        var authorization: String
        var radioState: String
        var phase: String
        var isAdvertising: Bool
        var registeredServiceCount: Int
        var requiredServiceCount: Int
        var reportSubscriberCount: Int
        var bootSubscriberCount: Int
        var inputReady: Bool
        var recoveryAttempt: Int
        var recoveryLimit: Int
        var generation: String?
        var isPreview: Bool

        init(snapshot: [String: Any] = [:], isPreview: Bool = false) {
            running = snapshot["running"] as? Bool ?? false
            authorization = snapshot["authorization"] as? String ?? "unknown"
            radioState = snapshot["radioState"] as? String ?? "unknown"
            phase = snapshot["phase"] as? String ?? "stopped"
            isAdvertising = snapshot["isAdvertising"] as? Bool ?? false
            registeredServiceCount = snapshot["registeredServiceCount"] as? Int ?? 0
            requiredServiceCount = snapshot["requiredServiceCount"] as? Int ?? 3
            reportSubscriberCount = snapshot["reportSubscriberCount"] as? Int ?? 0
            bootSubscriberCount = snapshot["bootSubscriberCount"] as? Int ?? 0
            inputReady = snapshot["inputReady"] as? Bool ?? false
            recoveryAttempt = snapshot["recoveryAttempt"] as? Int ?? 0
            recoveryLimit = snapshot["recoveryLimit"] as? Int ?? 2
            if let counter = snapshot["generation"] as? Int { generation = "counter:\(counter)" }
            else { generation = snapshot["generation"] as? String }
            self.isPreview = isPreview
        }

        var radioOn: Bool { radioState == "poweredOn" }
        var servicesReady: Bool {
            requiredServiceCount > 0 && registeredServiceCount == requiredServiceCount
        }
        var keyboardReady: Bool {
            running && authorization == "allowedAlways" && radioOn && servicesReady
                && inputReady && reportSubscriberCount + bootSubscriberCount > 0
        }
    }

    enum SystemPanelResult: String {
        case notOpened, open, cancelled, selectionPaired, failed
    }

    enum VerificationState: String {
        case notTested, sending, awaitingUser, visibleByUser, notVisibleByUser
    }

    private struct TestAttempt {
        let id: UUID
        let epoch: Int
        var finishedSending = false
    }

    private struct ManualReport {
        let visible: Bool
        let date: Date
        let epoch: Int
    }

    private(set) var observation = Observation()
    private(set) var systemPanelResult = SystemPanelResult.notOpened
    private(set) var systemPanelOpen = false
    private var connectionEpoch = 0
    private var testAttempt: TestAttempt?
    private var lastManualReport: ManualReport?

    mutating func observe(_ next: Observation) {
        // A new service generation or a lost/re-established input subscription
        // invalidates the old trial, even if the UI missed an intermediate event.
        if next.generation != observation.generation || next.keyboardReady != observation.keyboardReady {
            connectionEpoch += 1
            testAttempt = nil
        }
        observation = next
    }

    var canOpenSystemPairing: Bool {
        observation.running && observation.radioOn && observation.servicesReady
            && observation.isAdvertising && !observation.keyboardReady && !systemPanelOpen
            && !observation.isPreview
    }

    var canRecoverService: Bool {
        observation.running && observation.radioOn && !systemPanelOpen
            && observation.phase != "recovering"
            && observation.phase != "registering"
            && verificationState != .sending && !observation.isPreview
    }

    var canSendTest: Bool {
        observation.keyboardReady && !systemPanelOpen && verificationState != .sending
    }

    var canConfirmPhoneText: Bool {
        observation.keyboardReady && !observation.isPreview
            && testAttempt?.epoch == connectionEpoch && testAttempt?.finishedSending == true
            && verificationState == .awaitingUser
    }

    var verificationState: VerificationState {
        if let attempt = testAttempt, attempt.epoch == connectionEpoch {
            return attempt.finishedSending ? .awaitingUser : .sending
        }
        if observation.keyboardReady, let report = lastManualReport, report.epoch == connectionEpoch {
            return report.visible ? .visibleByUser : .notVisibleByUser
        }
        return .notTested
    }

    mutating func systemPanelDidOpen() {
        systemPanelOpen = true
        systemPanelResult = .open
    }

    mutating func systemPanelDidFinish(_ result: SystemPanelResult) {
        systemPanelOpen = false
        systemPanelResult = result
        // No transport state is inferred from the system panel's return code.
    }

    @discardableResult
    mutating func beginTest() -> UUID? {
        guard canSendTest else { return nil }
        let id = UUID()
        lastManualReport = nil
        testAttempt = TestAttempt(id: id, epoch: connectionEpoch)
        return id
    }

    @discardableResult
    mutating func finishedSendingTest(_ id: UUID) -> Bool {
        guard observation.keyboardReady, var attempt = testAttempt,
              attempt.id == id, attempt.epoch == connectionEpoch, !attempt.finishedSending else { return false }
        attempt.finishedSending = true
        testAttempt = attempt
        return true
    }

    mutating func cancelTest(_ id: UUID? = nil) {
        guard id == nil || testAttempt?.id == id else { return }
        testAttempt = nil
    }

    @discardableResult
    mutating func recordPhoneTextVisible(_ visible: Bool, at date: Date = Date()) -> Bool {
        guard canConfirmPhoneText else { return false }
        lastManualReport = ManualReport(visible: visible, date: date, epoch: connectionEpoch)
        testAttempt = nil
        return true
    }

    mutating func serviceRecoveryRequested() {
        connectionEpoch += 1
        testAttempt = nil
    }

    var diagnosticSnapshot: [String: Any] {
        var result: [String: Any] = [
            "systemPairingPanel": systemPanelResult.rawValue,
            "keyboardInputReady": observation.keyboardReady,
            "phoneTextVerification": verificationState.rawValue,
            "phoneTextVerifiedByUser": verificationState == .visibleByUser,
            "verificationSource": "userObservation",
            "preview": observation.isPreview
        ]
        if let report = lastManualReport {
            result["lastUserReportedVisible"] = report.visible
            result["lastUserReportAt"] = ISO8601DateFormatter().string(from: report.date)
            result["lastUserReportAppliesToCurrentConnection"] = report.epoch == connectionEpoch && observation.keyboardReady
        }
        return result
    }
}

/// Existing users already have a runtime log. Migrate them without opening a
/// new window; first-time users see the assistant once, whether or not they finish.
enum ConnectionAssistantOnboarding {
    static let preferenceKey = "hasSeenConnectionAssistantV1"

    static func shouldPresent(hasExistingUse: Bool, defaults: UserDefaults = .standard) -> Bool {
        if defaults.bool(forKey: preferenceKey) { return false }
        defaults.set(true, forKey: preferenceKey)
        return !hasExistingUse
    }

    static func markSeen(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: preferenceKey)
    }
}
