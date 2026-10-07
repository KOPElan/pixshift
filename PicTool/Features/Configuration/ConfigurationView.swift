import SwiftUI

@MainActor
struct ConfigurationView: View {
    @Bindable var configuration: BatchConfiguration
    let batchProcessor: BatchProcessorStore
    let items: [ImageItem]

    @State private var cropEditor: CropEditorPresentation?

    var body: some View {
        Form {
            if batchProcessor.phase != .idle {
                batchStatus
            }

            Section("resize.section") {
                Picker("resize.mode", selection: $configuration.mode) {
                    ForEach(BatchConfiguration.Mode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }

                valueFields

                Toggle("resize.allow_upscaling", isOn: $configuration.allowsUpscaling)

                if configuration.allowsUpscaling {
                    Label("resize.upscaling_warning", systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if configuration.mode == .exact {
                    Text("resize.exact_help")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(batchProcessor.phase.isActive)

            Section("crop.section") {
                Toggle("crop.enable", isOn: $configuration.cropEnabled)

                if configuration.cropEnabled {
                    Picker("crop.ratio", selection: $configuration.cropPreset) {
                        ForEach(CropAspectPreset.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }

                    if configuration.cropPreset == .custom {
                        HStack {
                            TextField("crop.ratio_width", value: $configuration.cropCustomWidth, format: .number)
                            Text(":")
                            TextField("crop.ratio_height", value: $configuration.cropCustomHeight, format: .number)
                        }
                    }

                    Button("crop.adjust") {
                        cropEditor = CropEditorPresentation()
                    }
                    .disabled(items.isEmpty)

                    Text("crop.batch_help")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("crop.disabled_help")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(batchProcessor.phase.isActive)

            Section("export.section") {
                Picker("export.format", selection: $configuration.exportFormat) {
                    ForEach(ExportFormat.allCases) { format in
                        Text(format.title).tag(format)
                    }
                }

                LabeledContent("export.quality") {
                    HStack {
                        Slider(value: integerQuality($configuration.quality), in: 1...100)
                            .frame(minWidth: 120)
                        Text(configuration.quality, format: .number.precision(.fractionLength(0)))
                            .monospacedDigit()
                            .frame(width: 28, alignment: .trailing)
                    }
                }

                Picker("export.destination", selection: $configuration.destinationMode) {
                    ForEach(OutputDestinationMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }

                if configuration.destinationMode == .unifiedFolder {
                    LabeledContent("export.folder") {
                        Button {
                            Task {
                                configuration.unifiedOutputURL = await OutputPanel.chooseDirectory()
                            }
                        } label: {
                            Text(configuration.unifiedOutputURL?.lastPathComponent ?? String(localized: "export.choose_folder"))
                                .lineLimit(1)
                        }
                    }
                }

                TextField("export.naming_template", text: $configuration.namingTemplate)
                Text("settings.naming_help")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .disabled(batchProcessor.phase.isActive)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .overlay(alignment: .bottomTrailing) {
            if batchProcessor.phase == .processing {
                Button("batch.cancel", role: .destructive) {
                    batchProcessor.cancel()
                }
                .padding()
            }
        }
        .sheet(item: $cropEditor) { _ in
            CropEditorView(configuration: configuration, items: items)
        }
    }

    private func integerQuality(_ value: Binding<Double>) -> Binding<Double> {
        Binding(
            get: { value.wrappedValue },
            set: { value.wrappedValue = $0.rounded() }
        )
    }

    @ViewBuilder
    private var batchStatus: some View {
        Section("batch.status") {
            switch batchProcessor.phase {
            case .preparing:
                ProgressView()
                Text("batch.preparing")
                    .foregroundStyle(.secondary)
            case .processing, .cancelling:
                ProgressView(
                    value: Double(batchProcessor.completedCount),
                    total: Double(max(1, batchProcessor.totalCount))
                )
                HStack {
                    Text("\(batchProcessor.completedCount) / \(batchProcessor.totalCount)")
                        .monospacedDigit()
                    Spacer()
                    Text(batchProcessor.phase == .cancelling ? "batch.cleaning" : "batch.processing")
                        .foregroundStyle(.secondary)
                }
            case .completed:
                Label("batch.completed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(String(format: String(localized: "batch.result"), batchProcessor.successCount, batchProcessor.failures.count))
            case .cancelled:
                Label("batch.cancelled", systemImage: "xmark.circle")
            case .cleanupFailed:
                Label("batch.cleanup_failed", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(String(format: String(localized: "batch.cleanup_failed_count"), batchProcessor.cleanupFailureCount))
            case .authorizationFailed:
                Label("permission.failed", systemImage: "folder.badge.questionmark")
                    .foregroundStyle(.orange)
                Text(String(
                    format: String(localized: "permission.failed_count"),
                    batchProcessor.authorizationFailureCount
                ))
            case .recoveryAvailable:
                Label("recovery.available", systemImage: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90")
                    .foregroundStyle(.orange)
            case .recovering:
                ProgressView()
                Text("recovery.cleaning")
                    .foregroundStyle(.secondary)
            case .recoveryFailed:
                Label("recovery.failed", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(String(
                    format: String(localized: "recovery.failed_count"),
                    batchProcessor.recoveryFailureCount
                ))
            case .ledgerFailed:
                Label("ledger.failed", systemImage: "externaldrive.badge.exclamationmark")
                    .foregroundStyle(.red)
            case .idle:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private var valueFields: some View {
        switch configuration.mode {
        case .exact:
            HStack {
                TextField("resize.width", value: $configuration.width, format: .number)
                Text("×")
                TextField("resize.height", value: $configuration.height, format: .number)
                Text("px")
                    .foregroundStyle(.secondary)
            }
        case .percentage:
            HStack {
                TextField("resize.percentage", value: $configuration.percentage, format: .number)
                Text("%")
                    .foregroundStyle(.secondary)
            }
        case .fixedWidth, .fixedHeight, .longestEdge, .shortestEdge:
            HStack {
                TextField("resize.pixels", value: $configuration.edge, format: .number)
                Text("px")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct CropEditorPresentation: Identifiable {
    let id = UUID()
}
