import AppKit

@main enum SystemPairingAssistantTests {
    private final class Fixture {
        var resolverCalls = 0
        var available = true
        var openedURLs: [URL] = []
        var completions: [(Bool) -> Void] = []
        var deadlines: [TimeInterval] = []
        var timeouts: [() -> Void] = []
        var cancelled: Set<Int> = []

        func make() -> SystemPairingAssistant {
            SystemPairingAssistant(resolveApplication: {
                self.resolverCalls += 1
                return self.available ? SystemPairingAssistant.applicationURL : nil
            }, openApplication: { url, completion in
                self.openedURLs.append(url)
                self.completions.append(completion)
            }, scheduleTimeout: { seconds, action in
                let id = self.timeouts.count
                self.deadlines.append(seconds)
                self.timeouts.append(action)
                return { self.cancelled.insert(id) }
            })
        }
    }

    static func main() {
        var checks = 0
        func expect(_ value: Bool, _ message: String) {
            checks += 1
            guard value else { fatalError(message) }
        }
        let fixture = Fixture()
        let launcher = fixture.make()
        var changeStates: [SystemPairingAssistant.State] = []
        launcher.onChange = {
            expect(Thread.isMainThread, "UI changes must be delivered on the main thread")
            changeStates.append(launcher.state)
        }
        expect(launcher.state == .notRequested && launcher.canLaunch, "initial state does not start the helper")
        expect(!launcher.launch(buildVariant: "direct", isPreview: false, keyboardReady: true),
               "a ready input connection blocks the helper")
        expect(fixture.resolverCalls == 0 && launcher.state == .notRequested, "connected state has no side effects")
        launcher.launch(buildVariant: "direct", isPreview: true, keyboardReady: false)
        expect(launcher.state == .previewBlocked && fixture.resolverCalls == 0, "previews never resolve or open the helper")
        launcher.launch(buildVariant: "appstore", isPreview: false, keyboardReady: false)
        expect(launcher.state == .unsupportedForStore && fixture.resolverCalls == 0, "store variant has an explicit policy result")
        launcher.launch(buildVariant: "unknown", isPreview: false, keyboardReady: false)
        expect(launcher.state == .unavailable && fixture.resolverCalls == 0, "unknown build variants fail closed")

        fixture.available = false
        launcher.launch(buildVariant: "direct", isPreview: false, keyboardReady: false)
        expect(launcher.state == .unavailable && fixture.openedURLs.isEmpty, "missing or untrusted helper does not launch")
        fixture.available = true
        expect(launcher.launch(buildVariant: "direct", isPreview: false, keyboardReady: false), "explicit retry may launch")
        expect(launcher.state == .launching && !launcher.canLaunch, "pending launch blocks duplicate requests")
        expect(fixture.deadlines == [10] && fixture.openedURLs.count == 1, "one launch has a bounded confirmation deadline")
        expect(!launcher.launch(buildVariant: "direct", isPreview: false, keyboardReady: false)
            && fixture.openedURLs.count == 1, "double click does not open a second helper")
        fixture.completions[0](true)
        expect(launcher.state == .launched && fixture.cancelled.contains(0), "launch confirmation cancels its timeout")
        fixture.timeouts[0]()
        fixture.completions[0](false)
        expect(launcher.state == .launched, "late timer or duplicate callback cannot revoke launch confirmation")
        expect(!launcher.diagnosticSnapshot.keys.contains("keyboardReady"), "launching never claims transport readiness")

        launcher.launch(buildVariant: "direct", isPreview: false, keyboardReady: false)
        expect(fixture.openedURLs.count == 2, "an explicit launch after success can reopen a helper that exited")
        fixture.completions[1](false)
        expect(launcher.state == .failed && launcher.canLaunch, "launch failure keeps an explicit retry available")
        launcher.launch(buildVariant: "direct", isPreview: false, keyboardReady: false)
        fixture.completions[1](true)
        expect(launcher.state == .launching, "stale completion cannot finish a newer launch")
        fixture.timeouts[2]()
        expect(launcher.state == .confirmationTimedOut && launcher.canLaunch && fixture.cancelled.contains(2),
               "missing callback becomes unconfirmed rather than pairing success")
        fixture.completions[2](true)
        expect(launcher.state == .confirmationTimedOut, "late completion cannot rewrite a timed-out attempt")
        launcher.launch(buildVariant: "direct", isPreview: false, keyboardReady: false)
        fixture.timeouts[2]()
        expect(launcher.state == .launching, "old timeout cannot finish a new attempt")
        fixture.completions[3](true)
        let diagnostic = launcher.diagnosticSnapshot
        expect(diagnostic["state"] as? String == "launched" && diagnostic["scope"] as? String == "appSession"
            && diagnostic["launchAttemptCount"] as? Int == 4, "diagnostics declare result and counter scope")
        expect(Set(diagnostic.keys) == Set(["state", "scope", "launchAttemptCount"]),
               "diagnostics contain no paths, raw errors, device IDs, or pairing codes")

        let url = SystemPairingAssistant.applicationURL
        func trusted(_ candidate: URL = url, _ resolved: URL = url, _ identifier: String? = SystemPairingAssistant.applicationBundleIdentifier,
                     _ owner: UInt32? = 0, _ directory: Bool = true) -> Bool {
            SystemPairingAssistant.isTrustedApplication(url: candidate, resolvedURL: resolved,
                bundleIdentifier: identifier, ownerID: owner, isDirectory: directory)
        }
        expect(trusted(), "fixed OS directory and identifier are eligible")
        let userURL = URL(fileURLWithPath: "/Applications/BluetoothSetupAssistant.app")
        expect(!trusted(userURL, userURL), "a bundle-ID shadow outside System is rejected")
        expect(!trusted(url, userURL), "a symlink out of the system helper location is rejected")
        expect(!trusted(url, url, "example.wrong"), "a mismatched bundle identifier is rejected")
        expect(!trusted(url, url, nil), "a missing bundle identifier is rejected")
        expect(!trusted(url, url, SystemPairingAssistant.applicationBundleIdentifier, 501), "non-root-owned helper is rejected")
        expect(!trusted(url, url, SystemPairingAssistant.applicationBundleIdentifier, nil), "unknown owner is rejected")
        expect(!trusted(url, url, SystemPairingAssistant.applicationBundleIdentifier, 0, false), "non-directory helper is rejected")

        let immediateFixture = Fixture()
        var wasCancelled = false
        let immediate = SystemPairingAssistant(resolveApplication: { url }, openApplication: { _, _ in
            immediateFixture.openedURLs.append(url)
        }, scheduleTimeout: { _, callback in callback(); return { wasCancelled = true } })
        immediate.launch(buildVariant: "direct", isPreview: false, keyboardReady: false)
        expect(immediate.state == .confirmationTimedOut && wasCancelled && immediateFixture.openedURLs.isEmpty,
               "an immediately expired attempt cannot launch afterward")

        let releasedFixture = Fixture()
        var released: SystemPairingAssistant? = releasedFixture.make()
        released?.launch(buildVariant: "direct", isPreview: false, keyboardReady: false)
        released = nil
        expect(releasedFixture.cancelled.contains(0), "deinit cancels pending confirmation work")
        releasedFixture.completions[0](true)
        releasedFixture.timeouts[0]()

        let backgroundFixture = Fixture()
        let background = backgroundFixture.make()
        var deliveredOnMain = false
        background.onChange = {
            if background.state == .launched { deliveredOnMain = Thread.isMainThread }
        }
        background.launch(buildVariant: "direct", isPreview: false, keyboardReady: false)
        let callback = backgroundFixture.completions[0]
        DispatchQueue.global().async { callback(true) }
        let limit = Date().addingTimeInterval(1)
        while !deliveredOnMain && Date() < limit {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        expect(deliveredOnMain, "even a background opener callback is delivered to the main thread")
        expect(!changeStates.isEmpty, "explicit requests publish UI state changes")
        print("PASS: \(checks) bounded system pairing assistant and no-side-effect checks")
    }
}
