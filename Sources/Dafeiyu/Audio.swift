import AppKit
import AVFoundation
import Foundation

/// 语音 / 音效 / BGM。语音用于 dafeiyu 皮肤(预渲染 mp3 + 原文台词)。
final class AudioManager {
    static let shared = AudioManager()

    private var voicePlayer: AVAudioPlayer?
    private var sfxPlayer: AVAudioPlayer?
    private var bgmPlayer: AVAudioPlayer?
    private var dir: URL { DafeiyuSkin.resourceDir() }

    var voiceEnabled: Bool {
        get { Config.load().voiceEnabled }
        set { var c = Config.load(); c.voiceEnabled = newValue; c.save() }
    }
    var sfxEnabled: Bool {
        get { Config.load().sfxEnabled }
        set { var c = Config.load(); c.sfxEnabled = newValue; c.save() }
    }
    var bgmEnabled: Bool {
        get { Config.load().bgmEnabled }
        set { var c = Config.load(); c.bgmEnabled = newValue; c.save(); newValue ? startBGM() : stopBGM() }
    }

    /// 播放语音,返回时长(秒);失败返回 0。
    @discardableResult
    func playVoice(_ id: String) -> TimeInterval {
        guard voiceEnabled else { return 0 }
        let url = dir.appendingPathComponent("voice/\(id).mp3")
        guard let p = try? AVAudioPlayer(contentsOf: url) else { return 0 }
        voicePlayer?.stop()
        p.prepareToPlay()
        p.play()
        voicePlayer = p
        return p.duration
    }

    func stopVoice() {
        voicePlayer?.stop()
        voicePlayer = nil
    }

    func playSfx(_ name: String) {
        guard sfxEnabled else { return }
        let url = dir.appendingPathComponent("sfx/\(name).mp3")
        guard let p = try? AVAudioPlayer(contentsOf: url) else { return }
        sfxPlayer?.stop()
        p.play()
        sfxPlayer = p
    }

    func startBGM() {
        guard bgmPlayer == nil else { return }
        let url = dir.appendingPathComponent("bgm/dafeiyu.mp3")
        guard let p = try? AVAudioPlayer(contentsOf: url) else { return }
        p.numberOfLoops = -1
        p.volume = 0.35
        p.play()
        bgmPlayer = p
    }

    func stopBGM() {
        bgmPlayer?.stop()
        bgmPlayer = nil
    }

    func applyBGMPreference() {
        if Config.load().bgmEnabled { startBGM() } else { stopBGM() }
    }
}
