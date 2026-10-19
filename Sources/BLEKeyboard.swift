import Foundation
import CoreBluetooth

/// Pure FIFO state used by the BLE transport. A failed CoreBluetooth submission
/// leaves `nextReport` untouched. Cancellation removes every unsent key report
/// and installs one highest-priority release, including after an overflow.
struct BLEInputReportQueue {
    private let capacity: Int
    private var reports: [Data] = []
    private var releaseRequired = false
    private static let release = Data(repeating: 0, count: 8)

    init(capacity: Int = 128) {
        precondition(capacity > 0)
        self.capacity = capacity
    }

    var count: Int { reports.count }
    var nextReport: Data? { releaseRequired ? Self.release : reports.first }

    @discardableResult
    mutating func enqueue(_ report: Data) -> Bool {
        guard reports.count < capacity else { cancel(); return false }
        reports.append(report)
        return true
    }

    mutating func didSubmitNext() {
        if releaseRequired { releaseRequired = false }
        else if !reports.isEmpty { reports.removeFirst() }
    }

    mutating func cancel() {
        reports.removeAll(keepingCapacity: true)
        releaseRequired = true
    }
}

/// Experimental HID-over-GATT transport using public CoreBluetooth APIs only.
///
/// Publishing 0x1812 may be rejected by macOS. Registration and advertising are
/// diagnostics, not proof that iOS accepted a keyboard. A notification subscription
/// is the earliest point at which `isConnected` becomes true; even then, the user
/// must verify actual text on the iPhone. Public CoreBluetooth does not expose
/// descriptor encryption permissions or an API to disconnect a peripheral's central.
final class BLEKeyboard: NSObject, CBPeripheralManagerDelegate {
    var onLog: ((String) -> Void)?
    var onStateChange: ((Bool, String) -> Void)?
    private(set) var isConnected = false
    private(set) var serviceRegistrationSucceeded = false
    let hostName = "MacKeys"

    private let expandedServiceUUID: Bool
    private var manager: CBPeripheralManager?
    private var running = false
    private var hidService: CBMutableService?
    private var mandatoryServices: [CBMutableService] = []
    private var registeredServices = Set<ObjectIdentifier>()
    private var failedServices = Set<ObjectIdentifier>()
    private var batteryLevel: CBMutableCharacteristic?
    private var pnpID: CBMutableCharacteristic?
    private var loggedReadUUIDs = Set<String>()
    private var loggedWriteUUIDs = Set<String>()
    private var reportMap: CBMutableCharacteristic?
    private var hidInformation: CBMutableCharacteristic?
    private var protocolModeCharacteristic: CBMutableCharacteristic?
    private var controlPoint: CBMutableCharacteristic?
    private var inputReport: CBMutableCharacteristic?
    private var outputReport: CBMutableCharacteristic?
    private var bootInputReport: CBMutableCharacteristic?
    private var bootOutputReport: CBMutableCharacteristic?
    private var protocolMode: UInt8 = 1
    private var suspended = false
    private var outputLEDs: UInt8 = 0
    private var lastInputReport = Data(repeating: 0, count: 8)
    private var reportSubscribers: [UUID: CBCentral] = [:]
    private var bootSubscribers: [UUID: CBCentral] = [:]
    private var selectedCentralID: UUID?
    private var pendingInput = BLEInputReportQueue()
    private var observedBackpressure = false
    private var flushingInput = false

    // Experimental fixture only: Vendor ID Source 0x01 selects Bluetooth SIG's
    // identifier space. 0xFFFF is deliberately an unassigned placeholder, not
    // Apple's (or another vendor's) registered identity. This is not a qualified
    // shipping-device identity. Fields following the source are little-endian.
    private static let experimentalPnPID = Data([0x01, 0xFF, 0xFF, 0x01, 0x00, 0x01, 0x00])

    // 63-byte, no-Report-ID map: 8-byte keyboard input and one-byte LED output.
    // 0x73 includes the keypad equals usage used by the physical-key mapping.
    private static let reportDescriptor = Data([
        0x05, 0x01, 0x09, 0x06, 0xA1, 0x01,
        0x05, 0x07, 0x19, 0xE0, 0x29, 0xE7, 0x15, 0x00, 0x25, 0x01,
        0x75, 0x01, 0x95, 0x08, 0x81, 0x02,
        0x95, 0x01, 0x75, 0x08, 0x81, 0x01,
        0x95, 0x05, 0x75, 0x01, 0x05, 0x08, 0x19, 0x01, 0x29, 0x05, 0x91, 0x02,
        0x95, 0x01, 0x75, 0x03, 0x91, 0x01,
        0x95, 0x06, 0x75, 0x08, 0x15, 0x00, 0x25, 0x73,
        0x05, 0x07, 0x19, 0x00, 0x29, 0x73, 0x81, 0x00, 0xC0,
    ])

    /// The expanded form is an explicitly selected public-API registration probe,
    /// not an automatic workaround or a claim of standard HID recognition by iOS.
    /// The default first attempts the ordinary 16-bit standard service UUID.
    init(useExpandedServiceUUID: Bool = false) {
        expandedServiceUUID = useExpandedServiceUUID
        super.init()
    }

    func start() {
        precondition(Thread.isMainThread)
        guard !running else { return }
        running = true
        clearPublishedState()
        log("BLE 实验开始：先验证标准 HID GATT 服务能否注册；尚未确认 iPhone 接受键盘。")
        state(false, "BLE 实验：正在初始化")
        manager = CBPeripheralManager(delegate: self, queue: .main,
                                      options: [CBPeripheralManagerOptionShowPowerAlertKey: true])
    }

    func stop() {
        precondition(Thread.isMainThread)
        guard running || manager != nil else { return }
        // Clear unsent typing before the best-effort release. CoreBluetooth does
        // not expose delivery acknowledgement or cancellation of submitted data.
        cancelPendingInput()
        running = false
        if let manager {
            manager.delegate = nil
            if manager.state == .poweredOn {
                manager.stopAdvertising()
                manager.removeAllServices()
            }
        }
        manager = nil
        clearPublishedState()
        state(false, "BLE 实验：已停止")
    }

    /// A peripheral cannot actively connect to a central by Classic address.
    /// This keeps the existing transport-facing interface source-compatible.
    func connect(address: String) {
        precondition(Thread.isMainThread)
        if !running { start() }
        log("BLE 实验采用 iPhone 主动连接；Classic 蓝牙地址不用于 BLE 连接。")
    }

    @discardableResult
    func sendReport(modifiers: UInt8, keys: [UInt8]) -> Bool {
        precondition(Thread.isMainThread)
        guard running, isConnected, !suspended, let manager,
              manager.state == .poweredOn, selectedInputCharacteristic != nil,
              selectedSubscriber != nil else {
            pendingInput.cancel()
            return false
        }
        var report = [UInt8](repeating: 0, count: 8)
        report[0] = modifiers
        let unique = Array(Set(keys.filter { $0 != 0 })).sorted()
        if unique.count > 6 {
            for index in 2..<8 { report[index] = 0x01 }
        } else {
            for (index, usage) in unique.enumerated() { report[index + 2] = usage }
        }
        let data = Data(report)
        guard pendingInput.enqueue(data) else {
            log("BLE 实验：待发报告超过有界队列上限；已取消待发输入，仅保留释放，停止本次输入。")
            flushPendingInput()
            return false
        }
        flushPendingInput()
        // Accepted by this bounded transport FIFO. This is not a delivery ack.
        return true
    }

    /// Cancels all reports that CoreBluetooth has not accepted yet, then submits
    /// a release before any future input. A normal zero key-up uses sendReport
    /// instead, preserving the press/release sequence already queued.
    func cancelPendingInput() {
        precondition(Thread.isMainThread)
        pendingInput.cancel()
        flushPendingInput()
    }

    private func flushPendingInput() {
        guard !flushingInput, running, isConnected, !suspended, let manager,
              manager.state == .poweredOn, let characteristic = selectedInputCharacteristic,
              let central = selectedSubscriber else { return }
        flushingInput = true
        defer { flushingInput = false }
        while let report = pendingInput.nextReport {
            guard manager.updateValue(report, for: characteristic, onSubscribedCentrals: [central]) else {
                if !observedBackpressure {
                    observedBackpressure = true
                    log("BLE 实验：蓝牙发送暂缓，报告已按顺序进入有界队列；停止输入会取消未发内容。")
                }
                return
            }
            lastInputReport = report
            pendingInput.didSubmitNext()
        }
        if observedBackpressure {
            observedBackpressure = false
            log("BLE 实验：蓝牙发送恢复，待发报告已按顺序提交。")
        }
    }

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        precondition(Thread.isMainThread)
        guard peripheral === manager, running else { return }
        switch peripheral.state {
        case .poweredOn:
            if hidService == nil { publishHIDService(peripheral) }
        case .poweredOff:
            clearPublishedState()
            state(false, "BLE 实验：蓝牙已关闭")
        case .unauthorized:
            clearPublishedState()
            state(false, "BLE 实验：蓝牙权限未允许")
        case .unsupported:
            clearPublishedState()
            state(false, "BLE 实验：系统不支持 BLE peripheral")
        case .resetting:
            clearPublishedState()
            state(false, "BLE 实验：系统蓝牙正在重置")
        default:
            state(false, "BLE 实验：等待系统蓝牙状态")
        }
    }

    private func publishHIDService(_ peripheral: CBPeripheralManager) {
        precondition(Self.reportDescriptor.count == 63)
        func standardServiceUUID(_ short: String) -> CBUUID {
            CBUUID(string: expandedServiceUUID ? "0000\(short)-0000-1000-8000-00805F9B34FB" : short)
        }
        let serviceUUID = standardServiceUUID("1812")
        let service = CBMutableService(type: serviceUUID, primary: true)
        let battery = CBMutableService(type: standardServiceUUID("180F"), primary: true)
        let deviceInformation = CBMutableService(type: standardServiceUUID("180A"), primary: true)
        let encryptedRead: CBAttributePermissions = [.readEncryptionRequired]
        let encryptedReadWrite: CBAttributePermissions = [.readEncryptionRequired, .writeEncryptionRequired]
        let notifying: CBCharacteristicProperties = [.read, .notify, .notifyEncryptionRequired]
        func characteristic(_ uuid: String, properties: CBCharacteristicProperties,
                            permissions: CBAttributePermissions) -> CBMutableCharacteristic {
            // A non-nil cached value forces .readable in CoreBluetooth. All values
            // are dynamic so that encryption-required permissions remain intact.
            CBMutableCharacteristic(type: CBUUID(string: uuid), properties: properties,
                                    value: nil, permissions: permissions)
        }
        let info = characteristic("2A4A", properties: [.read], permissions: encryptedRead)
        let map = characteristic("2A4B", properties: [.read], permissions: encryptedRead)
        let mode = characteristic("2A4E", properties: [.read, .writeWithoutResponse], permissions: encryptedReadWrite)
        let control = characteristic("2A4C", properties: [.writeWithoutResponse], permissions: [.writeEncryptionRequired])
        let input = characteristic("2A4D", properties: notifying, permissions: encryptedRead)
        let output = characteristic("2A4D", properties: [.read, .write, .writeWithoutResponse], permissions: encryptedReadWrite)
        let bootInput = characteristic("2A22", properties: notifying, permissions: encryptedRead)
        let bootOutput = characteristic("2A32", properties: [.read, .write, .writeWithoutResponse], permissions: encryptedReadWrite)
        let level = characteristic("2A19", properties: notifying, permissions: encryptedRead)
        let identity = characteristic("2A50", properties: [.read], permissions: encryptedRead)
        // Report ID is zero because this map has no Report ID item. Report Type
        // is one for input and two for output. CCCDs are managed by CoreBluetooth.
        input.descriptors = [CBMutableDescriptor(type: CBUUID(string: "2908"), value: Data([0, 1]))]
        output.descriptors = [CBMutableDescriptor(type: CBUUID(string: "2908"), value: Data([0, 2]))]
        service.characteristics = [info, map, mode, control, input, output, bootInput, bootOutput]
        battery.characteristics = [level]
        deviceInformation.characteristics = [identity]
        hidService = service
        mandatoryServices = [service, battery, deviceInformation]
        registeredServices.removeAll()
        failedServices.removeAll()
        batteryLevel = level
        pnpID = identity
        hidInformation = info
        reportMap = map
        protocolModeCharacteristic = mode
        controlPoint = control
        inputReport = input
        outputReport = output
        bootInputReport = bootInput
        bootOutputReport = bootOutput
        log("BLE 实验：注册 HID、Battery、Device Information 三项必需服务；macOS 可能保留并拒绝标准服务。")
        log("BLE 实验：Battery 为固定测试占位值；PnP 使用未分配实验标识，未声明任何已注册厂商身份。")
        for requiredService in mandatoryServices {
            log("BLE 实验：尝试注册服务 \(requiredService.uuid.uuidString)，UUID 长度 \(requiredService.uuid.data.count) 字节。")
            peripheral.add(requiredService)
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        guard peripheral === manager, running,
              let required = mandatoryServices.first(where: { $0 === service }) else { return }
        let identifier = ObjectIdentifier(required)
        if let error {
            failedServices.insert(identifier)
            serviceRegistrationSucceeded = false
            log("BLE 实验：服务 \(service.uuid.uuidString) 注册被系统拒绝：\(describe(error))")
            state(false, "BLE 实验：必需服务注册失败，不启动广播")
            return
        }
        registeredServices.insert(identifier)
        log("BLE 实验：服务 \(service.uuid.uuidString) 注册回调成功（\(registeredServices.count)/\(mandatoryServices.count)）。")
        guard failedServices.isEmpty, registeredServices.count == mandatoryServices.count,
              !serviceRegistrationSucceeded else { return }
        serviceRegistrationSucceeded = true
        log("BLE 实验：三项必需 GATT 服务均注册成功；不代表 iPhone 已识别或接受键盘。")
        log("BLE 实验：广告使用短 HID UUID 1812 和短名称 MacKeys；GATT 服务保留本次注册的 UUID 表达。")
        state(false, "BLE 实验：服务已注册，正在广播")
        peripheral.startAdvertising([CBAdvertisementDataLocalNameKey: hostName,
                                     CBAdvertisementDataServiceUUIDsKey: [CBUUID(string: "1812")]])
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        guard peripheral === manager, running, serviceRegistrationSucceeded else { return }
        if let error {
            log("BLE 实验：广播启动失败：\(describe(error))")
            state(false, "BLE 实验：广播失败")
        } else {
            log("BLE 实验：广播启动回调成功，等待 iPhone 加密订阅输入报告；尚未确认手机输入。")
            if !isConnected { state(false, "BLE 实验：等待 iPhone 订阅键盘") }
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral,
                           didSubscribeTo characteristic: CBCharacteristic) {
        guard peripheral === manager, running else { return }
        if characteristic === batteryLevel {
            log("BLE 实验：主机订阅 Battery 通知；此项不视为键盘连接。")
            if let batteryLevel {
                _ = peripheral.updateValue(Data([100]), for: batteryLevel, onSubscribedCentrals: [central])
            }
            return
        }
        if characteristic === inputReport { reportSubscribers[central.identifier] = central }
        else if characteristic === bootInputReport { bootSubscribers[central.identifier] = central }
        else { return }
        if selectedCentralID == nil {
            pendingInput.cancel()
            selectedCentralID = central.identifier
        }
        guard selectedCentralID == central.identifier else {
            log("BLE 实验：另一台 central 订阅输入；本实验只向首先订阅的设备发送。")
            return
        }
        log("BLE 实验：收到加密输入通知订阅（\(characteristic.uuid.uuidString)）；仍需查看 iPhone 实际文字。")
        let wasConnected = isConnected
        updateConnectionState()
        if isConnected && !wasConnected { cancelPendingInput() }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral,
                           didUnsubscribeFrom characteristic: CBCharacteristic) {
        guard peripheral === manager, running else { return }
        let affectsCurrentInput = selectedCentralID == central.identifier && characteristic === selectedInputCharacteristic
        if affectsCurrentInput { pendingInput.cancel() }
        if characteristic === inputReport { reportSubscribers.removeValue(forKey: central.identifier) }
        else if characteristic === bootInputReport { bootSubscribers.removeValue(forKey: central.identifier) }
        else { return }
        if selectedCentralID == central.identifier,
           reportSubscribers[central.identifier] == nil, bootSubscribers[central.identifier] == nil {
            selectedCentralID = nil
            pendingInput.cancel()
            observedBackpressure = false
            protocolMode = 1
            suspended = false
            log("BLE 实验：输入报告订阅已解除。")
        }
        updateConnectionState()
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        guard peripheral === manager, running else { return }
        logFirstTransaction("读", characteristic: request.characteristic)
        let data: Data
        if request.characteristic === batteryLevel { data = Data([100]) }
        else if request.characteristic === pnpID { data = Self.experimentalPnPID }
        else if request.characteristic === hidInformation { data = Data([0x11, 0x01, 0x00, 0x02]) }
        else if request.characteristic === reportMap { data = Self.reportDescriptor }
        else if request.characteristic === protocolModeCharacteristic { data = Data([protocolMode]) }
        else if request.characteristic === inputReport || request.characteristic === bootInputReport { data = lastInputReport }
        else if request.characteristic === outputReport || request.characteristic === bootOutputReport { data = Data([outputLEDs]) }
        else { peripheral.respond(to: request, withResult: .readNotPermitted); return }
        guard request.offset >= 0, request.offset <= data.count else {
            peripheral.respond(to: request, withResult: .invalidOffset)
            return
        }
        request.value = Data(data.dropFirst(request.offset))
        peripheral.respond(to: request, withResult: .success)
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        guard peripheral === manager, running, let first = requests.first else { return }
        for request in requests { logFirstTransaction("写", characteristic: request.characteristic) }
        // Validate the complete batch before changing state. Respond once, using
        // the first request, as required by the CoreBluetooth batch-write API.
        for request in requests {
            if let selectedCentralID, request.central.identifier != selectedCentralID {
                peripheral.respond(to: first, withResult: .insufficientAuthorization); return
            }
            guard request.offset == 0 else { peripheral.respond(to: first, withResult: .invalidOffset); return }
            guard let value = request.value, value.count == 1 else {
                peripheral.respond(to: first, withResult: .invalidAttributeValueLength); return
            }
            if request.characteristic === protocolModeCharacteristic || request.characteristic === controlPoint {
                guard value[0] <= 1 else { peripheral.respond(to: first, withResult: .unlikelyError); return }
            } else if request.characteristic !== outputReport && request.characteristic !== bootOutputReport {
                peripheral.respond(to: first, withResult: .writeNotPermitted); return
            }
        }
        for request in requests {
            let value = request.value![0]
            if request.characteristic === protocolModeCharacteristic {
                // Cancel unsent text and release the old path before changing
                // protocol. A false state stops the UI's existing capture session.
                if protocolMode != value {
                    cancelPendingInput()
                    state(false, "BLE 实验：主机切换协议，已停止当前输入")
                    pendingInput.cancel()
                    observedBackpressure = false
                }
                protocolMode = value
                log("BLE 实验：主机选择 \(value == 0 ? "Boot" : "Report") 协议。")
                updateConnectionState()
                flushPendingInput()
            } else if request.characteristic === controlPoint {
                if value == 0 { cancelPendingInput() }
                suspended = value == 0
                log("BLE 实验：主机\(suspended ? "暂停" : "恢复") HID。")
                updateConnectionState()
                if isConnected { cancelPendingInput() }
            } else {
                outputLEDs = value & 0x1F
            }
        }
        peripheral.respond(to: first, withResult: .success)
    }

    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        guard peripheral === manager, running else { return }
        flushPendingInput()
    }

    private var selectedInputCharacteristic: CBMutableCharacteristic? {
        protocolMode == 0 ? bootInputReport : inputReport
    }

    private var selectedSubscriber: CBCentral? {
        guard let selectedCentralID else { return nil }
        return protocolMode == 0 ? bootSubscribers[selectedCentralID] : reportSubscribers[selectedCentralID]
    }

    private func updateConnectionState() {
        let connected = running && serviceRegistrationSucceeded && selectedSubscriber != nil && !suspended
        if !connected {
            pendingInput.cancel()
            observedBackpressure = false
        }
        if connected {
            state(true, "BLE 实验：输入报告已订阅，待验证 iPhone 文字")
        } else {
            state(false, suspended ? "BLE 实验：主机已暂停输入" : "BLE 实验：等待当前协议的输入订阅")
        }
    }

    private func resetInputState() {
        protocolMode = 1
        suspended = false
        outputLEDs = 0
        lastInputReport = Data(repeating: 0, count: 8)
        reportSubscribers.removeAll()
        bootSubscribers.removeAll()
        selectedCentralID = nil
        pendingInput.cancel()
        observedBackpressure = false
    }

    private func clearPublishedState() {
        serviceRegistrationSucceeded = false
        hidService = nil
        mandatoryServices.removeAll()
        registeredServices.removeAll()
        failedServices.removeAll()
        batteryLevel = nil
        pnpID = nil
        loggedReadUUIDs.removeAll()
        loggedWriteUUIDs.removeAll()
        resetInputState()
    }

    private func logFirstTransaction(_ operation: String, characteristic: CBCharacteristic) {
        let uuid = characteristic.uuid.uuidString
        let first: Bool
        if operation == "读" { first = loggedReadUUIDs.insert(uuid).inserted }
        else { first = loggedWriteUUIDs.insert(uuid).inserted }
        if first { log("BLE 实验：首次收到 GATT \(operation)事务，特征 UUID \(uuid)；不记录内容。") }
    }

    private func log(_ message: String) { onLog?(message) }
    private func state(_ connected: Bool, _ message: String) {
        isConnected = connected
        onStateChange?(connected, message)
    }
    private func describe(_ error: Error) -> String {
        let value = error as NSError
        return "\(value.domain) / \(value.code)：\(value.localizedDescription)"
    }
}
