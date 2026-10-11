import Foundation

/// Replaces, inserts or removes one top-level member of a JSON object by splicing the original text, so every
/// other byte of the user's file (key order, indentation, spacing) stays exactly as it was.
/// Callers validate the result by parsing it; the editor itself only locates spans.
struct JSONTopLevelEditor {
    enum EditError: Error, Equatable { case notAnObject, malformed }

    struct Member {
        let key: String
        let keyStart: Int
        let valueStart: Int
        let valueEnd: Int
    }

    private(set) var bytes: [UInt8]
    private(set) var members: [Member] = []
    private var openBrace = 0
    private var closeBrace = 0

    init(_ text: String) throws {
        bytes = Array(text.utf8)
        try scan()
    }

    var text: String { String(decoding: bytes, as: UTF8.self) }

    /// The raw JSON text of a member's value, exactly as written.
    func rawValue(_ key: String) -> String? {
        members.last { $0.key == key }.map { String(decoding: bytes[$0.valueStart..<$0.valueEnd], as: UTF8.self) }
    }

    mutating func set(_ key: String, rawValue: String) throws {
        let value = Array(rawValue.utf8)
        if let member = members.last(where: { $0.key == key }) {
            bytes.replaceSubrange(member.valueStart..<member.valueEnd, with: value)
        } else if let last = members.last {
            let indent = indentation(before: members[0].keyStart)
            let separator = indent.map { ",\n" + $0 } ?? ", "
            bytes.insert(contentsOf: Array((separator + quoted(key) + ": ").utf8) + value, at: last.valueEnd)
        } else {
            let inner = "\n  " + quoted(key) + ": " + rawValue + "\n"
            bytes.replaceSubrange((openBrace + 1)..<closeBrace, with: Array(inner.utf8))
        }
        try scan()
    }

    mutating func remove(_ key: String) throws {
        guard let index = members.lastIndex(where: { $0.key == key }) else { return }
        let range: Range<Int>
        if index > 0 {
            range = members[index - 1].valueEnd..<members[index].valueEnd
        } else if members.count > 1 {
            range = members[0].keyStart..<members[1].keyStart
        } else {
            range = (openBrace + 1)..<closeBrace
        }
        bytes.removeSubrange(range)
        try scan()
    }

    // MARK: Scanning

    private func quoted(_ key: String) -> String {
        (try? JSONSerialization.data(withJSONObject: key, options: [.fragmentsAllowed]))
            .map { String(decoding: $0, as: UTF8.self) } ?? "\"\(key)\""
    }

    /// The whitespace that starts the line holding `position`, when the member sits on its own line.
    private func indentation(before position: Int) -> String? {
        var i = position - 1
        while i >= 0, bytes[i] == UInt8(ascii: " ") || bytes[i] == UInt8(ascii: "\t") { i -= 1 }
        guard i >= 0, bytes[i] == UInt8(ascii: "\n") else { return nil }
        return String(decoding: bytes[(i + 1)..<position], as: UTF8.self)
    }

    private mutating func scan() throws {
        members = []
        var i = skipSpace(0)
        guard i < bytes.count, bytes[i] == UInt8(ascii: "{") else { throw EditError.notAnObject }
        openBrace = i
        i = skipSpace(i + 1)
        if i < bytes.count, bytes[i] == UInt8(ascii: "}") {
            closeBrace = i
            try expectEnd(i + 1)
            return
        }
        while true {
            guard i < bytes.count, bytes[i] == UInt8(ascii: "\"") else { throw EditError.malformed }
            let keyStart = i
            let keyEnd = try skipString(i)
            guard let key = try? JSONSerialization.jsonObject(with: Data(bytes[keyStart..<keyEnd]),
                                                              options: [.fragmentsAllowed]) as? String else {
                throw EditError.malformed
            }
            i = skipSpace(keyEnd)
            guard i < bytes.count, bytes[i] == UInt8(ascii: ":") else { throw EditError.malformed }
            let valueStart = skipSpace(i + 1)
            let valueEnd = try skipValue(valueStart)
            members.append(Member(key: key, keyStart: keyStart, valueStart: valueStart, valueEnd: valueEnd))
            i = skipSpace(valueEnd)
            guard i < bytes.count else { throw EditError.malformed }
            if bytes[i] == UInt8(ascii: ",") { i = skipSpace(i + 1); continue }
            guard bytes[i] == UInt8(ascii: "}") else { throw EditError.malformed }
            closeBrace = i
            try expectEnd(i + 1)
            return
        }
    }

    private func expectEnd(_ i: Int) throws {
        guard skipSpace(i) == bytes.count else { throw EditError.malformed }
    }

    private func skipSpace(_ start: Int) -> Int {
        var i = start
        while i < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[i]) { i += 1 }
        return i
    }

    /// `start` is an opening quote; returns the index just past the closing quote.
    private func skipString(_ start: Int) throws -> Int {
        var i = start + 1
        while i < bytes.count {
            switch bytes[i] {
            case UInt8(ascii: "\\"): i += 2
            case UInt8(ascii: "\""): return i + 1
            default: i += 1
            }
        }
        throw EditError.malformed
    }

    private func skipValue(_ start: Int) throws -> Int {
        guard start < bytes.count else { throw EditError.malformed }
        switch bytes[start] {
        case UInt8(ascii: "\""):
            return try skipString(start)
        case UInt8(ascii: "{"), UInt8(ascii: "["):
            var depth = 0
            var i = start
            while i < bytes.count {
                switch bytes[i] {
                case UInt8(ascii: "\""): i = try skipString(i); continue
                case UInt8(ascii: "{"), UInt8(ascii: "["): depth += 1
                case UInt8(ascii: "}"), UInt8(ascii: "]"):
                    depth -= 1
                    if depth == 0 { return i + 1 }
                default: break
                }
                i += 1
            }
            throw EditError.malformed
        default:
            var i = start
            while i < bytes.count, ![UInt8(ascii: ","), UInt8(ascii: "}"), UInt8(ascii: "]"),
                                     0x20, 0x09, 0x0A, 0x0D].contains(bytes[i]) { i += 1 }
            guard i > start else { throw EditError.malformed }
            return i
        }
    }
}
