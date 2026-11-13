import SwiftUI

struct ContentView: View {

    private enum ActiveSheet: Identifiable {
        case picker, preview, saveAs, share
        var id: Int { hashValue }
    }

    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    @State private var activeSheet: ActiveSheet?
    @State private var saveAsName = "未命名.html"

    private static let ulSnippet = "<ul>\n  <li></li>\n  <li></li>\n</ul>\n"
    private static let tableSnippet = """
    <table border="1" cellpadding="6" cellspacing="0">
      <tr><th>标题 1</th><th>标题 2</th></tr>
      <tr><td>内容</td><td>内容</td></tr>
    </table>

    """

    var body: some View {
        VStack(spacing: 0) {
            editorBar
            Divider()
            ZStack {
                Color(uiColor: .systemBackground)
                EditorWebView(model: model)
                if !model.isEditorReady {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("正在准备编辑器…")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
            }
            Divider()
            statusBar
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .picker:
                DocumentPicker(isPresented: pickerPresented) { url in
                    model.open(url: url)
                }
            case .preview:
                PreviewSheet(url: model.fileURL)
            case .saveAs:
                SaveAsSheet(name: $saveAsName) {
                    let name = saveAsName
                    activeSheet = nil
                    Task { @MainActor in
                        await model.saveAs(name: name)
                    }
                } onCancel: {
                    activeSheet = nil
                }
            case .share:
                ShareSheet(items: shareItems)
            }
        }
        .onChange(of: scenePhase) { phase in
            guard phase != .active else { return }
            Task { @MainActor in
                await model.autosaveIfNeeded()
            }
        }
    }

    private var pickerPresented: Binding<Bool> {
        Binding(
            get: { activeSheet == .picker },
            set: { if !$0 { activeSheet = nil } }
        )
    }

    private var shareItems: [Any] {
        if let url = model.fileURL {
            return [url]
        }
        return []
    }

    // MARK: - 顶部工具条

    private var editorBar: some View {
        HStack(spacing: 18) {
            Button(action: { activeSheet = .picker }) {
                Image(systemName: "folder")
                    .font(.system(size: 18, weight: .medium))
            }
            .accessibilityLabel("打开文件")

            Spacer(minLength: 4)

            VStack(spacing: 1) {
                Text(model.fileName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(model.isDirty ? "未保存" : "已保存")
                    .font(.caption2)
                    .foregroundColor(model.isDirty ? Color.orange : Color.secondary)
            }

            Spacer(minLength: 4)

            Button(action: startPreview) {
                Image(systemName: "eye")
                    .font(.system(size: 18, weight: .medium))
            }
            .accessibilityLabel("预览")

            Button(action: saveTapped) {
                Image(systemName: "tray.and.arrow.down")
                    .font(.system(size: 18, weight: .medium))
            }
            .accessibilityLabel("保存")

            Menu {
                menuContent
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 18, weight: .medium))
            }
            .accessibilityLabel("更多")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(uiColor: .secondarySystemBackground))
    }

    @ViewBuilder
    private var menuContent: some View {
        Button {
            model.newDocument()
        } label: {
            Label("新建空白页面", systemImage: "doc.badge.plus")
        }

        Button {
            prepareSaveAs()
        } label: {
            Label("另存为…", systemImage: "doc.on.doc")
        }

        Button {
            activeSheet = .share
        } label: {
            Label("导出 / 分享文件", systemImage: "square.and.arrow.up")
        }

        Button {
            model.reloadFromDisk()
        } label: {
            Label("重新载入", systemImage: "arrow.clockwise")
        }

        Divider()

        Menu {
            Button("标题 <h1>") { model.wrapSelection(before: "<h1>", after: "</h1>") }
            Button("段落 <p>") { model.wrapSelection(before: "<p>", after: "</p>") }
            Button("加粗 <strong>") { model.wrapSelection(before: "<strong>", after: "</strong>") }
            Button("链接 <a>") { model.wrapSelection(before: "<a href=\"https://example.com\">", after: "</a>") }
            Button("图片 <img>") { model.insertText("<img src=\"\" alt=\"\">") }
            Button("无序列表") { model.insertText(ContentView.ulSnippet) }
            Button("表格") { model.insertText(ContentView.tableSnippet) }
            Button("换行 <br>") { model.insertText("<br>") }
            Button("注释") { model.wrapSelection(before: "<!-- ", after: " -->") }
        } label: {
            Label("插入代码片段", systemImage: "chevron.left.forwardslash.chevron.right")
        }

        Divider()

        if model.recents.isEmpty {
            Text("暂无最近文件")
        } else {
            Menu {
                ForEach(model.recents) { item in
                    Button(item.name) { model.openRecent(item) }
                }
            } label: {
                Label("最近文件", systemImage: "clock")
            }
        }
    }

    // MARK: - 底部状态条

    private var statusBar: some View {
        HStack(spacing: 8) {
            Text(model.status)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Text("\(model.charCount) 字符")
                .monospacedDigit()
        }
        .font(.caption2)
        .foregroundColor(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color(uiColor: .secondarySystemBackground))
    }

    // MARK: - 动作

    private func prepareSaveAs() {
        let current = model.fileURL?.lastPathComponent ?? model.fileName
        saveAsName = current.isEmpty ? "未命名.html" : current
        activeSheet = .saveAs
    }

    private func saveTapped() {
        guard model.fileURL != nil else {
            prepareSaveAs()
            return
        }
        Task { @MainActor in
            await model.save()
        }
    }

    private func startPreview() {
        guard model.fileURL != nil else {
            prepareSaveAs()
            return
        }
        Task { @MainActor in
            if model.isDirty {
                await model.save()
            }
            if !model.isDirty {
                activeSheet = .preview
            }
        }
    }
}
