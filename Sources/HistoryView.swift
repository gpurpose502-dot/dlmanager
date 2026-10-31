import SwiftUI

struct DayGroup: Identifiable {
    let day: Date
    let items: [DownloadRecord]
    var id: Date { day }
}

struct HistoryView: View {
    @ObservedObject private var dm = DownloadManager.shared
    @State private var confirmClear = false
    @State private var preview: PreviewItem?

    private var groups: [DayGroup] {
        let g = Dictionary(grouping: dm.completed) { Calendar.current.startOfDay(for: $0.finishedAt ?? $0.addedAt) }
        return g.keys.sorted(by: >).map { DayGroup(day: $0, items: g[$0] ?? []) }
    }

    private func label(_ d: Date) -> String {
        if Calendar.current.isDateInToday(d) { return "Today" }
        if Calendar.current.isDateInYesterday(d) { return "Yesterday" }
        return d.formatted(date: .abbreviated, time: .omitted)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button { Haptic.tap(); confirmClear = true } label: {
                    CircleIcon(symbol: "trash", tint: dm.completed.isEmpty ? Theme.sub.opacity(0.5) : Theme.accent)
                }
                .buttonStyle(PressStyle())
                .disabled(dm.completed.isEmpty)
                .accessibilityLabel("Clear history")
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            List {
                PageTitle("History").plainRow(top: 8, bottom: 4)
                if groups.isEmpty {
                    EmptyState(symbol: "clock", title: "No history yet",
                               hint: "Finished downloads show up here.").plainRow()
                }
                ForEach(groups) { group in
                    SectionLabel(label(group.day)).plainRow(top: 14, bottom: 2)
                    ForEach(group.items) { r in
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
            .animation(.spring(response: 0.42, dampingFraction: 0.86), value: dm.completed.map { $0.id })
        }
        .confirmationDialog("Clear history?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear list (keep files)", role: .destructive) {
                withAnimation { dm.clearHistory(deleteFiles: false) }
            }
            Button("Clear list and delete files", role: .destructive) {
                withAnimation { dm.clearHistory(deleteFiles: true) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: $preview) { QuickLookView(url: $0.url).ignoresSafeArea() }
    }
}
