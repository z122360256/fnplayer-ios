import SwiftUI
import AVKit
func fmtTime(_ t: Double) -> String {
    guard t.isFinite, t >= 0 else { return "00:00" }
    let s = Int(t) % 3600
    return String(format: "%02d:%02d", s / 60, s % 60)
}
// MARK: - 登录
struct LoginView: View {
    @ObservedObject var state: AppState
    @State private var base = UserDefaults.standard.string(forKey: "fn_base") ?? ""
    @State private var user = ""
    @State private var pass = ""
    @State private var directURL = ""
    @State private var msg = ""
    @State private var busy = false
    var body: some View {
        Form {
            Section("连接飞牛 NAS") {
                TextField("服务地址 http://192.168.1.10:5666", text: $base)
                    .keyboardType(.URL).autocorrectionDisabled().textInputAutocapitalization(.never)
                TextField("账号", text: $user)
                SecureField("密码", text: $pass)
                Button(busy ? "连接中…" : "连接") {
                    Task { await connect() }
                }
                .disabled(busy)
                if !msg.isEmpty {
                    Text(msg).font(.footnote).foregroundColor(.secondary)
                }
            }
            Section("或直接播放视频链接") {
                TextField("http://nas/video.mp4 或 .m3u8", text: $directURL)
                    .keyboardType(.URL).autocorrectionDisabled().textInputAutocapitalization(.never)
                Button("播放直链") { playDirect() }
            }
            Section {
                Button("弹幕设置") { state.page = .settings }
            }
        }
        .navigationTitle("飞牛弹幕")
    }
    private func connect() async {
        busy = true
        msg = "连接中…"
        var b = base.trimmingCharacters(in: .whitespacesAndNewlines)
        while b.hasSuffix("/") { b.removeLast() }
        let r = await NASClient.login(base: b, user: user, pass: pass)
        if r.ok {
            state.baseURL = b
            state.token = r.token
            UserDefaults.standard.set(b, forKey: "fn_base")
            UserDefaults.standard.set(r.token, forKey: "fn_token")
            msg = "连接成功 ✓"
            state.page = .library
        } else {
            msg = r.message
        }
        busy = false
    }
    private func playDirect() {
        guard let u = URL(string: directURL.trimmingCharacters(in: .whitespaces)) else { return }
        state.playerURL = u
        state.playerTitle = u.lastPathComponent
        state.page = .player
    }
}
// MARK: - 媒体库
struct LibraryView: View {
    @ObservedObject var state: AppState
    @State private var items: [NASItem] = []
    @State private var path = ""
    @State private var loading = false
    @State private var err = ""
    var body: some View {
        List(items) { it in
            Button { Task { await tap(it) } } label: {
                HStack(spacing: 12) {
                    Text(it.isDir ? "📁" : (NASClient.isVideoFile(it.name) ? "🎬" : "📄"))
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(it.name).lineLimit(1).foregroundColor(.primary)
                        if !it.isDir && it.url == nil {
                            Text("将尝试默认接口播放").font(.caption2).foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                }
            }
        }
        .overlay {
            if loading { ProgressView() }
            if !err.isEmpty && items.isEmpty {
                Text(err).font(.footnote).foregroundColor(.secondary).padding()
            }
        }
        .navigationTitle("媒体库")
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("退出") { state.page = .login }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("⚙️") { state.page = .settings }
            }
        }
        .task { await load() }
    }
    private func load() async {
        loading = true
        err = ""
        let r = await NASClient.list(base: state.baseURL, token: state.token, path: path)
        items = r
        if r.isEmpty {
            err = "未能读取媒体库列表（飞牛私有接口未完全公开，持续适配中）。可先回首页用「播放直链」播放 NAS 视频。"
        }
        loading = false
    }
    private func tap(_ it: NASItem) async {
        if it.isDir {
            path = it.path
            await load()
        } else {
            var url = it.url
            if url == nil {
                let enc = it.path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? it.path
                var s = "\(state.baseURL)/api/v1/file/download?path=\(enc)"
                if !state.token.isEmpty { s += "&token=\(state.token)" }
                url = URL(string: s)
            }
            if let u = url {
                state.playerURL = u
                state.playerTitle = it.name
                state.page = .player
            }
        }
    }
}
// MARK: - 播放器
struct PlayerView: View {
    @ObservedObject var state: AppState
    @StateObject private var model = PlayerModel()
    @State private var sendText = ""
    @State private var started = false
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                VideoPlayer(player: model.player)
                DanmakuView(engine: model.danmaku, settings: state.danmuSettings)
                    .allowsHitTesting(false)
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .background(Color.black)
            HStack(spacing: 10) {
                Text(fmtTime(model.currentTime)).font(.caption).monospacedDigit()
                Slider(value: Binding(
                    get: { model.duration > 0 ? model.currentTime / model.duration : 0 },
                    set: { f in model.seek(to: f * model.duration) }
                ))
                Text(fmtTime(model.duration)).font(.caption).monospacedDigit()
                Button {
                    model.togglePlay()
                } label: {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            HStack(spacing: 8) {
                Button {
                    state.danmuSettings.enabled.toggle()
                } label: {
                    Text(state.danmuSettings.enabled ? "弹幕 开" : "弹幕 关")
                        .font(.footnote)
                }
                TextField("发个弹幕…", text: $sendText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { sendDanmu() }
                Button("发送") { sendDanmu() }
                    .disabled(sendText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
            Spacer()
        }
        .navigationTitle(state.playerTitle.isEmpty ? "播放" : state.playerTitle)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("‹ 返回") { state.page = .library }
            }
        }
        .onAppear {
            if !started, let u = state.playerURL {
                started = true
                model.play(url: u)
            }
        }
        .task {
            await model.loadDanmus(cfg: state.danmuSettings)
        }
    }
    private func sendDanmu() {
        let t = sendText.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        if state.danmuSettings.apiBase.isEmpty {
            sendText = ""
            return
        }
        model.send(t, cfg: state.danmuSettings)
        sendText = ""
    }
}
struct DanmakuView: UIViewRepresentable {
    let engine: DanmakuCanvas
    let settings: DanmuSettings
    func makeUIView(context: Context) -> DanmakuCanvas { engine }
    func updateUIView(_ uiView: DanmakuCanvas, context: Context) {
        uiView.config = .from(settings: settings)
    }
}
// MARK: - 设置
struct SettingsView: View {
    @ObservedObject var state: AppState
    @State private var s = DanmuSettings.load()
    @State private var msg = ""
    @State private var testing = false
    var body: some View {
        Form {
            Section("弹幕 API（Docker danmu-api）") {
                TextField("API 地址 http://192.168.1.10:8080", text: $s.apiBase)
                    .keyboardType(.URL).autocorrectionDisabled().textInputAutocapitalization(.never)
                TextField("房间 / 视频 ID", text: $s.roomId)
                TextField("昵称", text: $s.nickname)
                Picker("接口协议", selection: $s.protocolName) {
                    Text("him-v2（B站风格）").tag("him-v2")
                    Text("通用").tag("generic")
                }
                Button(testing ? "测试中…" : "测试连通") {
                    Task { await test() }
                }
                .disabled(testing)
                if !msg.isEmpty {
                    Text(msg).font(.footnote).foregroundColor(.secondary)
                }
            }
            Section("弹幕显示") {
                Toggle("启用弹幕", isOn: $s.enabled)
                HStack {
                    Text("字号").frame(width: 60, alignment: .leading)
                    Slider(value: $s.fontSize, in: 12...32, step: 1)
                    Text("\(Int(s.fontSize))").monospacedDigit().frame(width: 32)
                }
                HStack {
                    Text("速度").frame(width: 60, alignment: .leading)
                    Slider(value: $s.duration, in: 3...15, step: 1)
                    Text("\(Int(s.duration))s").monospacedDigit().frame(width: 40)
                }
                HStack {
                    Text("不透明").frame(width: 60, alignment: .leading)
                    Slider(value: $s.opacity, in: 0.1...1, step: 0.05)
                    Text("\(Int(s.opacity * 100))%").monospacedDigit().frame(width: 44)
                }
                HStack {
                    Text("区域").frame(width: 60, alignment: .leading)
                    Slider(value: $s.areaRatio, in: 0.2...1, step: 0.05)
                    Text("\(Int(s.areaRatio * 100))%").monospacedDigit().frame(width: 44)
                }
                TextField("屏蔽词（逗号分隔）", text: $s.blocked)
            }
            Section {
                Button("保存设置") {
                    s.save()
                    state.danmuSettings = s
                    msg = "已保存 ✓"
                }
                Button("返回") {
                    state.page = state.playerURL == nil ? .login : .library
                }
            }
        }
        .navigationTitle("设置")
    }
    private func test() async {
        testing = true
        var b = s.apiBase.trimmingCharacters(in: .whitespacesAndNewlines)
        while b.hasSuffix("/") { b.removeLast() }
        guard let u = URL(string: b) else {
            msg = "地址无效"
            testing = false
            return
        }
        do {
            let (_, resp) = try await APIClient.session.data(from: u)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            msg = "连接成功 HTTP \(code) ✓"
        } catch {
            msg = "失败：\(error.localizedDescription)"
        }
        testing = false
    }
}