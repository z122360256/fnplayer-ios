import Foundation
struct DanmuItem: Identifiable {
    let id: Int
    let text: String
    let color: String
    let position: String
    let time: Double
}
enum APIClient {
    static let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 20
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: cfg)
    }()
    // MARK: - 弹幕
    static func fetchDanmus(apiBase: String, roomId: String, protocolName: String) async -> [DanmuItem] {
        let base = apiBase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { return [] }
        var urls: [String] = []
        if protocolName == "him-v2" {
            urls = ["\(base)/api/v2?pid=\(roomId)", "\(base)/api/v2/\(roomId)"]
        } else {
            urls = ["\(base)/danmu?room=\(roomId)", "\(base)/api/danmu?room=\(roomId)"]
        }
        for u in urls {
            guard let url = URL(string: u) else { continue }
            if let (data, _) = try? await session.data(from: url) {
                let items = normalizeDanmu(data)
                if !items.isEmpty { return items }
            }
        }
        return []
    }
    static func normalizeDanmu(_ data: Data) -> [DanmuItem] {
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
            var color = (d["color"] as? String) ?? (d["c"] as? String) ?? "#FFFFFF"
            if let c = d["color"] as? Int { color = String(format: "#%06X", c) }
            var pos = (d["position"] as? String) ?? (d["p"] as? String) ?? "scroll"
            if pos.count == 1 {
                switch pos {
                case "4": pos = "bottom"
                case "5": pos = "top"
                default: pos = "scroll"
                }
            }
            let time = doubleOf(d["time"]) ?? doubleOf(d["t"]) ?? doubleOf(d["stime"]) ?? 0
            let id = (d["id"] as? Int) ?? i
            out.append(DanmuItem(id: id, text: text, color: color, position: pos, time: time))
        }
        return out
    }
    static func doubleOf(_ v: Any?) -> Double? {
        if let d = v as? Double { return d }
        if let i = v as? Int { return Double(i) }
        if let s = v as? String { return Double(s) }
        return nil
    }
    static func sendDanmu(text: String, cfg: DanmuSettings) async {
        var base = cfg.apiBase.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        guard !base.isEmpty else { return }
        let endpoints = ["/api/v2", "/danmu", "/api/danmu", "/api/send"]
        let body: [String: Any] = [
            "text": text, "content": text, "color": "#FFFFFF",
            "position": "scroll", "room": cfg.roomId, "room_id": cfg.roomId,
            "nickname": cfg.nickname, "time": Date().timeIntervalSince1970
        ]
        for p in endpoints {
            guard let u = URL(string: base + p) else { continue }
            var r = URLRequest(url: u)
            r.httpMethod = "POST"
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.httpBody = try? JSONSerialization.data(withJSONObject: body)
            if let (_, resp) = try? await session.data(for: r),
               let http = resp as? HTTPURLResponse, http.statusCode < 500 {
                return
            }
        }
    }
}
// MARK: - 飞牛 NAS
enum NASClient {
    static func login(base: String, user: String, pass: String) async -> (ok: Bool, token: String, message: String) {
        let endpoints = ["/api/v1/auth/login", "/v1/user/login", "/api/user/login"]
        for p in endpoints {
            guard let u = URL(string: base + p) else { continue }
            var r = URLRequest(url: u)
            r.httpMethod = "POST"
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.httpBody = try? JSONSerialization.data(withJSONObject: ["username": user, "password": pass])
            guard let (data, resp) = try? await APIClient.session.data(for: r),
                  let http = resp as? HTTPURLResponse else { continue }
            if http.statusCode >= 500 { continue }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            let token = findToken(json) ?? ""
            var success: Bool
            if let b = json["success"] as? Bool { success = b }
            else if let n = json["success"] as? Int { success = n != 0 }
            else if let c = json["code"] as? Int { success = c == 0 || c == 200 }
            else { success = !token.isEmpty && http.statusCode < 400 }
            if success {
                return (true, token, "连接成功 ✓")
            } else {
                let m = (json["message"] as? String) ?? (json["msg"] as? String) ?? "账号或密码错误"
                return (false, "", m)
            }
        }
        return (false, "", "无法连接飞牛服务，请确认地址如 http://192.168.1.10:5666 且手机与 NAS 在同一网络")
    }
    static func findToken(_ obj: Any) -> String? {
        if let d = obj as? [String: Any] {
            for k in ["token", "access_token", "accessToken", "jwt"] {
                if let s = d[k] as? String, !s.isEmpty { return s }
            }
            for v in d.values { if let t = findToken(v) { return t } }
        }
        if let a = obj as? [Any] {
            for v in a { if let t = findToken(v) { return t } }
        }
        return nil
    }
    static func list(base: String, token: String, path: String) async -> [NASItem] {
        let endpoints = ["/api/v1/media/list", "/v1/media/list", "/api/v1/file/list", "/api/file/list"]
        for p in endpoints {
            guard var comps = URLComponents(string: base + p) else { continue }
            var q: [URLQueryItem] = []
            if !path.isEmpty { q.append(URLQueryItem(name: "path", value: path)) }
            if !token.isEmpty { q.append(URLQueryItem(name: "token", value: token)) }
            comps.queryItems = q
            guard let u = comps.url else { continue }
            guard let (data, resp) = try? await APIClient.session.data(from: u),
                  let http = resp as? HTTPURLResponse, http.statusCode < 400 else { continue }
            let parsed = parseList(data, currentPath: path)
            if !parsed.isEmpty { return parsed }
        }
        return []
    }
    static func parseList(_ data: Data, currentPath: String) -> [NASItem] {
        guard let obj = try? JSONSerialization.jsonObject(with: data) else { return [] }
        var raw: [Any] = []
        if let a = obj as? [Any] {
            raw = a
        } else if let d = obj as? [String: Any] {
            outer: for k in ["data", "list", "items", "files", "medias", "rows"] {
                if let a = d[k] as? [Any] { raw = a; break }
                if let d2 = d[k] as? [String: Any] {
                    for k2 in ["list", "items", "files", "records"] {
                        if let a = d2[k2] as? [Any] { raw = a; break outer }
                    }
                }
            }
        }
        var out: [NASItem] = []
        for it in raw {
            if let s = it as? String {
                out.append(NASItem(name: s, isDir: !isVideoFile(s), path: join(currentPath, s), url: nil))
                continue
            }
            guard let d = it as? [String: Any] else { continue }
            let name = (d["name"] as? String) ?? (d["filename"] as? String)
                ?? (d["title"] as? String) ?? (d["file_name"] as? String) ?? ""
            guard !name.isEmpty else { continue }
            var isDir = false
            if let b = d["is_dir"] as? Bool { isDir = b }
            else if let b = d["isDir"] as? Bool { isDir = b }
            else if let t = d["type"] as? String { isDir = (t == "folder" || t == "dir" || t == "directory") }
            else if let k = d["kind"] as? String { isDir = (k == "folder") }
            let pathStr = (d["path"] as? String) ?? (d["full_path"] as? String) ?? join(currentPath, name)
            var playURL: URL? = nil
            if let s = (d["url"] as? String) ?? (d["play_url"] as? String) ?? (d["stream_url"] as? String) {
                playURL = URL(string: s)
            }
            out.append(NASItem(name: name, isDir: isDir, path: pathStr, url: playURL))
        }
        return out
    }
    static func isVideoFile(_ name: String) -> Bool {
        let exts = ["mp4", "m4v", "mov", "mkv", "webm", "m3u8", "ts", "flv", "avi"]
        guard let ext = name.split(separator: ".").last.map(String.init)?.lowercased() else { return false }
        return exts.contains(ext)
    }
    static func join(_ a: String, _ b: String) -> String {
        var base = a
        while base.hasSuffix("/") { base.removeLast() }
        return base.isEmpty ? b : base + "/" + b
    }
}