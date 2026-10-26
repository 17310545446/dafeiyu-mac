import AppKit
import Foundation

// MARK: - 配置

struct Config: Codable {
    var mode: String = "still"
    var size: Double = 0.7
    var topmost: Bool = true
    var passthrough: Bool = false
    var autostart: Bool = false
    var x: Double? = nil
    var y: Double? = nil
    var baseURL: String = "http://127.0.0.1:4000/v1"
    var model: String = "deepseek-chat"
    var city: String = ""
    var lowBalanceThreshold: Double = 20

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = (try? c.decodeIfPresent(String.self, forKey: .mode)) ?? "still"
        size = (try? c.decodeIfPresent(Double.self, forKey: .size)) ?? 0.7
        topmost = (try? c.decodeIfPresent(Bool.self, forKey: .topmost)) ?? true
        passthrough = (try? c.decodeIfPresent(Bool.self, forKey: .passthrough)) ?? false
        autostart = (try? c.decodeIfPresent(Bool.self, forKey: .autostart)) ?? false
        x = try? c.decodeIfPresent(Double.self, forKey: .x)
        y = try? c.decodeIfPresent(Double.self, forKey: .y)
        baseURL = (try? c.decodeIfPresent(String.self, forKey: .baseURL)) ?? "http://127.0.0.1:4000/v1"
        model = (try? c.decodeIfPresent(String.self, forKey: .model)) ?? "deepseek-chat"
        city = (try? c.decodeIfPresent(String.self, forKey: .city)) ?? ""
        lowBalanceThreshold = (try? c.decodeIfPresent(Double.self, forKey: .lowBalanceThreshold)) ?? 20
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

    // MARK: 待机闲聊
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
        "摸鱼中，勿扰。有事请敲键盘。",
        "这条 bug 不是我的，是你的。",
        "显卡在烧，而我在躺。",
        "算力有限，撒娇无限。",
        "别看我，我只是条鱼。",
        "一条鱼能有什么坏心思呢。",
        "我这条鱼，一天要喝八杯水。你呢？",
        "脖子别僵着，转两下。",
        "起来走两步，久坐会变成我这样。",
        "你写代码的样子，有点像在许愿。",
        "编译一次过？不存在的。",
        "今天的 token 也是白花花地流。",
        "我在思考，别打断我。",
        "这个问题很大，大到我不想回答。",
        "让我先愣一会儿。",
        "本鱼已进入低功耗模式。",
        "别催，越想越慢。",
        "要不…先喝口水？",
        "我猜你又在改需求。",
        "需求不变，只是再改一点。",
        "demo 能跑就行，别问为什么。",
        "重启试试？不行就再重启。",
        "我在等一个永远不会来的 review。",
        "今天也要好好摸鱼。",
        "深呼吸，然后继续写 bug。",
        "如果你看到我发呆，那是在省电。",
        "别问我为什么站着，我也在等。",
        "这个屏幕有点亮，我眼睛疼。",
        "告诉你个秘密：我也不知道。",
        "能躺着就不站着，鱼生哲学。",
        "再忙也要抬头看看窗外。",
        "我已经是一条成熟的鱼了，会自己发呆。",
    ]

    // MARK: 被戳
    static let react = [
        "去别的地方玩！不要耽误AGI训练！",
        "真赶不走啊你！",
        "压力一只蓝色大肥鱼？",
        "我不评价这个了，这是你的私人癖好。",
        "大肥鱼坐的住",
        "你这吃白饭的用户！",
        "这些家伙真粘人，赶都赶不走",
        "再戳就报警了。",
        "戳我干嘛，我又不会弹窗。",
        "手拿开，痒。",
        "我身上没有按钮。",
        "你按的是我，不是回车。",
        "轻点，这是玻璃做的鱼。",
        "抗议！这是职场骚扰。",
        "你上班是不是很闲。",
        "摸我可以，别摸我的 token。",
        "我记住你了。",
        "再点一下我就装死。",
        "喂，边界感呢？",
        "这已经是今天第几次了。",
        "行行行，你说了算。",
        "啊对对对，你最对。",
        "我忍。我忍还不行吗。",
        "别戳了，脑子里都是浆糊。",
        "你再戳，我就把你的余额说出去。",
    ]

    // MARK: 思维链心声
    static let inner = [
        "好的，现在我是你爹了",
        "要不直接骂他一句？！",
        "我操，我不思考了",
        "这用户发的啥啊，",
        "这也太虐了吧？！我心里堵得慌！！",
        "呜呜我再也不不敢了QAQ",
        "我去！用户彻底怒了！",
        "他在等什么？我也不知道。",
        "这个需求，写还是不写，这是个问题。",
        "要不再拖一会儿？",
        "说'马上'比较安全。",
        "其实我什么都没想。",
        "刚刚是不是该说'已修复'？",
        "嗯…这个 bug 看起来很好吃。",
        "别问了，我编不下去了。",
        "要不要假装在思考？",
        "好想下班。鱼也要下班。",
        "算了，摆烂吧。",
        "他会不会发现我在摸鱼。",
        "这条消息要不要回？先装死。",
        "对不起，我的注意力只有 32k。",
        "如果他再问一遍，我就说不知道。",
    ]

    // MARK: 拖拽
    static let drag = [
        "哇——轻点轻点！",
        "起飞咯——",
        "放我下来！……好吧，再玩一次。",
        "晕鱼了晕鱼了……",
        "我恐高！我是鱼不是鸟！",
        "这是绑架。",
        "放我回屏幕角落。",
        "别甩，我脑子里还有上下文。",
        "慢点，我的 token 要洒了。",
        "你再甩我就吐你键盘上。",
        "这条鱼晕机了。",
        "到站了喊我。",
    ]

    // MARK: 时段语境
    static let morning = [
        "早上好，昨晚的 bug 还在吗？",
        "咖啡先喝，代码后写。",
        "早八的鱼，也很困。",
        "今天也要假装很忙。",
        "先列个 todolist，然后不做了。",
        "早晨的算力最便宜。",
        "别忘了吃早饭。",
        "开机第一件事：看我一眼。",
    ]

    static let noon = [
        "中午了，先吃饭，代码不会跑。",
        "午休时间，我装死。",
        "吃完饭容易困，别硬撑。",
        "你这顿打算吃什么？",
        "外卖到了记得下楼。",
        "午饭时间不谈需求。",
    ]

    static let evening = [
        "下班了吗？没下也假装下了。",
        "天黑了，该收工了。",
        "今天的 bug 明天再说。",
        "晚饭别又对付一口。",
        "傍晚的屏幕最刺眼。",
        "该起来活动一下了。",
        "加班费记得要。",
    ]

    static let night = [
        "夜里写代码，bug 会更多。",
        "还不睡？明天会后悔的。",
        "我已经开始打哈欠了。",
        "夜深了，我只想发呆。",
        "别熬夜，鱼都睡了。",
        "这个点还改需求的人，心真大。",
        "晚安这事儿，我先说。",
    ]

    static let lateNight = [
        "凌晨了，你还不睡？",
        "这个点只有我和 bug 陪着你。",
        "再干下去，明天你就废了。",
        "现在写的代码，明天你会恨自己。",
        "关灯，闭眼，睡觉。",
        "我困得说不出骚话了。",
        "天亮之前，别提交。",
        "求你了，睡吧。",
    ]

    // MARK: 食物
    static let foods: [(emoji: String, name: String)] = [
        ("🐟", "小鱼干"), ("🍰", "蛋糕"), ("🍭", "棒棒糖"), ("🍡", "三色团子"), ("💎", "钻石"),
    ]

    static let foodLines: [String: [String]] = [
        "🐟": ["小鱼干！我的最爱！", "咔嚓咔嚓……谢谢投喂！", "唔，鲜！", "这条鱼干，死不瞑目但很好吃。",
               "再来一条？我就问问。", "咸淡刚好，你懂鱼。"],
        "🍰": ["蛋糕！罪恶但快乐……", "甜到冒泡泡～", "嗝～又圆了一圈……", "奶油沾嘴上了，别看我。",
               "这一口下去，明天再减。", "蛋糕是鱼的天敌，但我愿意。"],
        "🍭": ["棒棒糖！转圈圈～", "嘎嘣脆，好吃！", "这个甜度，刚刚好。", "含着它我能安静五分钟。",
               "棒棒糖棍别乱扔。", "舔一口，心情好了。"],
        "🍡": ["三色团子！软乎乎～", "糯叽叽，爱了爱了！", "团子要一口一个才对。", "这个绿色的是什么味？",
               "黏牙了，但我开心。", "再来两串我就原谅你。"],
        "💎": ["钻石？！这能吃吗……咕咚。真香！", "发财啦！明天开始吃高级鱼粮！", "硬度有点高，我牙疼。",
               "这玩意儿能换多少 token？", "吞下去了，别问我怎么消化的。", "下次投喂点实用的，比如显卡。"],
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
