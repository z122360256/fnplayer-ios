import SwiftUI
enum AppPage { case login, library, player, settings }
struct DanmuSettings: Codable {
    var apiBase: String = ""
    var roomId: String = ""
    var nickname: String = "游客"
    var protocolName: String = "him-v2"
    var fontSize: Double = 18
    var duration: Double = 7
    var opacity: Double = 0.9
    var areaRatio: Double = 0.5
    var blocked: String = ""
    var enabled: Bool = true
    static let key = "danmu_settings"
    static func load() -> DanmuSettings {
        if let d = UserDefaults.standard.data(forKey: key),
           let s = try? JSONDecoder().decode(DanmuSettings.self, from: d) { return s }
        return DanmuSettings()
    }
    func save() {
        if let d = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(d, forKey: Self.key)
        }
    }
}
struct NASItem: Identifiable {
    let id = UUID()
    let name: String
    let isDir: Bool
    let path: String
    let url: URL?
}
@main
struct FnPlayerApp: App {
    var body: some Scene {
        WindowGroup { RootView() }
    }
}
final class AppState: ObservableObject {
    @Published var page: AppPage = .login
    @Published var baseURL: String = UserDefaults.standard.string(forKey: "fn_base") ?? ""
    @Published var token: String = UserDefaults.standard.string(forKey: "fn_token") ?? ""
    @Published var playerURL: URL?
    @Published var playerTitle: String = ""
    @Published var danmuSettings: DanmuSettings = DanmuSettings.load()
}
struct RootView: View {
    @StateObject private var state = AppState()
    var body: some View {
        NavigationStack {
            switch state.page {
            case .login: LoginView(state: state)
            case .library: LibraryView(state: state)
            case .player: PlayerView(state: state)
            case .settings: SettingsView(state: state)
            }
        }
    }
}