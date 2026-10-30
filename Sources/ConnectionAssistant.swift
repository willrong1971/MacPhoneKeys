import AppKit
import IOBluetoothUI

protocol ConnectionAssistantDelegate: AnyObject {
    func connectionAssistantNeedsRefresh()
    func connectionAssistantStartService()
    func connectionAssistantOpenBluetoothSettings()
    func connectionAssistantWillOpenSystemPairing()
    func connectionAssistantDidFinishSystemPairing(_ result: PairingFlow.SystemPanelResult, rawCode: Int32?, elapsedMilliseconds: Int)
    func connectionAssistantRecoverService()
    func connectionAssistantSendTest()
    func connectionAssistantReportPhoneText(visible: Bool)
    func connectionAssistantExportDiagnostics()
    func connectionAssistantShowFullSettings()
    func connectionAssistantDidClose()
}

private final class AssistantDocumentView: NSView {
    override var isFlipped: Bool { true }
}

/// An ordinary AppKit window. All Bluetooth work is requested through explicit
/// button actions; refreshing this window only reads aggregate diagnostics.
final class ConnectionAssistant: NSWindowController, NSWindowDelegate {
    private weak var delegate: ConnectionAssistantDelegate?
    private var refreshTimer: Timer?
    private var lastFlow = PairingFlow()
    private var pairingController: IOBluetoothPairingController?
    private let previewLabel = NSTextField(wrappingLabelWithString: "")
    private let permissionValue = NSTextField(wrappingLabelWithString: "")
    private let serviceValue = NSTextField(wrappingLabelWithString: "")
    private let advertisementValue = NSTextField(wrappingLabelWithString: "")
    private let connectionValue = NSTextField(wrappingLabelWithString: "")
    private let phoneInstructions = NSTextField(wrappingLabelWithString: "")
    private let pairingFeedback = NSTextField(wrappingLabelWithString: "")
    private let verificationValue = NSTextField(wrappingLabelWithString: "")
    private let recoveryValue = NSTextField(wrappingLabelWithString: "")
    private var startButton: NSButton!
    private var pairButton: NSButton!
    private var settingsButton: NSButton!
    private var testButton: NSButton!
    private var visibleButton: NSButton!
    private var missingButton: NSButton!
    private var recoverButton: NSButton!

    init(delegate: ConnectionAssistantDelegate) {
        self.delegate = delegate
        let height = min(760, max(580, (NSScreen.main?.visibleFrame.height ?? 900) - 90))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: height),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = L("连接 iPhone")
        window.minSize = NSSize(width: 620, height: 540)
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
        buildUI(in: window)
    }

    required init?(coder: NSCoder) { nil }

    func present() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        delegate?.connectionAssistantNeedsRefresh()
        if refreshTimer == nil {
            let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
                guard let self, self.window?.isVisible == true else { return }
                self.delegate?.connectionAssistantNeedsRefresh()
            }
            refreshTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func text(_ value: String, size: CGFloat = 13, color: NSColor = .labelColor) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: value)
        field.font = .systemFont(ofSize: size)
        field.textColor = color
        field.maximumNumberOfLines = 0
        return field
    }

    private func button(_ title: String, _ selector: Selector) -> NSButton {
        let value = NSButton(title: title, target: self, action: selector)
        value.bezelStyle = .rounded
        return value
    }

    private func row(_ views: [NSView]) -> NSStackView {
        let value = NSStackView(views: views)
        value.orientation = .horizontal
        value.alignment = .centerY
        value.spacing = 8
        return value
    }

    private func section(_ title: String, views: [NSView]) -> NSStackView {
        let heading = text(title, size: 16)
        heading.font = .systemFont(ofSize: 16, weight: .semibold)
        let value = NSStackView(views: [heading] + views)
        value.orientation = .vertical
        value.alignment = .leading
        value.spacing = 7
        for view in views {
            view.translatesAutoresizingMaskIntoConstraints = false
            view.widthAnchor.constraint(equalTo: value.widthAnchor).isActive = true
        }
        return value
    }

    private func buildUI(in window: NSWindow) {
        let content = NSView()
        window.contentView = content
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(scroll)
        let document = AssistantDocumentView()
        document.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = document
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: content.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -58),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 22),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -24)
        ])

        let title = text(L("用三步连接你的 iPhone"), size: 24)
        title.font = .systemFont(ofSize: 24, weight: .semibold)
        let intro = text(L("首次使用时完成系统配对，再确认手机上能收到文字。日后可直接使用菜单栏图标或 ⌃⌥K。"), color: .secondaryLabelColor)
        let header = NSStackView(views: [title, intro, previewLabel])
        header.orientation = .vertical; header.alignment = .leading; header.spacing = 7
        intro.widthAnchor.constraint(equalTo: header.widthAnchor).isActive = true
        previewLabel.widthAnchor.constraint(equalTo: header.widthAnchor).isActive = true
        previewLabel.font = .systemFont(ofSize: 12)
        previewLabel.textColor = .systemOrange
        stack.addArrangedSubview(header)

        startButton = button(L("启动键盘服务"), #selector(startService))
        let mac = section(L("1. 检查 Mac"), views: [
            row([text(L("蓝牙权限：")), permissionValue]),
            row([text(L("键盘服务：")), serviceValue]),
            row([text(L("蓝牙广播：")), advertisementValue]),
            row([startButton])
        ])
        stack.addArrangedSubview(mac)

        pairButton = button(L("打开系统配对窗口…"), #selector(openSystemPairing))
        settingsButton = button(L("Mac 蓝牙设置…"), #selector(openBluetoothSettings))
        let phone = section(L("2. 在手机上连接"), views: [phoneInstructions,
            row([pairButton, settingsButton]), pairingFeedback, connectionValue])
        stack.addArrangedSubview(phone)

        testButton = button(L("发送测试串…"), #selector(sendTest))
        visibleButton = button(L("手机完整显示了"), #selector(confirmVisible))
        missingButton = button(L("手机没有完整显示"), #selector(confirmMissing))
        let verify = section(L("3. 看手机确认输入"), views: [
            text(L("在 iPhone 备忘录新建空白笔记，点正文看到光标，切到英文后再发送。测试不会按回车。"), color: .secondaryLabelColor),
            row([testButton]), verificationValue, row([visibleButton, missingButton])
        ])
        stack.addArrangedSubview(verify)

        recoverButton = button(L("重新建立键盘服务"), #selector(recoverService))
        let exportButton = button(L("导出诊断报告…"), #selector(exportDiagnostics))
        let help = section(L("仍然连不上？"), views: [
            text(L("先保持两端蓝牙页面打开。可以手动重建一次本 App 的键盘服务，再重新连接。"), color: .secondaryLabelColor),
            row([recoverButton, exportButton]), recoveryValue,
            text(L("不会自动清除配对记录，也不会开关系统蓝牙。"), size: 12, color: .secondaryLabelColor)
        ])
        stack.addArrangedSubview(help)
        for child in stack.arrangedSubviews {
            child.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        let fullSettings = button(L("完整设置…"), #selector(showFullSettings))
        let done = button(L("完成"), #selector(closeAssistant))
        let footer = row([fullSettings, NSView(), done])
        footer.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(footer)
        NSLayoutConstraint.activate([
            footer.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            footer.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            footer.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14)
        ])
    }

    func render(flow: PairingFlow, macName: String) {
        lastFlow = flow
        let observation = flow.observation
        previewLabel.stringValue = observation.isPreview ? L("界面预览，不连接手机；下列状态均为测试示例。") : ""
        previewLabel.isHidden = !observation.isPreview
        switch observation.authorization {
        case "allowedAlways": permissionValue.stringValue = L("已允许")
        case "denied", "restricted": permissionValue.stringValue = L("未允许，请在系统隐私设置中允许蓝牙")
        default: permissionValue.stringValue = L("等待系统授权")
        }
        permissionValue.textColor = observation.authorization == "allowedAlways" ? .systemGreen : .secondaryLabelColor
        if !observation.running { serviceValue.stringValue = L("尚未启动") }
        else if observation.radioState == "poweredOff" { serviceValue.stringValue = L("蓝牙已关闭，请在系统设置中打开") }
        else if observation.radioState == "unsupported" { serviceValue.stringValue = L("此 Mac 未提供所需蓝牙能力") }
        else if observation.servicesReady { serviceValue.stringValue = L("必需服务已注册") }
        else if observation.phase == "failed" { serviceValue.stringValue = L("服务未就绪，请查看诊断报告") }
        else { serviceValue.stringValue = L("正在准备键盘服务") }
        serviceValue.textColor = observation.servicesReady ? .systemGreen : .secondaryLabelColor
        advertisementValue.stringValue = observation.isAdvertising ? L("正在广播，可等待手机连接")
            : observation.keyboardReady ? L("已有键盘连接") : L("当前未广播")
        advertisementValue.textColor = observation.isAdvertising || observation.keyboardReady ? .systemGreen : .secondaryLabelColor
        phoneInstructions.stringValue = LF("在 iPhone 打开“设置 → 蓝牙”，点“%@”。如果系统显示配对码，请核对两端一致后确认。", macName)
        switch flow.systemPanelResult {
        case .notOpened: pairingFeedback.stringValue = L("需要配对时打开系统窗口，只选择自己的 iPhone。已配对的手机可以直接点已有的 Mac 记录连接。")
        case .open: pairingFeedback.stringValue = L("系统配对处理中，请按系统提示操作。")
        case .cancelled: pairingFeedback.stringValue = L("已取消系统配对；键盘服务保持原状态。")
        case .selectionPaired: pairingFeedback.stringValue = L("系统面板已完成配对；仍需等待手机订阅键盘。")
        case .failed: pairingFeedback.stringValue = L("系统配对窗口未完成，请使用 Mac 蓝牙设置并检查手机提示。")
        }
        pairingFeedback.textColor = .secondaryLabelColor
        connectionValue.stringValue = observation.keyboardReady ? L("已建立加密键盘通道；下一步请确认手机文字。") : L("等待手机订阅键盘；当前还不能发送输入。")
        connectionValue.textColor = observation.keyboardReady ? .systemGreen : .secondaryLabelColor
        switch flow.verificationState {
        case .notTested: verificationValue.stringValue = L("尚未验证手机文字。连接状态和发送计数不能代替手机上的实际结果。")
        case .sending: verificationValue.stringValue = L("正在提交测试按键，请稍候。")
        case .awaitingUser: verificationValue.stringValue = L("测试按键已交给发送队列。手机是否完整显示 mac keyboard test 123？")
        case .visibleByUser: verificationValue.stringValue = L("你已确认手机完整显示测试文字。本次连接已完成人工验证。")
        case .notVisibleByUser: verificationValue.stringValue = L("你反馈手机未完整显示。请重新点手机正文、切到英文，再测试；仍无文字时可重建服务。")
        }
        verificationValue.textColor = flow.verificationState == .visibleByUser ? .systemGreen : .secondaryLabelColor
        recoveryValue.stringValue = observation.recoveryAttempt >= observation.recoveryLimit
            ? L("自动恢复已结束。可手动重建一次服务，或导出诊断报告。")
            : L("此按钮每次只请求一次手动恢复。")
        recoveryValue.textColor = .secondaryLabelColor
        startButton.isEnabled = !observation.running && !observation.isPreview
        pairButton.isEnabled = flow.canOpenSystemPairing
        settingsButton.isEnabled = !observation.isPreview
        testButton.isEnabled = flow.canSendTest
        visibleButton.isEnabled = flow.canConfirmPhoneText
        missingButton.isEnabled = flow.canConfirmPhoneText
        recoverButton.isEnabled = flow.canRecoverService
    }

    @objc private func startService() { delegate?.connectionAssistantStartService() }
    @objc private func openBluetoothSettings() { delegate?.connectionAssistantOpenBluetoothSettings() }
    @objc private func sendTest() { delegate?.connectionAssistantSendTest() }
    @objc private func confirmVisible() { delegate?.connectionAssistantReportPhoneText(visible: true) }
    @objc private func confirmMissing() { delegate?.connectionAssistantReportPhoneText(visible: false) }
    @objc private func recoverService() { delegate?.connectionAssistantRecoverService() }
    @objc private func exportDiagnostics() { delegate?.connectionAssistantExportDiagnostics() }
    @objc private func showFullSettings() { delegate?.connectionAssistantShowFullSettings() }
    @objc private func closeAssistant() { close() }

    @objc private func openSystemPairing() {
        guard lastFlow.canOpenSystemPairing, pairingController == nil else { return }
        delegate?.connectionAssistantWillOpenSystemPairing()
        let startedAt = Date()
        func elapsedMilliseconds() -> Int {
            Int(max(0, (Date().timeIntervalSince(startedAt) * 1_000).rounded()))
        }
        guard let picker = MPKCreatePairingPanelController() else {
            delegate?.connectionAssistantDidFinishSystemPairing(.failed, rawCode: nil,
                                                                 elapsedMilliseconds: elapsedMilliseconds())
            return
        }
        pairingController = picker
        picker.setTitle(L("配对你自己的 iPhone"))
        picker.setDescriptionText(L("请保持 iPhone 的“设置 → 蓝牙”页面打开。只选择自己的 iPhone，并核对两端系统显示的配对码。取消不会清除已有配对。"))
        picker.clearAllowedUUIDs()
        picker.setOptions(IOBluetoothServiceBrowserControllerOptions(kIOBluetoothServiceBrowserControllerOptionsAutoStartInquiry))
        let result = picker.runModal()
        let elapsed = elapsedMilliseconds()
        pairingController = nil
        if result == kIOBluetoothUISuccess {
            delegate?.connectionAssistantDidFinishSystemPairing(.selectionPaired, rawCode: result, elapsedMilliseconds: elapsed)
        } else if result == kIOBluetoothUIUserCanceledErr {
            delegate?.connectionAssistantDidFinishSystemPairing(.cancelled, rawCode: result, elapsedMilliseconds: elapsed)
        } else {
            delegate?.connectionAssistantDidFinishSystemPairing(.failed, rawCode: result, elapsedMilliseconds: elapsed)
        }
        if window?.isVisible == true { window?.makeKeyAndOrderFront(nil) }
    }

    func windowWillClose(_ notification: Notification) {
        refreshTimer?.invalidate()
        refreshTimer = nil
        delegate?.connectionAssistantDidClose()
    }

    deinit { refreshTimer?.invalidate() }
}
