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
    enum Skin: String { case classic, dafeiyu, bigfish }
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
    enum Action: Equatable { case sway, stretch, think, lookLeft, lookRight, lookUp, stroll, jump }
    var action: Action?
    var actionT: CGFloat = 0
    var nextActionAt: TimeInterval = 3
    var homeCenter: NSPoint = .zero
    var walkSpeed: CGFloat = PetView.speed

    var bubbleText = ""
    var bubbleInner = false
    var bubbleUntil: TimeInterval = 0
    /// 用户触发的话在这之前不许被自动台词覆盖(自言自语/状态播报)。
    var bubbleProtectedUntil: TimeInterval = 0
    var lastLine = ""
    var recentLines: [String] = []
    var lastSpeakAt: TimeInterval = -999

    var jumpT: CGFloat = 0
    var startedAt = Date()

    // MARK: 动效层(B 路线)
    /// 动作总时长,用来算进度包络;没有它动作只能硬起硬停。
    var actionDur: CGFloat = 0
    /// 姿势交叉淡化(避免 PNG 硬切造成"瞬移")。
    var poseShown: DState?
    var poseFadeFrom: DState?
    var poseFade: CGFloat = 0
    /// 跟随滞后:身体移动后的残留倾斜,模仿跟随动作。
    var lean: CGFloat = 0
    /// 走路摆幅与待机摆幅的混合量(0 待机 / 1 走路),起步停下都不瞬间换相。
    var walkBlend: CGFloat = 0
    var lastOriginX: CGFloat = .nan
    /// 重绘节流:空闲 30Hz,且画面量化后没变化就不画。
    var lastDrawAt: TimeInterval = 0
    var lastDrawSig: Int = .min
    var tickInterval: TimeInterval = PetView.tick
    /// 临时性能探针(DAFEIYU_PERF=1 时每 5 秒向 stderr 吐一行)
    var perfDraws = 0
    var perfLastAt: TimeInterval = 0
    var timer: Timer?

    var dragging = false
    var dragStartMouse: NSPoint = .zero
    var dragStartOrigin: NSPoint = .zero
    var suppressClick = false
    weak var chat: ChatController?

    lazy var functionBar: FunctionBar = {
        let bar = FunctionBar()
        bar.onChat = { [weak self] in
            guard let self, let f = self.panel?.frame else { return }
            self.chatPill.showAndFocus(above: f)
        }
        return bar
    }()

    lazy var chatPill: ChatPill = {
        let pill = ChatPill()
        pill.onSubmit = { [weak self] text in self?.chat?.quickSend(text) }
        return pill
    }()

    lazy var feedBar: FeedBar = {
        let bar = FeedBar()
        bar.onPick = { [weak self] emoji in self?.feed(emoji) }
        return bar
    }()
    var chatPaused = false
    var skin: Skin = .dafeiyu
    var stateOverride: DState?
    var overrideUntil: TimeInterval = 0
    var blinkUntil: TimeInterval = 0
    var nextBlinkAt: TimeInterval = 0
    var voiceUntil: TimeInterval = 0
    var sleeping = false
    var lastInteract: TimeInterval = 0
    var pokeCount = 0
    var pokeStartedAt: TimeInterval = 0
    var walkPhase: CGFloat = 0

    // 物理拖拽
    struct Particle {
        var p: CGPoint
        var v: CGVector
        var life: CGFloat
        var maxLife: CGFloat
        var size: CGFloat
        var color: NSColor
    }
    var velocity: CGPoint = .zero
    var falling = false
    var airRotation: CGFloat = 0
    var squash: CGFloat = 0
    var particles: [Particle] = []
    var dragSamples: [(t: TimeInterval, x: CGFloat, y: CGFloat)] = []

    // 任务状态
    let activity = ActivityMonitor()
    var currentStatus = ActivityMonitor.Status()
    var lastStatusSpeak: TimeInterval = -999

    // 举牌小剧场
    struct SignLine { let text: String; let dur: Double }
    var signQueue: [SignLine] = []
    var signCurrent: SignLine?
    var signEnd: TimeInterval = 0
    var signPreview: String?
    let monitor = SystemMonitor()
    var lastMonitorAt: TimeInterval = 0

    var now: TimeInterval { Date().timeIntervalSince(startedAt) }

    static func displayHeight(skin: Skin, size: Double) -> Int {
        switch skin {
        case .classic: return Config.spriteHeight(for: size)
        case .dafeiyu: return max(90, Int((620.0 * size * 0.5).rounded()))
        case .bigfish: return max(90, Int((340.0 * size).rounded()))
        }
    }

    init(lib: SpriteLibrary, cfg: Config, spriteH: Int) {
        self.lib = lib
        self.cfg = cfg
        self.spriteH = spriteH
        self.skin = Skin(rawValue: cfg.skin) ?? .dafeiyu
        let mx = CGFloat(spriteH) * 0.062 + 6
        switch self.skin {
        case .dafeiyu: self.winW = CGFloat(spriteH) * (503.0 / 620.0) + mx * 2
        case .bigfish: self.winW = CGFloat(spriteH) + mx * 2
        case .classic: self.winW = lib.maxWidth(height: spriteH) + mx * 2
        }
        self.winH = CGFloat(spriteH) + PetView.bubbleH + PetView.margin * 2 + 10
        super.init(frame: NSRect(x: 0, y: 0, width: winW, height: winH))
        self.mode = Mode(rawValue: cfg.mode) ?? .still
        self.bubbleUntil = 0
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    // MARK: 生命周期

    func start() {
        activity.onChange = { [weak self] s in self?.applyStatus(s) }
        activity.start()
        let t = Timer(timeInterval: PetView.tick, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        tickInterval = PetView.tick
    }

    /// 空闲时把定时器降到 30Hz,动起来回到 50Hz。物理/走路路径只在快速模式下跑,
    /// 所以降频不影响陨落与步频。
    func setTickInterval(_ interval: TimeInterval) {
        guard abs(tickInterval - interval) > 0.0005 else { return }
        tickInterval = interval
        timer?.invalidate()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    deinit { timer?.invalidate() }

    override var isFlipped: Bool { false }

    // MARK: 主循环

    func tick() {
        if jumpT > 0 { jumpT = max(0, jumpT - 0.06) }
        // 方向切换与姿势淡化都放慢一档:0.10/tick ≈ 200ms,切上去不“晦”
        if crossT > 0 { crossT = max(0, crossT - 0.10) }
        if actionT > 0 {
            actionT = max(0, actionT - 0.03)
            if actionT == 0 { finishAction() }
        }

        monitorTick()
        if chatPaused { markDirty(now, fast: true); return }
        if dragging { markDirty(now, fast: true); return }
        guard let panel else { return }

        let time = now

        // 交叉淡化与跟随滞后都走同一个 tick,不另起 timer
        if poseFade > 0 { poseFade = max(0, poseFade - 0.10) }
        let ox = panel.frame.minX
        if lastOriginX.isNaN { lastOriginX = ox }
        let dx = ox - lastOriginX
        lastOriginX = ox
        let targetLean = max(-1.2, min(1.2, dx * 0.16))
        lean += (targetLean - lean) * 0.09
        let wantsWalk: CGFloat = (target != nil && !dragging) ? 1 : 0
        walkBlend += (wantsWalk - walkBlend) * 0.08

        if skin == .dafeiyu {
            if time >= nextBlinkAt {
                blinkUntil = time + 0.14
                nextBlinkAt = time + Double.random(in: 3...7)
            }
            if !sleeping, time - lastInteract > 180, target == nil, !dragging, !chatPaused,
               cfg.statusFeedback, currentStatus.kind == .none || currentStatus.kind == .idle {
                sleeping = true
            }
            if target != nil { walkPhase += curSpeed * CGFloat(PetView.tick) / 45 }
        }

        if falling {
            stepPhysics()
            markDirty(time, fast: true)
            return
        }
        if let cur = signCurrent, time >= signEnd {
            _ = cur
            if signQueue.isEmpty {
                signCurrent = nil
            } else {
                signCurrent = signQueue.removeFirst()
                signEnd = time + (signCurrent?.dur ?? 2.6)
            }
        }
        if squash > 0 { squash = max(0, squash - 0.05) }
        if abs(airRotation) > 0.005 { airRotation *= 0.92 } else { airRotation = 0 }
        updateParticles()

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
                walkSpeed = PetView.speed
            }

        case .wander:
            if target == nil && time >= restUntil {
                let f = panel.frame
                let geo = screenFrame(containing: NSPoint(x: f.midX, y: f.midY))
                let loX = geo.minX + 40
                let hiX = max(loX + 1, geo.maxX - f.width - 40)
                let loY = geo.minY + 40
                let hiY = max(loY + 1, geo.maxY - f.height - 40)
                walkSpeed = PetView.speed
                target = NSPoint(x: CGFloat.random(in: loX...hiX) + f.width / 2,
                                 y: CGFloat.random(in: loY...hiY) + f.height / 2)
            }

        case .still:
            if target == nil && time >= nextActionAt {
                performRandomAction(time)
            }
        }

        if let tg = target {
            let f = panel.frame
            let cx = f.midX, cy = f.midY
            let dx = tg.x - cx, dy = tg.y - cy
            let dist = sqrt(dx * dx + dy * dy)
            if dist < 12 {
                target = nil
                setDir(.down, facing: 1)
                if mode == .still {
                    restUntil = time + Double.random(in: 4...9)
                    nextActionAt = time + Double.random(in: 3...8)
                } else {
                    restUntil = time + Double.random(in: 8...18)
                }
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
            if mode != .still, CGFloat.random(in: 0...1) < 0.002, jumpT == 0 { jumpT = 0.5 }
        }

        let wanted: CGFloat = target != nil ? walkSpeed : 0
        curSpeed += (wanted - curSpeed) * 0.3
        // 动起来走 50Hz;静止时 30Hz 并跳过无实质变化的帧
        let moving = target != nil || jumpT > 0 || actionT > 0
            || crossT > 0 || poseFade > 0 || abs(lean) > 0.05
        markDirty(time, fast: moving)
        setTickInterval(moving ? PetView.tick : (1.0 / 30.0))
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

    /// 待机动作调度:大部分时间什么都不做,偶尔看看/想想/溜达一会儿。
    func performRandomAction(_ time: TimeInterval) {
        if Double.random(in: 0...1) < 0.12 {
            startPlaylet()
            nextActionAt = time + 8
            return
        }
        if skin == .dafeiyu, let act = DafeiyuSkin.idleActs.randomElement() {
            stateOverride = act.pose
            overrideUntil = time + act.seconds
            if let text = DafeiyuSkin.shared.line(act.line) {
                let dur = AudioManager.shared.playVoice(act.line)
                bubbleText = text
                bubbleInner = false
                bubbleUntil = time + max(2.4, dur)
                voiceUntil = time + max(0.6, dur)
                lastLine = text
            }
            if let sfx = act.sfx { AudioManager.shared.playSfx(sfx) }
            nextActionAt = time + act.seconds + Double.random(in: 4...10)
            log("action: dafeiyu \(act.pose.rawValue)")
            return
        }
        nextActionAt = time + Double.random(in: 7...16)
        let r = Double.random(in: 0...1)
        switch r {
        case ..<0.22:
            if Double.random(in: 0...1) < 0.5, let line = contextualLine() {
                say(line, priority: false)
            }
            log("action: 发呆")
        case ..<0.42:
            let pick = Int.random(in: 0...2)
            if pick == 0 {
                action = .lookLeft
                setDir(.left, facing: 1)
            } else if pick == 1 {
                action = .lookRight
                setDir(.right, facing: -1)
            } else {
                action = .lookUp
                setDir(.up)
            }
            actionT = 1.3
            actionDur = 1.3
            log("action: 张望 \(pick)")
        case ..<0.58:
            action = .think
            actionT = 2.0
            actionDur = 2.0
            applyActPose(.think, time)
            if Bool.random(), time - lastSpeakAt >= 25 {
                lastSpeakAt = time
                say(pick(Lines.inner), inner: true, priority: false)
            } else {
                say("……", inner: true, priority: false)
            }
            log("action: 思考")
        case ..<0.78:
            log("action: 溜达 \(startStroll() ? "走" : "太近没走")")
        case ..<0.88:
            action = .stretch
            actionT = 1.0
            actionDur = 1.0
            applyActPose(.stretch, time)
            log("action: 伸展")
        case ..<0.95:
            jumpT = 0.5
            log("action: 蹦")
        default:
            action = .sway
            actionT = 1.0
            actionDur = 1.0
            applyActPose(.sway, time)
            log("action: 摇晃")
        }
    }

    /// 原地模式下的小范围散步:只在家附近晃,不跑远。
    @discardableResult
    func startStroll() -> Bool {
        guard let panel else { return false }
        let f = panel.frame
        let geo = screenFrame(containing: NSPoint(x: f.midX, y: f.midY))
        let anchor = homeCenter == .zero ? NSPoint(x: f.midX, y: f.midY) : homeCenter
        let radius: CGFloat = 170
        var tx = anchor.x + CGFloat.random(in: -radius...radius)
        var ty = anchor.y + CGFloat.random(in: -radius * 0.55...radius * 0.55)
        tx = min(max(geo.minX + f.width / 2, tx), geo.maxX - f.width / 2)
        ty = min(max(geo.minY + f.height / 2, ty), geo.maxY - f.height / 2)
        guard hypot(tx - f.midX, ty - f.midY) > 45 else { return false }
        walkSpeed = 170
        target = NSPoint(x: tx, y: ty)
        return true
    }

    /// 动作期间用对应姿势“演”,而不是整只身体摇。
    func applyActPose(_ a: Action, _ time: TimeInterval) {
        guard skin == .dafeiyu else { return }
        let pose: DState
        switch a {
        case .think: pose = .think
        case .stretch: pose = .wave
        case .sway: pose = .happy
        default: return
        }
        stateOverride = pose
        // actionT 每 tick 减 0.03 而 tick 是 0.02s,动作实际时长是 actionDur / 1.5,姿势不要拖尾
        overrideUntil = time + Double(actionDur) / 1.5
    }

    func finishAction() {
        if let a = action {
            switch a {
            case .lookLeft, .lookRight, .lookUp:
                setDir(.down, facing: 1)
            default:
                break
            }
        }
        action = nil
    }

    // MARK: 台词选择

    /// 从池子里挑一条,避开最近 12 条,减少短期重复。
    func pick(_ pool: [String]) -> String {
        guard !pool.isEmpty else { return "……" }
        let fresh = pool.filter { !recentLines.contains($0) }
        let chosen = (fresh.isEmpty ? pool : fresh).randomElement() ?? "……"
        recentLines.append(chosen)
        if recentLines.count > 12 { recentLines.removeFirst(recentLines.count - 12) }
        return chosen
    }

    func contextualLine() -> String? {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 0..<5: return pick(Lines.lateNight)
        case 5..<11: return pick(Lines.morning)
        case 11..<14: return pick(Lines.noon)
        case 17..<20: return pick(Lines.evening)
        case 22..<24: return pick(Lines.night)
        default: return nil
        }
    }

    func greet() {
        lastInteract = now
        if skin == .dafeiyu {
            stateOverride = .wave
            overrideUntil = now + 2.2
            speak("greet", priority: false)
            return
        }
        say(contextualLine() ?? pick(Lines.idle), priority: false)
    }

    // MARK: dafeiyu 语音

    func applyStatus(_ s: ActivityMonitor.Status) {
        guard cfg.statusFeedback else { return }
        currentStatus = s
        needsDisplay = true
        guard s.kind != .none, s.kind != .idle, now - lastStatusSpeak > 30 else { return }
        lastStatusSpeak = now
        let text: String
        switch s.kind {
        case .thinking: text = s.source == "DSH" ? "在想\(s.detail)的活…" : "在想事情…"
        case .tool: text = "在敲命令"
        case .building: text = "编译中,别催"
        case .testing: text = "在跑测试"
        case .running: text = "手上有点活"
        case .coding: text = "写代码呢"
        default: text = ""
        }
        if !text.isEmpty { say(text, priority: false) }
        log("activity: \(s.kind.rawValue) \(s.detail) [\(s.source)]")
    }

    func speak(_ group: String, priority: Bool = true) {
        guard skin == .dafeiyu,
              let id = DafeiyuSkin.shared.pickVoice(group),
              let text = DafeiyuSkin.shared.line(id) else { return }
        speakLine(id, text: text, priority: priority)
    }

    func speakLine(_ id: String, text: String? = nil, priority: Bool = true) {
        let line = text ?? DafeiyuSkin.shared.line(id) ?? ""
        guard !line.isEmpty else { return }
        let t = now
        // 自动台词遇到用户气泡就让路,不要把它盖掉
        if !priority, t < bubbleProtectedUntil {
            log("speak: suppressed auto \(id)")
            return
        }
        let dur = AudioManager.shared.playVoice(id)
        bubbleText = line
        bubbleInner = false
        bubbleUntil = t + max(2.4, dur)
        if priority { bubbleProtectedUntil = bubbleUntil + 0.3 }
        voiceUntil = t + max(0.6, dur)
        lastLine = line
        lastInteract = t
        needsDisplay = true
    }

    // MARK: 说话

    func say(_ text: String, inner: Bool = false, priority: Bool = true) {
        let t = now
        // 自动台词遇到用户气泡就让路,不要把它盖掉
        if !priority, t < bubbleProtectedUntil {
            log("say: suppressed auto line")
            return
        }
        guard text != lastLine else { return }
        lastLine = text
        bubbleInner = inner
        bubbleText = inner ? "(\(text))" : text
        bubbleUntil = t + (priority ? 3.2 : 2.8)
        if priority { bubbleProtectedUntil = bubbleUntil + 0.3 }
        log("say: \(bubbleText)")
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
        // 先读磁盘再合并,避免把外部编辑过的配置(城市/阈值等)用内存旧值覆盖
        var fresh = Config.load()
        fresh.x = Double(f.minX)
        fresh.y = Double(f.minY)
        fresh.save()
        cfg = fresh
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
        let newH = PetView.displayHeight(skin: skin, size: mult)
        spriteH = newH
        let mx = CGFloat(newH) * 0.062 + 6
        switch skin {
        case .dafeiyu: winW = CGFloat(newH) * (503.0 / 620.0) + mx * 2
        case .bigfish: winW = CGFloat(newH) + mx * 2
        case .classic: winW = lib.maxWidth(height: newH) + mx * 2
        }
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

    // MARK: 动效层(B 路线:一个时钟、不停死、不瞬跳)

    /// 动作进度 0→1,actionT 走完时正好到 1。
    func actionProgress() -> CGFloat {
        guard actionDur > 0 else { return 0 }
        return min(1, max(0, 1 - actionT / actionDur))
    }

    /// 动作包络:进场 16%、出场 22% 淡入淡出,起止都不"停死"。
    func actionEnvelope() -> CGFloat {
        guard action != nil, actionDur > 0 else { return 0 }
        let p = actionProgress()
        let w = min(min(1, p / 0.16), min(1, (1 - p) / 0.22))
        return w * w * (3 - 2 * w)
    }

    /// 量化到像素级:避免亚像素插值带来的单帧成本。
    func snap(_ v: CGFloat, _ step: CGFloat) -> CGFloat { (v / step).rounded() * step }
    func snappedAngle(_ deg: CGFloat) -> CGFloat { snap(deg, 0.05) }

    /// 空闲 30Hz、动起来 50Hz;并跳过"量化后没有变化"的帧。
    func markDirty(_ time: TimeInterval, fast: Bool) {
        let minInterval = fast ? PetView.tick : (1.0 / 30.0)
        guard time - lastDrawAt >= minInterval else { return }
        if !fast {
            let sig = redrawSignature(time)
            if sig == lastDrawSig { return }
            lastDrawSig = sig
        }
        lastDrawAt = time
        needsDisplay = true
    }

    /// 把会变的量量化成一个签名:变化不够大就不重画。
    func redrawSignature(_ time: TimeInterval) -> Int {
        var h = 17
        func mix(_ v: Int) { h = h &* 31 &+ v }
        mix(Int((idleSway(time) * 100).rounded()))
        mix(Int((idleBob(time) * 10).rounded()))
        mix(Int(((idleBreath(time) - 1) * 10000).rounded()))
        mix(Int((fsin(time * 5.5) * 100).rounded()))
        mix(Int((fsin(time * 3.6) * 100).rounded()))
        mix(time < blinkUntil ? 1 : 0)
        mix(Int((actionT * 200).rounded()))
        mix(Int((jumpT * 200).rounded()))
        mix(Int((poseFade * 100).rounded()))
        mix(Int((crossT * 100).rounded()))
        mix(Int((squash * 100).rounded()))
        mix(Int((walkBlend * 100).rounded()))
        mix(Int((lean * 100).rounded()))
        return h
    }

    /// 走路摆幅与待机摆幅按 walkBlend 交叉相乘,避免起步/停下时相位突跳。
    func blendedSway(_ time: TimeInterval, walkAmp: CGFloat) -> CGFloat {
        let idle = idleSway(time) * (1 - actionEnvelope())
        let walk = fsin(time * 5.5) * walkAmp
        return idle + (walk - idle) * walkBlend
    }

    func blendedBob(_ time: TimeInterval, walkAmp: CGFloat) -> CGFloat {
        let idle = idleBob(time) * (1 - actionEnvelope() * 0.5)
        let walk = -abs(fsin(time * 3.6)) * walkAmp
        return idle + (walk - idle) * walkBlend
    }

    /// 永不停的待机生命:幅度极小,相位互相错开,避免"整机同步"。
    func idleSway(_ time: TimeInterval) -> CGFloat { 0.32 * fsin(time * 0.52 + 0.4) }
    func idleBob(_ time: TimeInterval) -> CGFloat { 1.6 * fsin(time * 1.05 + 1.3) }
    func idleBreath(_ time: TimeInterval) -> CGFloat { 1.0 + 0.007 * fsin(time * 0.9 + 0.6) }

    // MARK: 绘制

    override func draw(_ dirtyRect: NSRect) {
        if ProcessInfo.processInfo.environment["DAFEIYU_PERF"] != nil {
            perfDraws += 1
            let t = now
            if perfLastAt == 0 { perfLastAt = t }
            if t - perfLastAt >= 5 {
                let walking = target != nil
                FileHandle.standardError.write(
                    "PERF draws=\(perfDraws) in \(String(format: "%.1f", t - perfLastAt))s walking=\(walking) action=\(action != nil) jump=\(jumpT > 0)\n"
                        .data(using: .utf8)!)
                perfDraws = 0
                perfLastAt = t
            }
        }
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setShouldAntialias(true)
        ctx.interpolationQuality = .high

        let time = now
        if !bubbleText.isEmpty && time < bubbleUntil { drawBubble() }

        if skin == .bigfish {
            drawBigfish(ctx, time)
            return
        }
        if skin == .dafeiyu {
            drawDafeiyu(ctx, time)
            return
        }

        let env = actionEnvelope()
        // 动作期间底噪让位给姿势表演;走/停由 walkBlend 渐变
        let sway = blendedSway(time, walkAmp: 1.8)
        let bob = blendedBob(time, walkAmp: 5.0)
        let breath = idleBreath(time)
        let jump: CGFloat = jumpT > 0 ? -abs(fsin(jumpT * .pi)) * 14 * jumpT : 0

        var actRot: CGFloat = 0
        var actSX: CGFloat = 0
        var actSY: CGFloat = 0
        if action == .think {
            actRot = 2.5 * env
        } else if action == .stretch {
            actSY = 0.06 * fsin(actionProgress() * .pi) * env
            actSX = -0.03 * fsin(actionProgress() * .pi) * env
        } else if action == .sway {
            // “摇晃”不再整只横摇,改成两下轻微的呼吸式起伏
            let p = fsin(actionProgress() * .pi * 2) * env
            actSY = 0.025 * p
            actSX = -0.015 * p
        }

        let bottom = PetView.margin + CGFloat(spriteH)

        func drawOne(_ d: Dir, _ f: CGFloat, alpha: CGFloat) {
            guard let img = spriteImage(d, f) else { return }
            let ph = (img.size.height * breath * (1 + actSY)).rounded()
            let pw = (img.size.width * breath * (1 + actSX)).rounded()
            ctx.saveGState()
            ctx.setAlpha(alpha)
            ctx.translateBy(x: bounds.midX.rounded(), y: bottom)
            ctx.rotate(by: snappedAngle(sway + actRot + airRotation + lean) * .pi / 180)
            ctx.scaleBy(x: 1 + 0.18 * squash, y: 1 - 0.22 * squash)
            if f < 0 { ctx.scaleBy(x: -1, y: 1) }
            let rect = CGRect(x: (-pw / 2).rounded(), y: (-ph + jump + snap(bob, 0.5)).rounded(),
                              width: pw, height: ph)
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

    // MARK: 物理

    func stepPhysics() {
        guard let panel else { return }
        let dt = CGFloat(PetView.tick)
        let f = panel.frame
        let geo = screenFrame(containing: NSPoint(x: f.midX, y: f.midY))

        velocity.y -= 2200 * dt                      // 重力
        var nx = f.minX + velocity.x * dt
        var ny = f.minY + velocity.y * dt

        if nx < geo.minX { nx = geo.minX; velocity.x = -velocity.x * 0.45 }
        if nx + f.width > geo.maxX { nx = geo.maxX - f.width; velocity.x = -velocity.x * 0.45 }
        if ny + f.height > geo.maxY { ny = geo.maxY - f.height; velocity.y = -velocity.y * 0.45 }

        if ny <= geo.minY {
            ny = geo.minY
            let impact = abs(velocity.y)
            if impact > 520 {
                velocity.y = impact * 0.32
                squash = min(1, impact / 1200)
                spawnParticles(intensity: impact)
                AudioManager.shared.playSfx("splash")
                log("physics: bounce impact=\(Int(impact))")
            } else {
                velocity = .zero
                falling = false
                squash = min(0.9, impact / 900)
                if impact > 120 { AudioManager.shared.playSfx("pop") }
                homeCenter = NSPoint(x: nx + f.width / 2, y: ny + f.height / 2)
                nextActionAt = now + 2
                savePos()
                log("physics: landed impact=\(Int(impact)) at \(Int(nx)),\(Int(ny))")
            }
        }

        panel.setFrameOrigin(NSPoint(x: nx, y: ny))
        airRotation = max(-0.38, min(0.38, velocity.x / 2600))
    }

    func spawnParticles(intensity: CGFloat) {
        let n = Int(min(18, 6 + intensity / 120))
        for _ in 0..<n {
            let angle = CGFloat.random(in: (.pi * 0.15)...(.pi * 0.85))
            let speed = CGFloat.random(in: 90...320) * (intensity / 600)
            let life = CGFloat.random(in: 0.35...0.7)
            let colors: [NSColor] = [
                NSColor(calibratedRed: 1, green: 0.84, blue: 0.4, alpha: 1),
                NSColor(calibratedRed: 1, green: 0.62, blue: 0.78, alpha: 1),
                .white,
            ]
            particles.append(Particle(
                p: CGPoint(x: bounds.midX + CGFloat.random(in: -18...18), y: PetView.margin + 6),
                v: CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed),
                life: life, maxLife: life,
                size: CGFloat.random(in: 2...5),
                color: colors.randomElement() ?? .white
            ))
        }
    }

    func updateParticles() {
        guard !particles.isEmpty else { return }
        let dt = CGFloat(PetView.tick)
        for i in particles.indices {
            particles[i].p.x += particles[i].v.dx * dt
            particles[i].p.y += particles[i].v.dy * dt
            particles[i].v.dy -= 900 * dt
            particles[i].life -= dt
        }
        particles.removeAll { $0.life <= 0 }
    }

    func drawParticles() {
        for p in particles {
            let a = max(0, p.life / p.maxLife)
            p.color.withAlphaComponent(a).setFill()
            let r = NSRect(x: p.p.x - p.size / 2, y: p.p.y - p.size / 2, width: p.size, height: p.size)
            NSBezierPath(ovalIn: r).fill()
        }
    }

    func debugThrow() {
        velocity = CGPoint(x: 700, y: 900)
        falling = true
        log("physics: throw from \(Int(panel?.frame.minX ?? 0)),\(Int(panel?.frame.minY ?? 0))")
    }

    func bigfishAnim(_ time: TimeInterval) -> String {
        if falling || dragging { return "panic" }
        if time < voiceUntil { return "confirm" }
        switch currentStatus.kind {
        case .thinking, .tool, .testing, .building, .running: return "type"
        default: break
        }
        if signCurrent != nil || signPreview != nil { return "sign" }
        if let a = action {
            switch a {
            case .stretch: return "confirm"   // 原来是 wave:那组帧是大甩尾,伸展用安静的点头就好
            case .think: return "type"
            default: break
            }
        }
        if jumpT > 0 { return "celebrate" }
        if let cur = signCurrent, cur.text.isEmpty { return "sign" }
        return "breathe"
    }

    func drawBigfish(_ ctx: CGContext, _ time: TimeInterval) {
        guard let img = BigfishSkin.shared.frame(bigfishAnim(time), at: time) else { return }
        let h = CGFloat(spriteH)
        let w = h * CGFloat(img.width) / CGFloat(img.height)

        let sway = blendedSway(time, walkAmp: 1.0)
        let jump: CGFloat = jumpT > 0 ? -abs(fsin(jumpT * .pi)) * 14 * jumpT : 0

        let wantLeft: Bool
        switch dir {
        case .left: wantLeft = true
        case .right: wantLeft = false
        case .up, .down: wantLeft = true
        }

        ctx.saveGState()
        ctx.translateBy(x: bounds.midX.rounded(), y: PetView.margin)
        ctx.rotate(by: snappedAngle(sway + airRotation + lean) * .pi / 180)
        ctx.scaleBy(x: 1 + 0.18 * squash, y: 1 - 0.22 * squash)
        if wantLeft { ctx.scaleBy(x: -1, y: 1) }
        let dw = w.rounded(), dh = h.rounded()
        ctx.draw(img, in: CGRect(x: (-dw / 2).rounded(),
                                 y: (jump + snap(idleBob(time) * 0.6, 0.5)).rounded(),
                                 width: dw, height: dh))
        ctx.restoreGState()

        drawParticles()
        drawSignIfNeeded()
    }

    func currentDState(_ time: TimeInterval) -> DState {
        if let s = stateOverride, time < overrideUntil { return s }
        if cfg.statusFeedback {
            switch currentStatus.kind {
            case .thinking, .testing: return .think
            case .tool, .building: return .cheer
            case .running: return .basin
            default: break
            }
        }
        if falling { return .surprise }
        if dragging { return .surprise }
        if time < voiceUntil { return .talk }
        if sleeping { return .sleep }
        // 眨眼提到走路之前:否则走路时永远眨不了眼
        if time < blinkUntil { return .blink }
        // 蹦的那一下用 cheer 姿势,比拿 idle 图平移更像“动作”
        if jumpT > 0 { return .cheer }
        if target != nil {
            switch Int(walkPhase) % 4 {
            case 0: return .walk1
            case 1: return .walkpass
            case 2: return .walk2
            default: return .walkpass
            }
        }
        return .idle
    }

    func drawDafeiyu(_ ctx: CGContext, _ time: TimeInterval) {
        let state = currentDState(time)
        updatePoseCrossFade(state)

        let env = actionEnvelope()
        let sway = blendedSway(time, walkAmp: 1.1)
        let bob = blendedBob(time, walkAmp: 4.0)
        let breath = idleBreath(time)
        let jump: CGFloat = jumpT > 0 ? -abs(fsin(jumpT * .pi)) * 14 * jumpT : 0

        var actRot: CGFloat = 0
        var actSX: CGFloat = 0
        var actSY: CGFloat = 0
        if action == .think { actRot = 2.5 * env }
        if action == .stretch {
            actSY = 0.06 * fsin(actionProgress() * .pi) * env
            actSX = -0.03 * fsin(actionProgress() * .pi) * env
        }
        if action == .sway {
            // 不再整只横摇,改成两下呼吸式起伏
            let p = fsin(actionProgress() * .pi * 2) * env
            actSY = 0.025 * p
            actSX = -0.015 * p
        }

        let fade = poseFade > 0 ? poseFade * poseFade * (3 - 2 * poseFade) : 0
        if poseFade > 0, let from = poseFadeFrom, from != state {
            drawDafeiyuPose(ctx, from, alpha: fade, sway: sway, bob: bob, jump: jump,
                            breath: breath, actRot: actRot, actSX: actSX, actSY: actSY)
        }
        drawDafeiyuPose(ctx, state, alpha: poseFade > 0 ? 1 - fade : 1, sway: sway, bob: bob,
                        jump: jump, breath: breath, actRot: actRot, actSX: actSX, actSY: actSY)
        drawParticles()
        drawSignIfNeeded()
    }

    /// 只有跨"姿势家族"时才淡化;步行循环内部仍然硬切,否则会重影。
    func updatePoseCrossFade(_ state: DState) {
        guard let shown = poseShown else { poseShown = state; return }
        if shown == state { return }
        if poseFamily(shown) != poseFamily(state) {
            poseFadeFrom = shown
            poseFade = 1
        }
        poseShown = state
    }

    func poseFamily(_ s: DState) -> Int {
        switch s {
        case .walk1, .walkpass, .walk2: return 1
        case .idle, .blink: return 2
        default: return 3
        }
    }

    func drawDafeiyuPose(_ ctx: CGContext, _ state: DState, alpha: CGFloat,
                         sway: CGFloat, bob: CGFloat, jump: CGFloat, breath: CGFloat,
                         actRot: CGFloat, actSX: CGFloat, actSY: CGFloat) {
        guard alpha > 0.01, let img = DafeiyuSkin.shared.image(state) else { return }
        let h = (CGFloat(spriteH) * breath * (1 + actSY)).rounded()
        let w = (h * (img.size.width / img.size.height) * (1 + actSX)).rounded()

        let wantLeft: Bool
        switch dir {
        case .left: wantLeft = true
        case .right: wantLeft = false
        case .up, .down: wantLeft = true
        }
        let flip = wantLeft != DafeiyuSkin.shared.facesLeft(state)

        ctx.saveGState()
        ctx.translateBy(x: bounds.midX.rounded(), y: PetView.margin)
        ctx.rotate(by: snappedAngle(sway + actRot + airRotation + lean) * .pi / 180)
        ctx.scaleBy(x: 1 + 0.18 * squash, y: 1 - 0.22 * squash)
        if flip { ctx.scaleBy(x: -1, y: 1) }
        img.draw(in: CGRect(x: (-w / 2).rounded(), y: (jump + snap(bob, 0.5)).rounded(),
                            width: w, height: h),
                 from: .zero, operation: .sourceOver, fraction: alpha)
        ctx.restoreGState()
    }

    func drawSignIfNeeded() {
        if let preview = signPreview {
            drawSign(preview)
        } else if let cur = signCurrent {
            drawSign(cur.text)
        }
    }

    func drawSign(_ text: String) {
        let font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let w = min(bounds.width - 16, (text as NSString).size(withAttributes: [.font: font]).width + 26)
        let h: CGFloat = 38
        let cx = bounds.midX
        let top = PetView.margin + CGFloat(spriteH) + 4
        let rect = NSRect(x: cx - w / 2, y: top, width: w, height: h)

        if rect.maxY > bounds.maxY - 2 { return }

        // 木棍
        let stick = NSBezierPath()
        stick.move(to: NSPoint(x: cx + w / 2 - 8, y: rect.minY + 2))
        stick.line(to: NSPoint(x: cx + w / 2 - 18, y: rect.minY - 14))
        stick.lineWidth = 3
        stick.lineCapStyle = .round
        NSColor(calibratedRed: 0.60, green: 0.42, blue: 0.26, alpha: 1).setStroke()
        stick.stroke()

        // 牌面
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        NSColor(calibratedRed: 1.0, green: 0.94, blue: 0.74, alpha: 0.98).setFill()
        path.fill()
        NSColor(calibratedRed: 0.84, green: 0.68, blue: 0.34, alpha: 1).setStroke()
        path.lineWidth = 2
        path.stroke()

        // 字
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(calibratedRed: 0.26, green: 0.20, blue: 0.13, alpha: 1),
            .paragraphStyle: para,
        ]
        (text as NSString).draw(in: NSRect(x: rect.minX + 4, y: rect.midY - 9,
                                           width: rect.width - 8, height: 20),
                                withAttributes: attrs)
    }

    /// 一段 2–3 张牌的短剧。
    func startPlaylet() {
        let scripts: [[String]] = [
            ["需求再改我就倒立", "算了,倒立也不会"],
            ["今天必须早睡", "……再写五分钟"],
            ["这个 bug 我见过", "在梦里"],
            ["编译通过了", "但我没改代码"],
            ["摸鱼是工作的一部分", "鱼说的"],
            ["我不是胖", "我是圆"],
            ["余额还有一点", "够吃几顿白饭"],
        ]
        guard let script = scripts.randomElement(), !script.isEmpty else { return }
        signCurrent = SignLine(text: script[0], dur: 2.8)
        signQueue = script.dropFirst().map { SignLine(text: $0, dur: 2.8) }
        signEnd = now + 2.8
        if skin == .dafeiyu {
            stateOverride = .happy
            overrideUntil = now + 1.6
        }
        AudioManager.shared.playSfx("pop")
        needsDisplay = true
        log("playlet: \(script.joined(separator: " / "))")
    }

    func drawBubble() {
        let inner = bubbleInner
        let base = NSFont.systemFont(ofSize: 12)
        let font: NSFont = inner ? (NSFontManager.shared.convert(base, toHaveTrait: .italicFontMask)) : base
        let fg: NSColor = inner ? Theme.dim : Theme.title
        let bg: NSColor = inner ? NSColor(calibratedRed: 232 / 255, green: 232 / 255, blue: 238 / 255, alpha: 0.94)
                               : Theme.surface

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
        // 气泡尾巴锚定在头顶上方,间距按大小模式自适应
        let tailGap = max(6, CGFloat(spriteH) * 0.04)
        let bx = (bounds.width - bw) / 2
        var by = PetView.margin + CGFloat(spriteH) + tailGap + 8
        by = min(by, bounds.maxY - 4 - bh)

        bg.setFill()
        let path = NSBezierPath(roundedRect: NSRect(x: bx, y: by, width: bw, height: bh),
                                xRadius: Theme.radius, yRadius: Theme.radius)
        path.fill()

        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: bounds.midX, y: by))
        tail.line(to: NSPoint(x: bounds.midX - 6, y: by - 8))
        tail.line(to: NSPoint(x: bounds.midX + 6, y: by - 8))
        tail.close()
        tail.fill()

        // 描边和举牌一致(金棕 2pt);先填尾巴再描边,接口不会断
        Theme.stroke.setStroke()
        path.lineWidth = Theme.strokeWidth
        path.stroke()

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
        lastInteract = now
        falling = false
        velocity = .zero
        dragSamples.removeAll()
        if sleeping {
            sleeping = false
            speakLine("wake1")
            stateOverride = .surprise
            overrideUntil = now + 1.2
        }
        if event.clickCount == 2 {
            suppressClick = true
            if let f = panel?.frame { feedBar.show(above: f) }
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
        dragSamples.append((t: now, x: m.x, y: m.y))
        if dragSamples.count > 10 { dragSamples.removeFirst(dragSamples.count - 10) }
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
            if skin == .dafeiyu {
                stateOverride = .surprise
                overrideUntil = now + 0.9
                speak("drag")
            } else if Bool.random() {
                say(pick(Lines.drag))
            }
            let t = now
            let recent = dragSamples.filter { t - $0.t <= 0.12 }
            if recent.count >= 2, let a = recent.first, let b = recent.last {
                let dt = max(0.016, b.t - a.t)
                velocity = CGPoint(x: min(3000, max(-3000, (b.x - a.x) / dt)),
                                   y: min(3000, max(-3000, (b.y - a.y) / dt)))
            } else {
                velocity = .zero
            }
            dragSamples.removeAll()
            falling = true
            log("physics: release v=\(Int(velocity.x)),\(Int(velocity.y))")
        } else {
            if skin == .dafeiyu {
                let t = now
                if t - pokeStartedAt > 2.0 { pokeCount = 0; pokeStartedAt = t }
                pokeCount += 1
                if pokeCount >= 3 {
                    pokeCount = 0
                    stateOverride = .angry
                    overrideUntil = t + 1.8
                    speakLine("angry1")
                } else {
                    stateOverride = .happy
                    overrideUntil = t + 0.9
                    speak("click")
                }
            } else {
                if CGFloat.random(in: 0...1) < 0.7 { jumpT = 1.0 }
                if CGFloat.random(in: 0...1) < 0.6 { say(pick(Lines.react)) }
            }
            if let f = panel?.frame { functionBar.showAutoHide(above: f) }
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

    func feed(_ emoji: String) {
        jumpT = 0.6
        lastInteract = now
        if skin == .dafeiyu {
            stateOverride = .eat
            overrideUntil = now + 3.2
            speakLine("eat1")
            AudioManager.shared.playSfx("clang")
            return
        }
        let pool = Lines.foodLines[emoji] ?? ["好吃！"]
        say(pick(pool))
    }

    func toggleVisible() {
        guard let p = panel else { return }
        if p.isVisible {
            p.orderOut(nil)
        } else {
            p.orderFrontRegardless()
        }
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

        let skinMenu = NSMenu()
        for (label, key) in [("大肥鱼 · 18 状态", "dafeiyu"),
                            ("bigfish · 图集动画", "bigfish"),
                            ("经典三视图", "classic")] {
            addCheck(skinMenu, label, cfg.skin == key, #selector(menuSetSkin(_:)), key)
        }
        let skinItem = NSMenuItem(title: "皮肤", action: nil, keyEquivalent: "")
        skinItem.submenu = skinMenu
        menu.addItem(skinItem)

        let audioMenu = NSMenu()
        addCheck(audioMenu, "静音(全部声音)", cfg.muted, #selector(menuToggleMute))
        audioMenu.addItem(NSMenuItem.separator())
        addCheck(audioMenu, "语音", cfg.voiceEnabled, #selector(menuToggleVoice))
        addCheck(audioMenu, "音效", cfg.sfxEnabled, #selector(menuToggleSfx))
        addCheck(audioMenu, "背景音乐", cfg.bgmEnabled, #selector(menuToggleBGM))
        let audioItem = NSMenuItem(title: "声音", action: nil, keyEquivalent: "")
        audioItem.submenu = audioMenu
        menu.addItem(audioItem)

        let statusLine = NSMenuItem(title: "状态: \(statusText())", action: nil, keyEquivalent: "")
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        addCheck(menu, "任务状态反馈", cfg.statusFeedback, #selector(menuToggleStatus))

        menu.addItem(NSMenuItem.separator())
        addCheck(menu, "鼠标穿透(点不到它)", cfg.passthrough, #selector(menuTogglePassthrough))
        addCheck(menu, "窗口置顶", cfg.topmost, #selector(menuToggleTopmost))
        addCheck(menu, "开机自启", cfg.autostart, #selector(menuToggleAutostart))
        menu.addItem(NSMenuItem.separator())

        let clearHistoryItem = NSMenuItem(title: "清空聊天记忆", action: #selector(menuClearHistory), keyEquivalent: "")
        clearHistoryItem.target = self
        menu.addItem(clearHistoryItem)

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

        let playletItem = NSMenuItem(title: "演一段", action: #selector(menuPlaylet), keyEquivalent: "")
        playletItem.target = self
        menu.addItem(playletItem)

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
        if let f = panel?.frame { homeCenter = NSPoint(x: f.midX, y: f.midY) }
        nextActionAt = now + 2
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

    @objc func menuClearHistory() {
        chat?.clearHistory()
        say("记忆清空了")
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

        let stack = NSStackView(frame: NSRect(x: 0, y: 0, width: 340, height: 196))
        stack.orientation = .vertical
        stack.spacing = 8

        let urlField = NSTextField(string: cfg.baseURL)
        let modelField = NSTextField(string: cfg.model)
        let keyField = NSSecureTextField(string: Keychain.read(account: "api-key") ?? "")
        let cityField = NSTextField(string: cfg.city)
        cityField.placeholderString = "留空=按 IP 自动定位"
        let dsKeyField = NSSecureTextField(string: Keychain.read(account: "deepseek-key") ?? "")
        dsKeyField.placeholderString = "留空=读本机网关 .env"
        let thresholdField = NSTextField(string: String(format: "%.0f", cfg.lowBalanceThreshold))
        thresholdField.placeholderString = "低于这个金额提醒,0=关闭"

        for (label, field) in [("Base URL", urlField), ("模型", modelField), ("API Key", keyField),
                               ("DS Key", dsKeyField), ("城市", cityField), ("余额提醒", thresholdField)] {
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
            newCfg.lowBalanceThreshold = max(0, Double(thresholdField.stringValue) ?? 20)
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

    @objc func menuPlaylet() {
        startPlaylet()
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

    @objc func menuSetSkin(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let s = Skin(rawValue: raw) else { return }
        cfg.skin = raw
        cfg.save()
        skin = s
        applySize(cfg.size)
        if s == .bigfish {
            say("bigfish 图集模式")
        } else if s == .dafeiyu {
            stateOverride = .wave
            overrideUntil = now + 1.6
            speak("greet")
        } else {
            say("换回三视图了")
        }
    }

    func statusText() -> String {
        let name = currentStatus.kind.rawValue
        let zh: [String: String] = [
            "none": "空闲", "thinking": "思考中", "tool": "跑工具", "building": "编译中",
            "testing": "测试中", "running": "运行任务", "coding": "写代码", "browsing": "浏览",
            "idle": "没人在",
        ]
        let label = zh[name] ?? name
        return currentStatus.detail.isEmpty ? label : "\(label) · \(currentStatus.detail)"
    }

    @objc func menuToggleMute() {
        cfg.muted.toggle()
        cfg.save()
        if cfg.muted {
            AudioManager.shared.stopVoice()
            AudioManager.shared.stopBGM()
            say("静音了,世界清净")
        } else {
            AudioManager.shared.applyBGMPreference()
            say("声音回来了")
        }
    }

    @objc func menuToggleStatus() {
        cfg.statusFeedback.toggle()
        cfg.save()
        say(cfg.statusFeedback ? "开始盯着你干活了" : "那我就不看了")
    }

    @objc func menuToggleVoice() {
        cfg.voiceEnabled.toggle()
        cfg.save()
        if !cfg.voiceEnabled { AudioManager.shared.stopVoice() }
        say(cfg.voiceEnabled ? "语音开了" : "语音关了")
    }

    @objc func menuToggleSfx() {
        cfg.sfxEnabled.toggle()
        cfg.save()
        say(cfg.sfxEnabled ? "音效开了" : "音效关了")
    }

    @objc func menuToggleBGM() {
        cfg.bgmEnabled.toggle()
        cfg.save()
        AudioManager.shared.applyBGMPreference()
        say(cfg.bgmEnabled ? "放首歌" : "先安静一会儿")
    }

    @objc func menuSay() {
        say(pick(Lines.idle))
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
