import AVKit
import Foundation
final class PlayerModel: NSObject, ObservableObject {
    let player = AVPlayer()
    let danmaku = DanmakuCanvas()
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var isPlaying = false
    @Published var danmus: [DanmuItem] = []
    private var cursor = 0
    private var observer: Any?
    private var lastTime: Double = 0
    func play(url: URL) {
        cursor = 0
        danmaku.clearAll()
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        player.play()
        isPlaying = true
        if observer == nil {
            observer = player.addPeriodicTimeObserver(
                forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
                queue: .main
            ) { [weak self] t in
                guard let self = self else { return }
                self.currentTime = max(0, t.seconds)
                if let d = self.player.currentItem?.duration.seconds, d.isFinite, d > 0 {
                    self.duration = d
                }
                self.tick()
            }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(itemEnded),
                                               name: .AVPlayerItemDidPlayToEndTime, object: item)
    }
    @objc private func itemEnded() { isPlaying = false }
    func togglePlay() {
        if player.timeControlStatus == .playing {
            player.pause(); isPlaying = false
        } else {
            player.play(); isPlaying = true
        }
    }
    func seek(to seconds: Double) {
        let back = seconds < lastTime - 1
        player.seek(to: CMTime(seconds: max(0, seconds), preferredTimescale: 600))
        if back { cursor = 0; danmaku.clearAll() }
        lastTime = seconds
    }
    func tick() {
        let hasTime = danmus.contains { $0.time > 0 }
        if hasTime {
            while cursor < danmus.count && danmus[cursor].time <= currentTime {
                emitItem(danmus[cursor]); cursor += 1
            }
        } else {
            let idx = Int(currentTime / 1.2)
            while cursor < min(idx, danmus.count) {
                emitItem(danmus[cursor]); cursor += 1
            }
        }
        lastTime = currentTime
    }
    private func emitItem(_ d: DanmuItem) {
        danmaku.emit(text: d.text, hexColor: d.color, position: d.position)
    }
    func send(_ text: String, cfg: DanmuSettings) {
        danmaku.emit(text: text, hexColor: "#FFFFFF", position: "scroll")
        Task { await APIClient.sendDanmu(text: text, cfg: cfg) }
    }
    func loadDanmus(cfg: DanmuSettings) async {
        let list = await APIClient.fetchDanmus(apiBase: cfg.apiBase, roomId: cfg.roomId, protocolName: cfg.protocolName)
        danmus = list.sorted { $0.time < $1.time }
        cursor = 0
    }
}