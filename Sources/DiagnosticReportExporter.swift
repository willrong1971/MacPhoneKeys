import AppKit
import UniformTypeIdentifiers

enum DiagnosticReportExporter {
    static func export(snapshot: [String: Any], logLines: [String], presentationWindow: NSWindow?) {
        precondition(Thread.isMainThread)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        #if arch(arm64)
        let architecture = "arm64"
        #elseif arch(x86_64)
        let architecture = "x86_64"
        #else
        let architecture = "unknown"
        #endif
        let report = DiagnosticReportBuilder.make(snapshot: snapshot, logLines: logLines,
            version: "\(version) (\(build))", systemVersion: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)", architecture: architecture)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.title = L("保存诊断报告")
        panel.message = L("诊断报告仅包含系统版本和连接状态摘要，不包含设备名称、地址或输入内容。")
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        panel.nameFieldStringValue = "MacPhoneKeys-Diagnostics-\(formatter.string(from: Date())).json"
        let finish: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
            } catch {
                let alert = NSAlert()
                alert.messageText = L("无法保存诊断报告")
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
        if let presentationWindow, presentationWindow.isVisible, NSApp.modalWindow == nil {
            panel.beginSheetModal(for: presentationWindow, completionHandler: finish)
        } else {
            finish(panel.runModal())
        }
    }
}
