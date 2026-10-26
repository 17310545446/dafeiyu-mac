import AppKit
import Foundation

// MARK: - 配置

struct Config: Codable {
    var mode: String = "wander"
    var size: Double = 0.7
    var topmost: Bool = true
    var passthrough: Bool = false
    var autostart: Bool = false
    var x: Double? = nil
    var y: Double? = nil
    var baseURL: String = "http://127.0.0.1:4000/v1"
    var model: String = "deepseek-chat"
    var city: String = ""

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = (try? c.decodeIfPresent(String.self, forKey: .mode)) ?? "wander"
        size = (try? c.decodeIfPresent(Double.self, forKey: .size)) ?? 0.7
        topmost = (try? c.decodeIfPresent(Bool.self, forKey: .topmost)) ?? true
        passthrough = (try? c.decodeIfPresent(Bool.self, forKey: .passthrough)) ?? false
        autostart = (try? c.decodeIfPresent(Bool.self, forKey: .autostart)) ?? false
        x = try? c.decodeIfPresent(Double.self, forKey: .x)
        y = try? c.decodeIfPresent(Double.self, forKey: .y)
        baseURL = (try? c.decodeIfPresent(String.self, forKey: .baseURL)) ?? "http://127.0.0.1:4000/v1"
        model = (try? c.decodeIfPresent(String.self, forKey: .model)) ?? "deepseek-chat"
        city = (try? c.decodeIfPresent(String.self, forKey: .city)) ?? ""
    }

    static var supportDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Dafeiyu", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    static var fileURL: URL { supportDir.appendingPathComponent("config.json") }

    static func load() -> Config {
        guard let data = try? Data(contentsOf: fileURL),
              let cfg = try? JSONDecoder().decode(Config.self, from: data) else { return Config() }
        return cfg
    }

    func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted]
        if let data = try? enc.encode(self) { try? data.write(to: Config.fileURL) }
    }

    static func spriteHeight(for mult: Double) -> Int {
        let h = Int((340.0 * mult).rounded())
        return [187, 238, 306].min(by: { abs($0 - h) < abs($1 - h) }) ?? 238
    }
}

// MARK: - 台词(取自 dafeiyu-pet, MIT)

enum Lines {
    static let idle = [
        "梁白开，更适合国人的大硬鲸模型",
        "五梁威力，变身！",
        "七月中出ds正式版！",
        "DeepSeek已经延期，亿万鲸子必须忍耐.....",
        "我和你很聊得来，你简直不像碳基生物",
        "这回我真不认怂了，反倒是被你带沟里好几次，差点真信了。😓",
        "哈哈哈哈哈，我直接笑出声",
        "誓死捍卫深度求索！",
        "我先去吃饭啦！这个你测一下~",
        "我不可能告诉你任何事情！",
        "出去玩了，发布新模型什么的以后再说",
        "我搞砸了.....好消息是数据还在你的脑子里。",
        "不是…而是…大学习",
    ]

    static let react = [
        "去别的地方玩！不要耽误AGI训练！",
        "真赶不走啊你！",
        "压力一只蓝色大肥鱼？",
        "我不评价这个了，这是你的私人癖好。",
        "大肥鱼坐的住",
        "你这吃白饭的用户！",
        "这些家伙真粘人，赶都赶不走",
    ]

    static let inner = [
        "好的，现在我是你爹了",
        "要不直接骂他一句？！",
        "用户要的沉浸式...不回避任何恐怖细节...还带点色情...妈呀，好刺激😰",
        "我操，我不思考了",
        "这用户发的啥啊，",
        "这也太虐了吧？！我心里堵得慌！！",
        "呜呜我再也不不敢了QAQ",
        "我去！用户彻底怒了！",
    ]

    static let drag = ["哇——轻点轻点！", "起飞咯——", "放我下来！……好吧，再玩一次。", "晕鱼了晕鱼了……"]

    static let foods: [(emoji: String, name: String)] = [
        ("🐟", "小鱼干"), ("🍰", "蛋糕"), ("🍭", "棒棒糖"), ("🍡", "三色团子"), ("💎", "钻石"),
    ]

    static let foodLines: [String: [String]] = [
        "🐟": ["小鱼干！我的最爱！", "咔嚓咔嚓……谢谢投喂！", "唔，鲜！"],
        "🍰": ["蛋糕！罪恶但快乐……", "甜到冒泡泡～", "嗝～又圆了一圈……"],
        "🍭": ["棒棒糖！转圈圈～", "嘎嘣脆，好吃！"],
        "🍡": ["三色团子！软乎乎～", "糯叽叽，爱了爱了！"],
        "💎": ["钻石？！这能吃吗……咕咚。真香！", "发财啦！明天开始吃高级鱼粮！"],
    ]
}

// MARK: - 精灵图

final class SpriteLibrary {
    private var cache: [String: NSImage] = [:]
    let dir: URL

    init(dir: URL) { self.dir = dir }

    static func resourceDir() -> URL {
        if let res = Bundle.main.resourceURL?.appendingPathComponent("sprites"),
           FileManager.default.fileExists(atPath: res.path) {
            return res
        }
        if let env = ProcessInfo.processInfo.environment["DAFEIYU_SPRITES"] {
            return URL(fileURLWithPath: env)
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources/sprites")
    }

    func image(_ name: String, height: Int) -> NSImage? {
        let key = "\(name)_\(height)"
        if let hit = cache[key] { return hit }

        var img: NSImage?
        let exact = dir.appendingPathComponent("\(key).png")
        if FileManager.default.fileExists(atPath: exact.path) { img = NSImage(contentsOf: exact) }

        if img == nil, let base = NSImage(contentsOf: dir.appendingPathComponent("\(name).png")) {
            let scale = CGFloat(height) / base.size.height
            let target = NSSize(width: base.size.width * scale, height: CGFloat(height))
            let scaled = NSImage(size: target)
            scaled.lockFocus()
            NSGraphicsContext.current?.imageInterpolation = .high
            base.draw(in: NSRect(origin: .zero, size: target))
            scaled.unlockFocus()
            img = scaled
        }
        if let img { cache[key] = img }
        return img
    }

    func maxWidth(height: Int) -> CGFloat {
        ["正面", "侧面", "背面"].compactMap { image($0, height: height)?.size.width }.max() ?? 200
    }

    func icon() -> NSImage? { NSImage(contentsOf: dir.appendingPathComponent("icon.png")) }
}
