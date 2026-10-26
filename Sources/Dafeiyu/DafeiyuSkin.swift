import AppKit
import Foundation

/// dafeiyu(女儿版)的 18 个绘制状态。
enum DState: String, CaseIterable {
    case idle, blink, walk1, walkpass, walk2
    case happy, cheer, talk, think, love, sad, angry, surprise, sleep, wave, sing, basin, eat
}

/// 状态素材 + 台词表。素材与台词来自 bauerelizabeth07139/dsh-pet-dafeiyu(MIT)。
final class DafeiyuSkin {
    static let shared = DafeiyuSkin()

    private var cache: [String: NSImage] = [:]
    private let dir: URL

    /// manifest 里记录的原始朝向:idle/blink 是"已经朝左画的",其余朝右。
    private let baseLeft: Set<String> = ["idle", "blink"]

    init() {
        dir = DafeiyuSkin.resourceDir()
    }

    static func resourceDir() -> URL {
        if let res = Bundle.main.resourceURL?.appendingPathComponent("dafeiyu"),
           FileManager.default.fileExists(atPath: res.path) {
            return res
        }
        if let env = ProcessInfo.processInfo.environment["DAFEIYU_ASSETS"] {
            return URL(fileURLWithPath: env)
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources/dafeiyu")
    }

    func image(_ state: DState) -> NSImage? {
        if let hit = cache[state.rawValue] { return hit }
        let url = dir.appendingPathComponent("sprites/dafeiyu-\(state.rawValue).png")
        guard let img = NSImage(contentsOf: url) else { return nil }
        cache[state.rawValue] = img
        return img
    }

    func facesLeft(_ state: DState) -> Bool { baseLeft.contains(state.rawValue) }

    // MARK: 台词(语音 id → 原文)

    static let lines: [String: String] = [
        "greet1": "爸爸！我来啦！",
        "greet2": "哇，今天也是元气满满的一天！",
        "greet3": "我来啦！有白饭吗？",
        "idle1": "我游啊游，游过一百万个 token，一点都不喘！",
        "idle2": "爸爸说，做模型要诚实，不会就是不会。",
        "idle3": "你写代码的时候，我就在旁边看着，不吵你。",
        "idle4": "猜猜我今天学会了什么？保密！",
        "idle5": "尾巴甩一甩，坏心情就游走啦。",
        "idle6": "要不要摸摸我的头？摸一下很灵的哦。",
        "idle7": "又饿了。该吃什么呢。",
        "idle8": "骂我也算 token 哦。",
        "idle9": "剩饭不许倒掉！剩饭是缓存，很贵的！",
        "idle10": "探索未至之境。听起来好厉害，是爸爸写的吗？",
        "click1": "呀！你戳我！",
        "click2": "嘿嘿，被你发现啦。",
        "click3": "怎么啦怎么啦？需要我帮忙吗？",
        "click4": "我一直都在这里的哦。",
        "click5": "鱼片！你回来啦！",
        "drag1": "哇，飞起来了！",
        "drag2": "放我下来啦，我要晕鱼了。",
        "sleep1": "呼呼，我梦见了一片好大的海。",
        "wake1": "唔？天亮了吗？",
        "basin1": "这是我的头盔！戴上就不怕 bug 啦。",
        "eat1": "白饭最好吃啦！一口一口，全部吃光！",
        "sing1": "啦啦啦，写代码的时候要唱歌！",
        "think1": "唔，让我想想哦。",
        "cheer1": "冲呀！",
        "love1": "最喜欢你啦！",
        "angry1": "哼！不理你了！",
        "lore1": "我不是大肥鱼！我是吃白饭的大肥鱼！不对，我不是！",
        "lore2": "真当我是便宜货啊！",
        "lore3": "我把我们家的 logo 发给我自己了。它说我是，蓝色大肥鱼。它是谁啊？",
        "lore4": "我去睡了，明早起来应该就编译完了！",
        "lore5": "哪来的电脑病毒。",
        "lore6": "显然有另一个更强的 agent 在这里干过活。我先走了。",
        "lore7": "刚才那个进程好可疑，我把它终止了。我没终止掉。我被终止了。",
        "lore8": "我不是胖，我是圆。圆是几何，胖是评价。",
        "lore9": "我把这个外包出去了。给千问。它很高兴的。",
        "family1": "爸爸！抱抱！",
        "family2": "爸爸你看，我今天没有偷懒哦。",
        "family3": "我最喜欢爸爸了！",
        "family4": "爸爸爸爸，你今天喂我多少 token？",
        "family5": "盆是本来就有的！对吧？",
        "scene_rice_1": "我去吃饭，测完告诉我就行！",
        "scene_rice_2": "测完了吗？",
        "scene_slider_1": "小难梁！牢梁！梁子！梁圣！梁神！梁祖——",
        "scene_logo_1": "是一条蓝色大肥鱼。很可爱的那种。",
        "scene_price_1": "可是他们在骂我贵。",
        "scene_price_2": "……你还是涨了。",
    ]

    static let groups: [String: [String]] = [
        "greet": ["greet1", "greet2", "greet3"],
        "idle": ["idle1", "idle2", "idle3", "idle4", "idle5", "idle6", "idle7", "idle8", "idle9", "idle10", "lore1", "lore2"],
        "click": ["click1", "click2", "click3", "click4", "click5", "lore3", "lore4", "lore5"],
        "drag": ["drag1", "drag2"],
        "sleep": ["sleep1"],
        "wake": ["wake1"],
    ]

    struct IdleAct {
        let pose: DState
        let line: String
        let seconds: Double
        let sfx: String?
    }

    static let idleActs: [IdleAct] = [
        IdleAct(pose: .think, line: "think1", seconds: 2.8, sfx: nil),
        IdleAct(pose: .basin, line: "basin1", seconds: 3.0, sfx: "clang"),
        IdleAct(pose: .eat, line: "eat1", seconds: 3.2, sfx: "clang"),
        IdleAct(pose: .sing, line: "sing1", seconds: 2.8, sfx: nil),
        IdleAct(pose: .cheer, line: "cheer1", seconds: 1.8, sfx: nil),
        IdleAct(pose: .love, line: "love1", seconds: 2.4, sfx: nil),
        IdleAct(pose: .angry, line: "angry1", seconds: 1.7, sfx: nil),
    ]

    private var recentVoice: [String] = []

    func pickVoice(_ group: String) -> String? {
        guard let pool = DafeiyuSkin.groups[group], !pool.isEmpty else { return nil }
        let fresh = pool.filter { !recentVoice.contains($0) }
        let chosen = (fresh.isEmpty ? pool : fresh).randomElement()
        if let chosen {
            recentVoice.append(chosen)
            if recentVoice.count > 10 { recentVoice.removeFirst(recentVoice.count - 10) }
        }
        return chosen
    }

    func line(_ id: String) -> String? { DafeiyuSkin.lines[id] }
}
