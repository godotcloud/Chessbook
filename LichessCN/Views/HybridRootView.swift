import SwiftUI
#if canImport(Translation)
import Translation
#endif

struct HybridRootView: View {
    @EnvironmentObject var bridge: HybridTranslationBridgeManager
    @ObservedObject private var speech = ChessSpeechService.shared

    @State private var showStudyQuickJumpSheet = false
    @State private var showTranslationSettingsSheet = false
    @State private var customURLOrStudyID: String = ""
    @State private var showSystemTranslationSheet = false

    var body: some View {
        VStack(spacing: 0) {
            if !bridge.isCompactFullscreen {
                slimTopControlHeader
            }

            ZStack(alignment: .bottom) {
                LichessHybridWebView(manager: bridge)

                if bridge.isCompactFullscreen {
                    HStack(spacing: 8) {
                        Spacer()
                        // Quick manual speak/stop button even in fullscreen mode!
                        Button {
                            bridge.toggleSpeakActiveComment()
                        } label: {
                            Image(systemName: speech.isSpeaking ? "stop.circle.fill" : "speaker.wave.2.fill")
                                .font(.caption.bold())
                                .padding(8)
                                .background(.ultraThinMaterial)
                                .foregroundColor(speech.isSpeaking ? .red : .accentColor)
                                .clipShape(Circle())
                                .shadow(radius: 3)
                        }

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
                    }
                    .padding(.trailing, 12)
                    .padding(.bottom, 12)
                }

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

    private var slimTopControlHeader: some View {
        HStack(spacing: 6) {
            Button {
                bridge.goBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 22, height: 28)
            }
            .disabled(!bridge.canGoBack)

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
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color(.secondarySystemBackground))
                .clipShape(Capsule())
            }
            .foregroundColor(.primary)

            Spacer(minLength: 2)

            // 1-Tap Manual Speak / Stop Button on Top Bar
            Button {
                bridge.toggleSpeakActiveComment()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: speech.isSpeaking ? "stop.fill" : (bridge.autoSpeakEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill"))
                        .font(.system(size: 11, weight: .bold))
                    Text(speech.isSpeaking ? "停止" : (bridge.autoSpeakEnabled ? "自动读" : "朗读"))
                        .font(.system(size: 11, weight: .bold))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(speech.isSpeaking ? Color.red.opacity(0.16) : (bridge.autoSpeakEnabled ? Color.green.opacity(0.16) : Color(.secondarySystemBackground)))
                .foregroundColor(speech.isSpeaking ? .red : (bridge.autoSpeakEnabled ? .green : .primary))
                .clipShape(Capsule())
            }

            // 1-Tap Rescan Button
            Button {
                bridge.triggerFullPageRescan()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 24, height: 28)
            }
            .accessibilityLabel("立即重译本页")

            // Translation & Voice Menu
            Menu {
                Section("语音朗读 (TTS)") {
                    Toggle("走子时自动朗读中文译文", isOn: $bridge.autoSpeakEnabled)
                    Button {
                        bridge.toggleSpeakActiveComment()
                    } label: {
                        Label(
                            speech.isSpeaking ? "停止当前朗读" : "立即手动朗读当前步译文",
                            systemImage: speech.isSpeaking ? "stop.circle" : "play.circle"
                        )
                    }
                    Picker("朗读语速", selection: $bridge.speechSpeedRaw) {
                        ForEach(SpeechSpeedPreset.allCases) { preset in
                            Text(preset.displayName).tag(preset.rawValue)
                        }
                    }
                    Toggle("棋谱符号口语化 (如 O-O 读作 短易位)", isOn: $bridge.verbalizeChessMoves)
                }

                Section("显示样式") {
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
                    showTranslationSettingsSheet = true
                } label: {
                    Label("打开完整语音与翻译设置面板...", systemImage: "slider.horizontal.3")
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "character.bubble.fill")
                        .font(.system(size: 11))
                    Text(bridge.lastUsedProviderBadge)
                        .font(.system(size: 11, weight: .bold))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(bridge.autoTranslateEnabled ? Color.accentColor.opacity(0.15) : Color(.secondarySystemBackground))
                .foregroundColor(bridge.autoTranslateEnabled ? .accentColor : .secondary)
                .clipShape(Capsule())
            }

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    bridge.isCompactFullscreen = true
                }
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 24, height: 28)
            }
            .accessibilityLabel("隐藏顶部栏进入全屏")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(.systemBackground))
        .overlay(Divider(), alignment: .bottom)
    }

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

                Button {
                    bridge.toggleSpeakActiveComment()
                } label: {
                    Label(speech.isSpeaking ? "停止" : "朗读", systemImage: speech.isSpeaking ? "stop.circle.fill" : "speaker.wave.2.fill")
                        .font(.caption.bold())
                        .foregroundColor(speech.isSpeaking ? .red : .accentColor)
                }

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
                        title: "卡罗-卡恩防御研习 (ZCPaIb70)",
                        subtitle: "直接打开 ZCPaIb70 研习，测试走子自动语音朗读",
                        url: "https://lichess.org/study/ZCPaIb70"
                    )
                    studyShortcutRow(
                        title: "Lichess 热门研习广场",
                        subtitle: "浏览全球棋手创建的开局、中局与残局研习",
                        url: "https://lichess.org/study/all/popular"
                    )
                    studyShortcutRow(
                        title: "Silman 经典残局教程",
                        subtitle: "互动式残局训练，支持连续走子自动翻译与语音播报",
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
                Section("语音朗读 (自动 / 手动 TTS)") {
                    Toggle("走子切换时自动朗读译文", isOn: $bridge.autoSpeakEnabled)
                    Toggle("棋谱着法口语化播报 (如 Bd2 读作 象d2, O-O 读作 短易位)", isOn: $bridge.verbalizeChessMoves)

                    Picker("朗读语速", selection: $bridge.speechSpeedRaw) {
                        ForEach(SpeechSpeedPreset.allCases) { preset in
                            Text(preset.displayName).tag(preset.rawValue)
                        }
                    }

                    Button {
                        ChessSpeechService.shared.speakOrToggle(
                            text: "对方吃了一个白送的兵。我们不必走 Bd2、Qc2 或 Qb3 来保护这个马。我们通过 O-O 再弃一兵！",
                            speed: bridge.speechSpeed,
                            verbalizeChessMoves: bridge.verbalizeChessMoves
                        )
                    } label: {
                        Label(
                            speech.isSpeaking ? "停止试听" : "试听中文棋评语音播报效果",
                            systemImage: speech.isSpeaking ? "stop.circle.fill" : "speaker.wave.2.circle.fill"
                        )
                    }
                }

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
            .navigationTitle("语音与翻译设置")
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
