import Foundation

/// Records test walks as JSON lines (developer mode), so thresholds are set
/// from what the detector actually saw rather than from guesses. The false
/// "Step down" warnings during normal walking were only fixed once this data
/// existed.
///
/// Files go to the app's Documents folder. tools/pull-logs.sh copies them off;
/// by hand:
///
///     xcrun devicectl device info files --device <id> \
///       --domain-type appDataContainer \
///       --domain-identifier com.sathvik.homestep --username mobile
///
///     xcrun devicectl device copy from --device <id> \
///       --domain-type appDataContainer \
///       --domain-identifier com.sathvik.homestep --username mobile \
///       --source Documents/sessions --destination ./logs
@MainActor
final class SessionLogger {

    private(set) var url: URL?
    private var handle: FileHandle?
    private var buffer = Data()
    private var lastFlush = Date()
    private var bytesWritten = 0

    /// About 6 MB an hour at 8 readings a second, so many hours of walking.
    /// It's there so a runaway can't fill the phone.
    private let maxBytes = 40 * 1024 * 1024
    private let flushInterval: TimeInterval = 1.0

    func begin() {
        close()
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let dir = docs.appendingPathComponent("sessions", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let file = dir.appendingPathComponent("session-\(stamp).jsonl")
        fm.createFile(atPath: file.path, contents: nil)
        handle = try? FileHandle(forWritingTo: file)
        url = handle == nil ? nil : file
        bytesWritten = 0
        log("session", ["device": UIDeviceModelName()])
    }

    /// One JSON object per line. `kind` says what the row is (session, start,
    /// reading, event, mark, stop).
    func log(_ kind: String, _ fields: [String: Any] = [:]) {
        guard handle != nil, bytesWritten < maxBytes else { return }
        var row: [String: Any] = fields
        row["t"] = Date().timeIntervalSince1970
        row["kind"] = kind
        guard let data = try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
        else { return }
        buffer.append(data)
        buffer.append(0x0A)   // newline
        if Date().timeIntervalSince(lastFlush) > flushInterval { flush() }
    }

    func flush() {
        guard let handle, !buffer.isEmpty else { return }
        try? handle.write(contentsOf: buffer)
        bytesWritten += buffer.count
        buffer.removeAll(keepingCapacity: true)
        lastFlush = Date()
    }

    func close() {
        flush()
        try? handle?.close()
        handle = nil
    }

    /// Number of session files on disk, for the on-screen counter.
    static func sessionCount() -> Int {
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return 0 }
        let dir = docs.appendingPathComponent("sessions", isDirectory: true)
        return (try? fm.contentsOfDirectory(atPath: dir.path))?.count ?? 0
    }

    static func deleteAll() {
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        try? fm.removeItem(at: docs.appendingPathComponent("sessions", isDirectory: true))
    }
}

private func UIDeviceModelName() -> String {
    var info = utsname()
    uname(&info)
    return withUnsafePointer(to: &info.machine) {
        $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
    }
}
