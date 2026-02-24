import SwiftUI
import AppKit

struct NativeWorkoutRootView: View {
    @StateObject private var coordinator = AppCoordinator(gateway: LiveAppGateway())

    var body: some View {
        Group {
            if coordinator.isSetupComplete {
                if coordinator.isUnlocked {
                    NavigationSplitView {
                        List(AppRoute.allCases, selection: $coordinator.route) { route in
                            Label(route.rawValue, systemImage: icon(for: route))
                                .tag(route)
                        }
                        .frame(minWidth: 240)
                    } detail: {
                        routeView(route: coordinator.route)
                            .padding(20)
                    }
                } else {
                    UnlockView(coordinator: coordinator)
                        .padding(20)
                }
            } else {
                SetupFlowView(coordinator: coordinator)
                    .padding(20)
            }
        }
        .frame(minWidth: 1080, minHeight: 720)
    }

    private func icon(for route: AppRoute) -> String {
        switch route {
        case .dashboard:
            return "house"
        case .generatePlan:
            return "wand.and.stars"
        case .viewPlan:
            return "list.bullet.rectangle"
        case .logWorkout:
            return "square.and.pencil"
        case .progress:
            return "chart.line.uptrend.xyaxis"
        case .weeklyReview:
            return "calendar"
        case .exerciseHistory:
            return "clock.arrow.circlepath"
        case .settings:
            return "gearshape"
        case .apiTestHarness: // TEMP: TEST HARNESS
            return "ant"
        case .dbStatus:
            return "internaldrive"
        }
    }

    @ViewBuilder
    private func routeView(route: AppRoute) -> some View {
        switch route {
        case .dashboard:
            DashboardPageView(coordinator: coordinator)
        case .generatePlan:
            GeneratePlanPageView(coordinator: coordinator)
        case .viewPlan:
            ViewPlanPageView(coordinator: coordinator)
        case .logWorkout:
            LogWorkoutPageView(coordinator: coordinator)
        case .progress:
            ProgressPageView(coordinator: coordinator)
        case .weeklyReview:
            WeeklyReviewPageView(coordinator: coordinator)
        case .exerciseHistory:
            ExerciseHistoryPageView(coordinator: coordinator)
        case .settings:
            SettingsPageView(coordinator: coordinator)
        case .apiTestHarness: // TEMP: TEST HARNESS
            APITestHarnessPageView(coordinator: coordinator)
        case .dbStatus:
            DBStatusPageView(coordinator: coordinator)
        }
    }
}

struct StatusBannerView: View {
    let banner: StatusBanner

    var body: some View {
        if !banner.text.isEmpty {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: iconName)
                    .foregroundStyle(foreground)
                Text(banner.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.callout)
            .padding(10)
            .background(background)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private var iconName: String {
        switch banner.severity {
        case .info:
            return "info.circle"
        case .success:
            return "checkmark.circle"
        case .warning:
            return "exclamationmark.triangle"
        case .error:
            return "xmark.octagon"
        }
    }

    private var foreground: Color {
        switch banner.severity {
        case .info:
            return .blue
        case .success:
            return .green
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }

    private var border: Color {
        switch banner.severity {
        case .info:
            return .blue.opacity(0.45)
        case .success:
            return .green.opacity(0.45)
        case .warning:
            return .orange.opacity(0.45)
        case .error:
            return .red.opacity(0.45)
        }
    }

    private var background: Color {
        switch banner.severity {
        case .info:
            return .blue.opacity(0.08)
        case .success:
            return .green.opacity(0.08)
        case .warning:
            return .orange.opacity(0.08)
        case .error:
            return .red.opacity(0.08)
        }
    }
}

struct MetricCardView: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct SetupFlowView: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Setup")
                    .font(.largeTitle.bold())

                Text("Configure local credentials for Anthropic and Google Sheets. Values are stored in your local app support directory.")
                    .foregroundStyle(.secondary)

                StatusBannerView(banner: coordinator.statusBanner)

                Group {
                    Text("Anthropic API Key")
                        .font(.headline)
                    TextField("sk-ant-...", text: $coordinator.setupState.anthropicAPIKey)
                        .textFieldStyle(.roundedBorder)

                    Text("Google Spreadsheet ID")
                        .font(.headline)
                    TextField("Spreadsheet ID", text: $coordinator.setupState.spreadsheetID)
                        .textFieldStyle(.roundedBorder)

                    Text("Google Auth Hint (token file path)")
                        .font(.headline)
                    TextField("/Users/.../token.json", text: $coordinator.setupState.googleAuthHint)
                        .textFieldStyle(.roundedBorder)

                    Text("Local App Password (optional)")
                        .font(.headline)
                    SecureField("Set app unlock password", text: $coordinator.setupState.localAppPassword)
                        .textFieldStyle(.roundedBorder)
                }

                GroupBox("Readiness") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .center, spacing: 8) {
                            Image(systemName: coordinator.setupReadinessSeverity == .success ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(coordinator.setupReadinessSeverity == .success ? .green : .orange)
                            Text(coordinator.setupReadinessText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        ProgressView(value: coordinator.setupCompletionPercent / 100.0) {
                            Text("Setup completion")
                        } currentValueLabel: {
                            Text("\(Int(coordinator.setupCompletionPercent.rounded()))%")
                        }
                        Text(coordinator.setupMissingSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                GroupBox("Checklist") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(coordinator.setupChecklist) { item in
                            Label(item.title, systemImage: item.isComplete ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(item.isComplete ? .green : .secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Auth Quick Help") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Use either a token file path or a bearer token in Google Auth Hint.")
                        Text("If token refresh fails, click Re-auth, update token.json, then retry.")
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !coordinator.setupErrors.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(coordinator.setupErrors, id: \.self) { err in
                            Text(err)
                                .foregroundStyle(.red)
                        }
                    }
                }

                HStack {
                    Button("Complete Setup") {
                        coordinator.completeSetup()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Re-auth") {
                        coordinator.triggerReauth()
                    }
                    .buttonStyle(.bordered)

                    Button("Copy Auth Hint") {
                        let hint = coordinator.setupState.googleAuthHint.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !hint.isEmpty else {
                            return
                        }
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(hint, forType: .string)
                    }
                    .buttonStyle(.bordered)
                    .disabled(coordinator.setupState.googleAuthHint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button("Paste Auth Hint") {
                        if let value = NSPasteboard.general.string(forType: .string), !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            coordinator.setupState.googleAuthHint = value.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    }
                    .buttonStyle(.bordered)

                    Button("Clear Sensitive Fields") {
                        coordinator.setupState.anthropicAPIKey = ""
                        coordinator.setupState.googleAuthHint = ""
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()
            }
        }
    }
}

struct UnlockView: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Unlock App")
                .font(.largeTitle.bold())
            Text("Enter your local app password to continue. If forgotten, return to Setup and set a new local password.")
                .foregroundStyle(.secondary)

            SecureField("App Password", text: $coordinator.unlockInput)
                .textFieldStyle(.roundedBorder)
                .onChange(of: coordinator.unlockInput) {
                    if !coordinator.unlockError.isEmpty {
                        coordinator.unlockError = ""
                    }
                }
                .onSubmit {
                    coordinator.unlock()
                }

            HStack {
                Button("Unlock") {
                    coordinator.unlock()
                }
                .buttonStyle(.borderedProminent)

                Button("Back To Setup") {
                    coordinator.markSetupIncomplete()
                }
                .buttonStyle(.bordered)
            }

            StatusBannerView(banner: coordinator.statusBanner)
            Spacer()
        }
    }
}

struct DashboardPageView: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Dashboard")
                        .font(.largeTitle.bold())
                    Spacer()
                    Text(coordinator.analyticsFreshnessText)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                StatusBannerView(banner: coordinator.statusBanner)

                // MARK: - Key Metrics Row
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 155), spacing: 10)], spacing: 10) {
                    DashboardMetricCard(
                        icon: "checkmark.circle.fill",
                        iconColor: .green,
                        title: "Completion",
                        value: String(format: "%.0f%%", coordinator.weeklyReviewAverageCompletion),
                        subtitle: "Avg across weeks"
                    )
                    DashboardMetricCard(
                        icon: "figure.strengthtraining.traditional",
                        iconColor: .blue,
                        title: "Exercises",
                        value: "\(coordinator.planExerciseCount)",
                        subtitle: coordinator.planSnapshot.title.isEmpty ? "No plan" : coordinator.planSnapshot.title
                    )
                    DashboardMetricCard(
                        icon: "scalemass.fill",
                        iconColor: .purple,
                        title: "Est. Volume",
                        value: String(format: "%.0f kg", coordinator.planDayStats.estimatedVolumeKG),
                        subtitle: coordinator.selectedPlanDetail?.dayLabel ?? "Selected day"
                    )
                    DashboardMetricCard(
                        icon: "pencil.and.list.clipboard",
                        iconColor: coordinator.loggerPendingVisibleCount > 0 ? .orange : .green,
                        title: "Logger",
                        value: "\(coordinator.loggerCompletionCount)/\(coordinator.loggerTotalCount)",
                        subtitle: coordinator.loggerPendingVisibleCount > 0 ? "\(coordinator.loggerPendingVisibleCount) pending" : "All done"
                    )
                }

                // MARK: - 1RM Status Strip
                if coordinator.oneRepMaxesAreFilled {
                    GroupBox {
                        HStack(spacing: 16) {
                            Label("1RM Profile", systemImage: "dumbbell.fill")
                                .font(.caption.bold())
                            ForEach(coordinator.oneRepMaxFields) { field in
                                if let value = field.parsedValue {
                                    HStack(spacing: 4) {
                                        Text(abbreviatedLiftName(field.liftName))
                                            .font(.system(.caption2, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                        Text(String(format: "%.0f", value))
                                            .font(.system(.caption, design: .monospaced).bold())
                                        Text("kg")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                            Spacer()
                            Button("Edit") { coordinator.quickNavigate(to: .settings) }
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("1RM values not set.")
                            .font(.callout)
                        Button("Set up now") { coordinator.quickNavigate(to: .settings) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        Spacer()
                    }
                    .padding(8)
                    .background(.orange.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                // MARK: - Training Week Grid
                GroupBox("This Week") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], spacing: 8) {
                        ForEach(coordinator.dashboardDays) { day in
                            DashboardDayCard(day: day)
                                .onTapGesture {
                                    coordinator.selectedPlanDay = day.title.capitalized
                                    coordinator.quickNavigate(to: .viewPlan)
                                }
                        }
                    }
                }

                // MARK: - Quick Actions & Refresh
                HStack(spacing: 12) {
                    GroupBox("Quick Actions") {
                        HStack(spacing: 8) {
                            Button { coordinator.quickNavigate(to: .generatePlan) } label: {
                                Label("Generate", systemImage: "wand.and.stars")
                            }
                            Button { coordinator.quickNavigate(to: .viewPlan) } label: {
                                Label("View Plan", systemImage: "list.bullet.rectangle")
                            }
                            Button { coordinator.quickNavigate(to: .logWorkout) } label: {
                                Label("Log", systemImage: "square.and.pencil")
                            }
                            Button { coordinator.quickNavigate(to: .dbStatus) } label: {
                                Label("DB", systemImage: "internaldrive")
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    Spacer()

                    GroupBox("Refresh") {
                        HStack(spacing: 8) {
                            Button("Plan") { Task { await coordinator.refreshPlanSnapshot() } }
                            Button("Logger") { Task { await coordinator.refreshLoggerSession() } }
                            Button("Analytics") { coordinator.refreshAnalytics() }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                // MARK: - Recent Activity
                if !coordinator.recentSessions.isEmpty {
                    GroupBox("Recent Sessions") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(coordinator.recentSessions.prefix(5)) { session in
                                HStack {
                                    Text(session.dayLabel)
                                        .font(.callout.weight(.medium))
                                    Text(session.sessionDateISO)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    let pct = session.totalRows > 0 ? Double(session.loggedRows) / Double(session.totalRows) * 100 : 0
                                    Text("\(session.loggedRows)/\(session.totalRows)")
                                        .font(.system(.caption, design: .monospaced))
                                    completionBadge(pct)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                // MARK: - Timestamp Footer
                GroupBox("Last Refresh") {
                    HStack(spacing: 16) {
                        Label("Plan: \(coordinator.formatTimestamp(coordinator.lastPlanRefreshAt))", systemImage: "doc.text")
                        Label("Logger: \(coordinator.formatTimestamp(coordinator.lastLoggerRefreshAt))", systemImage: "pencil")
                        Label("Analytics: \(coordinator.formatTimestamp(coordinator.lastAnalyticsRefreshAt))", systemImage: "chart.bar")
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .onAppear {
            coordinator.loadOneRepMaxFields()
        }
    }

    private func abbreviatedLiftName(_ name: String) -> String {
        switch name {
        case "Back Squat": return "SQ"
        case "Bench Press": return "BP"
        case "Deadlift": return "DL"
        default: return String(name.prefix(3)).uppercased()
        }
    }

    private func completionBadge(_ pct: Double) -> some View {
        Text(String(format: "%.0f%%", pct))
            .font(.system(.caption2, design: .monospaced).bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(pct >= 80 ? Color.green.opacity(0.15) : pct >= 50 ? Color.orange.opacity(0.15) : Color.red.opacity(0.15))
            .foregroundStyle(pct >= 80 ? .green : pct >= 50 ? .orange : .red)
            .clipShape(Capsule())
    }
}

struct DashboardMetricCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let value: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundStyle(iconColor)
                    .font(.caption)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.title2.bold())
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct DashboardDayCard: View {
    let day: DayPlanSummary

    private var isFortDay: Bool {
        let upper = day.title.uppercased()
        return upper == "MONDAY" || upper == "WEDNESDAY" || upper == "FRIDAY"
    }

    private var accentColor: Color {
        if day.blocks == 0 { return .gray }
        return isFortDay ? .blue : .purple
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(day.title)
                    .font(.caption.bold())
                Spacer()
                if isFortDay {
                    Text("FORT")
                        .font(.system(.caption2, design: .rounded).bold())
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.blue.opacity(0.12))
                        .clipShape(Capsule())
                } else if day.blocks > 0 {
                    Text("SUPP")
                        .font(.system(.caption2, design: .rounded).bold())
                        .foregroundStyle(.purple)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.purple.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
            HStack(spacing: 4) {
                Text("\(day.blocks)")
                    .font(.title3.bold())
                    .foregroundStyle(accentColor)
                Text(day.blocks == 1 ? "exercise" : "exercises")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(day.source.rawValue)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accentColor.opacity(0.04))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(accentColor.opacity(0.15), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct GeneratePlanPageView: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Generate Plan")
                    .font(.largeTitle.bold())

                Text("Target sheet: \(coordinator.generationTargetSheetName)")
                    .foregroundStyle(.secondary)

                StatusBannerView(banner: coordinator.statusBanner)

                HStack {
                    Button("Template Monday") { coordinator.applyGenerationTemplate(day: "monday") }
                    Button("Template Wednesday") { coordinator.applyGenerationTemplate(day: "wednesday") }
                    Button("Template Friday") { coordinator.applyGenerationTemplate(day: "friday") }
                    Button("Normalize Inputs") { coordinator.normalizeGenerationInput() }
                    Button("Copy All Inputs") {
                        let text = coordinator.copyGenerationInputsText()
                        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(text, forType: .string)
                        }
                    }
                    Button("Clear All") { coordinator.clearGenerationInput() }
                }
                .buttonStyle(.bordered)

                GroupBox("Preflight Checks") {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(
                            coordinator.generationReadinessSummary,
                            systemImage: coordinator.generationReadinessReport.isReady ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(coordinator.generationReadinessReport.isReady ? .green : .orange)

                        if !coordinator.generationReadinessReport.issues.isEmpty {
                            ForEach(coordinator.generationReadinessReport.issues, id: \.self) { issue in
                                Text("• \(issue)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .font(.callout)
                }
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(preflightTint(for: coordinator.generationReadinessSeverity))
                )

                if !coordinator.oneRepMaxWarningForGeneration.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(coordinator.oneRepMaxWarningForGeneration)
                                .font(.callout)
                                .foregroundStyle(.orange)
                            Button("Go to Settings") {
                                coordinator.quickNavigate(to: .settings)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .padding(10)
                    .background(.orange.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                HStack {
                    Text("Issues: \(coordinator.generationIssueCount)")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.thinMaterial)
                        .clipShape(Capsule())
                    Text("Input fingerprint: \(coordinator.generationInputFingerprint)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                if coordinator.generationHasPotentialDuplication {
                    GroupBox("Potential Duplication") {
                        Text("One or more day inputs look identical. This can degrade generation quality.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                Group {
                    Text("Monday Fort Input")
                        .font(.headline)
                    TextEditor(text: $coordinator.generationInput.monday)
                        .frame(height: 130)
                    Text("Characters: \(coordinator.mondayCharacterCount) | Lines: \(coordinator.generationDayLineCounts["Monday"] ?? 0)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("Wednesday Fort Input")
                        .font(.headline)
                    TextEditor(text: $coordinator.generationInput.wednesday)
                        .frame(height: 130)
                    Text("Characters: \(coordinator.wednesdayCharacterCount) | Lines: \(coordinator.generationDayLineCounts["Wednesday"] ?? 0)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("Friday Fort Input")
                        .font(.headline)
                    TextEditor(text: $coordinator.generationInput.friday)
                        .frame(height: 130)
                    Text("Characters: \(coordinator.fridayCharacterCount) | Lines: \(coordinator.generationDayLineCounts["Friday"] ?? 0)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button(coordinator.isGenerating ? "Generating..." : "Generate") {
                        Task { await coordinator.runGeneration() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!coordinator.canGenerateNow)

                    Button("Re-auth") {
                        coordinator.triggerReauth()
                    }
                    .buttonStyle(.bordered)

                    Button("Copy Status") {
                        let text = coordinator.copyStatusText()
                        if !text.isEmpty {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(text, forType: .string)
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(coordinator.copyStatusText().isEmpty)
                }

                if coordinator.isGenerating {
                    ProgressView("Generating and syncing weekly plan...")
                }

                if !coordinator.generationDisabledReason.isEmpty {
                    Text(coordinator.generationDisabledReason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("Tip: keep day headers and section cues from Fort to improve deterministic parsing and anchor fidelity.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func preflightTint(for severity: StatusSeverity) -> Color {
        switch severity {
        case .success:
            return .green.opacity(0.05)
        case .warning:
            return .orange.opacity(0.05)
        case .error:
            return .red.opacity(0.05)
        case .info:
            return .blue.opacity(0.05)
        }
    }
}

struct ViewPlanPageView: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("View Plan")
                .font(.largeTitle.bold())

            StatusBannerView(banner: coordinator.statusBanner)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Source: \(coordinator.planSnapshot.source.rawValue)")
                        .foregroundStyle(.secondary)
                    if !coordinator.planSnapshot.title.isEmpty {
                        Text("Plan: \(coordinator.planSnapshot.title)")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }
                Spacer()
                Button("Reload") {
                    Task { await coordinator.refreshPlanSnapshot() }
                }
                .buttonStyle(.bordered)
            }

            if coordinator.planSnapshot.days.isEmpty {
                Text(coordinator.viewPlanError.isEmpty ? "No plan available." : coordinator.viewPlanError)
                    .foregroundColor(coordinator.viewPlanError.isEmpty ? .secondary : .red)
            } else {
                Picker("Day", selection: $coordinator.selectedPlanDay) {
                    ForEach(coordinator.orderedPlanDays) { day in
                        Text(day.dayLabel).tag(day.dayLabel)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: coordinator.selectedPlanDay) {
                    if !coordinator.planBlockCatalog.contains(coordinator.planBlockFilter) {
                        coordinator.planBlockFilter = "All Blocks"
                    }
                }

                Text(coordinator.selectedPlanDayPositionText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Button("Previous") {
                        coordinator.moveToAdjacentPlanDay(step: -1)
                    }
                    .buttonStyle(.bordered)

                    Button("Next") {
                        coordinator.moveToAdjacentPlanDay(step: 1)
                    }
                    .buttonStyle(.bordered)

                    TextField("Search exercises, blocks, notes", text: $coordinator.planSearchQuery)
                        .textFieldStyle(.roundedBorder)

                    Picker("Block", selection: $coordinator.planBlockFilter) {
                        ForEach(coordinator.planBlockCatalog, id: \.self) { block in
                            Text(block).tag(block)
                        }
                    }
                    .pickerStyle(.menu)
                }

                HStack {
                    Toggle("Show Notes", isOn: $coordinator.showPlanNotes)
                        .toggleStyle(.switch)
                    Toggle("Show Logs", isOn: $coordinator.showPlanLogs)
                        .toggleStyle(.switch)
                    Toggle("Logged Only", isOn: $coordinator.showPlanLoggedOnly)
                        .toggleStyle(.switch)

                    Spacer()

                    Button("Reset Filters") {
                        coordinator.resetPlanFilters()
                    }
                    .buttonStyle(.bordered)

                    Button("Copy Day") {
                        let text = coordinator.buildSelectedPlanDayExportText()
                        if !text.isEmpty {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(text, forType: .string)
                        }
                    }
                    .buttonStyle(.bordered)
                }

                HStack(spacing: 10) {
                    MetricCardView(title: "Exercises", value: "\(coordinator.planVisibleExerciseCount)")
                    MetricCardView(title: "Blocks", value: "\(coordinator.planDayStats.blockCount)")
                    MetricCardView(title: "Est. Volume", value: String(format: "%.0f kg", coordinator.planDayStats.estimatedVolumeKG))
                    MetricCardView(title: "Logged Rows", value: "\(coordinator.planDayCompletionCount)")
                    MetricCardView(title: "Completion", value: String(format: "%.1f%%", coordinator.planDayCompletionPercent))
                }

                if coordinator.filteredPlanExercises.isEmpty {
                    Text("No exercises match the current filters. Try Reset Filters.")
                        .foregroundStyle(.secondary)
                } else {
                    List(coordinator.filteredPlanExercises) { exercise in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(exercise.block) - \(exercise.exercise)")
                                .font(.headline)
                            Text("\(exercise.sets) x \(exercise.reps) @ \(exercise.load) kg")
                            if !exercise.rest.isEmpty {
                                Text("Rest: \(exercise.rest)")
                                    .foregroundStyle(.secondary)
                            }
                            if coordinator.showPlanNotes, !exercise.notes.isEmpty {
                                Text("Notes: \(exercise.notes)")
                                    .foregroundStyle(.secondary)
                            }
                            if coordinator.showPlanLogs, !exercise.log.isEmpty {
                                Text("Log: \(exercise.log)")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            Spacer()
        }
    }
}

struct LogWorkoutPageView: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Log Workout")
                .font(.largeTitle.bold())

            StatusBannerView(banner: coordinator.statusBanner)

            HStack {
                Text(coordinator.loggerSession.dayLabel.isEmpty ? "No workout loaded" : "\(coordinator.loggerSession.dayLabel) | \(coordinator.loggerSession.sheetName)")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Load Today") {
                    Task { await coordinator.refreshLoggerSession() }
                }
                .buttonStyle(.bordered)

                Button("Save Logs") {
                    Task { await coordinator.saveLoggerSession() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!coordinator.loggerSaveDisabledReason.isEmpty)
            }

            HStack(spacing: 10) {
                MetricCardView(title: "Completed", value: "\(coordinator.loggerCompletionCount)/\(coordinator.loggerTotalCount)")
                MetricCardView(title: "Invalid RPE", value: "\(coordinator.loggerInvalidRPECount)")
                MetricCardView(title: "Unsaved", value: coordinator.hasUnsavedLoggerChanges ? "Yes" : "No")
                MetricCardView(title: "Visible", value: "\(coordinator.loggerVisibleCount)")
                MetricCardView(title: "Pending", value: "\(coordinator.loggerPendingVisibleCount)")
            }

            ProgressView(value: coordinator.loggerCompletionPercent / 100.0) {
                Text("Completion")
            } currentValueLabel: {
                Text("\(Int(coordinator.loggerCompletionPercent.rounded()))%")
            }

            HStack {
                TextField("Search exercises, blocks, notes", text: $coordinator.loggerSearchQuery)
                    .textFieldStyle(.roundedBorder)

                Button("Mark All Done") {
                    coordinator.markAllDraftsDone()
                }
                .buttonStyle(.bordered)
                .disabled(coordinator.loggerSession.drafts.isEmpty)

                Button("Clear All Edits") {
                    coordinator.clearAllDraftEntries()
                }
                .buttonStyle(.bordered)
                .disabled(coordinator.loggerSession.drafts.isEmpty)

                Picker("Block", selection: $coordinator.loggerBlockFilter) {
                    ForEach(coordinator.loggerBlockCatalog, id: \.self) { block in
                        Text(block).tag(block)
                    }
                }
                .pickerStyle(.menu)

                Toggle("Show Incomplete Only", isOn: $coordinator.showLoggerIncompleteOnly)
                    .toggleStyle(.switch)

                Button("Reset Filters") {
                    coordinator.resetLoggerFilters()
                }
                .buttonStyle(.bordered)
            }

            if !coordinator.loggerSaveDisabledReason.isEmpty {
                Text(coordinator.loggerSaveDisabledReason)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            if coordinator.hasInvalidLoggerEntries {
                Text("Some RPE values are invalid. Use a value between 1 and 10.")
                    .foregroundStyle(.orange)
                    .font(.callout)
            }

            if coordinator.loggerSession.drafts.isEmpty {
                Text("No exercises available for logging yet.")
                    .foregroundStyle(.secondary)
            } else {
                GroupBox("Block Progress") {
                    if coordinator.loggerBlockProgressRows.isEmpty {
                        Text("No blocks loaded.")
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(coordinator.loggerBlockProgressRows) { row in
                                HStack {
                                    Text(row.block)
                                    Spacer()
                                    Text("\(row.completed)/\(row.total) (\(Int(row.completionPercent.rounded()))%)")
                                        .foregroundStyle(.secondary)
                                }
                                ProgressView(value: row.completionPercent / 100.0)
                            }
                        }
                    }
                }

                List {
                    ForEach($coordinator.loggerSession.drafts) { $draft in
                        if coordinator.shouldShowDraft(draft) {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: coordinator.draftCompletionIcon(draft))
                                        .foregroundStyle(coordinator.isDraftComplete(draft) ? .green : .secondary)
                                    Text("\(draft.block) - \(draft.exercise)")
                                        .font(.headline)
                                    Spacer()
                                    Button("Done") {
                                        coordinator.markDraftDone(draftID: draft.id)
                                    }
                                    .buttonStyle(.bordered)

                                    Button("Skip") {
                                        coordinator.markDraftSkip(draftID: draft.id)
                                    }
                                    .buttonStyle(.bordered)

                                    Button("Clear") {
                                        coordinator.clearDraftEntry(draftID: draft.id)
                                    }
                                    .buttonStyle(.bordered)
                                }

                                Text("\(draft.sets) x \(draft.reps) @ \(draft.load) kg")
                                    .foregroundStyle(.secondary)

                                TextField("Performance (e.g. Done or Skip)", text: $draft.performance)
                                    .textFieldStyle(.roundedBorder)
                                TextField("RPE (1-10)", text: $draft.rpe)
                                    .textFieldStyle(.roundedBorder)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(
                                                !coordinator.isValidRPE(draft.rpe) && !draft.rpe.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                                    ? Color.red
                                                    : Color.clear,
                                                lineWidth: 1
                                            )
                                    )
                                TextField("Notes", text: $draft.noteEntry)
                                    .textFieldStyle(.roundedBorder)

                                if !draft.existingLog.isEmpty {
                                    Text("Current: \(draft.existingLog)")
                                        .foregroundStyle(.secondary)
                                        .font(.caption)
                                }
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(coordinator.isDraftComplete(draft) ? Color.green.opacity(0.06) : Color.clear)
                            )
                        }
                    }
                }
            }

            Text("Write format: performance | RPE x | Notes: ... (Column H)")
                .foregroundStyle(.secondary)

            Spacer()
        }
    }
}

struct ProgressPageView: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Progress")
                .font(.largeTitle.bold())

            Text(coordinator.progressSummary.sourceText)
                .foregroundStyle(.secondary)

            StatusBannerView(banner: coordinator.statusBanner)

            HStack(spacing: 10) {
                MetricCardView(title: "Completion", value: coordinator.progressSummary.completionRateText)
                MetricCardView(title: "Weekly Volume", value: coordinator.progressSummary.weeklyVolumeText)
                MetricCardView(title: "Recent Logs", value: coordinator.progressSummary.recentLoggedText)
            }

            GroupBox("Top Logged Exercises") {
                if coordinator.topExercises.isEmpty {
                    Text("No top exercise data yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(coordinator.topExercises) { row in
                        HStack {
                            Text(row.exerciseName)
                            Spacer()
                            Text("\(row.loggedCount) logs / \(row.sessionCount) sessions")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Text("Metrics refreshed: \(coordinator.formatTimestamp(coordinator.lastAnalyticsRefreshAt))")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Refresh Metrics") {
                coordinator.refreshAnalytics()
            }
            .buttonStyle(.bordered)
            Spacer()
        }
    }
}

struct WeeklyReviewPageView: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Weekly Review")
                .font(.largeTitle.bold())

            StatusBannerView(banner: coordinator.statusBanner)

            HStack {
                TextField("Filter by sheet name", text: $coordinator.weeklyReviewQuery)
                    .textFieldStyle(.roundedBorder)

                Picker("Sort", selection: $coordinator.weeklyReviewSort) {
                    ForEach(WeeklyReviewSortMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.menu)
            }

            HStack(spacing: 10) {
                MetricCardView(title: "Avg Completion", value: String(format: "%.1f%%", coordinator.weeklyReviewAverageCompletion))
                MetricCardView(title: "Best Week", value: coordinator.weeklyReviewBestWeek?.completionRateText ?? "n/a")
                MetricCardView(title: "Worst Week", value: coordinator.weeklyReviewWorstWeek?.completionRateText ?? "n/a")
            }

            HStack {
                Text("Best: \(coordinator.weeklyReviewBestWeek?.sheetName ?? "n/a")")
                Text("Worst: \(coordinator.weeklyReviewWorstWeek?.sheetName ?? "n/a")")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if coordinator.filteredWeeklyReviewSummaries.isEmpty {
                Text("No weekly summaries in local DB yet.")
                    .foregroundStyle(.secondary)
            } else {
                List(coordinator.filteredWeeklyReviewSummaries) { week in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(week.sheetName)
                                .font(.headline)
                            Spacer()
                            Text(week.completionRateText)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(completionBadgeColor(week))
                                .clipShape(Capsule())
                        }
                        Text("Sessions: \(week.sessions)")
                        Text("Logged: \(week.loggedCount)/\(week.totalCount)")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Text("Showing \(coordinator.filteredWeeklyReviewSummaries.count) week(s)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("Refresh Weekly Review") {
                coordinator.refreshAnalytics()
            }
            .buttonStyle(.bordered)

            Spacer()
        }
    }

    private func completionBadgeColor(_ week: WeeklyReviewSummary) -> Color {
        let completion = week.totalCount == 0 ? 0 : (Double(week.loggedCount) / Double(week.totalCount)) * 100
        if completion >= 80 {
            return .green.opacity(0.25)
        }
        if completion >= 50 {
            return .orange.opacity(0.25)
        }
        return .red.opacity(0.25)
    }
}

struct ExerciseHistoryPageView: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Exercise History")
                    .font(.largeTitle.bold())
                Spacer()
                Text("\(coordinator.historyPoints.count) entries")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            StatusBannerView(banner: coordinator.statusBanner)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search exercise name", text: $coordinator.selectedHistoryExercise)
                    .textFieldStyle(.roundedBorder)
                Button("Clear") { coordinator.selectedHistoryExercise = "" }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("Refresh") { coordinator.refreshExerciseCatalog() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }

            if !coordinator.filteredExerciseCatalog.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(coordinator.filteredExerciseCatalog.prefix(10)), id: \.self) { name in
                            Button(name) { coordinator.applyHistorySuggestion(name) }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                }
            }

            // MARK: - Summary Metrics with Trend
            let summary = coordinator.exerciseHistorySummary
            if summary.entryCount > 0 {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                    ExerciseMetricCard(
                        title: "Latest Load",
                        value: String(format: "%.1f kg", summary.latestLoad),
                        badge: summary.latestLoad >= summary.maxLoad && summary.latestLoad > 0 ? "PR" : nil,
                        badgeColor: .yellow
                    )
                    ExerciseMetricCard(
                        title: "All-Time Max",
                        value: String(format: "%.1f kg", summary.maxLoad),
                        badge: nil,
                        badgeColor: .clear
                    )
                    ExerciseMetricCard(
                        title: "Trend",
                        value: String(format: "%+.1f kg", summary.loadDelta),
                        badge: trendBadge(delta: summary.loadDelta),
                        badgeColor: summary.loadDelta > 0 ? .green : summary.loadDelta < 0 ? .red : .gray
                    )
                    ExerciseMetricCard(
                        title: "Latest",
                        value: summary.latestDateISO.isEmpty ? "n/a" : summary.latestDateISO,
                        badge: nil,
                        badgeColor: .clear
                    )
                }

                // MARK: - Load Sparkline
                if coordinator.historyPoints.count >= 2 {
                    GroupBox("Load History") {
                        ExerciseLoadSparkline(points: coordinator.historyPoints)
                            .frame(height: 80)
                            .frame(maxWidth: .infinity)
                    }
                }
            }

            if coordinator.historyPoints.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("No History Found")
                                .font(.headline)
                            Text(coordinator.historyEmptyReason)
                                .foregroundStyle(.secondary)
                                .font(.callout)
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                if !coordinator.filteredExerciseCatalog.isEmpty {
                    Text("Known Exercises")
                        .font(.headline)
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(coordinator.filteredExerciseCatalog, id: \.self) { name in
                                Button(name) { coordinator.applyHistorySuggestion(name) }
                                    .buttonStyle(.bordered)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                } else {
                    Text("No exercise catalog yet. Use DB Status > Rebuild DB Cache.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                let maxLoad = coordinator.historyPoints.map(\.load).max() ?? 0
                List(coordinator.historyPoints) { point in
                    HStack(alignment: .center, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(point.dateISO)
                                    .font(.system(.callout, design: .monospaced))
                                if point.load >= maxLoad && point.load > 0 {
                                    Text("PR")
                                        .font(.system(.caption2, design: .rounded).bold())
                                        .foregroundStyle(.yellow)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(.yellow.opacity(0.15))
                                        .clipShape(Capsule())
                                }
                            }
                            if !point.notes.isEmpty {
                                Text(point.notes)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            if point.load > 0 {
                                Text(String(format: "%.1f kg", point.load))
                                    .font(.system(.body, design: .monospaced).bold())
                                    .foregroundStyle(point.load >= maxLoad ? .yellow : .primary)
                            } else {
                                Text("- kg")
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            Text("x \(point.reps)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func trendBadge(delta: Double) -> String? {
        if delta > 0 { return "UP" }
        if delta < 0 { return "DOWN" }
        return "HOLD"
    }
}

struct ExerciseMetricCard: View {
    let title: String
    let value: String
    let badge: String?
    let badgeColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Text(value)
                    .font(.title3.bold())
                if let badge {
                    Text(badge)
                        .font(.system(.caption2, design: .rounded).bold())
                        .foregroundStyle(badgeColor)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(badgeColor.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct ExerciseLoadSparkline: View {
    let points: [ExerciseHistoryPoint]

    var body: some View {
        let loads = points.reversed().map(\.load)
        let maxVal = loads.max() ?? 1
        let minVal = loads.min() ?? 0
        let range = max(maxVal - minVal, 1)

        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let stepX = loads.count > 1 ? width / CGFloat(loads.count - 1) : width

            Path { path in
                for (index, load) in loads.enumerated() {
                    let x = CGFloat(index) * stepX
                    let y = height - ((CGFloat(load - minVal) / CGFloat(range)) * height * 0.85 + height * 0.075)
                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(
                LinearGradient(
                    colors: [.blue, .purple],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            )

            // Dot on the latest point
            if let last = loads.last {
                let x = CGFloat(loads.count - 1) * stepX
                let y = height - ((CGFloat(last - minVal) / CGFloat(range)) * height * 0.85 + height * 0.075)
                Circle()
                    .fill(.purple)
                    .frame(width: 6, height: 6)
                    .position(x: x, y: y)
            }

            // Min/Max labels
            VStack {
                Text(String(format: "%.0f kg", maxVal))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
                Spacer()
                Text(String(format: "%.0f kg", minVal))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

struct SettingsPageView: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Settings")
                    .font(.largeTitle.bold())

                Text("Configure your training profile. These values feed into AI plan generation.")
                    .foregroundStyle(.secondary)

                StatusBannerView(banner: coordinator.statusBanner)

                GroupBox("One Rep Max (1RM) — Main Lifts") {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Enter your current 1RM for each lift in kg. These values are sent to Claude when generating supplemental workouts so percentage-based loads are accurate.")
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        ForEach($coordinator.oneRepMaxFields) { $field in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(alignment: .center, spacing: 12) {
                                    Text(field.liftName)
                                        .font(.headline)
                                        .frame(width: 120, alignment: .leading)

                                    TextField("e.g. 140", text: $field.inputText)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 100)

                                    Text("kg")
                                        .foregroundStyle(.secondary)

                                    Spacer()

                                    VStack(alignment: .trailing, spacing: 2) {
                                        if let value = field.parsedValue {
                                            Text(String(format: "%.1f kg", value))
                                                .font(.caption)
                                                .foregroundStyle(.green)
                                        }
                                        Text("Updated: \(field.lastUpdatedText)")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                }

                                if !field.validationMessage.isEmpty {
                                    Text(field.validationMessage)
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                            }
                        }

                        Divider()

                        HStack {
                            Button("Save 1RM Values") {
                                coordinator.saveOneRepMaxes()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!coordinator.oneRepMaxAllValid)

                            if !coordinator.oneRepMaxStatus.isEmpty {
                                Text(coordinator.oneRepMaxStatus)
                                    .font(.caption)
                                    .foregroundStyle(
                                        coordinator.oneRepMaxStatus.contains("saved") ? .green : .orange
                                    )
                            }
                        }

                        if !coordinator.oneRepMaxesAreFilled {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                Text("Set all three 1RM values before generating plans. Missing: \(coordinator.oneRepMaxMissingLifts.joined(separator: ", ")).")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        } else {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text("All 1RM values are set. These will be included in Claude API context during plan generation.")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Percentage Reference") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Common training percentages based on your current 1RMs:")
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        let percentages = [0.50, 0.60, 0.70, 0.80, 0.85, 0.90, 0.95]
                        let config = coordinator.oneRepMaxFields

                        HStack(alignment: .top, spacing: 20) {
                            ForEach(config) { field in
                                if let value = field.parsedValue {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(field.liftName)
                                            .font(.caption.bold())
                                        ForEach(percentages, id: \.self) { pct in
                                            HStack {
                                                Text("\(Int(pct * 100))%")
                                                    .font(.system(.caption, design: .monospaced))
                                                    .frame(width: 36, alignment: .trailing)
                                                Text(String(format: "%.1f kg", value * pct))
                                                    .font(.system(.caption, design: .monospaced))
                                            }
                                            .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }

                        if !coordinator.oneRepMaxesAreFilled {
                            Text("Enter 1RM values above to see percentage breakdowns.")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("App Credentials") {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Anthropic API Key")
                                .font(.caption.bold())
                            Spacer()
                            Text(coordinator.setupState.anthropicAPIKey.isEmpty ? "Not set" : "Configured")
                                .font(.caption)
                                .foregroundStyle(coordinator.setupState.anthropicAPIKey.isEmpty ? .red : .green)
                        }
                        HStack {
                            Text("Spreadsheet ID")
                                .font(.caption.bold())
                            Spacer()
                            Text(coordinator.setupState.spreadsheetID.isEmpty ? "Not set" : "Configured")
                                .font(.caption)
                                .foregroundStyle(coordinator.setupState.spreadsheetID.isEmpty ? .red : .green)
                        }
                        HStack {
                            Text("Google Auth")
                                .font(.caption.bold())
                            Spacer()
                            let hint = coordinator.setupState.googleAuthHint.trimmingCharacters(in: .whitespacesAndNewlines)
                            Text(hint.isEmpty || hint == "OAuth token path" ? "Not set" : "Configured")
                                .font(.caption)
                                .foregroundStyle(hint.isEmpty || hint == "OAuth token path" ? .orange : .green)
                        }

                        Button("Edit Credentials (Back to Setup)") {
                            coordinator.markSetupIncomplete()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer()
            }
        }
        .onAppear {
            coordinator.loadOneRepMaxFields()
        }
    }
}

// TEMP: TEST HARNESS — REMOVE AFTER VERIFICATION
struct APITestHarnessPageView: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Text("API Test Harness")
                        .font(.largeTitle.bold())
                    Spacer()
                    Text("⚠️ TEMPORARY — Remove after verification")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.orange.opacity(0.1))
                        .clipShape(Capsule())
                }

                Text("Send a single Fort workout to the Claude API and inspect the raw request/response. Verify 1RM values appear in context and percentage calculations are correct.")
                    .foregroundStyle(.secondary)

                StatusBannerView(banner: coordinator.statusBanner)

                // MARK: - 1RM Status
                GroupBox("1RM Context Check") {
                    VStack(alignment: .leading, spacing: 6) {
                        if coordinator.oneRepMaxesAreFilled {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text("All 1RM values set — these will be injected into the API prompt.")
                                    .font(.callout)
                            }
                            ForEach(coordinator.oneRepMaxFields) { field in
                                if let value = field.parsedValue {
                                    HStack(spacing: 8) {
                                        Text(field.liftName)
                                            .font(.system(.caption, design: .monospaced).bold())
                                        Text(String(format: "%.1f kg", value))
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                        Text("→ 80%: \(String(format: "%.1f", value * 0.80)) kg")
                                            .font(.system(.caption2, design: .monospaced))
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                        } else {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                Text("1RM values not set. Go to Settings first.")
                                    .font(.callout)
                                Button("Go to Settings") { coordinator.quickNavigate(to: .settings) }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // MARK: - Fort Input
                GroupBox("Fort Workout Input (Monday slot)") {
                    VStack(alignment: .leading, spacing: 8) {
                        TextEditor(text: $coordinator.testHarnessFortInput)
                            .frame(height: 150)
                            .font(.system(.body, design: .monospaced))

                        HStack {
                            Button("Load Template") { coordinator.applyTestHarnessTemplate() }
                                .buttonStyle(.bordered)
                            Button("Clear") { coordinator.testHarnessFortInput = "" }
                                .buttonStyle(.bordered)
                            Spacer()
                            Text("\(coordinator.testHarnessFortInput.count) chars")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // MARK: - Payload Preview
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Payload Preview")
                                .font(.headline)
                            Spacer()
                            Toggle("Show", isOn: $coordinator.testHarnessShowPayload)
                                .toggleStyle(.switch)
                                .controlSize(.small)
                        }

                        if coordinator.testHarnessShowPayload {
                            ScrollView {
                                Text(coordinator.testHarnessPayloadPreview)
                                    .font(.system(.caption, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            }
                            .frame(maxHeight: 250)
                            .padding(8)
                            .background(Color(.textBackgroundColor).opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }

                // MARK: - Send Button
                HStack(spacing: 12) {
                    Button(coordinator.testHarnessIsSending ? "Sending..." : "Send to Claude") {
                        Task { await coordinator.sendTestHarnessRequest() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(!coordinator.testHarnessCanSend)

                    Button("Clear Results") { coordinator.clearTestHarnessResult() }
                        .buttonStyle(.bordered)

                    if coordinator.testHarnessIsSending {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Spacer()

                    if !coordinator.setupState.validate().isEmpty {
                        Text("Setup incomplete — configure API key first")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                // MARK: - Error Display
                if !coordinator.testHarnessResult.errorMessage.isEmpty {
                    GroupBox("Error") {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Image(systemName: "xmark.octagon.fill")
                                    .foregroundStyle(.red)
                                Text("API call failed")
                                    .font(.headline)
                                    .foregroundStyle(.red)
                            }
                            Text(coordinator.testHarnessResult.errorMessage)
                                .font(.system(.callout, design: .monospaced))
                                .textSelection(.enabled)
                                .foregroundStyle(.red.opacity(0.8))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                // MARK: - Response Metadata
                if !coordinator.testHarnessResult.rawResponse.isEmpty {
                    GroupBox("Response Metadata") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                            testHarnessMetricCard(title: "Model", value: coordinator.testHarnessResult.model)
                            testHarnessMetricCard(title: "Input Tokens", value: "\(coordinator.testHarnessResult.inputTokens)")
                            testHarnessMetricCard(title: "Output Tokens", value: "\(coordinator.testHarnessResult.outputTokens)")
                            testHarnessMetricCard(
                                title: "Response Time",
                                value: String(format: "%.2fs", coordinator.testHarnessResult.responseTimeSeconds)
                            )
                            testHarnessMetricCard(
                                title: "1RM in Prompt",
                                value: coordinator.testHarnessResult.containsOneRepMax ? "YES ✓" : "NO ✗"
                            )
                            testHarnessMetricCard(
                                title: "1RM Exercises",
                                value: coordinator.testHarnessResult.oneRepMaxExercises.isEmpty
                                    ? "None"
                                    : coordinator.testHarnessResult.oneRepMaxExercises.joined(separator: ", ")
                            )
                        }
                    }

                    // MARK: - Verification Checklist
                    GroupBox("Verification Checklist") {
                        VStack(alignment: .leading, spacing: 6) {
                            verificationRow(
                                "1RM values present in prompt",
                                passed: coordinator.testHarnessResult.containsOneRepMax
                            )
                            verificationRow(
                                "Response is non-empty",
                                passed: !coordinator.testHarnessResult.rawResponse.isEmpty
                            )
                            verificationRow(
                                "Model is claude-sonnet-4-6",
                                passed: coordinator.testHarnessResult.model.contains("claude")
                            )
                            verificationRow(
                                "Response time < 30s",
                                passed: coordinator.testHarnessResult.responseTimeSeconds < 30
                            )
                            verificationRow(
                                "Contains markdown headers (##)",
                                passed: coordinator.testHarnessResult.rawResponse.contains("##")
                            )
                            verificationRow(
                                "Contains exercise notation (x ... @ ... kg)",
                                passed: coordinator.testHarnessResult.rawResponse.contains("kg")
                            )
                            verificationRow(
                                "No error",
                                passed: coordinator.testHarnessResult.errorMessage.isEmpty
                            )
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // MARK: - Raw Response
                    GroupBox("Raw Response") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("\(coordinator.testHarnessResult.rawResponse.count) characters")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("Copy") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(coordinator.testHarnessResult.rawResponse, forType: .string)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            ScrollView {
                                Text(coordinator.testHarnessResult.rawResponse)
                                    .font(.system(.caption, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            }
                            .frame(maxHeight: 400)
                            .padding(8)
                            .background(Color(.textBackgroundColor).opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }

                    // MARK: - Full Prompt (Sent to API)
                    if !coordinator.testHarnessResult.prompt.isEmpty {
                        GroupBox("Full Prompt (Sent to API)") {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("\(coordinator.testHarnessResult.prompt.count) characters")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Button("Copy") {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(coordinator.testHarnessResult.prompt, forType: .string)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                                ScrollView {
                                    Text(coordinator.testHarnessResult.prompt)
                                        .font(.system(.caption, design: .monospaced))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .textSelection(.enabled)
                                }
                                .frame(maxHeight: 300)
                                .padding(8)
                                .background(Color(.textBackgroundColor).opacity(0.5))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    }
                }

                Spacer()
            }
        }
        .onAppear {
            coordinator.loadOneRepMaxFields()
        }
    }

    private func testHarnessMetricCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.callout, design: .monospaced).bold())
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func verificationRow(_ label: String, passed: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(passed ? .green : .red)
            Text(label)
                .font(.callout)
            Spacer()
            Text(passed ? "PASS" : "FAIL")
                .font(.system(.caption, design: .monospaced).bold())
                .foregroundStyle(passed ? .green : .red)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(passed ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
                .clipShape(Capsule())
        }
    }
}
// END TEMP: TEST HARNESS

struct DBStatusPageView: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DB Status")
                .font(.largeTitle.bold())

            Text(coordinator.dbStatusText)
                .foregroundStyle(.secondary)

            StatusBannerView(banner: coordinator.statusBanner)

            HStack {
                MetricCardView(title: "Exercises", value: "\(coordinator.dbHealthSnapshot.exerciseCount)")
                MetricCardView(title: "Sessions", value: "\(coordinator.dbHealthSnapshot.sessionCount)")
                MetricCardView(title: "Rows", value: "\(coordinator.dbHealthSnapshot.logCount)")
                MetricCardView(title: "Non-Empty Logs", value: "\(coordinator.dbHealthSnapshot.nonEmptyLogCount)")
            }

            Text("Latest session date: \(coordinator.dbHealthSnapshot.latestSessionDateISO.isEmpty ? "n/a" : coordinator.dbHealthSnapshot.latestSessionDateISO)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Last rebuild: \(coordinator.formatTimestamp(coordinator.lastDBRebuildAt))")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("Rebuild DB Cache") {
                    Task {
                        await coordinator.triggerRebuildDBCache()
                    }
                }
                .buttonStyle(.bordered)
                .disabled(!coordinator.dbRebuildDisabledReason.isEmpty)

                Button("Refresh DB Metrics") {
                    coordinator.refreshAnalytics()
                }
                .buttonStyle(.bordered)

                Button("Re-auth") {
                    coordinator.triggerReauth()
                }
                .buttonStyle(.bordered)
            }

            if !coordinator.dbRebuildDisabledReason.isEmpty {
                Text(coordinator.dbRebuildDisabledReason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if coordinator.isRebuildingDBCache {
                ProgressView("Importing weekly sheets into local DB...")
                    .controlSize(.small)
            }

            if !coordinator.dbRebuildSummary.isEmpty {
                GroupBox("Last Rebuild") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(coordinator.formattedDBRebuildSummaryLines, id: \.self) { line in
                            Text("• \(line)")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .font(.system(.callout, design: .monospaced))
                        }
                    }
                }
            }

            GroupBox("Top Exercises") {
                if coordinator.dbHealthSnapshot.topExercises.isEmpty {
                    Text("No top exercise metrics yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(coordinator.dbHealthSnapshot.topExercises) { row in
                        HStack {
                            Text(row.exerciseName)
                            Spacer()
                            Text("\(row.loggedCount) logs")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            GroupBox("Recent Sessions") {
                if coordinator.dbHealthSnapshot.recentSessions.isEmpty {
                    Text("No recent sessions yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(coordinator.dbHealthSnapshot.recentSessions) { row in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(row.dayLabel)
                                Text(row.sheetName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(row.loggedRows)/\(row.totalRows)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            GroupBox("Weekday Completion") {
                if coordinator.dbHealthSnapshot.weekdayCompletion.isEmpty {
                    Text("No weekday completion metrics yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(coordinator.dbHealthSnapshot.weekdayCompletion) { row in
                        HStack {
                            Text(row.dayName.isEmpty ? "Unknown" : row.dayName)
                            Spacer()
                            Text("\(row.loggedRows)/\(row.totalRows) (\(Int(coordinator.dbWeekdayCompletionPercent(row).rounded()))%)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Spacer()
        }
    }
}
