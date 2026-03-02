import SwiftUI

struct OptionsView: View {
    @Environment(PreferencesManager.self) private var prefs
    @Environment(AppScannerService.self) private var scanner
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var prefs = prefs

        VStack(spacing: 0) {
            // Title
            HStack {
                Text("Options")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // MARK: Icon Size
                    sectionHeader("Icon Size")
                    HStack {
                        Image(systemName: "square.grid.4x3.fill")
                            .font(.caption)
                        Slider(value: $prefs.iconSize, in: 32...128, step: 8)
                        Image(systemName: "square.grid.2x2.fill")
                            .font(.title3)
                    }

                    // MARK: List Size
                    sectionHeader("List Size")
                    HStack {
                        Image(systemName: "list.bullet")
                            .font(.caption)
                        Slider(value: $prefs.listIconSize, in: 16...48, step: 4)
                        Image(systemName: "list.bullet")
                            .font(.title3)
                    }

                    // MARK: Hidden Apps
                    hiddenAppsSection

                    Spacer(minLength: 8)
                }
                .padding(16)
            }
        }
        .frame(width: 320, height: 360)
    }

    // MARK: - Sections

    @ViewBuilder
    private var hiddenAppsSection: some View {
        @Bindable var prefs = prefs

        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Hidden Apps")

            Toggle("Show Hidden Apps", isOn: $prefs.showHidden)
                .toggleStyle(.switch)

            if !prefs.hiddenAppIDs.isEmpty {
                let hiddenApps = scanner.apps.filter { prefs.hiddenAppIDs.contains($0.id) }
                ForEach(hiddenApps) { app in
                    HStack {
                        Image(nsImage: app.icon)
                            .resizable()
                            .frame(width: 20, height: 20)
                        Text(app.name)
                            .font(.caption)
                        Spacer()
                        Button("Unhide") {
                            prefs.toggleHidden(app)
                        }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(.blue)
                    }
                }
            } else {
                Text("No hidden apps")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
    }
}
