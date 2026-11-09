import Foundation

enum TranslationProviderType: String, CaseIterable, Identifiable {
    case gtxHybrid = "gtx_hybrid"
    case pollinationsLLM = "pollinations_llm"
    case lingvaGoogle = "lingva_google"
    case myMemory = "mymemory_free"
    case localGlossaryOnly = "local_glossary"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gtxHybrid:
            return "GTX 极速神经翻译 + 完整国际象棋术语库 (免Key·毫秒级)"
        case .pollinationsLLM:
            return "Pollinations AI 大模型 (免Key·大师语境精译)"
        case .lingvaGoogle:
            return "Lingva 开源神经代理 + 术语库 (免Key)"
        case .myMemory:
            return "MyMemory 协作翻译 API + 术语库 (免Key)"
        case .localGlossaryOnly:
            return "离线国际象棋专业术语直译 (零网络延迟)"
        }
    }

    var shortBadge: String {
        switch self {
        case .gtxHybrid: return "GTX+棋库"
        case .pollinationsLLM: return "AI大模型"
        case .lingvaGoogle: return "Lingva+棋库"
        case .myMemory: return "MyMemory"
        case .localGlossaryOnly: return "离线棋库"
        }
    }
}

actor ChessTranslationService {
    static let shared = ChessTranslationService()

    private var cache: [String: String] = [:]

    func clearCache() {
        cache.removeAll()
    }

    func translateToChinese(
        text: String,
        preferredProvider: TranslationProviderType
    ) async -> (translated: String, usedProvider: TranslationProviderType) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ("", preferredProvider) }

        if containsMostlyChinese(trimmed) {
            return (ChessGlossaryProcessor.postProcessChineseChessTerms(trimmed), preferredProvider)
        }

        let cacheKey = "\(preferredProvider.rawValue)|\(trimmed)"
        if let cached = cache[cacheKey] {
            return (cached, preferredProvider)
        }

        var chain: [TranslationProviderType] = [preferredProvider]
        for fallback in [TranslationProviderType.gtxHybrid, .lingvaGoogle, .myMemory, .pollinationsLLM, .localGlossaryOnly] {
            if !chain.contains(fallback) {
                chain.append(fallback)
            }
        }

        for provider in chain {
            if let rawTranslated = try? await executeTranslation(text: trimmed, provider: provider),
               !rawTranslated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let polished = ChessGlossaryProcessor.postProcessChineseChessTerms(rawTranslated)
                cache[cacheKey] = polished
                return (polished, provider)
            }
        }

        let offlineFallback = ChessGlossaryProcessor.postProcessChineseChessTerms(
            ChessGlossaryProcessor.preAnnotateTermsForMT(trimmed)
        )
        return (offlineFallback, .localGlossaryOnly)
    }

    private func executeTranslation(text: String, provider: TranslationProviderType) async throws -> String {
        switch provider {
        case .gtxHybrid:
            return try await translateViaGTX(text: text)
        case .pollinationsLLM:
            return try await translateViaPollinationsLLM(text: text)
        case .lingvaGoogle:
            return try await translateViaLingva(text: text)
        case .myMemory:
            return try await translateViaMyMemory(text: text)
        case .localGlossaryOnly:
            return ChessGlossaryProcessor.preAnnotateTermsForMT(text)
        }
    }

    private func translateViaGTX(text: String) async throws -> String {
        // Inject authoritative Chinese chess terms BEFORE sending to GTX so White/Black, mate, check,
        // bishop, knight, rook, queen, king, pawn, file, rank, square are 100% unified and never mistranslated!
        let prepped = ChessGlossaryProcessor.preAnnotateTermsForMT(text)
        var comps = URLComponents(string: "https://translate.googleapis.com/translate_a/single")
        comps?.queryItems = [
            URLQueryItem(name: "client", value: "gtx"),
            URLQueryItem(name: "sl", value: "en"),
            URLQueryItem(name: "tl", value: "zh-CN"),
            URLQueryItem(name: "dt", value: "t"),
            URLQueryItem(name: "q", value: prepped)
        ]
        guard let url = comps?.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        if let outer = try JSONSerialization.jsonObject(with: data) as? [Any],
           let sentences = outer.first as? [Any] {
            var output = ""
            for item in sentences {
                if let arr = item as? [Any], let segment = arr.first as? String {
                    output += segment
                }
            }
            if !output.isEmpty {
                return output
            }
        }
        throw URLError(.cannotParseResponse)
    }

    private func translateViaPollinationsLLM(text: String) async throws -> String {
        guard let url = URL(string: "https://text.pollinations.ai/openai") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let systemPrompt = """
        你是一位精通国际象棋的特级大师兼中文棋评翻译专家。请将以下 Lichess 研习(Study)的章节标题或着法注解准确、简练地翻译为简体中文。
        严格遵守以下中国国际象棋标准译名（绝不允许前后不一致）：
        1. 阵营：White=白方（绝不可译为白人/白色），Black=黑方（绝不可译为黑人/黑色）。
        2. 棋子统一译名：King=王，Queen=后，Rook=车（不可译为城堡），Bishop=象（不可译为主教；light-squared bishop=白格象，dark-squared bishop=黑格象，bishop pair=双象），Knight=马（不可译为骑士），Pawn=兵（不可译为典当/卒）。
        3. 核心术语：check=将军（不可译为检查/支票），checkmate/mate=将杀/杀棋（不可译为交配/配偶），stalemate=逼和，castling/O-O=王车易位/短易位，en passant=吃过路兵，file=竖线/开放线，rank=横线/底线，diagonal=斜线，square=格，exchange=兑子/半子，sacrifice=弃子/弃兵，variation=变例，study=研习，development=出子，pin=牵制，fork=捉双，skewer=串击，discovered attack=闪击，zugzwang=楚茨文克(迫移)，outpost=前哨格，passed pawn=通路兵，isolated pawn=孤兵，backward pawn=落后兵，doubled pawns=叠兵。
        4. 保留所有代数记谱法着法（如 1.e4, Nf3, Bd2, Qc2, Qb3, Qxf7#, O-O）原样不变。只输出中文译文。
        """

        let payload: [String: Any] = [
            "model": "openai",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text]
            ],
            "temperature": 0.15
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let choices = json["choices"] as? [[String: Any]],
           let first = choices.first,
           let message = first["message"] as? [String: Any],
           let content = message["content"] as? String {
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let rawStr = String(data: data, encoding: .utf8), !rawStr.isEmpty {
            return rawStr.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        throw URLError(.cannotParseResponse)
    }

    private func translateViaLingva(text: String) async throws -> String {
        let instances = [
            "https://lingva.ml",
            "https://lingva.lunar.icu",
            "https://translate.plausibility.cloud"
        ]
        let prepped = ChessGlossaryProcessor.preAnnotateTermsForMT(text)
        guard let encoded = prepped.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw URLError(.badURL)
        }

        for base in instances {
            guard let url = URL(string: "\(base)/api/v1/en/zh/\(encoded)") else { continue }
            var request = URLRequest(url: url)
            request.timeoutInterval = 5
            if let (data, response) = try? await URLSession.shared.data(for: request),
               let http = response as? HTTPURLResponse,
               (200...299).contains(http.statusCode),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let translation = json["translation"] as? String,
               !translation.isEmpty {
                return translation
            }
        }
        throw URLError(.cannotConnectToHost)
    }

    private func translateViaMyMemory(text: String) async throws -> String {
        let prepped = ChessGlossaryProcessor.preAnnotateTermsForMT(String(text.prefix(480)))
        var comps = URLComponents(string: "https://api.mymemory.translated.net/get")
        comps?.queryItems = [
            URLQueryItem(name: "q", value: prepped),
            URLQueryItem(name: "langpair", value: "en|zh-CN")
        ]
        guard let url = comps?.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let respData = json["responseData"] as? [String: Any],
           let translatedText = respData["translatedText"] as? String,
           !translatedText.isEmpty {
            return translatedText
        }
        throw URLError(.cannotParseResponse)
    }

    private func containsMostlyChinese(_ s: String) -> Bool {
        var cjkCount = 0
        for scalar in s.unicodeScalars {
            if (0x4E00...0x9FFF).contains(scalar.value) {
                cjkCount += 1
            }
        }
        return cjkCount > max(3, (s.count * 2) / 5)
    }
}

// MARK: - Complete Authoritative Chinese Chess Terminology Engine
enum ChessGlossaryProcessor {

    /// Ordered from longest/most-specific multi-word phrases down to core single-word chess nouns/verbs.
    /// Injecting these Chinese domain terms BEFORE calling neural MT guarantees that:
    /// - "White" / "Black" are NEVER translated as "白人" / "黑人"
    /// - "mate" is NEVER translated as "交配" / "配偶"
    /// - "check" is NEVER translated as "检查" / "支票"
    /// - "bishop", "knight", "rook", "queen", "king", "pawn" are 100% consistently "象", "马", "车", "后", "王", "兵"
    static let orderedPreMTGlossary: [(pattern: String, replacement: String)] = [
        // 0. Non-chess idioms containing "check" or "mate" that must be disambiguated first
        ("check out", "查看"),
        ("checks out", "查看"),
        ("checking out", "查看"),
        ("check if", "看看是否"),
        ("check whether", "看看是否"),
        ("double-check", "仔细确认"),
        ("team mate", "队友"),
        ("teammate", "队友"),

        // 1. Standard Opening Systems & Variations
        ("queen's gambit declined", "拒后翼弃兵"),
        ("queen's gambit accepted", "受后翼弃兵"),
        ("queen's gambit", "后翼弃兵"),
        ("king's indian defense", "古印度防御"),
        ("king's indian defence", "古印度防御"),
        ("king's indian attack", "古印度攻击"),
        ("king's indian", "古印度防御"),
        ("nimzo-indian defense", "尼姆佐-印度防御"),
        ("nimzo-indian defence", "尼姆佐-印度防御"),
        ("nimzo-indian", "尼姆佐-印度防御"),
        ("queen's indian defense", "后翼印度防御"),
        ("queen's indian", "后翼印度防御"),
        ("bogo-indian", "博戈-印度防御"),
        ("grunfeld defense", "格林菲尔德防御"),
        ("grünfeld defense", "格林菲尔德防御"),
        ("grunfeld", "格林菲尔德防御"),
        ("caro-kann defense", "卡罗-卡恩防御"),
        ("caro-kann defence", "卡罗-卡恩防御"),
        ("caro-kann", "卡罗-卡恩防御"),
        ("sicilian defense", "西西里防御"),
        ("sicilian defence", "西西里防御"),
        ("najdorf variation", "纳道尔夫变例"),
        ("dragon variation", "龙式变例"),
        ("accelerated dragon", "加速龙式变例"),
        ("sveshnikov variation", "斯维什尼科夫变例"),
        ("alapin variation", "阿拉平变例"),
        ("french defense", "法兰西防御"),
        ("french defence", "法兰西防御"),
        ("winawer variation", "维纳维尔变例"),
        ("tarrasch variation", "塔拉什变例"),
        ("ruy lopez", "西班牙开局"),
        ("spanish game", "西班牙开局"),
        ("berlin defense", "柏林防御"),
        ("marshall attack", "马歇尔弃兵"),
        ("italian game", "意大利开局"),
        ("giuoco piano", "安静局面"),
        ("evans gambit", "伊文斯弃兵"),
        ("two knights defense", "双马防御"),
        ("two knights variation", "双马变例"),
        ("scotch game", "苏格兰开局"),
        ("petrov's defense", "俄罗斯防御"),
        ("petroff defense", "俄罗斯防御"),
        ("russian game", "俄罗斯防御"),
        ("philidor defense", "菲利道尔防御"),
        ("scandinavian defense", "斯堪的纳维亚防御"),
        ("alekhine's defense", "阿廖欣防御"),
        ("pirc defense", "皮尔茨防御"),
        ("modern defense", "现代防御"),
        ("slav defense", "斯拉夫防御"),
        ("semi-slav", "半斯拉夫防御"),
        ("benoni defense", "别诺尼防御"),
        ("benko gambit", "本科弃兵"),
        ("catalan opening", "卡塔兰开局"),
        ("london system", "伦敦体系"),
        ("dutch defense", "荷兰防御"),
        ("english opening", "英国式开局"),
        ("reti opening", "列蒂开局"),
        ("king's gambit", "王翼弃兵"),
        ("vienna game", "维也纳开局"),
        ("classical variation", "古典变例"),
        ("advance variation", "推进变例"),
        ("exchange variation", "兑换变例"),
        ("fantasy variation", "幻想变例"),
        ("panov-botvinnik attack", "帕诺夫-鲍特维尼克攻击"),
        ("panov attack", "帕诺夫攻击"),
        ("main line", "主线变例"),
        ("sidelines", "支线变例"),
        ("sideline", "支线变例"),

        // 2. Compound Piece & Color Phrases (Must precede standalone "white"/"black" and piece names)
        ("light-squared bishops", "白格象"),
        ("light-squared bishop", "白格象"),
        ("light squared bishop", "白格象"),
        ("light-square bishop", "白格象"),
        ("dark-squared bishops", "黑格象"),
        ("dark-squared bishop", "黑格象"),
        ("dark squared bishop", "黑格象"),
        ("dark-square bishop", "黑格象"),
        ("opposite-colored bishops", "异色格象"),
        ("opposite colored bishops", "异色格象"),
        ("same-colored bishops", "同色格象"),
        ("bishop pair", "双象"),
        ("two bishops", "双象"),
        ("bad bishop", "坏象"),
        ("good bishop", "好象"),
        ("fianchettoed bishop", "侧翼象"),
        ("knight pair", "双马"),
        ("two knights", "双马"),
        ("doubled rooks", "叠车"),
        ("rook pair", "双车"),
        ("rook lift", "提车"),
        ("white's king", "白王"),
        ("black's king", "黑王"),
        ("white king", "白王"),
        ("black king", "黑王"),
        ("white's queen", "白后"),
        ("black's queen", "黑后"),
        ("white queen", "白后"),
        ("black queen", "黑后"),
        ("white's rook", "白车"),
        ("black's rook", "黑车"),
        ("white rook", "白车"),
        ("black rook", "黑车"),
        ("white's bishop", "白象"),
        ("black's bishop", "黑象"),
        ("white bishop", "白象"),
        ("black bishop", "黑象"),
        ("white's knight", "白马"),
        ("black's knight", "黑马"),
        ("white knight", "白马"),
        ("black knight", "黑马"),
        ("white's pawns", "白兵"),
        ("black's pawns", "黑兵"),
        ("white's pawn", "白兵"),
        ("black's pawn", "黑兵"),
        ("white pawns", "白兵"),
        ("black pawns", "黑兵"),
        ("white pawn", "白兵"),
        ("black pawn", "黑兵"),
        ("white pieces", "白方棋子"),
        ("black pieces", "黑方棋子"),
        ("white piece", "白子"),
        ("black piece", "黑子"),
        ("white squares", "白格"),
        ("black squares", "黑格"),
        ("white square", "白格"),
        ("black square", "黑格"),
        ("light squares", "白格"),
        ("dark squares", "黑格"),
        ("light square", "白格"),
        ("dark square", "黑格"),
        ("minor pieces", "轻子"),
        ("minor piece", "轻子"),
        ("major pieces", "重子"),
        ("major piece", "重子"),
        ("heavy pieces", "重子"),
        ("heavy piece", "重子"),
        ("hanging pieces", "悬子"),
        ("hanging piece", "悬子"),
        ("trapped piece", "被困之子"),

        // 3. Compound Pawn Terms
        ("connected passed pawns", "联联通路兵"),
        ("outside passed pawn", "远端通路兵"),
        ("passed pawns", "通路兵"),
        ("passed pawn", "通路兵"),
        ("isolated queen's pawn", "后翼孤兵"),
        ("isolated pawns", "孤兵"),
        ("isolated pawn", "孤兵"),
        ("doubled pawns", "叠兵"),
        ("doubled pawn", "叠兵"),
        ("backward pawns", "落后兵"),
        ("backward pawn", "落后兵"),
        ("hanging pawns", "悬兵"),
        ("hanging pawn", "悬兵"),
        ("poisoned pawn", "毒兵"),
        ("free pawns", "白送的兵"),
        ("free pawn", "白送的兵"),
        ("extra pawn", "多兵"),
        ("pawn structure", "兵形结构"),
        ("pawn chains", "兵链"),
        ("pawn chain", "兵链"),
        ("pawn breaks", "冲兵突破"),
        ("pawn break", "冲兵突破"),
        ("pawn storm", "兵风暴"),
        ("pawn majority", "多兵翼"),
        ("pawn minority", "少兵翼"),
        ("pawn islands", "兵岛"),
        ("pawn island", "兵岛"),
        ("pawn endgame", "兵残局"),
        ("pawn ending", "兵残局"),

        // 4. Check, Checkmate & Game Outcomes (Prevents "检查/支票" & "交配/配偶")
        ("back-rank mate", "底线杀"),
        ("back rank mate", "底线杀"),
        ("smothered mate", "闷杀"),
        ("scholar's mate", "四步杀"),
        ("scholars mate", "四步杀"),
        ("fool's mate", "两步杀"),
        ("mate in 1", "一步杀"),
        ("mate in 2", "两步杀"),
        ("mate in 3", "三步杀"),
        ("mate in 4", "四步杀"),
        ("mate in one", "一步杀"),
        ("mate in two", "两步杀"),
        ("mate in three", "三步杀"),
        ("mating attack", "攻王杀势"),
        ("mating net", "杀网"),
        ("mating threats", "杀棋威胁"),
        ("mating threat", "杀棋威胁"),
        ("checkmated", "被将杀"),
        ("checkmates", "将杀"),
        ("checkmate", "将杀"),
        ("deliver mate", "实施将杀"),
        ("delivers mate", "实施将杀"),
        ("threaten mate", "威胁将杀"),
        ("threatens mate", "威胁将杀"),
        ("threatening mate", "威胁将杀"),
        ("forced mate", "强行杀棋"),
        ("unavoidable mate", "不可避免的杀棋"),
        ("mated", "被将杀"),
        ("mating", "将杀"),
        ("mates", "将杀"),
        ("mate", "将杀"),
        ("discovered checks", "闪将"),
        ("discovered check", "闪将"),
        ("double check", "双将"),
        ("perpetual check", "长将和棋"),
        ("cross-check", "反将"),
        ("gives check", "将军"),
        ("give check", "将军"),
        ("giving check", "将军"),
        ("gave check", "将军"),
        ("with check", "带将"),
        ("in check", "被将军"),
        ("into check", "送将"),
        ("out of check", "解将"),
        ("block the check", "垫将"),
        ("blocks the check", "垫将"),
        ("checks the king", "将军"),
        ("check the king", "将军"),
        ("checks", "将军"),
        ("check", "将军"),
        ("stalemate", "逼和"),
        ("threefold repetition", "三次重复局面"),
        ("draw by repetition", "重复局面和棋"),
        ("dead draw", "铁和"),
        ("drawn endgame", "和棋残局"),

        // 5. Castling, Exchange & Tactical Motifs
        ("castles kingside", "进行王翼易位"),
        ("castle kingside", "进行王翼易位"),
        ("castling kingside", "王翼易位"),
        ("kingside castling", "王翼易位"),
        ("short castling", "短易位"),
        ("castles queenside", "进行后翼易位"),
        ("castle queenside", "进行后翼易位"),
        ("castling queenside", "后翼易位"),
        ("queenside castling", "后翼易位"),
        ("long castling", "长易位"),
        ("artificial castling", "人工易位"),
        ("castling rights", "易位权"),
        ("castling", "王车易位"),
        ("castles", "王车易位"),
        ("castled", "完成王车易位"),
        ("win the exchange", "得半子"),
        ("wins the exchange", "得半子"),
        ("winning the exchange", "得半子"),
        ("won the exchange", "得半子"),
        ("up the exchange", "多半子"),
        ("down the exchange", "少半子"),
        ("sacrifice the exchange", "弃半子"),
        ("sacrifices the exchange", "弃半子"),
        ("exchange sacrifice", "弃半子"),
        ("the exchange", "半子"),
        ("queen trade", "兑后"),
        ("trade queens", "兑后"),
        ("exchange queens", "兑后"),
        ("discovered attack", "闪击"),
        ("absolute pin", "绝对牵制"),
        ("relative pin", "相对牵制"),
        ("unpin", "解脱牵制"),
        ("unpins", "解脱牵制"),
        ("pinned", "被牵制"),
        ("pinning", "牵制"),
        ("pins", "牵制"),
        ("pin", "牵制"),
        ("royal fork", "王后捉双"),
        ("forking", "捉双"),
        ("forks", "捉双"),
        ("fork", "捉双"),
        ("skewers", "串击"),
        ("skewer", "串击"),
        ("deflection", "引离"),
        ("decoy", "引入"),
        ("overloaded", "过载"),
        ("interference", "堵塞"),
        ("clearance", "腾挪"),
        ("zwischenzug", "过渡着"),
        ("intermezzo", "过渡着"),
        ("in-between move", "过渡着"),
        ("desperado", "亡命子"),
        ("zugzwang", "楚茨文克(迫移)"),
        ("prophylaxis", "预防性着法"),
        ("prophylactic move", "预防性着法"),
        ("prophylactic", "预防性的"),
        ("fianchetto", "侧翼出象"),
        ("en passant", "吃过路兵"),
        ("underpromotion", "低升变"),
        ("promotion square", "升变格"),
        ("promotion", "升变"),
        ("promotes", "升变"),
        ("promote", "升变"),
        ("gain a tempo", "抢先"),
        ("gains a tempo", "抢先"),
        ("lose a tempo", "失先"),
        ("loses a tempo", "失先"),
        ("with tempo", "带先手"),
        ("tempi", "先手步数"),
        ("tempo", "先手"),
        ("initiative", "主动权"),
        ("counterplay", "反击机会"),
        ("compensation", "补偿"),
        ("minority attack", "少子冲击"),
        ("opposition", "对王"),
        ("triangulation", "三角机动"),
        ("fortress", "堡垒和棋"),
        ("lucena position", "卢塞纳局面"),
        ("philidor position", "菲利道尔局面"),

        // 6. Board Geometry: Files, Ranks, Diagonals, Squares (Prevents "文件/排名/广场")
        ("half-open file", "半开放线"),
        ("semi-open file", "半开放线"),
        ("open files", "开放线"),
        ("open file", "开放线"),
        ("a-file", "a线"),
        ("b-file", "b线"),
        ("c-file", "c线"),
        ("d-file", "d线"),
        ("e-file", "e线"),
        ("f-file", "f线"),
        ("g-file", "g线"),
        ("h-file", "h线"),
        ("back rank", "底线"),
        ("first rank", "底线"),
        ("second rank", "第二横线"),
        ("2nd rank", "第二横线"),
        ("seventh rank", "第七横线"),
        ("7th rank", "第七横线"),
        ("eighth rank", "第八横线"),
        ("8th rank", "第八横线"),
        ("long diagonal", "长斜线"),
        ("diagonals", "斜线"),
        ("diagonal", "斜线"),
        ("outposts", "前哨格"),
        ("outpost", "前哨格"),
        ("weak squares", "弱格"),
        ("weak square", "弱格"),
        ("key squares", "关键格"),
        ("key square", "关键格"),
        ("critical square", "关键格"),
        ("central squares", "中心格"),
        ("central square", "中心格"),
        ("squares", "棋格"),
        ("square", "格"),
        ("kingside", "王翼"),
        ("queenside", "后翼"),
        ("in the center", "在中心"),
        ("the center", "中心"),

        // 7. Study, Move Quality & Phases
        ("in this study", "在本研习中"),
        ("this study", "本研习"),
        ("newest study", "最新研习"),
        ("new study", "新研习"),
        ("lichess study", "Lichess研习"),
        ("studies", "研习"),
        ("study", "研习"),
        ("variations", "变例"),
        ("variation", "变例"),
        ("blunders", "败着"),
        ("blunder", "败着"),
        ("inaccuracies", "缓着"),
        ("inaccuracy", "缓着"),
        ("brilliant move", "妙着"),
        ("only move", "唯一着法"),
        ("quiet move", "冷着"),
        ("waiting move", "等着"),
        ("candidate move", "候选着法"),
        ("developing move", "出子着法"),
        ("development", "出子"),
        ("develops", "出子"),
        ("develop", "出子"),
        ("sacrifices", "弃掉"),
        ("sacrifice", "弃子"),
        ("gambit", "弃兵"),
        ("recaptures", "回吃"),
        ("recapture", "回吃"),
        ("captures", "吃掉"),
        ("capture", "吃子"),
        ("endgames", "残局"),
        ("endgame", "残局"),
        ("middlegame", "中局"),
        ("openings", "开局"),
        ("opening", "开局"),

        // 8. Standalone Pieces (100% Unified: 象 / 马 / 车 / 后 / 王 / 兵)
        ("bishops", "双象"),
        ("bishop", "象"),
        ("knights", "马"),
        ("knight", "马"),
        ("rooks", "车"),
        ("rook", "车"),
        ("queens", "后"),
        ("queen", "后"),
        ("kings", "王"),
        ("king", "王"),
        ("pawns", "兵"),
        ("pawn", "兵"),

        // 9. Standalone Sides (White -> 白方, Black -> 黑方)
        ("white's", "白方的"),
        ("black's", "黑方的"),
        ("white", "白方"),
        ("black", "黑方")
    ]

    /// Pre-injects standardized Chinese chess terminology into English text before neural MT
    static func preAnnotateTermsForMT(_ input: String) -> String {
        var output = input

        // Protect algebraic move tokens like `1.e4`, `Nf3`, `Bxf7+`, `O-O`, `O-O-O` from being altered by case-insensitive word regexes
        var movePlaceholders: [String: String] = [:]
        if let moveRegex = try? NSRegularExpression(pattern: #"\b(?:O-O-O|O-O|0-0-0|0-0|[KQRBN][a-h1-8]?x?[a-h][1-8][+#!?]*|[a-h]x[a-h][1-8](?:=[QRBN])?[+#!?]*|[a-h][1-8](?:=[QRBN])?[+#!?]*)\b"#) {
            let matches = moveRegex.matches(in: output, range: NSRange(output.startIndex..<output.endIndex, in: output)).reversed()
            for (idx, match) in matches.enumerated() {
                if let r = Range(match.range, in: output) {
                    let token = String(output[r])
                    let placeholder = "ZXM\(idx)M"
                    movePlaceholders[placeholder] = token
                    output.replaceSubrange(r, with: placeholder)
                }
            }
        }

        // Convert `[a-h] square` (e.g. "f7 square", "d4 square") -> "f7格"
        if let sqRegex = try? NSRegularExpression(pattern: #"\b(ZXM\d+M|[a-h][1-8])\s+squares?\b"#, options: [.caseInsensitive]) {
            let range = NSRange(output.startIndex..<output.endIndex, in: output)
            output = sqRegex.stringByReplacingMatches(in: output, range: range, withTemplate: "$1格")
        }

        // Apply all ordered domain glossary replacements
        for item in orderedPreMTGlossary {
            if let regex = try? NSRegularExpression(pattern: "\\b\(item.pattern)\\b", options: [.caseInsensitive]) {
                let range = NSRange(output.startIndex..<output.endIndex, in: output)
                output = regex.stringByReplacingMatches(in: output, range: range, withTemplate: item.replacement)
            }
        }

        // Restore algebraic move tokens
        for (placeholder, origMove) in movePlaceholders {
            output = output.replacingOccurrences(of: placeholder, with: origMove)
        }

        return output
    }

    /// Post-processes machine/LLM translation output to scrub any residual mistranslations and unify piece names
    static func postProcessChineseChessTerms(_ translated: String) -> String {
        var result = translated
        let fixes: [(String, String)] = [
            // 1. Fix White / Black mistranslations ("白人/黑人/白色/黑色/怀特/布莱克")
            ("白人占优", "白方占优"),
            ("黑人占优", "黑方占优"),
            ("白人获胜", "白方获胜"),
            ("黑人获胜", "黑方获胜"),
            ("白人有", "白方有"),
            ("黑人有", "黑方有"),
            ("白人的", "白方的"),
            ("黑人的", "黑方的"),
            ("白人", "白方"),
            ("黑人", "黑方"),
            ("白色占优", "白方占优"),
            ("黑色占优", "黑方占优"),
            ("白色可以", "白方可以"),
            ("黑色可以", "黑方可以"),
            ("白色更好", "白方占优"),
            ("黑色更好", "黑方占优"),
            ("白色有", "白方有"),
            ("黑色有", "黑方有"),
            ("白色走", "白方走"),
            ("黑色走", "黑方走"),
            ("白色的王", "白王"),
            ("黑色的王", "黑王"),
            ("白色的后", "白后"),
            ("黑色的后", "黑后"),
            ("黑色开局", "黑方开局"),
            ("白色开局", "白方开局"),

            // 2. Fix Mate / Check mistranslations ("交配/配偶/检查/支票")
            ("交配网", "杀网"),
            ("交配攻击", "攻王杀势"),
            ("交配威胁", "杀棋威胁"),
            ("强制交配", "强行将杀"),
            ("交配", "将杀"),
            ("配偶", "将杀"),
            ("将死", "将杀"),
            ("支票", "将军"),
            ("双重检查", "双将"),
            ("发现检查", "闪将"),
            ("永恒的检查", "长将"),
            ("永久检查", "长将"),
            ("用检查", "带将"),
            ("带检查", "带将"),
            ("给检查", "将军"),

            // 3. Unify Piece Names ("象 / 马 / 车 / 后 / 王 / 兵")
            ("浅色格主教", "白格象"),
            ("深色格主教", "黑格象"),
            ("白格主教", "白格象"),
            ("黑格主教", "黑格象"),
            ("一对主教", "双象"),
            ("两个主教", "双象"),
            ("坏主教", "坏象"),
            ("好主教", "好象"),
            ("主教对", "双象"),
            ("大主教", "象"),
            ("主教", "象"),
            ("两个骑士", "双马"),
            ("一对骑士", "双马"),
            ("保护骑士", "保护这个马"),
            ("骑士", "马"),
            ("爵士", "马"),
            ("两个城堡", "双车"),
            ("城堡残局", "车残局"),
            ("城堡", "车"),
            ("菜鸟", "车"),
            ("王后", "后"),
            ("女王", "后"),
            ("皇后", "后"),
            ("国王", "王"),
            ("免费典当", "白送的兵"),
            ("免费的兵", "白送的兵"),
            ("通过典当", "通路兵"),
            ("孤立的典当", "孤兵"),
            ("落后的典当", "落后兵"),
            ("双典当", "叠兵"),
            ("典当链", "兵链"),
            ("典当结构", "兵形结构"),
            ("典当风暴", "兵风暴"),
            ("典当", "兵"),
            ("当铺", "兵"),
            ("小兵", "兵"),

            // 4. Fix Geometry, Tactics & Study Terms ("变奏/辩护/广场/文件/研究")
            ("变奏曲", "变例"),
            ("变奏", "变例"),
            ("这项研究", "本研习"),
            ("最新研究", "最新研习"),
            ("这种辩护", "这种防御"),
            ("辩护", "防御"),
            ("Caro-Kann", "卡罗-卡恩"),
            ("开放文件", "开放线"),
            ("半开放文件", "半开放线"),
            ("电子文件", "e线"),
            ("后排交配", "底线杀"),
            ("后排", "底线"),
            ("弱广场", "弱格"),
            ("关键广场", "关键格"),
            ("中心广场", "中心格"),
            ("叉子", "捉双"),
            ("餐叉", "捉双"),
            ("大头针", "牵制"),
            ("别针", "牵制"),
            ("烤肉串", "串击"),
            ("牺牲另一个兵", "再弃一兵"),
            ("牺牲", "弃"),
            ("如何玩", "如何下好")
        ]
        for (wrong, right) in fixes {
            result = result.replacingOccurrences(of: wrong, with: right)
        }
        return result
    }
}
