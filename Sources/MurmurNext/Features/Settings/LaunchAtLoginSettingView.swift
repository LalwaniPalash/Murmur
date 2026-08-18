import ServiceManagement
import SwiftUI

struct LaunchAtLoginSettingView: View {
    @State private var isEnabled = false
    @State private var isSynchronizing = false
    @State private var errorMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: MurmurTheme.Space.xSmall) {
            PanelSwitch(legend: "Launch at login", isOn: $isEnabled)
                .onChange(of: isEnabled) { _, enabled in
                    guard isSynchronizing == false else { return }
                    updateService(enabled: enabled)
                }
            if errorMessage.isEmpty == false {
                HStack(spacing: MurmurTheme.Space.small) {
                    Lamp(colour: .caution, isLit: true)
                    Text(errorMessage)
                        .font(MurmurFace.body(11.5))
                        .foregroundStyle(MurmurTheme.Engraving.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.bottom, MurmurTheme.Space.small)
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
