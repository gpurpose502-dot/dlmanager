import SwiftUI

struct SettingsView: View {
    @AppStorage("themeMode") private var themeMode = 0
    @AppStorage("wifiOnly") private var wifiOnly = false
    @AppStorage("notify") private var notify = true
    @AppStorage("haptics") private var haptics = true
    @ObservedObject private var dm = DownloadManager.shared
    @State private var confirmClear = false

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                PageTitle("Settings")

                SectionLabel("Appearance").padding(.top, 10)
                Picker("Appearance", selection: $themeMode.animation(.easeInOut(duration: 0.3))) {
                    Text("System").tag(0)
                    Text("Light").tag(1)
                    Text("Dark").tag(2)
                }
                .pickerStyle(.segmented)

                SectionLabel("Downloads").padding(.top, 10)
                VStack(spacing: 0) {
                    toggleRow("Wi-Fi only", "Don't use mobile data", $wifiOnly)
                    Divider().background(Theme.border)
                    toggleRow("Notifications", "When a download finishes", $notify)
                    Divider().background(Theme.border)
                    toggleRow("Haptics", "Subtle taps and buzzes", $haptics)
                }
                .padding(.horizontal, 14)
                .card()

                SectionLabel("Storage").padding(.top, 10)
                VStack(spacing: 0) {
                    infoRow("Downloaded files", Fmt.bytes(dm.storageUsed))
                    Divider().background(Theme.border)
                    infoRow("Finished downloads", "\(dm.completed.count)")
                    Divider().background(Theme.border)
                    Button { Haptic.tap(); confirmClear = true } label: {
                        HStack {
                            Text("Clear history").font(.mono(14, .semibold)).foregroundColor(Theme.accent)
                            Spacer()
                        }
                        .frame(height: 52)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                }
                .padding(.horizontal, 14)
                .card()

                SectionLabel("About").padding(.top, 10)
                VStack(spacing: 0) {
                    infoRow("Version", version)
                    Divider().background(Theme.border)
                    infoRow("Saved to", "Files › DL Manager")
                }
                .padding(.horizontal, 14)
                .card()
            }
            .padding(.horizontal, 20)
            .padding(.top, 60)
            .padding(.bottom, 130)
        }
        .confirmationDialog("Clear history?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear list (keep files)", role: .destructive) {
                withAnimation { dm.clearHistory(deleteFiles: false) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func toggleRow(_ title: String, _ sub: String, _ value: Binding<Bool>) -> some View {
        Toggle(isOn: value) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.mono(14, .semibold)).foregroundColor(Theme.text)
                Text(sub).font(.mono(12)).foregroundColor(Theme.sub)
            }
        }
        .tint(Theme.brand)
        .frame(minHeight: 58)
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(.mono(14)).foregroundColor(Theme.text)
            Spacer()
            Text(value).font(.mono(13)).foregroundColor(Theme.sub)
        }
        .frame(height: 52)
    }
}
