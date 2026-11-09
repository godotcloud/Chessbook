import Foundation
import AVFoundation
import Combine

enum SpeechSpeedPreset: String, CaseIterable, Identifiable {
    case slow = "slow"
    case normal = "normal"
    case fast = "fast"
    case veryFast = "very_fast"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .slow: return "慢速 (0.85x)"
        case .normal: return "标准 (1.0x)"
        case .fast: return "稍快 (1.15x)"
        case .veryFast: return "快速 (1.3x)"
        }
    }

    var avRate: Float {
        switch self {
        case .slow: return 0.44
        case .normal: return 0.50
        case .fast: return 0.55
        case .veryFast: return 0.60
        }
    }
}

@MainActor
final class ChessSpeechService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = ChessSpeechService()

    private let synthesizer = AVSpeechSynthesizer()

    @Published var isSpeaking: Bool = false
    @Published var currentSpokenText: String = ""

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speakOrToggle(
        text: String,
        speed: SpeechSpeedPreset = .normal,
        verbalizeChessMoves: Bool = true
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if synthesizer.isSpeaking && currentSpokenText == trimmed {
            stopSpeaking()
            return
        }

        speakImmediately(text: trimmed, speed: speed, verbalizeChessMoves: verbalizeChessMoves)
    }

    func speakImmediately(
        text: String,
        speed: SpeechSpeedPreset = .normal,
        verbalizeChessMoves: Bool = true
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        configureAudioSessionForSilentSwitchOverride()

        let spokenString = verbalizeChessMoves ? Self.verbalizeChessNotation(trimmed) : trimmed
        let utterance = AVSpeechUtterance(string: spokenString)
        utterance.voice = preferredMandarinVoice()
        utterance.rate = speed.avRate
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0

        currentSpokenText = trimmed
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func stopSpeaking() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
        currentSpokenText = ""
    }

    private func configureAudioSessionForSilentSwitchOverride() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playback,
                mode: .spokenAudio,
                options: [.duckOthers, .mixWithOthers]
            )
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {}
    }

    private func preferredMandarinVoice() -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language.lowercased().hasPrefix("zh-cn") || $0.language.lowercased().hasPrefix("zh_cn")
        }
        if let premium = voices.first(where: { $0.quality == .premium }) {
            return premium
        }
        if let enhanced = voices.first(where: { $0.quality == .enhanced }) {
            return enhanced
        }
        return AVSpeechSynthesisVoice(language: "zh-CN")
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            self.currentSpokenText = ""
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            self.currentSpokenText = ""
        }
    }

    static func verbalizeChessNotation(_ input: String) -> String {
        var s = input

        s = s.replacingOccurrences(of: "O-O-O", with: "长易位")
        s = s.replacingOccurrences(of: "0-0-0", with: "长易位")
        s = s.replacingOccurrences(of: "O-O", with: "短易位")
        s = s.replacingOccurrences(of: "0-0", with: "短易位")

        let pieceMap: [Character: String] = [
            "K": "王",
            "Q": "后",
            "R": "车",
            "B": "象",
            "N": "马"
        ]

        if let sanRegex = try? NSRegularExpression(pattern: #"\b([KQRBN])([a-h1-8]?)(x?)([a-h][1-8])([+#]?)\b"#) {
            let matches = sanRegex.matches(in: s, range: NSRange(s.startIndex..<s.endIndex, in: s)).reversed()
            for match in matches {
                guard let fullRange = Range(match.range, in: s),
                      let pRange = Range(match.range(at: 1), in: s),
                      let sqRange = Range(match.range(at: 4), in: s) else { continue }
                let pieceChar = s[pRange].first ?? " "
                let pieceName = pieceMap[pieceChar] ?? ""
                let disambig = Range(match.range(at: 2), in: s).map { String(s[$0]) } ?? ""
                let isCapture = Range(match.range(at: 3), in: s).map { !s[$0].isEmpty } ?? false
                let targetSq = String(s[sqRange])
                let checkMod = Range(match.range(at: 5), in: s).map { String(s[$0]) } ?? ""

                var spoken = pieceName
                if !disambig.isEmpty {
                    spoken += " \(disambig) "
                }
                spoken += isCapture ? "吃 \(targetSq)" : " \(targetSq)"
                if checkMod == "+" {
                    spoken += " 将军"
                } else if checkMod == "#" {
                    spoken += " 将杀"
                }
                s.replaceSubrange(fullRange, with: spoken)
            }
        }

        if let pawnCapRegex = try? NSRegularExpression(pattern: #"\b([a-h])x([a-h][1-8])([+#]?)\b"#) {
            let matches = pawnCapRegex.matches(in: s, range: NSRange(s.startIndex..<s.endIndex, in: s)).reversed()
            for match in matches {
                guard let fullRange = Range(match.range, in: s),
                      let fileRange = Range(match.range(at: 1), in: s),
                      let sqRange = Range(match.range(at: 2), in: s) else { continue }
                let fromFile = String(s[fileRange])
                let targetSq = String(s[sqRange])
                let checkMod = Range(match.range(at: 3), in: s).map { String(s[$0]) } ?? ""
                var spoken = "\(fromFile) 兵吃 \(targetSq)"
                if checkMod == "+" { spoken += " 将军" }
                else if checkMod == "#" { spoken += " 将杀" }
                s.replaceSubrange(fullRange, with: spoken)
            }
        }

        return s
    }
}
