import Darwin
import Foundation

public struct ProcessEntry: Sendable {
    public var pid: Int32
    public var parent: Int32
    public var uid: UInt32
    public var name: String
    public var started: Date
    /// Terminal de control, p. ej. "/dev/ttys003". Sirve para encontrar la pestaña exacta.
    public var tty: String?

    public init(pid: Int32, parent: Int32, uid: UInt32, name: String, started: Date, tty: String? = nil) {
        self.pid = pid
        self.parent = parent
        self.uid = uid
        self.name = name
        self.started = started
        self.tty = tty
    }
}

public struct Invocation: Sendable {
    public var executable: String
    public var arguments: [String]
    /// Lo único que se conserva del entorno del proceso; el resto puede contener secretos.
    public var configDirectory: String?

    public init(executable: String, arguments: [String], configDirectory: String? = nil) {
        self.executable = executable
        self.arguments = arguments
        self.configDirectory = configDirectory
    }
}

public protocol ProcessSource {
    func processes() -> [Int32: ProcessEntry]
    func invocation(of pid: Int32) -> Invocation?
    func workingDirectory(of pid: Int32) -> String?
}

public struct SystemProcesses: ProcessSource {
    public init() {}

    public func processes() -> [Int32: ProcessEntry] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0 else { return [:] }

        let stride = MemoryLayout<kinfo_proc>.stride
        // Margen por si nacen procesos entre las dos llamadas.
        var list = [kinfo_proc](repeating: kinfo_proc(), count: size / stride + 64)
        size = list.count * stride
        guard sysctl(&mib, 3, &list, &size, nil, 0) == 0 else { return [:] }

        var result = [Int32: ProcessEntry](minimumCapacity: size / stride)
        for var info in list.prefix(size / stride) where info.kp_proc.p_stat != SZOMB {
            let name = withUnsafeBytes(of: &info.kp_proc.p_comm) {
                String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self)
            }
            let time = info.kp_proc.p_un.__p_starttime
            let device = info.kp_eproc.e_tdev
            let tty = device == -1 ? nil : devname(device, S_IFCHR).map { "/dev/" + String(cString: $0) }
            result[info.kp_proc.p_pid] = ProcessEntry(
                pid: info.kp_proc.p_pid,
                parent: info.kp_eproc.e_ppid,
                uid: info.kp_eproc.e_ucred.cr_uid,
                name: name,
                started: Date(timeIntervalSince1970: Double(time.tv_sec) + Double(time.tv_usec) / 1e6),
                tty: tty)
        }
        return result
    }

    public func invocation(of pid: Int32) -> Invocation? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 4 else { return nil }
        var bytes = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &bytes, &size, nil, 0) == 0, size > 4 else { return nil }
        return Self.parse(bytes.prefix(size))
    }

    /// Formato de KERN_PROCARGS2: argc, ejecutable, relleno de ceros, argumentos y entorno.
    static func parse(_ bytes: ArraySlice<UInt8>) -> Invocation? {
        guard bytes.count > 4 else { return nil }
        let count = bytes.prefix(4).reversed().reduce(0) { $0 << 8 | Int($1) }
        var index = bytes.startIndex + 4

        func next() -> String? {
            guard index < bytes.endIndex else { return nil }
            let start = index
            while index < bytes.endIndex, bytes[index] != 0 { index += 1 }
            let value = String(decoding: bytes[start..<index], as: UTF8.self)
            if index < bytes.endIndex { index += 1 }
            return value
        }

        guard let executable = next() else { return nil }
        while index < bytes.endIndex, bytes[index] == 0 { index += 1 }

        var arguments: [String] = []
        while arguments.count < count, let value = next() { arguments.append(value) }

        let key = "CLAUDE_CONFIG_DIR="
        var directory: String?
        while let value = next(), !value.isEmpty {
            if value.hasPrefix(key) {
                directory = String(value.dropFirst(key.count))
                break
            }
        }
        return Invocation(executable: executable, arguments: arguments, configDirectory: directory)
    }

    public func workingDirectory(of pid: Int32) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        return withUnsafeBytes(of: &info.pvi_cdir.vip_path) {
            String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}
