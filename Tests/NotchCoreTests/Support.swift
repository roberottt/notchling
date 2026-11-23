import Foundation
@testable import NotchCore

let now = Date(timeIntervalSince1970: 1_800_000_000)

func line(_ object: [String: Any]) -> Data {
    try! JSONSerialization.data(withJSONObject: object)
}

func prompt(_ text: String) -> [String: Any] {
    ["type": "user", "timestamp": "2026-11-22T20:00:00.500Z", "message": ["role": "user", "content": text]]
}

func tool(_ name: String, id: String = "t1", input: [String: Any] = [:]) -> [String: Any] {
    ["type": "assistant", "message": [
        "stop_reason": "tool_use", "content": [["type": "tool_use", "id": id, "name": name, "input": input]],
    ]]
}

func result(_ id: String = "t1") -> [String: Any] {
    ["type": "user", "message": ["content": [["type": "tool_result", "tool_use_id": id, "content": "ok"]]]]
}

func answer(_ text: String) -> [String: Any] {
    ["type": "assistant", "message": ["stop_reason": "end_turn", "content": [["type": "text", "text": text]]]]
}

func transcript(_ entries: [String: Any]...) -> Transcript {
    var value = Transcript()
    for entry in entries { value.consume(line: line(entry)) }
    return value
}

struct FakeProcesses: ProcessSource {
    var entries: [Int32: ProcessEntry] = [:]
    var calls: [Int32: Invocation] = [:]
    var directory = "/work/app"

    mutating func add(
        _ pid: Int32, parent: Int32 = 1, uid: UInt32 = 501, name: String = "claude",
        arguments: [String] = ["claude"], config: String? = nil, started: Date = now.addingTimeInterval(-60)
    ) {
        entries[pid] = ProcessEntry(pid: pid, parent: parent, uid: uid, name: name, started: started)
        calls[pid] = Invocation(executable: "/bin/\(name)", arguments: arguments, configDirectory: config)
    }

    func processes() -> [Int32: ProcessEntry] { entries }
    func invocation(of pid: Int32) -> Invocation? { calls[pid] }
    func workingDirectory(of pid: Int32) -> String? { directory }
}

final class Sandbox {
    let root = NSTemporaryDirectory() + "notch-tests-" + UUID().uuidString

    deinit { try? FileManager.default.removeItem(atPath: root) }

    func write(_ path: String, _ data: Data) {
        let full = root + "/" + path
        try! FileManager.default.createDirectory(
            atPath: (full as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: full, contents: data)
    }

    func register(_ pid: Int, in folder: String = "claude", _ extra: [String: Any] = [:]) {
        var record: [String: Any] = [
            "pid": pid, "sessionId": "s\(pid)", "cwd": "/work/app", "status": "busy",
            "startedAt": (now.timeIntervalSince1970 - 59) * 1000,
        ]
        record.merge(extra) { $1 }
        write("\(folder)/sessions/\(pid).json", line(record))
    }

    func scan(_ source: FakeProcesses) -> [Session] {
        SessionScanner(source: source, defaultDirectory: root + "/claude", uid: 501).scan(now: now)
    }
}
