import ServiceManagement
import SwiftUI

struct LaunchAtLoginSettingView: View {
    @State private var isEnabled = false
    @State private var isSynchronizing = false
    @State private var errorMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Launch Murmur at login").font(.system(size: 13, weight: .semibold))
                    Text("Keep voice writing ready after you sign in.")
                        .font(.system(size: 12))
                        .foregroundStyle(MurmurTheme.ColorToken.secondaryInk)
                }
                Spacer()
                Toggle("", isOn: $isEnabled)
                    .labelsHidden()
                    .onChange(of: isEnabled) { _, enabled in
                        guard isSynchronizing == false else { return }
                        updateService(enabled: enabled)
                    }
            }
            if errorMessage.isEmpty == false {
                Text(errorMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(MurmurTheme.ColorToken.danger)
            }
        }
        .onAppear { synchronizeFromSystem() }
    }

    private func synchronizeFromSystem() {
        isSynchronizing = true
        isEnabled = SMAppService.mainApp.status == .enabled
        isSynchronizing = false
    }

    private func updateService(enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            errorMessage = ""
        } catch {
            errorMessage = error.localizedDescription
        }
        synchronizeFromSystem()
    }
}
