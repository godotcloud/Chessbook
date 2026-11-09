import SwiftUI

struct EngineAnalysisView: View {
    @EnvironmentObject var appState: AppStateViewModel

    @State private var boardState = ChessBoardState()
    @State private var fenInput: String = ChessBoardState.startingFEN
    @State private var flipped = false
    @State private var cloudEval: LichessCloudEvalResponse? = nil
    @State private var explorerData: LichessOpeningExplorerResponse? = nil
    @State private var translatedOpeningName: String = ""
    @State private var bestMoveArrow: [BoardArrow] = []
    @State private var isAnalyzing = false

    private var currentAdvantageRatio: Double {
        cloudEval?.pvs.first?.normalizedWhiteAdvantage ?? 0.52
    }

    private var currentScoreString: String {
        cloudEval?.pvs.first?.formattedScore ?? "+0.20"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    // 1. Opening Name & Depth Header
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            if let op = explorerData?.opening {
                                Text("\(op.eco) · \(translatedOpeningName.isEmpty ? op.name : translatedOpeningName)")
                                    .font(.subheadline.bold())
                            } else {
                                Text("Lichess Cloud Stockfish 实时分析")
                                    .font(.subheadline.bold())
                            }
                            Text(cloudEval != nil ? "云端深度 Depth \(cloudEval!.depth) · 显示前 \(cloudEval!.pvs.count) 条最佳主变 (Multi-PV)" : "点击棋盘走子自动查询 Lichess 云端引擎与大师开局库")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if isAnalyzing {
                            ProgressView()
                        }
                    }
                    .padding(.horizontal, 12)

                    // 2. EvalBar + Chessboard Side-by-Side
                    HStack(spacing: 8) {
                        EvalBarView(
                            whiteAdvantageRatio: currentAdvantageRatio,
                            scoreText: currentScoreString
                        )
                        .frame(width: 28)

                        ChessBoardView(
                            boardState: boardState,
                            flipped: flipped,
                            theme: appState.boardTheme,
                            arrows: bestMoveArrow,
                            interactive: true,
                            onMoveExecuted: { uci in
                                if boardState.applyUCIMove(uci) {
                                    fenInput = boardState.toFEN()
                                    Task { await runCloudAnalysis() }
                                }
                            }
                        )
                    }
                    .padding(.horizontal, 12)

                    // 3. Controls & FEN Bar
                    HStack(spacing: 8) {
                        TextField("输入或粘贴 FEN 局面", text: $fenInput)
                            .font(.system(.caption, design: .monospaced))
                            .padding(8)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        Button("加载FEN") {
                            boardState.loadFEN(fenInput)
                            Task { await runCloudAnalysis() }
                        }
                        .font(.caption.bold())
                        .buttonStyle(.borderedProminent)

                        Button {
                            boardState = ChessBoardState()
                            fenInput = boardState.toFEN()
                            Task { await runCloudAnalysis() }
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.horizontal, 12)

                    // 4. Multi-PV Engine Lines Card
                    if let eval = cloudEval, !eval.pvs.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Stockfish 最佳主变推荐 (点击可走出首步)")
                                .font(.footnote.bold())
                                .foregroundColor(.secondary)

                            ForEach(Array(eval.pvs.enumerated()), id: \.element.id) { idx, pv in
                                Button {
                                    if let firstUCI = pv.moves.split(separator: " ").first {
                                        if boardState.applyUCIMove(String(firstUCI)) {
                                            fenInput = boardState.toFEN()
                                            Task { await runCloudAnalysis() }
                                        }
                                    }
                                } label: {
                                    HStack(alignment: .top, spacing: 8) {
                                        Text(pv.formattedScore)
                                            .font(.system(.caption, design: .monospaced).bold())
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 3)
                                            .background(idx == 0 ? Color.accentColor : Color(.tertiarySystemBackground))
                                            .foregroundColor(idx == 0 ? .white : .primary)
                                            .clipShape(RoundedRectangle(cornerRadius: 5))

                                        Text(pv.moves)
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundColor(.primary)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.leading)

                                        Spacer()
                                    }
                                    .padding(8)
                                    .background(Color(.tertiarySystemBackground).opacity(0.6))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                            }
                        }
                        .padding(12)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 12)
                    }

                    // 5. Lichess Masters Opening Explorer Card
                    if let exp = explorerData, !exp.moves.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Lichess 大师开局库统计 (白胜 \(exp.white) / 和 \(exp.draws) / 黑胜 \(exp.black))")
                                .font(.footnote.bold())
                                .foregroundColor(.secondary)

                            ForEach(exp.moves.prefix(5)) { m in
                                let total = max(1, m.white + m.draws + m.black)
                                let wPct = Int(Double(m.white) / Double(total) * 100)
                                let dPct = Int(Double(m.draws) / Double(total) * 100)
                                let bPct = max(0, 100 - wPct - dPct)

                                Button {
                                    if boardState.applyUCIMove(m.uci) {
                                        fenInput = boardState.toFEN()
                                        Task { await runCloudAnalysis() }
                                    }
                                } label: {
                                    HStack {
                                        Text(m.san)
                                            .font(.system(.subheadline, design: .monospaced).bold())
                                            .frame(width: 54, alignment: .leading)
                                        Text("白 \(wPct)% · 和 \(dPct)% · 黑 \(bPct)%")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Text("\(total) 局")
                                            .font(.caption2.monospaced())
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                        .padding(12)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 12)
                    }
                }
                .padding(.vertical, 8)
            }
            .navigationTitle("云端引擎与开局库")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await runCloudAnalysis()
            }
        }
    }

    private func runCloudAnalysis() async {
        isAnalyzing = true
        defer { isAnalyzing = false }

        let fen = boardState.toFEN()
        async let evalTask = try? LichessAPIService.shared.fetchCloudEval(fen: fen, multiPv: 3)
        async let expTask = try? LichessAPIService.shared.fetchOpeningExplorer(fen: fen)

        let (evalRes, expRes) = await (evalTask, expTask)
        cloudEval = evalRes
        explorerData = expRes

        if let firstMove = evalRes?.pvs.first?.moves.split(separator: " ").first,
           firstMove.count >= 4 {
            let s = firstMove.startIndex
            let fromStr = String(firstMove[s..<firstMove.index(s, offsetBy: 2)])
            let toStr = String(firstMove[firstMove.index(s, offsetBy: 2)..<firstMove.index(s, offsetBy: 4)])
            if let fSq = BoardSquare(algebraic: fromStr),
               let tSq = BoardSquare(algebraic: toStr) {
                bestMoveArrow = [BoardArrow(from: fSq, to: tSq, colorCode: "B")]
            }
        } else {
            bestMoveArrow = []
        }

        if let opName = expRes?.opening?.name {
            let (zh, _) = await ChessTranslationService.shared.translateToChinese(
                text: opName,
                preferredProvider: appState.selectedProvider
            )
            translatedOpeningName = zh
        } else {
            translatedOpeningName = ""
        }
    }
}
