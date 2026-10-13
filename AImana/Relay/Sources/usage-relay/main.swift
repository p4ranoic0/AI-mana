import AImanaCore
import Foundation
import RelayKit

/// `usage-relay costs`: prints local cost totals without publishing anything.
func printCosts(_ publisher: RelayPublisher) async {
    let reports = await publisher.buildCosts(now: Date())
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd"
    let today = f.string(from: Date())
    for report in reports {
        print("\n\(report.providerID)")
        for (label, days) in [("today", 1), ("7 days", 7), ("30 days", 30)] {
            let t = report.total(lastDays: days, endingOn: today)
            print(String(format: "  %-8@ $%9.2f   %12ld tokens   unpriced: %ld", label as NSString, t.usd, t.tokens.total, t.unpricedTokens))
        }
        let byModel = Dictionary(grouping: report.days.flatMap(\.models), by: \.model)
            .mapValues { ($0.reduce(0.0) { $0 + ($1.usd ?? 0) }, $0.reduce(0) { $0 + $1.tokens.total }) }
            .sorted { $0.value.0 > $1.value.0 }.prefix(6)
        for (model, v) in byModel { print(String(format: "    %-30@ $%9.2f  %12ld tokens", model as NSString, v.0, v.1)) }
    }
}

let args = Array(CommandLine.arguments.dropFirst())
if args == ["--version"] || args == ["version"] {
    print("usage-relay \(RelayVersion.current)")
    exit(0)
}
func value(_ flag: String) -> String? {
    guard let i = args.firstIndex(of: flag), args.indices.contains(i + 1) else { return nil }
    return args[i + 1]
}
func path(_ string: String) -> URL { URL(fileURLWithPath: (string as NSString).expandingTildeInPath) }
var paths = RelayPaths.standard
if let state = value("--state-dir") { paths.stateDirectory = path(state) }
if let cache = value("--cache-dir") { paths.caches = path(cache) }
let publisher = RelayPublisher(paths: paths)
func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}
if ["setup", "doctor", "uninstall"].contains(args.first ?? "") {
    #if canImport(Darwin)
    print("The AI·mana Mac app manages the relay in Settings.")
    exit(0)
    #else
    let setup = RelaySetup(paths: paths)
    do {
        switch args[0] {
        case "setup":
            let options = try SetupOptions(arguments: Array(args.dropFirst()))
            for line in try await setup.setup(options) { print(line) }
        case "doctor":
            guard args.count == 1 else { throw SetupError.invalidArguments }
            let result = setup.doctor()
            for line in result.lines { print(line) }
            exit(result.healthy ? 0 : 1)
        default:
            guard args.count == 1 else { throw SetupError.invalidArguments }
            for line in try setup.uninstall() { print(line) }
        }
        exit(0)
    } catch {
        fail("\(args[0]) failed: \(error). Usage: usage-relay setup [--output FILE] [--interval MINUTES]", code: 2)
    }
    #endif
}
if args.first == "statusline-capture" {
    guard args.count == 1 else { fail("usage: usage-relay statusline-capture", code: 2) }
    let input = FileHandle.standardInput.readDataToEndOfFile()
    do {
        print(try StatuslineCapture.save(input, to: paths.claudeStatuslineFile))
        exit(0)
    } catch { fail("statusline capture failed: \(error)") }
}
if args.first == "run" {
    do {
        let (runPaths, options) = try RelayRun.resolve(arguments: Array(args.dropFirst()), defaultPaths: paths)
        _ = try await RelayRun.publish(paths: runPaths, options: options)
        exit(0)
    }
    catch {
        #if canImport(Darwin)
        fputs("publish failed: \(error)\n", stderr)
        #else
        FileHandle.standardError.write(Data("publish failed: \(error)\n".utf8))
        #endif
        exit(1)
    }
}
if args.first == "check", args.count > 1 {
    // Decodes a published file exactly as the iPhone does and prints a summary (no message content exists in it).
    do {
        let envelope = try RelayEnvelope.decode(try Data(contentsOf: path(args[1])))
        print("version \(envelope.version), generated \(envelope.generatedAt)")
        for entry in envelope.entries {
            let lanes = entry.usage?.windows.map { "\($0.kind.wireValue)=\($0.usedPercent)%" }.joined(separator: " ") ?? "-"
            print("  \(entry.providerID): source=\(entry.source?.rawValue ?? "-") error=\(entry.error?.rawValue ?? "-") \(lanes) updated=\(entry.usage.map { "\($0.lastUpdated)" } ?? "-")")
        }
        print("  costs: \(envelope.costs.map { "\($0.providerID) \($0.days.count) days" }.joined(separator: ", "))")
        print("  history: \(envelope.history.map { "\($0.providerID)/\($0.kind.wireValue) \($0.points.count) pts" }.joined(separator: ", "))")
        exit(0)
    } catch {
        print("decode failed: \(error)")
        exit(1)
    }
}
if args.first == "statusline", args.count > 1 {
    // Same installer as AImana for Mac's Settings: backs up settings.json and restores it exactly on uninstall.
    let installer = StatuslineInstaller(paths: paths)
    do {
        switch args[1] {
        case "install": try installer.install()
        case "uninstall": try installer.uninstall()
        case "status": break
        default: print("usage: usage-relay statusline install|uninstall|status"); exit(2)
        }
        print("status: \(installer.status())")
        print("last capture: \(installer.lastCapture().map { "\($0)" } ?? "none yet")")
        exit(0)
    } catch {
        print("statusline \(args[1]) failed: \(error)")
        exit(1)
    }
}
if args.first == "costs" {
    await printCosts(publisher)
    exit(0)
}
print("usage-relay --version\nusage-relay run [--output FILE | --config SETUP_JSON] [--no-costs] [--state-dir DIR] [--cache-dir DIR]\nusage-relay setup [--output FILE] [--interval MINUTES]\nusage-relay doctor\nusage-relay uninstall\nusage-relay check FILE\nusage-relay costs\nusage-relay statusline install|uninstall|status")
exit(args.isEmpty ? 0 : 2)
