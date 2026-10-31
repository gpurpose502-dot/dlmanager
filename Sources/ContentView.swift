import SwiftUI

struct ContentView: View {
    @StateObject private var browser = Browser()
    @ObservedObject private var dm = DownloadManager.shared

    var body: some View {
        TabView {
            BrowserScreen(browser: browser)
                .tabItem { Label("Browser", systemImage: "globe") }
            DownloadsScreen(dm: dm)
                .tabItem { Label("Downloads", systemImage: "arrow.down.circle") }
        }
    }
}

struct DownloadsScreen: View {
    @ObservedObject var dm: DownloadManager

    var body: some View {
        NavigationView {
            List(dm.items) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name).lineLimit(1)
                    switch item.status {
                    case .running:
                        ProgressView(value: item.total > 0 ? item.progress : nil)
                        Text(sizeText(item)).font(.caption).foregroundColor(.secondary)
                    case .done:
                        Text("Saved. Open the Files app, On My iPad, DL Manager.")
                            .font(.caption).foregroundColor(.secondary)
                    case .failed(let msg):
                        Text(msg).font(.caption).foregroundColor(.red)
                    }
                }
                .swipeActions {
                    Button("Remove", role: .destructive) { dm.remove(item) }
                    if dm.canRetry(item) {
                        Button("Resume") { dm.retry(item) }.tint(.blue)
                    }
                }
            }
            .overlay { if dm.items.isEmpty { Text("No downloads yet").foregroundColor(.secondary) } }
            .navigationTitle("Downloads")
        }
        .navigationViewStyle(.stack)
    }

    private func sizeText(_ i: DownloadItem) -> String {
        let f = ByteCountFormatter()
        let got = f.string(fromByteCount: i.received)
        return i.total > 0 ? "\(got) of \(f.string(fromByteCount: i.total))" : got
    }
}
