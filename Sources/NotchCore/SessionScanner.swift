import Foundation

/// Descubre las sesiones vivas sin hooks y sin escribir en la configuración de Claude Code.
/// No es thread-safe: se usa siempre desde la misma cola.
public final class SessionScanner {
    private struct InvocationKey: Hashable {
        let pid: Int32
        let started: Date
        let name: String
    }

    private let source: ProcessSource
    private let defaultDirectory: String
    private let uid: UInt32
    private let files = FileManager.default

    private var invocations: [InvocationKey: Invocation] = [:]
    private var readers: [String: TranscriptReader] = [:]
    private var transcriptPaths: [String: String] = [:]

    public init(
        source: ProcessSource = SystemProcesses(),
        defaultDirectory: String = NSHomeDirectory() + "/.claude",
        uid: UInt32 = getuid()
    ) {
        self.source = source
        self.defaultDirectory = defaultDirectory
        self.uid = uid
    }

    public func scan(now: Date = Date()) -> [Session] {
        let table = source.processes()
        let calls = claudeInvocations(in: table)

        var directories: Set<String> = [defaultDirectory]
        for case let directory? in calls.values.map(\.configDirectory) where directory.hasPrefix("/") {
            directories.insert((directory as NSString).standardizingPath)
        }

        var records: [Int32: (record: RegistryRecord, directory: String)] = [:]
        for directory in directories {
            for record in readRegistry(directory) {
                guard let process = table[record.pid], process.uid == uid else { continue }
                // Tras un cierre forzoso el fichero se queda y el PID puede reutilizarse.
                if let started = record.startedAt, process.started > started.addingTimeInterval(5) { continue }
                if let other = records[record.pid]?.record.startedAt, other >= (record.startedAt ?? .distantPast) { continue }
                records[record.pid] = (record, directory)
            }
        }

        var usedPaths: Set<String> = []
        var sessions: [Session] = []

        for (pid, found) in records {
            guard let process = table[pid] else { continue }
            let path = found.record.sessionID.flatMap { transcriptPath(id: $0, directory: found.directory) }
            if let path { usedPaths.insert(path) }
            sessions.append(makeSession(
                process: process, table: table, record: found.record, path: path,
                directory: found.record.directory ?? source.workingDirectory(of: pid)))
        }

        for process in unregistered(table: table, calls: calls, registered: Set(records.keys), now: now) {
            let directory = source.workingDirectory(of: process.pid)
            let config = calls[process.pid]?.configDirectory ?? defaultDirectory
            let path = directory.flatMap {
                newestTranscript(directory: $0, config: config, after: process.started, excluding: usedPaths)
            }
            if let path { usedPaths.insert(path) }
            sessions.append(makeSession(process: process, table: table, record: nil, path: path, directory: directory))
        }

        readers = readers.filter { usedPaths.contains($0.key) }
        transcriptPaths = transcriptPaths.filter { usedPaths.contains($0.value) }
        return sessions.sorted { ($0.startedAt, $0.pid) < ($1.startedAt, $1.pid) }
    }

    private func claudeInvocations(in table: [Int32: ProcessEntry]) -> [Int32: Invocation] {
        var cache: [InvocationKey: Invocation] = [:]
        var result: [Int32: Invocation] = [:]
        for process in table.values where process.uid == uid && ClaudeProcess.mightBeClaude(name: process.name) {
            let key = InvocationKey(pid: process.pid, started: process.started, name: process.name)
            guard let call = invocations[key] ?? source.invocation(of: process.pid) else { continue }
            cache[key] = call
            if ClaudeProcess.isClaude(call) { result[process.pid] = call }
        }
        invocations = cache
        return result
    }

    private func readRegistry(_ directory: String) -> [RegistryRecord] {
        let folder = directory + "/sessions"
        guard let names = try? files.contentsOfDirectory(atPath: folder) else { return [] }
        return names.compactMap { name in
            // Junto a los registros hay ficheros .key con credenciales: solo se abre <pid>.json.
            guard name.hasSuffix(".json"), Int32(name.dropLast(5)) != nil,
                  let data = files.contents(atPath: "\(folder)/\(name)")
            else { return nil }
            return RegistryRecord(json: data)
        }
    }

    private func unregistered(
        table: [Int32: ProcessEntry], calls: [Int32: Invocation], registered: Set<Int32>, now: Date
    ) -> [ProcessEntry] {
        let candidates = Set(calls.filter { !registered.contains($0.key) && ClaudeProcess.isSession($0.value) }.keys)
        guard !candidates.isEmpty else { return [] }

        // El lanzador de npm y los ayudantes de una sesión no son sesiones aparte.
        var wrappers: Set<Int32> = []
        for pid in candidates.union(registered) { wrappers.formUnion(ancestors(of: pid, in: table)) }

        return candidates.sorted().compactMap { pid in
            guard !wrappers.contains(pid), let process = table[pid],
                  now.timeIntervalSince(process.started) > 3,
                  registered.isDisjoint(with: ancestors(of: pid, in: table))
            else { return nil }
            return process
        }
    }

    private func ancestors(of pid: Int32, in table: [Int32: ProcessEntry]) -> [Int32] {
        var result: [Int32] = []
        var current = table[pid]?.parent ?? 0
        while current > 1, result.count < 24, !result.contains(current) {
            result.append(current)
            current = table[current]?.parent ?? 0
        }
        return result
    }

    private func transcriptPath(id: String, directory: String) -> String? {
        let key = directory + "|" + id
        if let path = transcriptPaths[key] { return path }
        let root = directory + "/projects"
        for project in (try? files.contentsOfDirectory(atPath: root)) ?? [] {
            let path = "\(root)/\(project)/\(id).jsonl"
            if files.fileExists(atPath: path) {
                transcriptPaths[key] = path
                return path
            }
        }
        return nil
    }

    private func newestTranscript(directory: String, config: String, after date: Date, excluding used: Set<String>) -> String? {
        let encoded = String(String.UnicodeScalarView(directory.unicodeScalars.map {
            $0.isASCII && ($0.properties.isAlphabetic || ("0"..."9").contains($0)) ? $0 : "-"
        }))
        let folder = "\(config)/projects/\(encoded)"
        var newest: (path: String, date: Date)?
        for name in (try? files.contentsOfDirectory(atPath: folder)) ?? [] where name.hasSuffix(".jsonl") {
            let path = "\(folder)/\(name)"
            guard !used.contains(path),
                  let modified = (try? files.attributesOfItem(atPath: path))?[.modificationDate] as? Date,
                  modified >= date, modified > (newest?.date ?? .distantPast)
            else { continue }
            newest = (path, modified)
        }
        return newest?.path
    }

    private func makeSession(
        process: ProcessEntry, table: [Int32: ProcessEntry], record: RegistryRecord?, path: String?, directory: String?
    ) -> Session {
        var transcript: Transcript?
        if let path {
            let reader = readers[path] ?? TranscriptReader(path: path)
            readers[path] = reader
            reader.refresh()
            transcript = reader.transcript
        }

        let (state, detail) = StateResolver.resolve(
            status: record?.status, waitingFor: record?.waitingFor, transcript: transcript)
        let started = record?.startedAt ?? process.started
        var since = record?.statusChanged ?? transcript?.lastEvent ?? started
        // Aprobar un permiso no debe reiniciar el cronómetro del turno.
        if state == .working, let turn = transcript?.turnStarted, turn >= process.started, transcript?.outcome == .running {
            since = turn
        }

        return Session(
            id: "\(process.pid)-\(Int(process.started.timeIntervalSince1970))-\(record?.sessionID ?? "")",
            pid: process.pid,
            project: Self.projectName(directory),
            title: record?.name ?? transcript?.title,
            state: state, detail: detail, since: since, startedAt: started,
            outcome: transcript?.outcome,
            ancestors: ancestors(of: process.pid, in: table),
            sessionID: record?.sessionID ?? path.map { (($0 as NSString).lastPathComponent as NSString).deletingPathExtension },
            tty: process.tty,
            tasks: transcript?.tasks,
            contextTokens: transcript?.contextTokens,
            lastMessage: transcript?.lastMessage)
    }

    static func projectName(_ directory: String?) -> String {
        guard var path = directory, !path.isEmpty else { return "Claude Code" }
        if let range = path.range(of: "/.claude/worktrees/") { path = String(path[..<range.lowerBound]) }
        return path == NSHomeDirectory() ? "~" : (path as NSString).lastPathComponent
    }
}
