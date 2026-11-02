import Foundation

/// A user-guided plan. Observations can advance to a text check, but this model
/// never performs an action or treats a Next button as phone-side success.
struct TroubleshootingFlow {
    enum Symptom: String { case firstConnection, macNotVisible, pairingFailed, connectedNoText }
    enum Step: String {
        case chooseSymptom, checkMac, openMacPairing, findMac, waitForKeyboard
        case testPhoneText, recoverService, waitAfterRecovery, systemSupport, finished, exportDiagnostics
    }
    enum Action: String { case none, startService, openBluetoothSettings, openSystemPairing, sendTest, recoverService, systemSupport, exportDiagnostics }
    enum Blocker: Equatable { case stopped, permission, radio, preparing, failedService }
    enum ExitReason: String { case requestedEarly, stepsExhausted, unableToPerform, completedVerified }

    struct Evidence {
        var running = false
        var permissionAllowed = false
        var radioOn = false
        var servicesReady = false
        var phase = "stopped"
        var keyboardReady = false
        var verification = "notTested"
        var verificationAttemptID: UUID?
        var generation: String?
    }

    private(set) var symptom: Symptom?
    private(set) var step = Step.chooseSymptom
    private(set) var recoveryUsed = false
    private(set) var pairingRequested = false
    private(set) var supportRequested = false
    private(set) var testRequested = false
    private(set) var sawCurrentTest = false
    private(set) var exitReason: ExitReason?
    private(set) var skippedStep: Step?
    private var history: [Step] = []
    private var evidence = Evidence()
    private var reviewingPreviousStep = false
    private var testBaselineID: UUID?
    private var currentGuideTestID: UUID?
    private var recoveryBaselineGeneration: String?
    private var attemptedPreparation: Blocker?

    var blocker: Blocker? {
        if !evidence.running { return .stopped }
        if !evidence.permissionAllowed { return .permission }
        if !evidence.radioOn { return .radio }
        if !evidence.servicesReady {
            return evidence.phase == "failed" ? .failedService : .preparing
        }
        return nil
    }

    var displayedStep: Step {
        if blocker != nil && step != .exportDiagnostics { return .checkMac }
        if step == .testPhoneText && !evidence.keyboardReady { return .waitForKeyboard }
        return step
    }

    mutating func begin(_ symptom: Symptom) {
        self.symptom = symptom
        history = [.chooseSymptom]
        reviewingPreviousStep = false
        recoveryUsed = false; pairingRequested = false; supportRequested = false
        testRequested = false; sawCurrentTest = false
        exitReason = nil; skippedStep = nil; attemptedPreparation = nil
        testBaselineID = nil; currentGuideTestID = nil; recoveryBaselineGeneration = nil
        switch symptom {
        case .firstConnection, .pairingFailed: step = .openMacPairing
        case .macNotVisible: step = .findMac
        case .connectedNoText: step = .testPhoneText
        }
    }

    mutating func observe(_ next: Evidence) {
        let lostKeyboard = evidence.keyboardReady && !next.keyboardReady
        let changedGeneration = evidence.generation != next.generation
        evidence = next
        if lostKeyboard || changedGeneration || blocker != nil {
            testRequested = false; sawCurrentTest = false; currentGuideTestID = nil
        }
        if testRequested, blocker == nil, next.keyboardReady,
           let id = next.verificationAttemptID, id != testBaselineID,
           ["sending", "awaitingUser"].contains(next.verification) {
            sawCurrentTest = true; currentGuideTestID = id
        }
        if symptom != nil && blocker == nil && next.keyboardReady && !reviewingPreviousStep {
            if [.openMacPairing, .findMac, .waitForKeyboard, .systemSupport].contains(step)
                || step == .waitAfterRecovery && freshRecoveryConnection {
                move(to: .testPhoneText)
            }
            if step == .testPhoneText && sawCurrentTest && next.verification == "visibleByUser"
                && next.verificationAttemptID == currentGuideTestID {
                move(to: .finished)
            }
        }
        if step == .finished && (lostKeyboard || changedGeneration || blocker != nil) {
            move(to: .waitForKeyboard)
        }
    }

    var primaryAction: Action {
        if displayedStep == .checkMac {
            switch blocker {
            case .stopped: return .startService
            case .permission, .radio: return .openBluetoothSettings
            case .failedService: return recoveryUsed ? .exportDiagnostics : .recoverService
            default: return .none
            }
        }
        switch displayedStep {
        case .openMacPairing: return .openSystemPairing
        case .findMac: return .openBluetoothSettings
        case .waitForKeyboard: return .openSystemPairing
        case .testPhoneText: return .sendTest
        case .recoverService: return recoveryUsed ? .exportDiagnostics : .recoverService
        case .systemSupport: return .systemSupport
        case .exportDiagnostics: return .exportDiagnostics
        default: return .none
        }
    }

    /// Call only when the UI is about to dispatch this explicit user action.
    @discardableResult
    mutating func recordAction(_ action: Action) -> Bool {
        guard action != .none, action == primaryAction else { return false }
        reviewingPreviousStep = false
        if displayedStep == .checkMac { attemptedPreparation = blocker }
        switch action {
        case .openSystemPairing: pairingRequested = true
        case .recoverService:
            guard !recoveryUsed else { return false }
            recoveryUsed = true
            testRequested = false; sawCurrentTest = false
            currentGuideTestID = nil
            recoveryBaselineGeneration = evidence.generation
            move(to: symptom == nil ? .chooseSymptom : .waitAfterRecovery)
        case .sendTest:
            testRequested = true; sawCurrentTest = false
            testBaselineID = evidence.verificationAttemptID; currentGuideTestID = nil
        case .systemSupport: supportRequested = true
        case .exportDiagnostics: finishWithDiagnostics()
        default: break
        }
        return true
    }

    var canGoBack: Bool { !history.isEmpty }
    mutating func goBack() {
        guard let previous = history.popLast() else { return }
        step = previous
        reviewingPreviousStep = true
        exitReason = nil; skippedStep = nil
        // The action budget is not reset, and no action is replayed.
    }

    var canGoNext: Bool {
        guard blocker == nil else { return false }
        switch displayedStep {
        case .openMacPairing: return pairingRequested
        case .findMac: return true
        case .systemSupport: return supportRequested
        case .waitForKeyboard: return evidence.keyboardReady
        case .waitAfterRecovery: return freshRecoveryConnection
        default: return false
        }
    }

    mutating func goNext() {
        guard canGoNext else { return }
        reviewingPreviousStep = false
        switch displayedStep {
        case .openMacPairing, .systemSupport: move(to: .findMac)
        case .findMac: move(to: .waitForKeyboard)
        case .waitForKeyboard, .waitAfterRecovery: move(to: .testPhoneText)
        default: break
        }
    }

    var canReportStillFailing: Bool {
        guard symptom != nil else { return false }
        switch displayedStep {
        case .chooseSymptom, .finished, .exportDiagnostics, .waitAfterRecovery: return false
        case .checkMac: return blocker != nil && attemptedPreparation == blocker && primaryAction != .none
        case .openMacPairing: return pairingRequested
        case .systemSupport: return supportRequested
        case .recoverService: return recoveryUsed
        case .testPhoneText: return testRequested
        case .findMac, .waitForKeyboard: return true
        }
    }

    var canReportUnableToPerformStep: Bool {
        symptom != nil && ![.chooseSymptom, .finished, .exportDiagnostics].contains(displayedStep)
    }

    /// Explicitly records a skipped step; it never stands in for a completed action.
    mutating func unableToPerformStep() {
        guard canReportUnableToPerformStep else { return }
        skippedStep = displayedStep
        exitReason = .unableToPerform
        move(to: .exportDiagnostics)
    }

    mutating func stillNotWorking() {
        guard canReportStillFailing else { return }
        if displayedStep == .checkMac { move(to: .exportDiagnostics); return }
        switch displayedStep {
        case .openMacPairing: move(to: supportRequested ? .exportDiagnostics : .systemSupport)
        case .findMac, .testPhoneText: move(to: recoveryUsed ? supportOrDiagnostics : .recoverService)
        case .waitForKeyboard:
            if symptom == .pairingFailed || symptom == .firstConnection {
                move(to: supportRequested ? .exportDiagnostics : .systemSupport)
            } else { move(to: recoveryUsed ? supportOrDiagnostics : .recoverService) }
        case .systemSupport: move(to: .exportDiagnostics)
        case .recoverService: move(to: supportOrDiagnostics)
        default: break
        }
    }

    /// This feedback is supplied only by the existing phone-text confirmation UI.
    mutating func phoneTextReportedMissing() {
        guard allowsConfirmation(attemptID: evidence.verificationAttemptID) else { return }
        move(to: recoveryUsed ? supportOrDiagnostics : .recoverService)
    }

    func allowsConfirmation(attemptID: UUID?) -> Bool {
        step == .testPhoneText && blocker == nil && evidence.keyboardReady && sawCurrentTest
            && attemptID != nil && attemptID == currentGuideTestID
    }

    mutating func recoveryStillFailed() {
        guard displayedStep == .waitAfterRecovery else { return }
        move(to: supportOrDiagnostics)
    }

    /// Exporting is allowed at any point, including when the save sheet is later
    /// cancelled. Neither entering this page nor saving a file verifies recovery.
    mutating func finishWithDiagnostics() {
        if exitReason == nil { exitReason = .requestedEarly }
        move(to: .exportDiagnostics)
    }

    private var supportOrDiagnostics: Step { supportRequested ? .exportDiagnostics : .systemSupport }
    private var freshRecoveryConnection: Bool {
        evidence.keyboardReady && evidence.generation != nil && evidence.generation != recoveryBaselineGeneration
    }

    var diagnosticSnapshot: [String: Any] {
        var snapshot: [String: Any] = [
            "scope": "currentGuide", "symptom": symptom?.rawValue ?? "notSelected",
            "step": displayedStep.rawValue, "serviceRecoveryUsed": recoveryUsed,
            "pairingRequested": pairingRequested, "supportRequested": supportRequested
        ]
        if let exitReason { snapshot["exitReason"] = exitReason.rawValue }
        if let skippedStep { snapshot["skippedStep"] = skippedStep.rawValue }
        return snapshot
    }

    private mutating func move(to next: Step) {
        guard step != next else { return }
        if next == .finished { exitReason = .completedVerified }
        else if next == .exportDiagnostics {
            if exitReason == nil { exitReason = .stepsExhausted }
        } else { exitReason = nil; skippedStep = nil }
        history.append(step)
        step = next
    }
}
