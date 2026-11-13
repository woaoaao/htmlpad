import SwiftUI
import UniformTypeIdentifiers

/// 调用系统「文件」选择器打开一个文件（in-place，可直接保存回原文件）。
struct DocumentPicker: UIViewControllerRepresentable {

    @Binding var isPresented: Bool
    var onPick: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        var types: [UTType] = [.html, .plainText]
        let extensions = ["html", "htm", "xhtml", "shtml", "css", "js", "mjs", "json",
                          "txt", "md", "markdown", "xml", "svg", "vue", "php"]
        for ext in extensions {
            if let type = UTType(filenameExtension: ext) {
                types.append(type)
            }
        }

        var seen = Set<String>()
        let uniqueTypes = types.filter { seen.insert($0.identifier).inserted }

        let picker = UIDocumentPickerViewController(forOpeningContentTypes: uniqueTypes, asCopy: false)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {

        private let parent: DocumentPicker

        init(_ parent: DocumentPicker) {
            self.parent = parent
        }

        func documentPicker(_ controller: UIDocumentPickerViewController,
                            didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else {
                parent.isPresented = false
                return
            }
            parent.isPresented = false
            parent.onPick(url)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.isPresented = false
        }
    }
}
