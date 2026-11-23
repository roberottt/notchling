import Foundation
import Testing
@testable import NotchCore

private func resolve(_ status: String?, _ waiting: String? = nil, _ value: Transcript? = nil) -> SessionState {
    StateResolver.resolve(status: status, waitingFor: waiting, transcript: value).0
}

@Test(arguments: [
    ("busy", nil, SessionState.working),
    ("idle", nil, .idle),
    ("shell", nil, .background),
    ("waiting", "permission prompt", .permission),
    ("waiting", "sandbox request", .permission),
    ("waiting", "worker request", .permission),
    ("waiting", "goal proposal", .permission),
    ("waiting", "input needed", .question),
    ("waiting", "dialog open", .dialog),
    ("waiting", "algo nuevo", .input),
    ("waiting", nil, .input),
] as [(String, String?, SessionState)])
func registryStatus(status: String, waiting: String?, expected: SessionState) {
    #expect(resolve(status, waiting) == expected)
}

@Test func planArrivesAsPermissionPrompt() {
    #expect(resolve("waiting", "permission prompt", transcript(prompt("x"), tool("ExitPlanMode"))) == .plan)
}

@Test func questionShowsItsText() {
    let value = transcript(prompt("x"), tool("AskUserQuestion", input: ["questions": [["question": "¿Rojo o azul?"]]]))
    let (state, detail) = StateResolver.resolve(status: "waiting", waitingFor: "input needed", transcript: value)
    #expect(state == .question)
    #expect(detail == "¿Rojo o azul?")
}

/// El idioma es global: las pruebas que comparan textos no pueden correr a la vez.
@Suite(.serialized) struct Texts {
    @Test func permissionShowsCommandNotDescription() {
        Language.current = .spanish
        let value = transcript(prompt("x"), tool("Bash", input: ["command": "rm -rf\n build", "description": "Limpiar"]))
        #expect(StateResolver.resolve(status: "waiting", waitingFor: "permission prompt", transcript: value).1 == "Ejecutar: rm -rf build")
        #expect(StateResolver.resolve(status: "busy", waitingFor: nil, transcript: value).1 == "Limpiar")
    }

    @Test func parallelPermissionShowsFirstPendingCall() {
        Language.current = .spanish
        var value = transcript(
            prompt("x"),
            tool("Bash", id: "a", input: ["command": "uno"]),
            tool("Bash", id: "b", input: ["command": "dos"]))
        #expect(StateResolver.resolve(status: "waiting", waitingFor: "permission prompt", transcript: value).1 == "Ejecutar: uno")
        value.consume(line: line(result("a")))
        #expect(StateResolver.resolve(status: "waiting", waitingFor: "permission prompt", transcript: value).1 == "Ejecutar: dos")
    }

    @Test func englishTexts() {
        Language.current = .english
        defer { Language.current = .spanish }
        let value = transcript(prompt("x"), tool("Bash", id: "a", input: ["command": "make"]), tool("Read", id: "b", input: ["file_path": "/a/b.swift"]))
        #expect(StateResolver.resolve(status: "waiting", waitingFor: "permission prompt", transcript: value).1 == "Run: make")
        #expect(StateResolver.resolve(status: "busy", waitingFor: nil, transcript: value).1 == "Reading b.swift")
        #expect(SessionState.working.label == "Working")
        #expect(StateResolver.resolve(status: "idle", waitingFor: nil, transcript: nil).1 == "Waiting for your next message")
    }
}

@Test func withoutStatusTheTranscriptDecides() {
    #expect(resolve(nil) == .unknown)
    #expect(resolve(nil, nil, transcript(prompt("x"))) == .working)
    #expect(resolve(nil, nil, transcript(prompt("x"), answer("fin"))) == .idle)
    #expect(resolve(nil, nil, transcript(prompt("x"), tool("AskUserQuestion"))) == .question)
}

@Test func interruptionClearsPendingWork() {
    let value = transcript(prompt("x"), tool("Bash"), prompt("[Request interrupted by user for tool use]"))
    #expect(value.pending.isEmpty)
    #expect(value.outcome == .interrupted)
}

@Test func apiErrorFailsTheTurn() {
    var error = answer("API Error")
    error["isApiErrorMessage"] = true
    #expect(transcript(prompt("x"), error).outcome == .failed)
}

@Test func internalEntriesDoNotStartTurns() {
    var meta = prompt("contexto")
    meta["isMeta"] = true
    var side = prompt("subagente")
    side["isSidechain"] = true
    let value = transcript(prompt("x"), answer("fin"), meta, side, prompt("<local-command-stdout>hola"))
    #expect(value.outcome == .completed)
}

@Test func customTitleWins() {
    let value = transcript(
        ["type": "custom-title", "customTitle": "Mío"],
        ["type": "ai-title", "aiTitle": "Generado"])
    #expect(value.title == "Mío")
}

private func session(_ state: SessionState, outcome: TurnOutcome? = nil, id: String = "a", since: Date = now) -> Session {
    Session(id: id, pid: 1, project: "p", state: state, since: since, startedAt: now, outcome: outcome)
}

@Test func doneOnlyAfterSeeingWork() {
    var tracker = AttentionTracker()
    #expect(tracker.update([session(.idle, outcome: .completed)], now: now).sessions[0].state == .idle)
    _ = tracker.update([session(.working)], now: now)
    #expect(tracker.update([session(.idle, outcome: .completed)], now: now).sessions[0].state == .done)
    #expect(tracker.update([session(.idle)], now: now.addingTimeInterval(301)).sessions[0].state == .idle)
}

@Test func interruptedIsNotDone() {
    var tracker = AttentionTracker()
    _ = tracker.update([session(.working)], now: now)
    #expect(tracker.update([session(.idle, outcome: .interrupted)], now: now).sessions[0].state == .idle)
}

@Test func acknowledgingClearsDoneAndError() {
    for outcome in [TurnOutcome.completed, .failed] {
        var tracker = AttentionTracker()
        _ = tracker.update([session(.working)], now: now)
        #expect(tracker.update([session(.idle, outcome: outcome)], now: now).sessions[0].state != .idle)
        tracker.acknowledge("a", now: now)
        #expect(tracker.update([session(.idle, outcome: outcome)], now: now).sessions[0].state == .idle)
    }
}

@Test func alertsFireOncePerRequest() {
    var tracker = AttentionTracker()
    #expect(tracker.update([session(.permission)], now: now).alerts.count == 1)
    #expect(tracker.update([session(.permission)], now: now).alerts.isEmpty)
    _ = tracker.update([session(.working)], now: now)
    #expect(tracker.update([session(.permission)], now: now).alerts.count == 1)
}

@Test func mostUrgentGoesFirst() {
    var tracker = AttentionTracker()
    let all = [session(.idle, id: "i"), session(.working, id: "w"), session(.permission, id: "p")]
    #expect(tracker.update(all, now: now).sessions.map(\.id) == ["p", "w", "i"])
}
