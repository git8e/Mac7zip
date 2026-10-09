import SwiftUI

@main
struct Mac7ZipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        WindowGroup {
            MainWindowView()
                .environmentObject(model)
        }
        .commands {
            AppCommands(model: model)
        }
    }
}
