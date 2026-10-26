import AppKit
import Foundation

private func fsin(_ x: CGFloat) -> CGFloat { CGFloat(sin(Double(x))) }
private func fcos(_ x: CGFloat) -> CGFloat { CGFloat(cos(Double(x))) }

final class PetView: NSView, NSMenuDelegate {

    // 常量
    static let bubbleH: CGFloat = 56
    static let margin: CGFloat = 4
    static let speed: CGFloat = 380
    static let tick: TimeInterval = 0.02
    static let agentLabel = "io.github.dafeiyu.mac"

    enum Mode: String { case wander, follow, still }
    enum Dir { case up, down, left, right }

    let lib: SpriteLibrary
    var cfg: Config
    weak var panel: NSPanel?

    var spriteH: Int
    var winW: CGFloat
    var winH: CGFloat

    var mode: Mode = .wander
    var dir: Dir = .down
    var facing: CGFloat = 1
    var prevDir: Dir = .down
    var prevFacing: CGFloat = 1
    var crossT: CGFloat = 0

    var target: NSPoint?
    var restUntil: TimeInterval = 0
    var curSpeed: CGFloat = 0
    var action: String?
    var actionT: CGFloat = 0

    var bubbleText = ""
    var bubbleInner = false
    var bubbleUntil: TimeInterval = 0
    var lastLine = ""
    var lastSpeakAt: TimeInterval = -999

    var jumpT: CGFloat = 0
    var startedAt = Date()
    var timer: Timer?

    var dragging = false
    var dragStartMouse: NSPoint = .zero
    var dragStartOrigin: NSPoint = .zero
    var suppressClick = false
    weak var chat: ChatController?
    var chatPaused = false
    let monitor = SystemMonitor()
    var lastMonitorAt: TimeInterval = 0

    var now: TimeInterval { Date().timeIntervalSince(startedAt) }

    init(lib: SpriteLibrary, cfg: Config, spriteH: Int) {
        self.lib = lib
        self.cfg = cfg
        self.spriteH = spriteH
        let mx = CGFloat(spriteH) * 0.062 + 6
        self.winW = lib.maxWidth(height: spriteH) + mx * 2
        self.winH = CGFloat(spriteH) + PetView.bubbleH + PetView.margin * 2 + 10
        super.init(frame: NSRect(x: 0, y: 0, width: winW, height: winH))
        self.mode = Mode(rawValue: cfg.mode) ?? .wander
        self.bubbleUntil = 0
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    // MARK: 生命周期

    func start() {
        let t = Timer(timeInterval: PetView.tick, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    deinit { timer?.invalidate() }

    override var isFlipped: Bool { false }

    // MARK: 主循环

    func tick() {
        if jumpT > 0 { jumpT = max(0, jumpT - 0.06) }
        if crossT > 0 { crossT = max(0, crossT - 0.15) }
        if actionT > 0 {
            actionT = max(0, actionT - 0.03)
            if actionT == 0 { action = nil }
        }

        monitorTick()
        if chatPaused { needsDisplay = true; return }
        if dragging { needsDisplay = true; return }
        guard let panel else { return }

        let time = now

        switch mode {
        case .follow:
            let m = NSEvent.mouseLocation
            let f = panel.frame
            let near = m.x >= f.minX - 100 && m.x <= f.maxX + 100
                && m.y >= f.minY - 100 && m.y <= f.maxY + 100
            if near {
                target = nil
            } else {
                let geo = screenFrame(containing: m)
                let tx = min(max(geo.minX, m.x - f.width / 2), geo.maxX - f.width)
                let ty = min(max(geo.minY, m.y - 90), geo.maxY - f.height)
                target = NSPoint(x: tx + f.width / 2, y: ty + f.height / 2)
            }

        case .wander:
            if target == nil {
                if time < restUntil {
                    maybeIdleAction()
                    needsDisplay = true
                    return
                }
                let f = panel.frame
                let geo = screenFrame(containing: NSPoint(x: f.midX, y: f.midY))
                let loX = geo.minX + 40
                let hiX = max(loX + 1, geo.maxX - f.width - 40)
                let loY = geo.minY + 40
                let hiY = max(loY + 1, geo.maxY - f.height - 40)
                target = NSPoint(x: CGFloat.random(in: loX...hiX) + f.width / 2,
                                 y: CGFloat.random(in: loY...hiY) + f.height / 2)
            }

        case .still:
            maybeIdleAction()
            needsDisplay = true
            return
        }

        if let tg = target {
            let f = panel.frame
            let cx = f.midX, cy = f.midY
            let dx = tg.x - cx, dy = tg.y - cy
            let dist = sqrt(dx * dx + dy * dy)
            if dist < 12 {
                target = nil
                restUntil = time + Double.random(in: 8...18)
                setDir(.down, facing: 1)
            } else {
                let step = curSpeed * CGFloat(PetView.tick)
                let nx = cx + dx / dist * step
                let ny = cy + dy / dist * step
                moveOrigin(NSPoint(x: nx - f.width / 2, y: ny - f.height / 2))
                if abs(dx) > abs(dy) * 1.15 {
                    setDir(dx < 0 ? .left : .right, facing: dx < 0 ? 1 : -1)
                } else {
                    setDir(dy < 0 ? .down : .up)
                }
            }
            if CGFloat.random(in: 0...1) < 0.002 && jumpT == 0 { jumpT = 0.5 }
        }

        let wanted: CGFloat = target != nil ? PetView.speed : 0
        curSpeed += (wanted - curSpeed) * 0.3
        needsDisplay = true
    }

    func monitorTick() {
        let time = now
        guard time - lastMonitorAt >= 10 else { return }
        lastMonitorAt = time
        let cpu = monitor.cpuUsage()
        let mem = monitor.memoryUsage()
        if cpu >= 90 {
            say("CPU跑满了,再这样下去我就卡死了")
        } else if mem >= 93 {
            say("内存爆了,快关掉几个没用的东西吧,注意,别把我关了")
        }
    }

    func maybeIdleAction() {
        guard CGFloat.random(in: 0...1) < 0.005 else { return }
        let pick = CGFloat.random(in: 0...1)
        if pick < 0.35 {
            jumpT = 1.0
        } else if pick < 0.6 {
            action = "sway"; actionT = 1.0
        } else if pick < 0.8 {
            action = "stretch"; actionT = 1.0
        } else if pick < 0.9, now - lastSpeakAt >= 30 {
            lastSpeakAt = now
            if pick < 0.82 {
                say(Lines.inner.randomElement() ?? "……", inner: true)
            } else {
                say(Lines.idle.randomElement() ?? "……")
            }
        }
    }

    // MARK: 说话

    func say(_ text: String, inner: Bool = false) {
        guard text != lastLine else { return }
        lastLine = text
        bubbleInner = inner
        bubbleText = inner ? "(\(text))" : text
        bubbleUntil = now + 2.8
        needsDisplay = true
    }

    // MARK: 位置 / 屏幕

    func screenFrame(containing p: NSPoint) -> NSRect {
        for s in NSScreen.screens where NSMouseInRect(p, s.frame, false) {
            return s.visibleFrame
        }
        return NSScreen.main?.visibleFrame ?? .zero
    }

    func moveOrigin(_ p: NSPoint) {
        panel?.setFrameOrigin(p)
    }

    func snapInto(panel: NSPanel) {
        let f = panel.frame
        let geo = screenFrame(containing: NSPoint(x: f.midX, y: f.midY))
        let x = min(max(geo.minX, f.minX), max(geo.minX, geo.maxX - f.width))
        let y = min(max(geo.minY, f.minY), max(geo.minY, geo.maxY - f.height))
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    func savePos() {
        guard let f = panel?.frame else { return }
        cfg.x = Double(f.minX)
        cfg.y = Double(f.minY)
        cfg.save()
    }

    // MARK: 方向 / 尺寸

    func setDir(_ d: Dir, facing f: CGFloat? = nil) {
        if d != dir {
            prevDir = dir
            prevFacing = facing
            crossT = 1.0
            dir = d
        }
        if let f, f != facing { facing = f }
    }

    func spriteImage(_ d: Dir, _ f: CGFloat) -> NSImage? {
        let name: String
        switch d {
        case .left, .right: name = "侧面"
        case .up: name = "背面"
        case .down: name = "正面"
        }
        return lib.image(name, height: spriteH)
    }

    func applySize(_ mult: Double) {
        guard let panel else { return }
        let newH = Config.spriteHeight(for: mult)
        spriteH = newH
        let mx = CGFloat(newH) * 0.062 + 6
        winW = lib.maxWidth(height: newH) + mx * 2
        winH = CGFloat(newH) + PetView.bubbleH + PetView.margin * 2 + 10
        let old = panel.frame
        let origin = NSPoint(x: old.midX - winW / 2, y: old.minY)
        panel.setFrame(NSRect(origin: origin, size: NSSize(width: winW, height: winH)), display: true)
        cfg.size = mult
        cfg.save()
        crossT = 0
        snapInto(panel: panel)
        needsDisplay = true
    }

    // MARK: 绘制

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setShouldAntialias(true)
        ctx.interpolationQuality = .high

        let time = now
        if !bubbleText.isEmpty && time < bubbleUntil { drawBubble() }

        let walking = target != nil && !dragging
        let sway = walking ? fsin(time * 9.0) * 3.5 : fsin(time * 2.5) * 1.5
        let bob: CGFloat = walking ? -abs(fsin(time * 4.5)) * 7.0 : 0
        let breath = 1.0 + 0.02 * fsin(time * 2.5)
        let jump: CGFloat = jumpT > 0 ? -abs(fsin(jumpT * .pi)) * 14 * jumpT : 0

        var actRot: CGFloat = 0
        var actSX: CGFloat = 0
        var actSY: CGFloat = 0
        if action == "sway" {
            actRot = fsin(actionT * .pi * 2) * 10 * actionT
        } else if action == "stretch" {
            actSY = 0.06 * fsin(actionT * .pi)
            actSX = -0.03 * fsin(actionT * .pi)
        }

        let bottom = PetView.margin + CGFloat(spriteH)

        func drawOne(_ d: Dir, _ f: CGFloat, alpha: CGFloat) {
            guard let img = spriteImage(d, f) else { return }
            let ph = img.size.height * breath * (1 + actSY)
            let pw = img.size.width * breath * (1 + actSX)
            ctx.saveGState()
            ctx.setAlpha(alpha)
            ctx.translateBy(x: bounds.midX, y: bottom)
            ctx.rotate(by: sway + actRot)
            if f < 0 { ctx.scaleBy(x: -1, y: 1) }
            let rect = CGRect(x: -pw / 2, y: -ph + jump + bob, width: pw, height: ph)
            img.draw(in: rect, from: .zero, operation: .sourceOver, fraction: alpha)
            ctx.restoreGState()
        }

        if crossT > 0 {
            drawOne(prevDir, prevFacing, alpha: crossT)
            drawOne(dir, facing, alpha: 1.0 - crossT)
        } else {
            drawOne(dir, facing, alpha: 1.0)
        }
    }

    func drawBubble() {
        let inner = bubbleInner
        let base = NSFont.systemFont(ofSize: 12)
        let font: NSFont = inner ? (NSFontManager.shared.convert(base, toHaveTrait: .italicFontMask)) : base
        let fg: NSColor = inner ? NSColor(calibratedRed: 125 / 255, green: 125 / 255, blue: 138 / 255, alpha: 1)
                               : NSColor(calibratedRed: 60 / 255, green: 60 / 255, blue: 80 / 255, alpha: 1)
        let bg: NSColor = inner ? NSColor(calibratedRed: 232 / 255, green: 232 / 255, blue: 238 / 255, alpha: 0.92)
                               : NSColor(calibratedWhite: 1.0, alpha: 0.92)

        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: fg]
        let maxW = min(240, bounds.width - 16)

        var lines: [String] = []
        var cur = ""
        for ch in bubbleText {
            let test = cur + String(ch)
            if (test as NSString).size(withAttributes: attrs).width > maxW - 20 {
                lines.append(cur)
                cur = String(ch)
            } else {
                cur = test
            }
        }
        lines.append(cur)

        let lineH = font.ascender - font.descender + font.leading
        let textW = lines.map { ($0 as NSString).size(withAttributes: attrs).width }.max() ?? 0
        let bw = textW + 20
        let bh = CGFloat(lines.count) * lineH + 14
        let bx = (bounds.width - bw) / 2
        let by = bounds.maxY - 6 - bh

        bg.setFill()
        let path = NSBezierPath(roundedRect: NSRect(x: bx, y: by, width: bw, height: bh), xRadius: 10, yRadius: 10)
        path.fill()

        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: bounds.midX, y: by))
        tail.line(to: NSPoint(x: bounds.midX - 6, y: by - 8))
        tail.line(to: NSPoint(x: bounds.midX + 6, y: by - 8))
        tail.close()
        tail.fill()

        let para = NSMutableParagraphStyle()
        para.alignment = .center
        let drawAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: fg, .paragraphStyle: para]
        for (i, line) in lines.enumerated() {
            let rect = NSRect(x: bx, y: by + 7 + CGFloat(lines.count - 1 - i) * lineH, width: bw, height: lineH)
            (line as NSString).draw(in: rect, withAttributes: drawAttrs)
        }
    }

    // MARK: 鼠标

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            suppressClick = true
            showFoodMenu()
            return
        }
        suppressClick = false
        dragging = false
        dragStartMouse = NSEvent.mouseLocation
        dragStartOrigin = panel?.frame.origin ?? .zero
    }

    override func mouseDragged(with event: NSEvent) {
        let m = NSEvent.mouseLocation
        let dx = m.x - dragStartMouse.x
        let dy = m.y - dragStartMouse.y
        if !dragging && hypot(dx, dy) > 4 { dragging = true }
        guard dragging else { return }
        moveOrigin(NSPoint(x: dragStartOrigin.x + dx, y: dragStartOrigin.y + dy))
        if abs(dx) > 10 { setDir(dx < 0 ? .left : .right, facing: dx < 0 ? 1 : -1) }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if suppressClick { suppressClick = false; return }
        if dragging {
            dragging = false
            setDir(.down, facing: 1)
            target = nil
            restUntil = now + Double.random(in: 6...14)
            if Bool.random() { say(Lines.drag.randomElement() ?? "放我下来！") }
            savePos()
        } else {
            if CGFloat.random(in: 0...1) < 0.7 { jumpT = 1.0 }
            if CGFloat.random(in: 0...1) < 0.6 { say(Lines.react.randomElement() ?? "别戳我") }
        }
        needsDisplay = true
    }

    override func rightMouseDown(with event: NSEvent) {
        showMenu(at: NSEvent.mouseLocation)
    }

    func showMenu(at point: NSPoint) {
        let menu = buildMenu()
        menu.popUp(positioning: nil, at: NSPoint(x: 10, y: bounds.midY), in: self)
        _ = point
    }

    func showFoodMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for (emoji, name) in Lines.foods {
            let item = NSMenuItem(title: "\(emoji)  \(name)", action: #selector(pickFood(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = emoji
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: bounds.midX, y: bounds.midY), in: self)
    }

    @objc func pickFood(_ sender: NSMenuItem) {
        guard let emoji = sender.representedObject as? String else { return }
        jumpT = 0.6
        let pool = Lines.foodLines[emoji] ?? ["好吃！"]
        say(pool.randomElement() ?? "好吃！")
    }

    // MARK: 菜单

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        populate(menu)
    }

    func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        populate(menu)
        return menu
    }

    private func addCheck(_ menu: NSMenu, _ title: String, _ on: Bool, _ action: Selector, _ rep: Any? = nil) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.state = on ? .on : .off
        item.representedObject = rep
        menu.addItem(item)
    }

    private func populate(_ menu: NSMenu) {
        menu.addItem(withTitle: "大肥鱼", action: nil, keyEquivalent: "").isEnabled = false

        let modeMenu = NSMenu()
        for (label, key) in [("自由散步", "wander"), ("跟随鼠标", "follow"), ("原地待着", "still")] {
            addCheck(modeMenu, label, mode.rawValue == key, #selector(menuSetMode(_:)), key)
        }
        let modeItem = NSMenuItem(title: "模式", action: nil, keyEquivalent: "")
        modeItem.submenu = modeMenu
        menu.addItem(modeItem)

        let sizeMenu = NSMenu()
        for (label, mult) in [("小", 0.55), ("中", 0.7), ("大", 0.9)] {
            addCheck(sizeMenu, label, abs(cfg.size - mult) < 0.01, #selector(menuSetSize(_:)), mult)
        }
        let sizeItem = NSMenuItem(title: "大小", action: nil, keyEquivalent: "")
        sizeItem.submenu = sizeMenu
        menu.addItem(sizeItem)

        menu.addItem(NSMenuItem.separator())
        addCheck(menu, "鼠标穿透(点不到它)", cfg.passthrough, #selector(menuTogglePassthrough))
        addCheck(menu, "窗口置顶", cfg.topmost, #selector(menuToggleTopmost))
        addCheck(menu, "开机自启", cfg.autostart, #selector(menuToggleAutostart))
        menu.addItem(NSMenuItem.separator())

        let chatItem = NSMenuItem(title: "聊天…", action: #selector(menuOpenChat), keyEquivalent: "k")
        chatItem.keyEquivalentModifierMask = [.control, .option]
        chatItem.target = self
        menu.addItem(chatItem)

        let settingsItem = NSMenuItem(title: "API 设置…", action: #selector(menuOpenSettings), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let balanceItem = NSMenuItem(title: "DeepSeek 余额", action: #selector(menuBalance), keyEquivalent: "")
        balanceItem.target = self
        menu.addItem(balanceItem)

        let usageItem = NSMenuItem(title: "打开用量页…", action: #selector(menuOpenUsagePage), keyEquivalent: "")
        usageItem.target = self
        menu.addItem(usageItem)

        let gatewayItem = NSMenuItem(title: "打开网关面板…", action: #selector(menuOpenGateway), keyEquivalent: "")
        gatewayItem.target = self
        menu.addItem(gatewayItem)

        let weatherItem = NSMenuItem(title: "看天气", action: #selector(menuWeather), keyEquivalent: "")
        weatherItem.target = self
        menu.addItem(weatherItem)

        let sayItem = NSMenuItem(title: "说句话", action: #selector(menuSay), keyEquivalent: "")
        sayItem.target = self
        menu.addItem(sayItem)

        let hideItem = NSMenuItem(title: "隐藏", action: #selector(menuHide), keyEquivalent: "")
        hideItem.target = self
        menu.addItem(hideItem)

        let snapItem = NSMenuItem(title: "回到屏幕内", action: #selector(menuSnap), keyEquivalent: "")
        snapItem.target = self
        menu.addItem(snapItem)

        menu.addItem(NSMenuItem.separator())
        let quit = NSMenuItem(title: "退出", action: #selector(menuQuit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    @objc func menuSetMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let m = Mode(rawValue: raw) else { return }
        mode = m
        cfg.mode = raw
        cfg.save()
        target = nil
        say(m == .follow ? "跟着你咯～" : (m == .still ? "那我就在这儿待着" : "出去溜达一圈"))
    }

    @objc func menuSetSize(_ sender: NSMenuItem) {
        guard let mult = sender.representedObject as? Double else { return }
        applySize(mult)
    }

    @objc func menuTogglePassthrough() {
        cfg.passthrough.toggle()
        cfg.save()
        panel?.ignoresMouseEvents = cfg.passthrough
        if cfg.passthrough { say("我隐身了！菜单栏里点我解除～") }
    }

    @objc func menuToggleTopmost() {
        cfg.topmost.toggle()
        cfg.save()
        panel?.level = cfg.topmost ? .floating : .normal
        say(cfg.topmost ? "我又在最上面啦" : "好，我退到后面去")
    }

    @objc func menuToggleAutostart() {
        setAutostart(!cfg.autostart)
    }

    @objc func menuOpenChat() {
        guard let chat, let f = panel?.frame else { return }
        chat.toggle(near: f)
    }

    @objc func menuOpenSettings() {
        let cfg = Config.load()
        let alert = NSAlert()
        alert.messageText = "API 设置"
        alert.informativeText = "默认指向本机 LiteLLM 网关(http://127.0.0.1:4000/v1)。网关不需要鉴权时 Key 留空。"

        let stack = NSStackView(frame: NSRect(x: 0, y: 0, width: 340, height: 164))
        stack.orientation = .vertical
        stack.spacing = 8

        let urlField = NSTextField(string: cfg.baseURL)
        let modelField = NSTextField(string: cfg.model)
        let keyField = NSSecureTextField(string: Keychain.read(account: "api-key") ?? "")
        let cityField = NSTextField(string: cfg.city)
        cityField.placeholderString = "留空=按 IP 自动定位"
        let dsKeyField = NSSecureTextField(string: Keychain.read(account: "deepseek-key") ?? "")
        dsKeyField.placeholderString = "留空=读本机网关 .env"

        for (label, field) in [("Base URL", urlField), ("模型", modelField), ("API Key", keyField),
                               ("DS Key", dsKeyField), ("城市", cityField)] {
            let row = NSStackView()
            row.orientation = .horizontal
            row.spacing = 8
            let l = NSTextField(labelWithString: label)
            l.widthAnchor.constraint(equalToConstant: 70).isActive = true
            field.widthAnchor.constraint(equalToConstant: 250).isActive = true
            row.addArrangedSubview(l)
            row.addArrangedSubview(field)
            stack.addArrangedSubview(row)
        }
        alert.accessoryView = stack
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")

        if alert.runModal() == .alertFirstButtonReturn {
            var newCfg = cfg
            let url = urlField.stringValue.trimmingCharacters(in: .whitespaces)
            let model = modelField.stringValue.trimmingCharacters(in: .whitespaces)
            newCfg.baseURL = url.isEmpty ? "http://127.0.0.1:4000/v1" : url
            newCfg.model = model.isEmpty ? "deepseek-chat" : model
            newCfg.city = cityField.stringValue.trimmingCharacters(in: .whitespaces)
            newCfg.save()
            self.cfg = newCfg
            Keychain.save(account: "api-key", value: keyField.stringValue)
            Keychain.save(account: "deepseek-key", value: dsKeyField.stringValue)
            say("设置好了,来聊两句?")
        }
    }

    @objc func menuBalance() {
        guard let found = KeyStore.deepSeekKey() else {
            say("没找到 DeepSeek Key,去「API 设置」填一个")
            return
        }
        say("查余额…")
        DeepSeekClient.fetch(key: found.key) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let infos) where !infos.isEmpty:
                    self.say(infos[0].speech)
                case .success:
                    self.say("接口没返回余额信息")
                case .failure:
                    self.say("查余额失败,key 过期还是网络不通?")
                }
            }
        }
    }

    @objc func menuOpenUsagePage() {
        if let url = URL(string: "https://platform.deepseek.com/usage") {
            NSWorkspace.shared.open(url)
            say("用量页给你打开了")
        }
    }

    @objc func menuOpenGateway() {
        if let url = URL(string: "http://127.0.0.1:4000/ui") {
            NSWorkspace.shared.open(url)
            say("网关面板在这儿")
        }
    }

    @objc func menuWeather() {
        say("我看看云图…")
        WeatherClient.fetch(city: cfg.city) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let w):
                    self.say(w.speech)
                case .failure:
                    self.say("查不到天气,网络还是 wttr.in 挂了?")
                }
            }
        }
    }

    @objc func menuSay() {
        say(Lines.idle.randomElement() ?? "在呢")
        jumpT = 1.0
    }

    @objc func menuHide() {
        panel?.orderOut(nil)
    }

    @objc func menuSnap() {
        if let p = panel { snapInto(panel: p) }
    }

    @objc func menuQuit() {
        NSApp.terminate(nil)
    }

    // MARK: 开机自启

    var launchAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(PetView.agentLabel).plist")
    }

    func setAutostart(_ on: Bool) {
        let appPath = Bundle.main.bundlePath
        guard appPath.hasSuffix(".app") else {
            say("打包成 .app 才能设开机自启")
            return
        }
        if on {
            let plist = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
              <key>Label</key><string>\(PetView.agentLabel)</string>
              <key>ProgramArguments</key>
              <array><string>\(appPath)/Contents/MacOS/Dafeiyu</string></array>
              <key>RunAtLoad</key><true/>
            </dict>
            </plist>
            """
            try? FileManager.default.createDirectory(at: launchAgentURL.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            do {
                try plist.write(to: launchAgentURL, atomically: true, encoding: .utf8)
            } catch {
                say("写入自启配置失败")
                return
            }
            runLaunchctl(["load", "-w", launchAgentURL.path])
            cfg.autostart = true
            say("已开机自启，明天见～")
        } else {
            runLaunchctl(["unload", "-w", launchAgentURL.path])
            try? FileManager.default.removeItem(at: launchAgentURL)
            cfg.autostart = false
            say("已取消开机自启")
        }
        cfg.save()
    }

    func runLaunchctl(_ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = args
        try? p.run()
        p.waitUntilExit()
    }
}
