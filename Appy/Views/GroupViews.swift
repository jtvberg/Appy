import SwiftUI

// MARK: - Auto-selecting TextField

struct SelectAllTextField: NSViewRepresentable {
    @Binding var text: String
    var onCommit: () -> Void
    var fontSize: CGFloat = NSFont.systemFontSize(for: .mini)
    var alignment: NSTextAlignment = .center

    func makeNSView(context: Context) -> NSTextField {
        let tf = NSTextField()
        tf.isBordered = false
        tf.backgroundColor = .clear
        tf.focusRingType = .none
        tf.alignment = alignment
        tf.font = NSFont.systemFont(ofSize: fontSize)
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

    private let nameHeight: CGFloat = 28

    var body: some View {
        VStack(spacing: 4) {
            Button(action: action) {
                Image(systemName: "folder.fill")
                    .resizable()
                    .scaledToFit()
                    .padding(iconSize * 0.1)
                    .frame(width: iconSize, height: iconSize)
                    .foregroundStyle(isDropTargeted ? .blue : .secondary)
            }
            .buttonStyle(.plain)

            if isEditing {
                SelectAllTextField(
                    text: $editName,
                    onCommit: commitRename,
                    fontSize: NSFont.systemFontSize(for: .mini),
                    alignment: .center
                )
                .frame(width: iconSize + 16, height: nameHeight)
                .onExitCommand { renamingGroupID = nil }
                .onAppear { editName = name }
            } else {
                Button(action: action) {
                    Text(name)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .frame(width: iconSize + 16, height: nameHeight, alignment: .top)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
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
            for appID in items { onDropApp(appID) }
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
    let iconSize: CGFloat
    let isExpanded: Bool
    let groupID: UUID
    let onToggle: () -> Void
    let onDropApp: (String) -> Void
    var onRename: ((String) -> Void)? = nil
    @Binding var renamingGroupID: UUID?

    @State private var isDropTargeted = false
    @State private var editName = ""

    private var isEditing: Bool { renamingGroupID == groupID }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.system(size: iconSize * 0.45, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: iconSize * 0.5)

            Image(systemName: "folder.fill")
                .resizable()
                .scaledToFit()
                .frame(width: iconSize, height: iconSize)
                .foregroundStyle(isDropTargeted ? .blue : .secondary)

            if isEditing {
                SelectAllTextField(
                    text: $editName,
                    onCommit: commitRename,
                    fontSize: max(iconSize * 0.55, 11),
                    alignment: .left
                )
                .onExitCommand { renamingGroupID = nil }
                .onAppear { editName = name }
            } else {
                Text(name)
                    .font(.system(size: max(iconSize * 0.55, 11), weight: .semibold))
            }

            Spacer()
            Text("\(appCount)")
                .font(.system(size: max(iconSize * 0.45, 9)))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            if !isEditing { onToggle() }
        }
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
    let listIconSize: CGFloat
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
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.semibold))
                        Text(groupName)
                            .font(.body.weight(.medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

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
                        iconSize: listIconSize,
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
