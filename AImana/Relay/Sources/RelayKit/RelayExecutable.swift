import Foundation

/// Turns package-manager version paths into links that survive an upgrade.
public enum RelayExecutable {
    public static func stable(_ executable: URL,
                              exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> URL {
        URL(fileURLWithPath: stablePath(executable.path, exists: exists))
    }

    public static func stablePath(_ original: String, exists: (String) -> Bool) -> String {
        let slashPath = original.replacingOccurrences(of: "\\", with: "/")
        if let range = slashPath.range(of: "/Cellar/") {
            let tail = slashPath[range.upperBound...].split(separator: "/", omittingEmptySubsequences: true)
            if tail.count >= 4, tail[2] == "bin" {
                let candidate = String(slashPath[..<range.lowerBound]) + "/opt/" + tail[0] + "/" +
                    tail.dropFirst(2).joined(separator: "/")
                if exists(candidate) { return candidate }
            }
        }
        if let range = slashPath.range(of: "/apps/", options: .caseInsensitive) {
            let tail = slashPath[range.upperBound...].split(separator: "/", omittingEmptySubsequences: true)
            if tail.count >= 3, tail[1].lowercased() != "current" {
                let candidate = String(slashPath[..<range.upperBound]) + tail[0] + "/current/" +
                    tail.dropFirst(2).joined(separator: "/")
                let native = original.contains("\\") ? candidate.replacingOccurrences(of: "/", with: "\\") : candidate
                if exists(native) { return native }
            }
        }
        return original
    }
}
