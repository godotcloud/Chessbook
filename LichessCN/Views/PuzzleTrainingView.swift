import SwiftUI

struct PuzzleTrainingView: View {
    @EnvironmentObject var appState: AppStateViewModel

    @State private var currentPuzzle: LichessPuzzleResponse? = nil
    @State private var boardState = ChessBoardState()
    @State private var playerColor: PieceColor = .white
    @State private var solutionIndex: Int = 0
    @State private var statusBanner: String = "正在加载 Lichess 官方战术谜题..."
    @State private var isSolved: Bool = false
    @State private var isFailed: Bool = false
    @State private var showHintArrow: [BoardArrow] = []
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    // 1. Puzzle Header Info
                    if let puz = currentPuzzle {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("谜题编号 #\(puz.puzzle.id) · 难度分 \(puz.puzzle.rating)")
                                    .font(.headline)
                                Text("你执\(playerColor.displayName) · 请找出最佳战术组合")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text("已挑战 \(puz.puzzle.plays) 次")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color(.secondarySystemBackground))
                                .clipShape(Capsule())
                        }
                        .padding(.horizontal, 12)
                    }

                    // 2. Interactive Chessboard
                    ChessBoardView(
                        boardState: boardState,
                        flipped: playerColor == .black,
                        theme: appState.boardTheme,
                        arrows: showHintArrow,
                        interactive: !isSolved,
                        onMoveExecuted: { uci in
                            handleUserPuzzleMove(uci)
                        }
                    )
                    .padding(.horizontal, 12)

                    // 3. Status Banner
                    HStack {
                        Image(systemName: isSolved ? "checkmark.seal.fill" : (isFailed ? "xmark.octagon.fill" : "lightbulb.fill"))
                            .foregroundColor(isSolved ? .green : (isFailed ? .red : .accentColor))
                        Text(statusBanner)
                            .font(.subheadline.bold())
                        Spacer()
                    }
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 12)

                    // 4. Action Buttons
                    HStack(spacing: 12) {
                        Button {
                            revealHint()
                        } label: {
                            Label("战术提示", systemImage: "wand.and.stars")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(isSolved)

                        Button {
                            Task { await loadPuzzle(daily: true) }
                        } label: {
                            Label("今日谜题", systemImage: "calendar")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(isLoading)

                        Button {
                            Task { await loadPuzzle(daily: false) }
                        } label: {
                            Label("下一题", systemImage: "arrow.right.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isLoading)
                    }
                    .padding(.horizontal, 12)

                    // 5. Translated Tactical Themes
                    if let puz = currentPuzzle {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("战术主题标签 (中文对照)")
                                .font(.footnote.bold())
                                .foregroundColor(.secondary)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(puz.puzzle.themes, id: \.self) { theme in
                                        Text(ChessGlossaryProcessor.translatePuzzleTheme(theme))
                                            .font(.caption.bold())
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .background(Color.accentColor.opacity(0.15))
                                            .foregroundColor(.accentColor)
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                        }
                        .padding(12)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .padding(.horizontal, 12)
                    }
                }
                .padding(.vertical, 8)
            }
            .navigationTitle("Lichess 战术谜题")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                if currentPuzzle == nil {
                    await loadPuzzle(daily: true)
                }
            }
        }
    }

    private func loadPuzzle(daily: Bool) async {
        isLoading = true
        defer { isLoading = false }

        let puz = await LichessAPIService.shared.fetchPuzzle(daily: daily, token: appState.apiToken)
        currentPuzzle = puz
        setupBoardForPuzzle(puz)
    }

    private func setupBoardForPuzzle(_ puz: LichessPuzzleResponse) {
        var b = ChessBoardState()
        let moves = puz.game.pgn
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty && !$0.contains(".") }

        let targetPly = min(moves.count, puz.puzzle.initialPly + 1)
        for i in 0..<targetPly {
            _ = b.applySANMove(moves[i])
        }

        boardState = b
        playerColor = b.turn
        solutionIndex = 0
        isSolved = false
        isFailed = false
        showHintArrow = []
        statusBanner = "轮到\(playerColor.displayName)走子：请点击棋子走出最佳战术着法"
    }

    private func handleUserPuzzleMove(_ uci: String) {
        guard let puz = currentPuzzle, solutionIndex < puz.puzzle.solution.count else { return }
        let expected = puz.puzzle.solution[solutionIndex].lowercased()
        showHintArrow = []

        if uci.lowercased().hasPrefix(expected.prefix(4)) {
            _ = boardState.applyUCIMove(expected)
            solutionIndex += 1
            isFailed = false

            if solutionIndex >= puz.puzzle.solution.count {
                isSolved = true
                statusBanner = "恭喜！你成功解开了这道战术谜题！"
            } else {
                statusBanner = "好棋！对方正在应子..."
                let replyMove = puz.puzzle.solution[solutionIndex]
                solutionIndex += 1
                Task {
                    try? await Task.sleep(nanoseconds: 450_000_000)
                    _ = boardState.applyUCIMove(replyMove)
                    if solutionIndex >= puz.puzzle.solution.count {
                        isSolved = true
                        statusBanner = "恭喜！战术组合全部完成！"
                    } else {
                        statusBanner = "请继续走出下一着杀招！"
                    }
                }
            }
        } else {
            isFailed = true
            statusBanner = "这步棋不够精确（不是最佳战术解），请再试一次或点击“战术提示”。"
        }
    }

    private func revealHint() {
        guard let puz = currentPuzzle, solutionIndex < puz.puzzle.solution.count else { return }
        let expected = puz.puzzle.solution[solutionIndex]
        guard expected.count >= 4 else { return }
        let s = expected.startIndex
        let fromStr = String(expected[s..<expected.index(s, offsetBy: 2)])
        let toStr = String(expected[expected.index(s, offsetBy: 2)..<expected.index(s, offsetBy: 4)])
        if let fromSq = BoardSquare(algebraic: fromStr),
           let toSq = BoardSquare(algebraic: toStr) {
            showHintArrow = [BoardArrow(from: fromSq, to: toSq, colorCode: "G")]
            statusBanner = "提示：注意观察 \(fromStr.uppercased()) 格棋子向 \(toStr.uppercased()) 的战术冲击"
        }
    }
}
