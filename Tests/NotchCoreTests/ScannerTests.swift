import Foundation
import Testing
@testable import NotchCore

@Test func findsRegisteredSessions() {
    let box = Sandbox()
    var source = FakeProcesses()
    source.add(100)
    source.add(200, name: "2.1.330")
    box.register(100)
    box.register(200, ["status": "waiting", "waitingFor": "permission prompt"])
    #expect(box.scan(source).map(\.state) == [.working, .permission])
}

@Test func ignoresLeftoversAndReusedPIDs() {
    let box = Sandbox()
    var source = FakeProcesses()
    source.add(101, name: "vim", arguments: ["vim"], started: now)
    box.register(100)
    box.register(101)
    #expect(box.scan(source).isEmpty)
}

@Test func ignoresOtherUsersContainersAndSpares() {
    let box = Sandbox()
    var source = FakeProcesses()
    source.add(100, uid: 502)
    source.add(101, name: "x", arguments: ["x"])
    source.add(102, name: "x", arguments: ["x"])
    box.register(100)
    box.register(101, ["pidDomain": "linux:abc"])
    box.register(102, ["spare": true])
    #expect(box.scan(source).isEmpty)
}

@Test func followsCustomConfigDirectory() {
    let box = Sandbox()
    var source = FakeProcesses()
    source.add(100, config: box.root + "/otra")
    box.register(100, in: "otra", ["status": "idle"])
    #expect(box.scan(source).map(\.state) == [.idle])
}

@Test(arguments: [
    ["claude", "--chrome-native-host"],
    ["claude", "daemon", "run"],
    ["claude", "agents", "--json"],
    ["claude", "--bg-spare", "/tmp/x.sock"],
    ["claude bg-pty-host", "--bg-pty-host", "/tmp/x.sock"],
    ["ugrep", "patrón"],
])
func helpersAreNotSessions(arguments: [String]) {
    let box = Sandbox()
    var source = FakeProcesses()
    source.add(100, arguments: arguments)
    #expect(box.scan(source).isEmpty)
}

@Test func childrenAndWrappersAreNotExtraSessions() {
    let box = Sandbox()
    var source = FakeProcesses()
    source.add(90, name: "node", arguments: ["node", "/opt/bin/claude"])
    source.add(100, parent: 90)
    source.add(110, parent: 100)
    box.register(100)
    #expect(box.scan(source).map(\.pid) == [100])
}

@Test func fallsBackToTheTranscriptWithoutRegistry() {
    let box = Sandbox()
    var source = FakeProcesses()
    source.add(100, name: "node", arguments: ["node", "/lib/node_modules/@anthropic-ai/claude-code/cli.js"],
               started: Date(timeIntervalSince1970: 1_000_000))
    source.directory = "/work/mi_app.web"
    box.write("claude/projects/-work-mi-app-web/abc.jsonl", line(prompt("hola")) + Data("\n".utf8))
    let found = box.scan(source)
    #expect(found.map(\.state) == [.working])
    #expect(found.first?.project == "mi_app.web")
}

@Test func worktreesShowTheRepository() {
    #expect(SessionScanner.projectName("/code/tienda/.claude/worktrees/rama") == "tienda")
}

@Test func rejectsPathsAsSessionID() {
    let record = RegistryRecord(json: line(["pid": 5, "sessionId": "../../etc/passwd"]))
    #expect(record != nil)
    #expect(record?.sessionID == nil)
}

@Test func readerHandlesPartialLinesAndTruncation() throws {
    let box = Sandbox()
    let first = line(prompt("hola")) + Data("\n".utf8)
    let second = line(answer("fin")) + Data("\n".utf8)
    let path = box.root + "/t.jsonl"
    let reader = TranscriptReader(path: path)

    box.write("t.jsonl", first + second.prefix(20))
    reader.refresh()
    #expect(reader.transcript.outcome == .running)

    box.write("t.jsonl", first + second)
    reader.refresh()
    #expect(reader.transcript.outcome == .completed)

    box.write("t.jsonl", first)
    reader.refresh()
    #expect(reader.transcript.outcome == .running)
}

@Test func readerOnlyNeedsTheTailOfHugeFiles() {
    let box = Sandbox()
    let filler = Data(repeating: UInt8(ascii: "x"), count: 3 << 20) + Data("\n".utf8)
    box.write("t.jsonl", filler + line(prompt("hola")) + Data("\n".utf8))
    let reader = TranscriptReader(path: box.root + "/t.jsonl")
    reader.refresh()
    #expect(reader.transcript.outcome == .running)
}

@Test func parsesProcessArguments() {
    var bytes: [UInt8] = [2, 0, 0, 0]
    bytes += Array("/bin/claude\0\0\0claude\0-p\0HOME=/h\0CLAUDE_CONFIG_DIR=/c\0\0".utf8)
    let call = SystemProcesses.parse(bytes[...])
    #expect(call?.arguments == ["claude", "-p"])
    #expect(call?.configDirectory == "/c")
}
