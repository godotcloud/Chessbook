import SwiftUI
#if canImport(Translation)
import Translation
#endif

struct StudyBrowserView: View {
    @EnvironmentObject var appState: AppStateViewModel

    @State private var studyInput: String = "YtBYXc3m"
    @State private var chapters: [StudyChapter] = []
    @State private var selectedChapterIndex: Int = 0
    @State private var currentPlyIndex: Int = 0 // 0 = initial position before move 1
    @State private var boardState = ChessBoardState()
    @State private var flippedBoard = false

    @State private var isLoadingStudy = false
    @State private var isTranslating = false
    @State private var isBatchTranslating = false

    @State private var translatedChapterTitles: [Int: String] = [:]
    @State private var translatedStepComments: [String: String] = [:]
    @State private var activeProviderBadge: String = "AI大模型"
    @State private var showStudyLibrarySheet = false
    @State private var showRawPGNImportSheet = false
    @State private var customPGNText = ""
    @State private var showSystemTranslationSheet = false

    private var currentChapter: StudyChapter? {
        guard chapters.indices.contains(selectedChapterIndex) else { return nil }
        return chapters[selectedChapterIndex]
    }

    private var currentRawComment: String {
        guard let chapter = currentChapter else { return "" }
        if currentPlyIndex == 0 {
            return chapter.openingComment
        }
        let stepIdx = currentPlyIndex - 1
        guard chapter.steps.indices.contains(stepIdx) else { return "" }
        return chapter.steps[stepIdx].rawComment
    }

    private var currentCommentKey: String {
        "\(selectedChapterIndex)_\(currentPlyIndex)"
    }

    private var currentArrows: [BoardArrow] {
        guard let chapter = currentChapter else { return [] }
        if currentPlyIndex == 0 { return chapter.openingArrows }
        let idx = currentPlyIndex - 1
        return chapter.steps.indices.contains(idx) ? chapter.steps[idx].arrows : []
    }

    private var currentCircles: [BoardCircleHighlight] {
        guard let chapter = currentChapter else { return [] }
        if currentPlyIndex == 0 { return chapter.openingCircles }
        let idx = currentPlyIndex - 1
        return chapter.steps.indices.contains(idx) ? chapter.steps[idx].circles : []
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    // 1. Top Study Import & Quick Engine Selector Bar
                    studyImportBar

                    // 2. Chapter Picker & Translation Controls
                    if let chapter = currentChapter {
                        chapterHeaderCard(chapter: chapter)
                    }

                    // 3. Interactive Native Chessboard with Study Arrows & Circles
                    ChessBoardView(
                        boardState: boardState,
                        flipped: flippedBoard,
                        theme: appState.boardTheme,
                        arrows: currentArrows,
                        circles: currentCircles,
                        interactive: true,
                        onMoveExecuted: { uci in
                            handleManualMoveOnStudyBoard(uci)
                        }
                    )
                    .padding(.horizontal, 12)

                    // 4. Move Navigation & Flip Controls
                    moveStepToolbar

                    // 5. Real-Time Chinese Translation Card
                    realTimeTranslationCard

                    // 6. Horizontal Move List Strip
                    if let chapter = currentChapter, !chapter.steps.isEmpty {
                        moveStripView(chapter: chapter)
                    }
                }
                .padding(.vertical, 8)
            }
            .navigationTitle("Lichess 研习实时翻译")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showStudyLibrarySheet = true
                    } label: {
                        Label("精选研习库", systemImage: "books.vertical.fill")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("实时翻译源 (免配置)", selection: $appState.selectedProviderRaw) {
                            ForEach(TranslationProviderType.allCases) { provider in
                                Text(provider.displayName).tag(provider.rawValue)
                            }
                        }
                        Divider()
                        Toggle("显示中英双语对照", isOn: $appState.showBilingualComments)
                        Toggle("走子时自动实时翻译", isOn: $appState.autoTranslateStudy)
                        Button {
                            showRawPGNImportSheet = true
                        } label: {
                            Label("直接粘贴 PGN 文本导入", systemImage: "doc.on.clipboard")
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "character.bubble.fill")
                            Text(appState.selectedProvider.shortBadge)
                                .font(.caption.bold())
                        }
                    }
                }
            }
            .sheet(isPresented: $showStudyLibrarySheet) {
                studyLibrarySheetView
            }
            .sheet(isPresented: $showRawPGNImportSheet) {
                rawPGNImportSheetView
            }
            .task {
                if chapters.isEmpty {
                    await loadStudy(from: studyInput)
                }
            }
            .onChange(of: currentPlyIndex) { _ in
                syncBoardToCurrentStep()
                if appState.autoTranslateStudy {
                    Task { await translateCurrentPositionComment() }
                }
            }
            .onChange(of: selectedChapterIndex) { _ in
                currentPlyIndex = 0
                syncBoardToCurrentStep()
                Task {
                    await translateCurrentChapterTitle()
                    if appState.autoTranslateStudy {
                        await translateCurrentPositionComment()
                    }
                }
            }
            .onChange(of: appState.selectedProviderRaw) { _ in
                Task {
                    await translateCurrentChapterTitle()
                    await translateCurrentPositionComment(forceRefresh: true)
                }
            }
        }
    }

    // MARK: - Subviews

    private var studyImportBar: some View {
        HStack(spacing: 8) {
            HStack {
                Image(systemName: "link")
                    .foregroundColor(.secondary)
                TextField("输入 Lichess Study 链接或 8 位 ID (如 YtBYXc3m)", text: $studyInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.subheadline)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Button {
                Task { await loadStudy(from: studyInput) }
            } label: {
                if isLoadingStudy {
                    ProgressView()
                        .frame(width: 56, height: 34)
                } else {
                    Text("加载")
                        .font(.subheadline.bold())
                        .frame(width: 56, height: 34)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoadingStudy)
        }
        .padding(.horizontal, 12)
    }

    private func chapterHeaderCard(chapter: StudyChapter) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Menu {
                    ForEach(Array(chapters.enumerated()), id: \.element.id) { idx, chap in
                        Button {
                            selectedChapterIndex = idx
                        } label: {
                            let zhTitle = translatedChapterTitles[idx]
                            Text("第\(idx + 1)章: \(zhTitle ?? chap.title)")
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "list.bullet.rectangle.portrait.fill")
                        Text("章节 (\(selectedChapterIndex + 1)/\(chapters.count)): \(translatedChapterTitles[selectedChapterIndex] ?? chapter.title)")
                            .font(.subheadline.bold())
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.caption)
                    }
                }

                Spacer()

                Button {
                    Task { await batchTranslateEntireChapter() }
                } label: {
                    HStack(spacing: 4) {
                        if isBatchTranslating {
                            ProgressView().scaleEffect(0.7)
                        } else {
                            Image(systemName: "bolt.horizontal.fill")
                        }
                        Text(isBatchTranslating ? "全章翻译中" : "预译全章")
                            .font(.caption.bold())
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.14))
                    .clipShape(Capsule())
                }
                .disabled(isBatchTranslating)
            }
        }
        .padding(.horizontal, 12)
    }

    private var moveStepToolbar: some View {
        let totalSteps = currentChapter?.steps.count ?? 0
        return HStack(spacing: 16) {
            Button {
                flippedBoard.toggle()
            } label: {
                Image(systemName: "arrow.up.arrow.down.square")
                    .font(.title3)
            }
            .accessibilityLabel("翻转棋盘")

            Spacer()

            Button {
                currentPlyIndex = 0
            } label: {
                Image(systemName: "backward.end.fill")
                    .font(.title3)
            }
            .disabled(currentPlyIndex == 0)

            Button {
                if currentPlyIndex > 0 { currentPlyIndex -= 1 }
            } label: {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.title2)
            }
            .disabled(currentPlyIndex == 0)

            Text("\(currentPlyIndex) / \(totalSteps)")
                .font(.system(.subheadline, design: .monospaced).bold())
                .frame(minWidth: 64)

            Button {
                if currentPlyIndex < totalSteps { currentPlyIndex += 1 }
            } label: {
                Image(systemName: "chevron.right.circle.fill")
                    .font(.title2)
            }
            .disabled(currentPlyIndex >= totalSteps)

            Button {
                currentPlyIndex = totalSteps
            } label: {
                Image(systemName: "forward.end.fill")
                    .font(.title3)
            }
            .disabled(currentPlyIndex >= totalSteps)

            Spacer()

            Button {
                Task { await translateCurrentPositionComment(forceRefresh: true) }
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.title3)
            }
            .accessibilityLabel("重新翻译当前注解")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 12)
    }

    private var realTimeTranslationCard: some View {
        let rawText = currentRawComment
        let translatedText = translatedStepComments[currentCommentKey] ?? ""

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("研习解说实时中文翻译", systemImage: "sparkles")
                    .font(.footnote.bold())
                    .foregroundColor(.accentColor)

                Spacer()

                Text("引擎: \(activeProviderBadge)")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(Capsule())

                #if canImport(Translation)
                if #available(iOS 17.4, *), !rawText.isEmpty {
                    Button {
                        showSystemTranslationSheet = true
                    } label: {
                        Image(systemName: "translate")
                            .font(.caption)
                    }
                    .translationPresentation(isPresented: $showSystemTranslationSheet, text: rawText)
                }
                #endif
            }

            if rawText.isEmpty {
                Text("当前步没有文字解说（请点击前进按钮 `>` 浏览后续着法注解，棋盘已同步绘制本章战术箭头）。")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                if isTranslating && translatedText.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("正在实时翻译棋评与国际象棋术语...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text(translatedText.isEmpty ? ChessGlossaryProcessor.applyGlossaryReplacement(rawText) : translatedText)
                        .font(.body.weight(.medium))
                        .foregroundColor(.primary)
                        .textSelection(.enabled)
                }

                if appState.showBilingualComments {
                    Divider()
                    Text(rawText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 12)
    }

    private func moveStripView(chapter: StudyChapter) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Button {
                        currentPlyIndex = 0
                    } label: {
                        Text("开局")
                            .font(.caption.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(currentPlyIndex == 0 ? Color.accentColor : Color(.tertiarySystemBackground))
                            .foregroundColor(currentPlyIndex == 0 ? .white : .primary)
                            .clipShape(Capsule())
                    }
                    .id(0)

                    ForEach(chapter.steps) { step in
                        let isCurrent = currentPlyIndex == step.plyIndex
                        let hasComment = !step.rawComment.isEmpty
                        Button {
                            currentPlyIndex = step.plyIndex
                        } label: {
                            HStack(spacing: 3) {
                                Text(step.moveNumberDisplay)
                                    .font(.system(.caption, design: .monospaced).bold())
                                if hasComment {
                                    Image(systemName: "text.bubble.fill")
                                        .font(.system(size: 9))
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(isCurrent ? Color.accentColor : Color(.tertiarySystemBackground))
                            .foregroundColor(isCurrent ? .white : .primary)
                            .clipShape(Capsule())
                        }
                        .id(step.plyIndex)
                    }
                }
                .padding(.horizontal, 12)
            }
            .onChange(of: currentPlyIndex) { newIdx in
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(newIdx, anchor: .center)
                }
            }
        }
    }

    private var studyLibrarySheetView: some View {
        NavigationStack {
            List {
                Section("精选 Lichess 研习 (点击直接加载并开启中文翻译)") {
                    ForEach(LichessAPIService.featuredStudies) { item in
                        Button {
                            studyInput = item.id
                            showStudyLibrarySheet = false
                            Task { await loadStudy(from: item.id) }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(item.name)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    Text(item.id)
                                        .font(.caption.monospaced())
                                        .foregroundColor(.secondary)
                                }
                                Text("作者: \(item.ownerName)")
                                    .font(.caption.bold())
                                    .foregroundColor(.accentColor)
                                Text(item.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("精选研习与导入")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { showStudyLibrarySheet = false }
                }
            }
        }
    }

    private var rawPGNImportSheetView: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text("将任意带有英文/外文注解的 Lichess Study PGN 粘贴到下方，即可离线解析章节并实时翻译为中文：")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                TextEditor(text: $customPGNText)
                    .font(.system(.caption, design: .monospaced))
                    .padding(6)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                Button {
                    let parsed = PGNParser.parseStudyPGN(customPGNText)
                    if !parsed.isEmpty {
                        chapters = parsed
                        selectedChapterIndex = 0
                        currentPlyIndex = 0
                        translatedChapterTitles = [:]
                        translatedStepComments = [:]
                        syncBoardToCurrentStep()
                        showRawPGNImportSheet = false
                        Task {
                            await translateCurrentChapterTitle()
                            await translateCurrentPositionComment()
                        }
                    }
                } label: {
                    Text("解析 PGN 并启动实时翻译")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .disabled(customPGNText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
            .navigationTitle("粘贴导入研习 PGN")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showRawPGNImportSheet = false }
                }
            }
        }
    }

    // MARK: - Actions & Translation Logic

    private func loadStudy(from input: String) async {
        isLoadingStudy = true
        defer { isLoadingStudy = false }

        do {
            let pgn = try await LichessAPIService.shared.fetchStudyPGN(
                studyIDOrURL: input,
                token: appState.apiToken
            )
            let parsed = PGNParser.parseStudyPGN(pgn)
            if !parsed.isEmpty {
                chapters = parsed
                selectedChapterIndex = 0
                currentPlyIndex = 0
                translatedChapterTitles = [:]
                translatedStepComments = [:]
                syncBoardToCurrentStep()
                await translateCurrentChapterTitle()
                if appState.autoTranslateStudy {
                    await translateCurrentPositionComment()
                }
            }
        } catch {
            // Fallback to built-in study
            let parsed = PGNParser.parseStudyPGN(LichessAPIService.builtInSampleStudyPGN)
            chapters = parsed
            selectedChapterIndex = 0
            currentPlyIndex = 0
            syncBoardToCurrentStep()
            await translateCurrentPositionComment()
        }
    }

    private func syncBoardToCurrentStep() {
        guard let chapter = currentChapter else { return }
        if currentPlyIndex == 0 {
            boardState = ChessBoardState(fen: chapter.initialFEN)
        } else {
            let idx = currentPlyIndex - 1
            if chapter.steps.indices.contains(idx) {
                let step = chapter.steps[idx]
                var state = ChessBoardState(fen: step.fenAfterMove)
                if step.uci.count >= 4 {
                    let s = step.uci.startIndex
                    state.lastMoveFrom = BoardSquare(algebraic: String(step.uci[s..<step.uci.index(s, offsetBy: 2)]))
                    state.lastMoveTo = BoardSquare(algebraic: String(step.uci[step.uci.index(s, offsetBy: 2)..<step.uci.index(s, offsetBy: 4)]))
                }
                boardState = state
            }
        }
    }

    private func handleManualMoveOnStudyBoard(_ uci: String) {
        if let chapter = currentChapter,
           currentPlyIndex < chapter.steps.count,
           chapter.steps[currentPlyIndex].uci.lowercased() == uci.lowercased() {
            currentPlyIndex += 1
        } else {
            _ = boardState.applyUCIMove(uci)
        }
    }

    private func translateCurrentChapterTitle() async {
        guard let chapter = currentChapter else { return }
        let idx = selectedChapterIndex
        if translatedChapterTitles[idx] != nil { return }
        let (zh, used) = await ChessTranslationService.shared.translateToChinese(
            text: chapter.title,
            preferredProvider: appState.selectedProvider
        )
        translatedChapterTitles[idx] = zh
        activeProviderBadge = used.shortBadge
    }

    private func translateCurrentPositionComment(forceRefresh: Bool = false) async {
        let raw = currentRawComment
        guard !raw.isEmpty else { return }
        let key = currentCommentKey
        if !forceRefresh, translatedStepComments[key] != nil { return }

        isTranslating = true
        let (zh, used) = await ChessTranslationService.shared.translateToChinese(
            text: raw,
            preferredProvider: appState.selectedProvider
        )
        translatedStepComments[key] = zh
        activeProviderBadge = used.shortBadge
        isTranslating = false
    }

    private func batchTranslateEntireChapter() async {
        guard let chapter = currentChapter else { return }
        isBatchTranslating = true
        defer { isBatchTranslating = false }

        let chapIdx = selectedChapterIndex
        if !chapter.openingComment.isEmpty {
            let (zh, used) = await ChessTranslationService.shared.translateToChinese(
                text: chapter.openingComment,
                preferredProvider: appState.selectedProvider
            )
            translatedStepComments["\(chapIdx)_0"] = zh
            activeProviderBadge = used.shortBadge
        }

        for step in chapter.steps where !step.rawComment.isEmpty {
            let key = "\(chapIdx)_\(step.plyIndex)"
            if translatedStepComments[key] == nil {
                let (zh, _) = await ChessTranslationService.shared.translateToChinese(
                    text: step.rawComment,
                    preferredProvider: appState.selectedProvider
                )
                translatedStepComments[key] = zh
            }
        }
    }
}
