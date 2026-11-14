//
//  HomeView.swift
//  HTML — 本地 HTML 查看器
//
//  主页：标题「HTML」＋ 右上角蓝色「+」（打开文件 / 粘贴代码 / 打开文件夹）＋ 搜索 ＋ 文件列表。
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct HomeView: View {

    @EnvironmentObject private var fileManager: FileManagerModel

    @State private var searchText = ""
    @State private var showHTMLImporter = false
    @State private var showFolderImporter = false
    @State private var showPasteSheet = false
    @State private var pasteSeed = "新建页面.html"
    @State private var pasteCode = ""
    @State private var previewFile: HTMLFile?
    @State private var pendingDelete: HTMLFile?

    /// 搜索过滤（按文件名，忽略大小写）
    private var filteredFiles: [HTMLFile] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return fileManager.files }
        return fileManager.files.filter {
            $0.name.localizedCaseInsensitiveContains(keyword)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if fileManager.files.isEmpty {
                    EmptyStateView(
                        symbol: "doc.text.magnifyingglass",
                        title: "还没有 HTML 文件",
                        message: "点右上角「+」从「文件」App 导入，或直接粘贴一段 HTML 代码。"
                    )
                } else if filteredFiles.isEmpty {
                    EmptyStateView(
                        symbol: "magnifyingglass",
                        title: "没有匹配的文件",
                        message: "试试别的关键词。"
                    )
                } else {
                    List {
                        ForEach(filteredFiles) { file in
                            Button {
                                previewFile = file
                            } label: {
                                FileRow(file: file, isFavorite: fileManager.isFavorite(file))
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    pendingDelete = file
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                                Button {
                                    fileManager.toggleFavorite(file)
                                } label: {
                                    Label(
                                        fileManager.isFavorite(file) ? "取消收藏" : "收藏",
                                        systemImage: fileManager.isFavorite(file) ? "star.slash" : "star"
                                    )
                                }
                                .tint(.orange)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .refreshable {
                        fileManager.refresh()
                    }
                }
            }
            .navigationTitle("HTML")
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "搜索文件"
            )
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    addMenu
                }
            }
            // 打开 HTML 文件
            .fileImporter(
                isPresented: $showHTMLImporter,
                allowedContentTypes: [.html, .plainText],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first { fileManager.importFile(from: url) }
                case .failure(let error):
                    fileManager.lastError = "选择文件失败：\(error.localizedDescription)"
                }
            }
            // 打开文件夹（连 css / js / 图片一起拷贝）
            .fileImporter(
                isPresented: $showFolderImporter,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first { fileManager.importFolder(from: url) }
                case .failure(let error):
                    fileManager.lastError = "选择文件夹失败：\(error.localizedDescription)"
                }
            }
            // 粘贴代码（半屏 Sheet）
            .sheet(isPresented: $showPasteSheet) {
                PasteCodeSheet(initialName: pasteSeed, initialCode: pasteCode) { name, code in
                    if let url = fileManager.createFile(named: name, content: code) {
                        if let created = fileManager.files.first(where: { $0.url == url }) {
                            previewFile = created
                        }
                    }
                }
            }
            // 全屏预览
            .fullScreenCover(item: $previewFile) { file in
                HTMLPreviewView(file: file)
            }
            .confirmationDialog(
                pendingDelete.map { "删除「\($0.name)」？" } ?? "删除文件？",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("删除", role: .destructive) {
                    if let file = pendingDelete { fileManager.delete(file) }
                    pendingDelete = nil
                }
                Button("取消", role: .cancel) { pendingDelete = nil }
            }
        }
    }

    // MARK: - 右上角「+」菜单

    private var addMenu: some View {
        Menu {
            Button {
                showHTMLImporter = true
            } label: {
                Label("打开 HTML 文件", systemImage: "doc.badge.plus")
            }

            Button {
                pasteSeed = "新建页面.html"
                pasteCode = ""
                showPasteSheet = true
            } label: {
                Label("粘贴代码", systemImage: "doc.on.clipboard")
            }

            Button {
                let clipboard = UIPasteboard.general.string ?? ""
                pasteSeed = "剪贴板页面.html"
                pasteCode = clipboard
                showPasteSheet = true
            } label: {
                Label("从剪贴板新建文件", systemImage: "doc.on.clipboard.fill")
            }

            Button {
                showFolderImporter = true
            } label: {
                Label("打开文件夹", systemImage: "folder.badge.plus")
            }
        } label: {
            Image(systemName: "plus.circle.fill")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
        }
        .tint(.blue)
        .accessibilityLabel("添加")
    }
}

// MARK: - 文件列表行

struct FileRow: View {

    let file: HTMLFile
    let isFavorite: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.blue.opacity(0.12))
                    .frame(width: 38, height: 38)
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.blue)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(file.name)
                        .font(.body)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.primary)
                    if isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                Text("\(file.sizeText) · \(file.modifiedText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

// MARK: - 粘贴代码（半屏 Sheet）

struct PasteCodeSheet: View {

    @Environment(\.dismiss) private var dismiss

    @State private var fileName: String
    @State private var code: String

    /// 保存回调：(文件名, HTML 代码)
    let onSave: (String, String) -> Void

    init(initialName: String = "未命名.html",
         initialCode: String = "",
         onSave: @escaping (String, String) -> Void) {
        _fileName = State(initialValue: initialName)
        _code = State(initialValue: initialCode)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("文件名") {
                    TextField("例如 index.html", text: $fileName)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                Section {
                    TextEditor(text: $code)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 200)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .overlay(alignment: .topLeading) {
                            if code.isEmpty {
                                Text("把 HTML 代码粘贴到这里…")
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                } header: {
                    Text("HTML 代码")
                } footer: {
                    Text("保存后会写入 App 的本地目录，不会上传到任何服务器。")
                }
            }
            .navigationTitle("粘贴代码")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(fileName, code)
                        dismiss()
                    }
                    .disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
