import SwiftUI

@MainActor
struct ImageQueueView: View {
    let store: ImportStore

    var body: some View {
        Group {
            if store.items.isEmpty {
                emptyState
            } else {
                queue
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay {
            if store.isDropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.tint, style: StrokeStyle(lineWidth: 3, dash: [8]))
                    .padding(12)
                    .allowsHitTesting(false)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            statusBar
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("import.empty_title", systemImage: "photo.on.rectangle.angled")
        } description: {
            Text("import.empty_description")
        } actions: {
            HStack {
                Button("import.choose_files") {
                    store.chooseFiles()
                }
                Button("import.choose_folder") {
                    store.chooseFolders()
                }
            }
        }
    }

    private var queue: some View {
        Table(store.items, selection: Bindable(store).selection) {
            TableColumn("queue.image") { item in
                HStack(spacing: 10) {
                    thumbnail(for: item)
                    Text(item.filename)
                        .lineLimit(1)
                        .help(item.sourceURL.path)
                }
            }
            .width(min: 220, ideal: 320)

            TableColumn("queue.dimensions") { item in
                Text("\(item.pixelSize.width) × \(item.pixelSize.height)")
                    .monospacedDigit()
            }
            .width(110)

            TableColumn("queue.format") { item in
                Text(item.formatName)
            }
            .width(70)
        }
        .contextMenu(forSelectionType: ImageItem.ID.self) { selection in
            Button("queue.remove", role: .destructive) {
                store.selection = selection
                store.removeSelection()
            }
        }
        .overlay {
            if store.isImporting {
                ProgressView("import.loading")
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    @ViewBuilder
    private func thumbnail(for item: ImageItem) -> some View {
        if let image = item.thumbnail {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 44)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
        } else {
            Image(systemName: "photo")
                .frame(width: 44, height: 44)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
        }
    }

    private var statusBar: some View {
        HStack {
            Text("\(store.items.count) \(String(localized: "queue.valid_count"))")
            if store.ignoredCount > 0 {
                Text("·")
                Text("\(store.ignoredCount) \(String(localized: "queue.ignored_count"))")
            }
            Spacer()
            Button("queue.remove") {
                store.removeSelection()
            }
            .disabled(store.selection.isEmpty)

            Button("queue.clear") {
                store.removeAll()
            }
            .disabled(store.items.isEmpty)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(.bar)
    }
}
