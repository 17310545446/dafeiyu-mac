import AppKit

final class PetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: PetPanel!
    var pet: PetView!
    var statusItem: NSStatusItem!
    var chat: ChatController!
    var balanceMonitor: BalanceMonitor!
    var hiddenByUser = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        log("didFinishLaunching")
        let cfg = Config.load()
        let lib = SpriteLibrary(dir: SpriteLibrary.resourceDir())
        let skin = PetView.Skin(rawValue: cfg.skin) ?? .dafeiyu
        let height = PetView.displayHeight(skin: skin, size: cfg.size)

        pet = PetView(lib: lib, cfg: cfg, spriteH: height)

        panel = PetPanel(contentRect: NSRect(x: 0, y: 0, width: pet.winW, height: pet.winH),
                         styleMask: [.borderless],
                         backing: .buffered,
                         defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = cfg.topmost ? .floating : .normal
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = cfg.passthrough
        panel.contentView = pet
        pet.panel = panel
        log("panel frame=\(panel.frame) spriteDir=\(SpriteLibrary.resourceDir().path)")

        if let x = cfg.x, let y = cfg.y {
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            let vf = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            panel.setFrameOrigin(NSPoint(x: vf.maxX - pet.winW - 80, y: vf.minY + 60))
        }
        pet.snapInto(panel: panel)
        pet.homeCenter = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        panel.orderFrontRegardless()
        log("ordered front visible=\(panel.isVisible) frame=\(panel.frame)")
        pet.start()
        pet.greet()
        AudioManager.shared.applyBGMPreference()

        if CommandLine.arguments.contains("--throw-test") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.pet.debugThrow()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 7) { exit(0) }
        }

        let chat = ChatController()
        chat.pet = pet
        pet.chat = chat
        self.chat = chat

        HotKeyCenter.shared.onFire = { [weak self] in
            guard let self, let f = self.panel?.frame else { return }
            self.chat.toggle(near: f)
        }
        let hkStatus = HotKeyCenter.shared.register()
        log("hotkey ⌃⌥K register status=\(hkStatus)")

        setupStatusItem(icon: lib.icon())

        let monitor = BalanceMonitor()
        monitor.onUpdate = { [weak self] total in
            guard let self, let button = self.statusItem.button else { return }
            let text = total >= 100 ? String(format: "¥%.0f", total) : String(format: "¥%.1f", total)
            button.title = " " + text
            log("balance update=\(text)")
        }
        monitor.onLowBalance = { [weak self] total, threshold in
            self?.pet.say(String(format: "余额只剩 ¥%.1f,记得充值", total))
        }
        monitor.start()
        self.balanceMonitor = monitor

        if CommandLine.arguments.contains("--open-chat") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self, let f = self.panel?.frame else { return }
                self.chat.show(near: f)
            }
        }

        NotificationCenter.default.addObserver(self, selector: #selector(saveState),
                                               name: NSApplication.willTerminateNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    @objc func statusClicked(_ sender: Any?) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            guard let button = statusItem.button else { return }
            let menu = pet.buildMenu()
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
        } else {
            pet.toggleVisible()
        }
    }

    @objc func saveState() { pet.savePos() }

    @objc func screenChanged() {
        if let p = panel { pet.snapInto(panel: p) }
    }

    func setupStatusItem(icon: NSImage?) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            if let icon {
                let img = NSImage(size: NSSize(width: 20, height: 20))
                img.lockFocus()
                icon.draw(in: NSRect(x: 0, y: 0, width: 20, height: 20))
                img.unlockFocus()
                img.isTemplate = false
                button.image = img
            } else {
                button.title = "🐋"
            }
            button.toolTip = "大肥鱼桌宠"
        }
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }
}

// MARK: 入口

func log(_ msg: String) {
    guard ProcessInfo.processInfo.environment["DAFEIYU_DEBUG"] != nil else { return }
    let line = "[\(Date())] \(msg)\n"
    if let d = line.data(using: .utf8) {
        let url = URL(fileURLWithPath: "/tmp/dafeiyu-debug.log")
        if let fh = try? FileHandle(forWritingTo: url) {
            fh.seekToEndOfFile(); fh.write(d); try? fh.close()
        } else {
            try? d.write(to: url)
        }
    }
}

// --shot: 离屏渲染一张 PNG,用于自检(不需要录屏权限)
if CommandLine.arguments.contains("--shot") {
    log("shot: start")
    let lib = SpriteLibrary(dir: SpriteLibrary.resourceDir())
    log("shot: spriteDir=\(SpriteLibrary.resourceDir().path)")
    var cfg = Config.load()
    if let i = CommandLine.arguments.firstIndex(of: "--shot"),
       CommandLine.arguments.count > i + 1,
       CommandLine.arguments[i + 1] == "bigfish" {
        cfg.skin = "bigfish"
    }
    log("shot: cfg ok size=\(cfg.size)")
    // DState 只属于 dafeiyu 皮肤;直接指定姿势时自动切过去,否则画的是当前皮肤
    if let i = CommandLine.arguments.firstIndex(of: "--shot"),
       CommandLine.arguments.count > i + 1,
       DState(rawValue: CommandLine.arguments[i + 1]) != nil {
        cfg.skin = "dafeiyu"
    }
    let skin = PetView.Skin(rawValue: cfg.skin) ?? .dafeiyu
    let view = PetView(lib: lib, cfg: cfg, spriteH: PetView.displayHeight(skin: skin, size: cfg.size))
    log("shot: view \(view.bounds)")
    if let i = CommandLine.arguments.firstIndex(of: "--shot"),
       CommandLine.arguments.count > i + 1,
       CommandLine.arguments[i + 1] == "sign" {
        view.signPreview = "编译通过了"
        view.stateOverride = .happy
        view.overrideUntil = .greatestFiniteMagnitude
    } else if let i = CommandLine.arguments.firstIndex(of: "--shot"),
       CommandLine.arguments.count > i + 1,
       let st = DState(rawValue: CommandLine.arguments[i + 1]) {
        view.stateOverride = st
        view.overrideUntil = .greatestFiniteMagnitude
    } else {
        view.say("我是大肥鱼，今天也在摸鱼。")
    }
    log("shot: said")
    // 自检用:固定朝向,否则每次启动随机翻转,跨进程逐帧对比无意义
    view.dir = .down
    view.facing = 1

    var times: [Double] = [0]
    if let i = CommandLine.arguments.firstIndex(of: "--shot-at"),
       CommandLine.arguments.count > i + 1 {
        times = CommandLine.arguments[i + 1].split(separator: ",").compactMap { Double($0) }
        if times.isEmpty { times = [0] }
    }

    let size = view.bounds.size
    let W = Int(size.width * 2), H = Int(size.height * 2)
    for at in times {
        if at > 0 { view.startedAt = Date().addingTimeInterval(-at) }
        guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            log("shot: no ctx"); exit(1)
        }
        ctx.scaleBy(x: 2, y: 2)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        view.draw(view.bounds)
        NSGraphicsContext.restoreGraphicsState()
        guard let cg = ctx.makeImage() else { log("shot: no image"); exit(1) }
        let rep = NSBitmapImageRep(cgImage: cg)
        let path = times.count > 1
            ? String(format: "/tmp/pet-shot-%04d.png", Int(at * 1000))
            : "/tmp/pet-render.png"
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
            log("shot: wrote \(path) \(W)x\(H)")
        } else { log("shot: encode fail") }
    }
    exit(0)
}

let app = NSApplication.shared

if CommandLine.arguments.contains("--balance-test") {
    guard let found = KeyStore.deepSeekKey() else {
        print("ERR: 没找到 DeepSeek Key")
        exit(1)
    }
    let sem = DispatchSemaphore(value: 0)
    DeepSeekClient.fetch(key: found.key) { result in
        switch result {
        case .success(let infos):
            print("OK(src=\(found.source)): " + infos.map { $0.speech }.joined(separator: " | "))
        case .failure(let err):
            print("ERR: \(err.localizedDescription)")
        }
        sem.signal()
    }
    sem.wait()
    exit(0)
}

if let widx = CommandLine.arguments.firstIndex(of: "--weather-test") {
    let city = CommandLine.arguments.count > widx + 1 ? CommandLine.arguments[widx + 1] : "汕头"
    let sem = DispatchSemaphore(value: 0)
    WeatherClient.fetch(city: city) { result in
        switch result {
        case .success(let w):
            print("OK: \(w.speech)")
        case .failure(let e):
            print("ERR: \(e.localizedDescription)")
        }
        sem.signal()
    }
    sem.wait()
    exit(0)
}

if CommandLine.arguments.contains("--history-test") {
    let msg = "记住:我喜欢白饭"
    let chat = ChatController()
    chat.quickSend(msg)
    let deadline = Date().addingTimeInterval(25)
    while Date() < deadline {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.2))
        if let d = try? Data(contentsOf: HistoryStore.url),
           let t = String(data: d, encoding: .utf8), t.contains("\"assistant\"") { break }
    }
    let path = HistoryStore.url.path
    let text = (try? String(contentsOf: HistoryStore.url, encoding: .utf8)) ?? "(no file)"
    print("HISTORY_FILE:", path)
    print("BYTES:", text.utf8.count)
    print(text.prefix(400))
    exit(0)
}

if let idx = CommandLine.arguments.firstIndex(of: "--chat-test") {
    let msg = CommandLine.arguments.count > idx + 1 ? CommandLine.arguments[idx + 1] : "你好"
    let cfg = Config.load()
    let key = Keychain.read(account: "api-key") ?? ""
    let sem = DispatchSemaphore(value: 0)
    LLMClient.chat(baseURL: cfg.baseURL, model: cfg.model, apiKey: key,
                   history: [.init(role: "user", content: msg)]) { result in
        switch result {
        case .success(let reply): print("OK[\(cfg.model)]: \(reply)")
        case .failure(let err): print("ERR: \(err.localizedDescription)")
        }
        sem.signal()
    }
    sem.wait()
    exit(0)
}

let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
