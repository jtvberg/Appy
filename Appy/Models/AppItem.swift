import Foundation
import AppKit

/// Represents a single application found on disk.
struct AppItem: Identifiable, Hashable {
    let id: String // bundleIdentifier or path as fallback
    let name: String
    let url: URL
    let bundleIdentifier: String?
    let category: String?
    let icon: NSImage
    let dateAdded: Date

    var isHidden: Bool = false

    /// Human-friendly category name derived from LSApplicationCategoryType.
    var categoryDisplayName: String {
        guard let category else { return "Uncategorized" }
        return Self.categoryMap[category] ?? Self.humanize(category)
    }

    // MARK: - Hashable / Equatable

    static func == (lhs: AppItem, rhs: AppItem) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    // MARK: - Category mapping

    private static let categoryMap: [String: String] = [
        "public.app-category.business": "Business",
        "public.app-category.developer-tools": "Developer Tools",
        "public.app-category.education": "Education",
        "public.app-category.entertainment": "Entertainment",
        "public.app-category.finance": "Finance",
        "public.app-category.games": "Games",
        "public.app-category.action-games": "Games",
        "public.app-category.adventure-games": "Games",
        "public.app-category.arcade-games": "Games",
        "public.app-category.board-games": "Games",
        "public.app-category.card-games": "Games",
        "public.app-category.casino-games": "Games",
        "public.app-category.dice-games": "Games",
        "public.app-category.educational-games": "Games",
        "public.app-category.family-games": "Games",
        "public.app-category.kids-games": "Games",
        "public.app-category.music-games": "Games",
        "public.app-category.puzzle-games": "Games",
        "public.app-category.racing-games": "Games",
        "public.app-category.role-playing-games": "Games",
        "public.app-category.simulation-games": "Games",
        "public.app-category.sports-games": "Games",
        "public.app-category.strategy-games": "Games",
        "public.app-category.trivia-games": "Games",
        "public.app-category.word-games": "Games",
        "public.app-category.graphics-design": "Graphics & Design",
        "public.app-category.healthcare-fitness": "Health & Fitness",
        "public.app-category.lifestyle": "Lifestyle",
        "public.app-category.medical": "Medical",
        "public.app-category.music": "Music",
        "public.app-category.news": "News",
        "public.app-category.photography": "Photography",
        "public.app-category.productivity": "Productivity",
        "public.app-category.reference": "Reference",
        "public.app-category.social-networking": "Social Networking",
        "public.app-category.sports": "Sports",
        "public.app-category.travel": "Travel",
        "public.app-category.utilities": "Utilities",
        "public.app-category.video": "Video",
        "public.app-category.weather": "Weather",
    ]

    /// Fallback: convert reverse-DNS style to human-readable.
    private static func humanize(_ raw: String) -> String {
        let last = raw.components(separatedBy: ".").last ?? raw
        return last
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }
}
