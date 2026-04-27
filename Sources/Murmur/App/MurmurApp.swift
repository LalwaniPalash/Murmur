import SwiftUI

@main
struct MurmurApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var coordinator = AppCoordinator()

    var body: some Scene {
        WindowGroup("Murmur", id: "hub") {
            HubRootView(coordinator: coordinator)
                .task {
                    coordinator.start()
                }
                .onAppear {
                    coordinator.presentHubWindow()
                }
                .onDisappear {
                    coordinator.hubWindowDidClose()
                }
        }
        .defaultSize(width: 1180, height: 760)
        .defaultLaunchBehavior(.suppressed)

        Window("Scratchpad", id: "scratchpad") {
            ScratchpadWindowView(coordinator: coordinator)
        }
        .defaultSize(width: 920, height: 620)

        MenuBarExtra("Murmur", systemImage: "waveform.and.mic") {
            MenuBarRootView(coordinator: coordinator)
        }

        Settings {
            SettingsSceneView(coordinator: coordinator)
        }
    }
}
