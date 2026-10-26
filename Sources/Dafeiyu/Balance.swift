import Foundation

/// DeepSeek 官方余额接口:`GET https://api.deepseek.com/user/balance`
/// 注意:官方没有"用量"查询 API,用量只能去 platform.deepseek.com/usage 看。
enum DeepSeekClient {

    struct Balance {
        let currency: String
        let total: String
        let granted: String
        let topped: String
        let available: Bool

        var speech: String {
            var s = "余额 \(currency) \(total)"
            if let g = Double(granted), g > 0 { s += "(赠金 \(granted))" }
            return s
        }
    }

    enum Failure: LocalizedError {
        case http(Int, String)
        case decode

        var errorDescription: String? {
            switch self {
            case .http(let c, let body): return "HTTP \(c) \(body.prefix(80))"
            case .decode: return "余额数据解析失败"
            }
        }
    }

    static func fetch(key: String, completion: @escaping (Result<[Balance], Error>) -> Void) {
        guard let url = URL(string: "https://api.deepseek.com/user/balance") else {
            completion(.failure(Failure.decode)); return
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: req) { data, resp, err in
            if let err { completion(.failure(err)); return }
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard let data else { completion(.failure(Failure.decode)); return }
            guard code == 200 else {
                completion(.failure(Failure.http(code, String(decoding: data, as: UTF8.self))))
                return
            }
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let infos = obj["balance_infos"] as? [[String: Any]] else {
                completion(.failure(Failure.decode)); return
            }
            let available = (obj["is_available"] as? Bool) ?? false
            let list = infos.map {
                Balance(currency: $0["currency"] as? String ?? "?",
                        total: $0["total_balance"] as? String ?? "?",
                        granted: $0["granted_balance"] as? String ?? "0",
                        topped: $0["topped_up_balance"] as? String ?? "0",
                        available: available)
            }
            completion(.success(list))
        }.resume()
    }
}

/// 找 DeepSeek Key:优先 Keychain,其次读本机 LiteLLM 网关的 .env(不落盘、不外传)。
enum KeyStore {
    static let envPath = (("~/develop-tool/litellm-gw/.env") as NSString).expandingTildeInPath

    static func deepSeekKey() -> (key: String, source: String)? {
        if let k = Keychain.read(account: "deepseek-key"),
           !k.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return (k, "Keychain")
        }
        guard let text = try? String(contentsOfFile: envPath, encoding: .utf8) else { return nil }
        for raw in text.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            var value: String?
            for prefix in ["DEEPSEEK_API_KEY=", "export DEEPSEEK_API_KEY="] where line.hasPrefix(prefix) {
                value = String(line.dropFirst(prefix.count))
            }
            guard var v = value else { continue }
            v = v.trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
            if !v.isEmpty { return (v, "本机网关 .env") }
        }
        return nil
    }
}
