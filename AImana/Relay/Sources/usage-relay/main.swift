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
if args.first == "run" {
    let options = RelayOptions(output: value("--output").map(path) ?? value("--out").map(path) ?? RelayPaths.defaultOutput,
                               includeCosts: !args.contains("--no-costs"))
    do { _ = try await publisher.publish(options); exit(0) }
    catch {
        #if os(Linux)
        FileHandle.standardError.write(Data("publish failed: \(error)\n".utf8))
        #else
        fputs("publish failed: \(error)\n", stderr)
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
    #if os(Linux)
    FileHandle.standardError.write(Data("statusline install/uninstall/status is unavailable on Linux; publish with 'usage-relay run --output FILE' instead.\n".utf8))
    exit(2)
    #else
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
    #endif
}
if args.first == "costs" {
    await printCosts(publisher)
    exit(0)
}
#if os(Linux)
print("usage-relay --version\nusage-relay run [--output FILE] [--no-costs] [--state-dir DIR] [--cache-dir DIR]\nusage-relay check FILE\nusage-relay costs\nPass --output with a path inside a synced folder to share usage-relay.json with your iPhone.")
#else
print("usage-relay --version\nusage-relay run [--output FILE] [--no-costs] [--state-dir DIR]\nusage-relay check FILE\nusage-relay costs\nusage-relay statusline install|uninstall|status")
#endif
exit(args.isEmpty ? 0 : 2)
