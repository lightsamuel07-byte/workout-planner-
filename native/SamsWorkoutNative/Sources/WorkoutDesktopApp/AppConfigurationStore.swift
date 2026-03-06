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
    var oneRepMaxes: [String: OneRepMaxEntry]
    var bidirectionalSyncConflictPolicy: BidirectionalSyncConflictPolicy

    static let empty = NativeAppConfiguration(
        anthropicAPIKey: "",
        spreadsheetID: "",
        googleAuthHint: "OAuth token path",
        oneRepMaxes: [:],
        bidirectionalSyncConflictPolicy: .preferSheets
    )

    /// Canonical lift names for the three main barbell lifts.
    static let mainLifts = ["Back Squat", "Bench Press", "Deadlift"]

    init(
        anthropicAPIKey: String,
        spreadsheetID: String,
        googleAuthHint: String,
        oneRepMaxes: [String: OneRepMaxEntry],
        bidirectionalSyncConflictPolicy: BidirectionalSyncConflictPolicy = .preferSheets
    ) {
        self.anthropicAPIKey = anthropicAPIKey
        self.spreadsheetID = spreadsheetID
        self.googleAuthHint = googleAuthHint
        self.oneRepMaxes = oneRepMaxes
        self.bidirectionalSyncConflictPolicy = bidirectionalSyncConflictPolicy
    }

    private enum CodingKeys: String, CodingKey {
        case anthropicAPIKey
        case spreadsheetID
        case googleAuthHint
        case oneRepMaxes
        case bidirectionalSyncConflictPolicy
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        anthropicAPIKey = try container.decodeIfPresent(String.self, forKey: .anthropicAPIKey) ?? ""
        spreadsheetID = try container.decodeIfPresent(String.self, forKey: .spreadsheetID) ?? ""
        googleAuthHint = try container.decodeIfPresent(String.self, forKey: .googleAuthHint) ?? "OAuth token path"
        oneRepMaxes = try container.decodeIfPresent([String: OneRepMaxEntry].self, forKey: .oneRepMaxes) ?? [:]
        bidirectionalSyncConflictPolicy =
            try container.decodeIfPresent(BidirectionalSyncConflictPolicy.self, forKey: .bidirectionalSyncConflictPolicy) ?? .preferSheets
    }
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
