import Foundation
import WorkoutCore
import WorkoutIntegrations
import WorkoutPersistence

final class ThreadSafeBox<T>: @unchecked Sendable {
    private var value: T
    private let lock = NSLock()

    init(_ value: T) {
        self.value = value
    }

    func get() -> T {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set(_ newValue: T) {
        lock.lock()
        defer { lock.unlock() }
        value = newValue
    }
}

enum LiveGatewayError: LocalizedError {
    case setupIncomplete
    case missingSpreadsheetID
    case invalidSpreadsheetID
    case missingAuthToken
    case noWeeklyPlanSheets
    case noPlanData
    case noWorkoutForToday
    case dbSyncFailedAfterSheetsWrite(underlyingError: String)

    var errorDescription: String? {
        switch self {
        case .setupIncomplete:
            return "Setup is incomplete. Add Anthropic API key and Spreadsheet ID first."
        case .missingSpreadsheetID:
            return "Google Spreadsheet ID is required."
        case .invalidSpreadsheetID:
            return "Google Spreadsheet ID format is invalid. Expected a 44-character alphanumeric string."
        case .missingAuthToken:
            return "Google auth token is missing. Set a token path in setup and re-auth."
        case .noWeeklyPlanSheets:
            return "No weekly plan sheets were found."
        case .noPlanData:
            return "No plan data was found in local files or Google Sheets."
        case .noWorkoutForToday:
            return "No workout found for today in the latest weekly sheet."
        case .dbSyncFailedAfterSheetsWrite(let underlyingError):
            return "Sheets updated but local DB sync failed: \(underlyingError). Try Rebuild DB Cache to re-sync."
        }
    }
}

struct LiveAppGateway: NativeAppGateway {
    enum PlanWriteMode {
        case normal
        case localOnly
    }

    let integrations: IntegrationsFacade
    let configStore: AppConfigurationStore
    let bootstrap: PersistenceBootstrap
    let fileManager: FileManager
    let nowProvider: () -> Date
    let planWriteMode: PlanWriteMode
    let cachedDatabase: ThreadSafeBox<WorkoutDatabase?>

    init(
        integrations: IntegrationsFacade = IntegrationsFacade(),
        configStore: AppConfigurationStore = FileAppConfigurationStore(),
        bootstrap: PersistenceBootstrap = PersistenceBootstrap(),
        fileManager: FileManager = .default,
        nowProvider: @escaping () -> Date = Date.init,
        planWriteMode: PlanWriteMode = .normal
    ) {
        self.integrations = integrations
        self.configStore = configStore
        self.bootstrap = bootstrap
        self.fileManager = fileManager
        self.nowProvider = nowProvider
        self.planWriteMode = planWriteMode
        self.cachedDatabase = ThreadSafeBox(nil)
    }

    func initialRoute() -> AppRoute {
        .dashboard
    }

    func generatePlan(input: PlanGenerationInput) async throws -> String {
        try await generatePlan(input: input, onProgress: nil)
    }

    func loadDashboardDays() -> [DayPlanSummary] {
        if let snapshot = try? loadLocalPlanSnapshot(), !snapshot.days.isEmpty {
            return snapshot.days.map { day in
                DayPlanSummary(
                    id: day.dayLabel.lowercased(),
                    title: day.dayLabel.uppercased(),
                    source: day.source,
                    blocks: day.exercises.count
                )
            }
        }

        return [
            DayPlanSummary(id: "monday", title: "MONDAY", source: .localCache, blocks: 0),
            DayPlanSummary(id: "tuesday", title: "TUESDAY", source: .localCache, blocks: 0),
            DayPlanSummary(id: "wednesday", title: "WEDNESDAY", source: .localCache, blocks: 0),
            DayPlanSummary(id: "thursday", title: "THURSDAY", source: .localCache, blocks: 0),
            DayPlanSummary(id: "friday", title: "FRIDAY", source: .localCache, blocks: 0),
            DayPlanSummary(id: "saturday", title: "SATURDAY", source: .localCache, blocks: 0),
            DayPlanSummary(id: "sunday", title: "SUNDAY", source: .localCache, blocks: 0),
        ]
    }

}

extension LiveAppGateway {
    func requireGenerationSetup() throws -> NativeAppConfiguration {
        let config = configStore.load()
        let key = config.anthropicAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let sheet = config.spreadsheetID.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty || sheet.isEmpty {
            throw LiveGatewayError.setupIncomplete
        }
        if !Self.isValidSpreadsheetID(sheet) {
            throw LiveGatewayError.invalidSpreadsheetID
        }
        return config
    }

    func requireSheetsSetup() throws -> NativeAppConfiguration {
        let config = configStore.load()
        let sheet = config.spreadsheetID.trimmingCharacters(in: .whitespacesAndNewlines)
        if sheet.isEmpty {
            throw LiveGatewayError.missingSpreadsheetID
        }
        if !Self.isValidSpreadsheetID(sheet) {
            throw LiveGatewayError.invalidSpreadsheetID
        }
        return config
    }

    static func isValidSpreadsheetID(_ value: String) -> Bool {
        // Google Spreadsheet IDs are typically 44 characters of alphanumeric, hyphens, and underscores.
        let pattern = #"^[A-Za-z0-9_-]{20,}$"#
        return value.range(of: pattern, options: .regularExpression) != nil
    }

    func loadOneRepMaxesFromConfig() -> [String: Double] {
        let config = configStore.load()
        var result: [String: Double] = [:]
        for (lift, entry) in config.oneRepMaxes where entry.valueKG >= 20 {
            result[lift] = entry.valueKG
        }
        return result
    }

    func modeStatusText(config: NativeAppConfiguration) -> String {
        let authHint = config.googleAuthHint.trimmingCharacters(in: .whitespacesAndNewlines)
        let authText: String
        if authHint.isEmpty {
            authText = "Google auth not configured"
        } else if authHint.lowercased().hasPrefix("bearer ") {
            authText = "Google auth via bearer token hint"
        } else if authHint.hasPrefix("ya29.") || authHint.hasPrefix("eyJ") {
            authText = "Google auth via inline token hint"
        } else if fileManager.fileExists(atPath: authHint) {
            authText = "Google auth via OAuth token: \(authHint)"
        } else {
            authText = "Google auth hint path not found: \(authHint)"
        }

        let anthroConfigured = !config.anthropicAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let anthropicText = anthroConfigured ? "Anthropic key configured in app setup" : "Anthropic key missing in app setup"

        return "Local native mode with Google Sheets as source of truth (\(authText); \(anthropicText))"
    }

    func appSupportDirectoryURL() -> URL {
        URL(fileURLWithPath: integrations.authSessionManager.defaultAppSupportDirectory(), isDirectory: true)
    }

    func outputDirectoryURL() throws -> URL {
        let directory = appSupportDirectoryURL().appendingPathComponent("output", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func dataDirectoryURL() throws -> URL {
        let directory = appSupportDirectoryURL().appendingPathComponent("data", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func workoutDatabasePath() throws -> String {
        try dataDirectoryURL().appendingPathComponent("workout_history.db").path
    }

    func makeSheetsClient(config: NativeAppConfiguration) async throws -> GoogleSheetsClient {
        let token = try await resolveAuthToken(config: config)
        return integrations.makeGoogleSheetsClient(
            spreadsheetID: config.spreadsheetID,
            authToken: token
        )
    }

    func resolveAuthToken(config: NativeAppConfiguration) async throws -> String {
        let hint = config.googleAuthHint.trimmingCharacters(in: .whitespacesAndNewlines)
        if !hint.isEmpty {
            if hint.lowercased().hasPrefix("bearer ") {
                let token = String(hint.dropFirst("Bearer ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !token.isEmpty {
                    return token
                }
            }

            if hint.hasPrefix("ya29.") || hint.hasPrefix("eyJ") {
                return hint
            }

            if fileManager.fileExists(atPath: hint) {
                return try await integrations.authSessionManager.resolveOAuthAccessToken(tokenFilePath: hint)
            }

            if let token = parseAccessTokenFromJSONString(hint) {
                return token
            }
        }

        let env = ProcessInfo.processInfo.environment
        if let envToken = env["GOOGLE_OAUTH_ACCESS_TOKEN"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !envToken.isEmpty {
            return envToken
        }

        let authEnv = integrations.authSessionManager.loadEnvironment(from: env)
        if let tokenPath = authEnv.oauthTokenPath, fileManager.fileExists(atPath: tokenPath) {
            return try await integrations.authSessionManager.resolveOAuthAccessToken(tokenFilePath: tokenPath)
        }

        throw LiveGatewayError.missingAuthToken
    }

    func parseAccessTokenFromJSONString(_ raw: String) -> String? {
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = (object["access_token"] as? String) ?? (object["token"] as? String),
              !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }
        return token
    }

    func sanitizedSheetReferenceDate(_ referenceDate: Date) -> (date: Date, wasSanitized: Bool) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let now = nowProvider()
        let currentYear = calendar.component(.year, from: now)
        let referenceYear = calendar.component(.year, from: referenceDate)
        let yearDelta = abs(referenceYear - currentYear)
        if yearDelta > 2 {
            return (now, true)
        }
        return (referenceDate, false)
    }

    func weeklySheetName(referenceDate: Date) -> String {
        let safeReference = sanitizedSheetReferenceDate(referenceDate).date
        let calendar = Calendar(identifier: .gregorian)
        let weekday = calendar.component(.weekday, from: safeReference)
        // On weekends (Sat=7, Sun=1) we're planning ahead — advance to next week's Monday.
        // On Mon–Fri, back up to this week's Monday.
        let rawOffset = (weekday + 5) % 7  // 0=Mon, 1=Tue, …, 5=Sat, 6=Sun
        let mondayOffset = (weekday == 7 || weekday == 1) ? (7 - rawOffset) : -rawOffset
        let monday = calendar.date(byAdding: .day, value: mondayOffset, to: safeReference) ?? safeReference
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "M/d/yyyy"
        return "Weekly Plan (\(formatter.string(from: monday)))"
    }

    func dayName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }

    func isoDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    func isoDateTime(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    func archiveTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter.string(from: date)
    }

}

extension LiveAppGateway {
    static func testPreferredWeeklyPlanSheetName(_ sheetNames: [String], referenceDate: Date) -> String? {
        preferredWeeklyPlanSheetName(sheetNames, referenceDate: referenceDate)
    }

    static func testPreferredCandidate(
        _ candidates: [(String, Date)],
        referenceDate: Date,
        nearWindowDays: Int,
        fallbackToMostRecent: Bool
    ) -> (String, Date)? {
        preferredCandidate(
            candidates,
            referenceDate: referenceDate,
            nearWindowDays: nearWindowDays,
            fallbackToMostRecent: fallbackToMostRecent
        )
    }

    static func testParseLocalPlanDate(from fileName: String) -> Date? {
        parseLocalPlanDate(from: fileName)
    }

    static func testParseExistingLog(_ raw: String) -> (String, String, String) {
        let parsed = PlanTextParser.parseExistingLog(raw)
        return (parsed.performance, parsed.rpe, parsed.notes)
    }

    static func testSelectLoggerWorkout(_ workouts: [SheetDayWorkout], todayName: String) -> SheetDayWorkout? {
        PlanTextParser.selectLoggerWorkout(workouts: workouts, todayName: todayName)
    }

    static func testSanitizedSheetReferenceDate(referenceDate: Date, nowDate: Date) -> (Date, Bool) {
        let gateway = LiveAppGateway(nowProvider: { nowDate }, planWriteMode: .localOnly)
        let result = gateway.sanitizedSheetReferenceDate(referenceDate)
        return (result.date, result.wasSanitized)
    }

    static func testMarkdownDaysToPlanDays(_ planText: String) -> [PlanDayDetail] {
        PlanTextParser.markdownDaysToPlanDays(planText: planText, source: .localCache)
    }

    static func testParsePlanToSheetRows(planText: String, dayLabel: String) -> [[String]] {
        PlanTextParser.parsePlanToSheetRows(planText: planText, dayLabel: dayLabel)
    }

    static func testParseSelectedExercises(from text: String) -> [String: [String]] {
        let gateway = LiveAppGateway(planWriteMode: .localOnly)
        return gateway.parseSelectedExercises(from: text)
    }
}
