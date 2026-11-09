import Foundation
import WebKit
import Combine

@MainActor
final class HybridTranslationBridgeManager: NSObject, ObservableObject {
    @Published var currentURLString: String = "https://lichess.org/study"
    @Published var pageTitle: String = "Lichess.org"
    @Published var isLoading: Bool = false
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false

    // Real-time intercepted study comment state
    @Published var activeOriginalComment: String = ""
    @Published var activeTranslatedComment: String = ""
    @Published var activeChapterTitle: String = ""
    @Published var isTranslatingNow: Bool = false
    @Published var translatedCount: Int = 0
    @Published var lastUsedProviderBadge: String = "GTX极速"

    // User preferences
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
    @Published var injectionModeRaw: String = InlineInjectionMode.bilingual.rawValue {
        didSet { syncConfigToWebView() }
    }
    @Published var showFloatingSubtitleCard: Bool = true

    weak var webView: WKWebView?

    var selectedProvider: TranslationProviderType {
        get { TranslationProviderType(rawValue: selectedProviderRaw) ?? .gtxHybrid }
        set { selectedProviderRaw = newValue.rawValue }
    }

    var injectionMode: InlineInjectionMode {
        get { InlineInjectionMode(rawValue: injectionModeRaw) ?? .bilingual }
        set { injectionModeRaw = newValue.rawValue }
    }

    func navigateTo(_ urlString: String) {
        var target = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !target.hasPrefix("http://") && !target.hasPrefix("https://") {
            if target.count == 8 && !target.contains("/") && !target.contains(".") {
                // Treat 8-char ID as a Lichess Study ID
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

    // Handles incoming messages from the injected WKUserScript
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

            // Escape string safely for JS injection
            if let jsonData = try? JSONSerialization.data(withJSONObject: [
                "id": domId,
                "zh": zh,
                "badge": used.shortBadge,
                "mode": injectionMode.rawValue
            ]),
               let jsonStr = String(data: jsonData, encoding: .utf8) {
                let js = "if (window.__LichessCN_applyTranslation) { window.__LichessCN_applyTranslation(\(jsonStr)); }"
                webView?.evaluateJavaScript(js, completionHandler: nil)
            }
        }
    }

    // MARK: - Injected JavaScript for Lichess Study Real-Time Interception & Inline DOM Rendering
    static let injectedStudyInterceptorJS = #"""
    (function() {
      if (window.__LichessCN_Initialized) return;
      window.__LichessCN_Initialized = true;

      let config = {
        enabled: true,
        mode: 'bilingual' // 'bilingual' | 'replace' | 'subtitle_only'
      };

      let nodeCounter = 1;
      let lastActiveCommentText = '';

      // Inject CSS styling for inline Chinese translations inside Lichess dark & light themes
      function ensureStyleInjected() {
        if (document.getElementById('lichesscn-inline-style')) return;
        const style = document.createElement('style');
        style.id = 'lichesscn-inline-style';
        style.textContent = `
          .lc-zh-block {
            margin-top: 6px;
            padding: 6px 10px;
            border-left: 3px solid #3893e8;
            background: rgba(56, 147, 232, 0.13);
            border-radius: 4px;
            font-size: 0.95em;
            line-height: 1.45;
            color: inherit;
            font-weight: 500;
            word-break: break-word;
          }
          .lc-zh-inline {
            display: inline-block;
            margin-left: 4px;
            padding: 1px 6px;
            background: rgba(56, 147, 232, 0.16);
            border-radius: 4px;
            color: #5ab2ff;
            font-weight: 500;
          }
          .lc-zh-chapter {
            display: block;
            margin-top: 2px;
            font-size: 0.88em;
            color: #5ab2ff;
            font-weight: 500;
          }
          .lc-zh-badge {
            display: inline-block;
            font-size: 0.72em;
            padding: 1px 5px;
            margin-right: 6px;
            border-radius: 3px;
            background: rgba(56, 147, 232, 0.25);
            color: #6bc0ff;
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

      // Extract clean text from an element while ignoring our own injected .lc-zh-* nodes
      function extractOriginalText(el) {
        if (el.dataset && el.dataset.lcOrigText) {
          return el.dataset.lcOrigText;
        }
        const clone = el.cloneNode(true);
        const injected = clone.querySelectorAll('.lc-zh-block, .lc-zh-inline, .lc-zh-chapter, .author, .by');
        injected.forEach(n => n.remove());
        return (clone.innerText || clone.textContent || '').trim();
      }

      // Scan Lichess Study DOM for chapters, active commentary, gamebook prompts, and move tree comments
      function scanStudyDOM(forceAll) {
        if (!config.enabled) return;
        ensureStyleInjected();

        const batch = [];

        // 1. Active Study Comment Box (.study__comments, .gamebook .comment, .analyse__tools .comment)
        const activeSelectors = [
          '.study__comments .content',
          '.study__comments',
          '.gamebook .comment',
          '.gamebook__comment',
          '.gamebook .hint',
          '.analyse__tools > .ceval + .comment',
          '.analyse__underboard .study__comments'
        ];

        for (const sel of activeSelectors) {
          const nodes = document.querySelectorAll(sel);
          nodes.forEach(el => {
            const text = extractOriginalText(el);
            if (!text || text.length < 2 || hasMostlyChinese(text)) return;

            if (text !== lastActiveCommentText) {
              lastActiveCommentText = text;
              const activeChapEl = document.querySelector('.study__chapters .active h3, .study__chapters .elem.active h3, .study__chapters .active');
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
              el.dataset.lcLastSource = text;
              el.dataset.lcKind = 'active_comment';
              batch.push({ id: el.dataset.lcId, text: text, kind: 'active_comment' });
            }
          });
        }

        // 2. Move Tree Inline Comments (<comment> inside .analyse__moves / .tview2)
        const inlineComments = document.querySelectorAll('.tview2 comment, .analyse__moves comment, comment');
        inlineComments.forEach(el => {
          const text = extractOriginalText(el);
          if (!text || text.length < 2 || hasMostlyChinese(text)) return;
          if (forceAll || el.dataset.lcLastSource !== text) {
            if (!el.dataset.lcId) {
              el.dataset.lcId = 'lc_node_' + (nodeCounter++);
            }
            el.dataset.lcLastSource = text;
            el.dataset.lcKind = 'inline_comment';
            batch.push({ id: el.dataset.lcId, text: text, kind: 'inline_comment' });
          }
        });

        // 3. Study Chapter List Titles (.study__chapters h3)
        const chapterNodes = document.querySelectorAll('.study__chapters h3, .study__chapters .chapter-name, .study__chapters > div > h3');
        chapterNodes.forEach(el => {
          const text = extractOriginalText(el);
          if (!text || text.length < 2 || hasMostlyChinese(text)) return;
          if (forceAll || el.dataset.lcLastSource !== text) {
            if (!el.dataset.lcId) {
              el.dataset.lcId = 'lc_node_' + (nodeCounter++);
            }
            el.dataset.lcLastSource = text;
            el.dataset.lcKind = 'chapter_title';
            batch.push({ id: el.dataset.lcId, text: text, kind: 'chapter_title' });
          }
        });

        if (batch.length > 0) {
          // Send in chunks of 12 to avoid overwhelming a single bridge message
          const slice = batch.slice(0, 12);
          try {
            window.webkit.messageHandlers.lichessTranslator.postMessage({
              action: 'translateBatch',
              items: slice
            });
          } catch (e) {}
        }
      }

      // Callback invoked by Native Swift once a translation completes
      window.__LichessCN_applyTranslation = function(payload) {
        if (!payload || !payload.id || !payload.zh) return;
        const el = document.querySelector('[data-lc-id="' + payload.id + '"]');
        if (!el) return;

        // Remove any previous injected translation inside this element
        const oldInjected = el.querySelectorAll('.lc-zh-block, .lc-zh-inline, .lc-zh-chapter');
        oldInjected.forEach(n => n.remove());

        if (config.mode === 'subtitle_only') {
          return;
        }

        const kind = el.dataset.lcKind || 'comment';
        if (config.mode === 'replace') {
          if (!el.dataset.lcOrigText) {
            el.dataset.lcOrigText = extractOriginalText(el);
          }
          el.textContent = payload.zh;
          return;
        }

        // Default: Bilingual inline injection
        if (kind === 'chapter_title') {
          const span = document.createElement('span');
          span.className = 'lc-zh-chapter';
          span.textContent = '译: ' + payload.zh;
          el.appendChild(span);
        } else if (kind === 'inline_comment') {
          const span = document.createElement('span');
          span.className = 'lc-zh-inline';
          span.textContent = ' [译: ' + payload.zh + ']';
          el.appendChild(span);
        } else {
          const div = document.createElement('div');
          div.className = 'lc-zh-block';
          const badge = document.createElement('span');
          badge.className = 'lc-zh-badge';
          badge.textContent = payload.badge || '中文精译';
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
        scanStudyDOM(true);
      };

      window.__LichessCN_forceRescan = function() {
        document.querySelectorAll('[data-lc-last-source]').forEach(el => {
          delete el.dataset.lcLastSource;
        });
        lastActiveCommentText = '';
        scanStudyDOM(true);
      };

      // Selection listener: if user selects any text on page, send it to native subtitle bar for instant translation
      document.addEventListener('selectionchange', function() {
        const sel = window.getSelection ? window.getSelection().toString().trim() : '';
        if (sel && sel.length >= 3 && sel.length <= 600 && !hasMostlyChinese(sel)) {
          if (sel !== lastActiveCommentText) {
            lastActiveCommentText = sel;
            try {
              window.webkit.messageHandlers.lichessTranslator.postMessage({
                action: 'activeCommentChanged',
                text: sel,
                chapter: '划词实时翻译'
              });
            } catch (e) {}
          }
        }
      });

      // Debounced MutationObserver to catch Lichess Snabbdom virtual-DOM updates as moves change
      let debounceTimer = null;
      function scheduleScan() {
        if (debounceTimer) clearTimeout(debounceTimer);
        debounceTimer = setTimeout(() => scanStudyDOM(false), 280);
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

      // Periodic lightweight check for virtual-DOM replacements in Lichess analyse/study view
      setInterval(() => scanStudyDOM(false), 1500);
    })();
    """#
}

// MARK: - SwiftUI WKWebView Wrapper
import SwiftUI

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
