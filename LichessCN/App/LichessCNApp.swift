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
            return "清爽中文替换 + 点击[原文]展开对照 (推荐·不挤占空间)"
        case .bilingual:
            return "网页内上下双语同时显示 (自动滚动防遮挡)"
        case .subtitleOnly:
            return "不改动网页·仅顶部/底部悬浮窗看译文"
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
