import Foundation

struct Session: Identifiable, Codable {
    let id: String
    var title: String?
    var tool: Tool
    var project: String
    var cwd: String
    var gitBranch: String?
    var terminalTTY: String?
    var status: Status
    var lastMessage: String?
    var updatedAt: Date
    var createdAt: Date

    enum Tool: String, CaseIterable, Codable {
        case claudeCode = "Claude Code"
        case codex = "Codex"
    }

    enum Status: String, Codable {
        case running
        case waiting
        case completed
        case failed
    }

    var statusIcon: String {
        switch status {
        case .running: return "circle.fill"
        case .waiting: return "exclamationmark.circle.fill"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }

    var statusColor: String {
        switch status {
        case .running: return "blue"
        case .waiting: return "orange"
        case .completed: return "green"
        case .failed: return "red"
        }
    }

    var statusText: String {
        switch status {
        case .running: return "运行中"
        case .waiting: return "等待确认"
        case .completed: return "已完成"
        case .failed: return "出错"
        }
    }
}
