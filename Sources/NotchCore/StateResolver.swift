import Foundation

/// Una entrada de ~/.claude/sessions/<pid>.json. Es un formato interno, así que todo es opcional.
struct RegistryRecord {
    var pid: Int32
    var sessionID: String?
    var directory: String?
    var startedAt: Date?
    var status: String?
    var waitingFor: String?
    var statusChanged: Date?
    var name: String?

    init?(json data: Data) {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let number = object["pid"] as? Int, let pid = Int32(exactly: number)
        else { return nil }
        // Sesiones de contenedores que comparten la carpeta: su PID no significa nada aquí.
        if let domain = object["pidDomain"] as? String, domain != "darwin" { return nil }
        if object["spare"] as? Bool == true { return nil }

        func date(_ key: String) -> Date? {
            (object[key] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
        }
        self.pid = pid
        // El id acaba formando parte de una ruta.
        if let id = object["sessionId"] as? String, !id.isEmpty,
           id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) {
            sessionID = id
        }
        directory = object["cwd"] as? String
        startedAt = date("startedAt")
        status = object["status"] as? String
        waitingFor = object["waitingFor"] as? String
        statusChanged = date("statusUpdatedAt")
        // Los nombres derivados («proyecto-4f») aportan menos que el título de la conversación.
        if let source = object["nameSource"] as? String, source != "derived" {
            name = (object["name"] as? String)?.singleLine()
        }
    }
}

enum StateResolver {
    static func resolve(status: String?, waitingFor: String?, transcript: Transcript?) -> (SessionState, String) {
        let pending = transcript?.pending ?? []
        let question = pending.first { $0.name == "AskUserQuestion" }
        let plan = pending.first { $0.name == "ExitPlanMode" }
        let working = pending.last?.summary ?? (transcript?.activity ?? .thinking).text
        let resting = transcript?.lastText ?? tr("Esperando tu siguiente mensaje", "Waiting for your next message")

        switch status {
        case "busy":
            return (.working, working)
        case "idle":
            return (.idle, resting)
        case "shell":
            return (.background, tr("Comando en segundo plano", "Command running in the background"))
        case "waiting":
            switch waitingFor {
            case "permission prompt":
                if let plan { return (.plan, plan.subject) }
                if let question { return (.question, question.subject) }
                // En llamadas paralelas el permiso se pide en orden.
                return (.permission, pending.first?.permissionText ?? tr("Necesita tu aprobación", "Needs your approval"))
            case "input needed":
                if let question { return (.question, question.subject) }
                return (.question, tr("Necesita una respuesta", "Needs an answer"))
            case "sandbox request":
                return (.permission, tr("Acceso a la red desde el sandbox", "Network access from the sandbox"))
            case "worker request":
                return (.permission, tr("Un subagente pide permiso", "A subagent asks for permission"))
            case "goal proposal":
                return (.permission, tr("Propone un objetivo para la sesión", "Proposes a goal for the session"))
            case "dialog open":
                return (.dialog, tr("Hay un diálogo abierto en la sesión", "A dialog is open in the session"))
            default:
                return (.input, waitingFor?.singleLine() ?? tr("Necesita tu atención", "Needs your attention"))
            }
        default:
            // Sin estado en el registro solo queda deducirlo. Los permisos no se pueden deducir.
            guard let transcript, let outcome = transcript.outcome else { return (.unknown, tr("Sin información de estado", "No status information")) }
            if let question { return (.question, question.subject) }
            if let plan { return (.plan, plan.subject) }
            return outcome == .running ? (.working, working) : (.idle, resting)
        }
    }
}
