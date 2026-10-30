import AppKit

enum SingleInstanceCoordinator {
    static var runningInstanceCount: Int {
        guard let identifier = Bundle.main.bundleIdentifier else { return 1 }
        return NSRunningApplication.runningApplications(withBundleIdentifier: identifier).filter { !$0.isTerminated }.count
    }

    /// Reopening another copy must not create a second HID service or steal its hotkey.
    static func focusExistingInstanceIfNeeded() -> Bool {
        guard let identifier = Bundle.main.bundleIdentifier else { return false }
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let instances = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .filter { !$0.isTerminated }
            .sorted {
                let left = $0.launchDate ?? .distantPast
                let right = $1.launchDate ?? .distantPast
                return left == right ? $0.processIdentifier < $1.processIdentifier : left < right
            }
        guard let existing = instances.first, existing.processIdentifier != currentPID else { return false }
        existing.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        return true
    }
}
