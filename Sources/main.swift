import AppKit
import CoreBluetooth
import IOBluetooth
import IOBluetoothUI

protocol KeyboardTransport: AnyObject {
    var onLog: ((String) -> Void)? { get set }
    var onStateChange: ((Bool, String) -> Void)? { get set }
    var hostName: String { get }
    var isConnected: Bool { get }
    func start()
    func stop()
    func connect(address: String)
    func cancelPendingInput()
    @discardableResult func sendReport(modifiers: UInt8, keys: [UInt8]) -> Bool
}
extension BluetoothKeyboard: KeyboardTransport {}
extension BLEKeyboard: KeyboardTransport {}
extension KeyboardTransport {
    func cancelPendingInput() { _ = sendReport(modifiers: 0, keys: []) }
}

// A local prototype: keyboard events are accepted only while this app's capture view has focus.
// The diagnostic log records connection events and counts, never typed text or key codes.
final class KeyboardSurface: NSView {
    weak var controller: AppDelegate?
    var isCompact = false
    override var acceptsFirstResponder: Bool { true }
    override func resignFirstResponder() -> Bool {
        if controller?.captureSurface === self { controller?.endCapture() }
        return true
    }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        controller?.beginCapture(in: self)
    }
    override func keyDown(with event: NSEvent) { controller?.keyDown(event) }
    override func keyUp(with event: NSEvent) { controller?.keyUp(event) }
    override func flagsChanged(with event: NSEvent) { controller?.flagsChanged(event) }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard controller?.capturing == true, window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
        if event.keyCode == 40, event.modifierFlags.intersection([.control, .option, .command, .shift]) == [.control, .option] {
            if controller?.globalHotKey?.isRegistered != true { controller?.endCapture(restoreFocus: true) }
            return true
        }
        controller?.keyDown(event)
        return true
    }
    override func draw(_ dirtyRect: NSRect) {
        let active = controller?.capturing == true
        if isCompact {
            NSColor.windowBackgroundColor.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 14, yRadius: 14).fill()
            let style = NSMutableParagraphStyle(); style.alignment = .center
            let title = controller?.isLocalizationPreview == true ? L("界面预览，不向手机发送") : L("正在向 iPhone 输入")
            (title as NSString).draw(in: NSRect(x: 14, y: 55, width: bounds.width - 28, height: 26),
                                    withAttributes: [.font: NSFont.systemFont(ofSize: 17, weight: .semibold), .foregroundColor: NSColor.labelColor, .paragraphStyle: style])
            (L("Esc 或 ⌃⌥K 停止 · 切到其他窗口自动停止") as NSString).draw(in: NSRect(x: 10, y: 24, width: bounds.width - 20, height: 20),
                                    withAttributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: style])
            return
        }
        (active ? NSColor.controlAccentColor.withAlphaComponent(0.12) : NSColor.controlBackgroundColor).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 12, yRadius: 12).fill()
        (active ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 12, yRadius: 12)
        border.lineWidth = active ? 2 : 1
        border.stroke()
        let title = active ? L("正在将按键发送到 iPhone") : L("连接后，点这里开始输入")
        let detail = active ? L("按 Esc 停止 · 切到其他窗口会自动停止") : L("手机先打开备忘录，点一下正文输入位置")
        let style = NSMutableParagraphStyle(); style.alignment = .center
        (title as NSString).draw(in: NSRect(x: 10, y: 65, width: bounds.width - 20, height: 30),
                                 withAttributes: [.font: NSFont.systemFont(ofSize: 19, weight: .medium), .foregroundColor: NSColor.labelColor, .paragraphStyle: style])
        (detail as NSString).draw(in: NSRect(x: 10, y: 30, width: bounds.width - 20, height: 22),
                                  withAttributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: style])
    }
}

/// Isolated UI previews exercise event routing without accessing any radio.
private final class PreviewKeyboardTransport: KeyboardTransport {
    var onLog: ((String) -> Void)?
    var onStateChange: ((Bool, String) -> Void)?
    var hostName: String { "Preview" }
    var isConnected: Bool { true }
    private(set) var reportCount = 0
    private(set) var releaseCount = 0
    private(set) var heldKeyCount = 0
    private(set) var hasModifiers = false
    func start() {}
    func stop() {}
    func connect(address: String) {}
    func cancelPendingInput() {
        releaseCount += 1
        heldKeyCount = 0
        hasModifiers = false
    }
    func sendReport(modifiers: UInt8, keys: [UInt8]) -> Bool {
        reportCount += 1
        heldKeyCount = keys.filter { $0 != 0 }.count
        hasModifiers = modifiers != 0
        return true
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, CBCentralManagerDelegate {
    // UI validation uses an isolated bundle with this flag. It never starts a
    // Bluetooth manager or writes to the installed app's runtime directory.
    let isLocalizationPreview = Bundle.main.object(forInfoDictionaryKey: "MacPhoneKeysLocalizationPreview") as? Bool == true
    var transport: KeyboardTransport = BLEKeyboard(useExpandedServiceUUID: true)
    var transportMode = 2
    var transportGeneration = UUID()
    var window: NSWindow!
    var menuBar: MenuBarController!
    var globalHotKey: GlobalHotKey?
    weak var captureSurface: KeyboardSurface?
    var endingCapture = false
    var captureActivation = CaptureActivation()
    var advancingCaptureActivation = false
    var workspaceActivationObserver: NSObjectProtocol?
    var waitingForHotKeyRelease = false
    var previewHotKeyPresses = 0
    var central: CBCentralManager?
    var capturing = false
    var captureSessionID = UUID()
    var isStarted = false
    var isConnected = false
    var refreshingDevices = false
    var pressed = Set<UInt8>()
    var modifiers: UInt8 = 0
    var sentCount = 0
    var testGeneration = UUID()
    var isTesting = false
    var lastCapsLockState = false
    var status = L("尚未启动")
    var lines: [String] = []
    var surface: KeyboardSurface!
    var stateLabel: NSTextField!
    var detailLabel: NSTextField!
    var countLabel: NSTextField!
    var startButton: NSButton!
    var captureButton: NSButton!
    var testButton: NSButton!
    var languageButton: NSButton!
    var connectButton: NSButton!
    var modeButton: NSButton!
    var pairButton: NSButton!
    var instructionsLabel: NSTextField!
    var deviceRow: NSStackView!
    var devicePicker: NSPopUpButton!
    var logView: NSTextView!
    let rootURL: URL = {
        if Bundle.main.object(forInfoDictionaryKey: "MacPhoneKeysLocalizationPreview") as? Bool == true {
            return FileManager.default.temporaryDirectory.appendingPathComponent("MacPhoneKeysLocalizationPreview-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MacPhoneKeys", isDirectory: true)
    }()
    var logURL: URL { rootURL.appendingPathComponent("验证记录.log") }
    var stateURL: URL { rootURL.appendingPathComponent("连接状态.json") }

    func applicationDidFinishLaunching(_ notification: Notification) {
        try? FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        buildUI()
        if isLocalizationPreview { transport = PreviewKeyboardTransport() }
        attachTransportCallbacks()
        menuBar = MenuBarController(controller: self)
        workspaceActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let self, self.captureActivation.pending != nil,
                  let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
                  app.processIdentifier != self.menuBar.previousApplicationPID else { return }
            self.endCapture()
        }
        let shortcut = GlobalHotKey { [weak self] in
            guard let self else { return }
            if self.isLocalizationPreview { self.previewHotKeyPresses += 1 }
            self.toggleMenuBarCapture(fromHotKey: true)
        }
        globalHotKey = shortcut
        do {
            try shortcut.register()
            menuBar.shortcutAvailable = true
        } catch {
            appendLog(LF("无法注册 ⌃⌥K 快捷键（%@）；仍可点击菜单栏图标。", error.localizedDescription))
        }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? L("开发版")
        appendLog(LF("手机键盘 %@ 启动；仅记录连接事件和计数，不记录输入内容。", version))
        appendLog(LF("系统：%@", ProcessInfo.processInfo.operatingSystemVersionString))
        if isLocalizationPreview {
            status = L("界面预览：未启动蓝牙服务")
            isConnected = true
        }
        updateUI()
        if isLocalizationPreview || CommandLine.arguments.contains("--show-settings") { showSettings() }
        if !isLocalizationPreview {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.startService() }
        }
    }

    func attachTransportCallbacks() {
        let generation = transportGeneration
        transport.onLog = { [weak self] message in self?.onMain {
            guard self?.transportGeneration == generation else { return }
            self?.appendLog(message)
        } }
        transport.onStateChange = { [weak self] connected, message in
            self?.onMain {
                guard let self, self.transportGeneration == generation else { return }
                self.isConnected = connected
                if self.status != message { self.appendLog(message) }
                self.status = message
                if !connected { self.cancelTest(); self.endCapture() }
                self.updateUI()
            }
        }
    }

    func onMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }

    func label(_ text: String, size: CGFloat = 13, weight: NSFont.Weight = .regular, color: NSColor = .labelColor) -> NSTextField {
        let value = NSTextField(wrappingLabelWithString: text)
        value.font = .systemFont(ofSize: size, weight: weight)
        value.textColor = color
        value.translatesAutoresizingMaskIntoConstraints = false
        return value
    }

    func button(_ title: String, _ selector: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: selector)
        button.bezelStyle = .rounded
        return button
    }

    func buildUI() {
        let availableHeight = NSScreen.main?.visibleFrame.height ?? 900
        let contentHeight = min(760, max(620, availableHeight - 70))
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 750, height: contentHeight),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = L("手机键盘")
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 700, height: 620)
        window.center()
        window.delegate = self
        let content = NSView(); window.contentView = content
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 26),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -26),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -22)
        ])

        stack.addArrangedSubview(label(L("用 Mac 键盘给 iPhone 打字"), size: 25, weight: .semibold))
        stack.addArrangedSubview(label(L("通过蓝牙连接。无需更换 Apple ID，无需在 iPhone 安装 App。"), color: .secondaryLabelColor))
        stack.addArrangedSubview(label(L("日常点击菜单栏图标或按 ⌃⌥K；关闭此窗口后，App 继续在菜单栏运行。"), color: .secondaryLabelColor))
        stateLabel = label(L("尚未启动"), size: 17, weight: .medium)
        stack.addArrangedSubview(stateLabel)
        detailLabel = label(L("先启动服务，再打开两台设备的蓝牙设置完成配对。"), color: .secondaryLabelColor)
        stack.addArrangedSubview(detailLabel)

        startButton = button(L("启动蓝牙键盘"), #selector(toggleService))
        let bluetooth = button(L("打开 Mac 蓝牙设置"), #selector(openBluetoothSettings))
        bluetooth.isEnabled = !isLocalizationPreview
        pairButton = button(L("查找／配对 iPhone"), #selector(pairPhone))
        modeButton = button(L("低功耗蓝牙测试"), #selector(nextTransport))
        let topButtons = NSStackView(views: [startButton, bluetooth, pairButton, modeButton]); topButtons.spacing = 8
        stack.addArrangedSubview(topButtons)

        instructionsLabel = label("")
        instructionsLabel.maximumNumberOfLines = 0
        stack.addArrangedSubview(instructionsLabel)

        devicePicker = NSPopUpButton(); devicePicker.translatesAutoresizingMaskIntoConstraints = false
        devicePicker.addItem(withTitle: L("点“刷新”读取已配对的 iPhone"))
        devicePicker.setContentHuggingPriority(.defaultLow, for: .horizontal)
        connectButton = button(L("连接所选手机"), #selector(connectSelected))
        let refresh = button(L("刷新"), #selector(refreshDevices))
        refresh.isEnabled = !isLocalizationPreview
        deviceRow = NSStackView(views: [devicePicker, refresh, connectButton]); deviceRow.spacing = 8
        stack.addArrangedSubview(deviceRow)
        deviceRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        surface = KeyboardSurface(); surface.controller = self; surface.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(surface)
        surface.heightAnchor.constraint(equalToConstant: 128).isActive = true
        surface.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        captureButton = button(L("开始输入"), #selector(toggleCapture))
        testButton = button(L("发送英文测试串"), #selector(sendTest))
        languageButton = button(L("切换手机输入法"), #selector(switchPhoneLanguage))
        countLabel = label(L("已接收按键：0"), color: .secondaryLabelColor)
        let inputButtons = NSStackView(views: [captureButton, testButton, languageButton, countLabel]); inputButtons.spacing = 10
        stack.addArrangedSubview(inputButtons)
        stack.addArrangedSubview(label(L("中文使用 iPhone 的输入法。按 Esc 或切到其他窗口，即可停止输入。"), color: .secondaryLabelColor))

        let logTitle = NSStackView(views: [label(L("连接记录"), weight: .medium), button(L("打开记录文件"), #selector(openLog))]); logTitle.spacing = 12
        stack.addArrangedSubview(logTitle)
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        logView = NSTextView(); logView.isEditable = false; logView.isSelectable = true
        logView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        logView.textContainerInset = NSSize(width: 8, height: 8)
        scroll.documentView = logView
        stack.addArrangedSubview(scroll)
        scroll.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 75).isActive = true
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)

        let menu = NSMenu()
        let appMenu = NSMenuItem(); menu.addItem(appMenu)
        let submenu = NSMenu(title: L("手机键盘")); appMenu.submenu = submenu
        submenu.addItem(withTitle: L("关于手机键盘"), action: #selector(showAbout), keyEquivalent: "")
        submenu.addItem(withTitle: L("完整设置…"), action: #selector(showSettings), keyEquivalent: ",")
        submenu.addItem(.separator())
        submenu.addItem(withTitle: L("隐藏手机键盘"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = submenu.addItem(withTitle: L("隐藏其他"), action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        submenu.addItem(withTitle: L("显示全部"), action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        submenu.addItem(.separator())
        submenu.addItem(withTitle: L("退出手机键盘"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let windowMenuItem = NSMenuItem(); menu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: L("窗口")); windowMenuItem.submenu = windowMenu
        windowMenu.addItem(withTitle: L("最小化"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: L("缩放"), action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        NSApp.windowsMenu = windowMenu
        let helpMenuItem = NSMenuItem(); menu.addItem(helpMenuItem)
        let helpMenu = NSMenu(title: L("帮助")); helpMenuItem.submenu = helpMenu
        helpMenu.addItem(withTitle: L("连接与使用说明"), action: #selector(showHelp), keyEquivalent: "")
        NSApp.helpMenu = helpMenu
        NSApp.mainMenu = menu
    }

    @objc func showAbout() {
        endCapture(); cancelTest()
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: L("手机键盘"),
            .credits: NSAttributedString(string: L("用 Mac 的键盘，通过蓝牙给 iPhone 输入。\n无需更换 Apple ID。"))
        ])
    }

    @objc func showHelp() {
        cancelTest(); endCapture()
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = L("用 Mac 键盘给 iPhone 打字")
        alert.informativeText = L("1. 允许手机键盘使用蓝牙。\n2. iPhone 打开“设置 → 蓝牙”，选择这台 Mac 的名称并完成配对。\n3. 在 iPhone 的备忘录等 App 中点一下文字输入位置。\n4. 回到 Mac，点“开始输入”后打字；按 Esc 停止。\n\n中文使用 iPhone 的输入法，可点“切换手机输入法”发送切换快捷键。两个 Apple ID 无需更改。")
            + "\n\n" + L("日常使用：点击菜单栏图标或按 ⌃⌥K，切换手机输入。实心图标表示正在手机输入，灰色轮廓表示本机输入。按 Esc 或切到其他窗口也会停止。右键图标可打开完整设置。")
        alert.addButton(withTitle: L("知道了"))
        alert.runModal()
    }

    @objc func showSettings() {
        cancelTest(); endCapture()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    @objc func toggleService() {
        if isStarted {
            cancelTest()
            endCapture(); transport.stop(); isStarted = false; isConnected = false; status = L("已停止"); updateUI()
        } else { startService() }
    }

    func startService() {
        guard !isLocalizationPreview else { return }
        guard !isStarted else { return }
        if central == nil { central = CBCentralManager(delegate: self, queue: .main) }
        isStarted = true
        status = L("正在启动蓝牙键盘服务")
        updateUI()
        transport.start()
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let description: String
        switch central.state {
        case .poweredOn: description = L("蓝牙已开启")
        case .poweredOff: description = L("蓝牙未开启，请在系统设置中打开")
        case .unauthorized: description = L("蓝牙权限未允许，请在系统设置 → 隐私与安全性 → 蓝牙中允许手机键盘")
        case .unsupported: description = L("系统未提供所需蓝牙能力")
        case .resetting: description = L("系统蓝牙正在重新初始化")
        default: description = L("正在读取蓝牙状态")
        }
        appendLog(description)
        if central.state == .unauthorized || central.state == .poweredOff { status = description; updateUI() }
    }

    @objc func openBluetoothSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings")!)
    }

    @objc func nextTransport() {
        guard !isLocalizationPreview else { return }
        cancelTest(); endCapture()
        transport.stop()
        transport.onLog = nil; transport.onStateChange = nil
        isStarted = false; isConnected = false
        transportGeneration = UUID()
        transportMode = (transportMode + 1) % 3
        if transportMode == 0 { transport = BluetoothKeyboard() }
        else { transport = BLEKeyboard(useExpandedServiceUUID: transportMode == 2) }
        attachTransportCallbacks()
        appendLog(LF("切换连接方式：%@。", transportMode == 0 ? L("传统蓝牙") : transportMode == 1 ? L("低功耗蓝牙标准服务实验") : L("低功耗蓝牙完整 UUID 服务实验")))
        startService()
    }

    @objc func pairPhone() {
        guard !isLocalizationPreview else { return }
        guard transportMode == 0 else { return }
        cancelTest(); endCapture()
        if !isStarted { startService() }
        guard let picker = IOBluetoothDeviceSelectorController.deviceSelector() else {
            appendLog(L("系统配对窗口无法打开，请使用 Mac 蓝牙设置配对。"))
            return
        }
        picker.setTitle(L("选择你的 iPhone"))
        picker.setHeader(L("请在 iPhone 上打开“设置 → 蓝牙”，再选择你自己的手机。"))
        picker.setDescriptionText(L("只与选中的设备配对。请核对两端显示的配对码。"))
        picker.clearAllowedUUIDs()
        picker.setOptions(IOBluetoothServiceBrowserControllerOptions(kIOBluetoothServiceBrowserControllerOptionsAutoStartInquiry))
        guard picker.runModal() == kIOBluetoothUISuccess,
              let selected = (picker.getResults() as? [IOBluetoothDevice])?.first,
              let address = selected.addressString else { return }
        refreshDevices()
        for item in devicePicker.itemArray where item.representedObject as? String == address {
            devicePicker.select(item)
        }
        appendLog(L("系统设备选择已完成；将尝试建立所选手机的 HID 通道。"))
        transport.connect(address: address)
    }

    @objc func refreshDevices() {
        guard !isLocalizationPreview else { return }
        guard transportMode == 0, !refreshingDevices else { return }
        let previous = devicePicker.selectedItem?.representedObject as? String
        refreshingDevices = true
        DispatchQueue.global(qos: .userInitiated).async {
            let devices = ((IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []).compactMap { device -> (name: String, address: String)? in
                guard let address = device.addressString else { return nil }
                return (device.name ?? L("未命名设备"), address)
            }.sorted { $0.name < $1.name }
            DispatchQueue.main.async {
                self.refreshingDevices = false
                guard self.transportMode == 0 else { return }
                self.devicePicker.removeAllItems()
                self.devicePicker.addItem(withTitle: L("选择已配对的 iPhone"))
                for device in devices {
                    self.devicePicker.addItem(withTitle: device.name)
                    self.devicePicker.lastItem?.representedObject = device.address
                    if previous == device.address { self.devicePicker.select(self.devicePicker.lastItem) }
                }
                self.appendLog(LF("已刷新配对设备列表（%ld 台）；尚未确认手机输入。", devices.count))
            }
        }
    }

    @objc func connectSelected() {
        guard !isLocalizationPreview else { return }
        guard let address = devicePicker.selectedItem?.representedObject as? String else {
            status = L("请先完成配对，再刷新并选择 iPhone"); updateUI(); return
        }
        if !isStarted { startService() }
        cancelTest(); endCapture()
        transport.connect(address: address)
    }

    func updateUI() {
        stateLabel.stringValue = isLocalizationPreview ? status : isConnected ? L("蓝牙键盘已连接") : status.replacingOccurrences(of: L("BLE 实验："), with: "")
        stateLabel.textColor = isConnected ? .systemGreen : .labelColor
        detailLabel.stringValue = transportMode == 0
            ? LF("在 iPhone 蓝牙列表中查找：%@", transport.hostName)
            : LF("iPhone 蓝牙列表通常显示为：%@", Host.current().localizedName ?? L("这台 Mac"))
        startButton.isEnabled = !isLocalizationPreview
        modeButton.isEnabled = !isLocalizationPreview
        pairButton.isEnabled = transportMode == 0 && !isLocalizationPreview
        pairButton.isHidden = transportMode != 0
        modeButton.isHidden = !CommandLine.arguments.contains("--diagnostics")
        deviceRow.isHidden = transportMode != 0
        if transportMode == 0 {
            instructionsLabel.stringValue = L("① iPhone：设置 → 蓝牙，保持这个页面打开。\n② 在其他设备中选择这台 Mac，并核对系统显示的配对码。\n③ 若已配对，在下面选择 iPhone，点“连接所选手机”。")
            modeButton.title = L("低功耗蓝牙测试")
        } else {
            instructionsLabel.stringValue = L("① iPhone：设置 → 蓝牙，选择这台 Mac 的名称并完成配对。\n② 在手机的备忘录等 App 中，点一下要输入文字的位置。\n③ 下方“开始输入”亮起后，点它即可用 Mac 键盘打字。")
            modeButton.title = transportMode == 1 ? L("试完整 UUID 方式") : L("返回传统蓝牙")
        }
        startButton.title = isStarted ? L("停止蓝牙键盘") : L("启动蓝牙键盘")
        captureButton.isEnabled = isConnected && !isTesting
        captureButton.title = capturing || captureActivation.pending != nil ? L("停止输入（Esc）") : L("开始输入")
        testButton.isEnabled = isConnected && !capturing && !isTesting && captureActivation.pending == nil
        languageButton.isEnabled = isConnected && !isTesting && captureActivation.pending == nil
        connectButton.isEnabled = !capturing && !isTesting && captureActivation.pending == nil && !isLocalizationPreview
        countLabel.stringValue = LF("已接收按键：%ld", sentCount)
        surface.needsDisplay = true
        menuBar?.update()
        writeState()
    }

    @objc func toggleCapture() {
        toggleMenuBarCapture()
    }

    func toggleMenuBarCapture(fromHotKey: Bool = false) {
        if capturing || captureActivation.pending != nil { endCapture(restoreFocus: true); return }
        guard isConnected, !isTesting else { showSettings(); return }
        let request = captureActivation.begin(fromHotKey: fromHotKey)
        menuBar.showCapturePanel()
        advanceCaptureActivation()
        // Activation and key-window notifications may arrive on later turns.
        // The request survives those turns, but a stopped request never revives.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.captureActivation.isCurrent(request) else { return }
            self.advanceCaptureActivation()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.captureActivation.isCurrent(request) else { return }
            self.endCapture()
            self.appendLog(L("未能取得输入焦点，已取消；请重试快捷键。"))
        }
        updateUI()
    }

    func advanceCaptureActivation() {
        guard !advancingCaptureActivation, let request = captureActivation.pending,
              isConnected, !isTesting else { return }
        advancingCaptureActivation = true
        defer { advancingCaptureActivation = false }
        if NSApp.isActive { menuBar.focusCapturePanel() }
        guard let ready = captureActivation.completeIfReady(
            request, appActive: NSApp.isActive, panelKey: menuBar.panel.isKeyWindow,
            responderReady: menuBar.panel.firstResponder === menuBar.surface
        ) else { return }
        if !beginCapture(in: menuBar.surface, fromHotKey: ready.fromHotKey) {
            endCapture()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) { advanceCaptureActivation(); writeState() }
    func applicationDidResignActive(_ notification: Notification) { writeState() }
    func windowDidBecomeKey(_ notification: Notification) {
        if notification.object as? NSWindow === menuBar?.panel { advanceCaptureActivation() }
    }

    @discardableResult func beginCapture(in target: KeyboardSurface, fromHotKey: Bool = false) -> Bool {
        guard isConnected, !capturing, !isTesting else { return false }
        guard let targetWindow = target.window, targetWindow.makeFirstResponder(target),
              targetWindow.isKeyWindow, targetWindow.firstResponder === target else { return false }
        let initiatedByHotKey = fromHotKey || captureActivation.pending?.fromHotKey == true
        captureActivation.cancel()
        pressed.removeAll(); modifiers = 0
        lastCapsLockState = NSEvent.modifierFlags.contains(.capsLock)
        captureSurface = target
        captureSessionID = UUID()
        waitingForHotKeyRelease = initiatedByHotKey && !NSEvent.modifierFlags.intersection([.control, .option]).isEmpty
        capturing = true
        appendLog(L("开始前台键盘输入；Esc 或窗口失焦时停止。"))
        updateUI()
        return true
    }
    func endCapture(restoreFocus: Bool = false) {
        guard !endingCapture else { return }
        endingCapture = true
        defer { endingCapture = false }
        let wasCapturing = capturing
        let wasPending = captureActivation.pending != nil
        captureActivation.cancel()
        // Even an idle UI may still have a test or shortcut awaiting BLE capacity.
        if isConnected { transport.cancelPendingInput() }
        pressed.removeAll(); modifiers = 0; capturing = false
        captureSurface = nil
        waitingForHotKeyRelease = false
        menuBar?.hideCapturePanel(restoreFocus: restoreFocus && (wasCapturing || wasPending))
        if wasCapturing { appendLog(L("已停止键盘输入，并释放按键。")) }
        if window != nil { updateUI() }
    }

    func keyDown(_ event: NSEvent) {
        if event.keyCode == 53, captureActivation.pending != nil { endCapture(restoreFocus: true); return }
        guard acceptsKeyboardEvents else { return }
        if event.keyCode == 53 { endCapture(restoreFocus: true); return }
        if event.keyCode == 40, event.modifierFlags.intersection([.control, .option, .command, .shift]) == [.control, .option] {
            if globalHotKey?.isRegistered != true { endCapture(restoreFocus: true) }
            return
        }
        guard !waitingForHotKeyRelease else { return }
        guard let usage = KeyMapping.usage(forMacKeyCode: event.keyCode) else { return }
        // Holding a key is represented as a held HID key; the iPhone controls repeat.
        if event.isARepeat || pressed.contains(usage) { return }
        guard pressed.count < 6 else { return }
        modifiers = KeyMapping.modifierByte(rawFlags: event.modifierFlags.rawValue)
        pressed.insert(usage)
        if transport.sendReport(modifiers: modifiers, keys: pressed.sorted()) { sentCount += 1 }
        else { endCapture() }
        updateUI()
    }
    func keyUp(_ event: NSEvent) {
        guard acceptsKeyboardEvents, !waitingForHotKeyRelease else { return }
        guard let usage = KeyMapping.usage(forMacKeyCode: event.keyCode) else { return }
        pressed.remove(usage)
        modifiers = KeyMapping.modifierByte(rawFlags: event.modifierFlags.rawValue)
        if !transport.sendReport(modifiers: modifiers, keys: pressed.sorted()) { endCapture() }
    }
    func flagsChanged(_ event: NSEvent) {
        guard acceptsKeyboardEvents else { return }
        if waitingForHotKeyRelease {
            if event.modifierFlags.intersection([.control, .option]).isEmpty { waitingForHotKeyRelease = false }
            return
        }
        modifiers = KeyMapping.modifierByte(rawFlags: event.modifierFlags.rawValue)
        // Caps Lock is a HID key, not a modifier bit. One press toggles the phone's state.
        if event.keyCode == 57 {
            let state = event.modifierFlags.contains(.capsLock)
            guard state != lastCapsLockState else { return }
            lastCapsLockState = state
            guard pressed.count < 6 else { return }
            guard transport.sendReport(modifiers: modifiers, keys: pressed.union([0x39]).sorted()),
                  transport.sendReport(modifiers: modifiers, keys: pressed.sorted()) else {
                endCapture(); return
            }
        } else if !transport.sendReport(modifiers: modifiers, keys: pressed.sorted()) { endCapture() }
    }

    var acceptsKeyboardEvents: Bool {
        guard capturing, isConnected, NSApp.isActive, let target = captureSurface, let targetWindow = target.window else { return false }
        return targetWindow.isKeyWindow && targetWindow.firstResponder === target
    }

    @objc func sendTest() {
        guard isConnected, !capturing, !isTesting, captureActivation.pending == nil else { return }
        let alert = NSAlert()
        alert.messageText = L("将英文测试串输入到 iPhone")
        alert.informativeText = L("请先在 iPhone 的备忘录中点一下空白正文。此按钮会输入一行英文和数字，不会按回车。")
        alert.addButton(withTitle: L("发送测试串")); alert.addButton(withTitle: L("取消"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let strokes = "mac keyboard test 123".compactMap(KeyMapping.asciiStroke)
        appendLog(L("开始手动触发的英文测试；等待用户确认手机显示。"))
        isTesting = true
        testGeneration = UUID()
        updateUI()
        sendStrokes(strokes, index: 0, generation: testGeneration)
    }
    func sendStrokes(_ strokes: [(modifier: UInt8, usage: UInt8)], index: Int, generation: UUID) {
        guard generation == testGeneration, isTesting else { return }
        guard isConnected else { cancelTest(); updateUI(); return }
        guard index < strokes.count else {
            isTesting = false
            appendLog(L("英文测试报告已交给发送队列；尚需确认 iPhone 是否实际显示文字。"))
            updateUI(); return
        }
        let stroke = strokes[index]
        guard transport.sendReport(modifiers: stroke.modifier, keys: [stroke.usage]) else { cancelTest(); updateUI(); return }
        sentCount += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
            guard generation == self.testGeneration, self.isTesting else { return }
            guard self.isConnected else { self.cancelTest(); self.updateUI(); return }
            guard self.transport.sendReport(modifiers: 0, keys: []) else { self.cancelTest(); self.updateUI(); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { self.sendStrokes(strokes, index: index + 1, generation: generation) }
        }
    }

    func cancelTest() {
        if isTesting && isConnected { transport.cancelPendingInput() }
        isTesting = false
        testGeneration = UUID()
    }

    @objc func switchPhoneLanguage() {
        guard isConnected, !isTesting, captureActivation.pending == nil else { return }
        endCapture()
        if transport.sendReport(modifiers: 0x01, keys: [0x2C]) {
            _ = transport.sendReport(modifiers: 0, keys: [])
            appendLog(L("已接收手机输入法切换快捷键（Control + Space）。"))
        }
    }

    func appendLog(_ message: String) {
        let formatter = DateFormatter(); formatter.dateFormat = "HH:mm:ss"
        let line = "[\(formatter.string(from: Date()))] \(message)"
        lines.append(line)
        if lines.count > 300 { lines.removeFirst(lines.count - 300) }
        if logView != nil { logView.string = lines.joined(separator: "\n"); logView.scrollToEndOfDocument(nil) }
        if let data = (line + "\n").data(using: .utf8) {
            if !FileManager.default.fileExists(atPath: logURL.path) { FileManager.default.createFile(atPath: logURL.path, contents: nil) }
            if let handle = try? FileHandle(forWritingTo: logURL) {
                defer { try? handle.close() }; _ = try? handle.seekToEnd(); try? handle.write(contentsOf: data)
            }
        }
        writeState()
    }

    func writeState() {
        var state: [String: Any] = ["started": isStarted, "connected": isConnected, "capturing": capturing,
                                  "acceptedKeyPresses": sentCount, "status": status,
                                  "phoneTextVerifiedByApp": false, "transportMode": transportMode,
                                  "shortcutRegistered": globalHotKey?.isRegistered ?? false,
                                  "capturePending": captureActivation.pending != nil,
                                  "settingsVisible": window?.isVisible ?? false,
                                  "inputPanelVisible": menuBar?.panel.isVisible ?? false,
                                  "inputPanelKey": menuBar?.panel.isKeyWindow ?? false,
                                  "appActive": NSApp.isActive,
                                  "updatedAt": ISO8601DateFormatter().string(from: Date())]
        if let preview = transport as? PreviewKeyboardTransport {
            // Aggregate fixture diagnostics only; never save characters or key codes.
            state["preview"] = ["reports": preview.reportCount, "releases": preview.releaseCount,
                                "heldKeyCount": preview.heldKeyCount, "hasModifiers": preview.hasModifiers,
                                "hotKeyPresses": previewHotKeyPresses, "appActive": NSApp.isActive,
                                "panelVisible": menuBar?.panel.isVisible ?? false,
                                "panelIsKey": menuBar?.panel.isKeyWindow ?? false]
        }
        if let data = try? JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: stateURL, options: .atomic)
        }
    }

    @objc func openLog() { NSWorkspace.shared.selectFile(logURL.path, inFileViewerRootedAtPath: rootURL.path) }
    func windowDidResignKey(_ notification: Notification) {
        cancelTest()
        guard let lostWindow = notification.object as? NSWindow else { return }
        let pendingAtResign = captureActivation.pending
        let sessionAtResign = capturing ? captureSessionID : nil
        // A status-item click and a switch between our two windows may resign
        // key before their action runs. Check the final responder next turn.
        DispatchQueue.main.async { [weak self, weak lostWindow] in
            guard let self, let lostWindow, !lostWindow.isKeyWindow else { return }
            let wasCaptureWindow = sessionAtResign != nil && self.capturing && self.captureSessionID == sessionAtResign
                && self.captureSurface?.window === lostWindow
            let wasPendingPanel = pendingAtResign.map { self.captureActivation.isCurrent($0) } == true
                && self.menuBar?.panel === lostWindow
            guard wasCaptureWindow || wasPendingPanel else { return }
            self.endCapture()
        }
    }
    func applicationWillResignActive(_ notification: Notification) { cancelTest(); endCapture() }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        cancelTest(); endCapture()
        sender.orderOut(nil)
        writeState()
        return false
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) {
        if let observer = workspaceActivationObserver { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        globalHotKey?.unregister()
        menuBar?.remove()
        cancelTest(); endCapture(); transport.stop(); isStarted = false; isConnected = false; status = L("已退出"); writeState()
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
