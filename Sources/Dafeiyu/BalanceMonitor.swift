import Foundation

/// 定期查 DeepSeek 余额:更新菜单栏、低余额提醒一次(跨过阈值才响,回到阈值以上重置)。
final class BalanceMonitor {
    var onUpdate: ((Double) -> Void)?
    var onLowBalance: ((Double, Double) -> Void)?

    private var timer: Timer?
    private var lowAlerted = false
    private var inFlight = false

    static let refreshInterval: TimeInterval = 3 * 3600

    func start() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.refresh() }
        let t = Timer(timeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func refresh() {
        guard !inFlight else { return }
        guard let found = KeyStore.deepSeekKey() else { return }
        inFlight = true

        DeepSeekClient.fetch(key: found.key) { [weak self] result in
            guard let self else { return }
            self.inFlight = false
            guard case .success(let infos) = result,
                  let first = infos.first,
                  let total = Double(first.total) else { return }

            DispatchQueue.main.async {
                self.onUpdate?(total)
                let threshold = Config.load().lowBalanceThreshold
                if threshold > 0, total < threshold {
                    if !self.lowAlerted {
                        self.lowAlerted = true
                        self.onLowBalance?(total, threshold)
                    }
                } else {
                    self.lowAlerted = false
                }
            }
        }
    }
}
