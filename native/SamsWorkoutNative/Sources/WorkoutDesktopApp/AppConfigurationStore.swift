import Foundation

struct NativeAppConfiguration: Codable, Equatable {
    var anthropicAPIKey: String
    var spreadsheetID: String
    var googleAuthHint: String
    var localAppPassword: String

    static let empty = NativeAppConfiguration(
        anthropicAPIKey: "",
        spreadsheetID: "",
        googleAuthHint: "OAuth token path",
        localAppPassword: ""
    )
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
