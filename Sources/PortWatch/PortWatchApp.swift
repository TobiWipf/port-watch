import SwiftUI

struct Project: Identifiable {
    let cwd: String
    let tool: String
    let ports: [Int]
    let pids: [Int32]
    var id: String { cwd }
    var name: String { URL(fileURLWithPath: cwd).lastPathComponent }
    var path: String { cwd.replacingOccurrences(of: Scanner.home, with: "~") }
}

@MainActor final class Scanner: ObservableObject {
    @Published var projects: [Project] = []

    nonisolated static let home = FileManager.default.homeDirectoryForCurrentUser.path

    init() {
        Task {
            while true {
                projects = await Task.detached { Scanner.scan() }.value
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    nonisolated static func scan() -> [Project] {
        var portsByPid: [Int32: Set<Int>] = [:]
        var names: [Int32: String] = [:]
        var pid: Int32 = 0
        for line in run("/usr/sbin/lsof", ["+c0", "-nP", "-iTCP", "-sTCP:LISTEN", "-Fpcn"]).split(separator: "\n") {
            let value = String(line.dropFirst())
            switch line.first {
            case "p": pid = Int32(value) ?? 0
            case "c": names[pid] = value
            case "n": if let port = Int(value.split(separator: ":").last ?? "") { portsByPid[pid, default: []].insert(port) }
            default: break
            }
        }
        guard !portsByPid.isEmpty else { return [] }
        let pidList = portsByPid.keys.map(String.init).joined(separator: ",")

        var cwds: [Int32: String] = [:]
        for line in run("/usr/sbin/lsof", ["-a", "-p", pidList, "-d", "cwd", "-Fpn"]).split(separator: "\n") {
            let value = String(line.dropFirst())
            if line.first == "p" { pid = Int32(value) ?? 0 }
            if line.first == "n" { cwds[pid] = value }
        }

        var tools: [Int32: String] = [:]
        for line in run("/bin/ps", ["-o", "pid=,args=", "-p", pidList]).split(separator: "\n") {
            let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 1)
            guard parts.count == 2, let p = Int32(parts[0]) else { continue }
            tools[p] = tool(in: String(parts[1]))
        }

        let byCwd = Dictionary(grouping: portsByPid.keys) { cwds[$0] ?? "/" }
        return byCwd.compactMap { cwd, pids in
            guard cwd.hasPrefix(home + "/"), !cwd.hasPrefix(home + "/Library/") else { return nil }
            // Ports in the ephemeral range are treated as helpers (wrangler inspector, workerd), so a server bound to a random high port is hidden.
            let ports = pids.flatMap { portsByPid[$0] ?? [] }.filter { $0 < 49152 }.sorted()
            guard !ports.isEmpty else { return nil }
            let main = pids.filter { portsByPid[$0]?.contains(ports[0]) == true }
            let tool = main.lazy.compactMap { tools[$0] }.first ?? main.lazy.compactMap { names[$0] }.first ?? ""
            return Project(cwd: cwd, tool: tool, ports: ports, pids: pids)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    nonisolated static func tool(in args: String) -> String? {
        for token in args.split(separator: " ") {
            guard let range = token.range(of: "node_modules/", options: .backwards) else { continue }
            let package = token[range.upperBound...].split(separator: "/").first { ![".bin", "..", ".pnpm"].contains($0) }
            if let package, package != "node" { return String(package) }
        }
        return nil
    }

    nonisolated static func run(_ executable: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        try? p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}

struct ProjectRow: View {
    let project: Project

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(project.name).font(.headline)
                    if !project.tool.isEmpty {
                        Text(project.tool)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
                    }
                }
                Text(project.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
                HStack(spacing: 10) {
                    ForEach(project.ports, id: \.self) { port in
                        Link("localhost:\(String(port))", destination: URL(string: "http://localhost:\(port)")!)
                            .font(.callout.monospacedDigit())
                    }
                }
            }
            Spacer(minLength: 0)
            Button {
                NSWorkspace.shared.open(URL(fileURLWithPath: project.cwd))
            } label: {
                Image(systemName: "folder")
            }
            .help("Show in Finder")
            Button {
                project.pids.forEach { kill($0, SIGTERM) }
            } label: {
                Image(systemName: "stop.circle")
            }
            .help("Stop server")
        }
        .buttonStyle(.borderless)
        .padding(.vertical, 6)
    }
}

@main
struct PortWatchApp: App {
    @StateObject private var scanner = Scanner()

    var body: some Scene {
        MenuBarExtra("Port Watch", systemImage: "server.rack") {
            VStack(alignment: .leading, spacing: 0) {
                Text("Running dev servers")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)
                if scanner.projects.isEmpty {
                    Text("Nothing running")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 12)
                }
                ForEach(scanner.projects) { project in
                    Divider()
                    ProjectRow(project: project)
                }
                Divider()
                HStack {
                    Spacer()
                    Button("Quit") { NSApp.terminate(nil) }
                        .keyboardShortcut("q")
                        .buttonStyle(.borderless)
                }
                .padding(.top, 8)
            }
            .padding(12)
            .frame(width: 340)
        }
        .menuBarExtraStyle(.window)
    }
}
