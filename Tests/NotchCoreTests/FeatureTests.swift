import Darwin
import Foundation
import Testing
@testable import NotchCore

// MARK: - Transcript

@Test func todoWriteReportsProgress() {
    let todos: [[String: Any]] = [
        ["content": "a", "status": "completed"],
        ["content": "b", "status": "in_progress"],
        ["content": "c", "status": "pending"],
    ]
    let value = transcript(prompt("x"), tool("TodoWrite", input: ["todos": todos]))
    #expect(value.tasks == TaskProgress(done: 1, total: 3))
}

@Test func taskToolsUpdateProgressOneByOne() {
    let value = transcript(
        prompt("x"),
        tool("TaskCreate", id: "a", input: ["subject": "uno"]),
        tool("TaskCreate", id: "b", input: ["subject": "dos"]),
        tool("TaskCreate", id: "c", input: ["subject": "tres"]),
        tool("TaskUpdate", id: "d", input: ["taskId": "1", "status": "completed"]),
        tool("TaskUpdate", id: "e", input: ["taskId": "3", "status": "deleted"]))
    #expect(value.tasks == TaskProgress(done: 1, total: 2))
}

@Test func noTasksMeansNoProgress() {
    #expect(transcript(prompt("x"), answer("hola")).tasks == nil)
}

@Test func contextComesFromTheLastResponse() {
    func reply(_ input: Int, _ created: Int, _ read: Int) -> [String: Any] {
        ["type": "assistant", "message": [
            "stop_reason": "end_turn", "content": [["type": "text", "text": "ok"]],
            "usage": ["input_tokens": input, "cache_creation_input_tokens": created, "cache_read_input_tokens": read,
                      "output_tokens": 500],
        ]]
    }
    let value = transcript(prompt("x"), reply(10, 1000, 20000), prompt("y"), reply(2, 300, 40000))
    #expect(value.contextTokens == 40302)
}

@Test func lastMessageKeepsMoreThanTheDetail() {
    let long = String(repeating: "palabra ", count: 60)
    let value = transcript(prompt("x"), answer(long))
    #expect((value.lastText?.count ?? 0) <= 120)
    #expect((value.lastMessage?.count ?? 0) > 400)
}

// MARK: - Avisos

@Test func finishingIsReportedOnce() {
    var tracker = AttentionTracker()
    func make(_ state: SessionState, _ outcome: TurnOutcome? = nil) -> Session {
        Session(id: "a", pid: 1, project: "p", state: state, since: now, startedAt: now, outcome: outcome)
    }
    #expect(tracker.update([make(.working)], now: now).finished.isEmpty)
    #expect(tracker.update([make(.idle, .completed)], now: now).finished.count == 1)
    #expect(tracker.update([make(.idle, .completed)], now: now).finished.isEmpty)
    _ = tracker.update([make(.working)], now: now)
    #expect(tracker.update([make(.idle, .interrupted)], now: now).finished.isEmpty)
}

// MARK: - Hook de permisos

@Test func hookOutputMatchesClaudeCode() throws {
    let data = try #require(PermissionHook.output(.allow))
    let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    let output = try #require(object["hookSpecificOutput"] as? [String: Any])
    #expect(output["hookEventName"] as? String == "PermissionRequest")
    #expect((output["decision"] as? [String: Any])?["behavior"] as? String == "allow")

    let deny = try #require(PermissionHook.output(.deny))
    #expect(String(decoding: deny, as: UTF8.self).contains("\"deny\""))
    #expect(PermissionHook.output(.ask) == nil)
}

@Test func installingKeepsEverythingElse() {
    let other: [String: Any] = ["type": "command", "command": "afplay ping.aiff"]
    let settings: [String: Any] = [
        "model": "opus",
        "hooks": [
            "PermissionRequest": [["matcher": "Bash", "hooks": [other]]],
            "Stop": [["hooks": [other]]],
        ],
    ]
    let command = PermissionHook.command(executable: "/Users/a b/Applications/Notchling.app/Contents/MacOS/Notchling")
    let installed = PermissionHook.installing(command: command, into: settings)
    #expect(PermissionHook.isInstalled(in: installed))
    #expect(installed["model"] as? String == "opus")
    let hooks = installed["hooks"] as? [String: Any]
    #expect((hooks?["PermissionRequest"] as? [[String: Any]])?.count == 2)
    #expect(hooks?["Stop"] != nil)

    // Instalar dos veces no duplica.
    let again = PermissionHook.installing(command: command, into: installed)
    #expect(((again["hooks"] as? [String: Any])?["PermissionRequest"] as? [[String: Any]])?.count == 2)

    let removed = PermissionHook.removing(from: again)
    #expect(!PermissionHook.isInstalled(in: removed))
    let left = (removed["hooks"] as? [String: Any])?["PermissionRequest"] as? [[String: Any]]
    #expect(left?.count == 1)
    #expect(left?.first?["matcher"] as? String == "Bash")
}

@Test func removingTheOnlyHookLeavesNoEmptyKeys() {
    let installed = PermissionHook.installing(command: PermissionHook.command(executable: "/A/Notchling"), into: [:])
    #expect(PermissionHook.removing(from: installed).isEmpty)
}

@Test func commandSurvivesQuotesInThePath() {
    #expect(PermissionHook.command(executable: "/x/it's/Notchling") == #"'/x/it'\''s/Notchling' --permission-hook"#)
}

@Test func toolsWithTheirOwnUIAreLeftToClaudeCode() {
    let request = line(["session_id": "s", "tool_name": "AskUserQuestion", "tool_input": [:]])
    #expect(PermissionHook.ask(request: request, socket: "/nonexistent/socket") == .ask)
}

@Test func withoutTheAppTheHookStepsAside() {
    let request = line(["session_id": "s", "tool_name": "Bash", "tool_input": ["command": "ls"]])
    #expect(PermissionHook.ask(request: request, socket: "/tmp/notchling-test-missing.sock") == .ask)
}

@Test func hookReceivesTheAppDecision() throws {
    let path = NSTemporaryDirectory() + "nl-\(getpid()).sock"
    unlink(path)
    defer { unlink(path) }
    let server = socket(AF_UNIX, SOCK_STREAM, 0)
    var address = try #require(PermissionHook.socketAddress(path))
    let bound = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(server, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
    #expect(bound == 0)
    #expect(listen(server, 1) == 0)

    // Un hilo hace de app: lee la petición y contesta «deny».
    let received = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
    defer { received.deallocate() }
    let thread = Thread {
        let client = accept(server, nil, nil)
        _ = recv(client, received, 4096, 0)
        _ = "deny\n".withCString { send(client, $0, 5, 0) }
        close(client)
        close(server)
    }
    thread.start()

    let request = line(["session_id": "s1", "tool_name": "Bash", "tool_input": ["command": "rm -rf build"]])
    #expect(PermissionHook.ask(request: request, socket: path, wait: 5) == .deny)
    #expect(String(cString: received).contains("rm -rf build"))
}
