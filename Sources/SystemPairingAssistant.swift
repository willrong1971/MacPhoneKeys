import AppKit

/// Opens Apple's optional system helper after an explicit user action. Launch
/// confirmation is not evidence of pairing, an input subscription, or delivery.
/// The helper's location is an OS implementation detail, so absence or a launch
/// error must leave the ordinary pairing/settings fallback available.
final class SystemPairingAssistant {
    enum State: String {
        case notRequested, launching, launched, unavailable, failed
        case confirmationTimedOut, unsupportedForStore, previewBlocked
    }

    typealias Resolver = () -> URL?
    typealias Opener = (URL, @escaping (Bool) -> Void) -> Void
    typealias Scheduler = (TimeInterval, @escaping () -> Void) -> (() -> Void)

    static let applicationURL = URL(fileURLWithPath: "/System/Library/CoreServices/BluetoothSetupAssistant.app",
                                    isDirectory: true)
    static let applicationBundleIdentifier = "com.apple.BluetoothSetupAssistant"
    static let confirmationTimeout: TimeInterval = 10

    private(set) var state = State.notRequested
    private(set) var launchAttemptCount = 0
    var onChange: (() -> Void)?
    var canLaunch: Bool { state != .launching }

    private let resolveApplication: Resolver
    private let openApplication: Opener
    private let scheduleTimeout: Scheduler
    private var currentAttempt: UUID?
    private var cancelTimeout: (() -> Void)?

    init(resolveApplication: @escaping Resolver = SystemPairingAssistant.resolveSystemApplication,
         openApplication: @escaping Opener = SystemPairingAssistant.openSystemApplication,
         scheduleTimeout: @escaping Scheduler = SystemPairingAssistant.scheduleOnMainQueue) {
        self.resolveApplication = resolveApplication
        self.openApplication = openApplication
        self.scheduleTimeout = scheduleTimeout
    }

    /// Call on the main thread. A true result means the request was handled;
    /// inspect state to distinguish a policy block, failure, and a pending launch.
    /// Existing input connections are never disturbed merely to show a helper.
    @discardableResult
    func launch(buildVariant: String, isPreview: Bool, keyboardReady: Bool) -> Bool {
        guard Thread.isMainThread, canLaunch, !keyboardReady else { return false }
        if isPreview { changeState(.previewBlocked); return true }
        if buildVariant == "appstore" { changeState(.unsupportedForStore); return true }
        guard buildVariant == "direct", let url = resolveApplication() else {
            changeState(.unavailable)
            return true
        }

        let attempt = UUID()
        currentAttempt = attempt
        changeState(.launching)
        let cancel = scheduleTimeout(Self.confirmationTimeout) { [weak self] in
            Self.onMain { [weak self] in self?.finish(attempt, with: .confirmationTimedOut) }
        }
        // Injectable schedulers may fire immediately. Never launch after that
        // attempt already ended, and do not retain an expired timer's canceler.
        guard currentAttempt == attempt else { cancel(); return true }
        cancelTimeout = cancel
        launchAttemptCount = min(launchAttemptCount + 1, 1_000_000_000)
        openApplication(url) { [weak self] succeeded in
            Self.onMain { [weak self] in
                self?.finish(attempt, with: succeeded ? .launched : .failed)
            }
        }
        return true
    }

    var diagnosticSnapshot: [String: Any] {
        ["state": state.rawValue, "scope": "appSession", "launchAttemptCount": launchAttemptCount]
    }

    private func finish(_ attempt: UUID, with result: State) {
        guard currentAttempt == attempt, state == .launching else { return }
        currentAttempt = nil
        cancelTimeout?()
        cancelTimeout = nil
        changeState(result)
    }

    private func changeState(_ value: State) {
        state = value
        onChange?()
    }

    private static func onMain(_ action: @escaping () -> Void) {
        if Thread.isMainThread { action() }
        else { DispatchQueue.main.async(execute: action) }
    }

    /// Only the fixed OS-owned helper is eligible. Do not use Launch Services
    /// bundle-ID lookup: a user-installed bundle could shadow that identifier.
    static func isTrustedApplication(url: URL, resolvedURL: URL, bundleIdentifier: String?,
                                     ownerID: UInt32?, isDirectory: Bool) -> Bool {
        url.standardizedFileURL.path == applicationURL.path
            && resolvedURL.standardizedFileURL.path == applicationURL.path
            && bundleIdentifier == applicationBundleIdentifier
            && ownerID == 0 && isDirectory
    }

    private static func resolveSystemApplication() -> URL? {
        let url = applicationURL
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              isTrustedApplication(url: url, resolvedURL: url.resolvingSymlinksInPath(),
                                   bundleIdentifier: Bundle(url: url)?.bundleIdentifier,
                                   ownerID: (attributes[.ownerAccountID] as? NSNumber)?.uint32Value,
                                   isDirectory: attributes[.type] as? FileAttributeType == .typeDirectory) else { return nil }
        return url
    }

    private static func openSystemApplication(_ url: URL, completion: @escaping (Bool) -> Void) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = false
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { application, error in
            completion(error == nil && application != nil)
        }
    }

    private static func scheduleOnMainQueue(after seconds: TimeInterval, action: @escaping () -> Void) -> (() -> Void) {
        let task = DispatchWorkItem(block: action)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: task)
        return { task.cancel() }
    }

    deinit { cancelTimeout?() }
}
