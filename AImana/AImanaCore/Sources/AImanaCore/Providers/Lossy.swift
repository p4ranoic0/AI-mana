import Foundation

/// Decodes `T` or quietly yields nil, so a malformed optional extra can never break the rest of a response.
struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        value = try? decoder.singleValueContainer().decode(T.self)
    }
}
