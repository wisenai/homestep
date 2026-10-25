import Foundation

/// One value shared between the ARKit thread and the main actor, behind a lock.
public final class LockedBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T

    public init(_ value: T) { self.value = value }

    public func get() -> T {
        lock.withLock { value }
    }

    public func set(_ newValue: T) {
        lock.withLock { value = newValue }
    }

    /// Read and change the value in one locked step.
    @discardableResult
    public func update<R>(_ body: (inout T) -> R) -> R {
        lock.withLock { body(&value) }
    }
}
