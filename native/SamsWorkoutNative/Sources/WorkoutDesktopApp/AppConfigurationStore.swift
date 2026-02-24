import Foundation

struct OneRepMaxEntry: Codable, Equatable {
    var valueKG: Double
    var lastUpdated: Date

    static let empty = OneRepMaxEntry(valueKG: 0, lastUpdated: .distantPast)
}

struct NativeAppConfiguration: Codable, Equatable {
    var anthropicAPIKey: String
    var spreadsheetID: String
    var googleAuthHint: String
    var localAppPassword: String
    var oneRepMaxes: [String: OneRepMaxEntry]

    static let empty = NativeAppConfiguration(
        anthropicAPIKey: "",
        spreadsheetID: "",
        googleAuthHint: "OAuth token path",
        localAppPassword: "",
        oneRepMaxes: [:]
    )

    /// Canonical lift names for the three main barbell lifts.
    static let mainLifts = ["Back Squat", "Bench Press", "Deadlift"]
}

protocol AppConfigurationStore {
    func load() -> NativeAppConfiguration
    func save(_ config: NativeAppConfiguration) throws
}

struct FileAppConfigurationStore: AppConfigurationStore {
    private let fileURL: URL

    init(fileURL: URL = FileAppConfigurationStore.defaultURL()) {
        self.fileURL = fileURL
    }

    static func defaultURL() -> URL {
        let appSupport = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/SamsWorkoutApp", isDirectory: true)
        return appSupport.appendingPathComponent("config.json")
    }

    func load() -> NativeAppConfiguration {
        guard let data = try? Data(contentsOf: fileURL) else {
            return .empty
        }

        return (try? JSONDecoder().decode(NativeAppConfiguration.self, from: data)) ?? .empty
    }

    func save(_ config: NativeAppConfiguration) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(config)
        try data.write(to: fileURL, options: [.atomic])
    }
}
