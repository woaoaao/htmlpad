import SwiftUI

/// 「另存为」：把当前编辑内容写进 App 自己的 Documents 目录，
/// 该目录在「文件」App → 我的 iPhone → HTML 编辑 里可见。
struct SaveAsSheet: View {

    @Binding var name: String
    var onSave: () -> Void
    var onCancel: () -> Void

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                Text("保存位置：「文件」App → 我的 iPhone → HTML 编辑")
                    .font(.footnote)
                    .foregroundColor(.secondary)

                TextField("文件名", text: $name)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .autocapitalization(.none)
                    .disableAutocorrection(true)

                Spacer()
            }
            .padding(20)
            .navigationTitle("另存为")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: onSave)
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}
