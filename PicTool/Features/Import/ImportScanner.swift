import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ImportScanResult: Sendable {
    let images: [ImportedImageData]
    let ignoredCount: Int
    let errors: [ImportFailure]
}

struct ImportFailure: Sendable {
    let url: URL
    let reason: ImportFailureReason
}

enum ImportFailureReason: Sendable {
    case unreadable
    case invalidImage
}

actor ImportScanner {
    private struct Candidate {
        let url: URL
        let accessRootURL: URL
    }

    private let fileManager: FileManager
    private let supportedTypeIdentifiers: Set<String>

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.supportedTypeIdentifiers = [
            UTType.jpeg.identifier,
            UTType.png.identifier,
            UTType.webP.identifier,
            UTType.heic.identifier,
            UTType.tiff.identifier,
        ]
    }

    func scan(_ inputURLs: [URL]) -> ImportScanResult {
        let activeScopes = inputURLs.filter { $0.startAccessingSecurityScopedResource() }
        defer {
            for url in activeScopes { url.stopAccessingSecurityScopedResource() }
        }

        var candidates: [Candidate] = []
        var ignoredCount = 0
        var failures: [ImportFailure] = []

        for inputURL in inputURLs {
            do {
                let values = try inputURL.resourceValues(forKeys: [.isDirectoryKey, .isHiddenKey])
                if values.isHidden == true {
                    ignoredCount += 1
                } else if values.isDirectory == true {
                    let children = try fileManager.contentsOfDirectory(
                        at: inputURL,
                        includingPropertiesForKeys: [.contentTypeKey, .isRegularFileKey, .isHiddenKey],
                        options: [.skipsHiddenFiles]
                    )
                    candidates.append(contentsOf: children.map {
                        Candidate(url: $0, accessRootURL: inputURL)
                    })
                } else {
                    candidates.append(Candidate(url: inputURL, accessRootURL: inputURL))
                }
            } catch {
                failures.append(ImportFailure(url: inputURL, reason: .unreadable))
            }
        }

        var seenPaths = Set<String>()
        var images: [ImportedImageData] = []

        for candidate in candidates {
            let url = candidate.url
            let canonicalPath = url.standardizedFileURL.path
            guard seenPaths.insert(canonicalPath).inserted else { continue }

            do {
                let values = try url.resourceValues(forKeys: [.contentTypeKey, .isRegularFileKey, .isHiddenKey])
                guard values.isHidden != true, values.isRegularFile == true else {
                    ignoredCount += 1
                    continue
                }
                guard let contentType = values.contentType,
                      supportedTypeIdentifiers.contains(contentType.identifier) else {
                    ignoredCount += 1
                    continue
                }
                guard let image = makeImageData(
                    at: url,
                    accessRootURL: candidate.accessRootURL,
                    typeIdentifier: contentType.identifier
                ) else {
                    failures.append(ImportFailure(url: url, reason: .invalidImage))
                    continue
                }
                images.append(image)
            } catch {
                failures.append(ImportFailure(url: url, reason: .unreadable))
            }
        }

        return ImportScanResult(images: images, ignoredCount: ignoredCount, errors: failures)
    }

    private func makeImageData(
        at url: URL,
        accessRootURL: URL,
        typeIdentifier: String
    ) -> ImportedImageData? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let rawWidth = properties[kCGImagePropertyPixelWidth] as? Int,
              let rawHeight = properties[kCGImagePropertyPixelHeight] as? Int else {
            return nil
        }

        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        let swapsAxes = [5, 6, 7, 8].contains(orientation)
        guard let size = try? PixelSize(
            width: swapsAxes ? rawHeight : rawWidth,
            height: swapsAxes ? rawWidth : rawHeight
        ) else {
            return nil
        }

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 96,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary)
        let thumbnailData = thumbnail.flatMap(Self.pngData)

        return ImportedImageData(
            sourceURL: url,
            accessRootURL: accessRootURL,
            typeIdentifier: typeIdentifier,
            pixelSize: size,
            thumbnailData: thumbnailData
        )
    }

    private static func pngData(from image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
