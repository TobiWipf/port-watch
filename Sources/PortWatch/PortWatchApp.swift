import SwiftUI

struct Server: Identifiable, Hashable {
    let pid: Int32
    let port: Int
    let command: String
    let cwd: String
    var id: String { "\(pid):\(port)" }
    var project: String { URL(fileURLWithPath: cwd).lastPathComponent }
}

@MainActor final class Scanner: ObservableObject {
    @Published var servers: [Server] = []

    init() {
        Task {
            while true {
                servers = await Task.detached { Scanner.scan() }.value
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    nonisolated static func scan() -> [Server] {
        var listeners: [(pid: Int32, command: String, port: Int)] = []
        var pid: Int32 = 0, command = ""
        for line in lsof(["+c0", "-nP", "-iTCP", "-sTCP:LISTEN", "-Fpcn"]).split(separator: "\n") {
            let value = String(line.dropFirst())
            switch line.first {
            case "p": pid = Int32(value) ?? 0
            case "c": command = value
            case "n": if let port = Int(value.split(separator: ":").last ?? "") { listeners.append((pid, command, port)) }
            default: break
            }
        }
        guard !listeners.isEmpty else { return [] }

        var cwds: [Int32: String] = [:]
        let pids = Set(listeners.map(\.pid)).map(String.init).joined(separator: ",")
        for line in lsof(["-a", "-p", pids, "-d", "cwd", "-Fpn"]).split(separator: "\n") {
            let value = String(line.dropFirst())
            if line.first == "p" { pid = Int32(value) ?? 0 }
            if line.first == "n" { cwds[pid] = value }
        }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var seen = Set<String>()
        return listeners.compactMap { l in
            guard let cwd = cwds[l.pid], cwd.hasPrefix(home + "/") else { return nil }
            let s = Server(pid: l.pid, port: l.port, command: l.command, cwd: cwd)
            return seen.insert(s.id).inserted ? s : nil
        }.sorted { $0.port < $1.port }
    }

    nonisolated static func lsof(_ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        try? p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}

@main
struct PortWatchApp: App {
    @StateObject private var scanner = Scanner()

    var body: some Scene {
        MenuBarExtra("Dev servers", systemImage: "server.rack") {
            if scanner.servers.isEmpty { Text("No dev servers running") }
            ForEach(scanner.servers) { s in
                Menu(":\(s.port)  \(s.project)  (\(s.command))") {
                    Button("Open in Browser") { NSWorkspace.shared.open(URL(string: "http://localhost:\(s.port)")!) }
                    Button("Reveal in Finder") { NSWorkspace.shared.open(URL(fileURLWithPath: s.cwd)) }
                    Button("Stop") { kill(s.pid, SIGTERM) }
                }
            }
            Divider()
            Button("Quit") { NSApp.terminate(nil) }.keyboardShortcut("q")
        }
    }
}
