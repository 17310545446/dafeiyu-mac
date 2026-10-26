import Foundation

/// wttr.in(WorldWeatherOnline 数据源)天气。不需要 API Key。
/// 上游 `lang=zh` 实际不翻译,这里自己维护中英对照。
enum WeatherClient {

    struct Weather {
        let place: String
        let tempC: String
        let humidity: String
        let windKmph: String
        let descZh: String

        var speech: String {
            "\(place) \(tempC)°C \(descZh),湿度 \(humidity)%,风 \(windKmph)km/h"
        }
    }

    enum Failure: LocalizedError {
        case badURL
        case http(Int)
        case decode

        var errorDescription: String? {
            switch self {
            case .badURL: return "城市名无法编码"
            case .http(let c): return "wttr.in 返回 HTTP \(c)"
            case .decode: return "天气数据解析失败"
            }
        }
    }

    /// WWO condition 英文 → 中文。未命中时回落英文原文。
    private static let zhMap: [String: String] = [
        "sunny": "晴",
        "clear": "晴朗",
        "partly cloudy": "多云",
        "cloudy": "阴",
        "overcast": "阴天",
        "mist": "薄雾",
        "fog": "雾",
        "freezing fog": "冻雾",
        "haze": "霾",
        "smoky haze": "烟霾",
        "smoke": "烟",
        "dust": "扬尘",
        "sand": "沙尘",
        "patchy rain nearby": "周边有雨",
        "patchy rain possible": "可能有雨",
        "patchy light rain": "零星小雨",
        "light drizzle": "毛毛雨",
        "light rain": "小雨",
        "moderate rain": "中雨",
        "heavy rain": "大雨",
        "torrential rain shower": "暴雨",
        "light rain shower": "阵雨",
        "moderate or heavy rain shower": "中到大雨",
        "patchy light rain with thunder": "雷阵雨",
        "thundery outbreaks possible": "可能有雷雨",
        "moderate or heavy rain with thunder": "雷雨",
        "rain": "有雨",
        "light freezing rain": "冻雨",
        "light snow": "小雪",
        "patchy light snow": "零星小雪",
        "patchy moderate snow": "中雪",
        "moderate snow": "中雪",
        "heavy snow": "大雪",
        "blizzard": "暴雪",
        "patchy snow possible": "可能有雪",
        "patchy sleet possible": "可能有雨夹雪",
        "light sleet": "小雨夹雪",
        "moderate or heavy sleet": "雨夹雪",
        "ice pellets": "冰粒",
        "light showers of ice pellets": "小冰粒",
        "freezing drizzle": "冻毛毛雨",
    ]

    static func translate(_ english: String) -> String {
        let key = english.lowercased().trimmingCharacters(in: .whitespaces)
        return zhMap[key] ?? english
    }

    static func fetch(city: String, completion: @escaping (Result<Weather, Error>) -> Void) {
        let trimmed = city.trimmingCharacters(in: .whitespacesAndNewlines)
        let path = trimmed.isEmpty ? "" : (trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "")
        guard let url = URL(string: "https://wttr.in/\(path)?format=j1&lang=zh") else {
            completion(.failure(Failure.badURL)); return
        }

        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        req.setValue("curl/8", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: req) { data, resp, err in
            if let err { completion(.failure(err)); return }
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200 else { completion(.failure(Failure.http(code))); return }
            guard let data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let current = (obj["current_condition"] as? [[String: Any]])?.first else {
                completion(.failure(Failure.decode)); return
            }

            let area = ((obj["nearest_area"] as? [[String: Any]])?.first
                        .flatMap { $0["areaName"] as? [[String: Any]] }?
                        .first?["value"] as? String) ?? trimmed
            let place = trimmed.isEmpty ? (area.isEmpty ? "本地" : area) : trimmed

            let descEn = ((current["weatherDesc"] as? [[String: Any]])?.first?["value"] as? String) ?? ""

            let weather = Weather(
                place: place,
                tempC: current["temp_C"] as? String ?? "?",
                humidity: current["humidity"] as? String ?? "?",
                windKmph: current["windspeedKmph"] as? String ?? "?",
                descZh: translate(descEn)
            )
            completion(.success(weather))
        }.resume()
    }
}
