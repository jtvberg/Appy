import Foundation
import AppKit
import Observation

// Scans /Applications and ~/Applications for .app bundles
@Observable
final class AppScannerService {
    private(set) var apps: [AppItem] = []
    private(set) var spotlightApps: [AppItem] = []
    private(set) var isScanning = false
    private let fileManager = FileManager.default
    private var metadataQuery: NSMetadataQuery?

    // Directories to scan for applications
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

    // Perform a full scan (runs heavy work off the main thread)
    func scan() {
        guard !isScanning else { return }
        isScanning = true

        Task.detached { [weak self] in
            guard let self else { return }
            let scanned = self.performScan()
            await MainActor.run {
                self.apps = scanned
                self.isScanning = false
                self.runSpotlightQuery()
            }
        }
    }

    // MARK: Spotlight Search

    private func runSpotlightQuery() {
        metadataQuery?.stop()
        let query = NSMetadataQuery()
        query.predicate = NSPredicate(format: "kMDItemContentType == 'com.apple.application-bundle'")
        query.searchScopes = [NSMetadataQueryLocalComputerScope]

        NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidFinishGathering,
            object: query,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            query.stop()
            self.processSpotlightResults(query)
        }

        metadataQuery = query
        query.start()
    }

    private func processSpotlightResults(_ query: NSMetadataQuery) {
        let existingIDs = Set(apps.map(\.id))
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        let userAppsPath = homePath + "/Applications"
        let selfID = Bundle.main.bundleIdentifier

        struct SpotlightEntry {
            let path: String
            let spotlightCategory: String?
        }
        var entries: [SpotlightEntry] = []
        for i in 0..<query.resultCount {
            guard let item = query.result(at: i) as? NSMetadataItem,
                  let path = item.value(forAttribute: kMDItemPath as String) as? String
            else { continue }
            let cat = item.value(forAttribute: "kMDItemAppStoreCategory") as? String
            entries.append(SpotlightEntry(path: path, spotlightCategory: cat))
        }

        var spotlightCategoryByID: [String: String] = [:]
        for entry in entries {
            let bundle = Bundle(path: entry.path)
            if let bundleID = bundle?.bundleIdentifier, let cat = entry.spotlightCategory {
                spotlightCategoryByID[bundleID] = cat
            }
        }
        supplementCategories(from: spotlightCategoryByID)

        Task.detached { [weak self] in
            guard let self else { return }
            var results: [AppItem] = []
            var seen = Set<String>()

            for entry in entries {
                let path = entry.path

                // Exclude anything under ~/ except ~/Applications
                if path.hasPrefix(homePath + "/") && !path.hasPrefix(userAppsPath + "/") {
                    continue
                }

                let url = URL(fileURLWithPath: path)
                guard url.pathExtension == "app" else { continue }

                // Filter out non-user-facing apps
                if !Self.isUserFacingApp(at: url) { continue }

                guard let appItem = self.makeAppItem(from: url, seen: &seen, spotlightCategory: entry.spotlightCategory) else { continue }

                // Skip self
                if appItem.bundleIdentifier == selfID { continue }
                // Skip if already in filesystem scan
                if existingIDs.contains(appItem.id) { continue }

                results.append(appItem)
            }

            let sorted = results.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            await MainActor.run {
                self.spotlightApps = sorted
            }
        }
    }

    // Supplement filesystem-scanned apps that have no category with the category from Spotlight metadata (kMDItemAppStoreCategory)
    private func supplementCategories(from spotlightCategories: [String: String]) {
        for i in apps.indices {
            guard apps[i].category == nil || apps[i].category?.isEmpty == true,
                  let bundleID = apps[i].bundleIdentifier,
                  let spotCat = spotlightCategories[bundleID]
            else { continue }
            apps[i] = AppItem(
                id: apps[i].id,
                name: apps[i].name,
                url: apps[i].url,
                bundleIdentifier: apps[i].bundleIdentifier,
                category: spotCat,
                icon: apps[i].icon,
                dateAdded: apps[i].dateAdded
            )
        }
    }

    // Check if an app is user-facing (not a background agent, UIElement, or iconless helper)
    nonisolated private static func isUserFacingApp(at url: URL) -> Bool {
        guard let bundle = Bundle(url: url),
              let info = bundle.infoDictionary else { return false }

        // Exclude background-only apps
        if info["LSBackgroundOnly"] as? Bool == true { return false }
        // Exclude UIElement apps (menu bar agents with no dock icon)
        if info["LSUIElement"] as? Bool == true { return false }
        // Also check string "1" variant
        if info["LSUIElement"] as? String == "1" { return false }
        // Exclude apps without a custom icon (helper stubs use generic icon)
        let hasIcon = (info["CFBundleIconFile"] as? String) != nil
            || (info["CFBundleIconName"] as? String) != nil
        if !hasIcon { return false }

        return true
    }

    // MARK: Private

    nonisolated private func performScan() -> [AppItem] {
        var results: [AppItem] = []
        var seen = Set<String>()

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

    nonisolated private func makeAppItem(from url: URL, seen: inout Set<String>, spotlightCategory: String? = nil) -> AppItem? {
        let bundle = Bundle(url: url)
        let info = bundle?.infoDictionary
        let bundleID = info?["CFBundleIdentifier"] as? String
        let dedupeKey = bundleID ?? url.path

        // Exclude self from results
        if bundleID == Bundle.main.bundleIdentifier { return nil }

        guard !seen.contains(dedupeKey) else { return nil }
        seen.insert(dedupeKey)

        let name = (info?["CFBundleDisplayName"] as? String)
            ?? (info?["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent

        // Use Info.plist category, fall back to Spotlight category if available
        var category = info?["LSApplicationCategoryType"] as? String
        if (category == nil || category?.isEmpty == true), let spotCat = spotlightCategory {
            category = spotCat
        }

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

    // Rasterize icon to a CGImage-backed NSImage so SwiftUI never treats it as a template or symbol image
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
