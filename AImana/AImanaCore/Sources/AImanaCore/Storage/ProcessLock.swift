import Foundation
#if os(Windows)
import WinSDK
#endif

/// Mutual exclusion that holds across processes (the app and its widget run at the same time and share the
/// Keychain and the App Group), and across separate instances inside one process.
public protocol ProcessLock: Sendable {
    func withLock<T>(_ body: () async throws -> T) async throws -> T
}

public enum ProcessLockError: Error, Sendable, Equatable {
    /// Another holder kept the lock past the timeout.
    case timedOut
    /// The lock file could not be opened.
    case unavailable
}

/// `flock` on a file in the App Group container. The lock belongs to the open file, not to a thread, so it can be
/// held across `await`; a crashed holder releases it automatically. Two opens of the same file exclude each other
/// even inside one process, which is what lets tests run two token managers against one lock file.
///
/// iOS terminates a suspended process that still holds a lock on a shared-container file (0xdead10cc), so while the
/// lock is held the process asks for a little background time, and gives the lock up if that time runs out.
public final class FileLock: ProcessLock, @unchecked Sendable {
    private let url: URL
    private let timeout: TimeInterval
    private let pollInterval: TimeInterval

    public init(url: URL, timeout: TimeInterval = 15, pollInterval: TimeInterval = 0.05) {
        self.url = url
        self.timeout = timeout
        self.pollInterval = pollInterval
    }

    public func withLock<T>(_ body: () async throws -> T) async throws -> T {
        let held = try await acquire()
        defer { held.release() }
        return try await body()
    }

    private func acquire() async throws -> Held {
        #if os(Windows)
        let deadline = Date().addingTimeInterval(timeout)
        let wide = Array(url.path.utf16) + [0]
        while true {
            let handle = wide.withUnsafeBufferPointer {
                CreateFileW($0.baseAddress, DWORD(GENERIC_READ) | DWORD(GENERIC_WRITE), 0, nil,
                            DWORD(OPEN_ALWAYS), DWORD(FILE_ATTRIBUTE_NORMAL), nil)
            }
            if handle != INVALID_HANDLE_VALUE { return Held(handle: handle) }
            let error = GetLastError()
            guard (error == ERROR_SHARING_VIOLATION || error == ERROR_LOCK_VIOLATION),
                  Date() < deadline, !Task.isCancelled else {
                throw error == ERROR_SHARING_VIOLATION || error == ERROR_LOCK_VIOLATION
                    ? ProcessLockError.timedOut : ProcessLockError.unavailable
            }
            try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }
        #else
        let fd = open(url.path, O_CREAT | O_RDWR | O_CLOEXEC, 0o644)
        guard fd >= 0 else { throw ProcessLockError.unavailable }
        let deadline = Date().addingTimeInterval(timeout)
        while flock(fd, LOCK_EX | LOCK_NB) != 0 {
            guard errno == EWOULDBLOCK || errno == EINTR, Date() < deadline, !Task.isCancelled else {
                close(fd)
                throw ProcessLockError.timedOut
            }
            try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }
        return Held(fd: fd)
        #endif
    }

    /// One acquisition. Released exactly once: by the holder, or by the expiring-activity handler.
    private final class Held: @unchecked Sendable {
        #if os(Windows)
        private var handle: HANDLE?
        #else
        private var fd: Int32
        #endif
        private let state = NSLock()
        private let done = DispatchSemaphore(value: 0)

        #if os(Windows)
        init(handle: HANDLE?) { self.handle = handle }
        #else
        init(fd: Int32) {
            self.fd = fd
            #if os(iOS)
            ProcessInfo.processInfo.performExpiringActivity(withReason: "AImana shared lock") { [self] expired in
                if expired { release() } else { done.wait() }
            }
            #endif
        }
        #endif

        func release() {
            #if os(Windows)
            let toClose: HANDLE? = state.withLock {
                let current = handle
                handle = nil
                return current
            }
            if let toClose { CloseHandle(toClose) }
            #else
            let toClose: Int32 = state.withLock {
                let current = fd
                fd = -1
                return current
            }
            guard toClose >= 0 else { return }
            flock(toClose, LOCK_UN)
            close(toClose)
            done.signal()
            #endif
        }
    }
}

/// Runs the body directly. For tests and for callers that only ever live in one process.
public struct NoProcessLock: ProcessLock {
    public init() {}
    public func withLock<T>(_ body: () async throws -> T) async throws -> T { try await body() }
}
