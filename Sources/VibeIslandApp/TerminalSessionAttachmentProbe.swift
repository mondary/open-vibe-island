import AppKit
import Foundation
import VibeIslandCore

struct TerminalSessionAttachmentProbe {
    private struct GhosttyTerminalSnapshot {
        var sessionID: String
        var workingDirectory: String
        var title: String
    }

    private struct TerminalTabSnapshot {
        var tty: String
        var customTitle: String
    }

    private static let liveGraceWindow: TimeInterval = 120
    private static let staleGraceWindow: TimeInterval = 15 * 60
    private static let fieldSeparator = "\u{1f}"
    private static let recordSeparator = "\u{1e}"

    func attachmentStates(for sessions: [AgentSession], now: Date = .now) -> [String: SessionAttachmentState] {
        guard !sessions.isEmpty else {
            return [:]
        }

        let ghosttySessions = sessions.filter { normalizedTerminalName(for: $0.jumpTarget?.terminalApp) == "ghostty" }
        let terminalSessions = sessions.filter { normalizedTerminalName(for: $0.jumpTarget?.terminalApp) == "terminal" }

        let ghosttySnapshots = (try? ghosttySnapshots()) ?? []
        let terminalSnapshots = (try? terminalSnapshots()) ?? []
        let ghosttyRunning = isRunning(bundleIdentifier: "com.mitchellh.ghostty")
        let terminalRunning = isRunning(bundleIdentifier: "com.apple.Terminal")

        var updates: [String: SessionAttachmentState] = [:]

        for session in sessions {
            if ghosttySessions.contains(where: { $0.id == session.id }) {
                updates[session.id] = resolveGhosttyAttachmentState(
                    for: session,
                    snapshots: ghosttySnapshots,
                    appIsRunning: ghosttyRunning,
                    now: now
                )
                continue
            }

            if terminalSessions.contains(where: { $0.id == session.id }) {
                updates[session.id] = resolveTerminalAttachmentState(
                    for: session,
                    snapshots: terminalSnapshots,
                    appIsRunning: terminalRunning,
                    now: now
                )
                continue
            }

            updates[session.id] = fallbackAttachmentState(for: session, appIsRunning: nil, now: now)
        }

        return updates
    }

    private func resolveGhosttyAttachmentState(
        for session: AgentSession,
        snapshots: [GhosttyTerminalSnapshot],
        appIsRunning: Bool,
        now: Date
    ) -> SessionAttachmentState {
        guard let jumpTarget = session.jumpTarget else {
            return fallbackAttachmentState(for: session, appIsRunning: appIsRunning, now: now)
        }

        if snapshots.contains(where: { snapshot in
            if let sessionID = jumpTarget.terminalSessionID, !sessionID.isEmpty, snapshot.sessionID == sessionID {
                return true
            }

            if let workingDirectory = jumpTarget.workingDirectory, !workingDirectory.isEmpty, snapshot.workingDirectory == workingDirectory {
                return true
            }

            return !jumpTarget.paneTitle.isEmpty && snapshot.title.contains(jumpTarget.paneTitle)
        }) {
            return .attached
        }

        return fallbackAttachmentState(for: session, appIsRunning: appIsRunning, now: now)
    }

    private func resolveTerminalAttachmentState(
        for session: AgentSession,
        snapshots: [TerminalTabSnapshot],
        appIsRunning: Bool,
        now: Date
    ) -> SessionAttachmentState {
        guard let jumpTarget = session.jumpTarget else {
            return fallbackAttachmentState(for: session, appIsRunning: appIsRunning, now: now)
        }

        if snapshots.contains(where: { snapshot in
            if let tty = jumpTarget.terminalTTY, !tty.isEmpty, snapshot.tty == tty {
                return true
            }

            return !jumpTarget.paneTitle.isEmpty && snapshot.customTitle.contains(jumpTarget.paneTitle)
        }) {
            return .attached
        }

        return fallbackAttachmentState(for: session, appIsRunning: appIsRunning, now: now)
    }

    private func fallbackAttachmentState(
        for session: AgentSession,
        appIsRunning: Bool?,
        now: Date
    ) -> SessionAttachmentState {
        let age = now.timeIntervalSince(session.updatedAt)

        if session.phase.requiresAttention {
            return .attached
        }

        if session.attachmentState == .attached && age <= Self.liveGraceWindow {
            return .attached
        }

        if session.codexMetadata?.currentTool?.isEmpty == false && age <= Self.liveGraceWindow {
            return .attached
        }

        if let appIsRunning, appIsRunning == false {
            return age <= Self.staleGraceWindow ? .stale : .detached
        }

        return age <= Self.staleGraceWindow ? .stale : .detached
    }

    private func ghosttySnapshots() throws -> [GhosttyTerminalSnapshot] {
        guard isRunning(bundleIdentifier: "com.mitchellh.ghostty") else {
            return []
        }

        let script = """
        set fieldSeparator to ASCII character 31
        set recordSeparator to ASCII character 30
        tell application "Ghostty"
            if not (it is running) then return ""
            set outputLines to {}
            repeat with aTerminal in terminals
                set terminalID to ""
                set terminalDirectory to ""
                set terminalTitle to ""
                try
                    set terminalID to (id of aTerminal as text)
                end try
                try
                    set terminalDirectory to (working directory of aTerminal as text)
                end try
                try
                    set terminalTitle to (name of aTerminal as text)
                end try
                set end of outputLines to terminalID & fieldSeparator & terminalDirectory & fieldSeparator & terminalTitle
            end repeat
            set AppleScript's text item delimiters to recordSeparator
            set joinedOutput to outputLines as string
            set AppleScript's text item delimiters to ""
            return joinedOutput
        end tell
        """

        let output = try runAppleScript(script)
        return output
            .split(separator: Character(Self.recordSeparator), omittingEmptySubsequences: true)
            .map(String.init)
            .compactMap { line in
                let values = line.components(separatedBy: Self.fieldSeparator)
                guard values.count == 3 else {
                    return nil
                }

                return GhosttyTerminalSnapshot(
                    sessionID: values[0],
                    workingDirectory: values[1],
                    title: values[2]
                )
            }
    }

    private func terminalSnapshots() throws -> [TerminalTabSnapshot] {
        guard isRunning(bundleIdentifier: "com.apple.Terminal") else {
            return []
        }

        let script = """
        set fieldSeparator to ASCII character 31
        set recordSeparator to ASCII character 30
        tell application "Terminal"
            if not (it is running) then return ""
            set outputLines to {}
            repeat with aWindow in windows
                repeat with aTab in tabs of aWindow
                    set tabTTY to ""
                    set tabTitle to ""
                    try
                        set tabTTY to (tty of aTab as text)
                    end try
                    try
                        set tabTitle to (custom title of aTab as text)
                    end try
                    set end of outputLines to tabTTY & fieldSeparator & tabTitle
                end repeat
            end repeat
            set AppleScript's text item delimiters to recordSeparator
            set joinedOutput to outputLines as string
            set AppleScript's text item delimiters to ""
            return joinedOutput
        end tell
        """

        let output = try runAppleScript(script)
        return output
            .split(separator: Character(Self.recordSeparator), omittingEmptySubsequences: true)
            .map(String.init)
            .compactMap { line in
                let values = line.components(separatedBy: Self.fieldSeparator)
                guard values.count == 2 else {
                    return nil
                }

                return TerminalTabSnapshot(
                    tty: values[0],
                    customTitle: values[1]
                )
            }
    }

    private func normalizedTerminalName(for value: String?) -> String? {
        value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func isRunning(bundleIdentifier: String) -> Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty == false
    }

    private func runAppleScript(_ script: String) throws -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = errorPipe

        try task.run()
        task.waitUntilExit()

        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard task.terminationStatus == 0 else {
            let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw NSError(domain: "TerminalSessionAttachmentProbe", code: Int(task.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: stderr.isEmpty ? "AppleScript probe failed." : stderr,
            ])
        }

        return output
    }
}
