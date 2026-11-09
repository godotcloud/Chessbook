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
    case smartCompact = "smart_compact"
    case bilingual = "bilingual"
    case subtitleOnly = "subtitle_only"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .smartCompact:
            return "清爽中文替换 + [🔊朗读] / [原文] 按钮 (推荐)"
        case .bilingual:
            return "网页内上下双语同时显示 + [🔊朗读]"
        case .subtitleOnly:
            return "不改动网页·仅悬浮窗看译文与朗读"
        }
    }

    var shortName: String {
        switch self {
        case .smartCompact: return "清爽中文"
        case .bilingual: return "双语同显"
        case .subtitleOnly: return "仅悬浮窗"
        }
    }
}
