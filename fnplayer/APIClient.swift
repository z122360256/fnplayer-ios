import Foundation
import CryptoKit
// MARK: - 数据模型
struct DanmuItem: Identifiable {
    let id: Int
    let text: String
    let color: String
    let position: String
    let time: Double
}
struct NASItem: Identifiable {
    let id = UUID()
    let name: String
    let isDir: Bool
    let path: String
    let guid: String
    let url: URL?
}
// MARK: - 飞牛影视 API 客户端
/// 逆向自飞牛影视 Web 端（fnOS 影视 App，服务端 0.9.8）
/// - API 前缀：/v/api/v1（基础）、/v/api/v2（新版登录）
/// - 鉴权：authx 头 = nonce=xxx&timestamp=xxx&sign=SHA256(secret_path_nonce_ts_bodyHash_apiKey)
///   · 未登录：apiKey = 固定值
///   · 已登录：apiKey 位置改用用户 token
/// - 登录：POST /v/api/v2/user/loginByPassword，password = SHA256(明文)
enum FnAPI {
    // 逆向出的常量（来自官方 Web 前端 JS）
    static let secret = "NDzZTVxnRKP8Z0jXg1VAMonaG8akvh"
    static let apiKey = "16CCEB3D-AB42-077D-36A1-F355324E4237"
    static let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 20
        cfg.timeoutIntervalForResource = 60
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.httpShouldSetCookies = true
        return URLSession(configuration: cfg)
    }()
    // MARK: 基础工具
    static func sha256Hex(_ s: String) -> String {
        let digest = SHA256.hash(data: Data(s.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
    /// 规范化 base：补协议、去尾斜杠
    static func normalizeBase(_ raw: String) -> String {
        var b = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if b.isEmpty { return "" }
        if !b.lowercased().hasPrefix("http://") && !b.lowercased().hasPrefix("https://") {
            b = "http://" + b
        }
        while b.hasSuffix("/") { b.removeLast() }
        return b
    }
    /// 构造 authx 签名头
    /// - Parameters:
    ///   - path: 参与签名的路径（含 /v/api/vX 前缀，不含 query）
    ///   - method: HTTP 方法
    ///   - bodyString: 请求体字符串（GET 传空）
    ///   - query: GET 查询参数（参与签名，按 key 排序）
    ///   - token: 已登录时传入，参与签名（替代固定 apiKey）
    static func authxHeader(
        path: String,
        method: String,
        bodyString: String,
        query: [String: String] = [:],
        token: String? = nil
    ) -> String {
        let isGet = method.uppercased() == "GET"
        var payload = ""
        if isGet {
            // GET：按 key 排序拼接 query，再 SHA256
            let sorted = query.keys.sorted()
            let parts = sorted.map { k -> String in
                let v = query[k] ?? ""
                let enc = v.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? v
                return "\(k)=\(enc)"
            }
            payload = parts.joined(separator: "&")
        } else {
            payload = bodyString
        }
        let bodyHash = sha256Hex(payload)
        let nonce = String(Int.random(in: 100000...999999))
        let ts = String(Int(Date().timeIntervalSince1970 * 1000))
        // 已登录用 token 参与签名，未登录用固定 apiKey
        let key = (token?.isEmpty == false) ? token! : apiKey
        let raw = [secret, path, nonce, ts, bodyHash, key].joined(separator: "_")
        let sign = sha256Hex(raw)
        return "nonce=\(nonce)&timestamp=\(ts)&sign=\(sign)"
    }
    /// 统一请求
    /// - prefix: "/v/api/v1" 或 "/v/api/v2"
    static func request(
        base: String,
        prefix: String,
        path: String,
        method: String = "GET",
        query: [String: String] = [:],
        jsonBody: [String: Any]? = nil,
        token: String? = nil
    ) async -> (status: Int, data: Data?, error: String?) {
        let b = normalizeBase(base)
        guard !b.isEmpty else { return (-1, nil, "服务地址为空") }
        let fullPath = prefix + path
        var urlStr = b + fullPath
        if !query.isEmpty {
            let qs = query.map { k, v in
                let enc = v.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? v
                return "\(k)=\(enc)"
            }.joined(separator: "&")
            urlStr += "?" + qs
        }
        guard let url = URL(string: urlStr) else { return (-1, nil, "地址无效：\(urlStr)") }
        var bodyStr = ""
        if let jb = jsonBody {
            if let d = try? JSONSerialization.data(withJSONObject: jb, options: [.sortedKeys]),
               let s = String(data: d, encoding: .utf8) {
                bodyStr = s
            }
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15",
                     forHTTPHeaderField: "User-Agent")
        req.setValue(b + "/v/", forHTTPHeaderField: "Referer")
        req.setValue(b, forHTTPHeaderField: "Origin")
        req.setValue(
            authxHeader(path: fullPath, method: method, bodyString: bodyStr, query: query, token: token),
            forHTTPHeaderField: "authx"
        )
        if let t = token, !t.isEmpty {
            req.setValue(t, forHTTPHeaderField: "Authorization")
        }
        if !bodyStr.isEmpty {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = bodyStr.data(using: .utf8)
        }
        do {
            let (data, resp) = try await session.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            return (code, data, nil)
        } catch {
            return (-1, nil, friendlyError(error))
        }
    }
    static func friendlyError(_ e: Error) -> String {
        let ns = e as NSError
        switch ns.code {
        case NSURLErrorCannotConnectToHost, NSURLErrorCannotFindHost:
            return "无法连接到服务器，请检查地址与端口是否正确"
        case NSURLErrorTimedOut:
            return "连接超时，请检查网络或地址"
        case NSURLErrorNotConnectedToInternet:
            return "设备未联网"
        case NSURLErrorAppTransportSecurityRequiresSecureConnection:
            return "iOS 安全策略阻止了 HTTP 请求"
        default:
            return "网络错误：\(ns.localizedDescription)"
        }
    }
    // MARK: 登录
    struct LoginResult {
        let ok: Bool
        let token: String
        let message: String
        let serverVersion: String
    }
    static func login(base: String, user: String, pass: String) async -> LoginResult {
        let b = normalizeBase(base)
        guard !b.isEmpty else {
            return LoginResult(ok: false, token: "", message: "请填写服务地址", serverVersion: "")
        }
        guard !user.isEmpty else {
            return LoginResult(ok: false, token: "", message: "请填写账号", serverVersion: "")
        }
        // 先探版本（同时验证签名与连通性）
        var ver = ""
        let vr = await request(base: b, prefix: "/v/api/v1", path: "/sys/version")
        if let d = vr.data,
           let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
           let dd = j["data"] as? [String: Any],
           let v = dd["version"] as? String {
            ver = v
        } else if vr.status < 0 {
            return LoginResult(ok: false, token: "", message: vr.error ?? "无法连接", serverVersion: "")
        }
        let pwdHash = sha256Hex(pass)
        let body: [String: Any] = [
            "username": user,
            "password": pwdHash,
            "app_name": "trimemedia-web"
        ]
        // 依次尝试：v2 前缀 → v1 前缀 → legacy /login
        let attempts: [(String, String)] = [
            ("/v/api/v2", "/user/loginByPassword"),
            ("/v/api/v1", "/user/loginByPassword"),
            ("/v/api/v1", "/login"),
        ]
        var lastMsg = "登录失败"
        for (prefix, path) in attempts {
            let r = await request(base: b, prefix: prefix, path: path, method: "POST", jsonBody: body)
            guard let data = r.data else {
                lastMsg = r.error ?? "网络错误"
                continue
            }
            guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            let code = (j["code"] as? Int) ?? 0
            let msg = (j["msg"] as? String) ?? ""
            if code == 0, let dd = j["data"] as? [String: Any],
               let tk = (dd["token"] as? String) ?? (dd["access_token"] as? String), !tk.isEmpty {
                return LoginResult(ok: true, token: tk, message: "连接成功 ✓", serverVersion: ver)
            }
            // 翻译错误码
            switch code {
            case -15:
                lastMsg = "账号或密码错误。请确认这是「飞牛影视」的登录账号密码（不是 fnOS 系统管理员账号），并先到网页端试登一次。"
            case -1:
                lastMsg = "服务端不接受该登录方式（版本不匹配）"
            case -4:
                lastMsg = "服务端处理异常，请稍后重试"
            case -2:
                lastMsg = "认证失败"
            case -16:
                lastMsg = "权限不足"
            default:
                if !msg.isEmpty { lastMsg = msg }
            }
        }
        return LoginResult(ok: false, token: "", message: lastMsg, serverVersion: ver)
    }
    // MARK: 媒体库
    /// 拉取媒体库列表（需登录 token）
    static func fetchLibraries(base: String, token: String) async -> [NASItem] {
        let candidates = ["/mediadb/list", "/mdb/list", "/library/list"]
        for path in candidates {
            let r = await request(base: base, prefix: "/v/api/v1", path: path, token: token)
            if let d = r.data {
                if let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                   let c = j["code"] as? Int, c == 5000 {
                    continue   // 签名/权限问题，换下一个
                }
                if let items = parseMediaList(d), !items.isEmpty {
                    return items
                }
            }
        }
        return []
    }
    /// 拉取某个库下的内容
    static func fetchItems(base: String, token: String, libraryGuid: String, page: Int = 0) async -> [NASItem] {
        let q: [String: String] = [
            "library_guid": libraryGuid,
            "page": String(page),
            "page_size": "100",
        ]
        let candidates = ["/item/list", "/media/list", "/video/list", "/movie/list"]
        for path in candidates {
            let r = await request(base: base, prefix: "/v/api/v1", path: path, query: q, token: token)
            if let d = r.data, let items = parseMediaList(d), !items.isEmpty {
                return items
            }
        }
        return []
    }
    /// 兼容多种返回结构
    static func parseMediaList(_ data: Data) -> [NASItem]? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) else { return nil }
        var raw: [Any] = []
        if let arr = obj as? [Any] {
            raw = arr
        } else if let dict = obj as? [String: Any] {
            if let d = dict["data"] as? [Any] {
                raw = d
            } else if let d = dict["data"] as? [String: Any] {
                for k in ["list", "items", "records", "data", "medias"] {
                    if let a = d[k] as? [Any] { raw = a; break }
                }
            } else {
                for k in ["list", "items", "records", "medias"] {
                    if let a = dict[k] as? [Any] { raw = a; break }
                }
            }
        }
        guard !raw.isEmpty else { return nil }
        var out: [NASItem] = []
        for it in raw {
            guard let d = it as? [String: Any] else { continue }
            let name = (d["title"] as? String) ?? (d["name"] as? String)
                ?? (d["file_name"] as? String) ?? (d["filename"] as? String) ?? ""
            guard !name.isEmpty else { continue }
            let guid = (d["guid"] as? String) ?? (d["id"] as? String) ?? ""
            var isDir = false
            if let t = d["type"] as? String {
                isDir = ["folder", "dir", "library", "season", "tv", "collection"].contains(t.lowercased())
            }
            if let b = d["is_dir"] as? Bool { isDir = b }
            let path = (d["path"] as? String) ?? ""
            var url: URL? = nil
            if let s = (d["play_url"] as? String) ?? (d["url"] as? String) ?? (d["stream_url"] as? String) {
                url = URL(string: s)
            }
            out.append(NASItem(name: name, isDir: isDir, path: path, guid: guid, url: url))
        }
        return out.isEmpty ? nil : out
    }
    /// 获取播放地址
    static func resolvePlayURL(base: String, token: String, guid: String) async -> URL? {
        let candidates: [(String, [String: String])] = [
            ("/play/info", ["guid": guid]),
            ("/video/play", ["guid": guid]),
            ("/item/play", ["guid": guid]),
            ("/media/play", ["guid": guid]),
        ]
        for (path, q) in candidates {
            let r = await request(base: base, prefix: "/v/api/v1", path: path, query: q, token: token)
            guard let d = r.data,
                  let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { continue }
            if let urlStr = findPlayURL(j), let u = URL(string: urlStr) {
                return u
            }
        }
        return nil
    }
    static func findPlayURL(_ obj: Any) -> String? {
        if let d = obj as? [String: Any] {
            for k in ["play_url", "url", "stream_url", "src", "link", "play_link"] {
                if let s = d[k] as? String, s.lowercased().hasPrefix("http") { return s }
            }
            for v in d.values {
                if let s = findPlayURL(v) { return s }
            }
        }
        if let a = obj as? [Any] {
            for v in a {
                if let s = findPlayURL(v) { return s }
            }
        }
        return nil
    }
}
// MARK: - 弹幕 API
enum DanmuAPI {
    static func fetch(apiBase: String, roomId: String) async -> [DanmuItem] {
        var b = apiBase.trimmingCharacters(in: .whitespacesAndNewlines)
        while b.hasSuffix("/") { b.removeLast() }
        guard !b.isEmpty else { return [] }
        let urls = [
            "\(b)/api/v2?pid=\(roomId)",
            "\(b)/api/v2/\(roomId)",
            "\(b)/danmu?room=\(roomId)",
            "\(b)/api/danmu?room=\(roomId)",
        ]
        for u in urls {
            guard let url = URL(string: u) else { continue }
            var req = URLRequest(url: url)
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            if let (data, _) = try? await FnAPI.session.data(for: req) {
                let items = parse(data)
                if !items.isEmpty { return items }
            }
        }
        return []
    }
    static func parse(_ data: Data) -> [DanmuItem] {
        guard let obj = try? JSONSerialization.jsonObject(with: data) else { return [] }
        var raw: [Any] = []
        if let a = obj as? [Any] {
            raw = a
        } else if let d = obj as? [String: Any] {
            outer: for k in ["data", "list", "danmaku", "comments", "items"] {
                if let a = d[k] as? [Any] { raw = a; break }
                if let d2 = d[k] as? [String: Any] {
                    for k2 in ["list", "items", "data"] {
                        if let a = d2[k2] as? [Any] { raw = a; break outer }
                    }
                }
            }
        }
        var out: [DanmuItem] = []
        for (i, it) in raw.enumerated() {
            if let s = it as? String {
                out.append(DanmuItem(id: i, text: s, color: "#FFFFFF", position: "scroll", time: 0))
                continue
            }
            guard let d = it as? [String: Any] else { continue }
            let text = (d["text"] as? String) ?? (d["content"] as? String)
                ?? (d["m"] as? String) ?? (d["msg"] as? String) ?? ""
            guard !text.isEmpty else { continue }
            var color = (d["color"] as? String) ?? "#FFFFFF"
            if let c = d["color"] as? Int { color = String(format: "#%06X", c) }
            var pos = (d["position"] as? String) ?? (d["p"] as? String) ?? "scroll"
            if pos.count == 1 {
                switch pos {
                case "4": pos = "bottom"
                case "5": pos = "top"
                default: pos = "scroll"
                }
            }
            let time = (d["time"] as? Double) ?? Double((d["time"] as? Int) ?? 0)
            out.append(DanmuItem(id: i, text: text, color: color, position: pos, time: time))
        }
        return out
    }
    static func send(text: String, cfg: DanmuSettings) async -> Bool {
        var b = cfg.apiBase.trimmingCharacters(in: .whitespacesAndNewlines)
        while b.hasSuffix("/") { b.removeLast() }
        guard !b.isEmpty else { return false }
        let body: [String: Any] = [
            "text": text, "content": text, "color": "#FFFFFF",
            "position": "scroll", "room": cfg.roomId, "room_id": cfg.roomId,
            "nickname": cfg.nickname, "time": Date().timeIntervalSince1970
        ]
        for p in ["/api/v2", "/danmu", "/api/danmu", "/api/send"] {
            guard let u = URL(string: b + p) else { continue }
            var r = URLRequest(url: u)
            r.httpMethod = "POST"
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.httpBody = try? JSONSerialization.data(withJSONObject: body)
            if let (_, resp) = try? await FnAPI.session.data(for: r),
               let http = resp as? HTTPURLResponse, http.statusCode < 500 {
                return true
            }
        }
        return false
    }
}