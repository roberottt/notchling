import AppKit
import NotchCore

let options = Set(CommandLine.arguments.dropFirst())

if options.contains("--dump") {
    // Diagnóstico: qué ve el detector, sin abrir la interfaz.
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    if let data = try? encoder.encode(SessionScanner().scan()) {
        FileHandle.standardOutput.write(data + Data("\n".utf8))
    }
    exit(0)
}

if options.contains(PermissionHook.flag) {
    // Lo lanza Claude Code: pasa la petición a la app y escribe su decisión. Nunca falla.
    let request = FileHandle.standardInput.readDataToEndOfFile()
    if let output = PermissionHook.output(PermissionHook.ask(request: request)) {
        FileHandle.standardOutput.write(output)
    }
    exit(0)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate(demo: options.contains("--demo"))
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { app.run() }
}
