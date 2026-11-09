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
            return "GTX 极速神经翻译 + 国际象棋术语库 (免Key·毫秒级)"
        case .pollinationsLLM:
            return "Pollinations AI 大模型 (免Key·大师语境精译)"
        case .lingvaGoogle:
            return "Lingva 开源神经代理 (免Key·多节点)"
        case .myMemory:
            return "MyMemory 协作翻译 API (免Key·备用)"
        case .localGlossaryOnly:
            return "离线国际象棋专业术语直译 (零网络延迟)"
        }
    }

    var shortBadge: String {
        switch self {
        case .gtxHybrid: return "GTX极速"
        case .pollinationsLLM: return "AI大模型"
        case .lingvaGoogle: return "Lingva"
        case .myMemory: return "MyMemory"
        case .localGlossaryOnly: return "离线词库"
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
            return (trimmed, preferredProvider)
        }

        let cacheKey = "\(preferredProvider.rawValue)|\(trimmed)"
        if let cached = cache[cacheKey] {
            return (cached, preferredProvider)
        }

        var chain: [TranslationProviderType] = [preferredProvider]
        for fallback in [TranslationProviderType.gtxHybrid, .pollinationsLLM, .lingvaGoogle, .myMemory, .localGlossaryOnly] {
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

        let offlineFallback = ChessGlossaryProcessor.applyGlossaryReplacement(trimmed)
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
            return ChessGlossaryProcessor.applyGlossaryReplacement(text)
        }
    }

    private func translateViaGTX(text: String) async throws -> String {
        let prepped = ChessGlossaryProcessor.preAnnotateTermsForMT(text)
        var comps = URLComponents(string: "https://translate.googleapis.com/translate_a/single")
        comps?.queryItems = [
            URLQueryItem(name: "client", value: "gtx"),
            URLQueryItem(name: "sl", value: "auto"),
            URLQueryItem(name: "tl", value: "zh-CN"),
            URLQueryItem(name: "dt", value: "t"),
            URLQueryItem(name: "q", value: prepped)
        ]
        guard let url = comps?.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8

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
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let systemPrompt = """
        你是一位精通国际象棋的特级大师兼中文棋评翻译专家。请将以下 Lichess 研习(Study)的章节标题或着法注解准确、简练地翻译为简体中文。
        严格要求：
        1. 保留所有代数记谱法着法（如 1.e4, Nf3, Qxf7#, O-O）原样不变。
        2. 使用地道的中国国际象棋专业术语（Variation=变例, Study=研习, Defense=防御, Caro-Kann=卡罗-卡恩防御, Pin=牵制, Fork=捉双, Skewer=串击, Discovered attack=闪击, Zugzwang=楚茨文克/迫移, Fianchetto=侧翼象, Passed pawn=通路兵, Outpost=前哨格, Blunder=败着, Prophylaxis=预防性着法, Tempo=先手）。
        3. 只输出翻译后的中文内容，不要添加任何解释或前缀。
        """

        let payload: [String: Any] = [
            "model": "openai",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text]
            ],
            "temperature": 0.2
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
            guard let url = URL(string: "\(base)/api/v1/auto/zh/\(encoded)") else { continue }
            var request = URLRequest(url: url)
            request.timeoutInterval = 8
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
        request.timeoutInterval = 8

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
        return cjkCount > max(2, s.count / 3)
    }
}

enum ChessGlossaryProcessor {
    static let termDictionary: [(pattern: String, chinese: String)] = [
        ("classical variation", "古典变例"),
        ("advance variation", "推进变例"),
        ("exchange variation", "兑换变例"),
        ("fantasy variation", "幻想变例"),
        ("panov attack", "帕诺夫攻击"),
        ("two knights", "双马变例"),
        ("main line", "主线变例"),
        ("sideline", "支线变例"),
        ("variation", "变例"),
        ("variations", "变例"),
        ("caro-kann defense", "卡罗-卡恩防御"),
        ("caro-kann defence", "卡罗-卡恩防御"),
        ("caro-kann", "卡罗-卡恩防御"),
        ("sicilian defense", "西西里防御"),
        ("sicilian defence", "西西里防御"),
        ("french defense", "法兰西防御"),
        ("ruy lopez", "西班牙开局"),
        ("italian game", "意大利开局"),
        ("queen's gambit", "后翼弃兵"),
        ("king's indian", "古印度防御"),
        ("nimzo-indian", "尼姆佐-印度防御"),
        ("grunfeld", "格林菲尔德防御"),
        ("english opening", "英国式开局"),
        ("zugzwang", "楚茨文克(迫移)"),
        ("fianchetto", "侧翼象"),
        ("en passant", "吃过路兵"),
        ("discovered check", "闪将"),
        ("discovered attack", "闪击"),
        ("double check", "双将"),
        ("back rank mate", "底线杀"),
        ("smothered mate", "闷杀"),
        ("skewer", "串击"),
        ("fork", "捉双"),
        ("pin", "牵制"),
        ("pinned", "被牵制"),
        ("outpost", "前哨格"),
        ("passed pawn", "通路兵"),
        ("isolated pawn", "孤兵"),
        ("doubled pawns", "叠兵"),
        ("backward pawn", "落后兵"),
        ("hanging piece", "悬子"),
        ("minority attack", "少子冲击"),
        ("prophylaxis", "预防性着法"),
        ("zwischenzug", "过渡着"),
        ("intermezzo", "过渡着"),
        ("desperado", "亡命子"),
        ("opposition", "对王"),
        ("triangulation", "三角机动"),
        ("fortress", "堡垒和棋"),
        ("perpetual check", "长将和棋"),
        ("stalemate", "逼和"),
        ("castling", "王车易位"),
        ("kingside", "王翼"),
        ("queenside", "后翼"),
        ("blunder", "败着"),
        ("inaccuracy", "缓着"),
        ("brilliant", "妙着"),
        ("novelty", "理论新着"),
        ("initiative", "主动权"),
        ("development", "出子"),
        ("center control", "中心控制"),
        ("open file", "开放线"),
        ("half-open file", "半开放线"),
        ("seventh rank", "第七横线"),
        ("endgame", "残局"),
        ("middlegame", "中局"),
        ("opening", "开局")
    ]

    static func preAnnotateTermsForMT(_ input: String) -> String {
        var output = input
        let contextualReplacements: [(String, String)] = [
            ("Classical Variation", "古典变例"),
            ("Advance Variation", "推进变例"),
            ("Exchange Variation", "兑换变例"),
            ("Fantasy Variation", "幻想变例"),
            ("Two Knights Variation", "双马变例"),
            ("variation", "变例"),
            ("variations", "变例"),
            ("Caro-Kann", "卡罗-卡恩"),
            ("in this study", "在本研习中"),
            ("this study", "本研习"),
            ("black opening", "黑方开局"),
            ("white opening", "白方开局"),
            ("this defense", "这种防御"),
            ("this defence", "这种防御"),
            ("fork", "捉双"),
            ("pin", "牵制"),
            ("skewer", "串击"),
            ("zugzwang", "楚茨文克(迫移)"),
            ("fianchetto", "侧翼象"),
            ("en passant", "吃过路兵"),
            ("passed pawn", "通路兵"),
            ("isolated pawn", "孤兵"),
            ("backward pawn", "落后兵"),
            ("outpost", "前哨格"),
            ("zwischenzug", "过渡着"),
            ("prophylaxis", "预防性着法"),
            ("kingside", "王翼"),
            ("queenside", "后翼")
        ]
        for (en, zh) in contextualReplacements {
            if let regex = try? NSRegularExpression(pattern: "\\b\(en)\\b", options: [.caseInsensitive]) {
                let range = NSRange(output.startIndex..<output.endIndex, in: output)
                output = regex.stringByReplacingMatches(in: output, range: range, withTemplate: zh)
            }
        }
        return output
    }

    static func postProcessChineseChessTerms(_ translated: String) -> String {
        var result = translated
        let fixes: [(String, String)] = [
            ("变奏曲", "变例"),
            ("变奏", "变例"),
            ("这项研究", "本研习"),
            ("最新研究", "最新研习"),
            ("这种辩护", "这种防御"),
            ("辩护", "防御"),
            ("Caro-Kann", "卡罗-卡恩"),
            ("黑色开局", "黑方开局"),
            ("白色开局", "白方开局"),
            ("如何玩", "如何下好"),
            ("叉子", "捉双"),
            ("餐叉", "捉双"),
            ("大头针", "牵制"),
            ("别针", "牵制"),
            ("烤肉串", "串击"),
            ("白色可以", "白方可以"),
            ("黑色可以", "黑方可以"),
            ("白色更好", "白方占优"),
            ("黑色更好", "黑方占优"),
            ("白色的王", "白王"),
            ("黑色的王", "黑王"),
            ("主教", "象"),
            ("骑士", "马"),
            ("城堡", "车")
        ]
        for (wrong, right) in fixes {
            result = result.replacingOccurrences(of: wrong, with: right)
        }
        return result
    }

    static func applyGlossaryReplacement(_ text: String) -> String {
        var output = text
        for item in termDictionary {
            if let regex = try? NSRegularExpression(pattern: "\\b\(item.pattern)\\b", options: [.caseInsensitive]) {
                let range = NSRange(output.startIndex..<output.endIndex, in: output)
                output = regex.stringByReplacingMatches(in: output, range: range, withTemplate: item.chinese)
            }
        }
        return output
    }
}
