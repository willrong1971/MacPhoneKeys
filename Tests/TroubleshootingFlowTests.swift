import Foundation

@main enum TroubleshootingFlowTests {
    static func main() {
        var checks = 0
        func expect(_ value: Bool, _ message: String) {
            checks += 1
            guard value else { fatalError(message) }
        }
        var ready = TroubleshootingFlow.Evidence(running: true, permissionAllowed: true,
            radioOn: true, servicesReady: true, phase: "ready", keyboardReady: false, verification: "notTested",
            generation: "first")
        var flow = TroubleshootingFlow()
        flow.begin(.firstConnection)
        expect(flow.displayedStep == .checkMac && flow.primaryAction == .startService, "local prerequisites take priority")
        flow.observe(ready)
        expect(flow.step == .openMacPairing && !flow.canGoNext, "first pairing requires the Mac entry before phone instructions")
        expect(flow.recordAction(.openSystemPairing), "the user may request the public pairing entry")
        flow.goNext()
        expect(flow.step == .findMac, "requesting the Mac entry permits phone instructions without claiming pairing")
        flow.goNext()
        expect(flow.step == .waitForKeyboard && !flow.canGoNext, "Next never establishes an input subscription")
        flow.stillNotWorking()
        expect(flow.step == .systemSupport, "pairing failure goes to system guidance, not blind service resets")
        flow.recordAction(.systemSupport); flow.goNext(); flow.goNext(); flow.stillNotWorking()
        expect(flow.step == .exportDiagnostics && flow.exitReason == .stepsExhausted,
               "a repeated pairing failure terminates with an unverified exhausted-plan reason")
        expect(!flow.recordAction(.recoverService), "an export endpoint never retries in the background")

        flow.begin(.macNotVisible)
        expect(flow.step == .findMac, "the invisible-device branch starts with discoverability instructions")
        flow.stillNotWorking()
        expect(flow.step == .recoverService, "one explicit app service recovery may be offered")
        expect(flow.recordAction(.recoverService) && flow.recoveryUsed, "recovery executes only after an explicit action")
        expect(flow.step == .waitAfterRecovery, "recovery waits for a new subscription")
        for _ in 0..<10 { flow.observe(ready) }
        expect(flow.step == .waitAfterRecovery && flow.primaryAction == .none, "passive observations never create retry loops")
        flow.recoveryStillFailed()
        expect(flow.step == .systemSupport, "a failed app recovery offers one manual phone/system check")
        flow.recordAction(.systemSupport); flow.stillNotWorking()
        expect(flow.step == .exportDiagnostics, "a failed system/phone check reaches the diagnostic endpoint")
        flow.goBack()
        expect(flow.recoveryUsed && !flow.recordAction(.recoverService), "Back cannot replay or reset the recovery budget")

        ready.keyboardReady = true
        ready.verification = "visibleByUser"
        ready.verificationAttemptID = UUID()
        flow.observe(ready)
        flow.begin(.connectedNoText)
        flow.observe(ready)
        expect(flow.step == .testPhoneText && flow.symptom == .connectedNoText, "a live subscription and old confirmation do not erase the no-text symptom")
        flow.recordAction(.sendTest)
        flow.observe(ready)
        expect(flow.step == .testPhoneText, "requesting a test alert cannot reuse an old confirmation")
        ready.verificationAttemptID = UUID()
        ready.verification = "sending"; flow.observe(ready)
        ready.verification = "awaitingUser"; flow.observe(ready)
        expect(flow.step == .testPhoneText, "queued reports are not successful phone delivery")
        ready.verification = "notVisibleByUser"; flow.observe(ready); flow.phoneTextReportedMissing()
        expect(flow.step == .recoverService && flow.symptom == .connectedNoText, "user-reported missing text is preserved despite a live channel")
        flow.recordAction(.recoverService)
        flow.observe(ready)
        expect(flow.step == .waitAfterRecovery && !flow.canGoNext,
               "an unchanged old ready snapshot cannot complete recovery")
        ready.keyboardReady = false; ready.verification = "notTested"; flow.observe(ready)
        ready.keyboardReady = true; flow.observe(ready)
        expect(flow.step == .waitAfterRecovery, "a temporary unsubscribe on the old generation cannot complete recovery")
        ready.generation = "after-recovery"; flow.observe(ready)
        expect(flow.step == .testPhoneText && flow.symptom == .connectedNoText, "a restored channel advances to text verification, not success")
        flow.recordAction(.sendTest)
        ready.verificationAttemptID = UUID()
        ready.verification = "awaitingUser"; flow.observe(ready)
        ready.verification = "visibleByUser"; flow.observe(ready)
        expect(flow.step == .finished && flow.exitReason == .completedVerified,
               "only a current completed trial and user confirmation finish the guide")
        ready.keyboardReady = false; flow.observe(ready)
        expect(flow.step == .waitForKeyboard && flow.exitReason == nil,
               "a new disconnection invalidates the completed connection and verified exit reason")

        var stale = TroubleshootingFlow()
        ready.keyboardReady = true; ready.verification = "awaitingUser"; ready.verificationAttemptID = UUID()
        stale.observe(ready); stale.begin(.connectedNoText); stale.recordAction(.sendTest)
        stale.observe(ready)
        ready.verification = "visibleByUser"; stale.observe(ready)
        expect(stale.step == .testPhoneText && !stale.sawCurrentTest,
               "an old pending trial confirmed while the new test alert is open cannot finish the guide")
        ready.verificationAttemptID = UUID(); ready.verification = "awaitingUser"; stale.observe(ready)
        let currentTrial = ready.verificationAttemptID
        ready.verificationAttemptID = UUID(); ready.verification = "visibleByUser"; stale.observe(ready)
        expect(stale.step == .testPhoneText, "a different trial ID cannot confirm the observed current trial")
        ready.verificationAttemptID = currentTrial; stale.observe(ready)
        expect(stale.step == .finished, "the observed new trial and same-ID user confirmation finish normally")

        flow.begin(.pairingFailed)
        ready.permissionAllowed = false; flow.observe(ready)
        expect(flow.displayedStep == .checkMac && flow.primaryAction == .openBluetoothSettings, "permission failure blocks pairing instructions")
        expect(!flow.recordAction(.openSystemPairing), "blocked prerequisites cannot launch pairing")
        ready.permissionAllowed = true; ready.phase = "registering"; ready.servicesReady = false; flow.observe(ready)
        expect(flow.primaryAction == .none, "registration-in-progress is observed without a retry action")
        ready.phase = "failed"; flow.observe(ready)
        expect(flow.primaryAction == .recoverService, "a concrete local service failure offers an explicit repair")
        let report = flow.diagnosticSnapshot
        expect(Set(report.keys) == Set(["scope", "symptom", "step", "serviceRecoveryUsed", "pairingRequested", "supportRequested"]),
               "active diagnostic state contains fixed enums and scoped action-request flags")
        expect(report["scope"] as? String == "currentGuide", "guide action flags explicitly describe only the current plan")

        let disconnected = TroubleshootingFlow.Evidence(running: true, permissionAllowed: true,
            radioOn: true, servicesReady: true, phase: "ready", keyboardReady: false,
            verification: "notTested", generation: "current")
        var skipped = TroubleshootingFlow()
        skipped.observe(disconnected); skipped.begin(.pairingFailed)
        expect(!skipped.canReportStillFailing && !skipped.canGoNext,
               "the pairing entry cannot be reported attempted before requesting it")
        skipped.stillNotWorking(); skipped.stillNotWorking()
        expect(skipped.step == .openMacPairing && !skipped.pairingRequested && skipped.exitReason == nil,
               "two failure clicks cannot bypass an unrequested pairing entry and reach export")
        skipped.recordAction(.openSystemPairing); skipped.observe(disconnected)
        expect(skipped.step == .openMacPairing && skipped.canReportStillFailing && skipped.exitReason == nil,
               "requesting or launching a pairing helper does not create an input channel or verify success")
        skipped.stillNotWorking()
        expect(skipped.step == .systemSupport && !skipped.canReportStillFailing && !skipped.canGoNext,
               "system support also requires its own explicit action request")
        skipped.stillNotWorking()
        expect(skipped.step == .systemSupport, "failure feedback cannot silently skip the system-support action")
        expect(skipped.canReportUnableToPerformStep, "a blocked user may explicitly report an action they cannot perform")
        skipped.unableToPerformStep()
        expect(skipped.step == .exportDiagnostics && skipped.exitReason == .unableToPerform
               && skipped.skippedStep == .systemSupport && !skipped.supportRequested,
               "an explicit skip preserves the missing step without fabricating an action")
        let skippedReport = skipped.diagnosticSnapshot
        expect(skippedReport["exitReason"] as? String == "unableToPerform"
               && skippedReport["skippedStep"] as? String == "systemSupport"
               && skippedReport["pairingRequested"] as? Bool == true
               && skippedReport["supportRequested"] as? Bool == false,
               "export distinguishes requested pairing from unperformed support")
        skipped.finishWithDiagnostics()
        expect(skipped.exitReason == .unableToPerform && !skipped.canReportUnableToPerformStep,
               "opening the save sheet does not overwrite an explicit skipped-step outcome")
        skipped.goBack()
        expect(skipped.step == .systemSupport && skipped.exitReason == nil && skipped.skippedStep == nil,
               "returning from an ended plan clears its terminal outcome without replaying actions")
        skipped.recordAction(.systemSupport); skipped.stillNotWorking()
        expect(skipped.exitReason == .stepsExhausted && skipped.supportRequested,
               "requested support followed by failure is distinguished from an unperformed step")
        skipped.begin(.pairingFailed)
        expect(skipped.exitReason == nil && skipped.skippedStep == nil && !skipped.pairingRequested
               && !skipped.supportRequested && !skipped.recoveryUsed,
               "starting a fresh plan resets only its own action history and exit evidence")

        var early = TroubleshootingFlow()
        early.observe(disconnected); early.begin(.pairingFailed); early.finishWithDiagnostics()
        expect(early.step == .exportDiagnostics && early.exitReason == .requestedEarly
               && !early.pairingRequested && !early.supportRequested,
               "export is available before any action and truthfully records an early exit")
        var live = disconnected
        live.keyboardReady = true; live.verification = "visibleByUser"; live.verificationAttemptID = UUID()
        early.observe(live)
        expect(early.step == .exportDiagnostics && early.exitReason == .requestedEarly,
               "cancelling or leaving the save sheet cannot convert an early exit into verified success")

        var support = TroubleshootingFlow()
        support.observe(disconnected); support.begin(.pairingFailed)
        support.recordAction(.openSystemPairing); support.stillNotWorking()
        support.recordAction(.systemSupport); support.observe(live)
        expect(support.step == .testPhoneText && support.exitReason == nil,
               "a keyboard channel established during system support advances only to a fresh text test")
        expect(!support.canReportStillFailing, "a text-test step cannot be reported attempted before a test request")
        support.recordAction(.sendTest)
        expect(support.canReportStillFailing, "requesting a test permits failure feedback but does not assert delivery")
        live.verification = "awaitingUser"; live.verificationAttemptID = UUID(); support.observe(live)
        live.radioOn = false; live.verification = "visibleByUser"; support.observe(live)
        expect(support.displayedStep == .checkMac && support.exitReason == nil
               && !support.allowsConfirmation(attemptID: live.verificationAttemptID),
               "a contradictory ready flag cannot confirm text while the radio is unavailable")
        expect(!support.canReportStillFailing && support.canReportUnableToPerformStep,
               "an unattempted prerequisite repair offers an explicit unable path instead of attempted feedback")
        support.recordAction(.openBluetoothSettings)
        expect(support.canReportStillFailing, "requesting the prerequisite action enables truthful attempted feedback")

        var repair = TroubleshootingFlow()
        repair.observe(disconnected); repair.begin(.macNotVisible); repair.stillNotWorking()
        expect(repair.step == .recoverService && !repair.canReportStillFailing,
               "an offered service repair cannot be reported attempted before its action")
        repair.recordAction(.recoverService)
        expect(repair.canReportUnableToPerformStep, "a pending recovery may be ended explicitly if the user cannot continue")
        repair.unableToPerformStep()
        expect(repair.exitReason == .unableToPerform && repair.skippedStep == .waitAfterRecovery && repair.recoveryUsed,
               "leaving a pending recovery preserves both its requested action and skipped waiting step")

        var noPlan = TroubleshootingFlow()
        noPlan.observe(disconnected)
        expect(!noPlan.canReportUnableToPerformStep, "there is no step to skip before choosing a plan")
        noPlan.finishWithDiagnostics()
        expect(noPlan.exitReason == .requestedEarly && !noPlan.canReportStillFailing,
               "diagnostics before selecting a symptom never claims an exhausted plan")
        print("PASS: \(checks) guided troubleshooting transitions and no-blind-retry checks")
    }
}
