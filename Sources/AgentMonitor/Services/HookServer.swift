import Foundation
import Network
import SwiftUI

class HookServer: ObservableObject {
    private var listener: NWListener?
    static let defaultPort: UInt16 = 17321

    var onEvent: ((HookEvent) -> Void)?

    struct HookEvent {
        let sessionId: String
        let eventName: String
        let cwd: String
        let terminalTTY: String?
        let userMessage: String?
        let sessionTitle: String?
        let lastMessage: String?
        let source: String
        let rawJson: [String: Any]
    }

    func start(port: UInt16 = defaultPort) {
        do {
            let params = NWParameters.tcp
            stop()
            guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
                print("[AgentMonitor] Invalid hook server port: \(port)")
                return
            }
            let listener = try NWListener(using: params, on: endpointPort)

            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    print("[AgentMonitor] Hook server started on port \(port)")
                case .failed(let err):
                    print("[AgentMonitor] Hook server failed: \(err)")
                default:
                    break
                }
            }

            listener.newConnectionHandler = { [weak self] conn in
                conn.start(queue: .global())
                self?.handleConnection(conn)
            }

            listener.start(queue: .main)
            self.listener = listener
        } catch {
            print("[AgentMonitor] Failed to start hook server: \(error)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Connection Handling

    private func handleConnection(_ conn: NWConnection) {
        readData(conn: conn, buffer: Data())
    }

    private func readData(conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 1024 * 1024) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }

            var buf = buffer
            if let data = data, !data.isEmpty {
                buf.append(data)
            }

            // Try to parse complete HTTP request
            if let result = self.parseHTTPRequest(buf) {
                // Debug: log full raw request for codex
                if result.path.contains("codex") {
                    let rawStr = String(data: buf, encoding: .utf8) ?? "nil"
                    self.debugLog("Codex RAW REQUEST (\(buf.count) bytes): \(rawStr.prefix(1000))")
                }
                self.processBody(result, connection: conn)
                return
            }

            if isComplete == true || error != nil {
                conn.cancel()
                return
            }

            self.readData(conn: conn, buffer: buf)
        }
    }

    // MARK: - HTTP Parsing

    private struct ParsedRequest {
        let path: String
        let body: Data
    }

    private func parseHTTPRequest(_ data: Data) -> ParsedRequest? {
        let headerSep = Data("\r\n\r\n".utf8)
        guard let headerEndRange = data.range(of: headerSep) else {
            return nil
        }

        let headerData = data[data.startIndex..<headerEndRange.lowerBound]
        let headerStr = String(data: headerData, encoding: .utf8) ?? ""

        // Extract path from request line: "POST /hooks/codex HTTP/1.1"
        let path = extractPath(fromHeader: headerStr)

        // Extract Content-Length
        let contentLength = extractContentLength(from: headerStr)

        let bodyStart = headerEndRange.upperBound
        let availableBody = data.count - bodyStart

        if contentLength == 0 && availableBody >= 0 {
            return ParsedRequest(path: path, body: Data())
        }

        if availableBody >= contentLength {
            return ParsedRequest(path: path, body: Data(data[bodyStart..<(bodyStart + contentLength)]))
        }

        return nil
    }

    private func extractPath(fromHeader header: String) -> String {
        // First line: "POST /hooks/codex HTTP/1.1"
        guard let firstLine = header.split(separator: "\r\n").first else { return "/" }
        let parts = firstLine.split(separator: " ")
        return parts.count >= 2 ? String(parts[1]) : "/"
    }

    private func extractContentLength(from header: String) -> Int {
        for line in header.split(separator: "\r\n") {
            let lower = line.lowercased()
            if lower.hasPrefix("content-length:") {
                let parts = line.split(separator: ":")
                if parts.count >= 2 {
                    let value = parts[1].trimmingCharacters(in: .whitespaces)
                    return Int(value) ?? 0
                }
            }
        }
        return 0
    }

    // MARK: - Processing

    private func processBody(_ request: ParsedRequest, connection: NWConnection) {
        if request.path == "/health" {
            sendJSON("{\"ok\":true,\"app\":\"AgentMonitor\"}", connection: connection)
            return
        }

        var json: [String: Any] = [:]
        if !request.body.isEmpty {
            json = (try? JSONSerialization.jsonObject(with: request.body) as? [String: Any]) ?? [:]
        }

        // Determine source from URL path
        let source = request.path.contains("codex") ? "codex" : "claude"

        // Debug: log raw JSON keys for Codex events
        if source == "codex" {
            let bodyStr = String(data: request.body, encoding: .utf8) ?? "nil"
            debugLog("Codex raw JSON: \(bodyStr.prefix(500))")
        }

        // Map fields: Codex uses hyphens, Claude Code uses underscores
        let sessionId: String
        let eventName: String
        let cwd: String
        let terminalTTY: String?
        let userMessage: String?
        let sessionTitle: String?
        let lastMessage: String?

        if source == "codex" {
            sessionId = json["thread-id"] as? String ?? UUID().uuidString
            eventName = json["type"] as? String ?? "unknown"
            cwd = json["cwd"] as? String ?? ""
            terminalTTY = normalizeTTY(json["agentmonitor_tty"] as? String ?? json["agentbar_tty"] as? String ?? json["tty"] as? String)
            userMessage = extractUserMessage(from: json, eventName: eventName, source: source)
            sessionTitle = extractString(from: json, keys: ["title", "conversation-title", "thread-title", "session-title"])
            lastMessage = json["last-assistant-message"] as? String
        } else {
            sessionId = json["session_id"] as? String ?? UUID().uuidString
            eventName = json["hook_event_name"] as? String
                ?? json["notification_type"] as? String
                ?? "unknown"
            cwd = json["cwd"] as? String ?? ""
            terminalTTY = normalizeTTY(json["agentmonitor_tty"] as? String ?? json["agentbar_tty"] as? String ?? json["tty"] as? String)
            userMessage = extractUserMessage(from: json, eventName: eventName, source: source)
            sessionTitle = extractString(from: json, keys: ["title", "conversation_title", "session_title"])
            lastMessage = json["last_assistant_message"] as? String
        }

        let event = HookEvent(
            sessionId: sessionId,
            eventName: eventName,
            cwd: cwd,
            terminalTTY: terminalTTY,
            userMessage: userMessage,
            sessionTitle: sessionTitle,
            lastMessage: lastMessage,
            source: source,
            rawJson: json
        )

        DispatchQueue.main.async {
            self.onEvent?(event)
        }

        sendOK(connection: connection)
    }

    private func normalizeTTY(_ tty: String?) -> String? {
        guard let tty = tty?.trimmingCharacters(in: .whitespacesAndNewlines),
              !tty.isEmpty,
              tty != "not a tty" else {
            return nil
        }
        return tty
    }

    private func extractUserMessage(from json: [String: Any], eventName: String, source: String) -> String? {
        let keys: [String]
        if source == "codex" {
            keys = [
                "input-messages",
                "first-user-message",
                "last-user-message",
                "user-message",
                "user-prompt",
                "prompt",
                "input"
            ]
        } else if eventName == "UserPromptSubmit" {
            keys = [
                "input_messages",
                "prompt",
                "user_prompt",
                "user-message",
                "user_message",
                "last_user_message"
            ]
        } else {
            keys = [
                "input_messages",
                "first_user_message",
                "last_user_message",
                "user_message",
                "prompt"
            ]
        }
        return extractString(from: json, keys: keys)
    }

    private func extractString(from json: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = json[key] as? String {
                let normalized = normalizeTitle(value)
                if !normalized.isEmpty {
                    return normalized
                }
            }

            if let values = json[key] as? [String] {
                for value in values {
                    let normalized = normalizeTitle(value)
                    if !normalized.isEmpty {
                        return normalized
                    }
                }
            }

            if let values = json[key] as? [Any] {
                for value in values {
                    if let value = value as? String {
                        let normalized = normalizeTitle(value)
                        if !normalized.isEmpty {
                            return normalized
                        }
                    }
                }
            }
        }
        return nil
    }

    private func normalizeTitle(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sendOK(connection: NWConnection) {
        sendJSON("{\"ok\":true}", connection: connection)
    }

    private func sendJSON(_ body: String, connection: NWConnection) {
        let response = "HTTP/1.1 200 OK\r\n"
            + "Content-Type: application/json\r\n"
            + "Content-Length: \(body.utf8.count)\r\n"
            + "Connection: close\r\n"
            + "\r\n"
            + body
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
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
}
