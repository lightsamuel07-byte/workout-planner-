import Foundation
import WorkoutCore

public struct SupplementalSheetExercise: Equatable, Sendable {
    public let block: String
    public let exercise: String
    public let sets: String
    public let reps: String
    public let load: String
    public let rest: String
    public let notes: String
    public let log: String

    public init(block: String, exercise: String, sets: String, reps: String, load: String, rest: String, notes: String, log: String) {
        self.block = block
        self.exercise = exercise
        self.sets = sets
        self.reps = reps
        self.load = load
        self.rest = rest
        self.notes = notes
        self.log = log
    }
}

public struct ExerciseLogWrite: Equatable, Sendable {
    public let exercise: String
    public let log: String

    public init(exercise: String, log: String) {
        self.exercise = exercise
        self.log = log
    }
}

public struct ValueRangeUpdate: Equatable, Sendable {
    public let range: String
    public let values: [[String]]

    public init(range: String, values: [[String]]) {
        self.range = range
        self.values = values
    }
}

public struct SheetDayExercise: Equatable, Sendable {
    public let sourceRow: Int
    public let block: String
    public let exercise: String
    public let sets: String
    public let reps: String
    public let load: String
    public let rest: String
    public let notes: String
    public let log: String

    public init(
        sourceRow: Int,
        block: String,
        exercise: String,
        sets: String,
        reps: String,
        load: String,
        rest: String,
        notes: String,
        log: String
    ) {
        self.sourceRow = sourceRow
        self.block = block
        self.exercise = exercise
        self.sets = sets
        self.reps = reps
        self.load = load
        self.rest = rest
        self.notes = notes
        self.log = log
    }
}

public struct SheetDayWorkout: Equatable, Sendable {
    public let dayLabel: String
    public let dayName: String
    public let exercises: [SheetDayExercise]

    public init(dayLabel: String, dayName: String, exercises: [SheetDayExercise]) {
        self.dayLabel = dayLabel
        self.dayName = dayName
        self.exercises = exercises
    }
}

private struct SheetsValuesResponse: Decodable {
    let values: [[String]]?
}

private struct SheetsMetadataResponse: Decodable {
    struct SheetContainer: Decodable {
        struct SheetProperties: Decodable {
            let title: String
            let sheetId: Int?
        }

        let properties: SheetProperties
    }

    let sheets: [SheetContainer]?
}

private struct BatchUpdateBody: Encodable {
    struct BatchData: Encodable {
        let range: String
        let values: [[String]]
    }

    let valueInputOption: String
    let data: [BatchData]
}

private let weeklyPlanTitlePatterns: [NSRegularExpression] = [
    integrationsMakeRegex("^Weekly Plan \\((\\d{1,2})/(\\d{1,2})/(\\d{4})\\)$"),
    integrationsMakeRegex("^\\(Weekly Plan\\)\\s*(\\d{1,2})/(\\d{1,2})/(\\d{4})$"),
]
private let sheetDayNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
private let sheetRangePathAllowedCharacters: CharacterSet = {
    var allowed = CharacterSet.urlPathAllowed
    allowed.remove(charactersIn: "/")
    return allowed
}()

public struct GoogleSheetsClient: Sendable {
    public let spreadsheetID: String
    private let authToken: String
    private let httpClient: HTTPClient

    public init(
        spreadsheetID: String,
        authToken: String,
        httpClient: HTTPClient = URLSessionHTTPClient()
    ) {
        self.spreadsheetID = spreadsheetID
        self.authToken = authToken
        self.httpClient = httpClient
    }

    public static func enforceEightColumnSchema(_ row: [String]) -> [String] {
        if row.count == 8 {
            return row
        }

        if row.count > 8 {
            return Array(row.prefix(8))
        }

        var padded = row
        padded.append(contentsOf: Array(repeating: "", count: 8 - row.count))
        return padded
    }

    public static func parseWeeklyPlanSheetDate(_ title: String) -> Date? {
        for pattern in weeklyPlanTitlePatterns {
            if let match = pattern.firstMatch(in: title, options: [], range: integrationsFullRange(of: title)),
               let monthRange = Range(match.range(at: 1), in: title),
               let dayRange = Range(match.range(at: 2), in: title),
               let yearRange = Range(match.range(at: 3), in: title),
               let month = Int(title[monthRange]),
               let day = Int(title[dayRange]),
               let year = Int(title[yearRange]) {
                var components = DateComponents()
                components.year = year
                components.month = month
                components.day = day
                components.calendar = Calendar(identifier: .gregorian)
                return components.date
            }
        }

        return nil
    }

    public static func allWeeklyPlanSheetsSorted(_ sheetNames: [String]) -> [String] {
        sheetNames
            .compactMap { name -> (String, Date)? in
                guard let date = parseWeeklyPlanSheetDate(name) else {
                    return nil
                }
                return (name, date)
            }
            .sorted { $0.1 < $1.1 }
            .map { $0.0 }
    }

    public static func mostRecentWeeklyPlanSheet(_ sheetNames: [String]) -> String? {
        allWeeklyPlanSheetsSorted(sheetNames).last
    }

    public static func parseSupplementalWorkouts(values: [[String]]) -> [String: [SupplementalSheetExercise]] {
        var supplemental: [String: [SupplementalSheetExercise]] = [
            "Tuesday": [],
            "Thursday": [],
            "Saturday": [],
        ]

        var currentDay: String?
        var inExerciseSection = false

        for row in values {
            if row.isEmpty {
                continue
            }

            let firstCol = row[0]
            let upper = firstCol.uppercased()
            let anyDayHeader = ["MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY", "SUNDAY"].contains {
                upper.contains($0)
            }

            if upper.contains("TUESDAY") || upper.contains("THURSDAY") || upper.contains("SATURDAY") {
                if upper.contains("TUESDAY") {
                    currentDay = "Tuesday"
                } else if upper.contains("THURSDAY") {
                    currentDay = "Thursday"
                } else {
                    currentDay = "Saturday"
                }
                inExerciseSection = false
                continue
            }

            if anyDayHeader {
                currentDay = nil
                inExerciseSection = false
                continue
            }

            if firstCol.lowercased() == "block", currentDay != nil {
                inExerciseSection = true
                continue
            }

            if inExerciseSection, let currentDay, row.count >= 2 {
                let normalized = enforceEightColumnSchema(row)
                let exercise = SupplementalSheetExercise(
                    block: normalized[0],
                    exercise: normalized[1],
                    sets: normalized[2],
                    reps: normalized[3],
                    load: normalized[4],
                    rest: normalized[5],
                    notes: normalized[6],
                    log: normalized[7]
                )

                if !exercise.exercise.isEmpty && exercise.exercise.lowercased() != "exercise" {
                    supplemental[currentDay, default: []].append(exercise)
                }
            }
        }

        return supplemental
    }

    public static func buildColumnHLogWrites(
        workoutDate: String,
        sheetValues: [[String]],
        logs: [ExerciseLogWrite],
        sheetName: String
    ) -> [ValueRangeUpdate] {
        if sheetValues.isEmpty || logs.isEmpty {
            return []
        }

        var dateRow: Int?
        for (index, row) in sheetValues.enumerated() {
            if row.count > 0, row[0].contains(workoutDate) {
                dateRow = index
                break
            }
        }

        guard let dateRow else {
            return []
        }

        var updates: [ValueRangeUpdate] = []
        var logIndex = 0
        var currentRow = dateRow + 1

        while currentRow < sheetValues.count, logIndex < logs.count {
            let row = sheetValues[currentRow]

            if row.isEmpty || (row.count > 0 && ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"].contains(where: { row[0].contains($0) })) {
                break
            }

            if row.count > 1 {
                let exerciseName = row[1].trimmingCharacters(in: .whitespacesAndNewlines)
                let logEntry = logs[logIndex]
                let rowExerciseLower = exerciseName.lowercased()
                let logExerciseLower = logEntry.exercise.lowercased()

                if !exerciseName.isEmpty,
                   (logExerciseLower.contains(rowExerciseLower) || rowExerciseLower.contains(logExerciseLower)) {
                    if !logEntry.log.isEmpty {
                        updates.append(
                            ValueRangeUpdate(
                                range: "'\(sheetName)'!H\(currentRow + 1)",
                                values: [[logEntry.log]]
                            )
                        )
                    }
                    logIndex += 1
                }
            }

            currentRow += 1
        }

        return updates
    }

    public static func parseDayWorkouts(values: [[String]]) -> [SheetDayWorkout] {
        var workouts: [SheetDayWorkout] = []
        var currentDayLabel: String?
        var currentDayName = ""
        var currentExercises: [SheetDayExercise] = []

        func flushCurrent() {
            guard let dayLabel = currentDayLabel else {
                return
            }
            workouts.append(
                SheetDayWorkout(
                    dayLabel: dayLabel,
                    dayName: currentDayName,
                    exercises: currentExercises
                )
            )
            currentDayLabel = nil
            currentDayName = ""
            currentExercises = []
        }

        for (index, row) in values.enumerated() {
            let normalized = enforceEightColumnSchema(row)
            let firstCol = normalized[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let secondCol = normalized[1].trimmingCharacters(in: .whitespacesAndNewlines)
            let dayName = dayNameFromLabel(firstCol)

            if let dayName, secondCol.isEmpty {
                flushCurrent()
                currentDayLabel = firstCol
                currentDayName = dayName
                continue
            }

            guard currentDayLabel != nil else {
                continue
            }

            if firstCol.lowercased() == "block", secondCol.lowercased() == "exercise" {
                continue
            }

            if secondCol.isEmpty || secondCol.lowercased() == "exercise" {
                continue
            }

            currentExercises.append(
                SheetDayExercise(
                    sourceRow: index + 1,
                    block: firstCol,
                    exercise: secondCol,
                    sets: normalized[2],
                    reps: normalized[3],
                    load: normalized[4],
                    rest: normalized[5],
                    notes: normalized[6],
                    log: normalized[7]
                )
            )
        }

        flushCurrent()
        return workouts
    }

    public static func dayNameFromLabel(_ label: String) -> String? {
        let upper = label.uppercased()
        for day in sheetDayNames where upper.contains(day.uppercased()) {
            return day
        }
        return nil
    }

    public func fetchSheetNames() async throws -> [String] {
        let url = URL(string: "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetID)")!
        let request = HTTPRequest(
            method: "GET",
            url: url,
            headers: ["Authorization": "Bearer \(authToken)"]
        )

        let response = try await httpClient.send(request)
        guard (200...299).contains(response.statusCode) else {
            throw HTTPClientError.invalidStatus(response.statusCode, String(data: response.body, encoding: .utf8) ?? "")
        }

        let decoded = try JSONDecoder().decode(SheetsMetadataResponse.self, from: response.body)
        return decoded.sheets?.map { $0.properties.title } ?? []
    }

    public func readSheetAtoH(sheetName: String) async throws -> [[String]] {
        let encodedRange = Self.encodeSheetRangePath("'\(sheetName)'!A:H")
        let url = URL(string: "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetID)/values/\(encodedRange)")!
        let request = HTTPRequest(
            method: "GET",
            url: url,
            headers: ["Authorization": "Bearer \(authToken)"]
        )

        let response = try await httpClient.send(request)
        guard (200...299).contains(response.statusCode) else {
            throw HTTPClientError.invalidStatus(response.statusCode, String(data: response.body, encoding: .utf8) ?? "")
        }

        let decoded = try JSONDecoder().decode(SheetsValuesResponse.self, from: response.body)
        return (decoded.values ?? []).map { Self.enforceEightColumnSchema($0) }
    }

    public func batchUpdateLogs(_ updates: [ValueRangeUpdate]) async throws {
        if updates.isEmpty {
            return
        }

        let body = BatchUpdateBody(
            valueInputOption: "USER_ENTERED",
            data: updates.map { BatchUpdateBody.BatchData(range: $0.range, values: $0.values) }
        )

        let url = URL(string: "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetID)/values:batchUpdate")!
        let request = HTTPRequest(
            method: "POST",
            url: url,
            headers: [
                "Authorization": "Bearer \(authToken)",
                "Content-Type": "application/json",
            ],
            body: try JSONEncoder().encode(body)
        )

        let response = try await httpClient.send(request)
        guard (200...299).contains(response.statusCode) else {
            throw HTTPClientError.invalidStatus(response.statusCode, String(data: response.body, encoding: .utf8) ?? "")
        }
    }

    public func fetchSheetNameToIDMap() async throws -> [String: Int] {
        let url = URL(string: "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetID)")!
        let request = HTTPRequest(
            method: "GET",
            url: url,
            headers: ["Authorization": "Bearer \(authToken)"]
        )

        let response = try await httpClient.send(request)
        guard (200...299).contains(response.statusCode) else {
            throw HTTPClientError.invalidStatus(response.statusCode, String(data: response.body, encoding: .utf8) ?? "")
        }

        let decoded = try JSONDecoder().decode(SheetsMetadataResponse.self, from: response.body)
        var mapping: [String: Int] = [:]
        for sheet in decoded.sheets ?? [] {
            if let id = sheet.properties.sheetId {
                mapping[sheet.properties.title] = id
            }
        }
        return mapping
    }

    public func archiveSheetIfExists(sheetName: String, archivedName: String) async throws -> Bool {
        let mapping = try await fetchSheetNameToIDMap()
        guard let sheetID = mapping[sheetName] else {
            return false
        }

        let payload: [String: Any] = [
            "requests": [
                [
                    "updateSheetProperties": [
                        "properties": [
                            "sheetId": sheetID,
                            "title": archivedName,
                        ],
                        "fields": "title",
                    ],
                ],
            ],
        ]

        try await sendBatchUpdate(payload)
        return true
    }

    public func ensureSheetExists(_ sheetName: String) async throws {
        let mapping = try await fetchSheetNameToIDMap()
        if mapping[sheetName] != nil {
            return
        }

        let payload: [String: Any] = [
            "requests": [
                [
                    "addSheet": [
                        "properties": [
                            "title": sheetName,
                        ],
                    ],
                ],
            ],
        ]

        try await sendBatchUpdate(payload)
    }

    public func clearSheetAtoZ(sheetName: String) async throws {
        let encodedRange = Self.encodeSheetRangePath("'\(sheetName)'!A:Z")
        let url = URL(string: "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetID)/values/\(encodedRange):clear")!
        let request = HTTPRequest(
            method: "POST",
            url: url,
            headers: [
                "Authorization": "Bearer \(authToken)",
                "Content-Type": "application/json",
            ],
            body: Data("{}".utf8)
        )

        let response = try await httpClient.send(request)
        guard (200...299).contains(response.statusCode) else {
            throw HTTPClientError.invalidStatus(response.statusCode, String(data: response.body, encoding: .utf8) ?? "")
        }
    }

    public func writeRows(sheetName: String, rows: [[String]], startCell: String = "A1") async throws {
        let range = "'\(sheetName)'!\(startCell)"
        let encodedRange = Self.encodeSheetRangePath(range)
        let url = URL(string: "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetID)/values/\(encodedRange)?valueInputOption=RAW")!
        let body = try JSONSerialization.data(withJSONObject: ["values": rows], options: [])
        let request = HTTPRequest(
            method: "PUT",
            url: url,
            headers: [
                "Authorization": "Bearer \(authToken)",
                "Content-Type": "application/json",
            ],
            body: body
        )

        let response = try await httpClient.send(request)
        guard (200...299).contains(response.statusCode) else {
            throw HTTPClientError.invalidStatus(response.statusCode, String(data: response.body, encoding: .utf8) ?? "")
        }
    }

    public func writeWeeklyPlanRows(sheetName: String, rows: [[String]], archiveExisting: Bool = true) async throws {
        if archiveExisting {
            let timestamp = Self.archiveTimestamp(Date())
            var archivedName = "\(sheetName) [Archived \(timestamp)]"
            var mapping = try await fetchSheetNameToIDMap()
            var suffix = 1
            while mapping[archivedName] != nil {
                archivedName = "\(sheetName) [Archived \(timestamp)-\(suffix)]"
                suffix += 1
            }
            if mapping[sheetName] != nil {
                _ = try await archiveSheetIfExists(sheetName: sheetName, archivedName: archivedName)
                mapping = try await fetchSheetNameToIDMap()
                if mapping[sheetName] != nil {
                    throw HTTPClientError.invalidStatus(409, "Failed to archive existing sheet before write")
                }
            }
        }

        try await ensureSheetExists(sheetName)
        try await clearSheetAtoZ(sheetName: sheetName)
        try await writeRows(sheetName: sheetName, rows: rows, startCell: "A1")
    }

    private func sendBatchUpdate(_ payload: [String: Any]) async throws {
        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        let url = URL(string: "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetID):batchUpdate")!
        let request = HTTPRequest(
            method: "POST",
            url: url,
            headers: [
                "Authorization": "Bearer \(authToken)",
                "Content-Type": "application/json",
            ],
            body: data
        )

        let response = try await httpClient.send(request)
        guard (200...299).contains(response.statusCode) else {
            throw HTTPClientError.invalidStatus(response.statusCode, String(data: response.body, encoding: .utf8) ?? "")
        }
    }

    private static func archiveTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter.string(from: date)
    }

    private static func encodeSheetRangePath(_ range: String) -> String {
        range.addingPercentEncoding(withAllowedCharacters: sheetRangePathAllowedCharacters) ?? range
    }
}
