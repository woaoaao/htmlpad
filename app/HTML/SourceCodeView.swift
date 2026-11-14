//
//  SourceCodeView.swift
//  HTML — 本地 HTML 查看器
//
//  可编辑的源码页：UITextView 编辑器 + 顶部查找条（上一处 / 下一处 / 命中计数）+ 保存回原文件。
//

import SwiftUI
import Combine

/// 让 SwiftUI 能把光标移到某个匹配位置
@MainActor
final class CodeEditorStore: ObservableObject {
    weak var textView: UITextView?

    func focus() {
        textView?.becomeFirstResponder()
    }

    func jump(to range: NSRange) {
        guard let textView else { return }
        textView.becomeFirstResponder()
        textView.selectedRange = range
        textView.scrollRangeToVisible(range)
    }
}

/// UIKit 编辑器封装（SwiftUI 的 TextEditor 拿不到选区，做不了“跳到下一处”）
struct CodeEditor: UIViewRepresentable {

    @Binding var text: String
    @ObservedObject var store: CodeEditorStore
    var onChange: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.spellCheckingType = .no
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.smartInsertDeleteType = .no
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 28, right: 8)
        textView.backgroundColor = .clear
        textView.text = text
        store.textView = textView
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.parent = self
        if textView.text != text {
            textView.text = text
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: CodeEditor

        init(_ parent: CodeEditor) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            parent.onChange()
        }
    }
}

struct SourceCodeView: View {

    let file: HTMLFile

    @EnvironmentObject private var fileManager: FileManagerModel
    @StateObject private var store = CodeEditorStore()

    @State private var text = ""
    @State private var dirty = false
    @State private var toast: String?

    @State private var showFindBar = false
    @State private var keyword = ""
    @State private var matches: [NSRange] = []
    @State private var currentIndex = 0

    var body: some View {
        VStack(spacing: 0) {
            if showFindBar {
                findBar
                Divider()
            }

            CodeEditor(text: $text, store: store) {
                if !dirty { dirty = true }
            }
        }
        .navigationTitle(dirty ? "源代码 ●" : "源代码")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    save()
                } label: {
                    Text("保存").fontWeight(.semibold)
                }
                .disabled(!dirty)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showFindBar.toggle()
                    }
                    if showFindBar {
                        store.focus()
                    } else {
                        clearFind()
                    }
                } label: {
                    Image(systemName: "magnifyingglass")
                }
            }
        }
        .overlay(alignment: .bottom) { toastView }
        .task(id: file.url) {
            text = FileManagerModel.readText(at: file.url)
            dirty = false
        }
        .onDisappear {
            if dirty {
                save()
            }
        }
    }

    // MARK: - 查找条

    private var findBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.footnote)
                .foregroundStyle(.secondary)

            TextField("在代码里查找", text: $keyword)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .onSubmit { jump(by: 1) }
                .onChange(of: keyword) { _ in updateMatches() }

            Text(countText)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 52)

            Button { jump(by: -1) } label: {
                Image(systemName: "chevron.up")
            }
            .disabled(matches.isEmpty)

            Button { jump(by: 1) } label: {
                Image(systemName: "chevron.down")
            }
            .disabled(matches.isEmpty)

            Button {
                withAnimation(.easeInOut(duration: 0.15)) { showFindBar = false }
                clearFind()
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(uiColor: .secondarySystemBackground))
    }

    private var countText: String {
        guard !matches.isEmpty else { return keyword.isEmpty ? "" : "0" }
        return "\(currentIndex + 1)/\(matches.count)"
    }

    private var toastView: some View {
        Group {
            if let toast {
                Text(toast)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.75), in: Capsule())
                    .padding(.bottom, 28)
                    .transition(.opacity)
            }
        }
    }

    // MARK: - 查找实现

    private func updateMatches() {
        let needle = keyword
        guard !needle.isEmpty else {
            matches = []
            currentIndex = 0
            return
        }

        let source = text as NSString
        var found: [NSRange] = []
        var searchRange = NSRange(location: 0, length: source.length)

        while searchRange.location < source.length {
            let result = source.range(of: needle, options: .caseInsensitive, range: searchRange)
            if result.location == NSNotFound { break }
            found.append(result)
            let next = result.location + result.length
            if next >= source.length { break }
            searchRange = NSRange(location: next, length: source.length - next)
        }

        matches = found
        currentIndex = 0
        if let first = found.first {
            store.jump(to: first)
        }
    }

    private func jump(by offset: Int) {
        guard !matches.isEmpty else { return }
        let count = matches.count
        currentIndex = ((currentIndex + offset) % count + count) % count
        store.jump(to: matches[currentIndex])
    }

    private func clearFind() {
        keyword = ""
        matches = []
        currentIndex = 0
    }

    // MARK: - 保存

    private func save() {
        do {
            try text.write(to: file.url, atomically: true, encoding: .utf8)
            dirty = false
            fileManager.refresh()
            NotificationCenter.default.post(name: .htmlFileSaved, object: nil)
            flash("已保存")
        } catch {
            flash("保存失败")
        }
    }

    private func flash(_ message: String) {
        withAnimation { toast = message }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            withAnimation { toast = nil }
        }
    }
}
