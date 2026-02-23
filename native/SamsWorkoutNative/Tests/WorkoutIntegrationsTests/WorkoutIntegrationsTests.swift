import Foundation
import XCTest
@testable import WorkoutIntegrations

actor MockHTTPClient: HTTPClient {
    private(set) var requests: [HTTPRequest] = []
    private var queuedResponses: [Result<HTTPResponse, Error>] = []

    func enqueue(_ result: Result<HTTPResponse, Error>) {
        queuedResponses.append(result)
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        requests.append(request)
        if queuedResponses.isEmpty {
            return HTTPResponse(statusCode: 200, headers: [:], body: Data())
        }

        let next = queuedResponses.removeFirst()
        switch next {
        case let .success(response):
            return response
        case let .failure(error):
            throw error
        }
    }

    func latestRequest() -> HTTPRequest? {
        requests.last
    }

    func requestCount() -> Int {
        requests.count
    }

    func allRequests() -> [HTTPRequest] {
        requests
    }
}

final class WorkoutIntegrationsTests: XCTestCase {
    private func tempFileURL(_ name: String = UUID().uuidString) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("sams-workout-native-tests", isDirectory: true)
            .appendingPathComponent("\(name).json")
    }

    func testFacadeReportsSupport() {
        let facade = IntegrationsFacade()
        XCTAssertTrue(facade.supportsRequiredSources())
    }

    func testAuthSessionManagerGoogleAuthModePriority() {
        let manager = AuthSessionManager()

        XCTAssertEqual(
            manager.resolveGoogleAuthMode(
                streamlitSecretAvailable: true,
                serviceAccountFile: "/tmp/sa.json",
                serviceAccountJSON: "{}",
                oauthTokenPath: "/tmp/token.json"
            ),
            .streamlitSecret
        )

        XCTAssertEqual(
            manager.resolveGoogleAuthMode(
                streamlitSecretAvailable: false,
                serviceAccountFile: "/tmp/sa.json",
                serviceAccountJSON: "{}",
                oauthTokenPath: "/tmp/token.json"
            ),
            .serviceAccountFile("/tmp/sa.json")
        )

        XCTAssertEqual(
            manager.resolveGoogleAuthMode(
                streamlitSecretAvailable: false,
                serviceAccountFile: nil,
                serviceAccountJSON: "{\"type\":\"service_account\"}",
                oauthTokenPath: "/tmp/token.json"
            ),
            .serviceAccountJSONEnv
        )

        XCTAssertEqual(
            manager.resolveGoogleAuthMode(
                streamlitSecretAvailable: false,
                serviceAccountFile: nil,
                serviceAccountJSON: nil,
                oauthTokenPath: "/tmp/token.json"
            ),
            .oauthTokenFile("/tmp/token.json")
        )
    }

    func testWeeklyPlanSheetDateParsingSupportsDualPatterns() {
        XCTAssertNotNil(GoogleSheetsClient.parseWeeklyPlanSheetDate("Weekly Plan (2/23/2026)"))
        XCTAssertNotNil(GoogleSheetsClient.parseWeeklyPlanSheetDate("(Weekly Plan) 2/23/2026"))
        XCTAssertNil(GoogleSheetsClient.parseWeeklyPlanSheetDate("Weekly Plan Archive"))
    }

    func testMostRecentWeeklyPlanSheetFindsLatestDate() {
        let names = [
            "Weekly Plan (2/9/2026)",
            "(Weekly Plan) 2/23/2026",
            "Weekly Plan (2/16/2026)",
            "Archive Weekly Plan (2/23/2026)",
        ]

        let mostRecent = GoogleSheetsClient.mostRecentWeeklyPlanSheet(names)
        XCTAssertEqual(mostRecent, "(Weekly Plan) 2/23/2026")
    }

    func testEnforceEightColumnSchemaPadsAndTruncates() {
        XCTAssertEqual(GoogleSheetsClient.enforceEightColumnSchema(["A", "B"]).count, 8)
        XCTAssertEqual(GoogleSheetsClient.enforceEightColumnSchema(["1", "2", "3", "4", "5", "6", "7", "8", "9"]).count, 8)
    }

    func testParseSupplementalWorkoutsParsesTueThuSatOnly() {
        let values = [
            ["TUESDAY"],
            ["Block", "Exercise", "Sets", "Reps", "Load", "Rest", "Notes", "Log"],
            ["B1", "DB Curl", "3", "12", "14", "60", "Strict", "Done"],
            ["MONDAY"],
            ["Block", "Exercise", "Sets", "Reps", "Load", "Rest", "Notes", "Log"],
            ["A1", "Back Squat", "4", "8", "100", "120", "", ""],
            ["THURSDAY"],
            ["Block", "Exercise", "Sets", "Reps", "Load", "Rest", "Notes", "Log"],
            ["D1", "Cable Curl", "3", "10", "20", "60", "", "Done"],
        ]

        let parsed = GoogleSheetsClient.parseSupplementalWorkouts(values: values)
        XCTAssertEqual(parsed["Tuesday"]?.count, 1)
        XCTAssertEqual(parsed["Thursday"]?.count, 1)
        XCTAssertEqual(parsed["Saturday"]?.count, 0)
    }

    func testBuildColumnHLogWritesUsesColumnHRange() {
        let values = [
            ["TUESDAY"],
            ["Block", "Exercise", "Sets", "Reps", "Load", "Rest", "Notes", "Log"],
            ["B1", "DB Curl", "3", "12", "14", "60", "Strict", ""],
            ["B2", "DB Lateral Raise", "3", "12", "8", "60", "", ""],
            ["WEDNESDAY"],
        ]

        let updates = GoogleSheetsClient.buildColumnHLogWrites(
            workoutDate: "TUESDAY",
            sheetValues: values,
            logs: [
                ExerciseLogWrite(exercise: "DB Curl", log: "Done | RPE 8"),
                ExerciseLogWrite(exercise: "DB Lateral Raise", log: "Done | RPE 7"),
            ],
            sheetName: "Weekly Plan (2/23/2026)"
        )

        XCTAssertEqual(updates.count, 2)
        XCTAssertEqual(updates[0].range, "'Weekly Plan (2/23/2026)'!H3")
        XCTAssertEqual(updates[1].range, "'Weekly Plan (2/23/2026)'!H4")
    }

    func testParseDayWorkoutsCapturesRowsAndSourceIndexes() {
        let values = [
            ["MONDAY 2/23"],
            ["Block", "Exercise", "Sets", "Reps", "Load", "Rest", "Notes", "Log"],
            ["A1", "Back Squat", "4", "8", "120", "120", "Depth", ""],
            ["TUESDAY 2/24"],
            ["Block", "Exercise", "Sets", "Reps", "Load", "Rest", "Notes", "Log"],
            ["B1", "DB Curl", "3", "12", "16", "60", "", "Done | RPE 8"],
        ]

        let workouts = GoogleSheetsClient.parseDayWorkouts(values: values)
        XCTAssertEqual(workouts.count, 2)
        XCTAssertEqual(workouts[0].dayName, "Monday")
        XCTAssertEqual(workouts[0].exercises.first?.sourceRow, 3)
        XCTAssertEqual(workouts[1].dayName, "Tuesday")
        XCTAssertEqual(workouts[1].exercises.first?.log, "Done | RPE 8")
    }

    func testReadSheetAtoHCallsAtoHRange() async throws {
        let mock = MockHTTPClient()
        let body = "{\"values\":[[\"A\",\"B\"]]}".data(using: .utf8) ?? Data()
        await mock.enqueue(.success(HTTPResponse(statusCode: 200, headers: [:], body: body)))

        let client = GoogleSheetsClient(
            spreadsheetID: "sheet_123",
            authToken: "token_abc",
            httpClient: mock
        )

        let values = try await client.readSheetAtoH(sheetName: "Weekly Plan (2/23/2026)")
        XCTAssertEqual(values.count, 1)
        XCTAssertEqual(values[0].count, 8)

        let request = await mock.latestRequest()
        XCTAssertEqual(request?.method, "GET")
        XCTAssertTrue(request?.url.absoluteString.contains("A:H") ?? false)
        XCTAssertTrue(request?.url.absoluteString.contains("%2F23%2F2026") ?? false)
        XCTAssertFalse(request?.url.absoluteString.contains("2/23/2026") ?? true)
    }

    func testBatchUpdateLogsSendsBatchUpdateRequest() async throws {
        let mock = MockHTTPClient()
        await mock.enqueue(.success(HTTPResponse(statusCode: 200, headers: [:], body: Data("{}".utf8))))

        let client = GoogleSheetsClient(
            spreadsheetID: "sheet_123",
            authToken: "token_abc",
            httpClient: mock
        )

        try await client.batchUpdateLogs([
            ValueRangeUpdate(range: "'Weekly Plan (2/23/2026)'!H3", values: [["Done"]]),
        ])

        let request = await mock.latestRequest()
        let requestCount = await mock.requestCount()
        XCTAssertEqual(request?.method, "POST")
        XCTAssertTrue(request?.url.absoluteString.hasSuffix("/values:batchUpdate") ?? false)
        XCTAssertEqual(requestCount, 1)
    }

    func testArchiveSheetIfExistsUsesBatchUpdateWithSheetID() async throws {
        let mock = MockHTTPClient()
        let metadata = """
        {
          "sheets": [
            {"properties": {"title": "Weekly Plan (2/23/2026)", "sheetId": 777}}
          ]
        }
        """.data(using: .utf8) ?? Data()
        await mock.enqueue(.success(HTTPResponse(statusCode: 200, headers: [:], body: metadata)))
        await mock.enqueue(.success(HTTPResponse(statusCode: 200, headers: [:], body: Data("{}".utf8))))

        let client = GoogleSheetsClient(
            spreadsheetID: "sheet_123",
            authToken: "token_abc",
            httpClient: mock
        )

        let archived = try await client.archiveSheetIfExists(
            sheetName: "Weekly Plan (2/23/2026)",
            archivedName: "Weekly Plan (2/23/2026) [Archived 20260222_130000]"
        )

        XCTAssertTrue(archived)
        let requests = await mock.allRequests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].method, "GET")
        XCTAssertEqual(requests[1].method, "POST")
        XCTAssertTrue(requests[1].url.absoluteString.hasSuffix(":batchUpdate"))
    }

    func testWriteRowsSendsPutRequest() async throws {
        let mock = MockHTTPClient()
        await mock.enqueue(.success(HTTPResponse(statusCode: 200, headers: [:], body: Data("{}".utf8))))

        let client = GoogleSheetsClient(
            spreadsheetID: "sheet_123",
            authToken: "token_abc",
            httpClient: mock
        )

        try await client.writeRows(
            sheetName: "Weekly Plan (2/23/2026)",
            rows: [["Block", "Exercise"]]
        )

        let request = await mock.latestRequest()
        XCTAssertEqual(request?.method, "PUT")
        XCTAssertTrue(request?.url.absoluteString.contains("valueInputOption=RAW") ?? false)
        XCTAssertTrue(request?.url.absoluteString.contains("%2F23%2F2026") ?? false)
        XCTAssertFalse(request?.url.absoluteString.contains("2/23/2026") ?? true)
    }

    func testClearSheetAtoZEncodesSlashInSheetNamePath() async throws {
        let mock = MockHTTPClient()
        await mock.enqueue(.success(HTTPResponse(statusCode: 200, headers: [:], body: Data("{}".utf8))))

        let client = GoogleSheetsClient(
            spreadsheetID: "sheet_123",
            authToken: "token_abc",
            httpClient: mock
        )

        try await client.clearSheetAtoZ(sheetName: "Weekly Plan (2/23/2026)")

        let request = await mock.latestRequest()
        XCTAssertEqual(request?.method, "POST")
        XCTAssertTrue(request?.url.absoluteString.contains(":clear") ?? false)
        XCTAssertTrue(request?.url.absoluteString.contains("%2F23%2F2026") ?? false)
        XCTAssertFalse(request?.url.absoluteString.contains("2/23/2026") ?? true)
    }

    func testWriteWeeklyPlanRowsCreatesSheetThenWritesRows() async throws {
        let mock = MockHTTPClient()
        let emptyMetadata = Data("{\"sheets\":[]}".utf8)

        await mock.enqueue(.success(HTTPResponse(statusCode: 200, headers: [:], body: emptyMetadata))) // archive lookup
        await mock.enqueue(.success(HTTPResponse(statusCode: 200, headers: [:], body: emptyMetadata))) // ensure lookup
        await mock.enqueue(.success(HTTPResponse(statusCode: 200, headers: [:], body: Data("{}".utf8)))) // addSheet
        await mock.enqueue(.success(HTTPResponse(statusCode: 200, headers: [:], body: Data("{}".utf8)))) // clear
        await mock.enqueue(.success(HTTPResponse(statusCode: 200, headers: [:], body: Data("{}".utf8)))) // write

        let client = GoogleSheetsClient(
            spreadsheetID: "sheet_123",
            authToken: "token_abc",
            httpClient: mock
        )

        try await client.writeWeeklyPlanRows(
            sheetName: "Weekly Plan (2/23/2026)",
            rows: [["Block", "Exercise", "Sets", "Reps", "Load (kg)", "Rest", "Notes", "Log"]],
            archiveExisting: true
        )

        let requests = await mock.allRequests()
        XCTAssertEqual(requests.count, 5)
        XCTAssertEqual(requests.last?.method, "PUT")
    }

    func testAnthropicClientBuildsMessageRequestAndParsesResponse() async throws {
        let mock = MockHTTPClient()
        let responseJSON = """
        {
          "model": "claude-sonnet-4-6",
          "stop_reason": "end_turn",
          "content": [
            {"type": "text", "text": "## MONDAY\\n### A1. Back Squat"}
          ]
        }
        """.data(using: .utf8) ?? Data()

        await mock.enqueue(.success(HTTPResponse(statusCode: 200, headers: [:], body: responseJSON)))

        let client = AnthropicClient(
            apiKey: "api_test",
            model: "claude-sonnet-4-6",
            maxTokens: 2048,
            httpClient: mock
        )

        let result = try await client.generatePlan(systemPrompt: "system", userPrompt: "user")
        XCTAssertTrue(result.text.contains("## MONDAY"))
        XCTAssertEqual(result.model, "claude-sonnet-4-6")

        let request = await mock.latestRequest()
        XCTAssertEqual(request?.method, "POST")
        XCTAssertTrue(request?.url.absoluteString.hasSuffix("/v1/messages") ?? false)
        XCTAssertEqual(request?.headers["x-api-key"], "api_test")
    }

    func testResolveOAuthAccessTokenReturnsExistingTokenWhenNotExpired() async throws {
        let manager = AuthSessionManager()
        let mock = MockHTTPClient()
        let fileURL = tempFileURL("oauth_not_expired")
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let payload: [String: Any] = [
            "access_token": "existing_token",
            "refresh_token": "refresh_token",
            "client_id": "client_id",
            "client_secret": "client_secret",
            "token_uri": "https://oauth2.googleapis.com/token",
            "expiry": "2099-01-01T00:00:00Z",
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        try data.write(to: fileURL, options: [.atomic])

        let token = try await manager.resolveOAuthAccessToken(
            tokenFilePath: fileURL.path,
            now: Date(timeIntervalSince1970: 0),
            httpClient: mock
        )

        XCTAssertEqual(token, "existing_token")
        let requestCount = await mock.requestCount()
        XCTAssertEqual(requestCount, 0)
    }

    func testResolveOAuthAccessTokenRefreshesExpiredTokenAndPersists() async throws {
        let manager = AuthSessionManager()
        let mock = MockHTTPClient()
        let fileURL = tempFileURL("oauth_refresh")
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let payload: [String: Any] = [
            "token": "old_token",
            "refresh_token": "refresh_token",
            "client_id": "client_id",
            "client_secret": "client_secret",
            "token_uri": "https://oauth2.googleapis.com/token",
            "expiry": "2000-01-01T00:00:00Z",
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        try data.write(to: fileURL, options: [.atomic])

        let responseBody = """
        {
          "access_token": "new_access_token",
          "expires_in": 3600
        }
        """.data(using: .utf8) ?? Data()
        await mock.enqueue(.success(HTTPResponse(statusCode: 200, headers: [:], body: responseBody)))

        let token = try await manager.resolveOAuthAccessToken(
            tokenFilePath: fileURL.path,
            now: Date(timeIntervalSince1970: 1_700_000_000),
            httpClient: mock
        )

        XCTAssertEqual(token, "new_access_token")
        let requests = await mock.allRequests()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.method, "POST")

        let updatedData = try Data(contentsOf: fileURL)
        let updated = try JSONSerialization.jsonObject(with: updatedData) as? [String: Any]
        XCTAssertEqual(updated?["token"] as? String, "new_access_token")
        XCTAssertEqual(updated?["access_token"] as? String, "new_access_token")
        XCTAssertNotNil(updated?["expiry"] as? String)
    }
}
