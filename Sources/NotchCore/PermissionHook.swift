import Darwin
import Foundation

/// Hook `PermissionRequest` de Claude Code para contestar permisos desde la isla.
///
/// Claude Code ejecuta `Notchling --permission-hook`, que pasa la petición a la app por un socket local
/// y espera la respuesta. Si la app no está abierta, no contesta a tiempo o eliges «Terminal»,
/// el hook termina sin decidir y Claude Code muestra su pregunta de siempre.
public enum PermissionHook {
    public static let flag = "--permission-hook"
    /// Lo que espera el hook antes de devolver la pregunta a la terminal.
    public static let wait: TimeInterval = 45
    /// Margen que se le da en settings.json, por encima de `wait`.
    public static let timeout = 60
    /// Herramientas con interfaz propia en Claude Code: aprobarlas sin verla no tiene sentido.
    public static let skipped: Set<String> = ["AskUserQuestion", "ExitPlanMode"]

    public enum Decision: String, CaseIterable, Sendable {
        case allow, deny
        /// Sin decidir: Claude Code pregunta en la terminal.
        case ask
    }

    public static var socketPath: String {
        NSHomeDirectory() + "/Library/Application Support/Notchling/permissions.sock"
    }

    /// Lo que el hook imprime para Claude Code. `nil` deja la decisión a la terminal.
    public static func output(_ decision: Decision) -> Data? {
        let body: [String: Any]
        switch decision {
        case .allow: body = ["behavior": "allow"]
        case .deny: body = ["behavior": "deny", "message": "Denied from Notchling"]
        case .ask: return nil
        }
        let output = ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": body]]
        return try? JSONSerialization.data(withJSONObject: output)
    }

    /// Texto corto de la petición, el de la fila de la isla.
    public static func describe(tool: String, input: [String: Any]) -> String {
        ToolCall(id: "", name: tool, input: input).permissionText
    }

    /// Lo más largo que se acepta aprobar desde la isla: cabe entero en la tarjeta.
    public static let maxShown = 400

    /// La petición completa, tal cual, si se puede enseñar entera. `nil` la manda a la terminal:
    /// comandos de varias líneas o muy largos, ediciones (la terminal enseña el diff) y herramientas
    /// cuya entrada no se puede resumir sin perder algo.
    public static func fullText(tool: String, input: [String: Any]) -> String? {
        func value(_ key: String) -> String? {
            guard let text = input[key] as? String, !text.isEmpty, text.count <= maxShown,
                  !text.contains(where: \.isNewline)
            else { return nil }
            return text
        }
        switch tool {
        case "Bash", "PowerShell": return value("command").map { tr("Ejecutar: \($0)", "Run: \($0)") }
        case "Read": return value("file_path").map { tr("Leer \($0)", "Read \($0)") }
        case "WebFetch": return value("url").map { tr("Acceder a \($0)", "Access \($0)") }
        case "WebSearch": return value("query").map { tr("Buscar en la web: \($0)", "Search the web: \($0)") }
        default: return nil
        }
    }

    // MARK: - Cliente (el proceso que lanza Claude Code)

    /// Pasa la petición a la app y devuelve su decisión. Cualquier fallo equivale a `.ask`.
    public static func ask(request: Data, socket path: String = socketPath, wait: TimeInterval = wait) -> Decision {
        guard let object = (try? JSONSerialization.jsonObject(with: request)) as? [String: Any],
              let tool = object["tool_name"] as? String, !skipped.contains(tool),
              fullText(tool: tool, input: object["tool_input"] as? [String: Any] ?? [:]) != nil,
              let line = try? JSONSerialization.data(withJSONObject: object)
        else { return .ask }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return .ask }
        defer { close(fd) }
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        var limit = timeval(tv_sec: Int(wait), tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &limit, socklen_t(MemoryLayout<timeval>.size))

        guard var address = Self.socketAddress(path),
              withUnsafePointer(to: &address, {
                  $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                      connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                  }
              }) == 0
        else { return .ask }

        let message = line + Data("\n".utf8)
        let sent = message.withUnsafeBytes { send(fd, $0.baseAddress, $0.count, 0) }
        guard sent == message.count else { return .ask }

        var reply = Data()
        var buffer = [UInt8](repeating: 0, count: 64)
        while !reply.contains(UInt8(ascii: "\n")) {
            let count = recv(fd, &buffer, buffer.count, 0)
            guard count > 0 else { break }
            reply.append(contentsOf: buffer.prefix(count))
        }
        let word = String(decoding: reply, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return Decision(rawValue: word) ?? .ask
    }

    public static func socketAddress(_ path: String) -> sockaddr_un? {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else { return nil }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        return address
    }

    // MARK: - settings.json

    /// Orden con la que Claude Code lanza el hook.
    public static func command(executable: String) -> String {
        "'" + executable.replacingOccurrences(of: "'", with: "'\\''") + "' " + flag
    }

    public static func isInstalled(in settings: [String: Any]) -> Bool {
        groups(settings).contains { group in handlers(group).contains(where: isOurs) }
    }

    /// Añade el hook (o actualiza la ruta si ya estaba) sin tocar el resto de la configuración.
    public static func installing(command: String, into settings: [String: Any]) -> [String: Any] {
        var result = removing(from: settings)
        var hooks = result["hooks"] as? [String: Any] ?? [:]
        var list = hooks["PermissionRequest"] as? [[String: Any]] ?? []
        list.append(["hooks": [["type": "command", "command": command, "timeout": timeout]]])
        hooks["PermissionRequest"] = list
        result["hooks"] = hooks
        return result
    }

    /// Quita solo nuestro hook y deja limpias las listas que se queden vacías.
    public static func removing(from settings: [String: Any]) -> [String: Any] {
        var result = settings
        guard var hooks = result["hooks"] as? [String: Any],
              let list = hooks["PermissionRequest"] as? [[String: Any]]
        else { return result }

        let kept: [[String: Any]] = list.compactMap { group in
            let mine = handlers(group).filter(isOurs)
            guard !mine.isEmpty else { return group }
            let others = handlers(group).filter { !isOurs($0) }
            guard !others.isEmpty else { return nil }
            var copy = group
            copy["hooks"] = others
            return copy
        }
        if kept.isEmpty { hooks["PermissionRequest"] = nil } else { hooks["PermissionRequest"] = kept }
        if hooks.isEmpty { result["hooks"] = nil } else { result["hooks"] = hooks }
        return result
    }

    private static func groups(_ settings: [String: Any]) -> [[String: Any]] {
        (settings["hooks"] as? [String: Any])?["PermissionRequest"] as? [[String: Any]] ?? []
    }

    private static func handlers(_ group: [String: Any]) -> [[String: Any]] {
        group["hooks"] as? [[String: Any]] ?? []
    }

    private static func isOurs(_ handler: [String: Any]) -> Bool {
        guard let command = handler["command"] as? String else { return false }
        return command.hasSuffix(" " + flag) && command.contains("Notchling")
    }
}
