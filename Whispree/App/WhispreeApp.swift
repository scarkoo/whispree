import SwiftUI

@main
struct WhispreeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            Color.clear
                .frame(width: 0, height: 0)
                .onAppear {
                    DispatchQueue.main.async {
                        NSApp.keyWindow?.close()
                        appDelegate.showMainWindow()
                    }
                }
        }
    }
}
