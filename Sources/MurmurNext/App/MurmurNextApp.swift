import AppKit
import SwiftUI

final class MurmurApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }
}

@main
struct MurmurNextApp: App {
    @NSApplicationDelegateAdaptor(MurmurApplicationDelegate.self) private var applicationDelegate
    @StateObject private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup("Murmur", id: "hub") {
            HubRootView(environment: environment)
                .frame(minWidth: 940, minHeight: 620)
                .environmentObject(environment)
                .task {
                    await environment.start()
                }
        }
        .defaultSize(width: 1120, height: 720)
        .windowStyle(.hiddenTitleBar)

        Window("Scratchpad", id: "scratchpad") {
            ScratchpadWindowView(environment: environment)
                .frame(minWidth: 680, minHeight: 480)
                .environmentObject(environment)
        }
        .defaultSize(width: 860, height: 620)

        MenuBarExtra("Murmur", systemImage: "waveform", isInserted: menuBarBinding) {
            MurmurMenuBarView(environment: environment)
        }

        Settings {
            SettingsFeatureView()
                .frame(width: 720, height: 560)
                .environmentObject(environment)
        }
    }

    private var menuBarBinding: Binding<Bool> {
        Binding(
            get: { environment.settings.showMenuBarItem },
            set: { value in environment.updateSettings { $0.showMenuBarItem = value } }
        )
    }
}

private struct MurmurMenuBarView: View {
    @ObservedObject var environment: AppEnvironment
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if environment.dictationOrchestrator.phase == .listening {
            Button("Finish Dictation") {
                Task { await environment.dictationOrchestrator.finish() }
            }
            Button("Cancel Dictation", role: .destructive) {
                Task { await environment.dictationOrchestrator.cancel() }
            }
        } else {
            Button("Start Dictation") { environment.beginDictation(mode: .handsFree) }
            if environment.settings.commandModeEnabled {
                Button("Start Command Mode") { environment.beginDictation(mode: .command) }
            }
        }
        Divider()
        Button("Open Murmur") { openWindow(id: "hub") }
        Button("Open Scratchpad") { openWindow(id: "scratchpad") }
        Divider()
        Button("Quit Murmur") { NSApp.terminate(nil) }
    }
}
