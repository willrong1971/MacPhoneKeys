import AppKit
import Carbon

/// One registered shortcut, not a global keyboard-event monitor. Register on the
/// main thread, and keep this object alive for as long as the shortcut is needed.
/// Carbon registration does not require Accessibility or Input Monitoring access.
final class GlobalHotKey {
    static let defaultKeyCode = UInt32(kVK_ANSI_K)
    static let defaultModifiers = UInt32(controlKey | optionKey)

    enum RegistrationError: Error, LocalizedError {
        case requiresMainThread
        case shortcutAlreadyInUse
        case invalidShortcut
        case eventHandlerFailed(OSStatus)
        case registrationFailed(OSStatus)

        var errorDescription: String? {
            switch self {
            case .requiresMainThread:
                return L("请在主线程注册快捷键。")
            case .shortcutAlreadyInUse:
                return L("此快捷键已被其他 App 或系统占用。")
            case .invalidShortcut:
                return L("系统不接受此按键与修饰键组合。")
            case .eventHandlerFailed(let status):
                return LF("无法安装系统快捷键处理器（OSStatus %d）。", status)
            case .registrationFailed(let status):
                return LF("无法注册全局快捷键（OSStatus %d）。", status)
            }
        }
    }

    /// Set/read this callback on the main thread. Delivery is always asynchronous
    /// on the main queue, and queued callbacks are invalidated by unregister().
    var onPress: (() -> Void)?
    var isRegistered: Bool { registration != nil }

    private let keyCode: UInt32
    private let modifiers: UInt32
    private var registration: Registration?
    private static var nextID: UInt32 = 0 // Mutated only by main-thread register().

    init(keyCode: UInt32 = GlobalHotKey.defaultKeyCode,
         modifiers: UInt32 = GlobalHotKey.defaultModifiers,
         onPress: (() -> Void)? = nil) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.onPress = onPress
    }

    deinit { unregister() }

    /// Idempotent for an already registered instance. Exclusive registration
    /// detects conflicts instead of silently sharing the same chord with an app.
    func register() throws {
        guard Thread.isMainThread else { throw RegistrationError.requiresMainThread }
        guard registration == nil else { return }
        Self.nextID &+= 1
        if Self.nextID == 0 { Self.nextID = 1 }
        let identifier = EventHotKeyID(signature: 0x4D504B59, id: Self.nextID) // MPKY
        let context = CallbackContext(identifier: identifier) { [weak self] in self?.onPress?() }
        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        var eventHandler: EventHandlerRef?
        let handlerStatus = eventTypes.withUnsafeMutableBufferPointer { buffer in
            InstallEventHandler(GetApplicationEventTarget(), Self.carbonCallback,
                                buffer.count, buffer.baseAddress,
                                Unmanaged.passUnretained(context).toOpaque(), &eventHandler)
        }
        guard handlerStatus == noErr, let eventHandler else {
            context.invalidate()
            if let eventHandler { RemoveEventHandler(eventHandler) }
            throw RegistrationError.eventHandlerFailed(handlerStatus == noErr ? OSStatus(eventInternalErr) : handlerStatus)
        }
        var hotKey: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, identifier, GetApplicationEventTarget(),
                                        OptionBits(kEventHotKeyExclusive), &hotKey)
        guard status == noErr, let hotKey else {
            context.invalidate()
            if let hotKey { UnregisterEventHotKey(hotKey) }
            RemoveEventHandler(eventHandler)
            if status == OSStatus(eventHotKeyExistsErr) { throw RegistrationError.shortcutAlreadyInUse }
            if status == OSStatus(eventHotKeyInvalidErr) || status == OSStatus(paramErr) {
                throw RegistrationError.invalidShortcut
            }
            throw RegistrationError.registrationFailed(status == noErr ? OSStatus(eventInternalErr) : status)
        }
        registration = Registration(hotKey: hotKey, handler: eventHandler, context: context)
    }

    /// Normal UI use is main-thread only. A background-thread deinit also works:
    /// it first disables callbacks, then retains the context until main-thread
    /// Carbon cleanup completes. No synchronous dispatch or deadlock is needed.
    func unregister() {
        let previous = registration
        registration = nil
        previous?.dispose()
    }

    private static let carbonCallback: EventHandlerUPP = { _, event, userData in
        guard let event, let userData else { return OSStatus(eventNotHandledErr) }
        var identifier = EventHotKeyID()
        let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                       EventParamType(typeEventHotKeyID), nil,
                                       MemoryLayout<EventHotKeyID>.size, nil, &identifier)
        guard status == noErr else { return status }
        let context = Unmanaged<CallbackContext>.fromOpaque(userData).takeUnretainedValue()
        guard identifier.signature == context.identifier.signature,
              identifier.id == context.identifier.id else { return OSStatus(eventNotHandledErr) }
        return context.handle(kind: GetEventKind(event))
    }

    private final class CallbackContext {
        let identifier: EventHotKeyID
        private let action: () -> Void
        private let lock = NSLock()
        private var active = true
        private var held = false

        init(identifier: EventHotKeyID, action: @escaping () -> Void) {
            self.identifier = identifier
            self.action = action
        }

        func invalidate() {
            lock.lock()
            active = false
            held = false
            lock.unlock()
        }

        func handle(kind: UInt32) -> OSStatus {
            lock.lock()
            guard active else { lock.unlock(); return OSStatus(eventNotHandledErr) }
            if kind == UInt32(kEventHotKeyReleased) {
                held = false
                lock.unlock()
                return noErr
            }
            guard kind == UInt32(kEventHotKeyPressed) else {
                lock.unlock()
                return OSStatus(eventNotHandledErr)
            }
            let shouldDeliver = !held
            held = true
            lock.unlock()
            if shouldDeliver {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.lock.lock()
                    let stillActive = self.active
                    self.lock.unlock()
                    if stillActive { self.action() }
                }
            }
            return noErr
        }
    }

    private final class Registration {
        private let hotKey: EventHotKeyRef
        private let handler: EventHandlerRef
        private let context: CallbackContext

        init(hotKey: EventHotKeyRef, handler: EventHandlerRef, context: CallbackContext) {
            self.hotKey = hotKey
            self.handler = handler
            self.context = context
        }

        func dispose() {
            context.invalidate()
            let hotKey = self.hotKey
            let handler = self.handler
            let context = self.context
            let cleanup = {
                withExtendedLifetime(context) {
                    UnregisterEventHotKey(hotKey)
                    RemoveEventHandler(handler)
                }
            }
            if Thread.isMainThread { cleanup() }
            else { DispatchQueue.main.async(execute: cleanup) }
        }
    }
}
