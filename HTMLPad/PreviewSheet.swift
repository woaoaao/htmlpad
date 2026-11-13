import SwiftUI
import WebKit

/// 预览当前 HTML（相对路径的 css / 图片可以正常加载）。
struct PreviewSheet: View {

    let url: URL?

    @Environment(\.dismiss) private var dismiss
    @State private var reloadToken = 0

    var body: some View {
        NavigationView {
            Group {
                if let url = url {
                    PreviewWebView(url: url, reloadToken: reloadToken)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "doc.questionmark")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("还没有可预览的文件，请先保存")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle(url?.lastPathComponent ?? "预览")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        reloadToken += 1
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("重新加载")
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

struct PreviewWebView: UIViewRepresentable {

    let url: URL
    let reloadToken: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(token: reloadToken)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        load(webView)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if context.coordinator.token != reloadToken {
            context.coordinator.token = reloadToken
            load(uiView)
        }
    }

    private func load(_ webView: WKWebView) {
        let directory = url.deletingLastPathComponent()
        let scoped = directory.startAccessingSecurityScopedResource()
        webView.loadFileURL(url, allowingReadAccessTo: directory)
        if scoped {
            // 让 WebKit 完成读取后再释放，这里简单地在下一轮 runloop 释放
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                directory.stopAccessingSecurityScopedResource()
            }
        }
    }

    final class Coordinator {
        var token: Int
        init(token: Int) {
            self.token = token
        }
    }
}
