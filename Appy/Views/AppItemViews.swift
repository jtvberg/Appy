import SwiftUI

// MARK: - Icon + Name Grid Cell

struct AppIconNameView: View {
    let app: AppItem
    let iconSize: CGFloat
    let onLaunch: () -> Void
    let onToggleHidden: () -> Void
    let groups: [AppGroup]
    let onAddToGroup: (UUID) -> Void
    var onRemoveFromGroup: (() -> Void)? = nil
    var onAddToNewGroup: ((String) -> Void)? = nil
    var currentGroupID: UUID? = nil

    // Fixed height for name area: 2 lines of caption text ≈ 28pt
    private let nameHeight: CGFloat = 28

    var body: some View {
        Button(action: onLaunch) {
            VStack(spacing: 4) {
                Image(nsImage: app.icon)
                    .interpolation(.high)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: iconSize, height: iconSize)

                Text(app.name)
                    .font(.caption)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: iconSize + 16, height: nameHeight, alignment: .top)
            }
            .padding(4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(app.isHidden ? 0.4 : 1.0)
        .draggable(app.id)
        .contextMenu { AppContextMenu(app: app, groups: groups, currentGroupID: currentGroupID, onToggleHidden: onToggleHidden, onAddToGroup: onAddToGroup, onRemoveFromGroup: onRemoveFromGroup, onAddToNewGroup: onAddToNewGroup) }
    }
}

// MARK: - Icon Only Grid Cell

struct AppIconOnlyView: View {
    let app: AppItem
    let iconSize: CGFloat
    let onLaunch: () -> Void
    let onToggleHidden: () -> Void
    let groups: [AppGroup]
    let onAddToGroup: (UUID) -> Void
    var onRemoveFromGroup: (() -> Void)? = nil
    var onAddToNewGroup: ((String) -> Void)? = nil
    var currentGroupID: UUID? = nil

    var body: some View {
        Button(action: onLaunch) {
            Image(nsImage: app.icon)
                .interpolation(.high)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: iconSize, height: iconSize)
                .padding(4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(app.isHidden ? 0.4 : 1.0)
        .help(app.name)
        .draggable(app.id)
        .contextMenu { AppContextMenu(app: app, groups: groups, currentGroupID: currentGroupID, onToggleHidden: onToggleHidden, onAddToGroup: onAddToGroup, onRemoveFromGroup: onRemoveFromGroup, onAddToNewGroup: onAddToNewGroup) }
    }
}

// MARK: - List Row

struct AppListRowView: View {
    let app: AppItem
    let onLaunch: () -> Void
    let onToggleHidden: () -> Void
    let groups: [AppGroup]
    let onAddToGroup: (UUID) -> Void
    var onRemoveFromGroup: (() -> Void)? = nil
    var onAddToNewGroup: ((String) -> Void)? = nil
    var currentGroupID: UUID? = nil

    var body: some View {
        Button(action: onLaunch) {
            HStack(spacing: 8) {
                Image(nsImage: app.icon)
                    .interpolation(.high)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)

                Text(app.name)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(app.isHidden ? 0.4 : 1.0)
        .draggable(app.id)
        .contextMenu { AppContextMenu(app: app, groups: groups, currentGroupID: currentGroupID, onToggleHidden: onToggleHidden, onAddToGroup: onAddToGroup, onRemoveFromGroup: onRemoveFromGroup, onAddToNewGroup: onAddToNewGroup) }
    }
}

// MARK: - Shared Context Menu

struct AppContextMenu: View {
    let app: AppItem
    let groups: [AppGroup]
    let currentGroupID: UUID?
    let onToggleHidden: () -> Void
    let onAddToGroup: (UUID) -> Void
    let onRemoveFromGroup: (() -> Void)?
    let onAddToNewGroup: ((String) -> Void)?

    var body: some View {
        Button(app.isHidden ? "Unhide" : "Hide") {
            onToggleHidden()
        }

        let availableGroups = groups.filter { $0.id != currentGroupID }
        if !availableGroups.isEmpty || onAddToNewGroup != nil {
            Menu("Add to Group") {
                ForEach(availableGroups) { group in
                    Button(group.name) {
                        onAddToGroup(group.id)
                    }
                }

                if onAddToNewGroup != nil && !availableGroups.isEmpty {
                    Divider()
                }

                if let onAddToNewGroup {
                    Button("New Group…") {
                        onAddToNewGroup("New Group")
                    }
                }
            }
        } else if let onAddToNewGroup {
            Button("Add to New Group") {
                onAddToNewGroup("New Group")
            }
        }

        if let onRemoveFromGroup {
            Button("Remove from Group", role: .destructive) {
                onRemoveFromGroup()
            }
        }
    }
}
