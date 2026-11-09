import Foundation
import SwiftUI

enum PieceColor: String, Codable, CaseIterable {
    case white = "w"
    case black = "b"

    var opposite: PieceColor {
        self == .white ? .black : .white
    }

    var displayName: String {
        self == .white ? "白方" : "黑方"
    }
}

enum PieceType: String, Codable, CaseIterable {
    case king = "k"
    case queen = "q"
    case rook = "r"
    case bishop = "b"
    case knight = "n"
    case pawn = "p"

    var chineseName: String {
        switch self {
        case .king: return "王"
        case .queen: return "后"
        case .rook: return "车"
        case .bishop: return "象"
        case .knight: return "马"
        case .pawn: return "兵"
        }
    }
}

struct ChessPiece: Equatable, Identifiable {
    var id: String { "\(color.rawValue)_\(type.rawValue)" }
    let type: PieceType
    let color: PieceColor

    var symbol: String {
        switch (color, type) {
        case (.white, .king): return "♔"
        case (.white, .queen): return "♕"
        case (.white, .rook): return "♖"
        case (.white, .bishop): return "♗"
        case (.white, .knight): return "♘"
        case (.white, .pawn): return "♙"
        case (.black, .king): return "♚"
        case (.black, .queen): return "♛"
        case (.black, .rook): return "♜"
        case (.black, .bishop): return "♝"
        case (.black, .knight): return "♞"
        case (.black, .pawn): return "♟"
        }
    }

    var filledSymbol: String {
        switch type {
        case .king: return "♚"
        case .queen: return "♛"
        case .rook: return "♜"
        case .bishop: return "♝"
        case .knight: return "♞"
        case .pawn: return "♟"
        }
    }

    var fenChar: Character {
        let ch = Character(type.rawValue)
        return color == .white ? Character(ch.uppercased()) : ch
    }

    init?(fenChar: Character) {
        let lower = Character(fenChar.lowercased())
        guard let t = PieceType(rawValue: String(lower)) else { return nil }
        self.type = t
        self.color = fenChar.isUppercase ? .white : .black
    }

    init(type: PieceType, color: PieceColor) {
        self.type = type
        self.color = color
    }
}

struct BoardSquare: Hashable, Codable, CustomStringConvertible {
    let file: Int // 0..7 (a..h)
    let rank: Int // 0..7 (1..8, where 0 is rank 1)

    init(file: Int, rank: Int) {
        self.file = file
        self.rank = rank
    }

    init?(algebraic: String) {
        let chars = Array(algebraic.lowercased())
        guard chars.count == 2,
              let fileAscii = chars[0].asciiValue,
              let rankAscii = chars[1].asciiValue else { return nil }
        let f = Int(fileAscii) - Int(Character("a").asciiValue!)
        let r = Int(rankAscii) - Int(Character("1").asciiValue!)
        guard (0..<8).contains(f) && (0..<8).contains(r) else { return nil }
        self.file = f
        self.rank = r
    }

    var algebraic: String {
        let fChar = Character(UnicodeScalar(Int(Character("a").asciiValue!) + file)!)
        let rChar = Character(UnicodeScalar(Int(Character("1").asciiValue!) + rank)!)
        return "\(fChar)\(rChar)"
    }

    var description: String { algebraic }

    var isLightSquare: Bool {
        (file + rank) % 2 != 0
    }
}

struct BoardArrow: Identifiable, Equatable {
    var id: String { "\(from.algebraic)->\(to.algebraic)_\(colorCode)" }
    let from: BoardSquare
    let to: BoardSquare
    let colorCode: String // G, R, B, Y
}

struct BoardCircleHighlight: Identifiable, Equatable {
    var id: String { "\(square.algebraic)_\(colorCode)" }
    let square: BoardSquare
    let colorCode: String // G, R, B, Y
}

enum BoardTheme: String, CaseIterable, Identifiable {
    case brown = "brown"
    case green = "green"
    case blue = "blue"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .brown: return "Lichess 经典木纹"
        case .green: return "锦标赛森林绿"
        case .blue: return "深海冰川蓝"
        }
    }

    var lightColor: Color {
        switch self {
        case .brown: return Color(red: 0.94, green: 0.85, blue: 0.71)
        case .green: return Color(red: 0.93, green: 0.93, blue: 0.82)
        case .blue: return Color(red: 0.87, green: 0.91, blue: 0.95)
        }
    }

    var darkColor: Color {
        switch self {
        case .brown: return Color(red: 0.71, green: 0.53, blue: 0.39)
        case .green: return Color(red: 0.46, green: 0.59, blue: 0.34)
        case .blue: return Color(red: 0.38, green: 0.55, blue: 0.72)
        }
    }
}

struct ChessBoardState: Equatable {
    static let startingFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

    private(set) var grid: [[ChessPiece?]] = Array(
        repeating: Array(repeating: nil, count: 8),
        count: 8
    ) // [rank][file]
    var turn: PieceColor = .white
    var castlingRights: String = "KQkq"
    var enPassantTarget: BoardSquare? = nil
    var halfmoveClock: Int = 0
    var fullmoveNumber: Int = 1
    var lastMoveFrom: BoardSquare? = nil
    var lastMoveTo: BoardSquare? = nil

    init(fen: String = ChessBoardState.startingFEN) {
        loadFEN(fen)
    }

    func piece(at square: BoardSquare) -> ChessPiece? {
        guard (0..<8).contains(square.rank), (0..<8).contains(square.file) else { return nil }
        return grid[square.rank][square.file]
    }

    mutating func setPiece(_ piece: ChessPiece?, at square: BoardSquare) {
        guard (0..<8).contains(square.rank), (0..<8).contains(square.file) else { return }
        grid[square.rank][square.file] = piece
    }

    mutating func loadFEN(_ fen: String) {
        grid = Array(repeating: Array(repeating: nil, count: 8), count: 8)
        let components = fen.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ")
        guard let boardPart = components.first else { return }

        let ranks = boardPart.split(separator: "/")
        for (idx, rankStr) in ranks.enumerated() {
            let rank = 7 - idx
            guard (0..<8).contains(rank) else { continue }
            var file = 0
            for ch in rankStr {
                if let emptyCount = ch.wholeNumberValue {
                    file += emptyCount
                } else if let p = ChessPiece(fenChar: ch) {
                    if file < 8 {
                        grid[rank][file] = p
                    }
                    file += 1
                }
            }
        }

        if components.count > 1 {
            turn = components[1] == "b" ? .black : .white
        }
        if components.count > 2 {
            castlingRights = String(components[2])
        }
        if components.count > 3 {
            let ep = String(components[3])
            enPassantTarget = ep == "-" ? nil : BoardSquare(algebraic: ep)
        }
        if components.count > 4, let hm = Int(components[4]) {
            halfmoveClock = hm
        }
        if components.count > 5, let fm = Int(components[5]) {
            fullmoveNumber = fm
        }
    }

    func toFEN() -> String {
        var rankStrings: [String] = []
        for r in stride(from: 7, through: 0, by: -1) {
            var str = ""
            var empty = 0
            for f in 0..<8 {
                if let p = grid[r][f] {
                    if empty > 0 {
                        str.append("\(empty)")
                        empty = 0
                    }
                    str.append(p.fenChar)
                } else {
                    empty += 1
                }
            }
            if empty > 0 { str.append("\(empty)") }
            rankStrings.append(str)
        }
        let boardPart = rankStrings.joined(separator: "/")
        let ep = enPassantTarget?.algebraic ?? "-"
        let castle = castlingRights.isEmpty ? "-" : castlingRights
        return "\(boardPart) \(turn.rawValue) \(castle) \(ep) \(halfmoveClock) \(fullmoveNumber)"
    }

    /// Applies a UCI move like "e2e4" or "e7e8q"
    mutating func applyUCIMove(_ uci: String) -> Bool {
        let clean = uci.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard clean.count >= 4 else { return false }
        let startIdx = clean.startIndex
        let fromStr = String(clean[startIdx..<clean.index(startIdx, offsetBy: 2)])
        let toStr = String(clean[clean.index(startIdx, offsetBy: 2)..<clean.index(startIdx, offsetBy: 4)])
        guard let from = BoardSquare(algebraic: fromStr),
              let to = BoardSquare(algebraic: toStr),
              let movingPiece = piece(at: from) else { return false }

        var promoType: PieceType? = nil
        if clean.count >= 5 {
            let promoChar = String(clean[clean.index(startIdx, offsetBy: 4)])
            promoType = PieceType(rawValue: promoChar)
        }

        // Handle Castling (standard & 960 king-takes-rook style)
        if movingPiece.type == .king && abs(to.file - from.file) > 1 {
            setPiece(nil, at: from)
            if to.file > from.file {
                // Kingside O-O
                let rookFrom = BoardSquare(file: 7, rank: from.rank)
                let rookTo = BoardSquare(file: 5, rank: from.rank)
                let kingTo = BoardSquare(file: 6, rank: from.rank)
                let rook = piece(at: rookFrom) ?? ChessPiece(type: .rook, color: movingPiece.color)
                setPiece(nil, at: rookFrom)
                setPiece(movingPiece, at: kingTo)
                setPiece(rook, at: rookTo)
            } else {
                // Queenside O-O-O
                let rookFrom = BoardSquare(file: 0, rank: from.rank)
                let rookTo = BoardSquare(file: 3, rank: from.rank)
                let kingTo = BoardSquare(file: 2, rank: from.rank)
                let rook = piece(at: rookFrom) ?? ChessPiece(type: .rook, color: movingPiece.color)
                setPiece(nil, at: rookFrom)
                setPiece(movingPiece, at: kingTo)
                setPiece(rook, at: rookTo)
            }
        } else {
            // Handle En Passant capture
            if movingPiece.type == .pawn,
               from.file != to.file,
               piece(at: to) == nil {
                let capturedSquare = BoardSquare(file: to.file, rank: from.rank)
                setPiece(nil, at: capturedSquare)
            }

            setPiece(nil, at: from)
            if let promo = promoType {
                setPiece(ChessPiece(type: promo, color: movingPiece.color), at: to)
            } else if movingPiece.type == .pawn && (to.rank == 7 || to.rank == 0) {
                setPiece(ChessPiece(type: .queen, color: movingPiece.color), at: to)
            } else {
                setPiece(movingPiece, at: to)
            }
        }

        // Update En Passant square
        if movingPiece.type == .pawn && abs(to.rank - from.rank) == 2 {
            enPassantTarget = BoardSquare(file: from.file, rank: (from.rank + to.rank) / 2)
        } else {
            enPassantTarget = nil
        }

        lastMoveFrom = from
        lastMoveTo = to
        if turn == .black {
            fullmoveNumber += 1
        }
        turn = turn.opposite
        return true
    }

    /// Generates candidate squares a piece at `from` can move to
    func candidateDestinations(from square: BoardSquare) -> [BoardSquare] {
        guard let p = piece(at: square) else { return [] }
        var targets: [BoardSquare] = []

        func addIfValid(_ f: Int, _ r: Int) -> Bool {
            guard (0..<8).contains(f), (0..<8).contains(r) else { return false }
            let sq = BoardSquare(file: f, rank: r)
            if let occ = piece(at: sq) {
                if occ.color != p.color {
                    targets.append(sq)
                }
                return false
            }
            targets.append(sq)
            return true
        }

        switch p.type {
        case .pawn:
            let dir = p.color == .white ? 1 : -1
            let startRank = p.color == .white ? 1 : 6
            let oneStep = BoardSquare(file: square.file, rank: square.rank + dir)
            if (0..<8).contains(oneStep.rank) && piece(at: oneStep) == nil {
                targets.append(oneStep)
                let twoStep = BoardSquare(file: square.file, rank: square.rank + 2 * dir)
                if square.rank == startRank && piece(at: twoStep) == nil {
                    targets.append(twoStep)
                }
            }
            for df in [-1, 1] {
                let cf = square.file + df
                let cr = square.rank + dir
                guard (0..<8).contains(cf), (0..<8).contains(cr) else { continue }
                let capSq = BoardSquare(file: cf, rank: cr)
                if let occ = piece(at: capSq), occ.color != p.color {
                    targets.append(capSq)
                } else if capSq == enPassantTarget {
                    targets.append(capSq)
                }
            }

        case .knight:
            let jumps = [(-2,-1),(-2,1),(-1,-2),(-1,2),(1,-2),(1,2),(2,-1),(2,1)]
            for (df, dr) in jumps {
                _ = addIfValid(square.file + df, square.rank + dr)
            }

        case .bishop:
            for (df, dr) in [(-1,-1),(-1,1),(1,-1),(1,1)] {
                var step = 1
                while addIfValid(square.file + df * step, square.rank + dr * step) {
                    step += 1
                }
            }

        case .rook:
            for (df, dr) in [(-1,0),(1,0),(0,-1),(0,1)] {
                var step = 1
                while addIfValid(square.file + df * step, square.rank + dr * step) {
                    step += 1
                }
            }

        case .queen:
            for (df, dr) in [(-1,-1),(-1,1),(1,-1),(1,1),(-1,0),(1,0),(0,-1),(0,1)] {
                var step = 1
                while addIfValid(square.file + df * step, square.rank + dr * step) {
                    step += 1
                }
            }

        case .king:
            for df in -1...1 {
                for dr in -1...1 where !(df == 0 && dr == 0) {
                    _ = addIfValid(square.file + df, square.rank + dr)
                }
            }
            // Castling squares
            let homeRank = p.color == .white ? 0 : 7
            if square.file == 4 && square.rank == homeRank {
                if piece(at: BoardSquare(file: 5, rank: homeRank)) == nil &&
                   piece(at: BoardSquare(file: 6, rank: homeRank)) == nil {
                    targets.append(BoardSquare(file: 6, rank: homeRank))
                }
                if piece(at: BoardSquare(file: 3, rank: homeRank)) == nil &&
                   piece(at: BoardSquare(file: 2, rank: homeRank)) == nil &&
                   piece(at: BoardSquare(file: 1, rank: homeRank)) == nil {
                    targets.append(BoardSquare(file: 2, rank: homeRank))
                }
            }
        }

        return targets
    }

    /// Resolves Standard Algebraic Notation (SAN, e.g. "Nf3", "exd5", "O-O", "Qh4#") and applies it
    mutating func applySANMove(_ sanRaw: String) -> String? {
        var san = sanRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip check/mate/annotation suffixes
        while let last = san.last, "+#!?".contains(last) {
            san.removeLast()
        }
        guard !san.isEmpty else { return nil }

        let homeRank = turn == .white ? 0 : 7
        if san == "O-O" || san == "0-0" {
            let uci = BoardSquare(file: 4, rank: homeRank).algebraic + BoardSquare(file: 6, rank: homeRank).algebraic
            _ = applyUCIMove(uci)
            return uci
        }
        if san == "O-O-O" || san == "0-0-0" {
            let uci = BoardSquare(file: 4, rank: homeRank).algebraic + BoardSquare(file: 2, rank: homeRank).algebraic
            _ = applyUCIMove(uci)
            return uci
        }

        // Promotion check (e.g. e8=Q)
        var promoSuffix = ""
        if let eqIdx = san.firstIndex(of: "=") {
            let afterEq = san[san.index(after: eqIdx)...]
            if let firstPromo = afterEq.first {
                promoSuffix = String(firstPromo).lowercased()
            }
            san = String(san[..<eqIdx])
        }

        san = san.replacingOccurrences(of: "x", with: "")
        guard san.count >= 2 else { return nil }

        let destStr = String(san.suffix(2))
        guard let destSquare = BoardSquare(algebraic: destStr) else { return nil }
        let prefix = String(san.dropLast(2))

        var pieceType: PieceType = .pawn
        var disambig = prefix
        if let first = prefix.first, first.isUppercase {
            switch first {
            case "K": pieceType = .king
            case "Q": pieceType = .queen
            case "R": pieceType = .rook
            case "B": pieceType = .bishop
            case "N": pieceType = .knight
            default: pieceType = .pawn
            }
            disambig = String(prefix.dropFirst())
        }

        var requiredFile: Int? = nil
        var requiredRank: Int? = nil
        for ch in disambig {
            if let ascii = ch.asciiValue {
                if ch >= "a" && ch <= "h" {
                    requiredFile = Int(ascii) - Int(Character("a").asciiValue!)
                } else if ch >= "1" && ch <= "8" {
                    requiredRank = Int(ascii) - Int(Character("1").asciiValue!)
                }
            }
        }

        for r in 0..<8 {
            for f in 0..<8 {
                if let reqF = requiredFile, reqF != f { continue }
                if let reqR = requiredRank, reqR != r { continue }
                let sq = BoardSquare(file: f, rank: r)
                guard let p = piece(at: sq), p.color == turn, p.type == pieceType else { continue }
                let candidates = candidateDestinations(from: sq)
                if candidates.contains(destSquare) {
                    let uci = sq.algebraic + destSquare.algebraic + promoSuffix
                    _ = applyUCIMove(uci)
                    return uci
                }
            }
        }
        return nil
    }
}
