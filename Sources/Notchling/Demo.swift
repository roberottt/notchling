import Foundation
import NotchCore

/// `--demo`: recorre todos los estados con sesiones inventadas.
enum Demo {
    private static var steps: [(state: SessionState, detail: String)] { [
        (.working, tr("Editando AppDelegate.swift", "Editing AppDelegate.swift")),
        (.permission, tr("Ejecutar: npm install", "Run: npm install")),
        (.working, tr("Ejecutando los tests", "Running the tests")),
        (.question, tr("¿Qué base de datos quieres usar?", "Which database do you want to use?")),
        (.working, tr("Buscando referencias", "Searching for references")),
        (.plan, tr("El plan está listo para revisar", "The plan is ready for review")),
        (.working, Activity.writing.text),
        (.idle, tr("He terminado la migración", "I've finished the migration")),
    ] }

    static func sessions(began: Date, now: Date = Date()) -> [Session] {
        let elapsed = Int(now.timeIntervalSince(began) / 9)
        let step = steps[elapsed % steps.count]
        var main = Session(
            id: "demo-1", pid: 1, project: tr("tienda-web", "web-store"), title: tr("Migrar los pagos", "Migrate payments"),
            state: step.state, detail: step.detail,
            since: began.addingTimeInterval(Double(elapsed * 9)), startedAt: began,
            tasks: TaskProgress(done: min(elapsed % steps.count, 5), total: 6), contextTokens: 61_000 + elapsed * 3_400,
            lastMessage: tr(
                "He movido los pagos a la nueva API. Faltan los reembolsos y los tests de integración; ¿sigo con eso?",
                "I've moved payments to the new API. Refunds and the integration tests are still left. Shall I continue with those?"))
        // Así se ven los botones de un permiso, aunque en la demo no hacen nada.
        main.awaitingDecision = step.state == .permission
        return [
            main,
            Session(
                id: "demo-2", pid: 2, project: "api", title: tr("Documentar endpoints", "Document endpoints"),
                state: .background, detail: tr("Comando en segundo plano", "Command running in the background"),
                since: began.addingTimeInterval(-95), startedAt: began, contextTokens: 128_000),
            Session(
                id: "demo-3", pid: 3, project: tr("notas", "notes"),
                state: .idle, detail: tr("Esperando tu siguiente mensaje", "Waiting for your next message"),
                since: began.addingTimeInterval(-640), startedAt: began, contextTokens: 23_000,
                lastMessage: tr(
                    "Listo: he resumido las notas de la reunión en tres puntos y las he guardado en notas/2026-11-23.md.",
                    "Done: I summarized the meeting notes into three points and saved them to notes/2026-11-23.md.")),
        ]
    }
}
