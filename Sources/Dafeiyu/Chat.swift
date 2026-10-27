import AppKit
import Foundation
import Security

// MARK: - Keychain(API Key 不落明文)

enum Keychain {
    static let service = "io.github.dafeiyu.mac"

    static func save(account: String, value: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        guard !value.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - LLM 客户端(OpenAI 兼容协议)

enum LLMError: LocalizedError {
    case badURL
    case http(Int, String)
    case empty
    case decode(String)

    var errorDescription: String? {
        switch self {
        case .badURL: return "Base URL 不合法"
        case .http(let code, let body): return "HTTP \(code) \(body.prefix(120))"
        case .empty: return "模型返回空内容"
        case .decode(let s): return "解析失败:\(s.prefix(100))"
        }
    }
}

final class LLMClient {
    static let systemPrompt = "你是桌面宠物大肥鱼,贱兮兮但可爱,每句话不超过25字,偶尔吐槽主人但别真骂人。"

    struct Message { let role: String; let content: String }

    static func chat(baseURL: String,
                     model: String,
                     apiKey: String,
                     history: [Message],
                     completion: @escaping (Result<String, Error>) -> Void) {
        let trimmed = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: trimmed + "/chat/completions") else {
            completion(.failure(LLMError.badURL)); return
        }

        var messages: [[String: String]] = [["role": "system", "content": systemPrompt]]
        messages.append(contentsOf: history.map { ["role": $0.role, "content": $0.content] })

        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "temperature": 0.8,
            "max_tokens": 200,
            "stream": false,
        ]

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 45
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        guard let data = try? JSONSerialization.data(withJSONObject: body) else {
            completion(.failure(LLMError.decode("body"))); return
        }
        req.httpBody = data

        URLSession.shared.dataTask(with: req) { data, resp, err in
            if let err { completion(.failure(err)); return }
            guard let data else { completion(.failure(LLMError.empty)); return }
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200 else {
                completion(.failure(LLMError.http(code, String(decoding: data, as: UTF8.self))))
                return
            }
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = obj["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any],
                  let text = message["content"] as? String,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                completion(.failure(LLMError.decode(String(decoding: data, as: UTF8.self))))
                return
            }
            completion(.success(text.trimmingCharacters(in: .whitespacesAndNewlines)))
        }.resume()
    }
}

// MARK: - 聊天面板

final class ChatPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class ChatController: NSObject, NSTextFieldDelegate, NSWindowDelegate {
    private(set) var panel: ChatPanel!
    private var textView: NSTextView!
    private var input: NSTextField!
    private var sendButton: NSButton!
    private var history: [LLMClient.Message] = []
    private var busy = false
    weak var pet: PetView?

    override init() {
        super.init()
        history = HistoryStore.load()
        buildPanel()
    }

    private func buildPanel() {
        panel = ChatPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 420),
                          styleMask: [.titled, .closable],
                          backing: .buffered, defer: false)
        panel.title = "和大肥鱼聊天"
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.delegate = self

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 420))
        content.autoresizingMask = [.width, .height]

        let scroll = NSScrollView(frame: NSRect(x: 12, y: 56, width: 336, height: 348))
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        let tv = NSTextView(frame: scroll.bounds)
        tv.isEditable = false
        tv.isSelectable = true
        tv.drawsBackground = true
        tv.backgroundColor = .textBackgroundColor
        tv.textContainerInset = NSSize(width: 8, height: 8)
        tv.autoresizingMask = [.width]
        scroll.documentView = tv
        textView = tv

        input = NSTextField(frame: NSRect(x: 12, y: 18, width: 268, height: 26))
        input.placeholderString = "说点什么…"
        input.delegate = self
        input.target = self
        input.action = #selector(sendPressed)

        sendButton = NSButton(frame: NSRect(x: 288, y: 17, width: 60, height: 28))
        sendButton.title = "发送"
        sendButton.bezelStyle = .rounded
        sendButton.target = self
        sendButton.action = #selector(sendPressed)

        content.addSubview(scroll)
        content.addSubview(input)
        content.addSubview(sendButton)
        panel.contentView = content
        appendLine("大肥鱼", "戳我聊天?先说好,我嘴很贱。")
    }

    func toggle(near rect: NSRect) {
        if panel.isVisible {
            panel.orderOut(nil)
            pet?.chatPaused = false
        } else {
            show(near: rect)
        }
    }

    func show(near rect: NSRect) {
        var origin = NSPoint(x: rect.maxX - 360, y: rect.minY - 430)
        if let screen = NSScreen.main?.visibleFrame {
            origin.x = min(max(screen.minX + 8, origin.x), screen.maxX - 368)
            origin.y = max(screen.minY + 8, origin.y)
        }
        panel.setFrameOrigin(origin)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        pet?.chatPaused = true
    }

    func windowWillClose(_ notification: Notification) {
        pet?.chatPaused = false
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)) {
            sendPressed()
            return true
        }
        return false
    }

    @objc func sendPressed() {
        let text = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !busy else { return }
        input.stringValue = ""
        appendLine("你", text)
        history.append(.init(role: "user", content: text))
        persist()
        setBusy(true)

        let cfg = Config.load()
        let key = Keychain.read(account: "api-key") ?? ""
        let historySnapshot = history

        LLMClient.chat(baseURL: cfg.baseURL, model: cfg.model, apiKey: key, history: historySnapshot) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.setBusy(false)
                switch result {
                case .success(let reply):
                    self.appendLine("大肥鱼", reply)
                    self.history.append(.init(role: "assistant", content: reply))
                    self.persist()
                    self.pet?.say(String(reply.prefix(24)))
                case .failure(let err):
                    let msg = err.localizedDescription
                    self.appendLine("系统", "请求失败:\(msg)")
                    self.pet?.say("连不上网关,是不是没开?")
                }
            }
        }
    }

    /// 一行胶囊发送:回复直接冒泡(超过 28 字截断),不进大面板。
    func quickSend(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        history.append(.init(role: "user", content: trimmed))
        persist()

        let cfg = Config.load()
        let key = Keychain.read(account: "api-key") ?? ""
        LLMClient.chat(baseURL: cfg.baseURL, model: cfg.model, apiKey: key, history: history) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let reply):
                    self.history.append(.init(role: "assistant", content: reply))
                    self.persist()
                    let short = reply.count > 28 ? String(reply.prefix(28)) + "…" : reply
                    self.pet?.say(short)
                case .failure(let err):
                    let short = String(err.localizedDescription.prefix(16))
                    self.pet?.say("API错误:\(short)")
                }
            }
        }
    }

    private func trimHistory() {
        if history.count > 40 { history.removeFirst(history.count - 40) }
    }

    /// 裁剪后写盘。
    private func persist() {
        trimHistory()
        HistoryStore.save(history)
    }

    func clearHistory() {
        history.removeAll()
        HistoryStore.clear()
        appendLine("系统", "本地对话记忆已清空")
    }

    private func setBusy(_ on: Bool) {
        busy = on
        input.isEnabled = !on
        sendButton.isEnabled = !on
        if on { appendLine("大肥鱼", "……(正在想)") }
    }

    private func appendLine(_ who: String, _ text: String) {
        let font = NSFont.systemFont(ofSize: 12)
        let color: NSColor = who == "你" ? .systemBlue : (who == "系统" ? .systemRed : .labelColor)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let line = "\(who):\(text)\n\n"
        textView.textStorage?.append(NSAttributedString(string: line, attributes: attrs))
        textView.scrollToEndOfDocument(nil)
    }
}


// MARK: - 本地对话历史(JSON,0600)

enum HistoryStore {
    static let url: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Dafeiyu", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("chat-history.json")
    }()

    static func load() -> [LLMClient.Message] {
        guard let data = try? Data(contentsOf: url),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] else { return [] }
        return arr.compactMap { d in
            guard let role = d["role"], let content = d["content"], !content.isEmpty else { return nil }
            return LLMClient.Message(role: role, content: content)
        }
    }

    static func save(_ messages: [LLMClient.Message]) {
        let arr: [[String: String]] = messages.map { ["role": $0.role, "content": $0.content] }
        guard let data = try? JSONSerialization.data(withJSONObject: arr, options: [.prettyPrinted]) else { return }
        try? data.write(to: url, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}
