import Foundation
import SwiftUI
import Observation
import ServiceManagement

// MARK: Enums

enum ViewMode: String, CaseIterable, Identifiable {
    case iconWithName = "Icons & Names"
    case iconOnly = "Icons Only"
    case list = "List"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .iconWithName: return "square.grid.2x2"
        case .iconOnly: return "circle.grid.3x3"
        case .list: return "list.bullet"
        }
    }
}

enum SortOrder: String, CaseIterable, Identifiable {
    case alphabetical = "A-Z"
    case newest = "Newest"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .alphabetical: return "textformat.abc"
        case .newest: return "clock"
        }
    }
}

enum GroupingMode: String, CaseIterable, Identifiable {
    case none = "None"
    case manual = "Manual"
    case category = "Category"

    var id: String { rawValue }
}

// MARK: PreferencesManager

@Observable
final class PreferencesManager {

    // MARK: View settings

    var viewMode: ViewMode {
        didSet { defaults.set(viewMode.rawValue, forKey: Keys.viewMode) }
    }

    var iconSize: CGFloat {
        didSet { defaults.set(Double(iconSize), forKey: Keys.iconSize) }
    }

    var listIconSize: CGFloat {
        didSet { defaults.set(Double(listIconSize), forKey: Keys.listIconSize) }
    }

    var sortOrder: SortOrder {
        didSet { defaults.set(sortOrder.rawValue, forKey: Keys.sortOrder) }
    }

    // MARK: Grouping

    var groupingMode: GroupingMode {
        didSet { defaults.set(groupingMode.rawValue, forKey: Keys.groupingMode) }
    }

    var groups: [AppGroup] {
        didSet { saveGroups() }
    }

    // MARK: Hidden apps

    var hiddenAppIDs: Set<String> {
        didSet { defaults.set(Array(hiddenAppIDs), forKey: Keys.hiddenAppIDs) }
    }

    var showHidden: Bool {
        didSet { defaults.set(showHidden, forKey: Keys.showHidden) }
    }

    // MARK: Window

    var popoverWidth: CGFloat {
        didSet { defaults.set(Double(popoverWidth), forKey: Keys.popoverWidth) }
    }

    var popoverHeight: CGFloat {
        didSet { defaults.set(Double(popoverHeight), forKey: Keys.popoverHeight) }
    }

    // Transient — not persisted; used to signal ContentView to reset sheet state on close
    var popoverVisible: Bool = false

    // MARK: UI

    var showControls: Bool {
        didSet { defaults.set(showControls, forKey: Keys.showControls) }
    }

    // MARK: Login

    var launchAtLogin: Bool {
        didSet {
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                // Revert on failure
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        }
    }

    // MARK: Init

    private let defaults = UserDefaults.standard

    init() {
        self.viewMode = ViewMode(rawValue: defaults.string(forKey: Keys.viewMode) ?? "") ?? .iconWithName
        self.iconSize = CGFloat(defaults.double(forKey: Keys.iconSize) != 0 ? defaults.double(forKey: Keys.iconSize) : 64)
        self.listIconSize = CGFloat(defaults.double(forKey: Keys.listIconSize) != 0 ? defaults.double(forKey: Keys.listIconSize) : 24)
        self.sortOrder = SortOrder(rawValue: defaults.string(forKey: Keys.sortOrder) ?? "") ?? .alphabetical
        self.groupingMode = GroupingMode(rawValue: defaults.string(forKey: Keys.groupingMode) ?? "") ?? .none
        self.hiddenAppIDs = Set(defaults.stringArray(forKey: Keys.hiddenAppIDs) ?? [])
        self.showHidden = defaults.bool(forKey: Keys.showHidden)
        let storedWidth = CGFloat(defaults.double(forKey: Keys.popoverWidth))
        self.popoverWidth = (storedWidth >= 336) ? storedWidth : 560
        self.popoverHeight = CGFloat(defaults.double(forKey: Keys.popoverHeight) != 0 ? defaults.double(forKey: Keys.popoverHeight) : 520)
        self.showControls = defaults.object(forKey: Keys.showControls) == nil ? true : defaults.bool(forKey: Keys.showControls)
        self.launchAtLogin = SMAppService.mainApp.status == .enabled

        // Load groups
        if let data = defaults.data(forKey: Keys.groups),
           let decoded = try? JSONDecoder().decode([AppGroup].self, from: data) {
            self.groups = decoded
        } else {
            self.groups = []
        }
    }

    // MARK: Helpers

    func isHidden(_ app: AppItem) -> Bool {
        hiddenAppIDs.contains(app.id)
    }

    func toggleHidden(_ app: AppItem) {
        if hiddenAppIDs.contains(app.id) {
            hiddenAppIDs.remove(app.id)
        } else {
            hiddenAppIDs.insert(app.id)
        }
    }

    func addGroup(named name: String) {
        groups.append(AppGroup(name: name))
    }

    // Create a new group, add the given app to it, and return the group
    @discardableResult
    func addGroupWithApp(named name: String, appID: String) -> AppGroup {
        var baseName = name
        var counter = 1
        while groups.contains(where: { $0.name == baseName }) {
            counter += 1
            baseName = "\(name) \(counter)"
        }
        var group = AppGroup(name: baseName)
        group.appBundleIdentifiers.append(appID)
        groups.append(group)
        return group
    }

    func removeGroup(_ group: AppGroup) {
        groups.removeAll { $0.id == group.id }
    }

    func renameGroup(_ groupID: UUID, to newName: String) {
        guard let idx = groups.firstIndex(where: { $0.id == groupID }) else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        groups[idx].name = trimmed
    }

    func addApp(_ appID: String, toGroup groupID: UUID) {
        // Remove from any other group first
        for i in groups.indices where groups[i].id != groupID {
            groups[i].appBundleIdentifiers.removeAll { $0 == appID }
        }
        // Clean up any groups that became empty
        groups.removeAll { $0.id != groupID && $0.appBundleIdentifiers.isEmpty }
        // Add to target group
        guard let idx = groups.firstIndex(where: { $0.id == groupID }) else { return }
        if !groups[idx].appBundleIdentifiers.contains(appID) {
            groups[idx].appBundleIdentifiers.append(appID)
        }
    }

    func removeApp(_ appID: String, fromGroup groupID: UUID) {
        guard let idx = groups.firstIndex(where: { $0.id == groupID }) else { return }
        groups[idx].appBundleIdentifiers.removeAll { $0 == appID }
        // Auto-remove empty groups
        if groups[idx].appBundleIdentifiers.isEmpty {
            groups.remove(at: idx)
        }
    }

    // MARK: Private

    private func saveGroups() {
        if let data = try? JSONEncoder().encode(groups) {
            defaults.set(data, forKey: Keys.groups)
        }
    }

    private enum Keys {
        static let viewMode = "viewMode"
        static let iconSize = "iconSize"
        static let listIconSize = "listIconSize"
        static let sortOrder = "sortOrder"
        static let groupingMode = "groupingMode"
        static let groups = "groups"
        static let hiddenAppIDs = "hiddenAppIDs"
        static let showHidden = "showHidden"
        static let popoverWidth = "popoverWidth"
        static let popoverHeight = "popoverHeight"
        static let showControls = "showControls"
    }
}
