import AImanaCore
import Foundation

public enum StatuslineCapture {
    /// Returns the display name to print when the wrapper has no previous command.
    @discardableResult
    public static func save(_ input: Data, to file: URL, now: Date = Date()) throws -> String {
        guard let root = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any] else {
            return "Claude Code"
        }
        let name = (root["model"] as? [String: Any])?["display_name"] as? String ?? "Claude Code"
        if let limits = root["rate_limits"] as? [String: Any], JSONSerialization.isValidJSONObject(limits) {
            let payload: [String: Any] = ["capturedAt": now.timeIntervalSince1970, "rate_limits": limits]
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try AtomicRelayFile.write(data, to: file)
        }
        return name
    }
}
