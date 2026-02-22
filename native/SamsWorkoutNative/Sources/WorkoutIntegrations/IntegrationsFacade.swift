import Foundation
import WorkoutCore

public struct IntegrationsFacade {
    public let authSessionManager: AuthSessionManager

    public init(authSessionManager: AuthSessionManager = AuthSessionManager()) {
        self.authSessionManager = authSessionManager
    }

    public func supportsRequiredSources() -> Bool {
        true
    }

    public func describeCurrentMode() -> String {
        let env = authSessionManager.loadEnvironment()
        let authMode = authSessionManager.resolveGoogleAuthMode(
            streamlitSecretAvailable: false,
            serviceAccountFile: env.googleServiceAccountFile,
            serviceAccountJSON: env.googleServiceAccountJSON,
            oauthTokenPath: env.oauthTokenPath
        )

        let authText: String
        switch authMode {
        case .streamlitSecret:
            authText = "Google auth via Streamlit secret"
        case let .serviceAccountFile(path):
            authText = "Google auth via service account file: \(path)"
        case .serviceAccountJSONEnv:
            authText = "Google auth via service account JSON env"
        case let .oauthTokenFile(path):
            authText = "Google auth via OAuth token: \(path)"
        case .unavailable:
            authText = "Google auth not configured"
        }

        let anthropicText = authSessionManager.hasAnthropicKey(env.anthropicAPIKey)
            ? "Anthropic key configured"
            : "Anthropic key missing"

        return "Local native mode with Google Sheets as source of truth (\(authText); \(anthropicText))"
    }

    public func makeAnthropicClient(apiKey: String, model: String, maxTokens: Int) -> AnthropicClient {
        AnthropicClient(apiKey: apiKey, model: model, maxTokens: maxTokens)
    }

    public func makeGoogleSheetsClient(spreadsheetID: String, authToken: String) -> GoogleSheetsClient {
        GoogleSheetsClient(spreadsheetID: spreadsheetID, authToken: authToken)
    }
}
