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
        let height = Config.spriteHeight(for: cfg.size)

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
        panel.orderFrontRegardless()
        log("ordered front visible=\(panel.isVisible) frame=\(panel.frame)")
        pet.start()

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
        let menu = NSMenu()
        menu.delegate = pet
        statusItem.menu = menu
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
    let cfg = Config.load()
    log("shot: cfg ok size=\(cfg.size)")
    let view = PetView(lib: lib, cfg: cfg, spriteH: Config.spriteHeight(for: cfg.size))
    log("shot: view \(view.bounds)")
    view.say("我是大肥鱼,今天也在摸鱼。")
    log("shot: said")
    let size = view.bounds.size
    let W = Int(size.width * 2), H = Int(size.height * 2)
    guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        log("shot: no ctx"); exit(1)
    }
    ctx.scaleBy(x: 2, y: 2)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    log("shot: ctx ok")
    view.draw(view.bounds)
    NSGraphicsContext.restoreGraphicsState()
    log("shot: drawn")
    guard let cg = ctx.makeImage() else { log("shot: no image"); exit(1) }
    let rep = NSBitmapImageRep(cgImage: cg)
    if let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: URL(fileURLWithPath: "/tmp/pet-render.png"))
        log("shot: wrote \(W)x\(H)")
    } else { log("shot: encode fail") }
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
