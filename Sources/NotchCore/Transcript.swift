import Foundation

public struct ToolCall: Equatable, Sendable {
    public var id: String
    public var name: String
    /// Lo que sale de la entrada de la herramienta, sin traducir. Puede estar vacío.
    private var target: String
    /// La descripción que acompaña a un comando.
    private var note: String?

    init(id: String, name: String, input: [String: Any]) {
        self.id = id
        self.name = name

        func text(_ key: String) -> String? {
            (input[key] as? String).flatMap { $0.isEmpty ? nil : $0.singleLine() }
        }
        func file(_ key: String) -> String? {
            (input[key] as? String).map { ($0 as NSString).lastPathComponent.singleLine() }
        }

        switch name {
        case "Bash", "PowerShell":
            target = text("command") ?? ""
            note = text("description")
        case "Edit", "MultiEdit", "Write", "NotebookEdit":
            target = file("file_path") ?? file("notebook_path") ?? ""
        case "Read":
            target = file("file_path") ?? ""
        case "Grep", "Glob":
            target = text("pattern") ?? ""
        case "WebFetch":
            target = (input["url"] as? String).flatMap { URL(string: $0)?.host } ?? ""
        case "WebSearch":
            target = text("query") ?? ""
        case "Agent", "Task":
            target = text("description") ?? ""
        case "AskUserQuestion":
            let questions = input["questions"] as? [[String: Any]]
            target = (questions?.first?["question"] as? String)?.singleLine() ?? ""
        case "Skill":
            target = text("skill") ?? ""
        default:
            target = name.hasPrefix("mcp__") ? name.dropFirst(5).components(separatedBy: "__").joined(separator: " › ") : name
        }
    }

    /// Los textos se componen al leerlos para que un cambio de idioma se vea al momento.
    var subject: String {
        switch name {
        case "WebFetch": target.isEmpty ? tr("una web", "a website") : target
        case "AskUserQuestion": target.isEmpty ? tr("Tiene una pregunta para ti", "Has a question for you") : target
        case "ExitPlanMode": tr("El plan está listo para revisar", "The plan is ready for review")
        case "TodoWrite", "TaskCreate", "TaskUpdate", "TaskList", "TaskGet": tr("tareas", "tasks")
        default: target
        }
    }

    var summary: String {
        switch name {
        case "Bash", "PowerShell": note ?? subject
        case "Write": tr("Escribiendo \(subject)", "Writing \(subject)")
        case "Edit", "MultiEdit", "NotebookEdit": tr("Editando \(subject)", "Editing \(subject)")
        case "Read": tr("Leyendo \(subject)", "Reading \(subject)")
        case "Grep", "Glob": tr("Buscando \(subject)", "Searching \(subject)")
        case "WebFetch": tr("Consultando \(subject)", "Fetching \(subject)")
        case "WebSearch": tr("Buscando en la web: \(subject)", "Searching the web: \(subject)")
        case "Agent", "Task": tr("Subagente: \(subject)", "Subagent: \(subject)")
        case "Skill": "Skill: \(subject)"
        case "TodoWrite", "TaskCreate", "TaskUpdate", "TaskList", "TaskGet": tr("Organizando tareas", "Organizing tasks")
        default: subject
        }
    }

    var permissionText: String {
        switch name {
        case "Bash", "PowerShell": tr("Ejecutar: \(subject)", "Run: \(subject)")
        case "Edit", "MultiEdit", "Write", "NotebookEdit": tr("Modificar \(subject)", "Modify \(subject)")
        case "Read": tr("Leer \(subject)", "Read \(subject)")
        case "WebFetch": tr("Acceder a \(subject)", "Access \(subject)")
        case "Agent", "Task": tr("Un subagente pide permiso", "A subagent asks for permission")
        default: tr("Usar \(subject.isEmpty ? name : subject)", "Use \(subject.isEmpty ? name : subject)")
        }
    }
}

/// Qué está haciendo Claude cuando no hay herramientas pendientes.
public enum Activity: Sendable {
    case thinking, writing, retrying, compacted

    public var text: String {
        switch self {
        case .thinking: tr("Pensando", "Thinking")
        case .writing: tr("Escribiendo", "Writing")
        case .retrying: tr("Reintentando la conexión", "Retrying the connection")
        case .compacted: tr("Contexto compactado", "Context compacted")
        }
    }
}

/// Resumen de una conversación, alimentado línea a línea.
public struct Transcript: Sendable {
    public private(set) var title: String?
    public private(set) var pending: [ToolCall] = []
    public private(set) var outcome: TurnOutcome?
    public private(set) var turnStarted: Date?
    public private(set) var lastEvent: Date?
    public private(set) var lastText: String?
    public private(set) var activity = Activity.thinking
    /// El último mensaje de Claude con más margen que `lastText`, para la vista previa.
    public private(set) var lastMessage: String?
    public private(set) var contextTokens: Int?
    private var hasCustomTitle = false
    /// Tareas por identificador: si están hechas.
    private var taskList: [(id: String, done: Bool)] = []
    private var createdTasks = 0

    public var tasks: TaskProgress? {
        taskList.isEmpty ? nil : TaskProgress(done: taskList.filter(\.done).count, total: taskList.count)
    }

    public init() {}

    private static let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    public mutating func consume(line: Data) {
        guard let entry = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
              let type = entry["type"] as? String,
              entry["isSidechain"] as? Bool != true
        else { return }
        let date = (entry["timestamp"] as? String).flatMap {
            (try? Date($0, strategy: Self.fractional)) ?? (try? Date($0, strategy: .iso8601))
        }

        switch type {
        case "custom-title":
            if let value = entry["customTitle"] as? String {
                title = value.singleLine()
                hasCustomTitle = true
            }
        case "ai-title":
            if !hasCustomTitle, let value = entry["aiTitle"] as? String { title = value.singleLine() }
        case "system":
            switch entry["subtype"] as? String {
            case "api_error": activity = .retrying
            case "compact_boundary": activity = .compacted
            default: break
            }
        case "user":
            consumeUser(entry, at: date)
        case "assistant":
            consumeAssistant(entry, at: date)
        default:
            break
        }
    }

    private mutating func consumeUser(_ entry: [String: Any], at date: Date?) {
        guard let message = entry["message"] as? [String: Any] else { return }
        let blocks = (message["content"] as? [[String: Any]])
            ?? (message["content"] as? String).map { [["type": "text", "text": $0]] }
            ?? []

        var hasResult = false
        for block in blocks where block["type"] as? String == "tool_result" {
            hasResult = true
            let id = block["tool_use_id"] as? String
            pending.removeAll { $0.id == id }
            activity = .thinking
        }

        let text = blocks.compactMap { $0["text"] as? String }.first ?? ""
        if text.hasPrefix("[Request interrupted") {
            pending = []
            outcome = .interrupted
            lastEvent = date ?? lastEvent
            return
        }
        if hasResult {
            outcome = .running
            lastEvent = date ?? lastEvent
            return
        }
        // Mensajes internos y comandos locales: no empiezan un turno.
        if entry["isMeta"] as? Bool == true || entry["isCompactSummary"] as? Bool == true { return }
        if ["<local-command", "<bash-", "<command-"].contains(where: text.hasPrefix) { return }
        guard !blocks.isEmpty else { return }

        pending = []
        lastText = nil
        outcome = .running
        activity = .thinking
        turnStarted = date
        lastEvent = date ?? lastEvent
    }

    private mutating func consumeAssistant(_ entry: [String: Any], at date: Date?) {
        guard let message = entry["message"] as? [String: Any] else { return }
        let blocks = message["content"] as? [[String: Any]] ?? []
        let isError = entry["isApiErrorMessage"] as? Bool == true
        if !isError, message["model"] as? String == "<synthetic>" { return }
        lastEvent = date ?? lastEvent
        if let usage = message["usage"] as? [String: Any] {
            let keys = ["input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"]
            let total = keys.reduce(0) { $0 + ((usage[$1] as? Int) ?? 0) }
            if total > 0 { contextTokens = total }
        }

        for block in blocks {
            switch block["type"] as? String {
            case "thinking", "redacted_thinking":
                activity = .thinking
            case "text":
                if let text = block["text"] as? String, !text.isEmpty {
                    lastText = text.singleLine()
                    lastMessage = text.singleLine(limit: 900)
                    activity = .writing
                }
            case "tool_use":
                guard let id = block["id"] as? String, let name = block["name"] as? String,
                      !pending.contains(where: { $0.id == id })
                else { continue }
                let input = block["input"] as? [String: Any] ?? [:]
                pending.append(ToolCall(id: id, name: name, input: input))
                trackTasks(name: name, input: input)
            default:
                break
            }
        }

        if isError {
            pending = []
            outcome = .failed
        } else if let reason = message["stop_reason"] as? String,
                  ["end_turn", "stop_sequence", "max_tokens", "refusal"].contains(reason) {
            pending = []
            outcome = .completed
        } else {
            outcome = .running
        }
    }

    /// TodoWrite manda la lista entera; TaskCreate y TaskUpdate la cambian de una en una
    /// (Claude Code numera las tareas creadas desde 1).
    private mutating func trackTasks(name: String, input: [String: Any]) {
        switch name {
        case "TodoWrite":
            let todos = input["todos"] as? [[String: Any]] ?? []
            taskList = todos.enumerated().map { (String($0.offset), $0.element["status"] as? String == "completed") }
        case "TaskCreate":
            createdTasks += 1
            taskList.append((String(createdTasks), false))
        case "TaskUpdate":
            let id = (input["taskId"] as? String) ?? (input["taskId"] as? Int).map(String.init)
            guard let id, let index = taskList.firstIndex(where: { $0.id == id }) else { return }
            switch input["status"] as? String {
            case "completed": taskList[index].done = true
            case "deleted": taskList.remove(at: index)
            case "pending", "in_progress": taskList[index].done = false
            default: break
            }
        default:
            break
        }
    }
}

/// Lee solo lo que se añade al fichero: un transcript puede pesar cientos de MB.
final class TranscriptReader {
    private static let initialTail: UInt64 = 2 << 20
    private static let maximumCatchUp: UInt64 = 8 << 20

    private let path: String
    private var offset: UInt64?
    private var lastSize: UInt64?
    private(set) var transcript = Transcript()

    init(path: String) { self.path = path }

    func refresh() {
        var status = stat()
        guard stat(path, &status) == 0 else { return }
        let size = UInt64(status.st_size)
        guard size != lastSize else { return }

        if let offset, size < offset || size - offset > Self.maximumCatchUp {
            self.offset = nil
            transcript = Transcript()
        }
        guard let handle = FileHandle(forReadingAtPath: path) else { return }
        defer { try? handle.close() }

        let first = offset == nil
        let start = offset ?? (size > Self.initialTail ? size - Self.initialTail : 0)
        guard (try? handle.seek(toOffset: start)) != nil,
              let data = try? handle.readToEnd() ?? Data()
        else { return }
        lastSize = size

        // La última línea puede estar a medio escribir: se deja para la siguiente lectura.
        guard let end = data.lastIndex(of: 0x0A) else {
            if first { offset = start }
            return
        }
        var lines = data[data.startIndex..<end].split(separator: 0x0A, omittingEmptySubsequences: false)
        if first, start > 0, !lines.isEmpty { lines.removeFirst() }
        for line in lines where !line.isEmpty { transcript.consume(line: Data(line)) }
        offset = start + UInt64(end - data.startIndex) + 1
    }

}
