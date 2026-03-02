//
//  ContentView.swift
//  Appy
//
//  Created by Joel Vandenberg on 3/1/26.
//

import SwiftUI
import AppKit

struct ContentView: View {
    @Environment(AppScannerService.self) private var scanner
    @Environment(PreferencesManager.self) private var prefs
    @Environment(\.dismissPopover) private var dismissPopover

    @State private var searchText = ""
    @State private var showOptions = false
    @State private var expandedGroupID: UUID? = nil
    @State private var expandedCategory: String?
    @State private var renamingGroupID: UUID? = nil

    // MARK: - Computed

    private var processedApps: [AppItem] {
        var apps = scanner.apps

        // Apply hidden filter
        if !prefs.showHidden {
            apps = apps.filter { !prefs.isHidden($0) }
        } else {
            apps = apps.map { app in
                var a = app
                a.isHidden = prefs.isHidden(app)
                return a
            }
        }

        // Apply search filter
        if !searchText.isEmpty {
            apps = apps.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }

        // Apply sort
        switch prefs.sortOrder {
        case .alphabetical:
            apps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .newest:
            apps.sort { $0.dateAdded > $1.dateAdded }
        }

        return apps
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            topBar

            Divider()

            // Main content
            if scanner.isScanning && scanner.apps.isEmpty {
                Spacer()
                ProgressView("Scanning…")
                    .frame(maxWidth: .infinity)
                Spacer()
            } else if let gid = expandedGroupID,
                      let group = prefs.groups.first(where: { $0.id == gid }) {
                let groupApps = processedApps.filter {
                    group.appBundleIdentifiers.contains($0.id)
                }
                GroupExpandedView(
                    groupName: group.name,
                    apps: groupApps,
                    viewMode: prefs.viewMode,
                    iconSize: prefs.iconSize,
                    groups: prefs.groups,
                    currentGroupID: group.id,
                    onLaunch: launchApp,
                    onToggleHidden: { prefs.toggleHidden($0) },
                    onAddToGroup: { app, gid in prefs.addApp(app.id, toGroup: gid) },
                    onRemoveFromGroup: { app in
                        prefs.removeApp(app.id, fromGroup: group.id)
                    },
                    onAddToNewGroup: { app, name in
                        prefs.addGroupWithApp(named: name, appID: app.id)
                    },
                    onBack: { expandedGroupID = nil }
                )
            } else if let category = expandedCategory {
                let catApps = processedApps.filter { $0.categoryDisplayName == category }
                GroupExpandedView(
                    groupName: category,
                    apps: catApps,
                    viewMode: prefs.viewMode,
                    iconSize: prefs.iconSize,
                    groups: prefs.groups,
                    onLaunch: launchApp,
                    onToggleHidden: { prefs.toggleHidden($0) },
                    onAddToGroup: { app, gid in prefs.addApp(app.id, toGroup: gid) },
                    onRemoveFromGroup: nil,
                    onAddToNewGroup: { app, name in
                        prefs.addGroupWithApp(named: name, appID: app.id)
                    },
                    onBack: { expandedCategory = nil }
                )
            } else {
                mainContent
            }
        }
        .frame(minWidth: 300, minHeight: 300)
        .onChange(of: prefs.groupingMode) { _, _ in
            expandedGroupID = nil
            expandedCategory = nil
        }
        .sheet(isPresented: $showOptions) {
            OptionsView()
                .environment(prefs)
                .environment(scanner)
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        VStack(spacing: 6) {
            // Search
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Search apps…", text: $searchText)
                    .textFieldStyle(.plain)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(.quaternary.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Controls row
            HStack(spacing: 8) {
                // Sort toggle
                Button {
                    prefs.sortOrder = prefs.sortOrder == .alphabetical ? .newest : .alphabetical
                } label: {
                    Image(systemName: prefs.sortOrder.systemImage)
                        .imageScale(.large)
                }
                .frame(width: 32)
                .buttonStyle(.plain)
                .help("Sort: \(prefs.sortOrder.rawValue)")
                
                Spacer()

                // View mode picker
                Picker("", selection: Binding(
                    get: { prefs.viewMode },
                    set: { prefs.viewMode = $0 }
                )) {
                    ForEach(ViewMode.allCases) { mode in
                        Image(systemName: mode.systemImage)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 100)

                // Grouping mode picker
                Picker("", selection: Binding(
                    get: { prefs.groupingMode },
                    set: { prefs.groupingMode = $0 }
                )) {
                    Text("—").tag(GroupingMode.none)
                    Image(systemName: "folder").tag(GroupingMode.manual)
                    Image(systemName: "tag").tag(GroupingMode.category)
                }
                .pickerStyle(.segmented)
                .frame(width: 100)
                .help("Grouping: \(prefs.groupingMode.rawValue)")

                Spacer()

                // Options gear
                Button {
                    showOptions = true
                } label: {
                    Image(systemName: "gearshape")
                        .imageScale(.large)
                }
                .buttonStyle(.plain)
                .help("Options")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        ScrollView {
            switch prefs.groupingMode {
            case .none:
                ungroupedContent
            case .manual:
                manualGroupedContent
            case .category:
                categoryGroupedContent
            }
        }
        .padding(8)
    }

    // MARK: Ungrouped

    @ViewBuilder
    private var ungroupedContent: some View {
        appGrid(processedApps)
    }

    // MARK: Manual Groups

    @ViewBuilder
    private var manualGroupedContent: some View {
        let apps = processedApps

        let activeGroups = prefs.groups.filter { group in
            apps.contains { group.appBundleIdentifiers.contains($0.id) }
        }
        // Also show empty groups so users can drag into them
        let emptyGroups = prefs.groups.filter { group in
            !activeGroups.contains(where: { $0.id == group.id })
        }
        let allDisplayGroups = activeGroups + emptyGroups

        if prefs.viewMode == .list {
            LazyVStack(spacing: 2) {
                ForEach(allDisplayGroups) { group in
                    let groupApps = apps.filter { group.appBundleIdentifiers.contains($0.id) }
                    DisclosureGroup {
                        ForEach(groupApps) { app in
                            AppListRowView(
                                app: app,
                                onLaunch: { launchApp(app) },
                                onToggleHidden: { prefs.toggleHidden(app) },
                                groups: prefs.groups,
                                onAddToGroup: { gid in prefs.addApp(app.id, toGroup: gid) },
                                onRemoveFromGroup: { prefs.removeApp(app.id, fromGroup: group.id) },
                                onAddToNewGroup: { name in prefs.addGroupWithApp(named: name, appID: app.id) },
                                currentGroupID: group.id
                            )
                        }
                    } label: {
                        GroupListHeaderView(
                            name: group.name,
                            appCount: group.appBundleIdentifiers.count,
                            groupID: group.id,
                            onDropApp: { appID in prefs.addApp(appID, toGroup: group.id) },
                            onRename: { newName in prefs.renameGroup(group.id, to: newName) },
                            renamingGroupID: $renamingGroupID
                        )
                    }
                    .contextMenu {
                        Button("Rename") {
                            renamingGroupID = group.id
                        }
                        Button("Delete Group", role: .destructive) {
                            prefs.removeGroup(group)
                        }
                    }
                }

                // Ungrouped apps
                let groupedIDs = Set(prefs.groups.flatMap(\.appBundleIdentifiers))
                let ungrouped = apps.filter { !groupedIDs.contains($0.id) }
                if !ungrouped.isEmpty {
                    DisclosureGroup {
                        ForEach(ungrouped) { app in
                            AppListRowView(
                                app: app,
                                onLaunch: { launchApp(app) },
                                onToggleHidden: { prefs.toggleHidden(app) },
                                groups: prefs.groups,
                                onAddToGroup: { gid in prefs.addApp(app.id, toGroup: gid) },
                                onAddToNewGroup: { name in prefs.addGroupWithApp(named: name, appID: app.id) }
                            )
                        }
                    } label: {
                        Label("Other", systemImage: "folder")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                }
            }
        } else {
            let gridItemSize = prefs.viewMode == .iconOnly ? prefs.iconSize + 12 : prefs.iconSize + 24
            LazyVGrid(columns: [GridItem(.adaptive(minimum: gridItemSize), spacing: 4)], spacing: 8) {
                ForEach(allDisplayGroups) { group in
                    GroupHeaderView(
                        name: group.name,
                        appCount: group.appBundleIdentifiers.count,
                        iconSize: prefs.iconSize,
                        groupID: group.id,
                        action: { expandedGroupID = group.id },
                        onDropApp: { appID in prefs.addApp(appID, toGroup: group.id) },
                        onRename: { newName in prefs.renameGroup(group.id, to: newName) },
                        renamingGroupID: $renamingGroupID
                    )
                    .contextMenu {
                        Button("Rename") {
                            renamingGroupID = group.id
                        }
                        Button("Delete Group", role: .destructive) {
                            prefs.removeGroup(group)
                        }
                    }
                }

                // Ungrouped apps inline
                let groupedIDs = Set(prefs.groups.flatMap(\.appBundleIdentifiers))
                let ungrouped = apps.filter { !groupedIDs.contains($0.id) }
                ForEach(ungrouped) { app in
                    appCell(app, onAddToNewGroup: { name in prefs.addGroupWithApp(named: name, appID: app.id) })
                }
            }
        }
    }

    // MARK: Category Groups

    @ViewBuilder
    private var categoryGroupedContent: some View {
        let apps = processedApps
        let grouped = Dictionary(grouping: apps) { $0.categoryDisplayName }
        let sortedKeys = grouped.keys.sorted()

        if prefs.viewMode == .list {
            LazyVStack(spacing: 2) {
                ForEach(sortedKeys, id: \.self) { category in
                    let catApps = grouped[category] ?? []
                    DisclosureGroup {
                        ForEach(catApps) { app in
                            AppListRowView(
                                app: app,
                                onLaunch: { launchApp(app) },
                                onToggleHidden: { prefs.toggleHidden(app) },
                                groups: prefs.groups,
                                onAddToGroup: { gid in prefs.addApp(app.id, toGroup: gid) },
                                onAddToNewGroup: { name in prefs.addGroupWithApp(named: name, appID: app.id) }
                            )
                        }
                    } label: {
                        HStack {
                            Text(category)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Spacer()
                            Text("\(catApps.count)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        } else {
            let gridItemSize = prefs.viewMode == .iconOnly ? prefs.iconSize + 12 : prefs.iconSize + 24
            LazyVGrid(columns: [GridItem(.adaptive(minimum: gridItemSize), spacing: 4)], spacing: 8) {
                ForEach(sortedKeys, id: \.self) { category in
                    let catApps = grouped[category] ?? []
                    GroupHeaderView(
                        name: category,
                        appCount: catApps.count,
                        iconSize: prefs.iconSize,
                        groupID: UUID(), // category groups don't have a real UUID
                        action: { expandedCategory = category },
                        onDropApp: { _ in }, // no drop for categories
                        renamingGroupID: .constant(nil)
                    )
                }
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func appGrid(_ apps: [AppItem]) -> some View {
        switch prefs.viewMode {
        case .iconWithName:
            LazyVGrid(columns: [GridItem(.adaptive(minimum: prefs.iconSize + 24), spacing: 4)], spacing: 8) {
                ForEach(apps) { app in
                    AppIconNameView(
                        app: app,
                        iconSize: prefs.iconSize,
                        onLaunch: { launchApp(app) },
                        onToggleHidden: { prefs.toggleHidden(app) },
                        groups: prefs.groups,
                        onAddToGroup: { gid in prefs.addApp(app.id, toGroup: gid) },
                        onAddToNewGroup: { name in prefs.addGroupWithApp(named: name, appID: app.id) }
                    )
                }
            }
        case .iconOnly:
            LazyVGrid(columns: [GridItem(.adaptive(minimum: prefs.iconSize + 12), spacing: 4)], spacing: 8) {
                ForEach(apps) { app in
                    AppIconOnlyView(
                        app: app,
                        iconSize: prefs.iconSize,
                        onLaunch: { launchApp(app) },
                        onToggleHidden: { prefs.toggleHidden(app) },
                        groups: prefs.groups,
                        onAddToGroup: { gid in prefs.addApp(app.id, toGroup: gid) },
                        onAddToNewGroup: { name in prefs.addGroupWithApp(named: name, appID: app.id) }
                    )
                }
            }
        case .list:
            LazyVStack(spacing: 2) {
                ForEach(apps) { app in
                    AppListRowView(
                        app: app,
                        onLaunch: { launchApp(app) },
                        onToggleHidden: { prefs.toggleHidden(app) },
                        groups: prefs.groups,
                        onAddToGroup: { gid in prefs.addApp(app.id, toGroup: gid) },
                        onAddToNewGroup: { name in prefs.addGroupWithApp(named: name, appID: app.id) }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func appCell(_ app: AppItem, onAddToNewGroup: ((String) -> Void)? = nil) -> some View {
        switch prefs.viewMode {
        case .iconWithName:
            AppIconNameView(
                app: app,
                iconSize: prefs.iconSize,
                onLaunch: { launchApp(app) },
                onToggleHidden: { prefs.toggleHidden(app) },
                groups: prefs.groups,
                onAddToGroup: { gid in prefs.addApp(app.id, toGroup: gid) },
                onAddToNewGroup: onAddToNewGroup
            )
        case .iconOnly:
            AppIconOnlyView(
                app: app,
                iconSize: prefs.iconSize,
                onLaunch: { launchApp(app) },
                onToggleHidden: { prefs.toggleHidden(app) },
                groups: prefs.groups,
                onAddToGroup: { gid in prefs.addApp(app.id, toGroup: gid) },
                onAddToNewGroup: onAddToNewGroup
            )
        case .list:
            AppListRowView(
                app: app,
                onLaunch: { launchApp(app) },
                onToggleHidden: { prefs.toggleHidden(app) },
                groups: prefs.groups,
                onAddToGroup: { gid in prefs.addApp(app.id, toGroup: gid) },
                onAddToNewGroup: onAddToNewGroup
            )
        }
    }

    private func launchApp(_ app: AppItem) {
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: app.url, configuration: config) { _, _ in }
        dismissPopover()
    }
}
