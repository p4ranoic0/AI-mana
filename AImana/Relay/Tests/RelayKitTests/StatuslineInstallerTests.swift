import Foundation
import Testing
@testable import RelayKit

func makeTempDir(_ name: String = #function) throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("relaykit-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

private struct Sandbox {
    let root: URL
    let installer: StatuslineInstaller
    var settings: URL { installer.settingsFile }

    init() throws {
        root = try makeTempDir()
        installer = StatuslineInstaller(settingsFile: root.appendingPathComponent(".claude/settings.json"),
                                        supportDirectory: root.appendingPathComponent("Support AImana"),
                                        dataFile: root.appendingPathComponent("Support AImana/claude-statusline.json"),
                                        platform: .macOS)
    }

    func write(_ text: String) throws {
        try FileManager.default.createDirectory(at: settings.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: settings)
    }

    func read() throws -> String { try String(contentsOf: settings, encoding: .utf8) }

    func json() throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as! [String: Any]
    }
}

@Suite struct JSONTopLevelEditorTests {
    @Test func replacesOnlyTheValueSpan() throws {
        let text = "{\n  \"model\": \"opus\",\n  \"statusLine\": {\"type\": \"command\", \"command\": \"a\"},\n  \"x\": [1, {\"y\": \"}\"}]\n}\n"
        var editor = try JSONTopLevelEditor(text)
        #expect(editor.rawValue("statusLine") == "{\"type\": \"command\", \"command\": \"a\"}")
        try editor.set("statusLine", rawValue: "{\"command\": \"b\"}")
        #expect(editor.text == "{\n  \"model\": \"opus\",\n  \"statusLine\": {\"command\": \"b\"},\n  \"x\": [1, {\"y\": \"}\"}]\n}\n")
    }

    @Test func insertsWithDetectedIndentation() throws {
        var editor = try JSONTopLevelEditor("{\n    \"a\": 1\n}")
        try editor.set("statusLine", rawValue: "{}")
        #expect(editor.text == "{\n    \"a\": 1,\n    \"statusLine\": {}\n}")
        var empty = try JSONTopLevelEditor("{}")
        try empty.set("k", rawValue: "true")
        #expect(empty.text == "{\n  \"k\": true\n}")
        var inline = try JSONTopLevelEditor("{\"a\":1}")
        try inline.set("k", rawValue: "2")
        #expect(inline.text == "{\"a\":1, \"k\": 2}")
    }

    @Test func removesFirstMiddleLastAndOnly() throws {
        let text = "{\n  \"a\": 1,\n  \"b\": 2,\n  \"c\": 3\n}"
        for (key, expected) in [("a", "{\n  \"b\": 2,\n  \"c\": 3\n}"), ("b", "{\n  \"a\": 1,\n  \"c\": 3\n}"),
                                ("c", "{\n  \"a\": 1,\n  \"b\": 2\n}")] {
            var editor = try JSONTopLevelEditor(text)
            try editor.remove(key)
            #expect(editor.text == expected)
        }
        var only = try JSONTopLevelEditor("{ \"a\": {\"b\": [1]} }")
        try only.remove("a")
        #expect(only.text == "{}")
    }

    @Test func handlesEscapedQuotesAndRejectsNonObjects() throws {
        let editor = try JSONTopLevelEditor(#"{"k\"ey": "va\"l}", "statusLine": null}"#)
        #expect(editor.members.map(\.key) == ["k\"ey", "statusLine"])
        #expect(editor.rawValue("statusLine") == "null")
        #expect(throws: JSONTopLevelEditor.EditError.notAnObject) { try JSONTopLevelEditor("[1]") }
        #expect(throws: JSONTopLevelEditor.EditError.malformed) { try JSONTopLevelEditor("{\"a\": 1,}") }
        #expect(throws: JSONTopLevelEditor.EditError.malformed) { try JSONTopLevelEditor("{\"a\": 1} x") }
    }
}

@Suite struct StatuslineInstallerTests {
    @Test func roundTripRestoresPreviousStatusLineExactly() throws {
        let box = try Sandbox()
        let original = """
        {
          "model": "opus",
          "statusLine": {
            "type": "command",
            "command": "~/.claude/my status.sh",
            "padding": 0
          },
          "permissions": {"allow": ["Bash(ls:*)"]},
          "hooks": {}
        }

        """
        try box.write(original)
        #expect(box.installer.status() == .notInstalled)

        try box.installer.install()
        #expect(box.installer.status() == .installed)
        let installed = try box.json()
        let statusLine = try #require(installed["statusLine"] as? [String: Any])
        #expect(statusLine["command"] as? String == box.installer.command)
        #expect(statusLine["type"] as? String == "command")
        #expect(statusLine["padding"] as? Int == 0)
        #expect(installed["model"] as? String == "opus")
        #expect((installed["permissions"] as? [String: Any])?["allow"] as? [String] == ["Bash(ls:*)"])
        // Every other line is untouched.
        #expect(try box.read().hasPrefix("{\n  \"model\": \"opus\",\n  \"statusLine\": { \"type\": \"command\""))
        #expect(try box.read().hasSuffix("\"permissions\": {\"allow\": [\"Bash(ls:*)\"]},\n  \"hooks\": {}\n}\n"))

        let script = try String(contentsOf: box.installer.scriptFile, encoding: .utf8)
        #expect(script.contains("previous='~/.claude/my status.sh'"))
        let backups = try FileManager.default.contentsOfDirectory(at: box.installer.backupDirectory, includingPropertiesForKeys: nil)
        #expect(backups.count == 1)
        #expect(try String(contentsOf: backups[0], encoding: .utf8) == original)

        try box.installer.uninstall()
        #expect(try box.read() == original)
        #expect(box.installer.status() == .notInstalled)
        #expect(!FileManager.default.fileExists(atPath: box.installer.scriptFile.path))
    }

    @Test func roundTripWithoutPreviousStatusLineRemovesTheKey() throws {
        let box = try Sandbox()
        let original = "{\n  \"theme\": \"dark\"\n}\n"
        try box.write(original)
        try box.installer.install()
        #expect(try box.read() == "{\n  \"theme\": \"dark\",\n  \"statusLine\": { \"type\": \"command\", \"command\": \(jsonString(box.installer.command)) }\n}\n")
        #expect(try String(contentsOf: box.installer.scriptFile, encoding: .utf8).contains("previous=''"))
        try box.installer.uninstall()
        #expect(try box.read() == original)
    }

    @Test func missingSettingsFileIsCreatedAndUninstallLeavesAnEmptyObject() throws {
        let box = try Sandbox()
        try box.installer.install()
        #expect(try box.json()["statusLine"] != nil)
        try box.installer.uninstall()
        #expect(try box.json().isEmpty)
    }

    @Test func installingTwiceKeepsTheOriginalPrevious() throws {
        let box = try Sandbox()
        let original = #"{"statusLine": {"type": "command", "command": "echo hi"}}"#
        try box.write(original)
        try box.installer.install()
        try box.installer.install()
        #expect(try String(contentsOf: box.installer.scriptFile, encoding: .utf8).contains("previous='echo hi'"))
        try box.installer.uninstall()
        #expect(try box.read() == original)
    }

    @Test func concurrentModificationAbortsWithoutWriting() throws {
        let box = try Sandbox()
        let original = #"{"a": 1}"#
        try box.write(original)
        let settings = box.settings
        var installer = box.installer
        installer.beforeCommit = { try? Data(#"{"a": 2}"#.utf8).write(to: settings) }
        #expect(throws: StatuslineInstaller.InstallError.concurrentModification) { try installer.install() }
        #expect(try box.read() == #"{"a": 2}"#)
        #expect(box.installer.status() == .notInstalled)
    }

    @Test func userReplacedStatusLineIsNotOverwrittenOnUninstall() throws {
        let box = try Sandbox()
        try box.write(#"{"statusLine": {"type": "command", "command": "old"}}"#)
        try box.installer.install()
        let replaced = #"{"statusLine": {"type": "command", "command": "someone else"}}"#
        try box.write(replaced)
        #expect(box.installer.status() == .replacedElsewhere)
        #expect(throws: StatuslineInstaller.InstallError.replacedElsewhere) { try box.installer.uninstall() }
        #expect(try box.read() == replaced)
        box.installer.forget()
        #expect(box.installer.status() == .notInstalled)
    }

    @Test func unreadableSettingsAreRefused() throws {
        let box = try Sandbox()
        try box.write("{ // comment\n \"a\": 1 }")
        #expect(throws: StatuslineInstaller.InstallError.settingsUnreadable) { try box.installer.install() }
        #expect(try box.read() == "{ // comment\n \"a\": 1 }")
    }

    #if !os(Windows)
    @Test func symlinkedSettingsAreEditedInPlace() throws {
        let box = try Sandbox()
        let real = box.root.appendingPathComponent("dotfiles/settings.json")
        try FileManager.default.createDirectory(at: real.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"a": 1}"#.utf8).write(to: real)
        try FileManager.default.createDirectory(at: box.settings.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: box.settings, withDestinationURL: real)
        try box.installer.install()
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: box.settings.path) == real.path)
        #expect(try String(contentsOf: real, encoding: .utf8).contains("statusLine"))
        try box.installer.uninstall()
        #expect(try String(contentsOf: real, encoding: .utf8) == #"{"a": 1}"#)
    }
    #endif

    private func jsonString(_ s: String) -> String {
        String(decoding: try! JSONSerialization.data(withJSONObject: s, options: [.fragmentsAllowed, .withoutEscapingSlashes]), as: UTF8.self)
    }
}

/// Runs the generated wrapper with /bin/sh, the way Claude Code does.
#if canImport(Darwin)
@Suite struct StatuslineScriptTests {
    private static let input = #"{"session_id":"x","model":{"id":"claude-opus","display_name":"Opus"},"workspace":{"current_dir":"/tmp"},"cost":null,"rate_limits":{"five_hour":{"used_percentage":23.5,"resets_at":1738425600},"seven_day":{"used_percentage":41.2,"resets_at":1738857600}}}"#

    private func run(script: URL, stdin: String, path: String = "/usr/bin:/bin:/usr/sbin:/sbin") throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [script.path]
        process.environment = ["PATH": path, "HOME": NSTemporaryDirectory()]
        let inPipe = Pipe(), outPipe = Pipe()
        process.standardInput = inPipe
        process.standardOutput = outPipe
        try process.run()
        inPipe.fileHandleForWriting.write(Data(stdin.utf8))
        try inPipe.fileHandleForWriting.close()
        let out = outPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        return String(decoding: out, as: UTF8.self)
    }

    private func install(previous: String?, in dir: URL) throws -> (script: URL, data: URL) {
        let data = dir.appendingPathComponent("out dir/claude-statusline.json")
        let script = dir.appendingPathComponent("statusline.sh")
        try Data(StatuslineScript.render(outputFile: data, previousCommand: previous).utf8).write(to: script)
        return (script, data)
    }

    private func checkCapture(_ url: URL) throws {
        let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        let captured = try #require(saved["capturedAt"] as? Double)
        #expect(abs(captured - Date().timeIntervalSince1970) < 30)
        let limits = try #require(saved["rate_limits"] as? [String: [String: Double]])
        #expect(limits["five_hour"]?["used_percentage"] == 23.5)
        #expect(limits["seven_day"]?["resets_at"] == 1738857600)
        #expect(saved["session_id"] == nil)
    }

    @Test(arguments: ["/usr/bin:/bin:/usr/sbin:/sbin", "/bin:/usr/sbin:/sbin"]) // with and without jq on PATH
    func savesRateLimitsAndPipesSameInputToPrevious(path: String) throws {
        let dir = try makeTempDir()
        let seen = dir.appendingPathComponent("seen it's.json")
        let previous = "cat > \(StatuslineScript.shellQuote(seen.path)); printf 'PREV-OUT'"
        let (script, data) = try install(previous: previous, in: dir)
        let output = try run(script: script, stdin: Self.input, path: path)
        #expect(output == "PREV-OUT")
        #expect(try String(contentsOf: seen, encoding: .utf8) == Self.input)
        try checkCapture(data)
        // No temp files are left behind.
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: data.deletingLastPathComponent().path)
        #expect(leftovers == ["claude-statusline.json"])
    }

    @Test func withoutPreviousPrintsAMinimalLine() throws {
        let dir = try makeTempDir()
        let (script, data) = try install(previous: nil, in: dir)
        #expect(try run(script: script, stdin: Self.input) == "Opus")
        try checkCapture(data)
    }

    @Test func missingRateLimitsKeepsTheOldCaptureAndStillPrints() throws {
        let dir = try makeTempDir()
        let (script, data) = try install(previous: "echo prev", in: dir)
        _ = try run(script: script, stdin: Self.input)
        let before = try Data(contentsOf: data)
        #expect(try run(script: script, stdin: #"{"model":{"display_name":"Opus"}}"#) == "prev\n")
        #expect(try run(script: script, stdin: "not json at all") == "prev\n")
        #expect(try Data(contentsOf: data) == before)
    }

    @Test func unwritableOutputNeverBreaksTheStatusline() throws {
        let dir = try makeTempDir()
        let script = dir.appendingPathComponent("statusline.sh")
        try Data(StatuslineScript.render(outputFile: URL(fileURLWithPath: "/nonexistent-root/x/claude-statusline.json"),
                                         previousCommand: "echo ok").utf8).write(to: script)
        #expect(try run(script: script, stdin: Self.input) == "ok\n")
    }
}
#endif
