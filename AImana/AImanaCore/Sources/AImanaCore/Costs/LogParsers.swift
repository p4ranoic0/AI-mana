import Foundation

/// One billable model response, normalised so that `input` never includes cached tokens.
public struct CostEvent: Codable, Sendable, Equatable {
    /// Identity used to count a response once even when it appears in several log files.
    public let key: String
    public let timestamp: Date
    public let model: String
    public let tokens: TokenUsage

    public init(key: String, timestamp: Date, model: String, tokens: TokenUsage) {
        self.key = key
        self.timestamp = timestamp
        self.model = model
        self.tokens = tokens
    }
}

extension ISO8601DateFormatter {
    nonisolated(unsafe) static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    nonisolated(unsafe) static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    public static func parseLoose(_ s: String) -> Date? { fractional.date(from: s) ?? plain.date(from: s) }
}

private func contains(_ data: Data, _ needle: String) -> Bool {
    data.range(of: Data(needle.utf8)) != nil
}

/// Reads token usage from Claude Code transcripts (`~/.claude/projects/**/*.jsonl`).
/// Only numeric usage fields, the model id, ids and the timestamp are decoded — never message content.
public enum ClaudeLogParser {
    private struct Line: Decodable {
        struct Message: Decodable {
            struct Usage: Decodable {
                let input_tokens: Int?
                let output_tokens: Int?
                let cache_creation_input_tokens: Int?
                let cache_read_input_tokens: Int?
            }
            let id: String?
            let model: String?
            let usage: Usage?
        }
        let type: String?
        let timestamp: String?
        let requestId: String?
        let message: Message?
    }

    public static func event(from line: Data) -> CostEvent? {
        guard contains(line, "\"usage\""),
              let decoded = try? JSONDecoder().decode(Line.self, from: line),
              decoded.type == "assistant",
              let message = decoded.message, let usage = message.usage,
              let model = message.model, model != "<synthetic>",
              let stamp = decoded.timestamp, let date = ISO8601DateFormatter.parseLoose(stamp) else { return nil }
        let tokens = TokenUsage(input: usage.input_tokens ?? 0, output: usage.output_tokens ?? 0,
                                cacheRead: usage.cache_read_input_tokens ?? 0,
                                cacheWrite: usage.cache_creation_input_tokens ?? 0)
        guard tokens.total > 0 else { return nil }
        let key = [message.id, decoded.requestId].compactMap { $0 }.joined(separator: ":")
        return CostEvent(key: key.isEmpty ? "\(stamp)|\(model)|\(tokens.total)" : key,
                         timestamp: date, model: model, tokens: tokens)
    }
}

/// Reads token usage from Codex rollouts (`~/.codex/sessions/**/*.jsonl`). Stateful per file: Codex reports
/// cumulative totals, so each event's cost is the growth since the previous snapshot.
public struct CodexLogParser {
    private struct Raw: Decodable, Equatable {
        let input_tokens: Int?
        let cached_input_tokens: Int?
        let cache_write_input_tokens: Int?
        let output_tokens: Int?

        var input: Int { input_tokens ?? 0 }
        var cached: Int { cached_input_tokens ?? 0 }
        var cacheWrite: Int { cache_write_input_tokens ?? 0 }
        var output: Int { output_tokens ?? 0 }

        func grewFrom(_ o: Raw) -> Bool {
            input >= o.input && cached >= o.cached && cacheWrite >= o.cacheWrite && output >= o.output
        }
        func minus(_ o: Raw) -> Raw {
            Raw(input_tokens: input - o.input, cached_input_tokens: cached - o.cached,
                cache_write_input_tokens: cacheWrite - o.cacheWrite, output_tokens: output - o.output)
        }
        var isZero: Bool { input == 0 && cached == 0 && cacheWrite == 0 && output == 0 }
        var tokens: TokenUsage {
            // OpenAI's input_tokens already contains the cached part: bill only the rest as fresh input.
            TokenUsage(input: max(0, input - cached), output: output, cacheRead: cached, cacheWrite: cacheWrite)
        }
    }

    private struct Line: Decodable {
        struct Payload: Decodable {
            struct Info: Decodable {
                let total_token_usage: Raw?
                let last_token_usage: Raw?
            }
            let type: String?
            let model: String?
            let info: Info?
        }
        let type: String?
        let timestamp: String?
        let payload: Payload?
    }

    private var model: String?
    private var previousTotal: Raw?

    public init() {}

    public mutating func consume(_ line: Data) -> CostEvent? {
        let isTurn = contains(line, "\"turn_context\"")
        guard isTurn || contains(line, "\"token_count\""),
              let decoded = try? JSONDecoder().decode(Line.self, from: line) else { return nil }

        if decoded.type == "turn_context" {
            if let m = decoded.payload?.model, !m.isEmpty { model = m }
            return nil
        }
        guard decoded.type == "event_msg", decoded.payload?.type == "token_count",
              let info = decoded.payload?.info, let total = info.total_token_usage,
              let stamp = decoded.timestamp, let date = ISO8601DateFormatter.parseLoose(stamp) else { return nil }

        let delta: Raw
        if let previous = previousTotal, total.grewFrom(previous) {
            delta = total.minus(previous)
        } else {
            // First snapshot of a file (possibly a fork carrying its parent's totals) or a counter reset:
            // only the latest turn is new work.
            delta = info.last_token_usage ?? total
        }
        previousTotal = total
        guard !delta.isZero else { return nil }
        return CostEvent(key: "\(stamp)|\(total.input)|\(total.output)", timestamp: date,
                         model: model ?? "unknown", tokens: delta.tokens)
    }
}
