import Foundation

/// Records a test walk as JSON lines, one object per line, so a threshold can
/// be argued from what the detector actually saw.
///
/// Developer mode only. Files go to Documents/sessions on the phone;
/// tools/pull-logs.sh copies them off and tools/analyze-log.py sums them up.
@MainActor
public final class SessionLogger {
    /// About 6 MB an hour at 8 readings a second, so this is many hours of
    /// walking. It's there so a runaway can't fill the phone.
    public nonisolated static let maxBytes = 40 * 1024 * 1024
    private static let flushInterval: TimeInterval = 1.0

    public let directory: URL
    public private(set) var url: URL?
    private var handle: FileHandle?
    private var buffer = Data()
    private var lastFlush = Date()
    private var bytesWritten = 0
    private let maxBytes: Int

    public init(directory: URL = SessionLogger.defaultDirectory, maxBytes: Int = SessionLogger.maxBytes) {
        self.directory = directory
        self.maxBytes = maxBytes
    }

    public nonisolated static var defaultDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("sessions", isDirectory: true)
    }

    public var isRecording: Bool { handle != nil }

    /// Start a new file.
    public func begin(device: String = SessionLogger.deviceModel()) {
        close()
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let file = directory.appendingPathComponent("session-\(stamp).jsonl")
        fm.createFile(atPath: file.path, contents: nil)
        handle = try? FileHandle(forWritingTo: file)
        url = handle == nil ? nil : file
        bytesWritten = 0
        log("session", ["device": device])
    }

    /// One row. `kind` says what the row is: session, start, reading, event,
    /// mark, stop. Does nothing unless recording.
    public func log(_ kind: String, _ fields: [String: Any] = [:]) {
        guard handle != nil, bytesWritten < maxBytes else { return }
        var row = fields
        row["t"] = Date().timeIntervalSince1970
        row["kind"] = kind
        guard let data = try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]) else { return }
        buffer.append(data)
        buffer.append(0x0A)
        if Date().timeIntervalSince(lastFlush) > Self.flushInterval { flush() }
    }

    public func flush() {
        guard let handle, !buffer.isEmpty else { return }
        try? handle.write(contentsOf: buffer)
        bytesWritten += buffer.count
        buffer.removeAll(keepingCapacity: true)
        lastFlush = Date()
    }

    public func close() {
        flush()
        try? handle?.close()
        handle = nil
    }

    public func sessionCount() -> Int {
        (try? FileManager.default.contentsOfDirectory(atPath: directory.path))?.count ?? 0
    }

    public func deleteAll() {
        try? FileManager.default.removeItem(at: directory)
    }

    /// The hardware model, such as "iPhone14,3".
    public nonisolated static func deviceModel() -> String {
        var info = utsname()
        uname(&info)
        return withUnsafePointer(to: &info.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
    }
}
