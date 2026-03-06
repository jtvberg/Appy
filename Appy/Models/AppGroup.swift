import Foundation

// A user-defined group of applications
struct AppGroup: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var appBundleIdentifiers: [String]

    init(id: UUID = UUID(), name: String, appBundleIdentifiers: [String] = []) {
        self.id = id
        self.name = name
        self.appBundleIdentifiers = appBundleIdentifiers
    }
}
