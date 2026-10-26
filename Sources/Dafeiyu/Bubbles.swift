import AppKit

/// 圆角背景视图,用来做气泡/胶囊底板。
final class RoundedView: NSView {
    var fillColor: NSColor = .white
    var strokeColor: NSColor = .clear
    var cornerRadius: CGFloat = 14

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                xRadius: cornerRadius, yRadius: cornerRadius)
        fillColor.setFill()
        path.fill()
        if strokeColor != .clear {
            strokeColor.setStroke()
            path.lineWidth = 1
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
        bg.fillColor = NSColor.white.withAlphaComponent(0.94)
        bg.strokeColor = NSColor.black.withAlphaComponent(0.06)
        bg.cornerRadius = 14
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
        bg.fillColor = NSColor.white
        bg.strokeColor = NSColor(calibratedRed: 0.90, green: 0.91, blue: 0.92, alpha: 1)
        bg.cornerRadius = 20
        bg.autoresizingMask = [.width, .height]
        contentView = bg

        field.frame = NSRect(x: 18, y: 12, width: 330, height: 32)
        field.isBordered = false
        field.drawsBackground = false
        field.font = NSFont.systemFont(ofSize: 15)
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
        send.layer?.backgroundColor = NSColor(calibratedRed: 0.73, green: 0.78, blue: 1, alpha: 1).cgColor
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
        let color = hasText
            ? NSColor(calibratedRed: 0.34, green: 0.53, blue: 0.99, alpha: 1)
            : NSColor(calibratedRed: 0.73, green: 0.78, blue: 1, alpha: 1)
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
        bg.fillColor = NSColor(calibratedRed: 40 / 255, green: 40 / 255, blue: 60 / 255, alpha: 0.85)
        bg.cornerRadius = 14
        bg.autoresizingMask = [.width, .height]
        contentView = bg

        let pink = NSColor(calibratedRed: 1, green: 0.70, blue: 0.78, alpha: 1)
        for (i, food) in Lines.foods.enumerated() {
            let btn = NSButton(frame: NSRect(x: 12 + CGFloat(i) * 52, y: 10, width: 44, height: 44))
            btn.title = food.emoji
            btn.font = NSFont.systemFont(ofSize: 20)
            btn.isBordered = false
            btn.wantsLayer = true
            btn.layer?.cornerRadius = 22
            btn.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.95).cgColor
            btn.layer?.borderWidth = 2
            btn.layer?.borderColor = pink.cgColor
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
        close.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.8).cgColor
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
