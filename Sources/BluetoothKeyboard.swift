import Foundation
import IOBluetooth

/// A user-space Bluetooth Classic HID keyboard. Call its public methods on the main thread.
/// Logs contain connection/protocol events only; keyboard reports are never logged.
final class BluetoothKeyboard: NSObject, IOBluetoothL2CAPChannelDelegate {
    var onLog: ((String) -> Void)?
    var onStateChange: ((Bool, String) -> Void)?
    var hostName: String { controller?.nameAsString() ?? Host.current().localizedName ?? "Mac" }
    private(set) var isConnected = false

    private let controlPSM: BluetoothL2CAPPSM = 0x0011
    private let interruptPSM: BluetoothL2CAPPSM = 0x0013
    private var publishedControlPSM: BluetoothL2CAPPSM = 0x0011
    private var publishedInterruptPSM: BluetoothL2CAPPSM = 0x0013
    private var serviceRecord: IOBluetoothSDPServiceRecord?
    private var notifications: [IOBluetoothUserNotification] = []
    private var controller: IOBluetoothHostController?
    private var originalClassOfDevice: BluetoothClassOfDevice?
    private var classRenewal: Timer?
    private var connectionTimeout: Timer?
    private var securityCheckTimer: Timer?
    private var securityWaiting = false
    private var controlChannel: IOBluetoothL2CAPChannel?
    private var interruptChannel: IOBluetoothL2CAPChannel?
    private var connectionGeneration: UInt64 = 0
    private var controlDelegate: OutgoingDelegate?
    private var interruptDelegate: OutgoingDelegate?
    private var pendingACLDelegates: [ACLDelegate] = []
    private var retiredChannelIDs: Set<IOBluetoothObjectID> = []
    private var controlOpened = false
    private var interruptOpened = false
    private var activeDevice: IOBluetoothDevice?
    private var remoteName = ""
    private var outgoingConnection = false
    private var controlRequested = false
    private var interruptRequested = false
    private var running = false
    private var suspended = false
    private var protocolMode: UInt8 = 1
    private var idleRate: UInt8 = 0
    private var outputLEDs: UInt8 = 0
    private var lastInputReport = [UInt8](repeating: 0, count: 8)

    private enum ChannelRole { case control, interrupt }

    private final class ACLDelegate: NSObject, IOBluetoothDeviceAsyncCallbacks {
        weak var owner: BluetoothKeyboard?
        let generation: UInt64

        init(owner: BluetoothKeyboard, generation: UInt64) {
            self.owner = owner
            self.generation = generation
        }

        func connectionComplete(_ device: IOBluetoothDevice!, status: IOReturn) {
            owner?.receiveACLComplete(device, status: status, generation: generation, delegateID: ObjectIdentifier(self))
        }

        func remoteNameRequestComplete(_ device: IOBluetoothDevice!, status: IOReturn) {}
        func sdpQueryComplete(_ device: IOBluetoothDevice!, status: IOReturn) {}
    }

    /// Each async open gets a delegate bound to its attempt before calling the
    /// framework. This also identifies a callback delivered before the out-channel
    /// parameter is returned, without guessing ownership from a PSM and a nil slot.
    private final class OutgoingDelegate: NSObject, IOBluetoothL2CAPChannelDelegate {
        weak var owner: BluetoothKeyboard?
        let generation: UInt64
        let role: ChannelRole

        init(owner: BluetoothKeyboard, generation: UInt64, role: ChannelRole) {
            self.owner = owner
            self.generation = generation
            self.role = role
        }

        func l2capChannelOpenComplete(_ channel: IOBluetoothL2CAPChannel!, status error: IOReturn) {
            owner?.receiveChannelOpen(channel, status: error, generation: generation, role: role)
        }

        func l2capChannelClosed(_ channel: IOBluetoothL2CAPChannel!) {
            owner?.receiveChannelClosed(channel, generation: generation)
        }

        func l2capChannelData(_ channel: IOBluetoothL2CAPChannel!, data pointer: UnsafeMutableRawPointer!, length count: Int) {
            owner?.receiveChannelData(channel, data: pointer, length: count, generation: generation)
        }
    }

    // Standard boot-compatible keyboard, 8 input bytes and one LED output byte, no report ID.
    private static let reportDescriptor: [UInt8] = [
        0x05, 0x01, 0x09, 0x06, 0xA1, 0x01,
        0x05, 0x07, 0x19, 0xE0, 0x29, 0xE7, 0x15, 0x00, 0x25, 0x01,
        0x75, 0x01, 0x95, 0x08, 0x81, 0x02,
        0x95, 0x01, 0x75, 0x08, 0x81, 0x01,
        0x95, 0x05, 0x75, 0x01, 0x05, 0x08, 0x19, 0x01, 0x29, 0x05, 0x91, 0x02,
        0x95, 0x01, 0x75, 0x03, 0x91, 0x01,
        0x95, 0x06, 0x75, 0x08, 0x15, 0x00, 0x25, 0x67,
        0x05, 0x07, 0x19, 0x00, 0x29, 0x67, 0x81, 0x00, 0xC0
    ]

    func start() {
        precondition(Thread.isMainThread)
        guard !running else { return }
        guard let controller = IOBluetoothHostController.default() else {
            state(false, "未找到蓝牙控制器")
            return
        }
        guard controller.powerState == kBluetoothHCIPowerStateON else {
            state(false, "请在系统设置中开启蓝牙")
            return
        }
        guard let record = IOBluetoothSDPServiceRecord.publishedServiceRecord(with: Self.serviceDictionary()) else {
            state(false, "HID 服务发布失败，请检查蓝牙权限")
            return
        }
        self.controller = controller
        serviceRecord = record
        running = true

        var actualControl: BluetoothL2CAPPSM = 0
        let psmStatus = record.getL2CAPPSM(&actualControl)
        let interruptPSMs = Self.l2capPSMs(in: record.getAttributeDataElement(0x000D))
        guard psmStatus == kIOReturnSuccess, actualControl != 0, let actualInterrupt = interruptPSMs.first else {
            log("HID SDP 已发布，但无法读取实际 control / interrupt PSM；移除此服务。")
            stop()
            state(false, "无法验证 HID 服务的通道")
            return
        }
        publishedControlPSM = actualControl
        publishedInterruptPSM = actualInterrupt
        log(String(format: "HID SDP 实际 PSM：control=0x%04X，interrupt=0x%04X。", actualControl, actualInterrupt))

        // Subscribe only to the channels belonging to this published service, so that if
        // bluetoothd remaps the PSMs we do not claim an unrelated system keyboard's channel.
        for psm in Set([actualControl, actualInterrupt]) {
            if let notification = IOBluetoothL2CAPChannel.register(
                forChannelOpenNotifications: self,
                selector: #selector(channelOpened(_:channel:)),
                withPSM: psm,
                direction: kIOBluetoothUserNotificationChannelDirectionIncoming
            ) {
                notifications.append(notification)
                log(String(format: "传入 PSM 0x%04X 的通知已注册。", psm))
            } else {
                log(String(format: "传入 PSM 0x%04X 的通知注册失败。", psm))
            }
        }
        if notifications.count != Set([actualControl, actualInterrupt]).count {
            log("部分传入通道监听注册失败；仍可尝试主动连接已配对 iPhone。")
        }
        if let observer = IOBluetoothL2CAPChannel.register(
            forChannelOpenNotifications: self,
            selector: #selector(observedChannelOpened(_:channel:)),
            withPSM: 0,
            direction: kIOBluetoothUserNotificationChannelDirectionAny
        ) {
            notifications.append(observer)
            log("全局 L2CAP 诊断通知已注册（仅观察 PSM 和方向）。")
        } else {
            log("全局 L2CAP 诊断通知注册失败。")
        }
        originalClassOfDevice = controller.classOfDevice()
        renewKeyboardClass()
        classRenewal = Timer.scheduledTimer(withTimeInterval: 90, repeats: true) { [weak self] _ in
            self?.renewKeyboardClass()
        }

        if actualControl == controlPSM && actualInterrupt == interruptPSM {
            state(false, "等待 iPhone 配对或连接")
        } else {
            log("系统分配了其他 PSM，不能视为标准 HID 监听成功。可选择已配对 iPhone 尝试主动连接；无需删除配对。")
            state(false, "标准 HID 通道被系统占用；可尝试主动连接")
        }
    }

    func stop() {
        precondition(Thread.isMainThread)
        running = false
        connectionTimeout?.invalidate()
        connectionTimeout = nil
        classRenewal?.invalidate()
        classRenewal = nil
        disconnectChannels(sendRelease: true)
        for notification in notifications { notification.unregister() }
        notifications.removeAll()
        if let serviceRecord {
            let status = serviceRecord.remove()
            if status != kIOReturnSuccess { log("移除临时 HID 服务失败：\(hex(status))") }
        }
        serviceRecord = nil
        if let originalClassOfDevice, let controller {
            let status = controller.setClassOfDevice(originalClassOfDevice, forTimeInterval: 120)
            if status != kIOReturnSuccess { log("恢复蓝牙设备类别失败：\(hex(status))；临时类别将在系统期限后失效。") }
        }
        originalClassOfDevice = nil
        controller = nil
        state(false, "已停止")
    }

    /// Connects to the selected, already-paired host's standard HID channels.
    /// An accepted asynchronous request is not treated as an established connection.
    func connect(address: String) {
        precondition(Thread.isMainThread)
        if !running {
            state(false, "正在启动键盘服务…")
            start()
        }
        guard running else {
            log("键盘服务未启动，无法发起连接；请按当前状态提示处理后重试。")
            return
        }
        guard let device = IOBluetoothDevice(addressString: address), device.isPaired() else {
            state(false, "请先在系统蓝牙设置中完成配对")
            return
        }
        disconnectChannels(sendRelease: true)
        activeDevice = device
        remoteName = device.name ?? "iPhone"
        outgoingConnection = true
        controlRequested = false
        interruptRequested = false
        state(false, "正在连接 \(remoteName)…")
        let generation = connectionGeneration
        armConnectionTimeout()
        logDevice("发起连接前", device: device)
        if device.isConnected() {
            log("设备已有 ACL 基带链路，继续打开 HID control 通道。")
            openOutgoingControl(generation: generation)
            return
        }
        let delegate = ACLDelegate(owner: self, generation: generation)
        // Keep an uncancelled ACL target alive even if its attempt times out. The
        // public API has no async create-connection cancellation without closing
        // the shared baseband link. Completion removes only this target.
        pendingACLDelegates.append(delegate)
        let status = device.openConnection(delegate, withPageTimeout: 0x2000, authenticationRequired: true)
        logDevice("ACL openConnection 返回 \(hex(status)) (\(status))", device: device)
        guard running, connectionGeneration == generation else { return }
        if status != kIOReturnSuccess {
            pendingACLDelegates.removeAll { $0 === delegate }
            if device.isConnected() {
                log("ACL 请求返回非零，但基带链路实际已存在；继续验证 HID 通道。")
                openOutgoingControl(generation: generation)
            } else {
                disconnectChannels(sendRelease: false)
                state(false, "蓝牙基带连接未建立，请保持 iPhone 蓝牙页面打开后重试")
            }
        }
    }

    private func receiveACLComplete(_ device: IOBluetoothDevice?, status: IOReturn,
                                    generation: UInt64, delegateID: ObjectIdentifier) {
        onMain { keyboard in
            keyboard.pendingACLDelegates.removeAll { ObjectIdentifier($0) == delegateID }
            guard keyboard.running, keyboard.connectionGeneration == generation,
                  let device, let target = keyboard.activeDevice, keyboard.sameDevice(device, target) else { return }
            keyboard.logDevice("ACL connectionComplete status=\(keyboard.hex(status)) (\(status))", device: device)
            guard status == kIOReturnSuccess || device.isConnected() else {
                keyboard.disconnectChannels(sendRelease: false)
                keyboard.state(false, "蓝牙基带连接失败，请在 iPhone 蓝牙页面确认后重试")
                return
            }
            if status != kIOReturnSuccess {
                keyboard.log("ACL 完成回调返回非零但实际链路已存在，继续检查 HID 通道。")
            } else if !device.isConnected() {
                keyboard.log("ACL 回调成功，但连接状态尚未显示为已连接；继续一次 HID 通道验证，输入仍须通过已配对与加密检查。")
            }
            keyboard.openOutgoingControl(generation: generation)
        }
    }

    private func openOutgoingControl(generation: UInt64) {
        guard running, connectionGeneration == generation, let device = activeDevice, !controlRequested else { return }
        controlRequested = true
        log("开始连接已配对设备的 HID control 通道。")
        let delegate = OutgoingDelegate(owner: self, generation: generation, role: .control)
        controlDelegate = delegate
        var channel: IOBluetoothL2CAPChannel?
        let status = device.openL2CAPChannelAsync(&channel, withPSM: controlPSM, delegate: delegate)
        logDevice("control openL2CAPChannelAsync 返回 \(hex(status)) (\(status))", device: device)
        guard running, connectionGeneration == generation else {
            retireReturnedChannel(channel)
            return
        }
        if status == kIOReturnSuccess, channel != nil || controlChannel != nil {
            if controlChannel == nil { controlChannel = channel }
        } else {
            log("发起 HID control 连接失败：\(hex(status))")
            disconnectChannels(sendRelease: false)
            state(false, "连接未建立，请在 iPhone 蓝牙设置中确认配对")
        }
    }

    /// Returns true only when the complete HID packet was submitted to the live interrupt
    /// channel. Bluetooth delivery does not prove an app on the iPhone displayed the input.
    @discardableResult
    func sendReport(modifiers: UInt8, keys: [UInt8]) -> Bool {
        precondition(Thread.isMainThread)
        guard isConnected, !suspended, let channel = interruptChannel, let activeDevice else { return false }
        guard activeDevice.isPaired(), activeDevice.getEncryptionMode() != 0 else {
            state(false, "蓝牙链路待加密，已暂停输入")
            armConnectionTimeout()
            updateConnectedState()
            return false
        }
        var report = [UInt8](repeating: 0, count: 8)
        report[0] = modifiers
        let uniqueKeys = Array(Set(keys.filter { $0 != 0 })).sorted()
        if uniqueKeys.count > 6 {
            for index in 2..<8 { report[index] = 0x01 } // USB HID ErrorRollOver
        } else {
            for (index, key) in uniqueKeys.enumerated() { report[index + 2] = key }
        }
        let result = write([0xA1] + report, to: channel)
        if result == kIOReturnSuccess {
            lastInputReport = report
            return true
        }
        log("HID 输入写入失败：\(hex(result))")
        disconnectChannels(sendRelease: false)
        state(false, "输入通道断开，请重新连接")
        return false
    }

    @objc private func channelOpened(_ notification: IOBluetoothUserNotification, channel: IOBluetoothL2CAPChannel) {
        // Retain the framework object across the dispatch. The incoming channel's
        // delegate is installed as soon as the main-thread handler adopts it.
        onMain { keyboard in
            guard keyboard.notifications.contains(where: { $0 === notification }) else { return }
            keyboard.acceptIncomingChannel(channel)
        }
    }

    @objc private func observedChannelOpened(_ notification: IOBluetoothUserNotification, channel: IOBluetoothL2CAPChannel) {
        onMain { keyboard in
            guard keyboard.running, keyboard.notifications.contains(where: { $0 === notification }) else { return }
            keyboard.log(String(format: "观察到 L2CAP 通道：PSM=0x%04X，方向=%@。", channel.psm, channel.isIncoming() ? "传入" : "传出"))
        }
    }

    private func acceptIncomingChannel(_ channel: IOBluetoothL2CAPChannel) {
        guard running, !retiredChannelIDs.contains(channel.objectID), let device = channel.device else { return }
        // An interrupt-only notification can belong to macOS's own existing HID
        // profiles when a requested PSM was remapped. Never adopt it without our
        // control channel identifying the remote host first.
        if channel.psm == publishedInterruptPSM && activeDevice == nil { return }
        if let activeDevice, !sameDevice(activeDevice, device) {
            log("忽略另一台设备的传入 HID 通道。")
            return
        }
        if activeDevice == nil {
            activeDevice = device
            remoteName = device.name ?? "iPhone"
            outgoingConnection = false
            protocolMode = 1
            suspended = false
            armConnectionTimeout()
        }
        let psm = channel.psm
        if psm == publishedControlPSM {
            guard controlChannel == nil || controlChannel?.objectID == channel.objectID else { return }
            controlChannel = channel
        } else if psm == publishedInterruptPSM {
            guard interruptChannel == nil || interruptChannel?.objectID == channel.objectID else { return }
            interruptChannel = channel
        } else {
            return
        }
        let status = channel.setDelegate(self)
        if status != kIOReturnSuccess {
            log("设置传入 HID 通道委托失败：\(hex(status))")
            disconnectChannels(sendRelease: false)
            state(false, "HID 通道初始化失败")
        }
        // setDelegate permits the incoming configuration to finish. Wait for the
        // corresponding open-complete callback before reporting a live channel.
    }

    func l2capChannelOpenComplete(_ channel: IOBluetoothL2CAPChannel!, status error: IOReturn) {
        // Incoming channels are installed before setDelegate permits configuration;
        // exact object ownership must be checked before reacting to an old error.
        receiveChannelOpen(channel, status: error, generation: nil, role: nil)
    }

    private func receiveChannelOpen(_ channel: IOBluetoothL2CAPChannel?, status error: IOReturn,
                                    generation: UInt64?, role: ChannelRole?) {
        onMain { keyboard in
            keyboard.completeChannelOpen(channel, status: error, generation: generation, role: role)
        }
    }

    private func completeChannelOpen(_ channel: IOBluetoothL2CAPChannel?, status error: IOReturn,
                                     generation: UInt64?, role: ChannelRole?) {
        guard let channel, running, let device = channel.device,
              let activeDevice, sameDevice(activeDevice, device) else { return }
        if let generation {
            guard generation == connectionGeneration, outgoingConnection, let role else { return }
            switch role {
            case .control:
                guard channel.psm == controlPSM,
                      controlChannel == nil || controlChannel?.objectID == channel.objectID else { return }
                controlChannel = channel
            case .interrupt:
                guard channel.psm == interruptPSM,
                      interruptChannel == nil || interruptChannel?.objectID == channel.objectID else { return }
                interruptChannel = channel
            }
        }
        let isControl = controlChannel?.objectID == channel.objectID
        let isInterrupt = interruptChannel?.objectID == channel.objectID
        guard isControl || isInterrupt else { return }
        logDevice("\(isControl ? "control" : "interrupt") openComplete status=\(hex(error)) (\(error))", device: device)
        guard error == kIOReturnSuccess else {
            log("HID 通道打开失败：\(hex(error))")
            disconnectChannels(sendRelease: false)
            state(false, "HID 连接失败，请确认 iPhone 蓝牙状态")
            return
        }
        if isControl {
            controlChannel = channel
            controlOpened = true
            log("HID control 通道已打开。")
            if outgoingConnection && !interruptRequested { openOutgoingInterrupt() }
        } else if isInterrupt {
            interruptChannel = channel
            interruptOpened = true
            log("HID interrupt 通道已打开。")
        } else {
            return
        }
        updateConnectedState()
    }

    func l2capChannelClosed(_ channel: IOBluetoothL2CAPChannel!) {
        receiveChannelClosed(channel, generation: nil)
    }

    private func receiveChannelClosed(_ channel: IOBluetoothL2CAPChannel?, generation: UInt64?) {
        onMain { keyboard in
            guard generation == nil || generation == keyboard.connectionGeneration else { return }
            keyboard.handleChannelClosed(channel)
        }
    }

    private func handleChannelClosed(_ channel: IOBluetoothL2CAPChannel?) {
        guard let channel,
              channel.objectID == controlChannel?.objectID || channel.objectID == interruptChannel?.objectID else { return }
        log("HID 通道已关闭。")
        disconnectChannels(sendRelease: false)
        state(false, running ? "设备已断开；可重新连接" : "已停止")
    }

    func l2capChannelData(_ channel: IOBluetoothL2CAPChannel!, data dataPointer: UnsafeMutableRawPointer!, length dataLength: Int) {
        receiveChannelData(channel, data: dataPointer, length: dataLength, generation: nil)
    }

    private func receiveChannelData(_ channel: IOBluetoothL2CAPChannel?, data dataPointer: UnsafeMutableRawPointer?,
                                    length dataLength: Int, generation: UInt64?) {
        guard let channel, let dataPointer, dataLength > 0, dataLength <= 1024 else { return }
        // The raw buffer belongs to IOBluetooth and is valid only for this callback.
        // Copy it before dispatching; the captured channel and array retain their data.
        let bytes = Array(UnsafeBufferPointer(start: dataPointer.assumingMemoryBound(to: UInt8.self), count: dataLength))
        onMain { keyboard in
            guard generation == nil || generation == keyboard.connectionGeneration else { return }
            keyboard.handleChannelData(channel, bytes: bytes)
        }
    }

    private func handleChannelData(_ channel: IOBluetoothL2CAPChannel, bytes: [UInt8]) {
        if channel.objectID == controlChannel?.objectID {
            handleControl(bytes, channel: channel)
        } else if channel.objectID == interruptChannel?.objectID,
                  bytes[0] == 0xA2, bytes.count >= 2 {
            outputLEDs = bytes[1] & 0x1F
        }
    }

    private func openOutgoingInterrupt() {
        guard let device = activeDevice, running, !interruptRequested else { return }
        interruptRequested = true
        let generation = connectionGeneration
        let delegate = OutgoingDelegate(owner: self, generation: generation, role: .interrupt)
        interruptDelegate = delegate
        var channel: IOBluetoothL2CAPChannel?
        let status = device.openL2CAPChannelAsync(&channel, withPSM: interruptPSM, delegate: delegate)
        logDevice("interrupt openL2CAPChannelAsync 返回 \(hex(status)) (\(status))", device: device)
        guard running, connectionGeneration == generation else {
            retireReturnedChannel(channel)
            return
        }
        if status == kIOReturnSuccess, channel != nil || interruptChannel != nil {
            if interruptChannel == nil { interruptChannel = channel }
        } else {
            log("发起 HID interrupt 连接失败：\(hex(status))")
            disconnectChannels(sendRelease: false)
            state(false, "HID 输入通道未建立")
        }
    }

    private func updateConnectedState() {
        guard controlOpened, interruptOpened,
              let controlDevice = controlChannel?.device,
              let interruptDevice = interruptChannel?.device,
              sameDevice(controlDevice, interruptDevice) else { return }
        let paired = controlDevice.isPaired()
        let encryption = controlDevice.getEncryptionMode()
        guard paired, encryption != 0 else {
            if !securityWaiting {
                securityWaiting = true
                log("HID 两通道已建立；paired=\(paired)，encryptionMode=\(encryption)，尚未启用键入。")
                state(false, paired ? "HID 通道已建立，等待蓝牙链路加密…" : "HID 通道已建立，等待系统完成配对…")
                securityCheckTimer?.invalidate()
                securityCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                    self?.updateConnectedState()
                }
            }
            return
        }
        securityCheckTimer?.invalidate()
        securityCheckTimer = nil
        securityWaiting = false
        guard !isConnected else { return }
        connectionTimeout?.invalidate()
        connectionTimeout = nil
        lastInputReport = [UInt8](repeating: 0, count: 8)
        log("HID 两通道属于同一已配对设备；链路 encryptionMode=\(encryption)，启用键入。")
        state(true, "已连接 \(remoteName)")
        _ = sendReport(modifiers: 0, keys: [])
    }

    private func handleControl(_ bytes: [UInt8], channel: IOBluetoothL2CAPChannel) {
        let transaction = bytes[0] & 0xF0
        let parameter = bytes[0] & 0x0F
        let transactionNames: [UInt8: String] = [
            0x10: "HID_CONTROL", 0x40: "GET_REPORT", 0x50: "SET_REPORT",
            0x60: "GET_PROTOCOL", 0x70: "SET_PROTOCOL", 0x80: "GET_IDLE", 0x90: "SET_IDLE"
        ]
        if let name = transactionNames[transaction] { log("收到 HID 控制事务：\(name)。") }
        switch transaction {
        case 0x10: // HID_CONTROL has no handshake response.
            switch parameter {
            case 0: break
            case 1, 2:
                _ = sendReport(modifiers: 0, keys: [])
                protocolMode = 1
                idleRate = 0
                suspended = false
            case 3:
                _ = sendReport(modifiers: 0, keys: [])
                suspended = true
                state(isConnected, "手机已暂停键盘输入")
            case 4:
                suspended = false
                state(isConnected, "已连接 \(remoteName)")
            case 5:
                // Close this virtual cable without deleting the system's pairing record.
                log("手机请求断开 HID 虚拟连接；系统配对信息保留。")
                disconnectChannels(sendRelease: true)
                state(false, "手机已断开键盘连接")
            default: break
            }
        case 0x40: // GET_REPORT
            let reportType = parameter & 0x03
            guard parameter & 0x04 == 0, reportType == 1 || reportType == 2 else {
                handshake(0x03, channel: channel)
                return
            }
            let secure = channel.device.map { $0.isPaired() && $0.getEncryptionMode() != 0 } ?? false
            var response: [UInt8] = reportType == 1 ? (secure ? lastInputReport : [UInt8](repeating: 0, count: 8)) : [outputLEDs]
            if parameter & 0x08 != 0 {
                // Without numbered reports, two trailing bytes encode BufferSize.
                // Tolerate a leading zero report ID used by some hosts.
                let offset = bytes.count == 4 && bytes[1] == 0 ? 2 : 1
                guard bytes.count == offset + 2 else { handshake(0x04, channel: channel); return }
                let maxLength = Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8)
                guard maxLength > 0 else { handshake(0x04, channel: channel); return }
                response = Array(response.prefix(maxLength))
            } else if bytes.count != 1 && !(bytes.count == 2 && bytes[1] == 0) {
                handshake(0x02, channel: channel)
                return
            }
            _ = write([0xA0 | reportType] + response, to: channel)
        case 0x50: // SET_REPORT: this keyboard accepts only the LED output report.
            guard parameter == 2 else { handshake(0x03, channel: channel); return }
            if bytes.count == 2 {
                outputLEDs = bytes[1] & 0x1F
                handshake(0, channel: channel)
            } else if bytes.count == 3 && bytes[1] == 0 {
                outputLEDs = bytes[2] & 0x1F
                handshake(0, channel: channel)
            } else {
                handshake(0x04, channel: channel)
            }
        case 0x60: // GET_PROTOCOL
            guard parameter == 0, bytes.count == 1 else { handshake(0x04, channel: channel); return }
            _ = write([0xA0, protocolMode], to: channel)
        case 0x70: // SET_PROTOCOL: identical 8-byte format in boot and report mode.
            guard parameter <= 1, bytes.count == 1 else { handshake(0x04, channel: channel); return }
            protocolMode = parameter
            log(parameter == 0 ? "手机选择 Boot 键盘协议。" : "手机选择 Report 键盘协议。")
            handshake(0, channel: channel)
        case 0x80: // GET_IDLE
            guard parameter == 0, bytes.count == 1 else { handshake(0x04, channel: channel); return }
            _ = write([0xA0, idleRate], to: channel)
        case 0x90: // SET_IDLE
            guard parameter == 0, bytes.count == 2 else { handshake(0x04, channel: channel); return }
            idleRate = bytes[1]
            handshake(0, channel: channel)
        case 0xA0: // Unacknowledged DATA(Output), also accepted on control.
            if parameter == 2, bytes.count == 2 { outputLEDs = bytes[1] & 0x1F }
        case 0x00:
            // A host handshake is a response; never acknowledge it recursively.
            break
        default:
            handshake(0x03, channel: channel)
        }
    }

    private func handshake(_ result: UInt8, channel: IOBluetoothL2CAPChannel) {
        let status = write([result & 0x0F], to: channel)
        if status != kIOReturnSuccess { log("HID 握手响应发送失败：\(hex(status))") }
    }

    private func write(_ bytes: [UInt8], to channel: IOBluetoothL2CAPChannel) -> IOReturn {
        guard !bytes.isEmpty, bytes.count <= Int(channel.outgoingMTU) else { return kIOReturnNoSpace }
        var packet = bytes
        return packet.withUnsafeMutableBytes { raw in
            channel.writeSync(raw.baseAddress!, length: UInt16(raw.count))
        }
    }

    private func disconnectChannels(sendRelease: Bool) {
        // Invalidate pending delegates before any synchronous write/close can
        // reenter the run loop. A retired attempt can no longer mutate this one.
        connectionGeneration &+= 1
        connectionTimeout?.invalidate()
        connectionTimeout = nil
        securityCheckTimer?.invalidate()
        securityCheckTimer = nil
        securityWaiting = false
        // Clear ownership before closeChannel, which may invoke a callback immediately.
        let oldControl = controlChannel
        let oldInterrupt = interruptChannel
        if let oldControl { retiredChannelIDs.insert(oldControl.objectID) }
        if let oldInterrupt { retiredChannelIDs.insert(oldInterrupt.objectID) }
        let wasInterruptOpened = interruptOpened
        controlChannel = nil
        interruptChannel = nil
        controlDelegate = nil
        interruptDelegate = nil
        controlOpened = false
        interruptOpened = false
        isConnected = false
        activeDevice = nil
        remoteName = ""
        suspended = false
        outgoingConnection = false
        controlRequested = false
        interruptRequested = false
        protocolMode = 1
        idleRate = 0
        outputLEDs = 0
        lastInputReport = [UInt8](repeating: 0, count: 8)
        if sendRelease, wasInterruptOpened, let oldInterrupt {
            _ = write([0xA1] + [UInt8](repeating: 0, count: 8), to: oldInterrupt)
        }
        _ = oldControl?.setDelegate(nil)
        _ = oldInterrupt?.setDelegate(nil)
        _ = oldInterrupt?.close()
        _ = oldControl?.close()
        // Deliberately do not close the device's baseband link: other profiles may use it.
    }

    private func retireReturnedChannel(_ channel: IOBluetoothL2CAPChannel?) {
        guard let channel,
              channel.objectID != controlChannel?.objectID,
              channel.objectID != interruptChannel?.objectID else { return }
        retiredChannelIDs.insert(channel.objectID)
        _ = channel.setDelegate(nil)
        _ = channel.close()
    }

    private func armConnectionTimeout() {
        connectionTimeout?.invalidate()
        let generation = connectionGeneration
        connectionTimeout = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { [weak self] _ in
            guard let self, self.connectionGeneration == generation, !self.isConnected else { return }
            self.log("HID 两通道未在等待期限内建立。")
            if let device = self.activeDevice { self.logDevice("连接超时现场", device: device) }
            self.disconnectChannels(sendRelease: false)
            self.state(false, "连接超时；请确认 iPhone 蓝牙页面后重试")
        }
    }

    private func renewKeyboardClass() {
        guard let controller, let originalClassOfDevice else { return }
        let keyboardClass: BluetoothClassOfDevice = (originalClassOfDevice & 0xFFE000) | 0x0540
        let status = controller.setClassOfDevice(keyboardClass, forTimeInterval: 120)
        if status != kIOReturnSuccess { log("临时设置键盘设备类别失败：\(hex(status))；继续尝试 HID 服务连接。") }
    }

    private func sameDevice(_ first: IOBluetoothDevice, _ second: IOBluetoothDevice) -> Bool {
        guard let a = first.addressString, let b = second.addressString else { return false }
        return a.caseInsensitiveCompare(b) == .orderedSame
    }

    private func onMain(_ work: @escaping (BluetoothKeyboard) -> Void) {
        if Thread.isMainThread {
            work(self)
        } else {
            DispatchQueue.main.async { [weak self] in
                if let self { work(self) }
            }
        }
    }

    private func state(_ connected: Bool, _ message: String) {
        isConnected = connected
        onStateChange?(connected, message)
    }

    private func log(_ message: String) { onLog?(message) }
    private func logDevice(_ prefix: String, device: IOBluetoothDevice) {
        log("\(prefix)：isConnected=\(device.isConnected())，isPaired=\(device.isPaired())，encryptionMode=\(device.getEncryptionMode())。")
    }
    private func hex(_ status: IOReturn) -> String { String(format: "0x%08X", UInt32(bitPattern: status)) }

    #if HID_SDP_TESTS
    // Compiled only by the offline descriptor probe; this does not publish SDP,
    // alter the controller, request permission, or connect to a device.
    static func sdpDictionaryForTests() -> [String: Any] { serviceDictionary() }
    static var descriptorForTests: [UInt8] { reportDescriptor }
    #endif

    private static func l2capPSMs(in element: IOBluetoothSDPDataElement?) -> [BluetoothL2CAPPSM] {
        guard let array = element?.getArrayValue() as? [IOBluetoothSDPDataElement] else { return [] }
        if array.count >= 2, let uuid = array[0].getUUIDValue(),
           uuid.isEqual(to: IOBluetoothSDPUUID(uuid16: 0x0100)), let value = array[1].getNumberValue() {
            return [value.uint16Value]
        }
        return array.flatMap { l2capPSMs(in: $0) }
    }

    private static func serviceDictionary() -> [String: Any] {
        func uint(_ value: UInt32, _ size: Int) -> [String: Any] {
            ["DataElementType": 1, "DataElementSize": size, "DataElementValue": NSNumber(value: value)]
        }
        func boolean(_ value: Bool) -> [String: Any] {
            ["DataElementType": 5, "DataElementSize": 1, "DataElementValue": NSNumber(value: value)]
        }
        func uuid(_ value: UInt16) -> IOBluetoothSDPUUID { IOBluetoothSDPUUID(uuid16: value) }
        let descriptor: [String: Any] = [
            "DataElementType": 4,
            "DataElementSize": reportDescriptor.count,
            "DataElementValue": Data(reportDescriptor)
        ]
        var localAttributes: [String: Any] = ["Persistent": false]
        if let executablePath = Bundle.main.executablePath { localAttributes["TargetApplication"] = executablePath }
        return [
            "0001 - ServiceClassIDList": [uuid(0x1124)],
            "0004 - ProtocolDescriptorList": [[uuid(0x0100), uint(0x0011, 2)], [uuid(0x0011)]],
            "0005 - BrowseGroupList": [uuid(0x1002)],
            "0006 - LanguageBaseAttributeIDList": [uint(0x656E, 2), uint(0x006A, 2), uint(0x0100, 2)],
            "0009 - BluetoothProfileDescriptorList": [[uuid(0x1124), uint(0x0101, 2)]],
            "000D - AdditionalProtocolDescriptorLists": [[[uuid(0x0100), uint(0x0013, 2)], [uuid(0x0011)]]],
            "0100 - ServiceName": "MacPhoneKeys Keyboard",
            "0101 - ServiceDescription": "Bluetooth keyboard for personal use",
            "0102 - ProviderName": "MacPhoneKeys",
            "0200 - HIDDeviceReleaseNumber": uint(0x0100, 2),
            "0201 - HIDParserVersion": uint(0x0111, 2),
            "0202 - HIDDeviceSubclass": uint(0x40, 1),
            "0203 - HIDCountryCode": uint(0, 1),
            "0204 - HIDVirtualCable": boolean(true),
            "0205 - HIDReconnectInitiate": boolean(false),
            "0206 - HIDDescriptorList": [[uint(0x22, 1), descriptor]],
            "0207 - HIDLANGIDBaseList": [[uint(0x0409, 2), uint(0x0100, 2)]],
            "0208 - HIDSDPDisable": boolean(false),
            "0209 - HIDBatteryPower": boolean(false),
            "020A - HIDRemoteWake": boolean(false),
            "020B - HIDProfileVersion": uint(0x0101, 2),
            "020C - HIDSupervisionTimeout": uint(0x0C80, 2),
            "020D - HIDNormallyConnectable": boolean(true),
            "020E - HIDBootDevice": boolean(true),
            "LocalAttributes": localAttributes
        ]
    }
}
