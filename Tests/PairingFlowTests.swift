import Foundation

@main enum PairingFlowTests {
    static func main() {
        var checks = 0
        func expect(_ value: Bool, _ message: String) {
            checks += 1
            guard value else { fatalError(message) }
        }
        func observation(_ changes: [String: Any] = [:], preview: Bool = false) -> PairingFlow.Observation {
            var snapshot: [String: Any] = [
                "running": true, "authorization": "allowedAlways", "radioState": "poweredOn",
                "phase": "advertising", "isAdvertising": true,
                "registeredServiceCount": 3, "requiredServiceCount": 3,
                "reportSubscriberCount": 0, "bootSubscriberCount": 0, "inputReady": false,
                "recoveryAttempt": 0, "recoveryLimit": 2, "generation": "first"
            ]
            snapshot.merge(changes) { _, new in new }
            return PairingFlow.Observation(snapshot: snapshot, isPreview: preview)
        }
        let ready = observation(["phase": "ready", "isAdvertising": false, "reportSubscriberCount": 1, "inputReady": true])
        var flow = PairingFlow()
        expect(!flow.observation.keyboardReady && !flow.canSendTest, "missing evidence is not a ready keyboard")
        flow.observe(observation())
        expect(flow.canOpenSystemPairing, "an advertising service may open the user-triggered system panel")
        expect(!flow.canConfirmPhoneText, "advertising cannot establish visible phone text")
        flow.systemPanelDidOpen()
        expect(!flow.canOpenSystemPairing && !flow.canRecoverService, "the system panel cannot be opened or recovered twice")
        flow.systemPanelDidFinish(.selectionPaired)
        expect(!flow.observation.keyboardReady && !flow.canSendTest, "a system pairing result does not create an input subscription")
        flow.systemPanelDidOpen(); flow.systemPanelDidFinish(.cancelled)
        expect(flow.systemPanelResult == .cancelled && flow.observation == observation(), "cancelling leaves transport evidence untouched")
        flow.observe(ready)
        expect(flow.observation.keyboardReady && flow.canSendTest, "encrypted current input evidence enables a trial")
        expect(!flow.canOpenSystemPairing, "an existing keyboard session does not offer unnecessary new pairing")
        expect(flow.verificationState == .notTested, "a subscription never claims phone text")
        expect(!flow.recordPhoneTextVisible(true), "manual confirmation requires a finished trial")
        let first = flow.beginTest()!
        expect(flow.verificationState == .sending && !flow.canConfirmPhoneText, "a sending trial cannot yet be confirmed")
        expect(!flow.canSendTest && !flow.canRecoverService, "a second trial or recovery cannot interrupt the current trial through the assistant")
        expect(!flow.finishedSendingTest(UUID()), "an unrelated completion cannot complete this trial")
        expect(flow.finishedSendingTest(first), "the matching trial may finish handing reports to its queue")
        expect(!flow.finishedSendingTest(first), "duplicate completion is ignored")
        expect(flow.verificationState == .awaitingUser && flow.canConfirmPhoneText, "queued reports wait for a person's observation")
        expect(flow.diagnosticSnapshot["phoneTextVerifiedByUser"] as? Bool == false, "queue acceptance is not human validation")
        expect(flow.recordPhoneTextVisible(true, at: Date(timeIntervalSince1970: 100)), "an explicit person report is accepted")
        expect(flow.verificationState == .visibleByUser, "human validation is labeled separately")
        expect(flow.diagnosticSnapshot["phoneTextVerifiedByUser"] as? Bool == true, "diagnostics retain the explicit user report")
        expect(!flow.recordPhoneTextVisible(false), "repeated confirmations cannot replace a completed trial")
        flow.observe(observation())
        expect(flow.verificationState == .notTested, "loss of subscription invalidates current validation")
        expect(flow.diagnosticSnapshot["lastUserReportAppliesToCurrentConnection"] as? Bool == false, "historical reports are not silently applied to a new connection")
        flow.observe(ready)
        expect(flow.verificationState == .notTested, "reconnection requires a new visible trial")
        let second = flow.beginTest()!
        flow.observe(observation(["generation": "second", "phase": "ready", "reportSubscriberCount": 1, "inputReady": true]))
        expect(!flow.finishedSendingTest(second), "a changed service generation invalidates a late trial completion")
        expect(flow.verificationState == .notTested, "a missed intermediate disconnect still invalidates the old trial")
        let third = flow.beginTest()!
        expect(flow.finishedSendingTest(third), "new service trial finishes normally")
        expect(flow.recordPhoneTextVisible(false), "a person may explicitly report missing text")
        expect(flow.verificationState == .notVisibleByUser, "failure feedback is not treated as transport failure or success")
        flow.serviceRecoveryRequested()
        expect(flow.verificationState == .notTested, "manual recovery invalidates the old trial immediately")
        let fourth = flow.beginTest()!
        flow.cancelTest(UUID())
        expect(flow.verificationState == .sending, "a stale cancellation cannot stop the current trial")
        flow.cancelTest(fourth)
        expect(!flow.finishedSendingTest(fourth), "cancelled trial completion is ignored")
        flow.observe(observation(["generation": 1, "phase": "ready", "reportSubscriberCount": 1, "inputReady": true]))
        let integerGenerationTrial = flow.beginTest()!
        flow.observe(observation(["generation": 2, "phase": "ready", "reportSubscriberCount": 1, "inputReady": true]))
        expect(!flow.finishedSendingTest(integerGenerationTrial), "integer transport generations invalidate stale test completions")

        for changes: [String: Any] in [
            ["authorization": "denied"], ["radioState": "poweredOff"], ["running": false],
            ["registeredServiceCount": 2], ["requiredServiceCount": 0], ["inputReady": false],
            ["reportSubscriberCount": 0, "bootSubscriberCount": 0]
        ] {
            var snapshot: [String: Any] = ["phase": "ready", "reportSubscriberCount": 1, "inputReady": true]
            snapshot.merge(changes) { _, new in new }
            flow.observe(observation(snapshot))
            expect(!flow.observation.keyboardReady, "partial or contradictory evidence never enables input: \(changes)")
            expect(!flow.canConfirmPhoneText, "partial evidence cannot confirm phone delivery")
        }
        flow.observe(observation(["reportSubscriberCount": 0, "bootSubscriberCount": 1, "inputReady": true]))
        expect(flow.observation.keyboardReady, "the active boot keyboard protocol is supported too")
        flow.observe(observation(["recoveryAttempt": 2]))
        expect(flow.canRecoverService, "an exhausted automatic budget still permits one explicit manual recovery")
        flow.observe(observation(["phase": "failed", "recoveryAttempt": 2]))
        expect(flow.canRecoverService, "the failed phase keeps an explicit manual recovery available")
        flow.observe(observation(["phase": "registering"]))
        expect(!flow.canRecoverService, "a new registration is allowed to finish before another manual recovery")
        flow.observe(ready)
        let preRecoveryTrial = flow.beginTest()!
        expect(flow.finishedSendingTest(preRecoveryTrial) && flow.recordPhoneTextVisible(true), "a current manual validation may exist before recovery")
        flow.serviceRecoveryRequested()
        expect(flow.verificationState == .notTested && !flow.canConfirmPhoneText,
               "an explicit manual recovery invalidates earlier confirmation without waiting for radio callbacks")
        flow.observe(observation(["phase": "recovering"]))
        expect(!flow.canRecoverService, "in-flight service recovery cannot be started twice")
        flow.observe(PairingFlow.Observation(snapshot: [
            "running": true, "authorization": "allowedAlways", "radioState": "poweredOn",
            "registeredServiceCount": 3, "requiredServiceCount": 3, "reportSubscriberCount": 1, "inputReady": true
        ], isPreview: true))
        let previewTrial = flow.beginTest()!
        expect(flow.finishedSendingTest(previewTrial), "an offline fixture may exercise trial UI")
        expect(!flow.canConfirmPhoneText && !flow.recordPhoneTextVisible(true), "a preview cannot record phone-side validation")
        expect(!flow.canOpenSystemPairing && !flow.canRecoverService, "a preview cannot operate the real Bluetooth stack")

        let suiteName = "MacPhoneKeys.PairingFlowTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        expect(ConnectionAssistantOnboarding.shouldPresent(hasExistingUse: false, defaults: defaults), "a new user sees the assistant")
        expect(!ConnectionAssistantOnboarding.shouldPresent(hasExistingUse: false, defaults: defaults), "a second launch stays quiet")
        defaults.removePersistentDomain(forName: suiteName)
        expect(!ConnectionAssistantOnboarding.shouldPresent(hasExistingUse: true, defaults: defaults), "an existing runtime log migrates quietly")
        expect(defaults.bool(forKey: ConnectionAssistantOnboarding.preferenceKey), "migration is persisted only in the supplied suite")
        defaults.removePersistentDomain(forName: suiteName)
        ConnectionAssistantOnboarding.markSeen(defaults: defaults)
        expect(!ConnectionAssistantOnboarding.shouldPresent(hasExistingUse: false, defaults: defaults), "manually opening the assistant marks it seen")
        print("PASS: \(checks) connection evidence, manual validation, cancellation, and onboarding checks")
    }
}
