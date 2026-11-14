//
//  SettingsView.swift
//  HTML — 本地 HTML 查看器
//
//  设置页：外观主题 / 安全（网络、JS、外部链接）/ 存储与数据。
//  所有功能默认全开，没有锁、没有 Pro、没有内购。
//

import SwiftUI

struct SettingsView: View {

    @EnvironmentObject private var fileManager: FileManagerModel

    @AppStorage("appearance") private var appearanceRaw = AppearanceMode.system.rawValue
    @AppStorage("allowJS") private var allowJS = true
    @AppStorage("allowNetwork") private var allowNetwork = true
    @AppStorage("openExternalInSafari") private var openExternalInSafari = true

    @State private var showClearConfirm = false

    var body: some View {
        NavigationStack {
            List {
                // MARK: 外观主题
                Section("外观主题") {
                    Picker("外观主题", selection: $appearanceRaw) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.title).tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                // MARK: 安全
                Section {
                    Toggle(isOn: $allowNetwork) {
                        Label("允许网络访问", systemImage: "network")
                    }
                    Toggle(isOn: $allowJS) {
                        Label("启用 JavaScript", systemImage: "curlybraces")
                    }
                    Toggle(isOn: $openExternalInSafari) {
                        Label("外部链接用 Safari 打开", systemImage: "safari")
                    }
                } header: {
                    Text("安全")
                } footer: {
                    Text("关闭网络后，页面里的在线脚本、图片、字体都不会被加载，本地文件不受影响。\n关闭 JavaScript 后需要重新打开页面才会生效。")
                }

                // MARK: 存储与数据
                Section {
                    LabeledContent("文件数量", value: "\(fileManager.files.count)")
                    LabeledContent("占用空间", value: fileManager.totalSizeText)

                    Button(role: .destructive) {
                        showClearConfirm = true
                    } label: {
                        Text("清空数据")
                    }
                    .disabled(fileManager.files.isEmpty)
                } header: {
                    Text("存储与数据")
                } footer: {
                    Text("清空会删除 App 本地目录里的全部 HTML 文件和收藏记录，不可恢复。")
                }

                // MARK: 关于
                Section {
                    LabeledContent("版本", value: appVersion)
                    HStack {
                        Image(systemName: "lock.shield")
                            .foregroundStyle(.green)
                        Text("纯本地运行 · 无广告 · 无内购 · 不收集任何数据")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("关于")
                }
            }
            .navigationTitle("设置")
            .confirmationDialog(
                "确定清空全部本地数据？",
                isPresented: $showClearConfirm,
                titleVisibility: .visible
            ) {
                Button("全部删除", role: .destructive) {
                    fileManager.clearAll()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("所有 HTML 文件和收藏记录都会被删除。")
            }
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
