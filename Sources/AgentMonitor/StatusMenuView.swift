import SwiftUI

struct StatusMenuView: View {
    @EnvironmentObject var manager: SessionManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if manager.sessions.isEmpty {
                emptyState
            } else {
                sessionsList
            }

            Divider()
            footer
        }
        .padding(12)
        .frame(width: 400)
        .alert("权限不足", isPresented: Binding(
            get: { manager.permissionAlertMessage != nil },
            set: { if !$0 { manager.permissionAlertMessage = nil } }
        )) {
            Button("好的") {
                manager.permissionAlertMessage = nil
            }
        } message: {
            Text(manager.permissionAlertMessage ?? "")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("AgentMonitor")
                .font(.system(size: 14, weight: .semibold))
            Spacer()
            if !manager.sessions.isEmpty {
                Text("\(manager.sessions.count) 个会话")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.bottom, 8)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 24))
                .foregroundColor(.secondary)
            Text("暂无活跃会话")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Text("运行 install.sh 配置 hooks 后即可监控")
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    // MARK: - Sessions List

    @ViewBuilder
    private var sessionsList: some View {
        if manager.sessions.count <= 8 {
            sessionsContent
        } else {
            ScrollView {
                sessionsContent
            }
            .frame(maxHeight: 720)
        }
    }

    private var sessionsContent: some View {
        let claudeSessions = manager.sessions.filter { $0.tool == .claudeCode }
        let codexSessions = manager.sessions.filter { $0.tool == .codex }

        return VStack(alignment: .leading, spacing: 0) {
            if !claudeSessions.isEmpty {
                sectionHeader(title: "Claude Code", icon: "cpu")
                ForEach(claudeSessions) { session in
                    sessionButton(session)
                }
                .id(claudeSessions.map { $0.id }.joined())
            }

            if !codexSessions.isEmpty {
                if !claudeSessions.isEmpty {
                    Divider().padding(.vertical, 4)
                }
                sectionHeader(title: "Codex", icon: "terminal")
                ForEach(codexSessions) { session in
                    sessionButton(session)
                }
                .id(codexSessions.map { $0.id }.joined())
            }
        }
    }

    private func sessionButton(_ session: Session) -> some View {
        Button {
            manager.openSession(session)
        } label: {
            SessionRow(session: session)
        }
        .buttonStyle(.plain)
        .help("跳转到 \(session.project) 会话窗口")
    }

    private func sectionHeader(title: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(title)
                .font(.system(size: 11, weight: .medium))
            Spacer()
        }
        .foregroundColor(.secondary)
        .padding(.top, 4)
        .padding(.bottom, 2)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("设置") {
                openWindow(id: "settings")
            }
            .font(.system(size: 11))

            Spacer()

            Button("退出") {
                NSApplication.shared.terminate(nil)
            }
            .font(.system(size: 11))
        }
        .padding(.top, 8)
    }

    private func colorForStatus(_ status: Session.Status) -> Color {
        switch status {
        case .running: return .blue
        case .waiting: return .orange
        case .completed: return .green
        case .failed: return .red
        }
    }

    private func timeAgo(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "刚刚" }
        if interval < 3600 { return "\(Int(interval / 60))分钟前" }
        return "\(Int(interval / 3600))小时前"
    }
}

// MARK: - Session Row

struct SessionRow: View {
    let session: Session
    @State private var isHovered = false
    @State private var now = Date()

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: session.statusIcon)
                .foregroundColor(colorForStatus(session.status))
                .font(.system(size: 10))
                .frame(width: 10, height: 16, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                if let title = session.title, !title.isEmpty {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(primaryTextColor)
                        .lineLimit(1)

                    metadataLine
                } else {
                    titleFallbackLine
                }

                if let msg = session.lastMessage, !msg.isEmpty {
                    Text(msg)
                        .font(.system(size: 12))
                        .foregroundColor(secondaryTextColor)
                        .lineLimit(2)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(session.statusText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(statusTextColor)

                Text(timeDisplay)
                    .font(.system(size: 11))
                    .foregroundColor(timeTextColor)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(rowBackgroundColor)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            now = Date()
        }
    }

    private var status: Session.Status { session.status }

    private var rowBackgroundColor: Color {
        if status == .waiting && isHovered {
            return Color.orange.opacity(1.0)
        }
        if status == .waiting {
            return Color.orange.opacity(0.08)
        }
        if isHovered {
            return Color(red: 95 / 255, green: 160 / 255, blue: 255 / 255)
        }
        return Color.clear
    }

    private var primaryTextColor: Color {
        isHovered ? .white : .primary
    }

    private var secondaryTextColor: Color {
        isHovered ? .white : .secondary
    }

    private var statusTextColor: Color {
        isHovered ? .white : colorForStatus(session.status)
    }

    private var timeTextColor: Color {
        isHovered ? .white.opacity(0.85) : .secondary.opacity(0.6)
    }

    private var titleFallbackLine: some View {
        HStack(spacing: 4) {
            Text(session.project)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(primaryTextColor)
                .lineLimit(1)

            branchText
        }
    }

    private var metadataLine: some View {
        HStack(spacing: 4) {
            Text(session.project)
                .font(.system(size: 12))
                .foregroundColor(secondaryTextColor)
                .lineLimit(1)

            branchText
        }
    }

    @ViewBuilder
    private var branchText: some View {
        if let branch = session.gitBranch, !branch.isEmpty {
            Text("· branch \(branch)")
                .font(.system(size: 12))
                .foregroundColor(secondaryTextColor)
                .lineLimit(1)
        }
    }

    private func colorForStatus(_ status: Session.Status) -> Color {
        switch status {
        case .running: return .blue
        case .waiting: return .orange
        case .completed: return .green
        case .failed: return .red
        }
    }

    private var timeDisplay: String {
        if status == .running {
            return elapsedTime(from: session.createdAt, to: now)
        }
        return timeAgo(session.updatedAt)
    }

    private func elapsedTime(from start: Date, to end: Date) -> String {
        let interval = Int(end.timeIntervalSince(start))
        if interval < 60 { return "\(interval)s" }
        let minutes = interval / 60
        let seconds = interval % 60
        if minutes < 60 { return "\(minutes)m \(seconds)s" }
        let hours = minutes / 60
        let remainMinutes = minutes % 60
        return "\(hours)h \(remainMinutes)m"
    }

    private func timeAgo(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "刚刚" }
        if interval < 3600 { return "\(Int(interval / 60))分钟前" }
        return "\(Int(interval / 3600))小时前"
    }
}
