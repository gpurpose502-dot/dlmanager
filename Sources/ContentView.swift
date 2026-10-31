import SwiftUI

enum AppTab: Hashable { case downloads, browser, history, settings }

struct NavItem: Identifiable {
    let tab: AppTab
    let title: String
    let symbol: String
    var id: AppTab { tab }
}

struct ContentView: View {
    @StateObject private var browser = Browser()
    @AppStorage("themeMode") private var themeMode = 0
    @State private var tab: AppTab = .downloads

    private var forcedScheme: ColorScheme? {
        themeMode == 1 ? .light : (themeMode == 2 ? .dark : nil)
    }

    var body: some View {
        ZStack {
            GridBackground()
            DownloadsView(tab: $tab, browser: browser).tabLayer(.downloads, tab)
            BrowserView(browser: browser, tab: $tab).tabLayer(.browser, tab)
            HistoryView().tabLayer(.history, tab)
            SettingsView().tabLayer(.settings, tab)
            VStack {
                Spacer()
                FloatingNav(tab: $tab)
            }
        }
        .preferredColorScheme(forcedScheme)
    }
}

extension View {
    func tabLayer(_ me: AppTab, _ current: AppTab) -> some View {
        self
            .opacity(me == current ? 1 : 0)
            .scaleEffect(me == current ? 1 : 0.97)
            .allowsHitTesting(me == current)
            .accessibilityHidden(me != current)
            .animation(.easeInOut(duration: 0.25), value: current)
    }
}

struct FloatingNav: View {
    @Binding var tab: AppTab
    @ObservedObject private var dm = DownloadManager.shared
    @Namespace private var ns

    private let items = [
        NavItem(tab: .downloads, title: "Downloads", symbol: "arrow.down.circle.fill"),
        NavItem(tab: .browser, title: "Browser", symbol: "globe"),
        NavItem(tab: .history, title: "History", symbol: "clock.fill"),
        NavItem(tab: .settings, title: "Settings", symbol: "slider.horizontal.3"),
    ]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items) { item in
                Button {
                    Haptic.tap()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { tab = item.tab }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 20, weight: .semibold))
                            .overlay(alignment: .topTrailing) {
                                if item.tab == .downloads && dm.runningCount > 0 {
                                    Text("\(dm.runningCount)")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 5)
                                        .background(Capsule().fill(Theme.brand))
                                        .offset(x: 10, y: -6)
                                        .transition(.scale)
                                }
                            }
                        Text(item.title).font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(tab == item.tab ? Theme.accent : Theme.text)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background {
                        if tab == item.tab {
                            Capsule().fill(Theme.highlight).matchedGeometryEffect(id: "highlight", in: ns)
                        }
                    }
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel(item.title)
            }
        }
        .padding(6)
        .frame(height: 72)
        .background(Capsule().fill(Theme.button))
        .shadow(color: Color.black.opacity(0.12), radius: 16, x: 0, y: 6)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: dm.runningCount)
    }
}
