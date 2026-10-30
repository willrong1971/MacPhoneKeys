import Foundation

@main
struct DiagnosticReportTests {
    static func main() throws {
        let snapshot: [String: Any] = [
            "connected": true, "started": true, "phoneTextVerifiedByApp": false,
            "phoneTextVerifiedByUser": true, "acceptedKeyPresses": 37, "runningInstanceCount": 1,
            "status": "secret-status user@example.com", "deviceName": "private-iPhone",
            "address": "AA:BB:CC:DD:EE:FF", "privateKey": "private-key",
            "ble": ["phase": "ready", "radioState": "poweredOn", "isAdvertising": true,
                    "reportSubscriberCount": 1, "generation": 3, "centralID": "secret-uuid",
                    "lastInputReport": [4, 5, 6], "authorization": "allowedAlways"]
        ]
        let report = DiagnosticReportBuilder.make(snapshot: snapshot, logLines: [
            "[2026-10-30 12:00:00 +08:00] BLE 实验：收到加密输入通知订阅（2A4D）； private-iPhone AA:BB:CC:DD:EE:FF",
            "[12:00:01] 系统配对 privateKey=private-key user@example.com /Users/private/file",
            "unrecognized message with typed-password and secret-uuid"
        ], version: "0.6.0 (9)", systemVersion: "26.6.2", architecture: "arm64", generatedAt: Date(timeIntervalSince1970: 0))
        let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
        let text = String(decoding: data, as: UTF8.self)
        for secret in ["secret-status", "user@example.com", "private-iPhone", "AA:BB:CC:DD:EE:FF", "private-key", "secret-uuid", "lastInputReport", "typed-password", "/Users/private"] {
            precondition(!text.contains(secret), "Export leaked \(secret)")
        }
        let state = report["state"] as! [String: Any]
        precondition(state["acceptedKeyPresses"] as? Int == 37)
        precondition(state["phoneTextVerifiedByApp"] as? Bool == false)
        precondition(state["phoneTextVerifiedByUser"] as? Bool == true)
        let transport = report["transport"] as! [String: Any]
        precondition(transport["phase"] as? String == "ready")
        precondition(transport["centralID"] == nil)
        precondition((report["recentEvents"] as! [[String: String]]).count == 2)
        precondition(report["omittedUnclassifiedLogLines"] as? Int == 1)
        precondition(report["generatedAt"] as? String == "1970-01-01T00:00:00Z")
        let untrusted = DiagnosticReportBuilder.make(snapshot: ["acceptedKeyPresses": -1, "transportMode": true,
            "ble": ["phase": "secret-state", "radioState": "private-radio", "generation": -2]],
            logLines: [], version: "private-version", systemVersion: "/Users/private", architecture: "secret-arch")
        precondition((untrusted["state"] as! [String: Any]).isEmpty)
        precondition((untrusted["transport"] as! [String: Any]).isEmpty)
        precondition(untrusted["appVersion"] as? String == "unknown")
        precondition(untrusted["architecture"] as? String == "unknown")
        let many = DiagnosticReportBuilder.make(snapshot: [:], logLines: Array(repeating: "[12:00:00] 系统配对 secret", count: 1_000), version: "0", systemVersion: "0", architecture: "x86_64")
        precondition((many["recentEvents"] as! [[String: String]]).count == 100)
        let english = DiagnosticReportBuilder.make(snapshot: [:], logLines: [
            "BLE test: advertising started; waiting for the iPhone to subscribe to encrypted input reports. Phone-side input is not yet verified.",
            "BLE test: received an encrypted input notification subscription (2A4D); text on the iPhone still needs verification.",
            "Input stopped; key release requested.",
            "BLE test: Stopped"
        ], version: "0.6.0", systemVersion: "26.6.2", architecture: "arm64")
        let categories = (english["recentEvents"] as! [[String: String]]).map { $0["event"]! }
        precondition(categories == ["advertisingStarted", "inputSubscribed", "captureStopped", "serviceStopped"],
                     "English advertising/capture events must not invent a keyboard subscription or service stop")
        print("Diagnostic privacy, confirmation boundaries, invalid inputs, and bounded export: passed")
    }
}
