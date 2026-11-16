import UIKit
final class DanmakuCanvas: UIView {
    struct Config {
        var fontSize: CGFloat = 18
        var duration: Double = 7
        var opacity: Double = 0.9
        var areaRatio: Double = 0.5
        var blockedWords: [String] = []
        var enabled: Bool = true
        static func from(settings: DanmuSettings) -> Config {
            Config(
                fontSize: CGFloat(settings.fontSize),
                duration: settings.duration,
                opacity: settings.opacity,
                areaRatio: settings.areaRatio,
                blockedWords: settings.blocked
                    .split(whereSeparator: { $0 == "," || $0 == "，" })
                    .map { String($0).trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty },
                enabled: settings.enabled
            )
        }
    }
    var config = Config() { didSet { setNeedsLayout() } }
    private var laneFree: [Double] = []
    private let laneHeightRatio: CGFloat = 1.45
    func clearAll() {
        subviews.forEach { $0.removeFromSuperview() }
        laneFree = []
    }
    private var laneCount: Int {
        let usable = bounds.height * CGFloat(config.areaRatio)
        let lh = config.fontSize * laneHeightRatio
        return max(1, Int(usable / lh))
    }
    func emit(text: String, hexColor: String, position: String) {
        guard config.enabled, bounds.width > 10, bounds.height > 10 else { return }
        if !config.blockedWords.isEmpty && config.blockedWords.contains(where: { text.contains($0) }) { return }
        let lanes = laneCount
        if laneFree.count != lanes { laneFree = Array(repeating: 0, count: lanes) }
        let now = CACurrentMediaTime()
        var lane = -1
        for i in 0..<lanes where laneFree[i] <= now { lane = i; break }
        if lane < 0 { lane = Int.random(in: 0..<lanes) }
        let label = UILabel()
        label.text = text
        label.font = .boldSystemFont(ofSize: config.fontSize)
        label.textColor = UIColor(hex: hexColor) ?? .white
        label.alpha = config.opacity
        label.layer.shadowColor = UIColor.black.cgColor
        label.layer.shadowOpacity = 0.8
        label.layer.shadowRadius = 2
        label.layer.shadowOffset = .zero
        label.sizeToFit()
        let laneH = config.fontSize * laneHeightRatio
        let y = CGFloat(lane) * laneH + 6
        if position == "top" || position == "bottom" {
            label.frame.origin = CGPoint(x: (bounds.width - label.frame.width) / 2, y: y)
            if position == "bottom" {
                label.frame.origin.y = bounds.height - y - label.frame.height
            }
            addSubview(label)
            label.alpha = 0
            UIView.animate(withDuration: 0.3, animations: { label.alpha = self.config.opacity }) { _ in
                UIView.animate(withDuration: self.config.duration * 0.4,
                               delay: self.config.duration * 0.6,
                               animations: { label.alpha = 0 }) { _ in label.removeFromSuperview() }
            }
            laneFree[lane] = now + 0.8
        } else {
            let startX = bounds.width
            label.frame.origin = CGPoint(x: startX, y: y)
            addSubview(label)
            let travel = startX + label.frame.width
            UIView.animate(withDuration: config.duration, delay: 0, options: [.curveLinear]) {
                label.frame.origin.x = -label.frame.width
            } completion: { _ in label.removeFromSuperview() }
            let enter = (label.frame.width / travel) * config.duration
            laneFree[lane] = now + enter + 0.25
        }
    }
}
extension UIColor {
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.hasPrefix("0x") { s.removeFirst(2) }
        guard s.count == 6, let v = UInt64(s, radix: 16) else { return nil }
        self.init(red: CGFloat((v >> 16) & 0xFF) / 255,
                  green: CGFloat((v >> 8) & 0xFF) / 255,
                  blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
}