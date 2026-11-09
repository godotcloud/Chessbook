import SwiftUI
#if canImport(Translation)
import Translation
#endif

struct HybridRootView: View {
    @EnvironmentObject var bridge: HybridTranslationBridgeManager

    @State private var showStudyQuickJumpSheet = false
    @State private var showTranslationSettingsSheet = false
    @State private var customURLOrStudyID: String = ""
    @State private var showSystemTranslationSheet = false

    var body: some View {
        VStack(spacing: 0) {
            // 1. Ultra-Slim 36pt Top Bar (Can be collapsed to full-screen with 1 tap)
            if !bridge.isCompactFullscreen {
                slimTopControlHeader
            }

            // 2. Full-Screen Lichess WKWebView (No bottom dock stealing vertical space!)
            ZStack(alignment: .bottom) {
                LichessHybridWebView(manager: bridge)

                // Floating restore pill when in fullscreen mode
                if bridge.isCompactFullscreen {
                    HStack {
                        Spacer()
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                bridge.isCompactFullscreen = false
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "character.bubble.fill")
                                Text("工具栏")
                            }
                            .font(.caption2.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                            .shadow(radius: 3)
                        }
                        .padding(.trailing, 12)
                        .padding(.bottom, 12)
                    }
                }

                // Optional floating subtitle overlay (only when user explicitly enables it)
                if bridge.showFloatingSubtitleCard && !bridge.activeOriginalComment.isEmpty {
                    floatingSubtitleOverlay
                        .padding(.horizontal, 10)
                        .padding(.bottom, 8)
                }
            }
        }
        .sheet(isPresented: $showStudyQuickJumpSheet) {
            studyQuickJumpSheetView
        }
        .sheet(isPresented: $showTranslationSettingsSheet) {
            translationSettingsSheetView
        }
    }

    // MARK: - Ultra-Slim 36pt Top Control Header
    private var slimTopControlHeader: some View {
        HStack(spacing: 8) {
            // Back / Forward
            Button {
                bridge.goBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 24, height: 28)
            }
            .disabled(!bridge.canGoBack)

            // Quick-Switch Lichess Modules Menu (Replaces bulky bottom bar!)
            Menu {
                Button {
                    bridge.navigateTo("https://lichess.org/study")
                } label: {
                    Label("研习中心 (Studies)", systemImage: "book.pages.fill")
                }
                Button {
                    bridge.navigateTo("https://lichess.org/")
                } label: {
                    Label("对局大厅 (Lobby)", systemImage: "checkerboard.rectangle")
                }
                Button {
                    bridge.navigateTo("https://lichess.org/training")
                } label: {
                    Label("战术谜题 (Puzzles)", systemImage: "puzzlepiece.extension.fill")
                }
                Button {
                    bridge.navigateTo("https://lichess.org/analysis")
                } label: {
                    Label("分析棋盘 (Analysis)", systemImage: "cpu.fill")
                }
                Button {
                    bridge.navigateTo("https://lichess.org/tv")
                } label: {
                    Label("大师直播 (Lichess TV)", systemImage: "tv.fill")
                }
                Divider()
                Button {
                    showStudyQuickJumpSheet = true
                } label: {
                    Label("输入研习 ID 或自定义网址...", systemImage: "magnifyingglass")
                }
                Button {
                    bridge.reload()
                } label: {
                    Label("刷新当前网页", systemImage: "arrow.clockwise")
                }
            } label: {
                HStack(spacing: 4) {
                    if bridge.isLoading || bridge.isTranslatingNow {
                        ProgressView()
                            .scaleEffect(0.65)
                    } else {
                        Image(systemName: "compass.drawing")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    Text(shortSectionTitle(bridge.currentURLString))
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(.secondarySystemBackground))
                .clipShape(Capsule())
            }
            .foregroundColor(.primary)

            Spacer(minLength: 4)

            // Quick Display Mode & Engine Menu
            Menu {
                Section("显示样式 (解决文字拥挤)") {
                    ForEach(InlineInjectionMode.allCases) { mode in
                        Button {
                            bridge.injectionMode = mode
                        } label: {
                            HStack {
                                Text(mode.displayName)
                                if bridge.injectionMode == mode {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
                Section("切换免费翻译源") {
                    ForEach(TranslationProviderType.allCases) { provider in
                        Button {
                            bridge.selectedProvider = provider
                        } label: {
                            HStack {
                                Text(provider.displayName)
                                if bridge.selectedProvider == provider {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
                Divider()
                Button {
                    bridge.triggerFullPageRescan()
                } label: {
                    Label("立即重新扫描翻译本页", systemImage: "bolt.fill")
                }
                Button {
                    showTranslationSettingsSheet = true
                } label: {
                    Label("更多翻译与悬浮窗设置...", systemImage: "slider.horizontal.3")
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "character.bubble.fill")
                        .font(.system(size: 11))
                    Text("\(bridge.lastUsedProviderBadge)·\(bridge.injectionMode.shortName)")
                        .font(.system(size: 11, weight: .bold))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(bridge.autoTranslateEnabled ? Color.accentColor.opacity(0.15) : Color(.secondarySystemBackground))
                .foregroundColor(bridge.autoTranslateEnabled ? .accentColor : .secondary)
                .clipShape(Capsule())
            }

            // 1-Tap Fullscreen Collapse Button
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    bridge.isCompactFullscreen = true
                }
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 26, height: 28)
            }
            .accessibilityLabel("隐藏顶部栏进入全屏")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color(.systemBackground))
        .overlay(Divider(), alignment: .bottom)
    }

    // MARK: - Optional Floating Subtitle Card
    private var floatingSubtitleOverlay: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label(
                    bridge.activeChapterTitle.isEmpty ? "当前棋评译文" : bridge.activeChapterTitle,
                    systemImage: "sparkles"
                )
                .font(.caption.bold())
                .foregroundColor(.accentColor)
                .lineLimit(1)

                Spacer()

                #if canImport(Translation)
                if #available(iOS 17.4, *), !bridge.activeOriginalComment.isEmpty {
                    Button {
                        showSystemTranslationSheet = true
                    } label: {
                        Image(systemName: "translate")
                            .font(.caption)
                    }
                    .translationPresentation(isPresented: $showSystemTranslationSheet, text: bridge.activeOriginalComment)
                }
                #endif

                Button {
                    withAnimation { bridge.showFloatingSubtitleCard = false }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Text(bridge.activeTranslatedComment.isEmpty ? bridge.activeOriginalComment : bridge.activeTranslatedComment)
                .font(.subheadline.weight(.medium))
                .foregroundColor(.primary)
                .lineLimit(4)
                .textSelection(.enabled)
        }
        .padding(10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 5, x: 0, y: 2)
    }

    private var studyQuickJumpSheetView: some View {
        NavigationStack {
            List {
                Section("输入 Lichess 研习 ID 或完整网址") {
                    HStack {
                        TextField("输入 8 位研习 ID (如 ZCPaIb70) 或 URL", text: $customURLOrStudyID)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("前往") {
                            let input = customURLOrStudyID.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !input.isEmpty else { return }
                            bridge.navigateTo(input)
                            showStudyQuickJumpSheet = false
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                Section("常用入口与热门研习") {
                    studyShortcutRow(
                        title: "卡罗-卡恩防御研习 (Caro-Kann Study)",
                        subtitle: "直接打开你刚才浏览的 ZCPaIb70 研习，检验全新清爽排版效果",
                        url: "https://lichess.org/study/ZCPaIb70"
                    )
                    studyShortcutRow(
                        title: "Lichess 热门研习广场",
                        subtitle: "浏览全球棋手创建的开局、中局与残局研习",
                        url: "https://lichess.org/study/all/popular"
                    )
                    studyShortcutRow(
                        title: "Silman 经典残局教程",
                        subtitle: "互动式残局训练，支持清爽中文替换与点击展开原文",
                        url: "https://lichess.org/study/wukLYIXj"
                    )
                }
            }
            .navigationTitle("研习与页面跳转")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { showStudyQuickJumpSheet = false }
                }
            }
        }
    }

    private func studyShortcutRow(title: String, subtitle: String, url: String) -> some View {
        Button {
            bridge.navigateTo(url)
            showStudyQuickJumpSheet = false
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundColor(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 3)
        }
    }

    private var translationSettingsSheetView: some View {
        NavigationStack {
            Form {
                Section("排版与防遮挡模式") {
                    Toggle("启用研习实时中文翻译", isOn: $bridge.autoTranslateEnabled)

                    Picker("网页内嵌样式", selection: $bridge.injectionModeRaw) {
                        ForEach(InlineInjectionMode.allCases) { mode in
                            Text(mode.displayName).tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.inline)

                    Toggle("额外开启底部悬浮字幕卡", isOn: $bridge.showFloatingSubtitleCard)
                }

                Section("免配置多翻译引擎切换") {
                    Picker("首选翻译源", selection: $bridge.selectedProviderRaw) {
                        ForEach(TranslationProviderType.allCases) { provider in
                            Text(provider.displayName).tag(provider.rawValue)
                        }
                    }
                    .pickerStyle(.inline)
                }
            }
            .navigationTitle("界面与翻译设置")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { showTranslationSettingsSheet = false }
                }
            }
        }
    }

    private func shortSectionTitle(_ urlStr: String) -> String {
        if urlStr.contains("/study") { return "研习中心" }
        if urlStr.contains("/training") { return "战术谜题" }
        if urlStr.contains("/analysis") { return "分析棋盘" }
        if urlStr.contains("/tv") { return "大师直播" }
        return "Lichess"
    }
}
