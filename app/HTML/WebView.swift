//
//  WebView.swift
//  HTML — 本地 HTML 查看器
//
//  WKWebView 的 SwiftUI 封装：
//  · loadFileURL(_:allowingReadAccessTo:) 允许读取整个父文件夹 → CSS / JS / 图片正常加载
//  · 按设置决定：是否允许网络、是否启用 JS、外链在 App 内还是 Safari 打开
//  · 暴露 WKWebView 给工具栏做页内查找
//

import SwiftUI
import WebKit

// MARK: - 显示样式（浅色 / 深色 / 跟随系统）

enum PreviewStyle: Int, CaseIterable, Identifiable {
    case system = 0
    case light = 1
    case dark = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    var symbol: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }

    /// 直接映射到 WKWebView 的 overrideUserInterfaceStyle
    var uiStyle: UIUserInterfaceStyle {
        switch self {
        case .system: return .unspecified
        case .light: return .light
        case .dark: return .dark
        }
    }
}

// MARK: - 把 WKWebView 暴露给 SwiftUI

@MainActor
final class WebViewStore: ObservableObject {

    weak var webView: WKWebView?

    /// 页内查找（工具栏放大镜）
    func find(_ text: String, forward: Bool, completion: @escaping (Bool) -> Void) {
        guard let webView, !text.isEmpty else {
            completion(false)
            return
        }
        let configuration = WKFindConfiguration()
        configuration.backwards = !forward
        configuration.wraps = true
        configuration.caseSensitive = false

        webView.find(text, configuration: configuration) { result in
            DispatchQueue.main.async {
                completion(result.matchFound)
            }
        }
    }

    /// 清除查找高亮
    func clearFind() {
        guard let webView else { return }
        let configuration = WKFindConfiguration()
        configuration.backwards = false
        webView.find("", configuration: configuration) { _ in }
    }

    func reload() {
        webView?.reload()
    }
}

// MARK: - WebView

struct WebView: UIViewRepresentable {

    let url: URL
    let allowNetwork: Bool
    let allowJS: Bool
    let openExternalInSafari: Bool
    let style: UIUserInterfaceStyle
    let reloadToken: Int

    @ObservedObject var store: WebViewStore

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        if allowJS {
            controller.addUserScript(Self.pageFixScript())
        }

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        configuration.defaultWebpagePreferences.allowsContentJavaScript = allowJS
        configuration.allowsInlineMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.overrideUserInterfaceStyle = style
        webView.isOpaque = false
        webView.backgroundColor = .clear

        context.coordinator.webView = webView
        context.coordinator.requestedURL = url
        context.coordinator.loadedToken = reloadToken
        context.coordinator.lastAllowJS = allowJS
        store.webView = webView

        context.coordinator.start(allowNetwork: allowNetwork, url: url)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self

        // 显示样式：直接改 overrideUserInterfaceStyle，不用重新加载
        webView.overrideUserInterfaceStyle = style

        // JS 开关变化 → 需要重载
        if context.coordinator.lastAllowJS != allowJS {
            context.coordinator.lastAllowJS = allowJS
            webView.configuration.defaultWebpagePreferences.allowsContentJavaScript = allowJS
            webView.reload()
        }

        // 重新加载 / 换文件
        if context.coordinator.loadedToken != reloadToken || context.coordinator.requestedURL != url {
            context.coordinator.loadedToken = reloadToken
            context.coordinator.requestedURL = url
            context.coordinator.load(url: url)
        }

        // 网络开关变化
        context.coordinator.setNetworkAllowed(allowNetwork)
    }

    // 注入到页面的小脚本：补 viewport、把 target=_blank 改成当前页
    static func pageFixScript() -> WKUserScript {
        let source = """
        (function () {
          function fixViewport() {
            if (!document.head) { return; }
            if (!document.querySelector('meta[name="viewport"]')) {
              var meta = document.createElement('meta');
              meta.name = 'viewport';
              meta.content = 'width=device-width, initial-scale=1, viewport-fit=cover';
              document.head.appendChild(meta);
            }
          }
          if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', fixViewport);
          } else {
            fixViewport();
          }
          document.addEventListener('click', function (event) {
            var node = event.target;
            var anchor = node && node.closest ? node.closest('a[target="_blank"]') : null;
            if (anchor) { anchor.target = '_self'; }
          }, true);
        })();
        """
        return WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {

        var parent: WebView
        weak var webView: WKWebView?

        var requestedURL: URL?
        var loadedToken: Int
        var lastAllowJS: Bool

        private var networkAllowed: Bool?

        init(_ parent: WebView) {
            self.parent = parent
            self.loadedToken = parent.reloadToken
            self.lastAllowJS = parent.allowJS
            self.requestedURL = parent.url
            super.init()
        }

        // MARK: 首次加载（必要时先装上「拦截网络」规则再加载）

        func start(allowNetwork: Bool, url: URL) {
            if allowNetwork {
                removeRuleLists()
                networkAllowed = true
                load(url: url)
            } else {
                compileBlockRuleList { [weak self] list in
                    guard let self, let webView = self.webView else { return }
                    let controller = webView.configuration.userContentController
                    controller.removeAllContentRuleLists()
                    if let list {
                        controller.add(list)
                    }
                    self.networkAllowed = false
                    self.load(url: url)
                }
            }
        }

        /// 本地文件加载：允许读取整个父文件夹（保证相对路径的 css / js / 图片可用）
        func load(url: URL) {
            guard let webView else { return }
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }

        func setNetworkAllowed(_ allowed: Bool) {
            guard networkAllowed != allowed else { return }

            if allowed {
                removeRuleLists()
                networkAllowed = true
                webView?.reload()
            } else {
                compileBlockRuleList { [weak self] list in
                    guard let self, let webView = self.webView else { return }
                    let controller = webView.configuration.userContentController
                    controller.removeAllContentRuleLists()
                    if let list {
                        controller.add(list)
                    }
                    self.networkAllowed = false
                    webView.reload()
                }
            }
        }

        private func removeRuleLists() {
            webView?.configuration.userContentController.removeAllContentRuleLists()
        }

        // MARK: 网络拦截规则（WKContentRuleList，只作用于 http/https，本地文件不受影响）

        private static var cachedBlockList: WKContentRuleList?
        private static var isCompiling = false
        private static var waiters: [(WKContentRuleList?) -> Void] = []

        private func compileBlockRuleList(_ completion: @escaping (WKContentRuleList?) -> Void) {
            if let cached = Coordinator.cachedBlockList {
                completion(cached)
                return
            }

            Coordinator.waiters.append(completion)
            guard !Coordinator.isCompiling else { return }
            Coordinator.isCompiling = true

            let json = "[{\"trigger\":{\"url-filter\":\".*\"},\"action\":{\"type\":\"block\"}}]"
            WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: "html.blockall",
                encodedContentRuleList: json
            ) { list, _ in
                DispatchQueue.main.async {
                    Coordinator.cachedBlockList = list
                    Coordinator.isCompiling = false
                    let callbacks = Coordinator.waiters
                    Coordinator.waiters.removeAll()
                    callbacks.forEach { $0(list) }
                }
            }
        }

        // MARK: WKNavigationDelegate

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {

            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            let scheme = (url.scheme ?? "").lowercased()

            // 本地文件与内联内容一律放行
            if scheme.isEmpty || scheme == "file" || scheme == "about"
                || scheme == "data" || scheme == "blob" || scheme == "javascript" {
                decisionHandler(.allow)
                return
            }

            // target=_blank：没有目标 frame，改成当前页面跳转
            if navigationAction.targetFrame == nil {
                if parent.allowNetwork {
                    webView.load(URLRequest(url: url))
                }
                decisionHandler(.cancel)
                return
            }

            // 禁止网络：一切 http/https 请求直接拦掉
            guard parent.allowNetwork else {
                decisionHandler(.cancel)
                return
            }

            // 外链：按设置决定留在 App 内还是交给 Safari
            let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? false
            if isMainFrame && parent.openExternalInSafari {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {

            guard let url = navigationAction.request.url,
                  let scheme = url.scheme?.lowercased(),
                  scheme != "about", scheme != "javascript" else {
                return nil
            }

            if !parent.allowNetwork {
                return nil
            }

            if parent.openExternalInSafari {
                UIApplication.shared.open(url)
            } else {
                webView.load(URLRequest(url: url))
            }
            return nil
        }
    }
}
