import Foundation

private struct StatusSignal: Sendable {
    let status: AssistantStatus
    let detail: String
}

private let statusStalledThreshold: TimeInterval = 20 * 60

@MainActor
final class ProgressMonitor {
    var onActivity: ((AssistantActivity?) -> Void)?

    private let settings: SettingsStore
    private var timer: Timer?
    private var monitoringObserver: NSObjectProtocol?
    private var lastActivity: AssistantActivity?
    private var lastEmittedKey = ""
    private var lastEmittedAt = Date.distantPast
    private var isPolling = false
    private let sameTaskCooldown: TimeInterval = 120
    private let home = FileManager.default.homeDirectoryForCurrentUser

    init(settings: SettingsStore) {
        self.settings = settings
        monitoringObserver = NotificationCenter.default.addObserver(
            forName: SettingsStore.monitoringDidChange,
            object: settings,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.resetAndPoll()
            }
        }
    }

    func start() {
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.poll()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        poll()
    }

    private func poll() {
        guard isPolling == false else { return }
        isPolling = true

        let home = home
        let includeCodex = settings.monitorCodex
        let includeClaude = settings.monitorClaude

        guard includeCodex || includeClaude else {
            isPolling = false
            consume(nil)
            return
        }

        Task {
            let latest = await Task.detached(priority: .utility) {
                Self.readLatestActivity(
                    home: home,
                    includeCodex: includeCodex,
                    includeClaude: includeClaude
                )
            }.value

            isPolling = false
            consume(latest)
        }
    }

    private func resetAndPoll() {
        lastEmittedKey = ""
        lastEmittedAt = .distantPast
        poll()
    }

    private func consume(_ latest: AssistantActivity?) {
        lastActivity = latest

        guard shouldEmit(latest) else {
            return
        }
        onActivity?(latest)
    }

    private func shouldEmit(_ activity: AssistantActivity?) -> Bool {
        guard let activity else {
            return false
        }

        let key = "\(activity.source)|\(activity.projectName)|\(activity.path)|\(activity.status.rawValue)|\(activity.detail)"
        let isImportant: Bool
        switch activity.status {
        case .waiting, .failed, .completed, .stalled:
            isImportant = true
        case .thinking, .running:
            isImportant = false
        }

        if key != lastEmittedKey {
            lastEmittedKey = key
            lastEmittedAt = Date()
            return true
        }

        if isImportant && Date().timeIntervalSince(lastEmittedAt) >= sameTaskCooldown {
            lastEmittedAt = Date()
            return true
        }

        return false
    }

    nonisolated private static func readLatestActivity(
        home: URL,
        includeCodex: Bool,
        includeClaude: Bool
    ) -> AssistantActivity? {
        let activities = [
            includeCodex ? readCodexActivity(home: home) : nil,
            includeClaude ? readClaudeActivity(home: home) : nil
        ].compactMap { $0 }
        return activities.max(by: { $0.updatedAt < $1.updatedAt })
    }

    nonisolated private static func readCodexActivity(home: URL) -> AssistantActivity? {
        let db = home.appendingPathComponent(".codex/state_5.sqlite").path
        if FileManager.default.fileExists(atPath: db) {
            let query = "select id,title,cwd,updated_at,rollout_path,coalesce(model,''),coalesce(preview,'') from threads order by updated_at desc limit 1;"
            if let output = run("/usr/bin/sqlite3", arguments: ["-separator", "\t", db, query]) {
                let parts = output.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\t")
                if parts.count >= 5, let seconds = TimeInterval(parts[3]) {
                    let threadTitle = codexThreadName(home: home, id: parts[0]) ?? parts[1]
                    let updatedAt = Date(timeIntervalSince1970: seconds)
                    let fallbackDetail = normalizeDetail(parts.dropFirst(5).joined(separator: " "))
                    let signal = latestCodexStatus(rolloutPath: parts[4])
                    let status = statusWithStall(
                        signal?.status ?? inferStatus(detail: fallbackDetail, defaultStatus: .thinking),
                        updatedAt: updatedAt
                    )
                    let detail = signal?.detail ?? fallbackDetail
                    return AssistantActivity(
                        source: "Codex",
                        projectName: projectDisplayName(path: parts[2], title: threadTitle),
                        title: threadTitle,
                        path: parts[2],
                        updatedAt: updatedAt,
                        detail: detail.isEmpty ? "Codex thread updated" : detail,
                        status: status
                    )
                }
            }
        }
        return readCodexSessionIndex(home: home)
    }

    nonisolated private static func readCodexSessionIndex(home: URL) -> AssistantActivity? {
        let url = home.appendingPathComponent(".codex/session_index.jsonl")
        guard let line = tailLines(url: url, maxLines: 1).last,
              let object = parseJSONLine(line),
              let title = object["thread_name"] as? String,
              let updated = object["updated_at"] as? String,
              let date = ISO8601DateFormatter().date(from: updated) else {
            return nil
        }
        return AssistantActivity(
            source: "Codex",
            projectName: title,
            title: title,
            path: "",
            updatedAt: date,
            detail: "Codex session index updated",
            status: statusWithStall(.thinking, updatedAt: date)
        )
    }

    nonisolated private static func readClaudeActivity(home: URL) -> AssistantActivity? {
        let projects = home.appendingPathComponent(".claude/projects")
        guard let latest = newestFile(under: projects, extensionName: "jsonl") else {
            return nil
        }

        let lines = tailLines(url: latest, maxLines: 120)
        var title = latest.deletingPathExtension().lastPathComponent
        var cwd = ""
        var timestamp: Date?

        for line in lines {
            guard let object = parseJSONLine(line) else { continue }
            if let aiTitle = object["aiTitle"] as? String {
                title = aiTitle
            }
            if let foundCwd = object["cwd"] as? String {
                cwd = foundCwd
            }
            if let raw = object["timestamp"] as? String,
               let date = ISO8601DateFormatter().date(from: raw) {
                timestamp = date
            } else if let raw = object["timestamp"] as? TimeInterval {
                timestamp = Date(timeIntervalSince1970: raw)
            }
        }

        let updatedAt = timestamp ?? fileModificationDate(latest) ?? Date.distantPast
        let signal = latestClaudeStatus(lines: lines)
        let status = statusWithStall(signal?.status ?? .thinking, updatedAt: updatedAt)
        return AssistantActivity(
            source: "Claude",
            projectName: projectDisplayName(path: cwd, title: title),
            title: title,
            path: cwd,
            updatedAt: updatedAt,
            detail: signal?.detail ?? "Claude activity updated",
            status: status
        )
    }

    nonisolated private static func latestCodexStatus(rolloutPath: String) -> StatusSignal? {
        guard rolloutPath.isEmpty == false else { return nil }

        let lines = tailLines(url: URL(fileURLWithPath: rolloutPath), maxLines: 120)
        for line in lines.reversed() {
            guard let object = parseJSONLine(line) else { continue }

            if let signal = notificationSignal(in: object, source: "Codex") {
                return signal
            }

            guard let type = (object["type"] as? String) ?? (object["event"] as? String) else { continue }
            if type == "event_msg",
               let payload = object["payload"] as? [String: Any],
               let payloadType = payload["type"] as? String,
               let signal = codexEventSignal(type: payloadType, payload: payload) {
                return signal
            }

            if type == "response_item",
               let payload = object["payload"] as? [String: Any],
               let signal = codexResponseSignal(payload: payload) {
                return signal
            }

            if let signal = codexLegacyEventSignal(type: type, object: object) {
                return signal
            }
        }
        return nil
    }

    nonisolated private static func codexEventSignal(type: String, payload: [String: Any]) -> StatusSignal? {
        switch type {
        case "task_complete":
            return StatusSignal(status: .completed, detail: "Codex 当前回合已完成")
        case "task_started", "user_message":
            return StatusSignal(status: .thinking, detail: "Codex 收到新需求，正在思考")
        case "agent_message":
            let phase = payload["phase"] as? String ?? ""
            let message = normalizeDetail(payload["message"] as? String ?? "")
            if phase == "final_answer" {
                return StatusSignal(status: .completed, detail: message.isEmpty ? "Codex 回复完成" : message)
            }
            if containsFailure(message) {
                return StatusSignal(status: .failed, detail: message)
            }
            if containsWaiting(message) {
                return StatusSignal(status: .waiting, detail: message)
            }
            return StatusSignal(status: .thinking, detail: message.isEmpty ? "Codex 正在整理回复" : message)
        default:
            return nil
        }
    }

    nonisolated private static func codexResponseSignal(payload: [String: Any]) -> StatusSignal? {
        guard let type = payload["type"] as? String else { return nil }

        switch type {
        case "function_call":
            let name = payload["name"] as? String ?? "tool"
            if isWaitingTool(name) {
                return StatusSignal(status: .waiting, detail: "Codex 正在等你确认")
            }
            return StatusSignal(status: .running, detail: "Codex 正在执行 \(friendlyToolName(name))")
        case "function_call_output":
            let output = normalizeDetail(payload["output"] as? String ?? "")
            if commandExitedSuccessfully(output) {
                return StatusSignal(status: .thinking, detail: "Codex 命令已返回，正在整理结果")
            }
            if commandExitedWithFailure(output) || containsFailure(output) {
                return StatusSignal(status: .failed, detail: output.isEmpty ? "Codex 命令执行出错" : output)
            }
            if containsWaiting(output) {
                return StatusSignal(status: .waiting, detail: output.isEmpty ? "Codex 正在等你确认" : output)
            }
            return StatusSignal(status: .thinking, detail: "Codex 命令已返回，正在整理结果")
        case "reasoning":
            return StatusSignal(status: .thinking, detail: "Codex 正在思考")
        case "message":
            let phase = payload["phase"] as? String ?? ""
            let message = codexMessageText(payload)
            if phase == "final_answer" {
                return StatusSignal(status: .completed, detail: message.isEmpty ? "Codex 回复完成" : message)
            }
            return StatusSignal(status: .thinking, detail: message.isEmpty ? "Codex 正在整理回复" : message)
        default:
            return nil
        }
    }

    nonisolated private static func codexLegacyEventSignal(type: String, object: [String: Any]) -> StatusSignal? {
        if type.contains("exec_command_begin") || type.contains("commandExecution") {
            return StatusSignal(status: .running, detail: "Codex 正在执行命令")
        }
        if type.contains("exec_approval_request") || type.contains("approval_request") || type.contains("request_user_input") {
            return StatusSignal(status: .waiting, detail: "Codex 正在等你确认")
        }
        if type.contains("stream_error") || type == "error" || type.contains("/error") {
            let detail = normalizeDetail((object["message"] as? String) ?? (object["error"] as? String) ?? "Codex 出错")
            return StatusSignal(status: .failed, detail: detail)
        }
        if type.contains("task_complete") || type.contains("turn/completed") {
            return StatusSignal(status: .completed, detail: "Codex 当前回合已完成")
        }
        if type.contains("agent_message") {
            let detail = normalizeDetail((object["message"] as? String) ?? (object["delta"] as? String) ?? "Codex 正在回复")
            return StatusSignal(status: .thinking, detail: detail)
        }
        if type.contains("agent_reasoning") || type.contains("task_started") {
            return StatusSignal(status: .thinking, detail: "Codex 正在思考")
        }
        return nil
    }

    nonisolated private static func latestClaudeStatus(lines: [String]) -> StatusSignal? {
        for line in lines.reversed() {
            guard let object = parseJSONLine(line) else { continue }

            if let signal = notificationSignal(in: object, source: "Claude") {
                return signal
            }

            guard let type = object["type"] as? String else { continue }
            switch type {
            case "assistant":
                guard let message = object["message"] as? [String: Any] else { continue }
                let text = claudeMessageText(message)
                if messageHasToolUse(message) {
                    return StatusSignal(status: .running, detail: text.isEmpty ? "Claude 正在执行工具或命令" : text)
                }
                if messageHasThinking(message) {
                    return StatusSignal(status: .thinking, detail: "Claude 正在思考")
                }
                let stopReason = message["stop_reason"] as? String ?? ""
                if stopReason == "tool_use" {
                    return StatusSignal(status: .running, detail: text.isEmpty ? "Claude 正在执行工具或命令" : text)
                }
                if stopReason == "end_turn" {
                    return StatusSignal(status: .completed, detail: text.isEmpty ? "Claude 当前回合已完成" : text)
                }
                return StatusSignal(status: .thinking, detail: text.isEmpty ? "Claude 正在整理回复" : text)
            case "user":
                if let signal = claudeToolResultSignal(object) {
                    return signal
                }
                return StatusSignal(status: .thinking, detail: "Claude 收到新需求，正在思考")
            case "queue-operation":
                let operation = object["operation"] as? String ?? ""
                if operation == "enqueue" {
                    return StatusSignal(status: .running, detail: "Claude 后台任务已入队")
                }
            case "system":
                let subtype = object["subtype"] as? String ?? ""
                if subtype == "stop_hook_summary" {
                    return StatusSignal(status: .completed, detail: "Claude 当前回合已完成")
                }
            default:
                continue
            }
        }
        return nil
    }

    nonisolated private static func notificationSignal(in object: [String: Any], source: String) -> StatusSignal? {
        for content in notificationContents(in: object) where content.contains("<task-notification>") {
            let detail = taskNotificationSummary(from: content)
            return StatusSignal(
                status: inferStatus(detail: content, defaultStatus: .running),
                detail: detail.isEmpty ? "\(source) task notification" : detail
            )
        }
        return nil
    }

    nonisolated private static func notificationContents(in object: [String: Any]) -> [String] {
        var contents: [String] = []
        if let content = object["content"] as? String {
            contents.append(content)
        }
        if let message = object["message"] as? [String: Any] {
            if let content = message["content"] as? String {
                contents.append(content)
            }
            if let items = message["content"] as? [[String: Any]] {
                for item in items {
                    if let text = item["text"] as? String {
                        contents.append(text)
                    }
                }
            }
        }
        return contents
    }

    nonisolated private static func codexMessageText(_ payload: [String: Any]) -> String {
        guard let items = payload["content"] as? [[String: Any]] else {
            return ""
        }
        return normalizeDetail(
            items.compactMap { item in
                (item["text"] as? String) ?? (item["output_text"] as? String)
            }.joined(separator: " ")
        )
    }

    nonisolated private static func claudeMessageText(_ message: [String: Any]) -> String {
        if let content = message["content"] as? String {
            return normalizeDetail(content)
        }
        guard let items = message["content"] as? [[String: Any]] else {
            return ""
        }
        return normalizeDetail(
            items.compactMap { item in
                guard item["type"] as? String == "text" else { return nil }
                return item["text"] as? String
            }.joined(separator: " ")
        )
    }

    nonisolated private static func messageHasToolUse(_ message: [String: Any]) -> Bool {
        guard let items = message["content"] as? [[String: Any]] else {
            return false
        }
        return items.contains { item in
            item["type"] as? String == "tool_use"
        }
    }

    nonisolated private static func messageHasThinking(_ message: [String: Any]) -> Bool {
        guard let items = message["content"] as? [[String: Any]] else {
            return false
        }
        return items.contains { item in
            item["type"] as? String == "thinking"
        }
    }

    nonisolated private static func claudeToolResultSignal(_ object: [String: Any]) -> StatusSignal? {
        var text = ""
        var isHardError = false

        if let result = object["toolUseResult"] as? [String: Any] {
            if result["interrupted"] as? Bool == true {
                isHardError = true
            }
            if let stdout = result["stdout"] as? String {
                text += " \(stdout)"
            }
            if let stderr = result["stderr"] as? String {
                text += " \(stderr)"
            }
        }

        if let message = object["message"] as? [String: Any],
           let items = message["content"] as? [[String: Any]] {
            for item in items where item["type"] as? String == "tool_result" {
                if item["is_error"] as? Bool == true {
                    isHardError = true
                }
                if let content = item["content"] as? String {
                    text += " \(content)"
                }
            }
        }

        let detail = normalizeDetail(text)
        if isHardError || commandExitedWithFailure(detail) || containsFailure(detail) {
            return StatusSignal(status: .failed, detail: detail.isEmpty ? "Claude 命令执行出错" : detail)
        }
        return detail.isEmpty ? nil : StatusSignal(status: .thinking, detail: "Claude 命令已返回，正在整理结果")
    }

    nonisolated private static func inferStatus(detail: String, defaultStatus: AssistantStatus) -> AssistantStatus {
        let lower = detail.lowercased()
        if containsFailure(lower) {
            return .failed
        }
        if containsWaiting(lower) {
            return .waiting
        }
        if lower.contains("complete") || lower.contains("completed") || lower.contains("success") || lower.contains("finished") || lower.contains("done") {
            return .completed
        }
        if lower.contains("running") || lower.contains("command") || lower.contains("tool") || lower.contains("enqueue") {
            return .running
        }
        if lower.contains("review") || lower.contains("analysis") || lower.contains("thinking") || lower.contains("planning") {
            return .thinking
        }
        return defaultStatus
    }

    nonisolated private static func statusWithStall(_ status: AssistantStatus, updatedAt: Date) -> AssistantStatus {
        switch status {
        case .thinking, .running:
            return Date().timeIntervalSince(updatedAt) > statusStalledThreshold ? .stalled : status
        case .waiting, .failed, .completed, .stalled:
            return status
        }
    }

    nonisolated private static func containsFailure(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("killed")
            || lower.contains("error")
            || lower.contains("failed")
            || lower.contains("failure")
            || lower.contains("traceback")
            || lower.contains("uncaught")
            || lower.contains("process exited with code 1")
            || lower.contains("process exited with code 2")
            || lower.contains("exited with code 1")
            || lower.contains("exited with code 2")
    }

    nonisolated private static func commandExitedSuccessfully(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("process exited with code 0") || lower.contains("exited with code 0")
    }

    nonisolated private static func commandExitedWithFailure(_ text: String) -> Bool {
        let lower = text.lowercased()
        guard lower.contains("exited with code") else { return false }
        return commandExitedSuccessfully(lower) == false
    }

    nonisolated private static func containsWaiting(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("waiting for user")
            || lower.contains("approval")
            || lower.contains("confirm")
            || lower.contains("confirmation")
            || lower.contains("permission request")
            || lower.contains("request_user_input")
            || lower.contains("request_plugin_install")
    }

    nonisolated private static func isWaitingTool(_ name: String) -> Bool {
        name == "request_user_input" || name == "request_plugin_install"
    }

    nonisolated private static func friendlyToolName(_ name: String) -> String {
        switch name {
        case "exec_command":
            return "命令"
        case "multi_tool_use.parallel":
            return "多项任务"
        case "apply_patch":
            return "文件修改"
        case "update_plan":
            return "计划更新"
        default:
            return name
        }
    }

    nonisolated private static func projectDisplayName(path: String, title: String) -> String {
        let cleanTitle = normalizeDetail(title)
        if cleanTitle.isEmpty == false {
            return cleanTitle
        }
        let folder = folderName(from: path)
        return folder.isEmpty ? "当前对话" : folder
    }

    nonisolated private static func codexThreadName(home: URL, id: String) -> String? {
        let url = home.appendingPathComponent(".codex/session_index.jsonl")
        for line in tailLines(url: url, maxLines: 5000).reversed() {
            guard let object = parseJSONLine(line),
                  object["id"] as? String == id,
                  let name = object["thread_name"] as? String else {
                continue
            }
            let normalized = normalizeDetail(name)
            return normalized.isEmpty ? nil : normalized
        }
        return nil
    }

    nonisolated private static func folderName(from path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return "" }
        return URL(fileURLWithPath: trimmed).lastPathComponent
    }

    nonisolated private static func taskNotificationSummary(from content: String) -> String {
        let status = extractTag("status", from: content)
        let summary = extractTag("summary", from: content)
        return [status, summary]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
            .joined(separator: ": ")
    }

    nonisolated private static func extractTag(_ tag: String, from content: String) -> String? {
        guard let startRange = content.range(of: "<\(tag)>"),
              let endRange = content.range(of: "</\(tag)>", range: startRange.upperBound..<content.endIndex) else {
            return nil
        }
        return String(content[startRange.upperBound..<endRange.lowerBound])
    }

    nonisolated private static func normalizeDetail(_ detail: String) -> String {
        let clean = detail
            .replacingOccurrences(of: "\u{001B}\\[[0-9;]*[A-Za-z]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.count > 220 {
            return "\(clean.prefix(217))..."
        }
        return clean
    }

    nonisolated private static func newestFile(under root: URL, extensionName: String) -> URL? {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        var newest: (url: URL, date: Date)?
        for case let url as URL in enumerator where url.pathExtension == extensionName {
            guard let date = fileModificationDate(url) else { continue }
            if let current = newest {
                if date > current.date {
                    newest = (url, date)
                }
            } else {
                newest = (url, date)
            }
        }
        return newest?.url
    }

    nonisolated private static func fileModificationDate(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    nonisolated private static func tailLines(url: URL, maxLines: Int) -> [String] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }

        let fileSize = (try? handle.seekToEnd()) ?? 0
        let readSize = min(UInt64(256_000), fileSize)
        do {
            try handle.seek(toOffset: fileSize - readSize)
            let data = try handle.readToEnd() ?? Data()
            guard let text = String(data: data, encoding: .utf8) else { return [] }
            return text.split(separator: "\n").suffix(maxLines).map(String.init)
        } catch {
            return []
        }
    }

    nonisolated private static func parseJSONLine(_ line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    nonisolated private static func run(_ executable: String, arguments: [String]) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}
