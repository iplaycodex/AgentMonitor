import SwiftUI
import UserNotifications

@main
struct AgentMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var settings: AppSettings
    @StateObject private var sessionManager: SessionManager

    init() {
        let settings = AppSettings()
        _settings = StateObject(wrappedValue: settings)
        _sessionManager = StateObject(wrappedValue: SessionManager(settings: settings))
    }

    var body: some Scene {
        MenuBarExtra {
            StatusMenuView()
                .environmentObject(sessionManager)
                .environmentObject(settings)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: menuIcon)
                Text(statusBarTitle)
                    .monospacedDigit()
            }
        }
        .menuBarExtraStyle(.window)

        Window("AgentMonitor 设置", id: "settings") {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(sessionManager)
                .padding(16)
                .frame(width: 360, height: 420)
                .onAppear { centerAndFocusSettingsWindow() }
        }
        .windowResizability(.contentSize)
    }

    private var statusBarTitle: String {
        let total = sessionManager.sessions.count
        let completed = sessionManager.sessions.filter { $0.status == .completed }.count
        let waiting = sessionManager.sessions.filter { $0.status == .waiting }.count
        return "\(total)  待\(waiting)  完\(completed)"
    }

    private var menuIcon: String {
        let hasWaiting = sessionManager.sessions.contains(where: { $0.status == .waiting })
        if hasWaiting && sessionManager.pulseToggle {
            return "rectangle.stack.badge.person.crop"
        }
        return hasWaiting
            ? "rectangle.stack.badge.person.crop.fill"
            : "rectangle.stack.badge.person.crop"
    }

    private func centerAndFocusSettingsWindow() {
        let work = DispatchWorkItem {
            guard let window = NSApplication.shared.windows.first(where: { $0.title == "AgentMonitor 设置" }) else { return }
            window.center()
            window.level = .floating
            NSApp.activate(ignoringOtherApps: true)
        }
        DispatchQueue.main.asyncAfter(deadline: .now(), execute: work)
    }
}

// AppDelegate only handles: prevent quit on window close + suppress auto-open settings
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let notificationCenter = UNUserNotificationCenter.current()
        notificationCenter.delegate = self
        notificationCenter.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error)")
            }
            print("[AgentMonitor] Notification permission granted: \(granted)")
        }

        // Auto-install hooks on first launch
        let installer = HookInstaller()
        if !installer.isInstalled {
            DispatchQueue.global(qos: .background).async {
                installer.install()
            }
        }

        // Close auto-opened settings window
        DispatchQueue.main.async {
            if let window = NSApp.windows.first(where: { $0.title == "AgentMonitor 设置" }) {
                window.close()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }
}
