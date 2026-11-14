//
//  HTMLPreviewView.swift
//  HTML — 本地 HTML 查看器
//
//  核心预览页：NavigationStack + WKWebView + 工具栏（关闭 / 文件名 / 查找 / ⋯ 菜单）。
//

import SwiftUI

struct HTMLPreviewView: View {

    let file: HTMLFile

    @EnvironmentObject private var fileManager: FileManagerModel
    @EnvironmentObject private var webViewStore: WebViewStore
    @Environment(\.dismiss) private var dismiss

    // 全局偏好（设置页里改的那三个开关）
    @AppStorage("allowJS") private var allowJS = true
    @AppStorage("allowNetwork") private var allowNetwork = true
    @AppStorage("openExternalInSafari") private var openExternalInSafari = true

    // 本页临时覆盖（只对当前这次预览生效）
    @State private var networkOverride: Bool?
    @State private var externalOverride: Bool?

    @State private var style: PreviewStyle = .system
    @State private var reloadToken = 0
    @State private var showSource = false

    @State private var showFindBar = false
    @State private var findText = ""
    @State private var findResult = ""

    private var effectiveNetworkAllowed: Bool { networkOverride ?? allowNetwork }
    private var effectiveExternalInSafari: Bool { externalOverride ?? openExternalInSafari }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                WebView(
                    url: file.url,
                    allowNetwork: effectiveNetworkAllowed,
                    allowJS: allowJS,
                    openExternalInSafari: effectiveExternalInSafari,
                    style: style.uiStyle,
                    reloadToken: reloadToken,
                    store: webViewStore
                )
                .ignoresSafeArea(edges: .bottom)

                if showFindBar {
                    findBar
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .navigationDestination(isPresented: $showSource) {
                SourceCodeView(file: file)
            }
        }
    }

    // MARK: - 工具栏

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
            }
            .tint(.blue)
            .accessibilityLabel("关闭")
        }

        ToolbarItem(placement: .principal) {
            Text(file.name)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 220)
        }

        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 14) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showFindBar.toggle()
                    }
                    if !showFindBar {
                        webViewStore.clearFind()
                        findResult = ""
                    }
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .accessibilityLabel("在页面中查找")

                Menu {
                    menuContent
                } label: {
                    Image(systemName: "ellipsis.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                }
                .accessibilityLabel("更多")
            }
            .tint(.blue)
        }
    }

    // MARK: - 「⋯」菜单

    @ViewBuilder
    private var menuContent: some View {
        Button {
            fileManager.toggleFavorite(file)
        } label: {
            Label(
                fileManager.isFavorite(file) ? "取消收藏" : "添加到收藏",
                systemImage: fileManager.isFavorite(file) ? "star.slash" : "star"
            )
        }

        Button {
            showSource = true
        } label: {
            Label("查看源代码", systemImage: "chevron.left.forwardslash.chevron.right")
        }

        Button {
            reloadToken += 1
        } label: {
            Label("重新加载", systemImage: "arrow.clockwise")
        }

        Divider()

        // 显示：切换 WebView 的 overrideUserInterfaceStyle
        Menu {
            ForEach(PreviewStyle.allCases) { item in
                Button {
                    style = item
                } label: {
                    Label(item.title, systemImage: style == item ? "checkmark" : item.symbol)
                }
            }
        } label: {
            Label("显示", systemImage: "circle.lefthalf.filled")
        }

        // 网络访问
        Menu {
            Button {
                networkOverride = true
            } label: {
                Label("允许", systemImage: effectiveNetworkAllowed ? "checkmark" : "wifi")
            }
            Button {
                networkOverride = false
            } label: {
                Label("禁止", systemImage: effectiveNetworkAllowed ? "wifi.slash" : "checkmark")
            }
        } label: {
            Label("网络访问", systemImage: effectiveNetworkAllowed ? "network" : "network.slash")
        }

        // 外部链接
        Menu {
            Button {
                externalOverride = false
            } label: {
                Label("App 内打开", systemImage: effectiveExternalInSafari ? "iphone" : "checkmark")
            }
            Button {
                externalOverride = true
            } label: {
                Label("Safari 中打开", systemImage: effectiveExternalInSafari ? "checkmark" : "safari")
            }
        } label: {
            Label("外部链接", systemImage: "arrow.up.right.square")
        }

        Divider()

        ShareLink(item: file.url) {
            Label("分享文件", systemImage: "square.and.arrow.up")
        }
    }

    // MARK: - 页内查找条

    private var findBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.footnote)
                .foregroundStyle(.secondary)

            TextField("在页面中查找", text: $findText)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .onSubmit { find(forward: true) }
                .onChange(of: findText) { newValue in
                    if newValue.isEmpty {
                        webViewStore.clearFind()
                        findResult = ""
                    }
                }

            if !findResult.isEmpty {
                Text(findResult)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Button {
                find(forward: false)
            } label: {
                Image(systemName: "chevron.up")
            }
            .disabled(findText.isEmpty)

            Button {
                find(forward: true)
            } label: {
                Image(systemName: "chevron.down")
            }
            .disabled(findText.isEmpty)

            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showFindBar = false }
                webViewStore.clearFind()
                findResult = ""
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
    }

    private func find(forward: Bool) {
        let keyword = findText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return }
        webViewStore.find(keyword, forward: forward) { found in
            findResult = found ? (forward ? "↓" : "↑") : "无结果"
        }
    }
}
