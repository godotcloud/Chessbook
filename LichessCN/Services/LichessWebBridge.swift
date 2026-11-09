import Foundation
import WebKit
import Combine
import SwiftUI

@MainActor
final class HybridTranslationBridgeManager: NSObject, ObservableObject {
    @Published var currentURLString: String = "https://lichess.org/study"
    @Published var pageTitle: String = "Lichess.org"
    @Published var isLoading: Bool = false
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false

    @Published var activeOriginalComment: String = ""
    @Published var activeTranslatedComment: String = ""
    @Published var activeChapterTitle: String = ""
    @Published var isTranslatingNow: Bool = false
    @Published var translatedCount: Int = 0
    @Published var lastUsedProviderBadge: String = "GTX极速"

    // Translation settings
    @Published var autoTranslateEnabled: Bool = true {
        didSet { syncConfigToWebView() }
    }
    @Published var selectedProviderRaw: String = TranslationProviderType.gtxHybrid.rawValue {
        didSet {
            Task {
                await ChessTranslationService.shared.clearCache()
                triggerFullPageRescan()
            }
        }
    }
    @Published var injectionModeRaw: String = InlineInjectionMode.smartCompact.rawValue {
        didSet { syncConfigToWebView() }
    }
    @Published var showFloatingSubtitleCard: Bool = false
    @Published var isCompactFullscreen: Bool = false

    // Text-to-Speech (Auto & Manual Reading) settings
    @AppStorage("tts_auto_speak_enabled") var autoSpeakEnabled: Bool = true
    @AppStorage("tts_speed_preset") var speechSpeedRaw: String = SpeechSpeedPreset.normal.rawValue
    @AppStorage("tts_verbalize_chess_moves") var verbalizeChessMoves: Bool = true

    private var lastAutoSpokenText: String = ""
    weak var webView: WKWebView?

    var selectedProvider: TranslationProviderType {
        get { TranslationProviderType(rawValue: selectedProviderRaw) ?? .gtxHybrid }
        set { selectedProviderRaw = newValue.rawValue }
    }

    var injectionMode: InlineInjectionMode {
        get { InlineInjectionMode(rawValue: injectionModeRaw) ?? .smartCompact }
        set { injectionModeRaw = newValue.rawValue }
    }

    var speechSpeed: SpeechSpeedPreset {
        get { SpeechSpeedPreset(rawValue: speechSpeedRaw) ?? .normal }
        set { speechSpeedRaw = newValue.rawValue }
    }

    func navigateTo(_ urlString: String) {
        var target = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !target.hasPrefix("http://") && !target.hasPrefix("https://") {
            if target.count == 8 && !target.contains("/") && !target.contains(".") {
                target = "https://lichess.org/study/\(target)"
            } else {
                target = "https://\(target)"
            }
        }
        guard let url = URL(string: target) else { return }
        ChessSpeechService.shared.stopSpeaking()
        webView?.load(URLRequest(url: url))
    }

    func goBack() {
        ChessSpeechService.shared.stopSpeaking()
        webView?.goBack()
    }

    func goForward() {
        ChessSpeechService.shared.stopSpeaking()
        webView?.goForward()
    }

    func reload() {
        ChessSpeechService.shared.stopSpeaking()
        webView?.reload()
    }

    /// Manual 1-tap speak or stop for the current active commentary
    func toggleSpeakActiveComment() {
        if ChessSpeechService.shared.isSpeaking {
            ChessSpeechService.shared.stopSpeaking()
            return
        }
        let targetText = activeTranslatedComment.isEmpty ? activeOriginalComment : activeTranslatedComment
        guard !targetText.isEmpty else { return }
        ChessSpeechService.shared.speakImmediately(
            text: targetText,
            speed: speechSpeed,
            verbalizeChessMoves: verbalizeChessMoves
        )
    }

    func syncConfigToWebView() {
        let enabledStr = autoTranslateEnabled ? "true" : "false"
        let modeStr = injectionMode.rawValue
        let js = "if (window.__LichessCN_updateConfig) { window.__LichessCN_updateConfig(\(enabledStr), '\(modeStr)'); }"
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }

    func triggerFullPageRescan() {
        lastAutoSpokenText = ""
        let js = "if (window.__LichessCN_forceRescan) { window.__LichessCN_forceRescan(); }"
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }

    func handleScriptMessage(_ body: [String: Any]) {
        guard let action = body["action"] as? String else { return }

        switch action {
        case "speakText":
            // Triggered when user taps the inline [🔊 朗读] button inside any webpage comment box!
            let textToSpeak = (body["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !textToSpeak.isEmpty else { return }
            ChessSpeechService.shared.speakOrToggle(
                text: textToSpeak,
                speed: speechSpeed,
                verbalizeChessMoves: verbalizeChessMoves
            )

        case "stopSpeaking":
            ChessSpeechService.shared.stopSpeaking()

        case "translatePriorityItem":
            guard autoTranslateEnabled,
                  let domId = body["id"] as? String,
                  let rawText = body["text"] as? String,
                  !rawText.isEmpty else { return }
            let kind = body["kind"] as? String ?? "active_comment"
            activeOriginalComment = rawText

            Task {
                isTranslatingNow = true
                let (zh, used) = await ChessTranslationService.shared.translateToChinese(
                    text: rawText,
                    preferredProvider: selectedProvider
                )
                activeTranslatedComment = zh
                lastUsedProviderBadge = used.shortBadge
                translatedCount += 1
                isTranslatingNow = false
                sendTranslationToWebView(domId: domId, zh: zh, orig: rawText, badge: used.shortBadge, kind: kind)

                // Automatic TTS Reading when advancing to a new move commentary!
                if autoSpeakEnabled && kind == "active_comment" && zh != lastAutoSpokenText {
                    lastAutoSpokenText = zh
                    ChessSpeechService.shared.speakImmediately(
                        text: zh,
                        speed: speechSpeed,
                        verbalizeChessMoves: verbalizeChessMoves
                    )
                }
            }

        case "translateBatch":
            guard autoTranslateEnabled,
                  let items = body["items"] as? [[String: String]] else { return }
            Task {
                await processTranslationBatch(items)
            }

        default:
            break
        }
    }

    private func processTranslationBatch(_ items: [[String: String]]) async {
        guard !items.isEmpty else { return }
        isTranslatingNow = true
        defer { isTranslatingNow = false }

        await withTaskGroup(of: (String, String, String, String, String)?.self) { group in
            for item in items {
                guard let domId = item["id"],
                      let rawText = item["text"],
                      !rawText.isEmpty else { continue }
                let kind = item["kind"] ?? "comment"
                let pref = selectedProvider

                group.addTask {
                    let (zh, used) = await ChessTranslationService.shared.translateToChinese(
                        text: rawText,
                        preferredProvider: pref
                    )
                    return (domId, zh, rawText, used.shortBadge, kind)
                }
            }

            for await result in group {
                guard let (domId, zh, orig, badge, kind) = result else { continue }
                lastUsedProviderBadge = badge
                translatedCount += 1
                if kind == "active_comment" {
                    activeOriginalComment = orig
                    activeTranslatedComment = zh
                }
                sendTranslationToWebView(domId: domId, zh: zh, orig: orig, badge: badge, kind: kind)
            }
        }
    }

    private func sendTranslationToWebView(domId: String, zh: String, orig: String, badge: String, kind: String) {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: [
            "id": domId,
            "zh": zh,
            "orig": orig,
            "badge": badge,
            "kind": kind,
            "mode": injectionMode.rawValue
        ]),
        let jsonStr = String(data: jsonData, encoding: .utf8) else { return }

        let js = "if (window.__LichessCN_applyTranslation) { window.__LichessCN_applyTranslation(\(jsonStr)); }"
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }

    // MARK: - Snabbdom-Safe Injected JS with Inline [🔊 朗读] & [原文] Buttons
    static let injectedStudyInterceptorJS = #"""
    (function() {
      if (window.__LichessCN_Initialized) return;
      window.__LichessCN_Initialized = true;

      let config = {
        enabled: true,
        mode: 'smart_compact' // 'smart_compact' | 'bilingual' | 'subtitle_only'
      };

      let nodeCounter = 1;

      function ensureStyleInjected() {
        if (document.getElementById('lichesscn-inline-style')) return;
        const style = document.createElement('style');
        style.id = 'lichesscn-inline-style';
        style.textContent = `
          main.analyse {
            padding-top: 2px !important;
          }

          .gamebook {
            display: flex !important;
            flex-direction: column !important;
            justify-content: flex-start !important;
            height: auto !important;
            max-height: none !important;
            overflow: visible !important;
            position: relative !important;
            padding-bottom: 6px !important;
          }
          .gamebook .comment {
            position: relative !important;
            max-height: 165px !important;
            overflow-y: auto !important;
            -webkit-overflow-scrolling: touch !important;
            padding: 8px 12px !important;
            margin-bottom: 6px !important;
            font-size: 0.95rem !important;
            line-height: 1.48 !important;
            z-index: 2 !important;
          }
          .gamebook .floor {
            position: relative !important;
            top: auto !important;
            bottom: auto !important;
            left: auto !important;
            right: auto !important;
            width: 100% !important;
            margin-top: 4px !important;
            z-index: 3 !important;
          }
          .gamebook .floor .instruction,
          .gamebook .floor .instruction strong,
          .gamebook .floor .instruction em {
            white-space: normal !important;
            word-break: keep-all !important;
            overflow-wrap: break-word !important;
          }
          .gamebook .mascot {
            width: 32px !important;
            height: 32px !important;
            right: 6px !important;
            bottom: 6px !important;
            opacity: 0.2 !important;
            pointer-events: none !important;
            z-index: 1 !important;
          }

          .study__comments {
            max-height: 160px !important;
            overflow-y: auto !important;
            -webkit-overflow-scrolling: touch !important;
          }

          .study__chapters > div,
          .study__chapters .elem,
          .study__chapters button {
            height: auto !important;
            min-height: 2.35rem !important;
            padding-top: 4px !important;
            padding-bottom: 4px !important;
          }
          .study__chapters h3 {
            white-space: normal !important;
            line-height: 1.32 !important;
          }

          .lc-compact-hide-orig {
            font-size: 0 !important;
            line-height: 0 !important;
            color: transparent !important;
          }
          .lc-compact-hide-orig > *:not(.lc-injected-box) {
            display: none !important;
          }
          .lc-compact-hide-orig > .lc-injected-box {
            display: block !important;
            font-size: 0.95rem !important;
            line-height: 1.48 !important;
            color: #262421 !important;
          }
          html.dark .lc-compact-hide-orig > .lc-injected-box,
          body.dark .lc-compact-hide-orig > .lc-injected-box,
          html.transp .lc-compact-hide-orig > .lc-injected-box {
            color: #e3e3e3 !important;
          }

          .lc-injected-box {
            display: block;
            word-break: break-word;
          }
          .lc-injected-bilingual {
            margin-top: 6px;
            padding: 6px 9px;
            border-left: 3px solid #3893e8;
            background: rgba(56, 147, 232, 0.12);
            border-radius: 4px;
            font-size: 0.93rem;
            line-height: 1.45;
            font-weight: 500;
          }
          .lc-action-pill {
            display: inline-block;
            margin-left: 6px;
            padding: 1px 7px;
            font-size: 0.75rem;
            line-height: 1.35;
            border-radius: 5px;
            background: rgba(56, 147, 232, 0.18);
            color: #3893e8 !important;
            cursor: pointer;
            user-select: none;
            font-weight: 600;
            vertical-align: baseline;
          }
          .lc-action-pill:active {
            background: rgba(56, 147, 232, 0.35);
          }
          .lc-orig-collapsible {
            display: none;
            margin-top: 5px;
            padding-top: 5px;
            border-top: 1px dashed rgba(128, 128, 128, 0.35);
            font-size: 0.84rem;
            line-height: 1.38;
            opacity: 0.8;
          }
          .lc-orig-collapsible.lc-open {
            display: block;
          }
          .lc-injected-inline {
            display: inline;
            margin-left: 4px;
            color: #3893e8 !important;
            font-size: 0.92rem !important;
            font-weight: 500;
          }
          .lc-injected-chapter {
            display: block;
            margin-top: 1px;
            font-size: 0.86rem !important;
            line-height: 1.28 !important;
            color: #3893e8 !important;
            font-weight: 600;
          }
          .lc-zh-badge {
            display: inline-block;
            font-size: 0.72rem;
            padding: 0px 5px;
            margin-right: 5px;
            border-radius: 3px;
            background: rgba(56, 147, 232, 0.2);
            color: #3893e8 !important;
            font-weight: 600;
          }
        `;
        (document.head || document.documentElement).appendChild(style);
      }

      function hasMostlyChinese(str) {
        if (!str) return true;
        let cjk = 0;
        for (let i = 0; i < str.length; i++) {
          const code = str.charCodeAt(i);
          if (code >= 0x4E00 && code <= 0x9FFF) cjk++;
        }
        return cjk > Math.max(2, str.length * 0.3);
      }

      function extractLiveSourceText(el) {
        const clone = el.cloneNode(true);
        const injected = clone.querySelectorAll('.lc-injected-box, .lc-injected-inline, .lc-injected-chapter, .author, .by');
        injected.forEach(n => n.remove());
        return (clone.textContent || '').replace(/\s+/g, ' ').trim();
      }

      function scanStudyDOM(forceAll) {
        if (!config.enabled) return;
        ensureStyleInjected();

        const activeSelectors = [
          '.gamebook .comment .content',
          '.gamebook .comment',
          '.study__comments .content',
          '.study__comments',
          '.gamebook .hint'
        ];

        const visitedActive = new Set();
        for (const sel of activeSelectors) {
          const nodes = document.querySelectorAll(sel);
          nodes.forEach(el => {
            if (visitedActive.has(el) || (el.parentElement && visitedActive.has(el.parentElement))) return;
            if (el.querySelector('.content') && (sel === '.gamebook .comment' || sel === '.study__comments')) return;

            const liveText = extractLiveSourceText(el);
            if (!liveText || liveText.length < 2) {
              el.classList.remove('lc-compact-hide-orig');
              el.querySelectorAll('.lc-injected-box').forEach(n => n.remove());
              return;
            }
            visitedActive.add(el);

            const existingBox = el.querySelector('.lc-injected-box');
            const alreadyTranslatedFor = existingBox ? existingBox.getAttribute('data-lc-for') : null;

            if (alreadyTranslatedFor && alreadyTranslatedFor !== liveText) {
              el.classList.remove('lc-compact-hide-orig');
              existingBox.remove();
            }

            if (hasMostlyChinese(liveText)) return;

            const nowMs = Date.now();
            const pendingText = el.dataset.lcPendingText || '';
            const pendingTime = parseInt(el.dataset.lcPendingTime || '0', 10);

            if (forceAll || (alreadyTranslatedFor !== liveText && (pendingText !== liveText || (nowMs - pendingTime) > 2500))) {
              if (!el.dataset.lcId) {
                el.dataset.lcId = 'lc_node_' + (nodeCounter++);
              }
              el.dataset.lcPendingText = liveText;
              el.dataset.lcPendingTime = String(nowMs);
              el.dataset.lcKind = 'active_comment';

              try {
                window.webkit.messageHandlers.lichessTranslator.postMessage({
                  action: 'translatePriorityItem',
                  id: el.dataset.lcId,
                  text: liveText,
                  kind: 'active_comment'
                });
              } catch (e) {}
            }
          });
        }

        const batch = [];

        const inlineComments = document.querySelectorAll('.tview2 comment, .analyse__moves comment');
        inlineComments.forEach(el => {
          const liveText = extractLiveSourceText(el);
          if (!liveText || liveText.length < 2 || hasMostlyChinese(liveText)) return;
          const existing = el.querySelector('.lc-injected-inline, .lc-injected-box');
          const translatedFor = existing ? existing.getAttribute('data-lc-for') : null;
          if (translatedFor && translatedFor !== liveText) {
            el.classList.remove('lc-compact-hide-orig');
            existing.remove();
          }
          const nowMs = Date.now();
          const pendingText = el.dataset.lcPendingText || '';
          const pendingTime = parseInt(el.dataset.lcPendingTime || '0', 10);
          if (forceAll || (translatedFor !== liveText && (pendingText !== liveText || (nowMs - pendingTime) > 3500))) {
            if (!el.dataset.lcId) {
              el.dataset.lcId = 'lc_node_' + (nodeCounter++);
            }
            el.dataset.lcPendingText = liveText;
            el.dataset.lcPendingTime = String(nowMs);
            el.dataset.lcKind = 'inline_comment';
            batch.push({ id: el.dataset.lcId, text: liveText, kind: 'inline_comment' });
          }
        });

        const chapterNodes = document.querySelectorAll('.study__chapters h3, .study__chapters .chapter-name');
        chapterNodes.forEach(el => {
          const liveText = extractLiveSourceText(el);
          if (!liveText || liveText.length < 2 || hasMostlyChinese(liveText)) return;
          const existing = el.querySelector('.lc-injected-chapter');
          const translatedFor = existing ? existing.getAttribute('data-lc-for') : null;
          if (translatedFor && translatedFor !== liveText) {
            existing.remove();
          }
          const nowMs = Date.now();
          const pendingText = el.dataset.lcPendingText || '';
          const pendingTime = parseInt(el.dataset.lcPendingTime || '0', 10);
          if (forceAll || (translatedFor !== liveText && (pendingText !== liveText || (nowMs - pendingTime) > 4000))) {
            if (!el.dataset.lcId) {
              el.dataset.lcId = 'lc_node_' + (nodeCounter++);
            }
            el.dataset.lcPendingText = liveText;
            el.dataset.lcPendingTime = String(nowMs);
            el.dataset.lcKind = 'chapter_title';
            batch.push({ id: el.dataset.lcId, text: liveText, kind: 'chapter_title' });
          }
        });

        if (batch.length > 0) {
          try {
            window.webkit.messageHandlers.lichessTranslator.postMessage({
              action: 'translateBatch',
              items: batch.slice(0, 10)
            });
          } catch (e) {}
        }
      }

      function createSpeakPill(zhText) {
        const speakBtn = document.createElement('span');
        speakBtn.className = 'lc-action-pill';
        speakBtn.textContent = '🔊 朗读';
        speakBtn.onclick = function(ev) {
          ev.stopPropagation();
          try {
            window.webkit.messageHandlers.lichessTranslator.postMessage({
              action: 'speakText',
              text: zhText
            });
          } catch (e) {}
        };
        return speakBtn;
      }

      window.__LichessCN_applyTranslation = function(payload) {
        if (!payload || !payload.id || !payload.zh) return;
        const el = document.querySelector('[data-lc-id="' + payload.id + '"]');
        if (!el) return;

        const currentLiveText = extractLiveSourceText(el);
        el.querySelectorAll('.lc-injected-box, .lc-injected-inline, .lc-injected-chapter').forEach(n => n.remove());
        el.classList.remove('lc-compact-hide-orig');

        if (config.mode === 'subtitle_only') {
          return;
        }

        const kind = payload.kind || el.dataset.lcKind || 'active_comment';

        if (kind === 'chapter_title') {
          const chapSpan = document.createElement('span');
          chapSpan.className = 'lc-injected-chapter';
          chapSpan.setAttribute('data-lc-for', currentLiveText);
          chapSpan.textContent = payload.zh;
          el.appendChild(chapSpan);
          return;
        }

        if (kind === 'inline_comment') {
          if (config.mode === 'smart_compact') {
            el.classList.add('lc-compact-hide-orig');
            const box = document.createElement('span');
            box.className = 'lc-injected-box';
            box.setAttribute('data-lc-for', currentLiveText);
            box.textContent = payload.zh;
            box.appendChild(createSpeakPill(payload.zh));
            el.appendChild(box);
          } else {
            const span = document.createElement('span');
            span.className = 'lc-injected-inline';
            span.setAttribute('data-lc-for', currentLiveText);
            span.textContent = ' [' + payload.zh + ']';
            span.appendChild(createSpeakPill(payload.zh));
            el.appendChild(span);
          }
          return;
        }

        // Active comment (.gamebook .comment or .study__comments)
        if (config.mode === 'smart_compact') {
          el.classList.add('lc-compact-hide-orig');

          const box = document.createElement('div');
          box.className = 'lc-injected-box';
          box.setAttribute('data-lc-for', currentLiveText);

          const zhSpan = document.createElement('span');
          zhSpan.textContent = payload.zh;

          const speakBtn = createSpeakPill(payload.zh);

          const toggleBtn = document.createElement('span');
          toggleBtn.className = 'lc-action-pill';
          toggleBtn.textContent = '原文';

          const origDiv = document.createElement('div');
          origDiv.className = 'lc-orig-collapsible';
          origDiv.textContent = currentLiveText;

          toggleBtn.onclick = function(ev) {
            ev.stopPropagation();
            origDiv.classList.toggle('lc-open');
            toggleBtn.textContent = origDiv.classList.contains('lc-open') ? '收起' : '原文';
          };

          box.appendChild(zhSpan);
          box.appendChild(speakBtn);
          box.appendChild(toggleBtn);
          box.appendChild(origDiv);
          el.appendChild(box);
        } else {
          // Bilingual mode
          const box = document.createElement('div');
          box.className = 'lc-injected-box lc-injected-bilingual';
          box.setAttribute('data-lc-for', currentLiveText);

          const badge = document.createElement('span');
          badge.className = 'lc-zh-badge';
          badge.textContent = payload.badge || '译';

          const zhSpan = document.createElement('span');
          zhSpan.textContent = payload.zh;

          const speakBtn = createSpeakPill(payload.zh);

          box.appendChild(badge);
          box.appendChild(zhSpan);
          box.appendChild(speakBtn);
          el.appendChild(box);
        }
      };

      window.__LichessCN_updateConfig = function(enabled, mode) {
        config.enabled = enabled;
        config.mode = mode;
        window.__LichessCN_forceRescan();
      };

      window.__LichessCN_forceRescan = function() {
        document.querySelectorAll('.lc-injected-box, .lc-injected-inline, .lc-injected-chapter').forEach(n => n.remove());
        document.querySelectorAll('.lc-compact-hide-orig').forEach(el => el.classList.remove('lc-compact-hide-orig'));
        document.querySelectorAll('[data-lc-pending-text]').forEach(el => {
          delete el.dataset.lcPendingText;
          delete el.dataset.lcPendingTime;
        });
        scanStudyDOM(true);
      };

      let debounceTimer = null;
      function scheduleScan(delayMs) {
        if (debounceTimer) clearTimeout(debounceTimer);
        debounceTimer = setTimeout(() => scanStudyDOM(false), delayMs || 150);
      }

      const observer = new MutationObserver(function() {
        scheduleScan(140);
      });

      function startObserving() {
        ensureStyleInjected();
        if (document.body) {
          observer.observe(document.body, {
            childList: true,
            subtree: true,
            characterData: true
          });
          scanStudyDOM(false);
        }
      }

      document.addEventListener('click', () => {
        setTimeout(() => scanStudyDOM(false), 120);
        setTimeout(() => scanStudyDOM(false), 400);
      }, true);

      document.addEventListener('touchend', () => {
        setTimeout(() => scanStudyDOM(false), 150);
        setTimeout(() => scanStudyDOM(false), 450);
      }, true);

      if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', startObserving);
      } else {
        startObserving();
      }

      setInterval(() => scanStudyDOM(false), 650);
    })();
    """#
}

struct LichessHybridWebView: UIViewRepresentable {
    @ObservedObject var manager: HybridTranslationBridgeManager

    func makeCoordinator() -> Coordinator {
        Coordinator(manager: manager)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let userContentController = WKUserContentController()
        let script = WKUserScript(
            source: HybridTranslationBridgeManager.injectedStudyInterceptorJS,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
        userContentController.addUserScript(script)
        userContentController.add(context.coordinator, name: "lichessTranslator")
        config.userContentController = userContentController

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

        manager.webView = webView

        if let url = URL(string: manager.currentURLString) {
            var req = URLRequest(url: url)
            req.setValue("zh-CN,zh-Hans;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
            webView.load(req)
        }

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        let manager: HybridTranslationBridgeManager

        init(manager: HybridTranslationBridgeManager) {
            self.manager = manager
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "lichessTranslator",
                  let body = message.body as? [String: Any] else { return }
            Task { @MainActor in
                manager.handleScriptMessage(body)
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            Task { @MainActor in
                manager.isLoading = true
                manager.canGoBack = webView.canGoBack
                manager.canGoForward = webView.canGoForward
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in
                manager.isLoading = false
                manager.canGoBack = webView.canGoBack
                manager.canGoForward = webView.canGoForward
                manager.currentURLString = webView.url?.absoluteString ?? manager.currentURLString
                manager.pageTitle = webView.title ?? "Lichess"
                manager.syncConfigToWebView()
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}
