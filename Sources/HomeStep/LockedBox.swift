import Foundation

/// One value shared between the ARKit thread and the main actor, behind a lock.
/// `@unchecked Sendable` because the lock serializes every access.
final class LockedBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T

    init(_ value: T) { self.value = value }

    func get() -> T {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    func set(_ newValue: T) {
        lock.lock(); defer { lock.unlock() }
        value = newValue
    }
}
