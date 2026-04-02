import Foundation
import Testing
@testable import VibeIslandApp
import VibeIslandCore

@MainActor
struct AppModelLiveSessionsTests {
    @Test
    func completedAttachedSessionsMoveOutOfSurfacedList() {
        let now = Date(timeIntervalSince1970: 1_000)
        let model = AppModel()
        let running = AgentSession(
            id: "running",
            title: "Running",
            tool: .codex,
            origin: .live,
            attachmentState: .attached,
            phase: .running,
            summary: "Working",
            updatedAt: now
        )
        let completed = AgentSession(
            id: "completed",
            title: "Completed",
            tool: .codex,
            origin: .live,
            attachmentState: .attached,
            phase: .completed,
            summary: "Done",
            updatedAt: now.addingTimeInterval(-5)
        )

        model.state = SessionState(sessions: [running, completed])

        #expect(model.liveSessionCount == 1)
        #expect(model.surfacedSessions.map(\.id) == ["running"])
        #expect(model.recentSessions.map(\.id).contains("completed"))
    }
}
