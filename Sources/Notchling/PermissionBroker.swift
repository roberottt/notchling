import Darwin
import Foundation
import NotchCore

/// Recibe las peticiones del hook por un socket local y guarda cada conexión abierta
/// hasta que se decide. Si Claude Code corta el hook (porque contestaste en la terminal), se olvida.
@MainActor
final class PermissionBroker {
    struct Request {
        let id = UUID()
        let sessionID: String
        let text: String
        /// Completo, sin recortar: es lo que se aprueba.
        let fullText: String
        let arrived = Date()
        fileprivate let source: DispatchSourceRead
        fileprivate let fd: Int32
    }

    private(set) var pending: [Request] = []
    var onChange: () -> Void = {}

    private let queue = DispatchQueue(label: "notchling.permissions")
    private var listener: DispatchSourceRead?
    private let path = PermissionHook.socketPath

    func start() {
        let folder = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        unlink(path)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0, var address = PermissionHook.socketAddress(path) else { return }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        // Solo este usuario puede hablar con la app.
        guard bound == 0, chmod(path, 0o600) == 0, listen(fd, 8) == 0 else {
            close(fd)
            return
        }

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            let client = accept(fd, nil, nil)
            guard client >= 0 else { return }
            Self.receive(client) { request in
                Task { @MainActor in self?.add(client: client, request: request) }
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        listener = source
    }

    func stop() {
        listener?.cancel()
        listener = nil
        for request in pending { decide(request.id, .ask) }
        unlink(path)
    }

    func request(for sessionID: String?) -> Request? {
        guard let sessionID else { return nil }
        return pending.first { $0.sessionID == sessionID }
    }

    func decide(_ id: UUID, _ decision: PermissionHook.Decision) {
        guard let index = pending.firstIndex(where: { $0.id == id }) else { return }
        let request = pending.remove(at: index)
        let line = decision.rawValue + "\n"
        _ = line.withCString { send(request.fd, $0, strlen($0), 0) }
        request.source.cancel()
        onChange()
    }

    /// Lee la línea con la petición fuera del hilo principal. Si no llega en 2 s, se descarta.
    nonisolated private static func receive(_ fd: Int32, then deliver: @escaping @Sendable ([String: Any]?) -> Void) {
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        var limit = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &limit, socklen_t(MemoryLayout<timeval>.size))

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while !data.contains(UInt8(ascii: "\n")), data.count < 1 << 20 {
            let count = recv(fd, &buffer, buffer.count, 0)
            guard count > 0 else { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        let object = (try? JSONSerialization.jsonObject(with: data.prefix { $0 != UInt8(ascii: "\n") })) as? [String: Any]
        nonisolated(unsafe) let request = object
        deliver(request)
    }

    private func add(client fd: Int32, request object: [String: Any]?) {
        guard let object, let session = object["session_id"] as? String, let tool = object["tool_name"] as? String else {
            close(fd)
            return
        }
        let input = object["tool_input"] as? [String: Any] ?? [:]
        // El hook ya filtra, pero la app no se fía: lo que no se puede enseñar entero va a la terminal.
        guard let full = PermissionHook.fullText(tool: tool, input: input) else {
            _ = "ask\n".withCString { send(fd, $0, 4, 0) }
            close(fd)
            return
        }

        // Si el hook se cierra (tiempo agotado o respuesta en la terminal), el socket se vuelve legible con 0 bytes.
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        let request = Request(
            sessionID: session, text: PermissionHook.describe(tool: tool, input: input), fullText: full,
            source: source, fd: fd)
        let id = request.id
        source.setEventHandler { [weak self] in
            var byte: UInt8 = 0
            guard recv(fd, &byte, 1, MSG_PEEK | MSG_DONTWAIT) <= 0 else { return }
            MainActor.assumeIsolated { self?.forget(id) }
        }
        source.setCancelHandler { close(fd) }
        pending.append(request)
        source.resume()
        onChange()
    }

    private func forget(_ id: UUID) {
        guard let index = pending.firstIndex(where: { $0.id == id }) else { return }
        pending.remove(at: index).source.cancel()
        onChange()
    }
}
