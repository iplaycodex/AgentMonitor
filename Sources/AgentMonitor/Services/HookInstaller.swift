import Foundation

final class HookInstaller {
    private static let installedKey = "hooksInstalledVersion"
    private static let currentVersion = 2

    private let fileManager = FileManager.default
    private let defaults = UserDefaults.standard

    var isInstalled: Bool {
        defaults.integer(forKey: Self.installedKey) >= Self.currentVersion
    }

    @discardableResult
    func install() -> String? {
        let scriptDir = NSHomeDirectory() + "/.agentmonitor"
        var errors: [String] = []

        try? fileManager.createDirectory(atPath: scriptDir, withIntermediateDirectories: true)

        if let err = installClaudeCodeHooks(scriptDir: scriptDir) {
            errors.append(err)
        }

        if let err = installCodexHooks(scriptDir: scriptDir) {
            errors.append(err)
        }

        if errors.isEmpty {
            defaults.set(Self.currentVersion, forKey: Self.installedKey)
            return nil
        }
        return errors.joined(separator: "\n")
    }

    // MARK: - Claude Code

    private func installClaudeCodeHooks(scriptDir: String) -> String? {
        let scriptPath = scriptDir + "/claude-notify.sh"
        let settingsPath = NSHomeDirectory() + "/.claude/settings.json"

        guard let data = claudeNotifyScript.data(using: .utf8) else { return "无法生成 Claude hook 脚本" }
        fileManager.createFile(atPath: scriptPath, contents: data, attributes: [.posixPermissions: 0o755])

        guard fileManager.fileExists(atPath: settingsPath) else {
            return "Claude Code 未初始化，请先运行一次 Claude Code"
        }

        guard let settingsData = try? Data(contentsOf: URL(fileURLWithPath: settingsPath)),
              var settings = try? JSONSerialization.jsonObject(with: settingsData) as? [String: Any] else {
            return "无法解析 Claude Code settings.json"
        }

        var hooks = (settings["hooks"] as? [String: Any]) ?? [:]
        let hookEntry: [[String: Any]] = [
            ["matcher": "", "hooks": [["type": "command", "command": scriptPath]]]
        ]
        for event in ["Stop", "Notification", "StopFailure", "PreToolUse", "UserPromptSubmit"] {
            hooks[event] = hookEntry
        }
        settings["hooks"] = hooks

        guard let output = try? JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys]) else {
            return "无法序列化 settings.json"
        }
        do {
            try output.write(to: URL(fileURLWithPath: settingsPath))
        } catch {
            return "无法写入 settings.json: \(error.localizedDescription)"
        }
        return nil
    }

    // MARK: - Codex

    private func installCodexHooks(scriptDir: String) -> String? {
        let scriptPath = scriptDir + "/codex-notify.sh"
        let configDir = NSHomeDirectory() + "/.codex"
        let configPath = configDir + "/config.toml"

        guard let data = codexNotifyScript.data(using: .utf8) else { return "无法生成 Codex hook 脚本" }
        fileManager.createFile(atPath: scriptPath, contents: data, attributes: [.posixPermissions: 0o755])

        try? fileManager.createDirectory(atPath: configDir, withIntermediateDirectories: true)

        let notifyLine = "notify = [\"\(scriptPath)\"]"

        if fileManager.fileExists(atPath: configPath),
           let content = try? String(contentsOf: URL(fileURLWithPath: configPath)) {
            if content.contains("notify =") {
                let updated = content.replacingOccurrences(
                    of: "notify = .*",
                    with: notifyLine,
                    options: .regularExpression
                )
                try? updated.write(toFile: configPath, atomically: true, encoding: .utf8)
            } else {
                let updated = content.hasSuffix("\n") ? content + notifyLine + "\n" : content + "\n" + notifyLine + "\n"
                try? updated.write(toFile: configPath, atomically: true, encoding: .utf8)
            }
        } else {
            try? "# AgentMonitor notification hook\n\(notifyLine)\n".write(toFile: configPath, atomically: true, encoding: .utf8)
        }
        return nil
    }

    // MARK: - Script Templates

    private var claudeNotifyScript: String {
        """
        #!/bin/bash
        payload="$(cat)"
        port="$(defaults read com.agentmonitor.app hookPort 2>/dev/null || true)"
        if ! [[ "$port" =~ ^[0-9]+$ ]]; then
            port=17321
        fi
        tty_name="$(ps -o tty= -p "$$" 2>/dev/null | tr -d ' ')"
        if [ -n "$tty_name" ] && [ "$tty_name" != "??" ]; then
            tty_value="/dev/${tty_name}"
        else
            tty_value="$(tty 2>/dev/null || true)"
        fi

        AGENTMONITOR_PAYLOAD="$payload" AGENTMONITOR_TTY="$tty_value" python3 - <<'PYEOF' | curl --noproxy '*' -s -X POST "http://localhost:${port}/hooks/claude" -H 'Content-Type: application/json' -d @- > /dev/null 2>&1
        import json
        import os
        import sys

        try:
            data = json.loads(os.environ.get("AGENTMONITOR_PAYLOAD", "{}") or "{}")
        except json.JSONDecodeError:
            data = {}

        tty = (os.environ.get("AGENTMONITOR_TTY") or "").strip()
        if tty and tty != "not a tty":
            data["agentmonitor_tty"] = tty

        json.dump(data, sys.stdout, ensure_ascii=False)
        PYEOF
        """
    }

    private var codexNotifyScript: String {
        """
        #!/bin/bash
        payload="$1"
        port="$(defaults read com.agentmonitor.app hookPort 2>/dev/null || true)"
        if ! [[ "$port" =~ ^[0-9]+$ ]]; then
            port=17321
        fi
        tty_name="$(ps -o tty= -p "$$" 2>/dev/null | tr -d ' ')"
        if [ -n "$tty_name" ] && [ "$tty_name" != "??" ]; then
            tty_value="/dev/${tty_name}"
        else
            tty_value="$(tty 2>/dev/null || true)"
        fi

        AGENTMONITOR_PAYLOAD="$payload" AGENTMONITOR_TTY="$tty_value" python3 - <<'PYEOF' | curl --noproxy '*' -s -X POST "http://localhost:${port}/hooks/codex" -H 'Content-Type: application/json' -d @- > /dev/null 2>&1
        import json
        import os
        import sys

        try:
            data = json.loads(os.environ.get("AGENTMONITOR_PAYLOAD", "{}") or "{}")
        except json.JSONDecodeError:
            data = {}

        tty = (os.environ.get("AGENTMONITOR_TTY") or "").strip()
        if tty and tty != "not a tty":
            data["agentmonitor_tty"] = tty

        json.dump(data, sys.stdout, ensure_ascii=False)
        PYEOF
        """
    }
}
