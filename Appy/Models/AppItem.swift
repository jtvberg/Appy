import Foundation
import AppKit

// Represents a single application found on disk
struct AppItem: Identifiable, Hashable {
    let id: String // bundleIdentifier or path as fallback
    let name: String
    let url: URL
    let bundleIdentifier: String?
    let category: String?
    let icon: NSImage
    let dateAdded: Date
    var isHidden: Bool = false

    // Human-friendly category name derived from LSApplicationCategoryType or Spotlight category
    var categoryDisplayName: String {
        guard let category, !category.isEmpty else { return "Other" }
        return Self.humanize(category)
    }

    // MARK: Hashable / Equatable

    static func == (lhs: AppItem, rhs: AppItem) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    // MARK: Category helpers

    // Convert a category identifier or display name to a human-readable label
    private static func humanize(_ raw: String) -> String {
        // If it doesn't look like a reverse-DNS identifier, it's already a display name from Spotlight — return as-is
        guard raw.contains(".") else { return raw }

        let last = raw.components(separatedBy: ".").last ?? raw

        // Collapse all game subcategories into "Games"
        if last.hasSuffix("-games") { return "Games" }

        return last
            .capitalized
    }
}
