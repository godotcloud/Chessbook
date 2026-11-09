import Foundation

struct StudyMoveStep: Identifiable, Equatable {
    let id = UUID()
    let plyIndex: Int
    let moveNumberDisplay: String
    let san: String
    let uci: String
    let fenAfterMove: String
    let rawComment: String
    let arrows: [BoardArrow]
    let circles: [BoardCircleHighlight]
}

struct StudyChapter: Identifiable, Equatable {
    let id = UUID()
    let index: Int
    let title: String
    let event: String
    let site: String
    let initialFEN: String
    let openingComment: String
    let openingArrows: [BoardArrow]
    let openingCircles: [BoardCircleHighlight]
    let steps: [StudyMoveStep]
}

enum PGNParser {
    /// Parses a multi-game / multi-chapter PGN string exported from Lichess Study
    static func parseStudyPGN(_ pgnText: String) -> [StudyChapter] {
        let normalized = pgnText.replacingOccurrences(of: "\r\n", with: "\n")
        let rawGames = splitIntoGames(normalized)
        var chapters: [StudyChapter] = []

        for (idx, rawGame) in rawGames.enumerated() {
            if let chapter = parseSingleChapter(rawGame, index: idx + 1) {
                chapters.append(chapter)
            }
        }
        return chapters
    }

    private static func splitIntoGames(_ pgn: String) -> [String] {
        let lines = pgn.components(separatedBy: "\n")
        var games: [String] = []
        var currentLines: [String] = []
        var seenMoveText = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[Event ") && seenMoveText {
                games.append(currentLines.joined(separator: "\n"))
                currentLines = [line]
                seenMoveText = false
            } else {
                if !trimmed.isEmpty && !trimmed.hasPrefix("[") {
                    seenMoveText = true
                }
                currentLines.append(line)
            }
        }
        let remainder = currentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if !remainder.isEmpty {
            games.append(remainder)
        }
        return games
    }

    private static func parseSingleChapter(_ rawGame: String, index: Int) -> StudyChapter? {
        var headers: [String: String] = [:]
        var bodyLines: [String] = []

        for line in rawGame.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                let inner = String(trimmed.dropFirst().dropLast())
                if let firstSpace = inner.firstIndex(of: " ") {
                    let key = String(inner[..<firstSpace])
                    var val = String(inner[inner.index(after: firstSpace)...]).trimmingCharacters(in: .whitespaces)
                    if val.hasPrefix("\"") && val.hasSuffix("\"") && val.count >= 2 {
                        val = String(val.dropFirst().dropLast())
                    }
                    headers[key] = val
                }
            } else {
                bodyLines.append(line)
            }
        }

        let eventName = headers["Event"] ?? "章节 \(index)"
        let chapterTitle: String
        if let colonRange = eventName.range(of: ": ") {
            chapterTitle = String(eventName[colonRange.upperBound...])
        } else {
            chapterTitle = eventName
        }

        let initialFEN = headers["FEN"] ?? ChessBoardState.startingFEN
        let site = headers["Site"] ?? "https://lichess.org"
        let body = bodyLines.joined(separator: " ")

        return parseMoveBody(
            body: body,
            index: index,
            title: chapterTitle,
            event: eventName,
            site: site,
            initialFEN: initialFEN
        )
    }

    private static func parseMoveBody(
        body: String,
        index: Int,
        title: String,
        event: String,
        site: String,
        initialFEN: String
    ) -> StudyChapter {
        var board = ChessBoardState(fen: initialFEN)
        var steps: [StudyMoveStep] = []
        var openingComment = ""
        var openingArrows: [BoardArrow] = []
        var openingCircles: [BoardCircleHighlight] = []

        // Tokenize PGN body preserving { ... } comments and skipping nested (...) ravs for main line
        var i = body.startIndex
        var variationDepth = 0
        var tokens: [String] = []
        var currentToken = ""

        while i < body.endIndex {
            let ch = body[i]
            if ch == "{" {
                if variationDepth == 0 {
                    if !currentToken.isEmpty {
                        tokens.append(currentToken)
                        currentToken = ""
                    }
                    var commentStr = "{"
                    i = body.index(after: i)
                    while i < body.endIndex && body[i] != "}" {
                        commentStr.append(body[i])
                        i = body.index(after: i)
                    }
                    commentStr.append("}")
                    tokens.append(commentStr)
                } else {
                    while i < body.endIndex && body[i] != "}" {
                        i = body.index(after: i)
                    }
                }
            } else if ch == "(" {
                if !currentToken.isEmpty && variationDepth == 0 {
                    tokens.append(currentToken)
                    currentToken = ""
                }
                variationDepth += 1
            } else if ch == ")" {
                variationDepth = max(0, variationDepth - 1)
            } else if variationDepth == 0 {
                if ch.isWhitespace {
                    if !currentToken.isEmpty {
                        tokens.append(currentToken)
                        currentToken = ""
                    }
                } else {
                    currentToken.append(ch)
                }
            }
            if i < body.endIndex {
                i = body.index(after: i)
            }
        }
        if !currentToken.isEmpty && variationDepth == 0 {
            tokens.append(currentToken)
        }

        for token in tokens {
            if token.hasPrefix("{") && token.hasSuffix("}") {
                let rawInside = String(token.dropFirst().dropLast())
                let parsed = extractAnnotationsAndCleanComment(rawInside)
                if steps.isEmpty {
                    if !parsed.cleanText.isEmpty {
                        openingComment = openingComment.isEmpty ? parsed.cleanText : (openingComment + "\n" + parsed.cleanText)
                    }
                    openingArrows.append(contentsOf: parsed.arrows)
                    openingCircles.append(contentsOf: parsed.circles)
                } else {
                    let last = steps.removeLast()
                    let combinedText = last.rawComment.isEmpty ? parsed.cleanText : (last.rawComment + "\n" + parsed.cleanText)
                    let updated = StudyMoveStep(
                        plyIndex: last.plyIndex,
                        moveNumberDisplay: last.moveNumberDisplay,
                        san: last.san,
                        uci: last.uci,
                        fenAfterMove: last.fenAfterMove,
                        rawComment: combinedText,
                        arrows: last.arrows + parsed.arrows,
                        circles: last.circles + parsed.circles
                    )
                    steps.append(updated)
                }
                continue
            }

            // Skip game result tokens or NAGs
            if ["1-0", "0-1", "1/2-1/2", "*"].contains(token) { continue }
            if token.hasPrefix("$") {
                if let nagSymbol = nagToSymbol(token), !steps.isEmpty {
                    let last = steps.removeLast()
                    let updated = StudyMoveStep(
                        plyIndex: last.plyIndex,
                        moveNumberDisplay: last.moveNumberDisplay,
                        san: last.san + nagSymbol,
                        uci: last.uci,
                        fenAfterMove: last.fenAfterMove,
                        rawComment: last.rawComment,
                        arrows: last.arrows,
                        circles: last.circles
                    )
                    steps.append(updated)
                }
                continue
            }

            // Strip leading move numbers like "1." or "12...Nf6"
            var cleanMove = token
            if let lastDot = cleanMove.lastIndex(of: ".") {
                cleanMove = String(cleanMove[cleanMove.index(after: lastDot)...])
            }
            guard !cleanMove.isEmpty else { continue }

            let moveNumber = board.fullmoveNumber
            let isWhite = board.turn == .white
            let moveNumDisplay = isWhite ? "\(moveNumber). \(cleanMove)" : "\(moveNumber)... \(cleanMove)"

            if let uci = board.applySANMove(cleanMove) {
                let step = StudyMoveStep(
                    plyIndex: steps.count + 1,
                    moveNumberDisplay: moveNumDisplay,
                    san: cleanMove,
                    uci: uci,
                    fenAfterMove: board.toFEN(),
                    rawComment: "",
                    arrows: [],
                    circles: []
                )
                steps.append(step)
            }
        }

        return StudyChapter(
            index: index,
            title: title,
            event: event,
            site: site,
            initialFEN: initialFEN,
            openingComment: openingComment,
            openingArrows: openingArrows,
            openingCircles: openingCircles,
            steps: steps
        )
    }

    private static func nagToSymbol(_ nag: String) -> String? {
        switch nag {
        case "$1": return "!"
        case "$2": return "?"
        case "$3": return "!!"
        case "$4": return "??"
        case "$5": return "!?"
        case "$6": return "?!"
        default: return nil
        }
    }

    /// Extracts Lichess `[%cal Ge2e4,Rf3g5]` arrows and `[%csl Gf7]` circles, returning clean commentary text
    static func extractAnnotationsAndCleanComment(_ raw: String) -> (cleanText: String, arrows: [BoardArrow], circles: [BoardCircleHighlight]) {
        var arrows: [BoardArrow] = []
        var circles: [BoardCircleHighlight] = []

        // Parse [%cal ...]
        if let calRegex = try? NSRegularExpression(pattern: #"\[%cal\s+([^\]]+)\]"#) {
            let nsRange = NSRange(raw.startIndex..<raw.endIndex, in: raw)
            for match in calRegex.matches(in: raw, range: nsRange) {
                if let range = Range(match.range(at: 1), in: raw) {
                    let items = raw[range].split(separator: ",")
                    for item in items {
                        let s = item.trimmingCharacters(in: .whitespaces)
                        if s.count >= 5 {
                            let color = String(s.prefix(1)).uppercased()
                            let fromStr = String(s.dropFirst().prefix(2))
                            let toStr = String(s.dropFirst(3).prefix(2))
                            if let fromSq = BoardSquare(algebraic: fromStr),
                               let toSq = BoardSquare(algebraic: toStr) {
                                arrows.append(BoardArrow(from: fromSq, to: toSq, colorCode: color))
                            }
                        }
                    }
                }
            }
        }

        // Parse [%csl ...]
        if let cslRegex = try? NSRegularExpression(pattern: #"\[%csl\s+([^\]]+)\]"#) {
            let nsRange = NSRange(raw.startIndex..<raw.endIndex, in: raw)
            for match in cslRegex.matches(in: raw, range: nsRange) {
                if let range = Range(match.range(at: 1), in: raw) {
                    let items = raw[range].split(separator: ",")
                    for item in items {
                        let s = item.trimmingCharacters(in: .whitespaces)
                        if s.count >= 3 {
                            let color = String(s.prefix(1)).uppercased()
                            let sqStr = String(s.dropFirst().prefix(2))
                            if let sq = BoardSquare(algebraic: sqStr) {
                                circles.append(BoardCircleHighlight(square: sq, colorCode: color))
                            }
                        }
                    }
                }
            }
        }

        // Strip all [%...] metadata tags (e.g., [%clk ...], [%eval ...], [%cal ...], [%csl ...])
        var cleaned = raw
        if let tagRegex = try? NSRegularExpression(pattern: #"\[%[^\]]+\]"#) {
            let range = NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned)
            cleaned = tagRegex.stringByReplacingMatches(in: cleaned, range: range, withTemplate: "")
        }
        cleaned = cleaned
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return (cleaned, arrows, circles)
    }
}
