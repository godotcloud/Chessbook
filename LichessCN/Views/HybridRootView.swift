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
            // 1. Compact Native Top Bar
            topControlHeader

            // 2. Full-Featured Lichess.org WKWebView with Injected JS Translator
            ZStack(alignment: .bottom) {
                LichessHybridWebView(manager: bridge)
                    .ignoresSafeArea(edges: .bottom)

                // 3. Collapsible Real-Time Chinese Commentary Subtitle Overlay
                if bridge.showFloatingSubtitleCard && !bridge.activeOriginalComment.isEmpty {
                    floatingSubtitleOverlay
                        .padding(.horizontal, 10)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }

            // 4. Native Bottom Quick-Switch Navigation Bar
            bottomNavigationDock
        }
        .sheet(isPresented: $showStudyQuickJumpSheet) {
            studyQuickJumpSheetView
        }
        .sheet(isPresented: $showTranslationSettingsSheet) {
            translationSettingsSheetView
        }
    }

    // MARK: - Top Control Header
    private var topControlHeader: some View {
        HStack(spacing: 10) {
            Button {
                bridge.goBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.subheadline.bold())
            }
            .disabled(!bridge.canGoBack)

            Button {
                bridge.goForward()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.subheadline.bold())
            }
            .disabled(!bridge.canGoForward)

            Button {
                showStudyQuickJumpSheet = true
            } label: {
                HStack(spacing: 5) {
                    if bridge.isLoading || bridge.isTranslatingNow {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: "globe")
                            .font(.caption)
                    }
                    Text(shortHostPathDisplay(bridge.currentURLString))
                        .font(.caption.monospaced())
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity)
                .background(Color(.secondarySystemBackground))
                .clipShape(Capsule())
            }
            .foregroundColor(.primary)

            // Instant Rescan / Translate Button
            Button {
                bridge.triggerFullPageRescan()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "character.bubble.fill")
                    Text(bridge.lastUsedProviderBadge)
                        .font(.caption2.bold())
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(bridge.autoTranslateEnabled ? Color.accentColor.opacity(0.15) : Color(.secondarySystemBackground))
                .foregroundColor(bridge.autoTranslateEnabled ? .accentColor : .secondary)
                .clipShape(Capsule())
            }

            Button {
                showTranslationSettingsSheet = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.subheadline.bold())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color(.systemBackground))
        .overlay(Divider(), alignment: .bottom)
    }

    // MARK: - Floating Real-Time Subtitle Card
    private var floatingSubtitleOverlay: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(
                    bridge.activeChapterTitle.isEmpty ? "研习棋评实时中文翻译" : bridge.activeChapterTitle,
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
                    bridge.triggerFullPageRescan()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }

                Button {
                    withAnimation { bridge.showFloatingSubtitleCard = false }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if bridge.isTranslatingNow && bridge.activeTranslatedComment.isEmpty {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.75)
                    Text("正在实时翻译当前着法注解...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                Text(bridge.activeTranslatedComment.isEmpty ? bridge.activeOriginalComment : bridge.activeTranslatedComment)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.primary)
                    .lineLimit(4)
                    .textSelection(.enabled)
            }

            Text(bridge.activeOriginalComment)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
        .padding(10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: 2)
    }

    // MARK: - Bottom Quick-Switch Navigation Bar
    private var bottomNavigationDock: some View {
        HStack(spacing: 0) {
            dockButton(title: "对局大厅", icon: "checkerboard.rectangle", url: "https://lichess.org/")
            dockButton(title: "研习翻译", icon: "book.pages.fill", url: "https://lichess.org/study")
            dockButton(title: "战术谜题", icon: "puzzlepiece.extension.fill", url: "https://lichess.org/training")
            dockButton(title: "分析棋盘", icon: "cpu.fill", url: "https://lichess.org/analysis")
            dockButton(title: "大师直播", icon: "tv.fill", url: "https://lichess.org/tv")
        }
        .padding(.top, 6)
        .padding(.bottom, 4)
        .background(Color(.systemBackground))
        .overlay(Divider(), alignment: .top)
    }

    private func dockButton(title: String, icon: String, url: String) -> some View {
        let isActive = bridge.currentURLString.hasPrefix(url) && (url != "https://lichess.org/" || bridge.currentURLString == "https://lichess.org/")
        return Button {
            bridge.navigateTo(url)
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                Text(title)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(isActive ? .accentColor : .secondary)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Study Quick Jump & URL Input Sheet
    private var studyQuickJumpSheetView: some View {
        NavigationStack {
            List {
                Section("输入 Lichess 研习 ID、网址或搜索关键词") {
                    HStack {
                        TextField("输入 8 位研习 ID (如 wukLYIXj) 或完整 URL", text: $customURLOrStudyID)
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

                Section("热门英文研习一键直达 (自动开启网页内嵌中文翻译)") {
                    studyShortcutRow(
                        title: "Silman 经典残局教程 (Silman's Endgame Course)",
                        subtitle: "Lichess 最受好评的残局研习，走子时自动将英文讲解译为中文",
                        url: "https://lichess.org/study/wukLYIXj"
                    )
                    studyShortcutRow(
                        title: "Lichess 官方全部热门研习广场",
                        subtitle: "浏览全球棋手分享的开局、中局与残局研习，章节名与棋评自动中文化",
                        url: "https://lichess.org/study/all/popular"
                    )
                    studyShortcutRow(
                        title: "我的个人研习库 (需在网页登录 Lichess)",
                        subtitle: "直接访问你自己创建或收藏的 Lichess 研习",
                        url: "https://lichess.org/study/mine/hot"
                    )
                }
            }
            .navigationTitle("快速跳转与研习直达")
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

    // MARK: - Translation & Hybrid Bridge Settings Sheet
    private var translationSettingsSheetView: some View {
        NavigationStack {
            Form {
                Section("研习实时拦截与翻译开关") {
                    Toggle("启用研习章节与注解实时中文翻译", isOn: $bridge.autoTranslateEnabled)
                    Toggle("显示底部原生实时字幕悬浮卡片", isOn: $bridge.showFloatingSubtitleCard)

                    Picker("网页内嵌译文显示模式", selection: $bridge.injectionModeRaw) {
                        ForEach(InlineInjectionMode.allCases) { mode in
                            Text(mode.displayName).tag(mode.rawValue)
                        }
                    }

                    Button {
                        bridge.triggerFullPageRescan()
                        showTranslationSettingsSheet = false
                    } label: {
                        Label("立即重新扫描并翻译当前网页全部棋评", systemImage: "bolt.fill")
                    }
                }

                Section("免配置多翻译引擎切换 (自动容灾)") {
                    Picker("首选翻译源", selection: $bridge.selectedProviderRaw) {
                        ForEach(TranslationProviderType.allCases) { provider in
                            Text(provider.displayName).tag(provider.rawValue)
                        }
                    }
                    .pickerStyle(.inline)
                }

                Section("实时拦截统计") {
                    LabeledContent("本次会话已自动翻译节点数", value: "\(bridge.translatedCount) 处")
                    LabeledContent("当前响应翻译引擎", value: bridge.lastUsedProviderBadge)
                    Text("提示：在 Lichess 网页中点击任意一步棋、展开章节列表或用手指选中任意一段英文文字，原生桥接器都会自动拦截并实时翻译为地道的国际象棋中文术语。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("混合桥接与翻译设置")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { showTranslationSettingsSheet = false }
                }
            }
        }
    }

    private func shortHostPathDisplay(_ urlStr: String) -> String {
        guard let url = URL(string: urlStr) else { return urlStr }
        let path = url.path.isEmpty || url.path == "/" ? "/ (首页大厅)" : url.path
        return "lichess.org\(path)"
    }
}
