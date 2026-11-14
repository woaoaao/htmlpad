//
//  FileManagerModel.swift
//  HTML — 本地 HTML 查看器
//
//  负责：沙盒目录（Documents/HTML）、文件列表（名称 / 大小 / 修改时间）、收藏夹持久化、
//  导入文件 / 文件夹、粘贴新建、删除、清空。
//  全部本地，不联网。
//

import Foundation
import CoreFoundation
import SwiftUI

// MARK: - 列表单元

struct HTMLFile: Identifiable, Hashable {
    let url: URL
    let size: Int64
    let modified: Date
    let favorite: Bool

    /// SwiftUI 列表需要一个稳定 ID，用绝对路径即可
    var id: String { url.path }

    var name: String { url.lastPathComponent }
    /// 去掉扩展名后的标题，给导航栏用
    var title: String { url.deletingPathExtension().lastPathComponent }

    var sizeText: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    var modifiedText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: modified)
    }
}

// MARK: - 通知

extension Notification.Name {
    /// 源码页保存成功后发出，预览页收到后自动重新加载
    static let htmlFileSaved = Notification.Name("HTML.fileSaved")
}

// MARK: - 模型

@MainActor
final class FileManagerModel: ObservableObject {

    /// 沙盒内的根目录：Documents/HTML
    let rootURL: URL

    @Published private(set) var files: [HTMLFile] = []
    /// 收藏夹（存相对路径，App 重装/容器路径变化也不丢）
    @Published private(set) var favorites: [String] = []
    /// 一次性错误提示
    @Published var lastError: String?

    private let favoritesKey = "html.favorites.v1"
    private let fileManager = FileManager.default

    static let supportedExtensions: Set<String> = [
        "html", "htm", "xhtml", "shtml", "css", "js", "mjs",
        "json", "txt", "md", "markdown", "xml", "svg"
    ]

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        rootURL = documents.appendingPathComponent("HTML", isDirectory: true)
        try? FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        if let stored = UserDefaults.standard.array(forKey: favoritesKey) as? [String] {
            favorites = stored
        }
        refresh()
    }

    // MARK: - 刷新列表

    func refresh() {
        var result: [HTMLFile] = []
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]

        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            files = []
            return
        }

        for case let url as URL in enumerator {
            guard Self.supportedExtensions.contains(url.pathExtension.lowercased()) else { continue }
            let values = try? url.resourceValues(forKeys: keys)
            guard values?.isRegularFile ?? true else { continue }

            result.append(HTMLFile(
                url: url,
                size: Int64(values?.fileSize ?? 0),
                modified: values?.contentModificationDate ?? .distantPast,
                favorite: favorites.contains(relativePath(of: url))
            ))
        }

        files = result.sorted { $0.modified > $1.modified }
    }

    // MARK: - 路径换算

    func relativePath(of url: URL) -> String {
        let root = rootURL.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(root) else { return path }
        var relative = String(path.dropFirst(root.count))
        if relative.hasPrefix("/") { relative.removeFirst() }
        return relative
    }

    func url(forRelativePath relative: String) -> URL {
        rootURL.appendingPathComponent(relative)
    }

    // MARK: - 导入

    /// 从「文件」App 选中的单个文件拷贝进沙盒
    func importFile(from picked: URL) {
        let scoped = picked.startAccessingSecurityScopedResource()
        defer { if scoped { picked.stopAccessingSecurityScopedResource() } }

        do {
            let target = uniqueURL(for: picked.lastPathComponent)
            try fileManager.copyItem(at: picked, to: target)
            refresh()
        } catch {
            lastError = "导入失败：\(error.localizedDescription)"
        }
    }

    /// 拷贝整个文件夹（保留内部相对结构，css / js / 图片都能一起进来）
    func importFolder(from picked: URL) {
        let scoped = picked.startAccessingSecurityScopedResource()
        defer { if scoped { picked.stopAccessingSecurityScopedResource() } }

        do {
            let name = picked.lastPathComponent.isEmpty ? "文件夹" : picked.lastPathComponent
            let target = uniqueURL(for: name, isDirectory: true)
            try fileManager.copyItem(at: picked, to: target)
            refresh()
        } catch {
            lastError = "导入文件夹失败：\(error.localizedDescription)"
        }
    }

    /// 生成的唯一目标路径（重名自动加 -2、-3…）
    private func uniqueURL(for name: String, isDirectory: Bool = false) -> URL {
        var candidate = rootURL.appendingPathComponent(name, isDirectory: isDirectory)
        guard fileManager.fileExists(atPath: candidate.path) else { return candidate }

        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var index = 2
        while fileManager.fileExists(atPath: candidate.path) {
            let newName = ext.isEmpty ? "\(base)-\(index)" : "\(base)-\(index).\(ext)"
            candidate = rootURL.appendingPathComponent(newName, isDirectory: isDirectory)
            index += 1
        }
        return candidate
    }

    // MARK: - 新建 / 删除

    @discardableResult
    func createFile(named rawName: String, content: String) -> URL? {
        var name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { name = "未命名.html" }
        if (name as NSString).pathExtension.isEmpty { name += ".html" }

        let target = uniqueURL(for: name)
        do {
            try content.write(to: target, atomically: true, encoding: .utf8)
            refresh()
            return target
        } catch {
            lastError = "保存失败：\(error.localizedDescription)"
            return nil
        }
    }

    func delete(_ file: HTMLFile) {
        do {
            try fileManager.removeItem(at: file.url)
            let relative = relativePath(of: file.url)
            favorites.removeAll { $0 == relative || $0.hasPrefix(relative + "/") }
            persistFavorites()
            refresh()
        } catch {
            lastError = "删除失败：\(error.localizedDescription)"
        }
    }

    // MARK: - 收藏夹

    func isFavorite(_ file: HTMLFile) -> Bool {
        favorites.contains(relativePath(of: file.url))
    }

    func toggleFavorite(_ file: HTMLFile) {
        let relative = relativePath(of: file.url)
        if let index = favorites.firstIndex(of: relative) {
            favorites.remove(at: index)
        } else {
            favorites.append(relative)
        }
        persistFavorites()
        refresh()
    }

    var favoriteFiles: [HTMLFile] {
        files.filter { isFavorite($0) }
    }

    private func persistFavorites() {
        UserDefaults.standard.set(favorites, forKey: favoritesKey)
    }

    // MARK: - 存储信息 / 清空

    var totalSize: Int64 {
        files.reduce(0) { $0 + $1.size }
    }

    var totalSizeText: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }

    func clearAll() {
        let contents = (try? fileManager.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil)) ?? []
        for url in contents {
            try? fileManager.removeItem(at: url)
        }
        favorites.removeAll()
        persistFavorites()
        refresh()
    }

    // MARK: - 读取源码文本（兼容 GB18030 等中文老编码）

    static func readText(at url: URL) -> String {
        guard let data = try? Data(contentsOf: url) else { return "" }
        if data.isEmpty { return "" }
        if let text = String(data: data, encoding: .utf8) { return text }

        let gb = CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        )
        if let text = String(data: data, encoding: String.Encoding(rawValue: gb)) { return text }
        if let text = String(data: data, encoding: .utf16) { return text }
        if let text = String(data: data, encoding: .isoLatin1) { return text }
        return String(decoding: data, as: UTF8.self)
    }
}
