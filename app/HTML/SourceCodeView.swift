//
//  SourceCodeView.swift
//  HTML — 本地 HTML 查看器
//
//  只读查看 HTML 源码，支持 .searchable 搜索并高亮命中的文本。
//

import SwiftUI

struct SourceCodeView: View {

    let file: HTMLFile

    @State private var code = ""
    @State private var keyword = ""

    /// 大文件不做高亮，避免卡顿
    private let highlightLimit = 300_000

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            Text(displayText)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
        }
        .background(Color(uiColor: .systemBackground))
        .navigationTitle("源代码")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $keyword, prompt: "搜索代码")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: file.url) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .task(id: file.url) {
            code = FileManagerModel.readText(at: file.url)
        }
    }

    // MARK: - 带高亮的文本

    private var displayText: AttributedString {
        var attributed = AttributedString(code)
        attributed.font = .system(size: 12, design: .monospaced)

        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, code.count <= highlightLimit else {
            return attributed
        }

        var searchStart = attributed.startIndex
        while searchStart < attributed.endIndex,
              let range = attributed[searchStart...].range(of: trimmed, options: .caseInsensitive) {
            attributed[range].backgroundColor = Color.yellow.opacity(0.35)
            attributed[range].foregroundColor = .primary
            if range.upperBound >= attributed.endIndex { break }
            searchStart = range.upperBound
        }
        return attributed
    }
}
