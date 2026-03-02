import SwiftUI

// MARK: - Auto-selecting TextField

struct SelectAllTextField: NSViewRepresentable {
    @Binding var text: String
    var onCommit: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let tf = NSTextField()
        tf.isBordered = false
        tf.backgroundColor = .clear
        tf.focusRingType = .none
        tf.delegate = context.coordinator
        return tf
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        // Select all + focus on first appear
        if !context.coordinator.didFocus {
            context.coordinator.didFocus = true
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
                nsView.currentEditor()?.selectAll(nil)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, NSTextFieldDelegate {
        let parent: SelectAllTextField
        var didFocus = false
        init(_ parent: SelectAllTextField) { self.parent = parent }

        func controlTextDidChange(_ obj: Notification) {
            guard let tf = obj.object as? NSTextField else { return }
            parent.text = tf.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
            if sel == #selector(NSResponder.insertNewline(_:)) {
                parent.onCommit()
                return true
            }
            return false
        }
    }
}

// MARK: - Group Header (grid mode) — compact, supports drop + inline rename

struct GroupHeaderView: View {
    let name: String
    let appCount: Int
    let iconSize: CGFloat
    let groupID: UUID
    let action: () -> Void
    let onDropApp: (String) -> Void
    var onRename: ((String) -> Void)? = nil
    @Binding var renamingGroupID: UUID?

    @State private var isDropTargeted = false
    @State private var editName = ""

    private var isEditing: Bool { renamingGroupID == groupID }

    var body: some View {
        VStack(spacing: 2) {
            Button(action: action) {
                Image(systemName: "folder.fill")
                    .font(.system(size: min(iconSize * 0.35, 28)))
                    .foregroundStyle(isDropTargeted ? .blue : .secondary)
            }
            .buttonStyle(.plain)

            if isEditing {
                SelectAllTextField(text: $editName, onCommit: commitRename)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.center)
                    .frame(width: iconSize)
                    .onExitCommand { renamingGroupID = nil }
                    .onAppear { editName = name }
            } else {
                Button(action: action) {
                    Text(name)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: iconSize, height: iconSize * 0.7)
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isDropTargeted ? Color.accentColor.opacity(0.15) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isDropTargeted ? Color.accentColor : Color.clear, lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { items, _ in
            for appID in items {
                onDropApp(appID)
            }
            return !items.isEmpty
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
    }

    private func commitRename() {
        let trimmed = editName.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            onRename?(trimmed)
        }
        renamingGroupID = nil
    }
}

// MARK: - Group List Row Header — compact, supports drop + inline rename

struct GroupListHeaderView: View {
    let name: String
    let appCount: Int
    let groupID: UUID
    let onDropApp: (String) -> Void
    var onRename: ((String) -> Void)? = nil
    @Binding var renamingGroupID: UUID?

    @State private var isDropTargeted = false
    @State private var editName = ""

    private var isEditing: Bool { renamingGroupID == groupID }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder.fill")
                .foregroundStyle(isDropTargeted ? .blue : .secondary)
                .font(.caption)

            if isEditing {
                SelectAllTextField(text: $editName, onCommit: commitRename)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .onExitCommand { renamingGroupID = nil }
                    .onAppear { editName = name }
            } else {
                Text(name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }

            Spacer()
            Text("\(appCount)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isDropTargeted ? Color.accentColor.opacity(0.15) : Color.clear)
        )
        .dropDestination(for: String.self) { items, _ in
            for appID in items {
                onDropApp(appID)
            }
            return !items.isEmpty
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
    }

    private func commitRename() {
        let trimmed = editName.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            onRename?(trimmed)
        }
        renamingGroupID = nil
    }
}

// MARK: - Group Expanded View (replaces main content)

struct GroupExpandedView: View {
    let groupName: String
    let apps: [AppItem]
    let viewMode: ViewMode
    let iconSize: CGFloat
    let groups: [AppGroup]
    var currentGroupID: UUID? = nil
    let onLaunch: (AppItem) -> Void
    let onToggleHidden: (AppItem) -> Void
    let onAddToGroup: (AppItem, UUID) -> Void
    let onRemoveFromGroup: ((AppItem) -> Void)?
    var onAddToNewGroup: ((AppItem, String) -> Void)? = nil
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Compact back-nav header
            HStack(spacing: 4) {
                Button(action: onBack) {
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.left")
                        Text(groupName)
                            .lineLimit(1)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 3)

            Divider()

            ScrollView {
                appContent
                    .padding(8)
            }
        }
    }

    @ViewBuilder
    private var appContent: some View {
        switch viewMode {
        case .iconWithName:
            LazyVGrid(columns: gridColumns(iconSize: iconSize + 24), spacing: 8) {
                ForEach(apps) { app in
                    AppIconNameView(
                        app: app,
                        iconSize: iconSize,
                        onLaunch: { onLaunch(app) },
                        onToggleHidden: { onToggleHidden(app) },
                        groups: groups,
                        onAddToGroup: { groupID in onAddToGroup(app, groupID) },
                        onRemoveFromGroup: onRemoveFromGroup != nil ? { onRemoveFromGroup?(app) } : nil,
                        onAddToNewGroup: onAddToNewGroup != nil ? { name in onAddToNewGroup?(app, name) } : nil,
                        currentGroupID: currentGroupID
                    )
                }
            }
        case .iconOnly:
            LazyVGrid(columns: gridColumns(iconSize: iconSize + 12), spacing: 8) {
                ForEach(apps) { app in
                    AppIconOnlyView(
                        app: app,
                        iconSize: iconSize,
                        onLaunch: { onLaunch(app) },
                        onToggleHidden: { onToggleHidden(app) },
                        groups: groups,
                        onAddToGroup: { groupID in onAddToGroup(app, groupID) },
                        onRemoveFromGroup: onRemoveFromGroup != nil ? { onRemoveFromGroup?(app) } : nil,
                        onAddToNewGroup: onAddToNewGroup != nil ? { name in onAddToNewGroup?(app, name) } : nil,
                        currentGroupID: currentGroupID
                    )
                }
            }
        case .list:
            LazyVStack(spacing: 2) {
                ForEach(apps) { app in
                    AppListRowView(
                        app: app,
                        onLaunch: { onLaunch(app) },
                        onToggleHidden: { onToggleHidden(app) },
                        groups: groups,
                        onAddToGroup: { groupID in onAddToGroup(app, groupID) },
                        onRemoveFromGroup: onRemoveFromGroup != nil ? { onRemoveFromGroup?(app) } : nil,
                        onAddToNewGroup: onAddToNewGroup != nil ? { name in onAddToNewGroup?(app, name) } : nil,
                        currentGroupID: currentGroupID
                    )
                }
            }
        }
    }

    private func gridColumns(iconSize: CGFloat) -> [GridItem] {
        [GridItem(.adaptive(minimum: iconSize), spacing: 4)]
    }
}
