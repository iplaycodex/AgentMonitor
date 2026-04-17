import Foundation
import ServiceManagement

final class AppSettings: ObservableObject {
    static let defaultPort = 17321

    @Published var launchAtLoginEnabled: Bool
    @Published var notifyCompleted: Bool {
        didSet { defaults.set(notifyCompleted, forKey: Keys.notifyCompleted) }
    }
    @Published var notifyWaiting: Bool {
        didSet { defaults.set(notifyWaiting, forKey: Keys.notifyWaiting) }
    }
    @Published private(set) var port: Int {
        didSet { defaults.set(port, forKey: Keys.port) }
    }
    @Published var settingsError: String?

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let launchAtLogin = "launchAtLoginEnabled"
        static let notifyCompleted = "notifyCompleted"
        static let notifyWaiting = "notifyWaiting"
        static let port = "hookPort"
    }

    init() {
        launchAtLoginEnabled = defaults.bool(forKey: Keys.launchAtLogin)
        notifyCompleted = defaults.object(forKey: Keys.notifyCompleted) as? Bool ?? true
        notifyWaiting = defaults.object(forKey: Keys.notifyWaiting) as? Bool ?? true
        port = defaults.object(forKey: Keys.port) as? Int ?? Self.defaultPort
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        settingsError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginEnabled = enabled
            defaults.set(enabled, forKey: Keys.launchAtLogin)
        } catch {
            settingsError = "开机启动设置失败：\(error.localizedDescription)"
            launchAtLoginEnabled = defaults.bool(forKey: Keys.launchAtLogin)
        }
    }

    func updatePort(from text: String) {
        settingsError = nil
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Int(trimmed), (1...65535).contains(value) else {
            settingsError = "端口必须是 1 到 65535 之间的数字"
            return
        }
        port = value
    }
}
