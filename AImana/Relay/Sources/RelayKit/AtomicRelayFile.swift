import Foundation
#if os(Windows)
import WinSDK
#endif

/// Replaces the target in its own directory, including when it already exists on Windows.
public enum AtomicRelayFile {
    public static func write(_ data: Data, to url: URL) throws {
        #if os(Windows)
        let temporary = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        try data.write(to: temporary)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let source = Array(temporary.path.utf16) + [0]
        let destination = Array(url.path.utf16) + [0]
        let moved = source.withUnsafeBufferPointer { src in
            destination.withUnsafeBufferPointer { dst in
                MoveFileExW(src.baseAddress, dst.baseAddress,
                            DWORD(MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH))
            }
        }
        guard moved else {
            throw NSError(domain: NSCocoaErrorDomain, code: Int(GetLastError()),
                          userInfo: [NSFilePathErrorKey: url.path])
        }
        #else
        try data.write(to: url, options: .atomic)
        #endif
    }
}
