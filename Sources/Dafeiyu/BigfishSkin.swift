import AppKit
import CoreGraphics
import ImageIO
import Foundation

/// dsh-bigfish 的图集动画(quiet / motions / signs / atlas)。
/// 素材来自 gosomea/dsh-bigfish(MIT),按 4 列网格切帧。
final class BigfishSkin {
    static let shared = BigfishSkin()

    enum Atlas: String {
        case quiet, motions, signs, work, daily, atlas
    }

    struct Anim {
        let atlas: Atlas
        let fps: Double
        let frames: [Int]
    }

    /// 从 pack manifest 抄下来的代表性动作。
    static let anims: [String: Anim] = [
        "breathe": .init(atlas: .quiet, fps: 6, frames: Array(repeating: 0, count: 12)),
        "confirm": .init(atlas: .quiet, fps: 3, frames: [4, 4, 5, 5, 6, 5, 7, 7]),
        "celebrate": .init(atlas: .motions, fps: 4, frames: [12, 13, 14, 15]),
        "wave": .init(atlas: .motions, fps: 4, frames: [12, 13, 12, 13, 14, 12]),
        "type": .init(atlas: .motions, fps: 5, frames: [4, 5, 4, 6, 4, 7, 7, 4]),
        "panic": .init(atlas: .motions, fps: 4, frames: [8, 9, 8, 9, 10, 11]),
        "sign": .init(atlas: .signs, fps: 2, frames: [0, 1, 2, 2, 3, 2, 2, 1]),
    ]

    /// 每个图集的行数(列固定 4)。
    private let rows: [String: Int] = [
        "quiet": 2, "motions": 4, "signs": 4, "atlas": 3, "work": 4, "daily": 4,
    ]

    private var cache: [String: CGImage] = [:]
    /// 裁切后的单帧缓存:原来每帧都重新 cropping,浪费在重复切割上。
    private var frameCache: [String: CGImage] = [:]
    private let dir: URL

    private init() {
        dir = BigfishSkin.resourceDir()
    }

    static func resourceDir() -> URL {
        if let res = Bundle.main.resourceURL?.appendingPathComponent("bigfish"),
           FileManager.default.fileExists(atPath: res.path) {
            return res
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources/bigfish")
    }

    func atlasImage(_ atlas: Atlas) -> CGImage? {
        if let hit = cache[atlas.rawValue] { return hit }
        let url = dir.appendingPathComponent("bigfish-\(atlas.rawValue).png")
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        cache[atlas.rawValue] = img
        return img
    }

    /// 取某一帧(已按网格裁好)。
    func frame(_ anim: Anim, index: Int) -> CGImage? {
        let key = "\(anim.atlas.rawValue)-\(index)"
        if let hit = frameCache[key] { return hit }
        guard let img = atlasImage(anim.atlas) else { return nil }
        let r = rows[anim.atlas.rawValue] ?? 1
        let cols = 4
        let cw = img.width / cols
        let ch = img.height / r
        let idx = ((index % (cols * r)) + cols * r) % (cols * r)
        let col = idx % cols
        let row = idx / cols
        let rect = CGRect(x: col * cw, y: row * ch, width: cw, height: ch)
        let out = img.cropping(to: rect)
        if let out { frameCache[key] = out }
        return out
    }

    func frame(_ name: String, at time: TimeInterval) -> CGImage? {
        guard let anim = BigfishSkin.anims[name], !anim.frames.isEmpty else { return nil }
        let step = Int(time * anim.fps)
        let idx = anim.frames[((step % anim.frames.count) + anim.frames.count) % anim.frames.count]
        return frame(anim, index: idx)
    }
}
