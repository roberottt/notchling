import Foundation

/// Decide si un proceso es una sesión de Claude Code o solo uno de sus ayudantes.
enum ClaudeProcess {
    private static let helperFlags: Set<String> = [
        "--chrome-native-host", "--claude-in-chrome-mcp", "--computer-use-mcp", "--bg-spare", "--bg-pty-host",
        "--version", "-v", "--help", "-h",
    ]
    private static let subcommands: Set<String> = [
        "agents", "attach", "auth", "config", "daemon", "doctor", "gateway", "install", "logs", "mcp",
        "plugin", "plugins", "remote-control", "rm", "setup-token", "stop", "update", "upgrade",
    ]

    /// Filtro barato por nombre, antes de pedir los argumentos al sistema.
    static func mightBeClaude(name: String) -> Bool {
        if name == "claude" || name == "node" || name == "bun" { return true }
        // El instalador nativo nombra el binario con su versión: «2.1.330».
        let parts = name.split(separator: ".")
        return parts.count == 3 && parts.allSatisfy { Int($0) != nil }
    }

    static func isClaude(_ call: Invocation) -> Bool { userArguments(call) != nil }

    static func isSession(_ call: Invocation) -> Bool {
        guard let arguments = userArguments(call) else { return false }
        if arguments.contains(where: helperFlags.contains) { return false }
        if let first = arguments.first, subcommands.contains(first) { return false }
        return true
    }

    private static func userArguments(_ call: Invocation) -> [String]? {
        guard let first = call.arguments.first else { return nil }
        let command = (first as NSString).lastPathComponent
        // El binario nativo también hace de rg, ugrep o bfs, por eso manda argv[0] y no la ruta.
        if command == "claude" { return Array(call.arguments.dropFirst()) }
        if call.executable.contains("/claude/versions/"), command == (call.executable as NSString).lastPathComponent {
            return Array(call.arguments.dropFirst())
        }
        guard command == "node" || command == "bun",
              let script = call.arguments.dropFirst().firstIndex(where: { !$0.hasPrefix("-") })
        else { return nil }
        let path = call.arguments[script]
        let isCLI = path.hasSuffix("/bin/claude")
            || path.hasSuffix("@anthropic-ai/claude-code/cli.js")
            || path.hasSuffix("@anthropic-ai/claude-code/cli.mjs")
        return isCLI ? Array(call.arguments[(script + 1)...]) : nil
    }
}
