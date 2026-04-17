import Foundation
import Combine
import SwiftUI
import UserNotifications

class SessionManager: ObservableObject {
    @Published var sessions: [Session] = []
    @Published var permissionAlertMessage: String?
    @Published var pulseToggle = false

    private let server = HookServer()
    private let settings: AppSettings
    private let terminalNavigator = TerminalNavigator()
    private var cancellables = Set<AnyCancellable>()
    private var staleCheckTimer: Timer?
    private var pulseTimer: Timer?

    init(settings: AppSettings) {
        self.settings = settings
        server.onEvent = { [weak self] event in
            DispatchQueue.main.async {
                self?.handleEvent(event)
            }
        }
        server.start(port: normalizedPort(settings.port))

        settings.$port
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] port in
                self?.debugLog("Restarting hook server on port \(port)")
                self?.server.start(port: self?.normalizedPort(port) ?? UInt16(AppSettings.defaultPort))
            }
            .store(in: &cancellables)

        staleCheckTimer = Timer.scheduledTimer(
            withTimeInterval: 5,
            repeats: true
        ) { [weak self] _ in
            self?.checkStaleSessions()
        }

        pulseTimer = Timer.scheduledTimer(
            withTimeInterval: 0.8,
            repeats: true
        ) { [weak self] _ in
            guard let self = self else { return }
            if self.sessions.contains(where: { $0.status == .waiting }) {
                self.pulseToggle.toggle()
            } else {
                self.pulseToggle = false
            }
        }
    }

    deinit {
        staleCheckTimer?.invalidate()
        pulseTimer?.invalidate()
    }

    // MARK: - Event Handling

    func handleEvent(_ event: HookServer.HookEvent) {
        let project = extractProject(from: event.cwd)
        let gitBranch = extractGitBranch(from: event.cwd)
        let newStatus = mapStatus(event)
        let previousStatus = sessions.first(where: { $0.id == event.sessionId })?.status

        debugLog("Received event: source=\(event.source), event=\(event.eventName), project=\(project), session=\(event.sessionId)")

        if let index = sessions.firstIndex(where: { $0.id == event.sessionId }) {
            // Update existing session — replace entire element to trigger @Published
            sessions[index].status = newStatus
            sessions[index].cwd = event.cwd
            sessions[index].project = project
            sessions[index].gitBranch = gitBranch
            if sessions[index].title?.isEmpty != false {
                sessions[index].title = makeSessionTitle(from: event)
            }
            if let terminalTTY = event.terminalTTY {
                sessions[index].terminalTTY = terminalTTY
            }
            if let msg = event.lastMessage {
                sessions[index].lastMessage = String(msg.prefix(200))
            }
            sessions[index].updatedAt = Date()
        } else {
            // Create new session
            let tool: Session.Tool = event.source == "codex" ? .codex : .claudeCode
            let session = Session(
                id: event.sessionId,
                title: makeSessionTitle(from: event),
                tool: tool,
                project: project,
                cwd: event.cwd,
                gitBranch: gitBranch,
                terminalTTY: event.terminalTTY,
                status: newStatus,
                lastMessage: event.lastMessage.map { String($0.prefix(200)) },
                updatedAt: Date(),
                createdAt: Date()
            )
            sessions.append(session)
        }

        // Force SwiftUI to detect the change
        objectWillChange.send()

        debugLog("Sessions count: \(sessions.count)")
        for s in sessions {
            debugLog("  - [\(s.tool.rawValue)] \(s.title ?? s.project): \(s.statusText)")
        }

        sendNotificationIfNeeded(event, project: project, previousStatus: previousStatus, newStatus: newStatus)
    }

    // MARK: - Status Mapping

    private func mapStatus(_ event: HookServer.HookEvent) -> Session.Status {
        switch event.eventName {
        case "Stop":
            return .completed

        case "Notification", "PermissionRequest", "PermissionDenied", "Elicitation":
            return .waiting

        case "StopFailure":
            return .failed

        case "SessionEnd":
            return .completed

        case "SessionStart", "PreToolUse", "PostToolUse", "PostToolUseFailure", "UserPromptSubmit", "CwdChanged":
            // Claude resumed working after user action
            return .running

        case "agent-turn-start":
            return .running

        case "agent-turn-user-prompt", "approval-requested", "exec-approval", "apply-patch-approval":
            return .waiting

        case "agent-turn-complete":
            return .completed

        case "notify":
            // Codex notify is primarily emitted after a turn completes.
            return mapCodexNotifyStatus(event)

        case "agent-turn-stop":
            return .failed

        default:
            // Unknown Codex notify payloads are sent only for user-visible notifications.
            if event.source == "codex" {
                return .waiting
            }
            return .completed
        }
    }

    private func mapCodexNotifyStatus(_ event: HookServer.HookEvent) -> Session.Status {
        let text = [
            event.rawJson["subtype"],
            event.rawJson["notification-type"],
            event.rawJson["notification_type"],
            event.rawJson["kind"],
            event.rawJson["title"],
            event.rawJson["message"],
            event.lastMessage
        ]
            .compactMap { $0 as? String }
            .joined(separator: " ")
            .lowercased()

        if text.contains("approval")
            || text.contains("permission")
            || text.contains("confirm")
            || text.contains("prompt")
            || text.contains("waiting")
            || text.contains("input")
        {
            return .waiting
        }

        if text.contains("error")
            || text.contains("fail")
            || text.contains("interrupted")
            || text.contains("cancel")
        {
            return .failed
        }

        return .completed
    }

    // MARK: - System Notification

    private func sendNotificationIfNeeded(
        _ event: HookServer.HookEvent,
        project: String,
        previousStatus: Session.Status?,
        newStatus status: Session.Status
    ) {
        if previousStatus == status {
            return
        }

        let body: String
        let sound: UNNotificationSound

        switch status {
        case .waiting:
            guard settings.notifyWaiting else { return }
            body = "\(project) - 需要你确认操作"
            sound = .default
        case .completed:
            guard settings.notifyCompleted else { return }
            body = "\(project) - 任务已完成"
            sound = UNNotificationSound(named: UNNotificationSoundName("Glass.aiff"))
        case .failed:
            body = "\(project) - 任务出错"
            sound = .default
        case .running:
            return // No notification for running state
        }

        let content = UNMutableNotificationContent()
        content.title = event.source == "codex" ? "Codex" : "Claude Code"
        content.body = body
        content.sound = sound

        let request = UNNotificationRequest(
            identifier: "\(event.sessionId)-\(event.eventName)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[AgentMonitor] Notification error: \(error)")
            }
        }
    }

    // MARK: - Helpers

    // MARK: - Stale Session Detection

    private func checkStaleSessions() {
        let staleIds = sessions.filter { session in
            guard session.status == .running || session.status == .waiting,
                  let tty = session.terminalTTY, !tty.isEmpty else {
                return false
            }
            return !FileManager.default.fileExists(atPath: tty)
        }.map(\.id)

        if !staleIds.isEmpty {
            debugLog("Removing stale sessions (TTY gone): \(staleIds)")
            sessions.removeAll { staleIds.contains($0.id) }
        }
    }

    func openSession(_ session: Session) {
        switch terminalNavigator.focusExistingTerminal(for: session) {
        case .focused:
            debugLog("Focused terminal session: \(session.id)")
        case .permissionDenied:
            permissionAlertMessage = "请在 系统设置 > 隐私与安全性 > 自动化 中允许 AgentMonitor 控制 Terminal/iTerm2"
            debugLog("Apple Events permission denied for session: \(session.id)")
        case .notFound:
            if !session.cwd.isEmpty {
                NSWorkspace.shared.open(URL(fileURLWithPath: session.cwd))
                debugLog("Could not focus terminal for \(session.id); opened cwd instead")
            }
        }
    }

    private func extractProject(from path: String) -> String {
        guard !path.isEmpty else { return "Unknown" }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    private func makeSessionTitle(from event: HookServer.HookEvent) -> String? {
        let rawTitle = event.userMessage ?? event.sessionTitle
        guard let title = rawTitle?
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !title.isEmpty else {
            return nil
        }
        return String(title.prefix(80))
    }

    private func extractGitBranch(from path: String) -> String? {
        guard !path.isEmpty else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", path, "branch", "--show-current"]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else {
            return nil
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        let branch = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return branch?.isEmpty == false ? branch : nil
    }

    private func debugLog(_ message: String) {
        let logPath = "/tmp/agentmonitor.log"
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let line = "[\(timestamp)] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: logPath) {
            if let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: logPath)) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            }
        } else {
            try? data.write(to: URL(fileURLWithPath: logPath))
        }
    }

    private func normalizedPort(_ port: Int) -> UInt16 {
        UInt16(exactly: port) ?? UInt16(AppSettings.defaultPort)
    }
}
