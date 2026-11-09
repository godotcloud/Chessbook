import SwiftUI

struct ChessBoardView: View {
    let boardState: ChessBoardState
    var flipped: Bool = false
    var theme: BoardTheme = .brown
    var arrows: [BoardArrow] = []
    var circles: [BoardCircleHighlight] = []
    var interactive: Bool = true
    var onMoveExecuted: ((String) -> Void)? = nil

    @State private var selectedSquare: BoardSquare? = nil
    @State private var candidateSquares: Set<BoardSquare> = []

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let sqSize = side / 8.0

            ZStack {
                // 1. 8x8 Squares & Pieces
                VStack(spacing: 0) {
                    ForEach(0..<8, id: \.self) { rowIdx in
                        let rank = flipped ? rowIdx : (7 - rowIdx)
                        HStack(spacing: 0) {
                            ForEach(0..<8, id: \.self) { colIdx in
                                let file = flipped ? (7 - colIdx) : colIdx
                                let sq = BoardSquare(file: file, rank: rank)
                                squareCell(
                                    square: sq,
                                    size: sqSize,
                                    showRankCoord: colIdx == 0,
                                    showFileCoord: rowIdx == 7
                                )
                            }
                        }
                    }
                }
                .frame(width: side, height: side)

                // 2. Circle Highlights ([%csl ...])
                ForEach(circles) { circle in
                    let center = pointForSquare(circle.square, sqSize: sqSize)
                    Circle()
                        .strokeBorder(annotationColor(circle.colorCode), lineWidth: max(3, sqSize * 0.08))
                        .frame(width: sqSize * 0.88, height: sqSize * 0.88)
                        .position(center)
                        .allowsHitTesting(false)
                }

                // 3. Tactical Arrows ([%cal ...])
                Canvas { context, _ in
                    for arrow in arrows {
                        let startPt = pointForSquare(arrow.from, sqSize: sqSize)
                        let endPt = pointForSquare(arrow.to, sqSize: sqSize)
                        drawArrow(
                            in: &context,
                            from: startPt,
                            to: endPt,
                            color: annotationColor(arrow.colorCode),
                            sqSize: sqSize
                        )
                    }
                }
                .frame(width: side, height: side)
                .allowsHitTesting(false)
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.15), lineWidth: 1)
            )
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
        .onChange(of: boardState) { _ in
            selectedSquare = nil
            candidateSquares = []
        }
    }

    @ViewBuilder
    private func squareCell(
        square: BoardSquare,
        size: CGFloat,
        showRankCoord: Bool,
        showFileCoord: Bool
    ) -> some View {
        let isSelected = selectedSquare == square
        let isLastMove = boardState.lastMoveFrom == square || boardState.lastMoveTo == square
        let isCandidate = candidateSquares.contains(square)
        let piece = boardState.piece(at: square)

        ZStack {
            // Base square color
            Rectangle()
                .fill(square.isLightSquare ? theme.lightColor : theme.darkColor)

            // Last move highlight
            if isLastMove {
                Rectangle()
                    .fill(Color.yellow.opacity(0.42))
            }

            // Selected square highlight
            if isSelected {
                Rectangle()
                    .fill(Color.green.opacity(0.45))
            }

            // Rank & File Coordinates
            if showRankCoord {
                Text("\(square.rank + 1)")
                    .font(.system(size: max(9, size * 0.2), weight: .bold))
                    .foregroundColor(square.isLightSquare ? theme.darkColor : theme.lightColor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(2)
            }

            if showFileCoord {
                let fileChar = String(square.algebraic.prefix(1))
                Text(fileChar)
                    .font(.system(size: max(9, size * 0.2), weight: .bold))
                    .foregroundColor(square.isLightSquare ? theme.darkColor : theme.lightColor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(2)
            }

            // Piece rendering
            if let piece = piece {
                Text(piece.filledSymbol)
                    .font(.system(size: size * 0.74))
                    .foregroundStyle(piece.color == .white ? Color.white : Color(white: 0.12))
                    .shadow(
                        color: piece.color == .white ? .black.opacity(0.85) : .white.opacity(0.4),
                        radius: 1.5,
                        x: 0,
                        y: 1
                    )
            }

            // Legal destination indicator
            if isCandidate {
                if piece != nil {
                    Circle()
                        .strokeBorder(Color.green.opacity(0.75), lineWidth: max(3, size * 0.09))
                        .padding(3)
                } else {
                    Circle()
                        .fill(Color.green.opacity(0.55))
                        .frame(width: size * 0.3, height: size * 0.3)
                }
            }
        }
        .frame(width: size, height: size)
        .contentShape(Rectangle())
        .onTapGesture {
            handleSquareTap(square)
        }
    }

    private func handleSquareTap(_ tapped: BoardSquare) {
        guard interactive else { return }

        if let currentSelected = selectedSquare {
            if currentSelected == tapped {
                selectedSquare = nil
                candidateSquares = []
                return
            }
            if candidateSquares.contains(tapped) {
                var uci = currentSelected.algebraic + tapped.algebraic
                if let movingPiece = boardState.piece(at: currentSelected),
                   movingPiece.type == .pawn,
                   (tapped.rank == 7 || tapped.rank == 0) {
                    uci += "q"
                }
                selectedSquare = nil
                candidateSquares = []
                onMoveExecuted?(uci)
                return
            }
        }

        if let p = boardState.piece(at: tapped), p.color == boardState.turn {
            selectedSquare = tapped
            candidateSquares = Set(boardState.candidateDestinations(from: tapped))
        } else {
            selectedSquare = nil
            candidateSquares = []
        }
    }

    private func pointForSquare(_ sq: BoardSquare, sqSize: CGFloat) -> CGPoint {
        let col = flipped ? (7 - sq.file) : sq.file
        let row = flipped ? sq.rank : (7 - sq.rank)
        return CGPoint(
            x: (CGFloat(col) + 0.5) * sqSize,
            y: (CGFloat(row) + 0.5) * sqSize
        )
    }

    private func annotationColor(_ code: String) -> Color {
        switch code.uppercased() {
        case "G": return Color.green.opacity(0.82)
        case "R": return Color.red.opacity(0.82)
        case "B": return Color.blue.opacity(0.82)
        case "Y": return Color.orange.opacity(0.85)
        default: return Color.green.opacity(0.82)
        }
    }

    private func drawArrow(
        in context: inout GraphicsContext,
        from start: CGPoint,
        to end: CGPoint,
        color: Color,
        sqSize: CGFloat
    ) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let angle = atan2(dy, dx)
        let headLength = sqSize * 0.36
        let lineEnd = CGPoint(
            x: end.x - cos(angle) * (headLength * 0.65),
            y: end.y - sin(angle) * (headLength * 0.65)
        )

        var shaft = Path()
        shaft.move(to: start)
        shaft.addLine(to: lineEnd)
        context.stroke(
            shaft,
            with: .color(color),
            style: StrokeStyle(lineWidth: max(4, sqSize * 0.14), lineCap: .round)
        )

        var head = Path()
        let wingAngle: CGFloat = .pi / 6
        let p1 = CGPoint(
            x: end.x - headLength * cos(angle - wingAngle),
            y: end.y - headLength * sin(angle - wingAngle)
        )
        let p2 = CGPoint(
            x: end.x - headLength * cos(angle + wingAngle),
            y: end.y - headLength * sin(angle + wingAngle)
        )
        head.move(to: end)
        head.addLine(to: p1)
        head.addLine(to: p2)
        head.closeSubpath()
        context.fill(head, with: .color(color))
    }
}

struct EvalBarView: View {
    let whiteAdvantageRatio: Double // 0.0 (Black winning) .. 1.0 (White winning)
    let scoreText: String

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                Rectangle()
                    .fill(Color(white: 0.18))
                Rectangle()
                    .fill(Color(white: 0.95))
                    .frame(height: geo.size.height * CGFloat(max(0.04, min(0.96, whiteAdvantageRatio))))
                    .animation(.easeInOut(duration: 0.25), value: whiteAdvantageRatio)

                Text(scoreText)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(whiteAdvantageRatio >= 0.5 ? .black : .white)
                    .padding(.vertical, 4)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            )
        }
    }
}
