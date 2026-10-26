import AppKit
import Foundation

/// 任务状态来源:
/// 1. DSH 会话缓存(只读):`~/.dsh/storages/session_projcache/sessions/*.json`,
///    取最新一份的 sessionStats(steps/llmMs/toolMs)+ 标题 + cwd,判断"在想/在跑工具"。
/// 2. 本机推断(不需要 DSH):进程表(xcodebuild/swiftc/pytest/node/git)+ 前台 App + 空闲时长。
final class ActivityMonitor {

    enum Kind: String {
        case none, thinking, tool, building, testing, running, coding, browsing, idle
    }

    struct Status {
        var kind: Kind = .none
        var detail: String = ""
        var source: String = ""
    }

    var onChange: ((Status) -> Void)?
    private(set) var status = Status()

    private var timer: Timer?
    private var lastSteps = -1
    private var lastLlm: Double = -1
    private var lastTool: Double = -1
    private var lastDSHAt: TimeInterval = 0
    private let queue = DispatchQueue(label: "dafeiyu.activity", qos: .utility)

    func start() {
        let t = Timer(timeInterval: 2.5, repeats: true) { [weak self] _ in self?.sample() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        sample()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func sample() {
        queue.async { [weak self] in
            guard let self else { return }
            let mode = ProcessInfo.processInfo.environment["DAFEIYU_STATUS_SOURCE"] ?? "auto"
            let s: Status
            switch mode {
            case "process": s = self.processStatus()
            case "dsh": s = self.dshStatus() ?? Status()
            default: s = self.dshStatus() ?? self.processStatus()
            }
            DispatchQueue.main.async {
                let changed = s.kind != self.status.kind || s.detail != self.status.detail
                self.status = s
                if changed { self.onChange?(s) }
            }
        }
    }

    // MARK: DSH 会话

    private var sessionsDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".dsh/storages/session_projcache/sessions")
    }

    private func dshStatus() -> Status? {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: sessionsDir,
                                                      includingPropertiesForKeys: [.contentModificationDateKey]) else { return nil }

        var newest: (URL, Date)?
        for f in files where f.pathExtension == "json" {
            let d = (try? f.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if newest == nil || d > newest!.1 { newest = (f, d) }
        }
        guard let (url, mtime) = newest, Date().timeIntervalSince(mtime) < 25 else { return nil }
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let record = obj["record"] as? [String: Any] else { return nil }

        let identity = record["identity"] as? [String: Any] ?? [:]
        let cwd = identity["cwd"] as? String ?? ""
        let project = (cwd as NSString).lastPathComponent
        let rows = record["rows"] as? [String: Any] ?? [:]
        let stats = ((rows["sessionStats"] as? [String: Any])?["val"] as? [String: Any]) ?? [:]
        let title = ((rows["title"] as? [String: Any])?["val"] as? String) ?? ""

        let steps = (stats["steps"] as? NSNumber)?.intValue ?? 0
        let llm = (stats["llmMs"] as? NSNumber)?.doubleValue ?? 0
        let tool = (stats["toolMs"] as? NSNumber)?.doubleValue ?? 0

        var kind: Kind = .none
        if lastSteps >= 0 {
            let dSteps = steps - lastSteps
            let dLlm = llm - lastLlm
            let dTool = tool - lastTool
            if dSteps > 0 || dLlm > 0.5 || dTool > 0.5 {
                kind = dTool > dLlm ? .tool : .thinking
            }
        }
        if kind == .none, Date().timeIntervalSince(mtime) < 6 { kind = .thinking }

        lastSteps = steps
        lastLlm = llm
        lastTool = tool
        lastDSHAt = Date().timeIntervalSince1970

        let detail = project.isEmpty ? (title.isEmpty ? "DSH" : title) : project
        log("dsh: kind=\(kind.rawValue) steps=\(steps) dLlm=\(Int(llm)) dTool=\(Int(tool)) project=\(detail)")
        return Status(kind: kind, detail: detail, source: "DSH")
    }

    // MARK: 本机推断

    private func processStatus() -> Status {
        let idleKey = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown)
        let idleMouse = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .mouseMoved)
        if min(idleKey, idleMouse) > 300 {
            return Status(kind: .idle, detail: "没人在", source: "本机")
        }

        let cmds = Self.runningCommands()
        func has(_ needles: [String]) -> Bool {
            cmds.contains { line in needles.contains { line.contains($0) } }
        }

        if has(["xcodebuild", "swift-frontend", "swiftc", "swift-build"]) {
            return Status(kind: .building, detail: "编译中", source: "本机")
        }
        if has(["pytest", "jest", "vitest", "go test", "cargo test"]) {
            return Status(kind: .testing, detail: "跑测试", source: "本机")
        }
        if has(["docker build", "docker compose"]) {
            return Status(kind: .running, detail: "容器任务", source: "本机")
        }
        if has(["npm run", "pnpm ", "yarn ", "tsc ", "vite", "webpack", "next build"]) {
            return Status(kind: .running, detail: "Node 构建", source: "本机")
        }
        if has(["git "]) {
            return Status(kind: .running, detail: "Git 操作", source: "本机")
        }

        let app = NSWorkspace.shared.frontmostApplication?.localizedName ?? ""
        if ["Visual Studio Code", "Xcode", "Cursor", "Zed"].contains(where: { app.contains($0) }) {
            return Status(kind: .coding, detail: app, source: "本机")
        }
        if ["Chrome", "Safari", "Arc"].contains(where: { app.contains($0) }) {
            return Status(kind: .browsing, detail: app, source: "本机")
        }
        return Status(kind: .none, detail: app, source: "本机")
    }

    private static func runningCommands() -> [String] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/ps")
        p.arguments = ["-axo", "command"]
        let pipe = Pipe()
        p.standardOutput = pipe
        do { try p.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init)
    }
}
