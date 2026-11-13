import Foundation
import CoreFoundation

enum FileIOError: LocalizedError {
    case undecodable(String)
    case unencodable(String)

    var errorDescription: String? {
        switch self {
        case .undecodable(let name):
            return "无法识别 \(name) 的文本编码"
        case .unencodable(let name):
            return "无法把内容写成文本（\(name)）"
        }
    }
}

/// 统一的文件读写：自动处理安全作用域（Files / iCloud 里的文件必须成对使用
/// startAccessingSecurityScopedResource / stopAccessingSecurityScopedResource），
/// 并在读取时对编码做多种尝试（UTF-8 / GB18030 / UTF-16 / Latin-1）。
enum FileIO {

    static func readText(at url: URL) throws -> String {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: url)
        if data.isEmpty { return "" }

        if let text = String(data: data, encoding: .utf8) { return text }
        if let text = String(data: data, encoding: gb18030) { return text }
        if let text = String(data: data, encoding: .utf16) { return text }
        if let text = String(data: data, encoding: .isoLatin1) { return text }

        throw FileIOError.undecodable(url.lastPathComponent)
    }

    static func write(_ text: String, to url: URL) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let data = text.data(using: .utf8) else {
            throw FileIOError.unencodable(url.lastPathComponent)
        }

        do {
            try data.write(to: url, options: .atomic)
        } catch {
            // 部分第三方文件提供者不支持“原子写入”，退回直接覆盖写入。
            try data.write(to: url, options: [])
        }
    }

    static var gb18030: String.Encoding {
        let cfEncoding = CFStringEncodings.GB_18030_2000
        let nsEncoding = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(cfEncoding.rawValue))
        return String.Encoding(rawValue: nsEncoding)
    }
}
