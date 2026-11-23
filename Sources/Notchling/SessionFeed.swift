import Foundation
import NotchCore

/// Consulta el escáner fuera del hilo principal.
final class SessionFeed {
    private let queue = DispatchQueue(label: "notchling.scanner", qos: .utility)
    private var timer: DispatchSourceTimer?

    func start(demo: Bool, deliver: @escaping @MainActor ([Session]) -> Void) {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(400), leeway: .milliseconds(100))

        let scanner = SessionScanner()
        let began = Date()
        timer.setEventHandler {
            autoreleasepool {
                let sessions = demo ? Demo.sessions(began: began) : scanner.scan()
                DispatchQueue.main.async { MainActor.assumeIsolated { deliver(sessions) } }
            }
        }
        timer.resume()
        self.timer = timer
    }
}
