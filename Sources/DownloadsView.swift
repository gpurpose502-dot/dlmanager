import SwiftUI
import QuickLook

struct PreviewItem: Identifiable {
    let url: URL
    var id: URL { url }
}

struct QuickLookView: UIViewControllerRepresentable {
    let url: URL
    func makeCoordinator() -> Coordinator { Coordinator(url) }
    func makeUIViewController(context: Context) -> QLPreviewController {
        let c = QLPreviewController()
        c.dataSource = context.coordinator
        return c
    }
    func updateUIViewController(_ vc: QLPreviewController, context: Context) {}

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(_ url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}

struct DownloadsView: View {
    @Binding var tab: AppTab
    @ObservedObject var browser: Browser
    @ObservedObject private var dm = DownloadManager.shared
    @AppStorage("themeMode") private var themeMode = 0
    @Environment(\.colorScheme) private var scheme
    @State private var link = ""
    @State private var shakes: CGFloat = 0
    @State private var preview: PreviewItem?
    @State private var checking = false
    @FocusState private var focused: Bool

    private var todays: [DownloadRecord] {
        dm.completed.filter { Calendar.current.isDateInToday($0.finishedAt ?? .distantPast) }
    }
    private var changeKey: [String] { dm.records.map { $0.id.uuidString + $0.status.rawValue } }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    Haptic.tap()
                    withAnimation(.easeInOut(duration: 0.3)) { themeMode = (scheme == .dark) ? 1 : 2 }
                } label: {
                    CircleIcon(symbol: scheme == .dark ? "sun.max.fill" : "moon.fill")
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel(scheme == .dark ? "Switch to light mode" : "Switch to dark mode")
                Spacer()
                Button { pasteFromClipboard() } label: {
                    CircleIcon(symbol: "plus", tint: Theme.accent)
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Paste a link")
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            List {
                PageTitle("Downloads").plainRow(top: 8, bottom: 4)
                pasteRow.plainRow(top: 10, bottom: 6)

                if dm.active.isEmpty && todays.isEmpty {
                    EmptyState(symbol: "arrow.down.circle", title: "No downloads yet",
                               hint: "Paste a link above, or open the\nBrowser tab to find a file.")
                        .plainRow()
                }

                if !dm.active.isEmpty {
                    HStack {
                        SectionLabel("Active · \(dm.active.count)")
                        Spacer()
                        Button {
                            Haptic.tap()
                            if dm.runningCount > 0 { dm.pauseAll() } else { dm.resumeAll() }
                        } label: {
                            Text(dm.runningCount > 0 ? "Pause all" : "Resume all")
                                .font(.mono(12, .semibold))
                                .foregroundColor(Theme.accent)
                                .frame(minHeight: 32)
                        }
                        .buttonStyle(PressStyle())
                    }
                    .plainRow(top: 14, bottom: 2)

                    ForEach(dm.active) { r in
                        DownloadCard(r: r)
                            .plainRow()
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) { dm.cancel(r.id) } label: {
                                    Label("Cancel", systemImage: "xmark")
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button { dm.toggle(r.id) } label: {
                                    Label(r.status == .running ? "Pause" : "Resume",
                                          systemImage: r.status == .running ? "pause.fill" : "play.fill")
                                }
                                .tint(Theme.brand)
                            }
                            .contextMenu {
                                Button { dm.toggle(r.id) } label: {
                                    Label(r.status == .running ? "Pause" : "Resume",
                                          systemImage: r.status == .running ? "pause.fill" : "play.fill")
                                }
                                Button { UIPasteboard.general.string = r.url } label: {
                                    Label("Copy link", systemImage: "link")
                                }
                                Button(role: .destructive) { dm.cancel(r.id) } label: {
                                    Label("Cancel download", systemImage: "xmark")
                                }
                            }
                    }

                    Text("Tap to pause · Swipe to delete · Hold for options")
                        .font(.mono(12))
                        .foregroundColor(Theme.sub)
                        .plainRow(top: 6, bottom: 6)
                }

                if !todays.isEmpty {
                    SectionLabel("Completed today").plainRow(top: 16, bottom: 2)
                    ForEach(todays) { r in
                        CompletedRow(r: r) { preview = PreviewItem(url: $0) }
                            .plainRow()
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) { dm.delete(r.id, withFile: false) } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                    }
                }

                Color.clear.frame(height: 110).plainRow()
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .animation(.spring(response: 0.42, dampingFraction: 0.86), value: changeKey)
        }
        .sheet(item: $preview) { QuickLookView(url: $0.url).ignoresSafeArea() }
    }

    @ViewBuilder private var pasteRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "link").foregroundColor(Theme.sub)
            TextField("Paste a link to download", text: $link)
                .font(.mono(14))
                .foregroundColor(Theme.text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .submitLabel(.go)
                .focused($focused)
                .onSubmit(addLink)
            Button(action: addLink) {
                Text(checking ? "Checking…" : "Download")
                    .font(.mono(13, .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .frame(height: 44)
                    .background(Capsule().fill(Theme.brand))
            }
            .buttonStyle(PressStyle())
        }
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .frame(height: 56)
        .card()
        .modifier(Shake(shakes: shakes))
    }

    private func addLink() {
        var t = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !checking else { return }
        if !t.contains("://") { t = "https://" + t }
        guard let url = URL(string: t), let host = url.host, !host.isEmpty,
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            withAnimation(.linear(duration: 0.4)) { shakes += 1 }
            Haptic.warn()
            return
        }
        checking = true
        focused = false
        Task { @MainActor in
            let kind = await LinkProbe.check(url)
            checking = false
            switch kind {
            case .file:
                dm.add(urlString: url.absoluteString)
                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { link = "" }
                Haptic.success()
            case .page, .unreachable:
                // Not a direct file: open it in the browser so the user can click through.
                browser.load(url.absoluteString)
                browser.flash("Opened as a web page")
                link = ""
                Haptic.tap()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { tab = .browser }
            }
        }
    }

    private func pasteFromClipboard() {
        Haptic.tap()
        if let s = UIPasteboard.general.string, s.contains(".") {
            link = s.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        focused = true
    }
}

struct DownloadCard: View {
    let r: DownloadRecord
    private var running: Bool { r.status == .running }

    private var subtitle: String {
        if r.status == .failed { return r.error ?? "Failed" }
        if r.total > 0 { return "\(Fmt.bytes(r.received)) of \(Fmt.bytes(r.total))" }
        return r.received > 0 ? Fmt.bytes(r.received) : "Starting…"
    }

    private var percent: String { r.total > 0 ? "\(Int(r.progress * 100))%" : "…" }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                FileTile(symbol: r.status == .failed ? "exclamationmark.triangle.fill" : "doc.fill")
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.name)
                        .font(.mono(14, .semibold))
                        .foregroundColor(Theme.text)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(subtitle)
                        .font(.mono(12))
                        .foregroundColor(Theme.sub)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Button { Haptic.tap(); DownloadManager.shared.toggle(r.id) } label: {
                    CircleIcon(symbol: running ? "pause.fill" : (r.status == .failed ? "arrow.clockwise" : "play.fill"),
                               tint: running ? Theme.text : Theme.accent, filled: false)
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel(running ? "Pause" : (r.status == .failed ? "Retry" : "Resume"))
                Button { Haptic.tap(); DownloadManager.shared.cancel(r.id) } label: {
                    CircleIcon(symbol: "xmark", tint: Theme.sub, filled: false)
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Cancel download")
            }
            ProgressBar(value: r.progress, active: running)
            HStack(spacing: 6) {
                tags
                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .card()
        .contentShape(Rectangle())
        .onTapGesture { Haptic.tap(); DownloadManager.shared.toggle(r.id) }
    }

    @ViewBuilder private var tags: some View {
        switch r.status {
        case .running:
            Tag(text: percent, kind: .red)
            Tag(text: Fmt.speed(r.speed), icon: "bolt.fill", kind: .purple)
            Tag(text: Fmt.eta(r.etaSeconds), icon: "timer", kind: .gray)
        case .paused:
            Tag(text: percent, kind: .gray)
            Tag(text: "Paused", icon: "pause.fill", kind: .gray)
        case .failed:
            Tag(text: "Failed", icon: "exclamationmark.triangle.fill", kind: .red)
            Tag(text: "Tap to retry", kind: .gray)
        case .completed:
            Tag(text: "Done", kind: .green)
        }
    }
}

struct CompletedRow: View {
    let r: DownloadRecord
    var onOpen: (URL) -> Void

    private var timeText: String {
        let d = r.finishedAt ?? r.addedAt
        return d.formatted(date: .omitted, time: .shortened)
    }

    var body: some View {
        let exists = r.fileExists
        HStack(spacing: 10) {
            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(Theme.greenFg)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Theme.greenBg))
            VStack(alignment: .leading, spacing: 2) {
                Text(r.name)
                    .font(.mono(14, .semibold))
                    .foregroundColor(Theme.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(Fmt.bytes(r.total)) · \(timeText)")
                    .font(.mono(12))
                    .foregroundColor(Theme.sub)
            }
            Spacer(minLength: 4)
            Tag(text: exists ? "Done" : "File missing", kind: exists ? .green : .gray)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .card()
        .contentShape(Rectangle())
        .onTapGesture {
            if exists, let u = r.fileURL { Haptic.tap(); onOpen(u) }
        }
        .contextMenu {
            if exists, let u = r.fileURL {
                Button { onOpen(u) } label: { Label("Open", systemImage: "eye") }
                ShareLink(item: u) { Label("Share", systemImage: "square.and.arrow.up") }
            }
            Button { UIPasteboard.general.string = r.url } label: { Label("Copy link", systemImage: "link") }
            Button { DownloadManager.shared.redownload(r) } label: { Label("Download again", systemImage: "arrow.clockwise") }
            Button(role: .destructive) { DownloadManager.shared.delete(r.id, withFile: false) } label: {
                Label("Remove from list", systemImage: "list.bullet.rectangle")
            }
            Button(role: .destructive) { DownloadManager.shared.delete(r.id, withFile: true) } label: {
                Label("Delete file too", systemImage: "trash")
            }
        }
    }
}
