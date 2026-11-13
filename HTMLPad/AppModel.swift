import Foundation
import SwiftUI
import WebKit

/// “最近打开”记录。bookmark 为空时退化为按路径打开。
struct RecentItem: Identifiable, Codable, Equatable {
    var path: String
    var name: String
    var bookmark: Data
    var date: Date

    var id: String { path }
}

@MainActor
final class AppModel: ObservableObject {

    // MARK: - 对外状态

    @Published var fileName: String = "未命名.html"
    @Published var fileURL: URL?
    @Published var isDirty: Bool = false
    @Published var isEditorReady: Bool = false
    @Published var status: String = "点左上角「打开」选择一个 HTML 文件"
    @Published var charCount: Int = 0
    @Published var recents: [RecentItem] = []

    /// WKWebView 由 EditorWebView 创建后注册进来
    fileprivate weak var webView: WKWebView?

    private var pendingText: String?
    private static let recentsKey = "HtmlPad.recents.v1"

    init() {
        recents = AppModel.loadRecents()
    }

    // MARK: - 与网页编辑器通信

    func attach(webView: WKWebView) {
        self.webView = webView
    }

    func editorDidBecomeReady() {
        isEditorReady = true
        if let text = pendingText {
            pendingText = nil
            setEditorText(text)
        }
    }

    func editorChanged(length: Int) {
        charCount = length
        if !isDirty { isDirty = true }
    }

    private func setEditorText(_ text: String) {
        guard isEditorReady, let webView = webView else {
            pendingText = text
            return
        }
        webView.evaluateJavaScript("window.editor.setText(\(AppModel.jsLiteral(text)));")
    }

    private func fetchText() async -> String {
        guard isEditorReady, let webView = webView else { return "" }
        do {
            let value = try await webView.evaluateJavaScript("window.editor.getText()")
            return value as? String ?? ""
        } catch {
            return ""
        }
    }

    /// 用 before/after 包住当前选区
    func wrapSelection(before: String, after: String = "") {
        guard isEditorReady, let webView = webView else { return }
        webView.evaluateJavaScript(
            "window.editor.wrap(\(AppModel.jsLiteral(before)), \(AppModel.jsLiteral(after)));"
        )
    }

    /// 在光标处插入文本
    func insertText(_ text: String) {
        guard isEditorReady, let webView = webView else { return }
        webView.evaluateJavaScript("window.editor.insert(\(AppModel.jsLiteral(text)));")
    }

    /// 把 Swift 字符串安全地塞进 JS 源码（引号 / 换行 / 反斜杠全部转义）
    static func jsLiteral(_ value: String) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: [value], options: []),
           let encoded = String(data: data, encoding: .utf8) {
            return String(encoded.dropFirst().dropLast())
        }
        return "\"\""
    }

    // MARK: - 打开 / 载入

    func open(url: URL) {
        // 外层作用域用于创建书签；readText 内部也会成对地 start/stop，互不影响。
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        do {
            let text = try FileIO.readText(at: url)
            let bookmark = (try? url.bookmarkData(options: .minimalBookmark,
                                                  includingResourceValuesForKeys: nil,
                                                  relativeTo: nil)) ?? Data()
            applyLoaded(text: text, url: url, bookmark: bookmark)
        } catch {
            status = "打开失败：\(error.localizedDescription)"
        }
    }

    func newDocument() {
        let template = """
        <!DOCTYPE html>
        <html lang="zh-CN">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>新页面</title>
          <style>
            body {
              margin: 0;
              padding: 24px;
              font-family: -apple-system, "PingFang SC", sans-serif;
              line-height: 1.75;
              color: #1f2328;
            }
          </style>
        </head>
        <body>
          <h1>新页面</h1>
          <p>开始编辑吧。</p>
        </body>
        </html>
        """
        applyLoaded(text: template, url: nil, bookmark: nil)
        status = "已新建空白页面，保存后写入「我的 iPhone → HTML 编辑」"
    }

    private func applyLoaded(text: String, url: URL?, bookmark: Data) {
        fileURL = url
        fileName = url?.lastPathComponent ?? "未命名.html"
        isDirty = false
        charCount = text.count
        setEditorText(text)

        if let url = url {
            addRecent(url: url, bookmark: bookmark)
            if url.path.contains("/Documents/Inbox/") {
                status = "已打开其他 App 送来的副本，改完请用「导出 / 分享文件」发回去"
            } else {
                status = "已打开 \(url.lastPathComponent)"
            }
        }
    }

    func reloadFromDisk() {
        guard let url = fileURL else { return }
        open(url: url)
    }

    // MARK: - 保存

    func save() async {
        guard let url = fileURL else {
            status = "这个页面还没有保存位置，请使用「另存为」"
            return
        }
        let text = await fetchText()
        do {
            try FileIO.write(text, to: url)
            isDirty = false
            charCount = text.count
            status = "已保存 · \(AppModel.timeString())"
        } catch {
            status = "保存失败：\(error.localizedDescription)"
        }
    }

    func saveAs(name rawName: String) async {
        var name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { name = "未命名.html" }
        if (name as NSString).pathExtension.isEmpty { name += ".html" }

        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        var target = documents.appendingPathComponent(name)
        var counter = 2
        while FileManager.default.fileExists(atPath: target.path) {
            let base = (name as NSString).deletingPathExtension
            let ext = (name as NSString).pathExtension
            target = documents.appendingPathComponent(ext.isEmpty ? "\(base)-\(counter)" : "\(base)-\(counter).\(ext)")
            counter += 1
        }

        let text = await fetchText()
        do {
            try FileIO.write(text, to: target)
            fileURL = target
            fileName = target.lastPathComponent
            isDirty = false
            charCount = text.count
            addRecent(url: target, bookmark: Data())
            status = "已另存为 \(target.lastPathComponent)"
        } catch {
            status = "保存失败：\(error.localizedDescription)"
        }
    }

    /// 退到后台时自动存盘，避免内容丢失
    func autosaveIfNeeded() async {
        guard isDirty, fileURL != nil else { return }
        await save()
    }

    // MARK: - 最近文件

    private func addRecent(url: URL, bookmark: Data) {
        recents.removeAll { $0.path == url.path }
        let item = RecentItem(path: url.path, name: url.lastPathComponent, bookmark: bookmark, date: Date())
        recents.insert(item, at: 0)
        if recents.count > 12 { recents = Array(recents.prefix(12)) }
        AppModel.saveRecents(recents)
    }

    func openRecent(_ item: RecentItem) {
        if !item.bookmark.isEmpty {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: item.bookmark,
                                  options: [],
                                  relativeTo: nil,
                                  bookmarkDataIsStale: &stale) {
                open(url: url)
                if stale,
                   let fresh = try? url.bookmarkData(options: .minimalBookmark,
                                                    includingResourceValuesForKeys: nil,
                                                    relativeTo: nil) {
                    addRecent(url: url, bookmark: fresh)
                }
                return
            }
        }

        if FileManager.default.fileExists(atPath: item.path) {
            open(url: URL(fileURLWithPath: item.path))
        } else {
            recents.removeAll { $0.path == item.path }
            AppModel.saveRecents(recents)
            status = "文件已不存在：\(item.name)"
        }
    }

    func forgetRecent(_ item: RecentItem) {
        recents.removeAll { $0.path == item.path }
        AppModel.saveRecents(recents)
    }

    static func loadRecents() -> [RecentItem] {
        guard let data = UserDefaults.standard.data(forKey: recentsKey) else { return [] }
        return (try? JSONDecoder().decode([RecentItem].self, from: data)) ?? []
    }

    static func saveRecents(_ items: [RecentItem]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: recentsKey)
    }

    static func timeString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: Date())
    }
}
