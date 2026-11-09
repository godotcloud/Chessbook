# LichessStudy Hybrid v3.0 — 原生壳 + WKWebView + JS 注入实时研习翻译

本版本采用 **SwiftUI 原生导航壳 + `WKWebView` 完整复用 Lichess 网页版 + 注入式 JS 桥接器 (`WKScriptMessageHandler`)** 架构：

1. **100% 原汁原味的 Lichess 体验**：直接复用 `lichess.org` 官方棋盘 (`chessground`)、音效、预走棋 (Premove)、在线寻局、锦标赛、每日战术谜题以及内置的 Stockfish WASM 本地/云端分析引擎。
2. **注入式 JS 实时拦截翻译 (`LichessWebBridge.swift`)**：
   - 自动注入 `MutationObserver` 脚本监听 Lichess 研习页面的 `.study__comments`（棋评框）、`.gamebook .comment`（互动教学提示）、`.tview2 comment`（着法树内嵌注解）与 `.study__chapters h3`（研习章节标题），并在网页内直接渲染中英双语对照块。
   - 支持**划词即译**：在网页上选中任意英文段落，底部原生悬浮卡片立即显示中文精译。
   - 内置免配置多翻译源（GTX 极速神经翻译、Pollinations AI 大模型、Lingva、MyMemory）与国际象棋专业术语词库修正。
3. **SideStore 100% 兼容**：`CFBundleName` 与 `CFBundleDisplayName` 强制锁定为纯 ASCII 英文字符 `LichessStudy`（Bundle ID 为 `com.lichess.studyapp`），彻底杜绝 `appIdName` 报错。
