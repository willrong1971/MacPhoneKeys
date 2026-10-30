import Foundation

/// Export a deliberately smaller report than the private, local diagnostic log.
/// Unknown fields and free-form log messages never cross this boundary.
enum DiagnosticReportBuilder {
    static func make(snapshot: [String: Any], logLines: [String],
                     version: String, systemVersion: String, architecture: String,
                     generatedAt: Date = Date()) -> [String: Any] {
        var state: [String: Any] = [:]
        for key in ["started", "connected", "capturing", "phoneTextVerifiedByApp",
                    "phoneTextVerifiedByUser", "shortcutRegistered", "capturePending",
                    "settingsVisible", "showsInputHint", "hintWindowVisible", "inputPanelKey"] {
            if let value = snapshot[key] as? Bool { state[key] = value }
        }
        for key in ["acceptedKeyPresses", "transportMode", "runningInstanceCount"] {
            if let value = nonnegativeInteger(snapshot[key]) { state[key] = value }
        }
        var transport: [String: Any] = [:]
        if let ble = snapshot["ble"] as? [String: Any] {
            let phases: Set<String> = ["stopped", "waitingForRadio", "registering", "advertising", "ready", "recovering", "failed"]
            let radioStates: Set<String> = ["unknown", "resetting", "unsupported", "unauthorized", "poweredOff", "poweredOn"]
            if let phase = ble["phase"] as? String, phases.contains(phase) { transport["phase"] = phase }
            if let radio = ble["radioState"] as? String, radioStates.contains(radio) { transport["radioState"] = radio }
            for key in ["isAdvertising", "running", "inputReady"] {
                if let value = ble[key] as? Bool { transport[key] = value }
            }
            for key in ["registeredServiceCount", "requiredServiceCount", "reportSubscriberCount",
                        "bootSubscriberCount", "recoveryAttempt", "recoveryLimit", "generation",
                        "queueDepth", "submittedReportCount", "enqueuedReportCount", "releaseSubmissionCount",
                        "cancelledQueuedReportCount", "overflowCount", "serviceCleanupCount", "recoveryCount",
                        "readTransactionCount", "writeTransactionCount", "subscriptionEventCount", "unsubscriptionEventCount"] {
                if let value = nonnegativeInteger(ble[key]) { transport[key] = value }
            }
            if let authorization = ble["authorization"] as? String,
               ["allowedAlways", "denied", "restricted", "notDetermined", "preview"].contains(authorization) {
                transport["authorization"] = authorization
            }
            if let failure = ble["lastFailure"] as? String,
               ["registration", "registrationTimeout", "advertising", "advertisingTimeout"].contains(failure) {
                transport["lastFailure"] = failure
            }
        }
        var assistant: [String: String] = [:]
        if let flow = snapshot["pairingAssistant"] as? [String: Any] {
            if let panel = flow["systemPairingPanel"] as? String,
               ["notOpened", "open", "cancelled", "selectionPaired", "failed"].contains(panel) { assistant["systemPairingPanel"] = panel }
            if let verification = flow["phoneTextVerification"] as? String,
               ["notTested", "sending", "awaitingUser", "visibleByUser", "notVisibleByUser"].contains(verification) { assistant["phoneTextVerification"] = verification }
        }
        let recent = Array(logLines.suffix(300))
        let events = recent.compactMap(event).suffix(100)
        return [
            "schemaVersion": 1,
            "generatedAt": ISO8601DateFormatter().string(from: generatedAt),
            "appVersion": safeVersion(version),
            "systemVersion": safeVersion(systemVersion),
            "architecture": ["arm64", "x86_64"].contains(architecture) ? architecture : "unknown",
            "state": state,
            "transport": transport,
            "connectionAssistant": assistant,
            "recentEvents": Array(events),
            "omittedUnclassifiedLogLines": recent.filter { event($0) == nil }.count,
            "privacy": ["containsInputContent": false, "containsDeviceIdentifiers": false,
                        "containsRawLogMessages": false],
            "verificationNote": "Only a user can confirm that text appeared on the iPhone. A subscription or report count is not delivery confirmation."
        ]
    }

    private static func nonnegativeInteger(_ value: Any?) -> Int? {
        guard let value, !(value is Bool), let number = value as? Int,
              (0...1_000_000_000).contains(number) else { return nil }
        return number
    }

    private static func safeVersion(_ value: String) -> String {
        guard value.range(of: #"^\d+(?:\.\d+){0,3}(?: \(\d+\))?$"#, options: .regularExpression) != nil else { return "unknown" }
        return value
    }

    private static func event(_ line: String) -> [String: String]? {
        // Classify only; never copy the remainder, even after redaction.
        let text = line.lowercased()
        let categories: [(String, [String])] = [
            ("phoneTextConfirmedByUser", ["手机文字已由用户确认", "用户确认手机完整显示", "phone text confirmed by user", "the user confirmed that the full test text appeared", "手機文字已由使用者確認"]),
            ("captureStopped", ["已停止键盘输入", "keyboard input stopped", "input stopped; key release requested", "已停止鍵盤輸入"]),
            ("serviceStopped", ["ble 实验：已停止", "ble experiment: stopped", "ble test: stopped", "ble 實驗：已停止", "service stopped"]),
            ("captureStarted", ["开始前台键盘输入", "foreground keyboard input started", "foreground input started", "開始前景鍵盤輸入"]),
            ("radioUnavailable", ["蓝牙已关闭", "蓝牙权限未允许", "bluetooth is off", "bluetooth permission", "藍牙已關閉"]),
            ("inputSubscribed", ["收到加密输入通知订阅", "received an encrypted input notification subscription", "收到加密輸入通知訂閱"]),
            ("inputUnsubscribed", ["订阅已解除", "unsubscribed", "input report subscription removed", "訂閱已解除"]),
            ("serviceRegistrationFailed", ["注册被系统拒绝", "registration failed", "註冊被系統拒絕"]),
            ("serviceRegistrationTimedOut", ["服务注册超时", "service registration timed out", "服務註冊逾時"]),
            ("serviceRegistered", ["注册回调成功", "registration callback succeeded", "registration succeeded", "註冊回呼成功"]),
            ("advertisingFailed", ["广播失败", "广播启动失败", "advertising failed", "廣播失敗"]),
            ("advertisingTimedOut", ["广播启动超时", "advertising startup timed out", "廣播啟動逾時"]),
            ("advertisingStarted", ["广播启动回调成功", "advertising started", "廣播啟動回呼成功"]),
            ("serviceRecovery", ["恢复蓝牙服务", "recovering bluetooth", "manual recovery of this app", "recovering this app's service", "恢復藍牙服務", "恢复尝试", "recovery attempt"]),
            ("pairingPanel", ["系统配对", "system pairing", "系統配對"]),
            ("appStarted", ["启动；仅记录", "started; logs", "started; only connection events", "啟動；僅記錄"])
        ]
        guard let category = categories.first(where: { _, patterns in patterns.contains { text.contains($0) } })?.0 else { return nil }
        var result = ["event": category]
        if let range = line.range(of: #"^\[(?:\d{4}-\d{2}-\d{2} )?\d{2}:\d{2}:\d{2}(?: [+-]\d{2}:\d{2}| Z)?\]"#, options: .regularExpression) {
            result["localTime"] = String(line[range].dropFirst().dropLast())
        }
        return result
    }
}
