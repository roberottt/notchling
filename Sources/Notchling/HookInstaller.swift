import AppKit
import NotchCore

/// Pone y quita el hook de permisos en ~/.claude/settings.json.
/// Es lo único que Notchling escribe fuera de su carpeta, y solo cuando lo activas.
@MainActor
enum HookInstaller {
    static let settings = URL(fileURLWithPath: NSHomeDirectory() + "/.claude/settings.json")
    private static var backup: URL { settings.appendingPathExtension("notchling-backup") }

    enum Failure: LocalizedError {
        case unreadable

        var errorDescription: String? {
            tr("No se puede leer ~/.claude/settings.json: no es JSON válido. No se ha tocado.",
               "~/.claude/settings.json isn't valid JSON, so it was left untouched.")
        }
    }

    static var isInstalled: Bool {
        (try? read()).map(PermissionHook.isInstalled(in:)) ?? false
    }

    private static var command: String? {
        Bundle.main.executablePath.map(PermissionHook.command(executable:))
    }

    /// Si la app se ha movido de sitio, el hook apunta a la ruta vieja: se corrige al arrancar.
    static func refresh() {
        guard isInstalled, let command, let current = try? read(),
              !(current.description.contains(command))
        else { return }
        try? install()
    }

    static func install() throws {
        guard let command else { return }
        let current = try read()
        if FileManager.default.fileExists(atPath: settings.path), !FileManager.default.fileExists(atPath: backup.path) {
            try FileManager.default.copyItem(at: settings, to: backup)
        }
        try write(PermissionHook.installing(command: command, into: current))
    }

    static func uninstall() throws {
        try write(PermissionHook.removing(from: try read()))
    }

    /// Pregunta antes de tocar la configuración de Claude Code.
    static func confirmInstall() -> Bool {
        let alert = NSAlert()
        alert.messageText = tr("¿Aprobar permisos desde la isla?", "Approve permissions from the island?")
        alert.informativeText = tr(
            """
            Notchling añadirá un hook a ~/.claude/settings.json (antes guarda una copia en settings.json.notchling-backup). \
            Cuando Claude pida permiso, la isla mostrará Permitir, Denegar y Terminal. \
            Si Notchling está cerrado, no contestas en \(Int(PermissionHook.wait)) s o eliges Terminal, \
            Claude Code pregunta en la terminal como siempre. Afecta a las sesiones que empieces a partir de ahora.
            """,
            """
            Notchling will add a hook to ~/.claude/settings.json (it saves a copy to settings.json.notchling-backup first). \
            When Claude asks for permission, the island shows Allow, Deny and Terminal. \
            If Notchling is closed, you don't answer within \(Int(PermissionHook.wait)) s, or you choose Terminal, \
            Claude Code asks in the terminal as usual. It applies to sessions you start from now on.
            """)
        alert.addButton(withTitle: tr("Activar", "Turn on"))
        alert.addButton(withTitle: tr("Cancelar", "Cancel"))
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn
    }

    private static func read() throws -> [String: Any] {
        guard let data = try? Data(contentsOf: settings), !data.isEmpty else { return [:] }
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { throw Failure.unreadable }
        return object
    }

    private static func write(_ object: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .withoutEscapingSlashes])
        try FileManager.default.createDirectory(
            at: settings.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: settings, options: .atomic)
    }
}
