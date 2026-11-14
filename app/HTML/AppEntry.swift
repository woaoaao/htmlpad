//
//  AppEntry.swift
//  HTML — 本地 HTML 查看器
//
//  入口。所有全局状态（沙盒文件系统、收藏夹、WebView 引用）通过 EnvironmentObject 注入，
//  用户在设置里的偏好通过 @AppStorage 全局共享。
//

import SwiftUI

@main
struct HTMLEntryApp: App {

    /// 沙盒文件、收藏夹
    @StateObject private var fileManager = FileManagerModel()
    /// 让工具栏（查找、刷新）能拿到当前 WKWebView
    @StateObject private var webViewStore = WebViewStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(fileManager)
                .environmentObject(webViewStore)
        }
    }
}
