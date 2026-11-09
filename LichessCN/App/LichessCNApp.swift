import SwiftUI

@main
struct LichessCNApp: App {
    @StateObject private var appState = AppStateViewModel()

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(appState)
        }
    }
}

@MainActor
final class AppStateViewModel: ObservableObject {
    @AppStorage("lichess_api_token") var apiToken: String = ""
    @AppStorage("preferred_translation_provider") var selectedProviderRaw: String = TranslationProviderType.pollinationsLLM.rawValue
    @AppStorage("bilingual_study_mode") var showBilingualComments: Bool = true
    @AppStorage("auto_translate_study") var autoTranslateStudy: Bool = true
    @AppStorage("board_theme") var boardThemeRaw: String = BoardTheme.brown.rawValue

    @Published var accountUsername: String? = nil
    @Published var accountRatingSummary: String = "未登录（支持免登录浏览研习/谜题/TV/云分析）"

    var selectedProvider: TranslationProviderType {
        get { TranslationProviderType(rawValue: selectedProviderRaw) ?? .pollinationsLLM }
        set { selectedProviderRaw = newValue.rawValue }
    }

    var boardTheme: BoardTheme {
        get { BoardTheme(rawValue: boardThemeRaw) ?? .brown }
        set { boardThemeRaw = newValue.rawValue }
    }

    func verifyTokenIfPresent() async {
        let trimmed = apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            accountUsername = nil
            accountRatingSummary = "未配置 Token（公开功能可直接使用）"
            return
        }
        do {
            let profile = try await LichessAPIService.shared.fetchAccountProfile(token: trimmed)
            accountUsername = profile.username
            let rapid = profile.perfs?.rapid?.rating ?? 1500
            let blitz = profile.perfs?.blitz?.rating ?? 1500
            let puzzle = profile.perfs?.puzzle?.rating ?? 1500
            accountRatingSummary = "@\(profile.username) · 快棋 \(rapid) | 超快 \(blitz) | 谜题 \(puzzle)"
        } catch {
            accountUsername = nil
            accountRatingSummary = "Token 验证失败: \(error.localizedDescription)"
        }
    }
}
