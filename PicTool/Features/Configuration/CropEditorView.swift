import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct CropEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let configuration: BatchConfiguration
    let items: [ImageItem]

    @State private var selectedID: ImageItem.ID
    @State private var crop: NormalizedCropRect
    @State private var preset: CropAspectPreset
    @State private var customWidth: Double
    @State private var customHeight: Double

    init(configuration: BatchConfiguration, items: [ImageItem]) {
        self.configuration = configuration
        self.items = items
        _selectedID = State(initialValue: items.first?.id ?? UUID())
        _crop = State(initialValue: configuration.normalizedCrop)
        _preset = State(initialValue: configuration.cropPreset)
        _customWidth = State(initialValue: configuration.cropCustomWidth)
        _customHeight = State(initialValue: configuration.cropCustomHeight)
    }

    private var selectedItem: ImageItem? {
        items.first { $0.id == selectedID } ?? items.first
    }

    private var selectedSize: PixelSize {
        selectedItem?.pixelSize ?? (try! PixelSize(width: 1, height: 1))
    }

    private var aspectRatio: Double? {
        preset.aspectRatio(
            for: selectedSize,
            customWidth: customWidth,
            customHeight: customHeight
        )
    }

    private var customRatioIsValid: Bool {
        preset != .custom || (customWidth.isFinite && customHeight.isFinite
            && customWidth > 0 && customHeight > 0)
    }

    var body: some View {
        VStack(spacing: 0) {
            controls

            Divider()

            if let selectedItem {
                CropCanvasView(
                    item: selectedItem,
                    crop: $crop,
                    aspectRatio: aspectRatio
                )
                .padding(20)
            } else {
                ContentUnavailableView("crop.no_image", systemImage: "photo")
            }

            Divider()

            HStack {
                Text("crop.apply_all_help")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("crop.cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("crop.apply_all") { apply() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!customRatioIsValid)
            }
            .padding()
        }
        .frame(minWidth: 820, minHeight: 600)
    }

    private var controls: some View {
        HStack(spacing: 16) {
            Picker("crop.representative", selection: $selectedID) {
                ForEach(items) { item in
                    Text(item.filename).tag(item.id)
                }
            }
            .frame(maxWidth: 260)

            Picker("crop.ratio", selection: $preset) {
                ForEach(CropAspectPreset.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .frame(width: 190)

            if preset == .custom {
                HStack(spacing: 6) {
                    TextField("crop.ratio_width", value: $customWidth, format: .number)
                        .frame(width: 64)
                    Text(":")
                    TextField("crop.ratio_height", value: $customHeight, format: .number)
                        .frame(width: 64)
                }
            }

            Spacer()

            Button("crop.reset_center") {
                crop = .centered(aspectRatio: aspectRatio, sourceSize: selectedSize)
            }
        }
        .padding()
        .onChange(of: preset) {
            crop = crop.fitted(aspectRatio: aspectRatio, sourceSize: selectedSize)
        }
        .onChange(of: selectedID) {
            crop = crop.fitted(aspectRatio: aspectRatio, sourceSize: selectedSize)
        }
        .onChange(of: customWidth) { fitCustomRatio() }
        .onChange(of: customHeight) { fitCustomRatio() }
    }

    private func fitCustomRatio() {
        guard preset == .custom, customRatioIsValid else { return }
        crop = crop.fitted(aspectRatio: aspectRatio, sourceSize: selectedSize)
    }

    private func apply() {
        configuration.cropPreset = preset
        configuration.cropCustomWidth = customWidth
        configuration.cropCustomHeight = customHeight
        configuration.normalizedCrop = crop.fitted(
            aspectRatio: aspectRatio,
            sourceSize: selectedSize
        )
        dismiss()
    }
}

private struct CropCanvasView: View {
    let item: ImageItem
    @Binding var crop: NormalizedCropRect
    let aspectRatio: Double?

    @State private var gestureStart: NormalizedCropRect?
    @State private var previewImage: NSImage?

    var body: some View {
        GeometryReader { proxy in
            let imageFrame = fittedImageFrame(in: proxy.size)
            let displayedCrop = crop.fitted(aspectRatio: aspectRatio, sourceSize: item.pixelSize)
            let cropFrame = canvasRect(for: displayedCrop, in: imageFrame)

            ZStack {
                Color.black.opacity(0.92)

                if let thumbnail = previewImage ?? item.thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .scaledToFit()
                        .frame(width: imageFrame.width, height: imageFrame.height)
                        .position(x: imageFrame.midX, y: imageFrame.midY)
                }

                outsideMask(imageFrame: imageFrame, cropFrame: cropFrame)

                Rectangle()
                    .stroke(.white, lineWidth: 2)
                    .frame(width: cropFrame.width, height: cropFrame.height)
                    .position(x: cropFrame.midX, y: cropFrame.midY)

                thirdsGrid(in: cropFrame)

                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .frame(width: cropFrame.width, height: cropFrame.height)
                    .position(x: cropFrame.midX, y: cropFrame.midY)
                    .gesture(moveGesture(imageFrame: imageFrame, displayedCrop: displayedCrop))
                    .onHover { hovering in
                        hovering ? NSCursor.openHand.push() : NSCursor.pop()
                    }

                ForEach(CropHandle.allCases, id: \.self) { handle in
                    cropHandle(handle, cropFrame: cropFrame, imageFrame: imageFrame, displayedCrop: displayedCrop)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .focusable()
            .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { press in
                let multiplier = press.modifiers.contains(.shift) ? 10.0 : 1.0
                let dx = multiplier / Double(item.pixelSize.width)
                let dy = multiplier / Double(item.pixelSize.height)
                switch press.key {
                case .leftArrow: crop = displayedCrop.moved(dx: -dx, dy: 0)
                case .rightArrow: crop = displayedCrop.moved(dx: dx, dy: 0)
                case .upArrow: crop = displayedCrop.moved(dx: 0, dy: -dy)
                case .downArrow: crop = displayedCrop.moved(dx: 0, dy: dy)
                default: return .ignored
                }
                return .handled
            }
            .accessibilityLabel("crop.canvas")
            .task(id: item.id) {
                previewImage = nil
                if let data = await CropPreviewLoader.shared.load(url: item.sourceURL) {
                    previewImage = NSImage(data: data)
                }
            }
        }
    }

    private func fittedImageFrame(in size: CGSize) -> CGRect {
        let available = CGSize(width: max(1, size.width - 32), height: max(1, size.height - 32))
        let scale = min(
            available.width / Double(item.pixelSize.width),
            available.height / Double(item.pixelSize.height)
        )
        let width = Double(item.pixelSize.width) * scale
        let height = Double(item.pixelSize.height) * scale
        return CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
    }

    private func canvasRect(for crop: NormalizedCropRect, in imageFrame: CGRect) -> CGRect {
        CGRect(
            x: imageFrame.minX + crop.x * imageFrame.width,
            y: imageFrame.minY + crop.y * imageFrame.height,
            width: crop.width * imageFrame.width,
            height: crop.height * imageFrame.height
        )
    }

    private func outsideMask(imageFrame: CGRect, cropFrame: CGRect) -> some View {
        Path { path in
            path.addRect(imageFrame)
            path.addRect(cropFrame)
        }
        .fill(.black.opacity(0.58), style: FillStyle(eoFill: true))
        .allowsHitTesting(false)
    }

    private func thirdsGrid(in rect: CGRect) -> some View {
        Path { path in
            for fraction in [1.0 / 3.0, 2.0 / 3.0] {
                let x = rect.minX + rect.width * fraction
                let y = rect.minY + rect.height * fraction
                path.move(to: CGPoint(x: x, y: rect.minY))
                path.addLine(to: CGPoint(x: x, y: rect.maxY))
                path.move(to: CGPoint(x: rect.minX, y: y))
                path.addLine(to: CGPoint(x: rect.maxX, y: y))
            }
        }
        .stroke(.white.opacity(0.45), lineWidth: 1)
        .allowsHitTesting(false)
    }

    private func cropHandle(
        _ handle: CropHandle,
        cropFrame: CGRect,
        imageFrame: CGRect,
        displayedCrop: NormalizedCropRect
    ) -> some View {
        let point = handlePoint(handle, in: cropFrame)
        return Image(systemName: handleSymbol(handle))
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.black)
            .frame(width: 24, height: 24)
            .background(.white, in: Circle())
            .contentShape(Rectangle())
            .position(point)
            .gesture(resizeGesture(
                handle: handle,
                imageFrame: imageFrame,
                displayedCrop: displayedCrop
            ))
            .onHover { hovering in
                hovering ? cursor(for: handle).push() : NSCursor.pop()
            }
            .accessibilityLabel(handleAccessibilityLabel(handle))
    }

    private func moveGesture(imageFrame: CGRect, displayedCrop: NormalizedCropRect) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if gestureStart == nil { gestureStart = displayedCrop }
                guard let gestureStart else { return }
                crop = gestureStart.moved(
                    dx: value.translation.width / imageFrame.width,
                    dy: value.translation.height / imageFrame.height
                )
            }
            .onEnded { _ in gestureStart = nil }
    }

    private func resizeGesture(
        handle: CropHandle,
        imageFrame: CGRect,
        displayedCrop: NormalizedCropRect
    ) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if gestureStart == nil { gestureStart = displayedCrop }
                guard let gestureStart else { return }
                crop = gestureStart.resized(
                    at: handle,
                    dx: value.translation.width / imageFrame.width,
                    dy: value.translation.height / imageFrame.height,
                    aspectRatio: aspectRatio,
                    sourceSize: item.pixelSize
                )
            }
            .onEnded { _ in gestureStart = nil }
    }

    private func handlePoint(_ handle: CropHandle, in rect: CGRect) -> CGPoint {
        switch handle {
        case .topLeft: CGPoint(x: rect.minX, y: rect.minY)
        case .top: CGPoint(x: rect.midX, y: rect.minY)
        case .topRight: CGPoint(x: rect.maxX, y: rect.minY)
        case .right: CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomRight: CGPoint(x: rect.maxX, y: rect.maxY)
        case .bottom: CGPoint(x: rect.midX, y: rect.maxY)
        case .bottomLeft: CGPoint(x: rect.minX, y: rect.maxY)
        case .left: CGPoint(x: rect.minX, y: rect.midY)
        }
    }

    private func handleSymbol(_ handle: CropHandle) -> String {
        switch handle {
        case .top, .bottom: "arrow.up.and.down"
        case .left, .right: "arrow.left.and.right"
        default: "arrow.up.left.and.arrow.down.right"
        }
    }

    private func cursor(for handle: CropHandle) -> NSCursor {
        switch handle {
        case .top, .bottom: .resizeUpDown
        case .left, .right: .resizeLeftRight
        default: .crosshair
        }
    }

    private func handleAccessibilityLabel(_ handle: CropHandle) -> Text {
        switch handle {
        case .topLeft: Text("crop.handle.top_left")
        case .top: Text("crop.handle.top")
        case .topRight: Text("crop.handle.top_right")
        case .right: Text("crop.handle.right")
        case .bottomRight: Text("crop.handle.bottom_right")
        case .bottom: Text("crop.handle.bottom")
        case .bottomLeft: Text("crop.handle.bottom_left")
        case .left: Text("crop.handle.left")
        }
    }
}

private actor CropPreviewLoader {
    static let shared = CropPreviewLoader()

    func load(url: URL) -> Data? {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1_600,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}
