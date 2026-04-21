import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

@MainActor
struct IslandDoneHoldTests {
    /// Within the 2s hold window after the newest completion, the pill
    /// reports `.done`; past the window it falls back to `.idle`.
    @Test
    func doneHoldWindowGatesTheDoneToIdleTransition() async throws {
        let model = AppModel()
        let now = Date()
        let completedRecent = makeCompleted(id: "recent", updatedAt: now.addingTimeInterval(-0.5))
        model.state = SessionState(sessions: [completedRecent])
        #expect(model.islandClosedMode == .done)

        let completedLongAgo = makeCompleted(id: "old", updatedAt: now.addingTimeInterval(-60))
        model.state = SessionState(sessions: [completedLongAgo])
        #expect(model.islandClosedMode == .idle)
    }

    /// A running session always beats a stale completion — even if the
    /// completed session's updatedAt is within the hold window.
    @Test
    func runningSessionOverridesDoneHoldOfPeer() {
        let model = AppModel()
        let now = Date()
        let completed = makeCompleted(id: "c", updatedAt: now.addingTimeInterval(-0.5))
        let running = makeRunning(id: "r", updatedAt: now)
        model.state = SessionState(sessions: [completed, running])
        #expect(model.islandClosedMode == .running)
    }

    // MARK: helpers

    private func makeCompleted(id: String, updatedAt: Date) -> AgentSession {
        baseSession(id: id, phase: .completed, updatedAt: updatedAt)
    }

    private func makeRunning(id: String, updatedAt: Date) -> AgentSession {
        baseSession(id: id, phase: .running, updatedAt: updatedAt)
    }

    private func baseSession(id: String, phase: SessionPhase, updatedAt: Date) -> AgentSession {
        var session = AgentSession(
            id: id,
            title: "Claude · \(id)",
            tool: .claudeCode,
            origin: .live,
            attachmentState: .attached,
            phase: phase,
            summary: "",
            updatedAt: updatedAt,
            firstSeenAt: updatedAt,
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: id,
                paneTitle: "claude ~/\(id)",
                workingDirectory: "/tmp/\(id)",
                terminalSessionID: "ghostty-\(id)"
            ),
            claudeMetadata: ClaudeSessionMetadata(
                transcriptPath: "/tmp/\(id).jsonl",
                currentTool: "Task"
            )
        )
        session.isProcessAlive = true
        session.isHookManaged = true
        return session
    }
}
