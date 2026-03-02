import Foundation
import AppKit
import Observation

/// Scans /Applications and ~/Applications for .app bundles.
@Observable
final class AppScannerService {
    private(set) var apps: [AppItem] = []
    private(set) var isScanning = false

    private let fileManager = FileManager.default

    /// Directories to scan for applications.
    nonisolated private static func appDirectories() -> [URL] {
        var dirs = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications")
        ]
        let userApps = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications")
        if FileManager.default.fileExists(atPath: userApps.path) {
            dirs.append(userApps)
        }
        return dirs
    }

    /// Perform a full scan (runs heavy work off the main thread).
    func scan() {
        guard !isScanning else { return }
        isScanning = true

        Task.detached { [weak self] in
            guard let self else { return }
            let scanned = self.performScan()
            await MainActor.run {
                self.apps = scanned
                self.isScanning = false
            }
        }
    }

    // MARK: - Private

    nonisolated private func performScan() -> [AppItem] {
        var results: [AppItem] = []
        var seen = Set<String>() // dedupe by bundle id or path

        let directories = Self.appDirectories()
        for directory in directories {
            guard let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey, .creationDateKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let fileURL as URL in enumerator {
                guard fileURL.pathExtension == "app" else { continue }
                guard let item = makeAppItem(from: fileURL, seen: &seen) else { continue }
                results.append(item)
            }
        }

        return results.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    nonisolated private func makeAppItem(from url: URL, seen: inout Set<String>) -> AppItem? {
        let bundle = Bundle(url: url)
        let info = bundle?.infoDictionary

        let bundleID = info?["CFBundleIdentifier"] as? String
        let dedupeKey = bundleID ?? url.path

        guard !seen.contains(dedupeKey) else { return nil }
        seen.insert(dedupeKey)

        let name = (info?["CFBundleDisplayName"] as? String)
            ?? (info?["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent

        let category = info?["LSApplicationCategoryType"] as? String

        let icon = Self.rasterizeIcon(NSWorkspace.shared.icon(forFile: url.path))

        let resourceValues = try? url.resourceValues(forKeys: [.creationDateKey])
        let dateAdded = resourceValues?.creationDate ?? Date.distantPast

        return AppItem(
            id: dedupeKey,
            name: name,
            url: url,
            bundleIdentifier: bundleID,
            category: category,
            icon: icon,
            dateAdded: dateAdded
        )
    }

    /// Rasterize icon to a CGImage-backed NSImage so SwiftUI never
    /// treats it as a template or symbol image.
    nonisolated private static func rasterizeIcon(_ source: NSImage) -> NSImage {
        let px = 256
        let size = NSSize(width: px, height: px)

        source.isTemplate = false

        // Create a CGContext directly — avoids all AppKit template semantics
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: px,
            height: px,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return source
        }

        // Draw via NSGraphicsContext wrapping the CGContext
        let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsCtx
        source.draw(in: NSRect(origin: .zero, size: size),
                    from: .zero,
                    operation: .copy,
                    fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()

        guard let cgImage = ctx.makeImage() else { return source }
        let result = NSImage(cgImage: cgImage, size: size)
        result.isTemplate = false
        return result
    }
}
