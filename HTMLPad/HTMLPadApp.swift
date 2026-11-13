import SwiftUI

@main
struct HTMLPadApp: App {

    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .onOpenURL { url in
                    model.open(url: url)
                }
        }
    }
}
