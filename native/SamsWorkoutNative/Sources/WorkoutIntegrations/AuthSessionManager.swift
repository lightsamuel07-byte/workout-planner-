import Foundation

public enum GoogleAuthMode: Equatable, Sendable {
    case streamlitSecret
    case serviceAccountFile(String)
    case serviceAccountJSONEnv
    case oauthTokenFile(String)
    case unavailable
}

public struct IntegrationEnvironment: Equatable, Sendable {
    public let anthropicAPIKey: String?
    public let googleServiceAccountFile: String?
    public let googleServiceAccountJSON: String?
    public let oauthTokenPath: String?
    public let appSupportDirectory: String

    public init(
        anthropicAPIKey: String?,
        googleServiceAccountFile: String?,
        googleServiceAccountJSON: String?,
        oauthTokenPath: String?,
        appSupportDirectory: String
    ) {
        self.anthropicAPIKey = anthropicAPIKey
        self.googleServiceAccountFile = googleServiceAccountFile
        self.googleServiceAccountJSON = googleServiceAccountJSON
        self.oauthTokenPath = oauthTokenPath
        self.appSupportDirectory = appSupportDirectory
    }
}

public struct AuthSessionManager: Sendable {
    public init() {}

    public func defaultAppSupportDirectory() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/Application Support/SamsWorkoutApp"
    }

    public func loadEnvironment(from env: [String: String] = ProcessInfo.processInfo.environment) -> IntegrationEnvironment {
        let appSupport = defaultAppSupportDirectory()
        let tokenPath = env["GOOGLE_OAUTH_TOKEN_PATH"] ?? "\(appSupport)/auth/token.json"
        return IntegrationEnvironment(
            anthropicAPIKey: env["ANTHROPIC_API_KEY"],
            googleServiceAccountFile: env["GOOGLE_SERVICE_ACCOUNT_FILE"],
            googleServiceAccountJSON: env["GOOGLE_SERVICE_ACCOUNT_JSON"],
            oauthTokenPath: tokenPath,
            appSupportDirectory: appSupport
        )
    }

    public func resolveGoogleAuthMode(
        streamlitSecretAvailable: Bool,
        serviceAccountFile: String?,
        serviceAccountJSON: String?,
        oauthTokenPath: String?
    ) -> GoogleAuthMode {
        if streamlitSecretAvailable {
            return .streamlitSecret
        }

        if let serviceAccountFile,
           !serviceAccountFile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .serviceAccountFile(serviceAccountFile)
        }

        if let serviceAccountJSON,
           !serviceAccountJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .serviceAccountJSONEnv
        }

        if let oauthTokenPath,
           !oauthTokenPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .oauthTokenFile(oauthTokenPath)
        }

        return .unavailable
    }

    public func hasAnthropicKey(_ key: String?) -> Bool {
        guard let key else {
            return false
        }
        return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public func resolveOAuthAccessToken(
        tokenFilePath: String,
        now: Date = Date(),
        refreshSkewSeconds: TimeInterval = 60,
        httpClient: HTTPClient = URLSessionHTTPClient()
    ) async throws -> String {
        let fileURL = URL(fileURLWithPath: tokenFilePath)
        let fileDescriptor = open(tokenFilePath, O_RDWR)
        guard fileDescriptor >= 0 else {
            // Fall back to non-locking read if we can't open for locking.
            return try await resolveOAuthAccessTokenUnlocked(
                fileURL: fileURL, now: now, refreshSkewSeconds: refreshSkewSeconds, httpClient: httpClient
            )
        }
        defer { close(fileDescriptor) }

        // Acquire an exclusive file lock to prevent concurrent token refreshes.
        flock(fileDescriptor, LOCK_EX)
        defer { flock(fileDescriptor, LOCK_UN) }

        return try await resolveOAuthAccessTokenUnlocked(
            fileURL: fileURL, now: now, refreshSkewSeconds: refreshSkewSeconds, httpClient: httpClient
        )
    }

    private func resolveOAuthAccessTokenUnlocked(
        fileURL: URL,
        now: Date,
        refreshSkewSeconds: TimeInterval,
        httpClient: HTTPClient
    ) async throws -> String {
        let data = try Data(contentsOf: fileURL)
        guard var payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AuthSessionError.invalidTokenFile
        }

        let currentToken = Self.currentToken(from: payload)
        let shouldRefresh = Self.shouldRefreshToken(
            payload: payload,
            now: now,
            refreshSkewSeconds: refreshSkewSeconds
        )

        if !shouldRefresh, let currentToken, !currentToken.isEmpty {
            return currentToken
        }

        let refreshedToken = try await refreshOAuthAccessToken(
            payload: &payload,
            now: now,
            httpClient: httpClient
        )

        let updatedData = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        try updatedData.write(to: fileURL, options: [.atomic])
        return refreshedToken
    }

    private func refreshOAuthAccessToken(
        payload: inout [String: Any],
        now: Date,
        httpClient: HTTPClient
    ) async throws -> String {
        guard let refreshToken = payload["refresh_token"] as? String,
              let clientID = payload["client_id"] as? String,
              let clientSecret = payload["client_secret"] as? String
        else {
            if let fallback = Self.currentToken(from: payload), !fallback.isEmpty {
                return fallback
            }
            throw AuthSessionError.missingRefreshFields
        }

        let tokenURIString = (payload["token_uri"] as? String) ?? "https://oauth2.googleapis.com/token"
        guard let tokenURL = URL(string: tokenURIString) else {
            throw AuthSessionError.invalidTokenURI
        }

        let body = Self.formURLEncoded([
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID,
            "client_secret": clientSecret,
        ])

        let request = HTTPRequest(
            method: "POST",
            url: tokenURL,
            headers: ["Content-Type": "application/x-www-form-urlencoded"],
            body: Data(body.utf8)
        )
        let response = try await httpClient.send(request)
        guard (200...299).contains(response.statusCode) else {
            throw HTTPClientError.invalidStatus(response.statusCode, String(data: response.body, encoding: .utf8) ?? "")
        }

        guard let responseJSON = try JSONSerialization.jsonObject(with: response.body) as? [String: Any],
              let accessToken = responseJSON["access_token"] as? String,
              !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw AuthSessionError.refreshFailed
        }

        payload["access_token"] = accessToken
        payload["token"] = accessToken

        if let expiresIn = responseJSON["expires_in"] as? Double {
            payload["expiry"] = Self.iso8601(now.addingTimeInterval(expiresIn))
        } else if let expiresInInt = responseJSON["expires_in"] as? Int {
            payload["expiry"] = Self.iso8601(now.addingTimeInterval(Double(expiresInInt)))
        }

        return accessToken
    }

    private static func currentToken(from payload: [String: Any]) -> String? {
        if let accessToken = payload["access_token"] as? String, !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return accessToken
        }
        if let token = payload["token"] as? String, !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return token
        }
        return nil
    }

    private static func shouldRefreshToken(payload: [String: Any], now: Date, refreshSkewSeconds: TimeInterval) -> Bool {
        if currentToken(from: payload) == nil {
            return true
        }

        guard let expiryRaw = payload["expiry"] as? String,
              let expiry = parseExpiry(expiryRaw)
        else {
            return false
        }

        return expiry <= now.addingTimeInterval(refreshSkewSeconds)
    }

    private static func parseExpiry(_ value: String) -> Date? {
        if let date = ISO8601DateFormatter().date(from: value) {
            return date
        }

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS'Z'"
        if let date = formatter.date(from: value) {
            return date
        }

        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        return formatter.date(from: value)
    }

    private static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private static func formURLEncoded(_ values: [String: String]) -> String {
        values.map { key, value in
            "\(percentEncode(key))=\(percentEncode(value))"
        }
        .sorted()
        .joined(separator: "&")
    }

    private static func percentEncode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "+&=?"))) ?? value
    }
}

public enum AuthSessionError: Error, Equatable {
    case invalidTokenFile
    case invalidTokenURI
    case missingRefreshFields
    case refreshFailed
}
