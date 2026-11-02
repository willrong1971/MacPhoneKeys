import AppKit
import IOBluetoothUI

protocol ConnectionAssistantDelegate: AnyObject {
    func connectionAssistantNeedsRefresh()
    func connectionAssistantStartService()
    func connectionAssistantOpenBluetoothSettings()
    func connectionAssistantOpenSystemPairingSupport()
    func connectionAssistantWillOpenSystemPairing()
    func connectionAssistantDidFinishSystemPairing(_ result: PairingFlow.SystemPanelResult, rawCode: Int32?, elapsedMilliseconds: Int)
    func connectionAssistantRecoverService()
    func connectionAssistantSendTest()
    func connectionAssistantReportPhoneText(visible: Bool)
    func connectionAssistantExportDiagnostics()
    func connectionAssistantShowFullSettings()
    func connectionAssistantDidClose()
}

extension ConnectionAssistantDelegate {
    func connectionAssistantOpenSystemPairingSupport() { connectionAssistantOpenBluetoothSettings() }
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
    private var troubleshooting = TroubleshootingFlow()
    var troubleshootingSnapshot: [String: Any] { troubleshooting.diagnosticSnapshot }
    private var guideStep = NSTextField(labelWithString: "")
    private var guideBody = NSTextField(wrappingLabelWithString: "")
    private var symptomChoices: NSStackView!
    private var guidePrimaryButton: NSButton!
    private var guideBackButton: NSButton!
    private var guideNextButton: NSButton!
    private var guideStillFailingButton: NSButton!
    private var phoneSection: NSStackView!
    private var verificationSection: NSStackView!
    private var recoverySection: NSStackView!
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

        let title = text(L("连接检查与修复"), size: 24)
        title.font = .systemFont(ofSize: 24, weight: .semibold)
        let intro = text(L("先检查 Mac，再选择手机上遇到的情况。每一步由你确认结果，最后以手机实际显示文字为准。"), color: .secondaryLabelColor)
        let header = NSStackView(views: [title, intro, previewLabel])
        header.orientation = .vertical; header.alignment = .leading; header.spacing = 7
        intro.widthAnchor.constraint(equalTo: header.widthAnchor).isActive = true
        previewLabel.widthAnchor.constraint(equalTo: header.widthAnchor).isActive = true
        previewLabel.font = .systemFont(ofSize: 12)
        previewLabel.textColor = .systemOrange
        stack.addArrangedSubview(header)

        startButton = button(L("启动键盘服务"), #selector(startService))
        let mac = section(L("Mac 当前状态"), views: [
            row([text(L("蓝牙权限：")), permissionValue]),
            row([text(L("键盘服务：")), serviceValue]),
            row([text(L("蓝牙广播：")), advertisementValue])
        ])
        stack.addArrangedSubview(mac)

        symptomChoices = NSStackView(views: [
            row([button(L("第一次连接 iPhone"), #selector(firstConnection)), button(L("手机找不到 Mac"), #selector(macNotVisible))]),
            row([button(L("手机提示配对失败"), #selector(pairingFailed)), button(L("已连接，但手机没有文字"), #selector(connectedNoText))])
        ])
        symptomChoices.orientation = .vertical; symptomChoices.alignment = .leading; symptomChoices.spacing = 7
        guideStep.font = .systemFont(ofSize: 15, weight: .semibold)
        guideBody.font = .systemFont(ofSize: 13)
        guideBody.maximumNumberOfLines = 0
        guidePrimaryButton = button("", #selector(performGuideAction))
        guideBackButton = button(L("上一步"), #selector(previousGuideStep))
        guideNextButton = button(L("下一步"), #selector(nextGuideStep))
        guideStillFailingButton = button(L("已完成，仍不行"), #selector(guideStillFailing))
        let guideExport = button(L("结束并导出诊断…"), #selector(finishAndExport))
        let guide = section(L("按步骤继续"), views: [symptomChoices, guideStep, guideBody,
            row([guidePrimaryButton]), row([guideBackButton, guideNextButton, guideStillFailingButton]), row([guideExport])])
        stack.addArrangedSubview(guide)

        pairButton = button(L("打开系统配对窗口…"), #selector(openSystemPairing))
        settingsButton = button(L("Mac 蓝牙设置…"), #selector(openBluetoothSettings))
        phoneSection = section(L("手机上的操作"), views: [phoneInstructions, pairingFeedback, connectionValue])
        stack.addArrangedSubview(phoneSection)

        testButton = button(L("发送测试串…"), #selector(sendTest))
        visibleButton = button(L("手机完整显示了"), #selector(confirmVisible))
        missingButton = button(L("手机没有完整显示"), #selector(confirmMissing))
        verificationSection = section(L("确认手机文字"), views: [
            text(L("在 iPhone 备忘录新建空白笔记，点正文看到光标，切到英文后再发送。测试不会按回车。"), color: .secondaryLabelColor),
            verificationValue, row([visibleButton, missingButton])
        ])
        stack.addArrangedSubview(verificationSection)

        recoverButton = button(L("重新建立键盘服务"), #selector(recoverService))
        recoverySection = section(L("服务恢复与诊断"), views: [
            text(L("先保持两端蓝牙页面打开。可以手动重建一次本 App 的键盘服务，再重新连接。"), color: .secondaryLabelColor),
            recoveryValue,
            text(L("不会自动清除配对记录，也不会开关系统蓝牙。"), size: 12, color: .secondaryLabelColor)
        ])
        stack.addArrangedSubview(recoverySection)
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
        renderTroubleshooting(flow: flow)
    }

    private func renderTroubleshooting(flow: PairingFlow) {
        let state = flow.observation
        troubleshooting.observe(TroubleshootingFlow.Evidence(running: state.running,
            permissionAllowed: state.authorization == "allowedAlways", radioOn: state.radioOn,
            servicesReady: state.servicesReady, phase: state.phase, keyboardReady: state.keyboardReady,
            verification: flow.verificationState.rawValue, verificationAttemptID: flow.verificationAttemptID,
            generation: state.generation))
        let step = troubleshooting.displayedStep
        let title: String
        let body: String
        switch step {
        case .chooseSymptom:
            title = L("选择当前情况")
            body = L("请选择第一次连接，或手机上实际看到的问题。App 不能直接读取手机蓝牙页面。")
        case .checkMac:
            title = L("先完成 Mac 的准备")
            switch troubleshooting.blocker {
            case .stopped: body = L("请先启动键盘服务；系统询问蓝牙权限时，选择允许。")
            case .permission: body = L("请在 Mac 的“系统设置 → 隐私与安全性 → 蓝牙”中允许手机键盘，然后回到这里。")
            case .radio: body = L("请在 Mac 的“系统设置 → 蓝牙”中开启蓝牙，然后回到这里。")
            case .failedService: body = L("Mac 的键盘服务尚未就绪。可以手动重建一次；如果仍失败，请导出诊断报告。")
            default: body = L("正在准备本 App 的键盘服务，请稍候。页面会更新状态，不需要反复点击恢复。")
            }
        case .openMacPairing:
            title = L("先打开 Mac 配对入口")
            body = L("先点下方按钮。在 Mac 系统窗口选择自己的 iPhone；保持该窗口打开，必要时在手机“设置 → 蓝牙”中点这台 Mac，并核对两端配对码。请先读完这些操作再打开窗口。")
        case .findMac:
            title = L("在手机列表中找到 Mac")
            body = L("保持 Mac 蓝牙设置打开。在手机进入“设置 → 蓝牙”；若未看到 Mac，退出该页面后重新进入。确实看到这台 Mac 后点“下一步”；仍找不到则点“已完成，仍不行”。")
        case .waitForKeyboard:
            title = L("等待手机建立键盘通道")
            body = L("在手机点这台 Mac，并按两端系统提示核对配对码。手机显示“已连接”后，仍需等待本 App 收到加密键盘订阅；收到后会自动进入文字测试。")
        case .testPhoneText:
            title = L("用本次新测试确认手机文字")
            body = L("连接通道已经就绪。请按下方说明准备空白备忘录，发送一次测试，再亲眼确认手机显示。已有连接或以前的测试成功，不能代替本次结果。")
        case .recoverService:
            title = L("手动重建一次 App 服务")
            body = L("此操作只重建本 App 的键盘服务，会暂时断开手机键盘通道。本轮最多做一次，然后按新的连接结果继续，不要反复重建。")
        case .waitAfterRecovery:
            title = L("等待恢复后的新连接")
            body = L("服务恢复已请求。请在手机点这台 Mac 重新连接；新的加密键盘通道就绪后，会自动进入文字测试。仍连不上时，点“已完成，仍不行”继续系统与手机检查。")
        case .systemSupport:
            title = L("检查系统与手机蓝牙页面")
            body = L("先打开并保持 Mac 蓝牙设置。你也可以手动在 iPhone 的“设置 → 蓝牙”中关闭蓝牙约 10 秒再开启，等待约 20 秒后重试；这会短暂断开手机的其他蓝牙配件，请自行决定是否执行。完成后点“下一步”重试，仍失败则导出诊断。")
        case .finished:
            title = L("本次手机文字已由你确认")
            body = L("本轮检查完成。关闭此窗口后，可用菜单栏图标或 ⌃⌥K 切换输入；再次按快捷键、按 Esc 或切到其他 Mac 程序会停止输入。")
        case .exportDiagnostics:
            title = L("停止重复尝试，保存诊断")
            body = L("本轮建议步骤已完成，仍未确认恢复。请保存诊断报告，保留当前配对记录，便于根据证据继续处理。App 不会自动忘记设备或重置系统蓝牙。")
        }
        guideStep.stringValue = LF("当前步骤：%@", title)
        guideBody.stringValue = body
        symptomChoices.isHidden = step != .chooseSymptom
        phoneSection.isHidden = ![.openMacPairing, .findMac, .waitForKeyboard, .systemSupport].contains(step)
        verificationSection.isHidden = ![.testPhoneText, .finished].contains(step)
        recoverySection.isHidden = ![.recoverService, .waitAfterRecovery, .exportDiagnostics].contains(step)
            && troubleshooting.primaryAction != .recoverService
        if step == .testPhoneText && !troubleshooting.sawCurrentTest {
            verificationValue.stringValue = L("本轮排查尚未完成新的手机文字测试，请发送后再确认。")
        }
        let currentTrial = troubleshooting.allowsConfirmation(attemptID: flow.verificationAttemptID)
        visibleButton.isEnabled = flow.canConfirmPhoneText && currentTrial
        missingButton.isEnabled = flow.canConfirmPhoneText && currentTrial
        let action = troubleshooting.primaryAction
        switch action {
        case .startService: guidePrimaryButton.title = L("启动键盘服务")
        case .openBluetoothSettings: guidePrimaryButton.title = L("Mac 蓝牙设置…")
        case .openSystemPairing: guidePrimaryButton.title = L("打开 Mac 配对入口…")
        case .sendTest: guidePrimaryButton.title = L("发送测试串…")
        case .recoverService: guidePrimaryButton.title = L("重新建立键盘服务")
        case .systemSupport: guidePrimaryButton.title = L("打开 Mac 蓝牙设置继续检查…")
        case .exportDiagnostics: guidePrimaryButton.title = L("导出诊断报告…")
        case .none: guidePrimaryButton.title = ""
        }
        guidePrimaryButton.isHidden = action == .none
        guidePrimaryButton.isEnabled = !flow.systemPanelOpen
        if action == .openSystemPairing { guidePrimaryButton.isEnabled = flow.canOpenSystemPairing }
        if action == .sendTest { guidePrimaryButton.isEnabled = flow.canSendTest }
        if action == .recoverService { guidePrimaryButton.isEnabled = flow.canRecoverService && !troubleshooting.recoveryUsed }
        if state.isPreview && [.startService, .openBluetoothSettings, .openSystemPairing, .recoverService, .systemSupport].contains(action) {
            guidePrimaryButton.isEnabled = false
        }
        guideBackButton.isEnabled = troubleshooting.canGoBack && !flow.systemPanelOpen && flow.verificationState != .sending
        guideNextButton.isEnabled = troubleshooting.canGoNext && !flow.systemPanelOpen && flow.verificationState != .sending
        guideStillFailingButton.isEnabled = (troubleshooting.canReportStillFailing || step == .waitAfterRecovery)
            && !flow.systemPanelOpen && flow.verificationState != .sending
            && state.phase != "registering" && state.phase != "recovering"
        if flow.recoveryCooldownRemainingSeconds > 0 {
            recoveryValue.stringValue = LF("请等待 %ld 秒后，再手动重建服务。", flow.recoveryCooldownRemainingSeconds)
        }
    }

    private func beginGuide(_ symptom: TroubleshootingFlow.Symptom) {
        troubleshooting.begin(symptom)
        delegate?.connectionAssistantNeedsRefresh()
    }
    @objc private func firstConnection() { beginGuide(.firstConnection) }
    @objc private func macNotVisible() { beginGuide(.macNotVisible) }
    @objc private func pairingFailed() { beginGuide(.pairingFailed) }
    @objc private func connectedNoText() { beginGuide(.connectedNoText) }
    @objc private func previousGuideStep() { troubleshooting.goBack(); delegate?.connectionAssistantNeedsRefresh() }
    @objc private func nextGuideStep() { troubleshooting.goNext(); delegate?.connectionAssistantNeedsRefresh() }
    @objc private func guideStillFailing() {
        if troubleshooting.displayedStep == .waitAfterRecovery { troubleshooting.recoveryStillFailed() }
        else { troubleshooting.stillNotWorking() }
        delegate?.connectionAssistantNeedsRefresh()
    }
    @objc private func finishAndExport() {
        troubleshooting.finishWithDiagnostics()
        delegate?.connectionAssistantNeedsRefresh()
        delegate?.connectionAssistantExportDiagnostics()
    }
    @objc private func performGuideAction() {
        guard guidePrimaryButton.isEnabled else { return }
        switch troubleshooting.primaryAction {
        case .startService: startService()
        case .openBluetoothSettings: openBluetoothSettings()
        case .openSystemPairing: openSystemPairing()
        case .sendTest: sendTest()
        case .recoverService: recoverService()
        case .systemSupport:
            guard troubleshooting.recordAction(.systemSupport) else { return }
            delegate?.connectionAssistantOpenSystemPairingSupport()
            delegate?.connectionAssistantNeedsRefresh()
        case .exportDiagnostics: finishAndExport()
        case .none: break
        }
    }

    @objc private func startService() {
        _ = troubleshooting.recordAction(.startService)
        delegate?.connectionAssistantStartService()
    }
    @objc private func openBluetoothSettings() {
        _ = troubleshooting.recordAction(.openBluetoothSettings)
        delegate?.connectionAssistantOpenBluetoothSettings()
    }
    @objc private func sendTest() {
        guard lastFlow.canSendTest else { return }
        _ = troubleshooting.recordAction(.sendTest)
        delegate?.connectionAssistantSendTest()
    }
    @objc private func confirmVisible() {
        guard lastFlow.canConfirmPhoneText,
              troubleshooting.allowsConfirmation(attemptID: lastFlow.verificationAttemptID) else { return }
        delegate?.connectionAssistantReportPhoneText(visible: true)
    }
    @objc private func confirmMissing() {
        guard lastFlow.canConfirmPhoneText,
              troubleshooting.allowsConfirmation(attemptID: lastFlow.verificationAttemptID) else { return }
        troubleshooting.phoneTextReportedMissing()
        delegate?.connectionAssistantReportPhoneText(visible: false)
    }
    @objc private func recoverService() {
        guard lastFlow.canRecoverService, troubleshooting.recordAction(.recoverService) else { return }
        delegate?.connectionAssistantRecoverService()
    }
    @objc private func exportDiagnostics() { delegate?.connectionAssistantExportDiagnostics() }
    @objc private func showFullSettings() { delegate?.connectionAssistantShowFullSettings() }
    @objc private func closeAssistant() { close() }

    @objc private func openSystemPairing() {
        guard lastFlow.canOpenSystemPairing, pairingController == nil else { return }
        _ = troubleshooting.recordAction(.openSystemPairing)
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
        picker.setDescriptionText(L("在此 Mac 窗口选择自己的 iPhone，并保持窗口打开。必要时在 iPhone 的“设置 → 蓝牙”中点这台 Mac，核对两端相同的配对码后确认。取消不会清除已有配对。"))
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
