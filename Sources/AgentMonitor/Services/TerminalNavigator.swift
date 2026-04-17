import Foundation

enum TerminalFocusResult {
    case focused
    case notFound
    case permissionDenied
}

final class TerminalNavigator {
    func focusExistingTerminal(for session: Session) -> TerminalFocusResult {
        guard (session.terminalTTY?.isEmpty == false) || !session.cwd.isEmpty else {
            return .notFound
        }

        return runAppleScript(tty: session.terminalTTY ?? "", cwd: session.cwd)
    }

    private func runAppleScript(tty: String, cwd: String) -> TerminalFocusResult {
        let script = """
        on run argv
            set targetTTY to item 1 of argv
            set targetCWD to item 2 of argv

            tell application "System Events"
                set terminalRunning to exists process "Terminal"
                set itermRunning to exists process "iTerm2"
                set ghosttyRunning to exists process "Ghostty"
            end tell

            if terminalRunning then
                tell application "Terminal"
                    repeat with theWindow in windows
                        repeat with theTab in tabs of theWindow
                            try
                                if tty of theTab is targetTTY then
                                    set selected tab of theWindow to theTab
                                    set index of theWindow to 1
                                    activate
                                    return "focused"
                                end if
                            end try
                        end repeat
                    end repeat
                end tell
            end if

            if itermRunning then
                tell application "iTerm2"
                    repeat with theWindow in windows
                        repeat with theTab in tabs of theWindow
                            repeat with theSession in sessions of theTab
                                try
                                    if tty of theSession is targetTTY then
                                        select theSession
                                        select theTab
                                        set index of theWindow to 1
                                        activate
                                        return "focused"
                                    end if
                                end try
                            end repeat
                        end repeat
                    end repeat
                end tell
            end if

            if ghosttyRunning then
                tell application "Ghostty"
                    if targetCWD is not "" then
                        set matchingTerms to every terminal whose working directory is targetCWD
                        if (count of matchingTerms) > 0 then
                            focus item 1 of matchingTerms
                            activate
                            return "focused"
                        end if
                    end if
                end tell
            end if

            return "not-found"
        end run
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script, tty, cwd]

        let output = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = output
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return .notFound
        }

        guard process.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? ""
            if errorMessage.contains("not authorized to send Apple events")
                || errorMessage.contains("Not allowed to send Apple events")
                || errorMessage.contains("AppleEvents")
                || errorMessage.contains("automator")
                || errorMessage.contains("Automation")
            {
                return .permissionDenied
            }
            return .notFound
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        let result = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return result == "focused" ? .focused : .notFound
    }
}
