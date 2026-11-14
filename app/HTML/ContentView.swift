//
//  ContentView.swift
//  HTML — 本地 HTML 查看器
//
//  三个 Tab：我的 HTML / 收藏夹 / 设置。外观主题（跟随系统 / 浅色 / 深色）在这里统一生效。
//

import SwiftUI

// MARK: - 外观主题

enum AppearanceMode: Int, CaseIterable, Identifiable {
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

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

// MARK: - 根视图

struct ContentView: View {

    @EnvironmentObject private var fileManager: FileManagerModel
    @AppStorage("appearance") private var appearanceRaw = AppearanceMode.system.rawValue

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("我的 HTML", systemImage: "doc.on.doc") }

            FavoritesView()
                .tabItem { Label("收藏夹", systemImage: "star") }

            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape") }
        }
        .tint(.blue)
        .preferredColorScheme(AppearanceMode(rawValue: appearanceRaw)?.colorScheme)
    }
}

// MARK: - 收藏夹

struct FavoritesView: View {

    @EnvironmentObject private var fileManager: FileManagerModel
    @State private var previewFile: HTMLFile?
    @State private var pendingDelete: HTMLFile?

    var body: some View {
        NavigationStack {
            Group {
                if fileManager.favoriteFiles.isEmpty {
                    EmptyStateView(
                        symbol: "star",
                        title: "还没有收藏",
                        message: "在预览页右上角「⋯」里点「添加到收藏」，文件就会出现在这里。"
                    )
                } else {
                    List {
                        ForEach(fileManager.favoriteFiles) { file in
                            Button {
                                previewFile = file
                            } label: {
                                FileRow(file: file, isFavorite: true)
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
                                    Label("取消收藏", systemImage: "star.slash")
                                }
                                .tint(.orange)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("收藏夹")
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
}

// MARK: - 空状态占位

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
