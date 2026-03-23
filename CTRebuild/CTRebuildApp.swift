import SwiftUI
import UIKit

@main
struct CTRebuildApp: App {
    init() {
        // Force the window background to match the system background
        // so no black bars appear behind the safe area or during transitions.
        let scenes = UIApplication.shared.connectedScenes
        if let windowScene = scenes.first as? UIWindowScene {
            windowScene.windows.forEach { $0.backgroundColor = .systemBackground }
        }
        // Auto-connect WebSocket if an active URL is already saved
        if !HubClient.shared.activeBaseURL.isEmpty {
            HubClient.shared.connect()
        }
    }

    var body: some Scene {
        WindowGroup {
            DashboardView()
        }
    }
}
