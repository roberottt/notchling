import Foundation

/// Ordenados de más a menos urgente: el primero es el que se muestra junto al notch.
public enum SessionState: Int, CaseIterable, Comparable, Encodable, Sendable {
    case permission, question, plan, input, error, dialog, done, working, background, idle, unknown

    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    /// Claude está parado hasta que el usuario responda.
    public var needsUser: Bool {
        switch self {
        case .permission, .question, .plan, .input: true
        default: false
        }
    }

    public var label: String {
        switch self {
        case .permission: tr("Permiso", "Permission")
        case .question: tr("Pregunta", "Question")
        case .plan: tr("Revisar plan", "Review plan")
        case .input: tr("Te necesita", "Needs you")
        case .error: "Error"
        case .dialog: tr("Menú abierto", "Menu open")
        case .done: tr("Listo", "Done")
        case .working: tr("Trabajando", "Working")
        case .background: tr("2º plano", "Background")
        case .idle: tr("En espera", "Idle")
        case .unknown: tr("Detectada", "Detected")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(String(describing: self))
    }
}

/// Avance de la lista de tareas de Claude.
public struct TaskProgress: Equatable, Encodable, Sendable {
    public var done: Int
    public var total: Int

    public init(done: Int, total: Int) {
        self.done = done
        self.total = total
    }
}

public struct Session: Identifiable, Equatable, Encodable, Sendable {
    public var id: String
    public var pid: Int32
    public var project: String
    public var title: String?
    public var state: SessionState
    public var detail: String
    /// Momento desde el que cuenta el cronómetro de la fila.
    public var since: Date
    public var startedAt: Date
    public var outcome: TurnOutcome?
    /// Procesos padre, del más cercano al más lejano. Sirve para encontrar la app que aloja la sesión.
    public var ancestors: [Int32]
    /// Identificador de la conversación en Claude Code; se conserva al reanudarla.
    public var sessionID: String?
    public var tty: String?
    public var tasks: TaskProgress?
    /// Tokens que ocupa el contexto tras la última respuesta.
    public var contextTokens: Int?
    /// El último mensaje de Claude, más largo que el detalle.
    public var lastMessage: String?

    // Lo decide la app, no el escáner.
    public var pinned = false
    public var muted = false
    /// Hay un permiso esperando respuesta desde la isla.
    public var awaitingDecision = false
    /// La petición concreta que enseñan los botones: decidir otra distinta no vale.
    public var pendingRequest: UUID?
    /// El texto completo de esa petición.
    public var requestText: String?

    public init(
        id: String, pid: Int32, project: String, title: String? = nil, state: SessionState,
        detail: String = "", since: Date, startedAt: Date, outcome: TurnOutcome? = nil, ancestors: [Int32] = [],
        sessionID: String? = nil, tty: String? = nil, tasks: TaskProgress? = nil, contextTokens: Int? = nil,
        lastMessage: String? = nil
    ) {
        self.id = id
        self.pid = pid
        self.project = project
        self.title = title
        self.state = state
        self.detail = detail
        self.since = since
        self.startedAt = startedAt
        self.outcome = outcome
        self.ancestors = ancestors
        self.sessionID = sessionID
        self.tty = tty
        self.tasks = tasks
        self.contextTokens = contextTokens
        self.lastMessage = lastMessage
    }

    /// Clave estable para recordar preferencias de la sesión entre reinicios.
    public var key: String { sessionID ?? id }
}

public enum TurnOutcome: String, Encodable, Sendable {
    case running, completed, interrupted, failed
}

extension String {
    /// Una sola línea y con longitud acotada, apta para pintar.
    func singleLine(limit: Int = 120) -> String {
        // Se recorta antes de procesar: un comando puede ocupar cientos de KB.
        let flat = prefix(limit * 3).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return flat.count > limit ? String(flat.prefix(limit - 1)) + "…" : flat
    }
}
