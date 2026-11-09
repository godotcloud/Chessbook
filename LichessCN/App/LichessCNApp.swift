import SwiftUI

@main
struct LichessCNApp: App {
    @StateObject private var bridgeManager = HybridTranslationBridgeManager()

    var body: some Scene {
        WindowGroup {
            HybridRootView()
                .environmentObject(bridgeManager)
        }
    }
}

enum InlineInjectionMode: String, CaseIterable, Identifiable {
    case bilingual = "bilingual"
    case replaceWithChinese = "replace"
    case subtitleOnly = "subtitle_only"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bilingual:
            return "网页内嵌中英双语 (推荐)"
        case .replaceWithChinese:
            return "网页直接替换为中文"
        case .subtitleOnly:
            return "仅底部原生悬浮窗显示译文"
        }
    }
}
