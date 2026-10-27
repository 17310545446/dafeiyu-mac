import AppKit

/// 全部弹层(气泡 / 功能条 / 输入胶囊 / 喂食面板)共用的一套视觉参数。
enum Theme {
    /// 底色:以举牌那块奶黄牌为准(1.0, 0.94, 0.74)
    static let surface = NSColor(calibratedRed: 1.0, green: 0.94, blue: 0.74, alpha: 0.98)
    static let surfaceSolid = NSColor(calibratedRed: 1.0, green: 0.94, blue: 0.74, alpha: 0.98)
    /// 描边:牌面的金棕色,2pt(和举牌一致)
    static let stroke = NSColor(calibratedRed: 0.84, green: 0.68, blue: 0.34, alpha: 1)
    static let strokeWidth: CGFloat = 2
    /// 正文与次要文字:深棕
    static let title = NSColor(calibratedRed: 0.26, green: 0.20, blue: 0.13, alpha: 1)
    static let dim = NSColor(calibratedRed: 0.46, green: 0.37, blue: 0.25, alpha: 1)
    /// 强调色(发送键 / 选中),沿用牌面的金棕
    static let accent = NSColor(calibratedRed: 0.84, green: 0.68, blue: 0.34, alpha: 1)
    static let accentSoft = NSColor(calibratedRed: 0.93, green: 0.86, blue: 0.66, alpha: 1)
    /// 圆角与阴影:与牌面一致
    static let radius: CGFloat = 6
    static let shadowOpacity: Float = 0.16
    static let shadowRadius: CGFloat = 10
}

/// 圆角背景视图,用来做气泡/胶囊底板。
final class RoundedView: NSView {
    var fillColor: NSColor = Theme.surface
    var strokeColor: NSColor = Theme.stroke
    var cornerRadius: CGFloat = Theme.radius

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                xRadius: cornerRadius, yRadius: cornerRadius)
        fillColor.setFill()
        path.fill()
        if strokeColor != .clear {
            strokeColor.setStroke()
            path.lineWidth = Theme.strokeWidth
            path.stroke()
        }
    }
}

/// 悬浮小面板基类。
class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(size: NSSize) {
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        hasShadow = true
    }

    /// 悬浮在桌宠正上方。
    func show(above petFrame: NSRect, offset: CGFloat = 6) {
        let x = petFrame.midX - frame.width / 2
        let y = petFrame.maxY + offset
        setFrameOrigin(NSPoint(x: x, y: y))
        orderFrontRegardless()
    }
}

/// 单击桌宠弹出的功能条(原版那颗 🗨️)。
final class FunctionBar: FloatingPanel {
    var onChat: (() -> Void)?
    private var hideWork: DispatchWorkItem?

    private static let barSize = NSSize(width: 68, height: 60)

    init() {
        super.init(size: FunctionBar.barSize)

        let bg = RoundedView(frame: NSRect(origin: .zero, size: FunctionBar.barSize))
        bg.fillColor = Theme.surface
        bg.strokeColor = Theme.stroke
        bg.cornerRadius = Theme.radius
        bg.autoresizingMask = [.width, .height]
        contentView = bg

        let btn = NSButton(frame: NSRect(x: 8, y: 6, width: 52, height: 48))
        btn.title = "🗨️"
        btn.font = NSFont.systemFont(ofSize: 26)
        btn.isBordered = false
        btn.target = self
        btn.action = #selector(chatTapped)
        bg.addSubview(btn)
    }

    override var canBecomeKey: Bool { false }

    func showAutoHide(above petFrame: NSRect) {
        show(above: petFrame)
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.orderOut(nil) }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: work)
    }

    @objc private func chatTapped() {
        orderOut(nil)
        onChat?()
    }
}

/// 一行聊天胶囊(原版 420×56 的白底输入框)。
final class ChatPill: FloatingPanel, NSWindowDelegate {
    var onSubmit: ((String) -> Void)?

    private let field = NSTextField()
    private let send = NSButton()
    private static let pillSize = NSSize(width: 420, height: 56)

    init() {
        super.init(size: ChatPill.pillSize)

        let bg = RoundedView(frame: NSRect(origin: .zero, size: ChatPill.pillSize))
        bg.fillColor = Theme.surfaceSolid
        bg.strokeColor = Theme.stroke
        bg.cornerRadius = Theme.radius
        bg.autoresizingMask = [.width, .height]
        contentView = bg

        field.frame = NSRect(x: 18, y: 12, width: 330, height: 32)
        field.isBordered = false
        field.drawsBackground = false
        field.font = NSFont.systemFont(ofSize: 15)
        field.textColor = Theme.title
        field.placeholderString = "给大肥鱼发送消息"
        field.focusRingType = .none
        field.delegate = self
        field.target = self
        field.action = #selector(submit)
        bg.addSubview(field)

        send.frame = NSRect(x: 366, y: 12, width: 32, height: 32)
        send.title = "↑"
        send.font = NSFont.systemFont(ofSize: 20, weight: .bold)
        send.isBordered = false
        send.wantsLayer = true
        send.layer?.cornerRadius = 16
        send.layer?.backgroundColor = Theme.accentSoft.cgColor
        send.contentTintColor = .white
        send.target = self
        send.action = #selector(submit)
        bg.addSubview(send)

        delegate = self
    }

    /// 点到别处(窗口失去键盘焦点)就收起,不用专门找关闭按钮。
    func windowDidResignKey(_ notification: Notification) {
        orderOut(nil)
    }

    func showAndFocus(above petFrame: NSRect) {
        show(above: petFrame, offset: 8)
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        field.stringValue = ""
        updateSendStyle()
        field.becomeFirstResponder()
    }

    private func updateSendStyle() {
        let hasText = !field.stringValue.trimmingCharacters(in: .whitespaces).isEmpty
        let color = hasText ? Theme.accent : Theme.accentSoft
        send.layer?.backgroundColor = color.cgColor
    }

    @objc private func submit() {
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        orderOut(nil)
        onSubmit?(text)
    }
}

extension ChatPill: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) { updateSendStyle() }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)) {
            submit()
            return true
        }
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            orderOut(nil)
            return true
        }
        return false
    }
}

/// 双击桌宠弹出的喂食面板(原版 310×64 的深色圆角条)。
final class FeedBar: FloatingPanel {
    var onPick: ((String) -> Void)?
    private static let barSize = NSSize(width: 310, height: 64)

    init() {
        super.init(size: FeedBar.barSize)

        let bg = RoundedView(frame: NSRect(origin: .zero, size: FeedBar.barSize))
        bg.fillColor = Theme.surface
        bg.strokeColor = Theme.stroke
        bg.cornerRadius = Theme.radius
        bg.autoresizingMask = [.width, .height]
        contentView = bg

        for (i, food) in Lines.foods.enumerated() {
            let btn = NSButton(frame: NSRect(x: 12 + CGFloat(i) * 52, y: 10, width: 44, height: 44))
            btn.title = food.emoji
            btn.font = NSFont.systemFont(ofSize: 20)
            btn.isBordered = false
            btn.wantsLayer = true
            btn.layer?.cornerRadius = 22
            btn.layer?.backgroundColor = Theme.accentSoft.cgColor
            btn.layer?.borderWidth = 1
            btn.layer?.borderColor = Theme.stroke.cgColor
            btn.target = self
            btn.action = #selector(pickFood(_:))
            btn.toolTip = food.name
            bg.addSubview(btn)
        }

        let close = NSButton(frame: NSRect(x: 272, y: 19, width: 26, height: 26))
        close.title = "✕"
        close.font = NSFont.systemFont(ofSize: 12)
        close.isBordered = false
        close.wantsLayer = true
        close.layer?.cornerRadius = 13
        close.layer?.backgroundColor = Theme.dim.withAlphaComponent(0.12).cgColor
        close.target = self
        close.action = #selector(closeTapped)
        bg.addSubview(close)
    }

    override var canBecomeKey: Bool { false }

    @objc private func pickFood(_ sender: NSButton) {
        orderOut(nil)
        onPick?(sender.title)
    }

    @objc private func closeTapped() { orderOut(nil) }
}
