import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @State private var portText = ""
    @State private var successMessage: String?
    @FocusState private var isPortFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("AgentMonitor 设置")
                .font(.system(size: 18, weight: .semibold))

            VStack(alignment: .leading, spacing: 8) {
                Toggle("开机启动", isOn: launchAtLoginBinding)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("系统通知")
                    .font(.system(size: 13, weight: .semibold))

                Toggle("任务已完成", isOn: $settings.notifyCompleted)
                Toggle("等待确认", isOn: $settings.notifyWaiting)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("端口配置")
                    .font(.system(size: 13, weight: .semibold))

                Text("默认端口：\(AppSettings.defaultPort)")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                HStack {
                    TextField("端口", text: $portText)
                        .textFieldStyle(.roundedBorder)
                        .focused($isPortFieldFocused)
                        .frame(width: 120)

                    Button("应用") {
                        let previousPort = settings.port
                        settings.updatePort(from: portText)
                        portText = "\(settings.port)"
                        isPortFieldFocused = false
                        if settings.settingsError == nil, settings.port != previousPort || portText == "\(settings.port)" {
                            showSuccess("端口已更新")
                        }
                    }

                    if let successMessage {
                        Text(successMessage)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.green)
                            .transition(.opacity)
                    }
                }

                Text("当前端口：\(settings.port)")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Hook 配置")
                    .font(.system(size: 13, weight: .semibold))

                Text("自动将通知 Hook 写入 Claude Code 和 Codex 配置文件")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                Button("重新安装 Hooks") {
                    let installer = HookInstaller()
                    if let error = installer.install() {
                        settings.settingsError = error
                    } else {
                        showSuccess("Hooks 安装成功")
                    }
                }
            }

            Divider()

            if let error = settings.settingsError {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundColor(.red)
            }

            Spacer(minLength: 0)
        }
        .onAppear {
            portText = "\(settings.port)"
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding {
            settings.launchAtLoginEnabled
        } set: { enabled in
            settings.setLaunchAtLogin(enabled)
        }
    }

    private func showSuccess(_ message: String) {
        withAnimation(.easeInOut(duration: 0.15)) {
            successMessage = message
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeInOut(duration: 0.15)) {
                successMessage = nil
            }
        }
    }
}
