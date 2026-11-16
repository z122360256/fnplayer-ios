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
    @State private var user = UserDefaults.standard.string(forKey: "fn_user") ?? ""
    @State private var pass = ""
    @State private var directURL = ""
    @State private var msg = ""
    @State private var busy = false
    @State private var showHelp = false
    var body: some View {
        Form {
            Section {
                TextField("服务地址，如 171.213.177.61:7799", text: $base)
                    .keyboardType(.URL).autocorrectionDisabled().textInputAutocapitalization(.never)
                TextField("账号", text: $user)
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
                SecureField("密码（飞牛影视登录密码）", text: $pass)
                Button(busy ? "连接中…" : "连接飞牛影视") {
                    Task { await connect() }
                }
                .disabled(busy)
                if !msg.isEmpty {
                    Text(msg)
                        .font(.footnote)
                        .foregroundColor(msg.contains("成功") ? .green : .orange)
                }
            } header: {
                Text("连接飞牛影视")
            } footer: {
                Text("地址填 IP:端口 即可，App 会自动补 http://。端口通常是 7799（影视）或 5666（系统）。")
            }
            Section("或直接播放视频链接") {
                TextField("http://nas/video.mp4 或 .m3u8", text: $directURL)
                    .keyboardType(.URL).autocorrectionDisabled().textInputAutocapitalization(.never)
                Button("播放直链") { playDirect() }
            }
            Section {
                Button("弹幕设置") { state.page = .settings }
                Button("连接不上？看看说明") { showHelp = true }
            }
        }
        .navigationTitle("飞牛弹幕播放器")
        .alert("连接说明", isPresented: $showHelp) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("""
            1. 地址只填 IP:端口，例如 171.213.177.61:7799
            2. 账号密码用「飞牛影视」的登录账号（不是 fnOS 系统管理员账号）
            3. 手机需能访问该地址（同一网络或已做端口映射）
            4. 若提示"账号或密码错误"，请到飞牛影视网页端确认能登录
            """)
        }
    }
    private func connect() async {
        busy = true
        msg = "正在连接…"
        let r = await FnAPI.login(base: base, user: user, pass: pass)
        if r.ok {
            let b = FnAPI.normalizeBase(base)
            state.baseURL = b
            state.token = r.token
            state.serverVersion = r.serverVersion
            UserDefaults.standard.set(b, forKey: "fn_base")
            UserDefaults.standard.set(user, forKey: "fn_user")
            UserDefaults.standard.set(r.token, forKey: "fn_token")
            UserDefaults.standard.set(r.serverVersion, forKey: "fn_ver")
            msg = "连接成功 ✓ 服务端 \(r.serverVersion)"
            state.page = .library
        } else {
            msg = r.message
        }
        busy = false
    }
    private func playDirect() {
        var s = directURL.trimmingCharacters(in: .whitespaces)
        if !s.lowercased().hasPrefix("http") { s = "http://" + s }
        guard let u = URL(string: s) else {
            msg = "链接格式不正确"
            return
        }
        state.playerURL = u
        state.playerTitle = u.lastPathComponent
        state.page = .player
    }
}
// MARK: - 媒体库
struct LibraryView: View {
    @ObservedObject var state: AppState
    @State private var libraries: [NASItem] = []
    @State private var items: [NASItem] = []
    @State private var currentLib: NASItem?
    @State private var loading = false
    @State private var err = ""
    var body: some View {
        List {
            if currentLib != nil {
                Section {
                    Button {
                        currentLib = nil
                        items = []
                    } label: {
                        Label("返回媒体库列表", systemImage: "chevron.left")
                    }
                }
            }
            if currentLib == nil {
                Section("媒体库") {
                    if libraries.isEmpty && !loading {
                        Text(err.isEmpty ? "暂无媒体库" : err)
                            .font(.footnote).foregroundColor(.secondary)
                    }
                    ForEach(libraries) { lib in
                        Button {
                            Task { await openLib(lib) }
                        } label: {
                            HStack {
                                Text("📚")
                                Text(lib.name).foregroundColor(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }
                }
            } else {
                Section(currentLib?.name ?? "") {
                    if items.isEmpty && !loading {
                        Text("该库暂无内容，或接口格式待适配")
                            .font(.footnote).foregroundColor(.secondary)
                    }
                    ForEach(items) { it in
                        Button {
                            Task { await tap(it) }
                        } label: {
                            HStack(spacing: 10) {
                                Text(it.isDir ? "📁" : "🎬").font(.title3)
                                Text(it.name).lineLimit(1).foregroundColor(.primary)
                                Spacer()
                            }
                        }
                    }
                }
            }
        }
        .overlay { if loading { ProgressView() } }
        .navigationTitle("媒体库")
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("退出") {
                    state.token = ""
                    state.page = .login
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("⚙️") { state.page = .settings }
            }
        }
        .task { await loadLibraries() }
    }
    private func loadLibraries() async {
        guard libraries.isEmpty else { return }
        loading = true
        err = ""
        let r = await FnAPI.fetchLibraries(base: state.baseURL, token: state.token)
        libraries = r
        if r.isEmpty {
            err = "未能读取媒体库。可能该账号无媒体库权限，或服务端接口版本不同。\n可先回首页用「播放直链」播放。"
        }
        loading = false
    }
    private func openLib(_ lib: NASItem) async {
        currentLib = lib
        loading = true
        let r = await FnAPI.fetchItems(base: state.baseURL, token: state.token, libraryGuid: lib.guid)
        items = r
        loading = false
    }
    private func tap(_ it: NASItem) async {
        if it.isDir {
            loading = true
            let r = await FnAPI.fetchItems(base: state.baseURL, token: state.token, libraryGuid: it.guid)
            if !r.isEmpty { items = r }
            loading = false
            return
        }
        loading = true
        var url = it.url
        if url == nil, !it.guid.isEmpty {
            url = await FnAPI.resolvePlayURL(base: state.baseURL, token: state.token, guid: it.guid)
        }
        loading = false
        if let u = url {
            state.playerURL = u
            state.playerTitle = it.name
            state.page = .player
        } else {
            err = "无法解析播放地址"
        }
    }
}
// MARK: - 播放器
struct PlayerView: View {
    @ObservedObject var state: AppState
    @StateObject private var model = PlayerModel()
    @State private var sendText = ""
    @State private var started = false
    @State private var loadMsg = ""
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
                Button { model.togglePlay() } label: {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            HStack(spacing: 8) {
                Button {
                    state.danmuSettings.enabled.toggle()
                } label: {
                    Text(state.danmuSettings.enabled ? "弹幕 开" : "弹幕 关").font(.footnote)
                }
                TextField("发个弹幕…", text: $sendText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { sendDanmu() }
                Button("发送") { sendDanmu() }
                    .disabled(sendText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
            if !loadMsg.isEmpty {
                Text(loadMsg).font(.caption2).foregroundColor(.secondary).padding(.bottom, 6)
            }
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
            let cfg = state.danmuSettings
            if cfg.apiBase.isEmpty {
                loadMsg = "未配置弹幕 API（可在设置页填写）"
                return
            }
            await model.loadDanmus(cfg: cfg)
            loadMsg = model.danmus.isEmpty
                ? "弹幕接口无数据（已连接 \(cfg.apiBase)）"
                : "已加载 \(model.danmus.count) 条弹幕"
        }
    }
    private func sendDanmu() {
        let t = sendText.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        guard !state.danmuSettings.apiBase.isEmpty else {
            loadMsg = "请先在设置页配置弹幕 API 地址"
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
            Section {
                TextField("API 地址，如 http://192.168.1.10:8080", text: $s.apiBase)
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
            } header: {
                Text("弹幕 API（Docker danmu-api）")
            } footer: {
                Text("需自行部署 danmu-api 服务；填好地址后点测试连通，再保存。")
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
                    state.page = state.token.isEmpty ? .login : .library
                }
            }
        }
        .navigationTitle("设置")
    }
    private func test() async {
        testing = true
        var b = s.apiBase.trimmingCharacters(in: .whitespacesAndNewlines)
        while b.hasSuffix("/") { b.removeLast() }
        guard !b.isEmpty, let u = URL(string: b) else {
            msg = "请填写有效地址"
            testing = false
            return
        }
        do {
            var req = URLRequest(url: u)
            req.timeoutInterval = 12
            let (_, resp) = try await FnAPI.session.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            msg = "连接成功 HTTP \(code) ✓"
        } catch {
            msg = "失败：\(FnAPI.friendlyError(error))"
        }
        testing = false
    }
}