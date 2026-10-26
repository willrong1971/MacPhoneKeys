import AppKit

/// A key window keeps input local to this app. No global keyboard monitor is used.
private final class CapturePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class MenuBarController: NSObject, NSMenuDelegate {
    weak var controller: AppDelegate?
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    let panel: NSPanel
    let surface = KeyboardSurface()
    private let menu = NSMenu()
    private var previousApplication: NSRunningApplication?
    var previousApplicationPID: pid_t? { previousApplication?.processIdentifier }
    private var toggleItem: NSMenuItem!
    private var connectionItem: NSMenuItem!
    private var shortcutItem: NSMenuItem!
    var shortcutAvailable = false

    init(controller: AppDelegate) {
        self.controller = controller
        panel = CapturePanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 104),
                             styleMask: [.borderless], backing: .buffered, defer: false)
        super.init()
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.title = L("手机输入")
        panel.delegate = controller
        surface.controller = controller
        surface.isCompact = true
        surface.setAccessibilityLabel(L("手机输入"))
        panel.contentView = surface
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(clicked(_:))
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
            button.setAccessibilityLabel(L("手机键盘"))
        }
        menu.delegate = self
        menu.autoenablesItems = false
        connectionItem = menu.addItem(withTitle: "", action: nil, keyEquivalent: "")
        connectionItem.isEnabled = false
        toggleItem = menu.addItem(withTitle: L("开始手机输入"), action: #selector(toggle), keyEquivalent: "k")
        toggleItem.keyEquivalentModifierMask = [.control, .option]
        toggleItem.target = self
        shortcutItem = menu.addItem(withTitle: "", action: nil, keyEquivalent: "")
        shortcutItem.isEnabled = false
        menu.addItem(.separator())
        addItem(L("完整设置…"), #selector(showSettings))
        addItem(L("连接与使用说明"), #selector(showHelp))
        addItem(L("关于手机键盘"), #selector(showAbout))
        menu.addItem(.separator())
        addItem(L("退出手机键盘"), #selector(quit))
        update()
    }

    private func addItem(_ title: String, _ action: Selector) {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
        item.target = self
    }

    func update() {
        guard let controller else { return }
        let active = controller.capturing
        let state = active ? L("正在向 iPhone 输入") : L("本机输入")
        let image = NSImage(systemSymbolName: active ? "iphone.circle.fill" : "iphone.circle", accessibilityDescription: state)
        image?.isTemplate = true
        statusItem.button?.image = image
        // Keep the inactive outline visible in both light and dark menu bars.
        statusItem.button?.alphaValue = active ? 1 : 0.5
        statusItem.button?.setAccessibilityValue(state)
        statusItem.button?.toolTip = LF("%@ · 点击切换 · ⌃⌥K · 右键打开完整设置", state)
        toggleItem.title = active || controller.captureActivation.pending != nil ? L("停止手机输入") : L("开始手机输入")
        toggleItem.isEnabled = controller.isConnected && !controller.isTesting
        connectionItem.title = controller.isLocalizationPreview ? L("界面预览，不向手机发送")
            : controller.isConnected ? L("iPhone 已连接") : L("iPhone 未连接，请打开完整设置")
        shortcutItem.title = shortcutAvailable ? L("快捷键：⌃⌥K") : L("快捷键不可用，请关闭占用它的其他 App 后重开")
        surface.needsDisplay = true
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseDown || event?.modifierFlags.contains(.control) == true {
            // Attach only while tracking; a permanently attached menu prevents
            // the button's ordinary left-click action from being delivered.
            controller?.cancelTest()
            controller?.endCapture()
            update()
            statusItem.menu = menu
            sender.performClick(nil)
        } else {
            controller?.toggleMenuBarCapture()
        }
    }

    func menuDidClose(_ menu: NSMenu) { statusItem.menu = nil }
    @objc private func toggle() {
        // Let menu tracking finish before asking the panel to take focus.
        DispatchQueue.main.async { [weak self] in self?.controller?.toggleMenuBarCapture() }
    }
    @objc private func showSettings() { controller?.showSettings() }
    @objc private func showHelp() { controller?.showHelp() }
    @objc private func showAbout() { controller?.showAbout() }
    @objc private func quit() { NSApp.terminate(nil) }

    func showCapturePanel() {
        previousApplication = NSWorkspace.shared.frontmostApplication
        if previousApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier { previousApplication = nil }
        if let button = statusItem.button, let buttonWindow = button.window {
            let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
            let screen = buttonWindow.screen ?? NSScreen.main
            let visible = screen?.visibleFrame ?? anchor
            let x = min(max(anchor.midX - panel.frame.width / 2, visible.minX + 8), visible.maxX - panel.frame.width - 8)
            panel.setFrameOrigin(NSPoint(x: x, y: anchor.minY - panel.frame.height - 8))
        } else { panel.center() }
        NSApp.unhideWithoutActivation()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Called after activation, not as a synchronous assertion that activate()
    /// has completed. The full settings window is never needed for capture.
    func focusCapturePanel() {
        guard NSApp.isActive, panel.isVisible else { return }
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(surface)
    }

    func hideCapturePanel(restoreFocus: Bool) {
        let previous = previousApplication
        let shouldRestore = restoreFocus && NSApp.isActive
        previousApplication = nil
        panel.orderOut(nil)
        if shouldRestore, let previous, !previous.isTerminated {
            previous.activate(options: [.activateIgnoringOtherApps])
        }
    }

    func remove() {
        panel.orderOut(nil)
        NSStatusBar.system.removeStatusItem(statusItem)
    }
}
