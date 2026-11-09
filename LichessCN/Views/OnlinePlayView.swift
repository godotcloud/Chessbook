import SwiftUI

struct OnlinePlayView: View {
    @EnvironmentObject var appState: AppStateViewModel

    @State private var boardState = ChessBoardState()
    @State private var aiLevel: Int = 3
    @State private var selectedColor: PieceColor = .white
    @State private var isPlayingLocalOrRemote = false
    @State private var activeGameId: String? = nil
    @State private var gameStatusMessage: String = "选择与 Lichess Stockfish AI 对弈，或观看 Lichess TV 大师直播"
    @State private var tvSummary: LichessTVGameSummary? = nil
    @State private var moveHistorySAN: [String] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    // 1. Live Match / TV Status Bar
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            if let tv = tvSummary, activeGameId == nil && !isPlayingLocalOrRemote {
                                Text("Lichess TV: \(tv.whiteName) (\(tv.whiteRating)) vs \(tv.blackName) (\(tv.blackRating))")
                                    .font(.subheadline.bold())
                            } else {
                                Text(activeGameId != nil ? "Lichess 在线对局 #\(activeGameId!)" : "人机/练习对局 (Stockfish Lv.\(aiLevel))")
                                    .font(.subheadline.bold())
                            }
                            Text(gameStatusMessage)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button {
                            Task { await loadLiveTV() }
                        } label: {
                            Label("TV直播", systemImage: "tv.fill")
                                .font(.caption.bold())
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.horizontal, 12)

                    // 2. Interactive Chessboard
                    ChessBoardView(
                        boardState: boardState,
                        flipped: selectedColor == .black,
                        theme: appState.boardTheme,
                        interactive: true,
                        onMoveExecuted: { uci in
                            Task { await handlePlayerMove(uci) }
                        }
                    )
                    .padding(.horizontal, 12)

                    // 3. Game Control Panel
                    VStack(spacing: 10) {
                        HStack {
                            Text("AI 强度等级: \(aiLevel) 级")
                                .font(.subheadline.bold())
                            Slider(value: Binding(
                                get: { Double(aiLevel) },
                                set: { aiLevel = Int($0) }
                            ), in: 1...8, step: 1)

                            Picker("执色", selection: $selectedColor) {
                                Text("执白").tag(PieceColor.white)
                                Text("执黑").tag(PieceColor.black)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 110)
                        }

                        HStack(spacing: 12) {
                            Button {
                                Task { await startNewGame() }
                            } label: {
                                Label("开始新对局", systemImage: "play.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)

                            Button(role: .destructive) {
                                resetBoard()
                            } label: {
                                Label("重置棋盘", systemImage: "arrow.counterclockwise")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 12)
                }
                .padding(.vertical, 8)
            }
            .navigationTitle("Lichess 在线对弈")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func resetBoard() {
        boardState = ChessBoardState()
        activeGameId = nil
        isPlayingLocalOrRemote = false
        moveHistorySAN = []
        gameStatusMessage = "棋盘已重置，点击“开始新对局”即可开战"
    }

    private func startNewGame() async {
        boardState = ChessBoardState()
        moveHistorySAN = []
        isPlayingLocalOrRemote = true
        tvSummary = nil

        let token = appState.apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if !token.isEmpty {
            do {
                let colorParam = selectedColor == .white ? "white" : "black"
                let gameId = try await LichessAPIService.shared.startAIGame(
                    level: aiLevel,
                    clockLimitSeconds: 600,
                    clockIncrementSeconds: 3,
                    color: colorParam,
                    token: token
                )
                activeGameId = gameId
                gameStatusMessage = "已连接 Lichess 云端对局 (#\(gameId))，请走子"
                return
            } catch {
                activeGameId = nil
            }
        }

        activeGameId = nil
        gameStatusMessage = "免登录快速对弈模式 (内置智能应子 + Lichess 云端评估辅助)"
        if selectedColor == .black {
            await makeSmartComputerReply()
        }
    }

    private func handlePlayerMove(_ uci: String) async {
        guard boardState.applyUCIMove(uci) else { return }
        moveHistorySAN.append(uci)

        if let gameId = activeGameId, !appState.apiToken.isEmpty {
            try? await LichessAPIService.shared.sendBoardMove(
                gameId: gameId,
                uciMove: uci,
                token: appState.apiToken
            )
        }

        gameStatusMessage = "电脑正在思考应着..."
        try? await Task.sleep(nanoseconds: 350_000_000)
        await makeSmartComputerReply()
    }

    private func makeSmartComputerReply() async {
        let currentFEN = boardState.toFEN()
        // First try Lichess Cloud Eval best move if available
        if let cloud = try? await LichessAPIService.shared.fetchCloudEval(fen: currentFEN, multiPv: 1),
           let firstPV = cloud.pvs.first,
           let bestMove = firstPV.moves.split(separator: " ").first {
            let uci = String(bestMove)
            if boardState.applyUCIMove(uci) {
                gameStatusMessage = "对方走出云端推荐着法: \(uci) (评分 \(firstPV.formattedScore))"
                return
            }
        }

        // Local tactical fallback move generator
        var allMoves: [(uci: String, score: Int)] = []
        for r in 0..<8 {
            for f in 0..<8 {
                let sq = BoardSquare(file: f, rank: r)
                guard let p = boardState.piece(at: sq), p.color == boardState.turn else { continue }
                for dest in boardState.candidateDestinations(from: sq) {
                    var score = 0
                    if let captured = boardState.piece(at: dest) {
                        score += pieceValue(captured.type) * 10
                    }
                    // Center control bonus
                    if (2...5).contains(dest.file) && (2...5).contains(dest.rank) {
                        score += 3
                    }
                    allMoves.append((sq.algebraic + dest.algebraic, score))
                }
            }
        }
        allMoves.sort { $0.score > $1.score }
        if let chosen = allMoves.prefix(max(1, 9 - aiLevel)).randomElement() {
            _ = boardState.applyUCIMove(chosen.uci)
            gameStatusMessage = "对方走出: \(chosen.uci)，轮到你走子"
        }
    }

    private func pieceValue(_ type: PieceType) -> Int {
        switch type {
        case .pawn: return 1
        case .knight, .bishop: return 3
        case .rook: return 5
        case .queen: return 9
        case .king: return 100
        }
    }

    private func loadLiveTV() async {
        gameStatusMessage = "正在同步 Lichess TV 实时局面..."
        let summary = await LichessAPIService.shared.fetchLichessTVFeed()
        tvSummary = summary
        activeGameId = nil
        isPlayingLocalOrRemote = false
        var state = ChessBoardState(fen: summary.fen)
        if let lm = summary.lastMoveUCI, lm.count >= 4 {
            let s = lm.startIndex
            state.lastMoveFrom = BoardSquare(algebraic: String(lm[s..<lm.index(s, offsetBy: 2)]))
            state.lastMoveTo = BoardSquare(algebraic: String(lm[lm.index(s, offsetBy: 2)..<lm.index(s, offsetBy: 4)]))
        }
        boardState = state
        gameStatusMessage = "已同步 Lichess TV 顶级对局局面，你可以直接在棋盘上推演后续变化"
    }
}
