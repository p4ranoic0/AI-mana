import Foundation

/// USD per one million tokens.
public struct ModelPrice: Codable, Sendable, Equatable {
    public let input: Double
    public let output: Double
    public let cacheRead: Double
    public let cacheWrite: Double

    public init(input: Double, output: Double, cacheRead: Double = 0, cacheWrite: Double = 0) {
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheWrite = cacheWrite
    }

    public func cost(of tokens: TokenUsage) -> Double {
        (Double(tokens.input) * input + Double(tokens.output) * output
            + Double(tokens.cacheRead) * cacheRead + Double(tokens.cacheWrite) * cacheWrite) / 1_000_000
    }
}

/// Prices keyed by "vendor/model" so the same model id under another vendor never borrows a price.
public struct PricingTable: Codable, Sendable, Equatable {
    public var prices: [String: ModelPrice]

    public init(prices: [String: ModelPrice]) {
        self.prices = prices
    }

    public func price(provider: String, model: String) -> ModelPrice? {
        var candidates = [model]
        // "claude-opus-5[1m]" → "claude-opus-5"
        if let bracket = model.firstIndex(of: "[") { candidates.append(String(model[..<bracket])) }
        for base in candidates {
            if let hit = prices["\(provider)/\(base)"] { return hit }
            // "claude-opus-5-20261001" → "claude-opus-5"
            if let range = base.range(of: #"-\d{8}$"#, options: .regularExpression),
               let hit = prices["\(provider)/\(base[..<range.lowerBound])"] { return hit }
        }
        return nil
    }

    /// Parses the public models.dev catalog (https://models.dev/api.json), keeping only the vendors whose
    /// local logs we read and only models that publish an input and output price.
    public static func fromModelsDev(_ data: Data) -> PricingTable? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        var prices: [String: ModelPrice] = [:]
        for vendor in ["anthropic", "openai"] {
            guard let models = (root[vendor] as? [String: Any])?["models"] as? [String: Any] else { continue }
            for (id, value) in models {
                guard let cost = (value as? [String: Any])?["cost"] as? [String: Any],
                      let input = (cost["input"] as? NSNumber)?.doubleValue,
                      let output = (cost["output"] as? NSNumber)?.doubleValue else { continue }
                prices["\(vendor)/\(id)"] = ModelPrice(
                    input: input, output: output,
                    cacheRead: (cost["cache_read"] as? NSNumber)?.doubleValue ?? 0,
                    cacheWrite: (cost["cache_write"] as? NSNumber)?.doubleValue ?? 0)
            }
        }
        return prices.isEmpty ? nil : PricingTable(prices: prices)
    }
}
