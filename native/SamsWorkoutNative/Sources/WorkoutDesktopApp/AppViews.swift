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
            VStack(alignment: .leading, spacing: 12) {
                Text("Dashboard")
                    .font(.largeTitle.bold())

                Text(coordinator.planSnapshot.summary.isEmpty ? "Source of truth: Google Sheets. Local cache: GRDB." : coordinator.planSnapshot.summary)
                    .foregroundStyle(.secondary)

                StatusBannerView(banner: coordinator.statusBanner)

                HStack {
                    Text("Status")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(coordinator.statusHeadline)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.thinMaterial)
                        .clipShape(Capsule())
                    Spacer()
                }

                GroupBox("Health Strip") {
                    HStack(spacing: 12) {
                        Label("Logger completion \(Int(coordinator.loggerCompletionPercent.rounded()))%", systemImage: "checkmark.circle")
                        Label("Invalid RPE \(coordinator.loggerInvalidRPECount)", systemImage: "exclamationmark.triangle")
                        Label("Weekly avg \(String(format: "%.1f%%", coordinator.weeklyReviewAverageCompletion))", systemImage: "chart.bar")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                    MetricCardView(title: "Plan Title", value: coordinator.planSnapshot.title.isEmpty ? "No plan loaded" : coordinator.planSnapshot.title)
                    MetricCardView(title: "Days", value: "\(coordinator.planDayCount)")
                    MetricCardView(title: "All Exercises", value: "\(coordinator.planExerciseCount)")
                    MetricCardView(title: "Selected Day", value: coordinator.selectedPlanDetail?.dayLabel ?? "-")
                    MetricCardView(title: "Exercises", value: "\(coordinator.planDayStats.exerciseCount)")
                    MetricCardView(title: "Est. Volume", value: String(format: "%.0f kg", coordinator.planDayStats.estimatedVolumeKG))
                    MetricCardView(title: "Pending Logs", value: "\(coordinator.loggerPendingVisibleCount)")
                    MetricCardView(title: "Edited Logs", value: "\(coordinator.loggerEditedCount)")
                }

                GroupBox("Quick Refresh") {
                    HStack {
                        Button("Refresh Plan") {
                            Task { await coordinator.refreshPlanSnapshot() }
                        }
                        .buttonStyle(.bordered)

                        Button("Refresh Logger") {
                            Task { await coordinator.refreshLoggerSession() }
                        }
                        .buttonStyle(.bordered)

                        Button("Refresh Analytics") {
                            coordinator.refreshAnalytics()
                        }
                        .buttonStyle(.bordered)
                    }
                }

                GroupBox("Quick Actions") {
                    HStack {
                        Button("Go Generate") { coordinator.quickNavigate(to: .generatePlan) }
                        Button("Go View") { coordinator.quickNavigate(to: .viewPlan) }
                        Button("Go Log") { coordinator.quickNavigate(to: .logWorkout) }
                        Button("Go DB") { coordinator.quickNavigate(to: .dbStatus) }
                    }
                    .buttonStyle(.bordered)
                }

                GroupBox("Last Refresh") {
                    HStack {
                        Text("Plan: \(coordinator.formatTimestamp(coordinator.lastPlanRefreshAt))")
                        Text("Logger: \(coordinator.formatTimestamp(coordinator.lastLoggerRefreshAt))")
                        Text("Analytics: \(coordinator.formatTimestamp(coordinator.lastAnalyticsRefreshAt))")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Text(coordinator.analyticsFreshnessText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 10)], spacing: 10) {
                    ForEach(coordinator.dashboardDays) { day in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(day.title).font(.headline)
                            Text("\(day.blocks) blocks")
                            Text(day.source.rawValue)
                                .foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
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
            Text("Exercise History")
                .font(.largeTitle.bold())

            StatusBannerView(banner: coordinator.statusBanner)

            HStack(spacing: 8) {
                TextField("Search exercise name", text: $coordinator.selectedHistoryExercise)
                    .textFieldStyle(.roundedBorder)
                Button("Clear") {
                    coordinator.selectedHistoryExercise = ""
                }
                .buttonStyle(.bordered)
                Button("Refresh") {
                    coordinator.refreshExerciseCatalog()
                }
                .buttonStyle(.bordered)
            }

            if !coordinator.filteredExerciseCatalog.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(coordinator.filteredExerciseCatalog.prefix(8)), id: \.self) { name in
                            Button(name) {
                                coordinator.applyHistorySuggestion(name)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }

            HStack(spacing: 10) {
                MetricCardView(title: "Entries", value: "\(coordinator.exerciseHistorySummary.entryCount)")
                MetricCardView(title: "Latest Load", value: String(format: "%.1f kg", coordinator.exerciseHistorySummary.latestLoad))
                MetricCardView(title: "Max Load", value: String(format: "%.1f kg", coordinator.exerciseHistorySummary.maxLoad))
                MetricCardView(title: "Delta", value: String(format: "%+.1f kg", coordinator.exerciseHistorySummary.loadDelta))
                MetricCardView(title: "Latest Date", value: coordinator.exerciseHistorySummary.latestDateISO.isEmpty ? "n/a" : coordinator.exerciseHistorySummary.latestDateISO)
            }

            Text("\(coordinator.historyPoints.count) history row(s)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if coordinator.historyPoints.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No Local History Found")
                        .font(.headline)
                    Text(coordinator.historyEmptyReason)
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
                .padding(10)
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                if !coordinator.filteredExerciseCatalog.isEmpty {
                    Text("Known Exercises")
                        .font(.headline)
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(coordinator.filteredExerciseCatalog, id: \.self) { name in
                                Button(name) {
                                    coordinator.applyHistorySuggestion(name)
                                }
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
                List(coordinator.historyPoints) { point in
                    VStack(alignment: .leading, spacing: 2) {
                        if point.load > 0 {
                            Text("\(point.dateISO) | \(point.load, specifier: "%.1f") kg x \(point.reps)")
                        } else {
                            Text("\(point.dateISO) | - kg x \(point.reps)")
                        }
                        if point.notes.isEmpty {
                            Text("No notes").foregroundStyle(.secondary)
                        } else {
                            Text(point.notes).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}

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
