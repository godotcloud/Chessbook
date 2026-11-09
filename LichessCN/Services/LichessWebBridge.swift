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
    // Default to smartCompact so Chinese replaces long English in-place with an [原文] toggle button,
    // completely preventing text crowding!
    @Published var injectionModeRaw: String = InlineInjectionMode.smartCompact.rawValue {
        didSet { syncConfigToWebView() }
    }
    // Off by default so the bottom of the screen is never covered unless the user wants a floating card
    @Published var showFloatingSubtitleCard: Bool = false
    @Published var isCompactFullscreen: Bool = false

    weak var webView: WKWebView?

    var selectedProvider: TranslationProviderType {
        get { TranslationProviderType(rawValue: selectedProviderRaw) ?? .gtxHybrid }
        set { selectedProviderRaw = newValue.rawValue }
    }

    var injectionMode: InlineInjectionMode {
        get { InlineInjectionMode(rawValue: injectionModeRaw) ?? .smartCompact }
        set { injectionModeRaw = newValue.rawValue }
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
        webView?.load(URLRequest(url: url))
    }

    func goBack() { webView?.goBack() }
    func goForward() { webView?.goForward() }
    func reload() { webView?.reload() }

    func syncConfigToWebView() {
        let enabledStr = autoTranslateEnabled ? "true" : "false"
        let modeStr = injectionMode.rawValue
        let js = "if (window.__LichessCN_updateConfig) { window.__LichessCN_updateConfig(\(enabledStr), '\(modeStr)'); }"
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }

    func triggerFullPageRescan() {
        let js = "if (window.__LichessCN_forceRescan) { window.__LichessCN_forceRescan(); }"
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }

    func handleScriptMessage(_ body: [String: Any]) {
        guard let action = body["action"] as? String else { return }

        switch action {
        case "translateBatch":
            guard autoTranslateEnabled,
                  let items = body["items"] as? [[String: String]] else { return }
            Task {
                await processTranslationBatch(items)
            }

        case "activeCommentChanged":
            let rawText = (body["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let chapter = (body["chapter"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !chapter.isEmpty {
                activeChapterTitle = chapter
            }
            guard !rawText.isEmpty else { return }
            activeOriginalComment = rawText
            guard autoTranslateEnabled else { return }

            Task {
                isTranslatingNow = true
                let (zh, used) = await ChessTranslationService.shared.translateToChinese(
                    text: rawText,
                    preferredProvider: selectedProvider
                )
                activeTranslatedComment = zh
                lastUsedProviderBadge = used.shortBadge
                isTranslatingNow = false
            }

        default:
            break
        }
    }

    private func processTranslationBatch(_ items: [[String: String]]) async {
        guard !items.isEmpty else { return }
        isTranslatingNow = true
        defer { isTranslatingNow = false }

        for item in items {
            guard let domId = item["id"],
                  let rawText = item["text"],
                  !rawText.isEmpty else { continue }
            let kind = item["kind"] ?? "comment"

            let (zh, used) = await ChessTranslationService.shared.translateToChinese(
                text: rawText,
                preferredProvider: selectedProvider
            )
            lastUsedProviderBadge = used.shortBadge
            translatedCount += 1

            if kind == "active_comment" {
                activeOriginalComment = rawText
                activeTranslatedComment = zh
            }

            if let jsonData = try? JSONSerialization.data(withJSONObject: [
                "id": domId,
                "zh": zh,
                "orig": rawText,
                "badge": used.shortBadge,
                "mode": injectionMode.rawValue
            ]),
               let jsonStr = String(data: jsonData, encoding: .utf8) {
                let js = "if (window.__LichessCN_applyTranslation) { window.__LichessCN_applyTranslation(\(jsonStr)); }"
                webView?.evaluateJavaScript(js, completionHandler: nil)
            }
        }
    }

    // MARK: - Injected JS & Responsive Layout CSS (Fixes .gamebook overlap, chapter clipping & board top cutoff)
    static let injectedStudyInterceptorJS = #"""
    (function() {
      if (window.__LichessCN_Initialized) return;
      window.__LichessCN_Initialized = true;

      let config = {
        enabled: true,
        mode: 'smart_compact' // 'smart_compact' | 'bilingual' | 'subtitle_only'
      };

      let nodeCounter = 1;
      let lastActiveCommentText = '';

      function ensureStyleInjected() {
        if (document.getElementById('lichesscn-inline-style')) return;
        const style = document.createElement('style');
        style.id = 'lichesscn-inline-style';
        style.textContent = `
          /* 1. Prevent chessboard top rank from being clipped under header */
          main.analyse {
            padding-top: 2px !important;
          }

          /* 2. Fix .gamebook (Interactive Study) overlap between comment text, green Next button (.floor), and blue octopus (.mascot) */
          .gamebook {
            display: flex !important;
            flex-direction: column !important;
            justify-content: space-between !important;
            height: auto !important;
            max-height: none !important;
            overflow: visible !important;
            position: relative !important;
            padding-bottom: 6px !important;
          }
          .gamebook .comment {
            position: relative !important;
            max-height: 155px !important;
            overflow-y: auto !important;
            -webkit-overflow-scrolling: touch !important;
            padding: 8px 12px !important;
            margin-bottom: 6px !important;
            font-size: 0.94rem !important;
            line-height: 1.48 !important;
            z-index: 2 !important;
          }
          .gamebook .floor {
            position: relative !important;
            top: auto !important;
            bottom: auto !important;
            left: auto !important;
            right: auto !important;
            margin-top: 4px !important;
            padding: 4px 10px !important;
            min-height: 44px !important;
            display: flex !important;
            align-items: center !important;
            justify-content: center !important;
            z-index: 3 !important;
          }
          .gamebook .floor button.next,
          .gamebook .floor button {
            position: relative !important;
            padding: 8px 18px !important;
            font-size: 1rem !important;
            border-radius: 8px !important;
          }
          /* Shrink decorative blue octopus mascot so it never blocks Chinese text */
          .gamebook .mascot {
            width: 34px !important;
            height: 34px !important;
            right: 6px !important;
            bottom: 6px !important;
            opacity: 0.22 !important;
            pointer-events: none !important;
            z-index: 1 !important;
          }

          /* 3. Fix regular .study__comments scrolling cleanly without pushing page layout */
          .study__comments {
            max-height: 150px !important;
            overflow-y: auto !important;
            -webkit-overflow-scrolling: touch !important;
          }

          /* 4. Fix .study__chapters row height so translated chapter names are never cut off */
          .study__chapters > div,
          .study__chapters .elem,
          .study__chapters button {
            height: auto !important;
            min-height: 2.4rem !important;
            padding-top: 5px !important;
            padding-bottom: 5px !important;
            align-items: center !important;
          }
          .study__chapters h3 {
            white-space: normal !important;
            line-height: 1.32 !important;
            font-size: 0.9rem !important;
          }

          /* 5. Clean styling for injected Chinese translations */
          .lc-smart-wrap {
            display: block;
            line-height: 1.48;
            word-break: break-word;
          }
          .lc-smart-zh {
            color: inherit;
            font-weight: 500;
          }
          .lc-toggle-orig-btn {
            display: inline-block;
            margin-left: 6px;
            padding: 1px 6px;
            font-size: 0.74em;
            border-radius: 4px;
            background: rgba(56, 147, 232, 0.18);
            color: #3893e8;
            cursor: pointer;
            user-select: none;
            font-weight: 600;
            vertical-align: middle;
          }
          .lc-orig-collapsible {
            display: none;
            margin-top: 5px;
            padding-top: 5px;
            border-top: 1px dashed rgba(128, 128, 128, 0.3);
            font-size: 0.85em;
            opacity: 0.78;
            line-height: 1.38;
          }
          .lc-orig-collapsible.lc-open {
            display: block;
          }
          .lc-zh-block {
            margin-top: 5px;
            padding: 5px 8px;
            border-left: 3px solid #3893e8;
            background: rgba(56, 147, 232, 0.11);
            border-radius: 4px;
            font-size: 0.92em;
            line-height: 1.42;
            color: inherit;
            font-weight: 500;
            word-break: break-word;
          }
          .lc-zh-inline {
            display: inline;
            margin-left: 3px;
            color: #3893e8;
            font-weight: 500;
          }
          .lc-zh-chapter-inline {
            display: inline;
            margin-left: 6px;
            font-size: 0.92em;
            color: #3893e8;
            font-weight: 600;
          }
          .lc-zh-badge {
            display: inline-block;
            font-size: 0.7em;
            padding: 0px 4px;
            margin-right: 5px;
            border-radius: 3px;
            background: rgba(56, 147, 232, 0.2);
            color: #3893e8;
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

      function extractOriginalText(el) {
        if (el.dataset && el.dataset.lcOrigText) {
          return el.dataset.lcOrigText;
        }
        const clone = el.cloneNode(true);
        const injected = clone.querySelectorAll('.lc-smart-wrap, .lc-zh-block, .lc-zh-inline, .lc-zh-chapter-inline, .author, .by');
        injected.forEach(n => n.remove());
        return (clone.innerText || clone.textContent || '').trim();
      }

      function scanStudyDOM(forceAll) {
        if (!config.enabled) return;
        ensureStyleInjected();

        const batch = [];

        // 1. Active Study Comment Box (.gamebook .comment, .study__comments)
        const activeSelectors = [
          '.gamebook .comment .content',
          '.gamebook .comment',
          '.study__comments .content',
          '.study__comments',
          '.gamebook .hint'
        ];

        const visitedElements = new Set();

        for (const sel of activeSelectors) {
          const nodes = document.querySelectorAll(sel);
          nodes.forEach(el => {
            // Avoid translating both .gamebook .comment and its child .content
            if (visitedElements.has(el) || (el.parentElement && visitedElements.has(el.parentElement))) return;
            if (el.querySelector('.content') && sel === '.gamebook .comment') return;
            if (el.querySelector('.content') && sel === '.study__comments') return;

            const text = extractOriginalText(el);
            if (!text || text.length < 2 || hasMostlyChinese(text)) return;
            visitedElements.add(el);

            if (text !== lastActiveCommentText) {
              lastActiveCommentText = text;
              const activeChapEl = document.querySelector('.study__chapters .active h3, .study__chapters .elem.active h3');
              const chapName = activeChapEl ? extractOriginalText(activeChapEl) : '';
              try {
                window.webkit.messageHandlers.lichessTranslator.postMessage({
                  action: 'activeCommentChanged',
                  text: text,
                  chapter: chapName
                });
              } catch (e) {}
            }

            if (forceAll || el.dataset.lcLastSource !== text) {
              if (!el.dataset.lcId) {
                el.dataset.lcId = 'lc_node_' + (nodeCounter++);
              }
              el.dataset.lcOrigText = text;
              el.dataset.lcLastSource = text;
              el.dataset.lcKind = 'active_comment';
              batch.push({ id: el.dataset.lcId, text: text, kind: 'active_comment' });
            }
          });
        }

        // 2. Move Tree Inline Comments (<comment> inside .tview2 / .analyse__moves)
        const inlineComments = document.querySelectorAll('.tview2 comment, .analyse__moves comment');
        inlineComments.forEach(el => {
          const text = extractOriginalText(el);
          if (!text || text.length < 2 || hasMostlyChinese(text)) return;
          if (forceAll || el.dataset.lcLastSource !== text) {
            if (!el.dataset.lcId) {
              el.dataset.lcId = 'lc_node_' + (nodeCounter++);
            }
            el.dataset.lcOrigText = text;
            el.dataset.lcLastSource = text;
            el.dataset.lcKind = 'inline_comment';
            batch.push({ id: el.dataset.lcId, text: text, kind: 'inline_comment' });
          }
        });

        // 3. Study Chapter List Titles (.study__chapters h3)
        const chapterNodes = document.querySelectorAll('.study__chapters h3, .study__chapters .chapter-name');
        chapterNodes.forEach(el => {
          const text = extractOriginalText(el);
          if (!text || text.length < 2 || hasMostlyChinese(text)) return;
          if (forceAll || el.dataset.lcLastSource !== text) {
            if (!el.dataset.lcId) {
              el.dataset.lcId = 'lc_node_' + (nodeCounter++);
            }
            el.dataset.lcOrigText = text;
            el.dataset.lcLastSource = text;
            el.dataset.lcKind = 'chapter_title';
            batch.push({ id: el.dataset.lcId, text: text, kind: 'chapter_title' });
          }
        });

        if (batch.length > 0) {
          const slice = batch.slice(0, 12);
          try {
            window.webkit.messageHandlers.lichessTranslator.postMessage({
              action: 'translateBatch',
              items: slice
            });
          } catch (e) {}
        }
      }

      window.__LichessCN_applyTranslation = function(payload) {
        if (!payload || !payload.id || !payload.zh) return;
        const el = document.querySelector('[data-lc-id="' + payload.id + '"]');
        if (!el) return;

        const origText = el.dataset.lcOrigText || payload.orig || extractOriginalText(el);
        el.dataset.lcOrigText = origText;

        // Clean any previous injected nodes
        const oldInjected = el.querySelectorAll('.lc-smart-wrap, .lc-zh-block, .lc-zh-inline, .lc-zh-chapter-inline');
        oldInjected.forEach(n => n.remove());

        if (config.mode === 'subtitle_only') {
          el.textContent = origText;
          return;
        }

        const kind = el.dataset.lcKind || 'comment';

        if (kind === 'chapter_title') {
          // Single-line compact chapter title: "中文名 · Original" so it never clips vertically
          el.textContent = payload.zh + ' · ' + origText;
          return;
        }

        if (kind === 'inline_comment') {
          if (config.mode === 'smart_compact') {
            el.textContent = payload.zh;
          } else {
            el.textContent = origText;
            const span = document.createElement('span');
            span.className = 'lc-zh-inline';
            span.textContent = ' [' + payload.zh + ']';
            el.appendChild(span);
          }
          return;
        }

        // Active comment (.gamebook .comment or .study__comments)
        if (config.mode === 'smart_compact') {
          // Replace bulky English paragraph in-place with Chinese + a tiny [原文] toggle button
          el.innerHTML = '';
          const wrap = document.createElement('div');
          wrap.className = 'lc-smart-wrap';

          const zhSpan = document.createElement('span');
          zhSpan.className = 'lc-smart-zh';
          zhSpan.textContent = payload.zh;

          const toggleBtn = document.createElement('span');
          toggleBtn.className = 'lc-toggle-orig-btn';
          toggleBtn.textContent = '原文';

          const origDiv = document.createElement('div');
          origDiv.className = 'lc-orig-collapsible';
          origDiv.textContent = origText;

          toggleBtn.onclick = function(ev) {
            ev.stopPropagation();
            origDiv.classList.toggle('lc-open');
            toggleBtn.textContent = origDiv.classList.contains('lc-open') ? '收起原文' : '原文';
          };

          wrap.appendChild(zhSpan);
          wrap.appendChild(toggleBtn);
          wrap.appendChild(origDiv);
          el.appendChild(wrap);
        } else {
          // Bilingual mode
          el.textContent = origText;
          const div = document.createElement('div');
          div.className = 'lc-zh-block';
          const badge = document.createElement('span');
          badge.className = 'lc-zh-badge';
          badge.textContent = payload.badge || '译';
          const txt = document.createElement('span');
          txt.textContent = payload.zh;
          div.appendChild(badge);
          div.appendChild(txt);
          el.appendChild(div);
        }
      };

      window.__LichessCN_updateConfig = function(enabled, mode) {
        config.enabled = enabled;
        config.mode = mode;
        window.__LichessCN_forceRescan();
      };

      window.__LichessCN_forceRescan = function() {
        document.querySelectorAll('[data-lc-id]').forEach(el => {
          if (el.dataset.lcOrigText) {
            el.textContent = el.dataset.lcOrigText;
          }
          delete el.dataset.lcLastSource;
        });
        lastActiveCommentText = '';
        scanStudyDOM(true);
      };

      let debounceTimer = null;
      function scheduleScan() {
        if (debounceTimer) clearTimeout(debounceTimer);
        debounceTimer = setTimeout(() => scanStudyDOM(false), 240);
      }

      const observer = new MutationObserver(function() {
        scheduleScan();
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

      if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', startObserving);
      } else {
        startObserving();
      }

      setInterval(() => scanStudyDOM(false), 1400);
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
