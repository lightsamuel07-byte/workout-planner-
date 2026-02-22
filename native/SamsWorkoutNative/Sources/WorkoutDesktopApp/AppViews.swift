import SwiftUI

struct NativeWorkoutRootView: View {
    @StateObject private var coordinator = AppCoordinator(gateway: LiveAppGateway())

    var body: some View {
        Group {
            if coordinator.isSetupComplete {
                if coordinator.isUnlocked {
                    NavigationSplitView {
                        List(AppRoute.allCases, selection: $coordinator.route) { route in
                            Text(route.rawValue)
                                .tag(route)
                        }
                        .frame(minWidth: 220)
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

struct SetupFlowView: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Setup")
                .font(.largeTitle.bold())

            TextField("Anthropic API Key", text: $coordinator.setupState.anthropicAPIKey)
                .textFieldStyle(.roundedBorder)

            TextField("Google Spreadsheet ID", text: $coordinator.setupState.spreadsheetID)
                .textFieldStyle(.roundedBorder)

            TextField("Google Auth Hint", text: $coordinator.setupState.googleAuthHint)
                .textFieldStyle(.roundedBorder)

            SecureField("Local App Password (optional)", text: $coordinator.setupState.localAppPassword)
                .textFieldStyle(.roundedBorder)

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
            }

            if !coordinator.generationStatus.isEmpty {
                Text(coordinator.generationStatus)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }
}

struct UnlockView: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Unlock App")
                .font(.largeTitle.bold())
            Text("Enter your local app password to continue.")
                .foregroundStyle(.secondary)

            SecureField("App Password", text: $coordinator.unlockInput)
                .textFieldStyle(.roundedBorder)

            Button("Unlock") {
                coordinator.unlock()
            }
            .buttonStyle(.borderedProminent)

            if !coordinator.unlockError.isEmpty {
                Text(coordinator.unlockError)
                    .foregroundStyle(.red)
            }

            Button("Back To Setup") {
                coordinator.markSetupIncomplete()
            }
            .buttonStyle(.bordered)

            Spacer()
        }
    }
}

struct DashboardPageView: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Dashboard")
                .font(.largeTitle.bold())

            Text(coordinator.planSnapshot.summary.isEmpty ? "Source of truth: Google Sheets. Local cache: GRDB." : coordinator.planSnapshot.summary)
                .foregroundStyle(.secondary)

            HStack {
                Button("Refresh Plan") {
                    Task { await coordinator.refreshPlanSnapshot() }
                }
                .buttonStyle(.bordered)

                Button("Refresh Logger") {
                    Task { await coordinator.refreshLoggerSession() }
                }
                .buttonStyle(.bordered)
            }

            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                ForEach(coordinator.dashboardDays) { day in
                    GridRow {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(day.title).font(.headline)
                            Text("\(day.blocks) blocks")
                            Text(day.source.rawValue).foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }

            if !coordinator.viewPlanError.isEmpty {
                Text(coordinator.viewPlanError)
                    .foregroundStyle(.red)
            }

            Spacer()
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

                Group {
                    Text("Monday Fort Input")
                    TextEditor(text: $coordinator.generationInput.monday).frame(height: 130)

                    Text("Wednesday Fort Input")
                    TextEditor(text: $coordinator.generationInput.wednesday).frame(height: 130)

                    Text("Friday Fort Input")
                    TextEditor(text: $coordinator.generationInput.friday).frame(height: 130)
                }
                .font(.headline)

                HStack {
                    Button(coordinator.isGenerating ? "Generating..." : "Generate") {
                        Task { await coordinator.runGeneration() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!coordinator.generationInput.canGenerate || coordinator.isGenerating)

                    Button("Re-auth") {
                        coordinator.triggerReauth()
                    }
                    .buttonStyle(.bordered)
                }

                if !coordinator.generationStatus.isEmpty {
                    Text(coordinator.generationStatus)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct ViewPlanPageView: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("View Plan")
                .font(.largeTitle.bold())

            HStack {
                Text("Source: \(coordinator.planSnapshot.source.rawValue)")
                    .foregroundStyle(.secondary)
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
                    ForEach(coordinator.planSnapshot.days) { day in
                        Text(day.dayLabel).tag(day.dayLabel)
                    }
                }
                .pickerStyle(.segmented)

                if let day = coordinator.selectedPlanDetail {
                    List(day.exercises) { exercise in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(exercise.block) - \(exercise.exercise)")
                                .font(.headline)
                            Text("\(exercise.sets) x \(exercise.reps) @ \(exercise.load) kg")
                            if !exercise.rest.isEmpty {
                                Text("Rest: \(exercise.rest)")
                                    .foregroundStyle(.secondary)
                            }
                            if !exercise.notes.isEmpty {
                                Text("Notes: \(exercise.notes)")
                                    .foregroundStyle(.secondary)
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
                .disabled(coordinator.loggerSession.drafts.isEmpty)
            }

            if coordinator.loggerSession.drafts.isEmpty {
                Text("No exercises available for logging yet.")
                    .foregroundStyle(.secondary)
            } else {
                List {
                    ForEach($coordinator.loggerSession.drafts) { $draft in
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(draft.block) - \(draft.exercise)")
                                .font(.headline)
                            Text("\(draft.sets) x \(draft.reps) @ \(draft.load) kg")
                                .foregroundStyle(.secondary)

                            TextField("Performance (e.g. Done or Skip)", text: $draft.performance)
                            TextField("RPE", text: $draft.rpe)
                            TextField("Notes", text: $draft.noteEntry)

                            if !draft.existingLog.isEmpty {
                                Text("Current: \(draft.existingLog)")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
            }

            Text("Write format: performance | RPE x | Notes: ... (Column H)")
                .foregroundStyle(.secondary)

            if !coordinator.loggerStatus.isEmpty {
                Text(coordinator.loggerStatus)
                    .foregroundColor(coordinator.loggerStatus.lowercased().contains("failed") ? .red : .secondary)
            }
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

            VStack(alignment: .leading, spacing: 6) {
                Text(coordinator.progressSummary.completionRateText)
                Text(coordinator.progressSummary.weeklyVolumeText)
                Text(coordinator.progressSummary.recentLoggedText)
            }

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

            if coordinator.weeklyReviewSummaries.isEmpty {
                Text("No weekly summaries in local DB yet.")
                    .foregroundStyle(.secondary)
            } else {
                List(coordinator.weeklyReviewSummaries) { week in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(week.sheetName).font(.headline)
                        Text("Sessions: \(week.sessions)")
                        Text("Logged: \(week.loggedCount)/\(week.totalCount)")
                        Text("Completion: \(week.completionRateText)")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }

            Button("Refresh Weekly Review") {
                coordinator.refreshAnalytics()
            }
            .buttonStyle(.bordered)
            Spacer()
        }
    }
}

struct ExerciseHistoryPageView: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Exercise History")
                .font(.largeTitle.bold())

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

            Text("\(coordinator.historyPoints.count) history row(s)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if coordinator.historyPoints.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No Local History Found")
                        .font(.headline)
                    Text("Import DB cache from Google Sheets, or choose an exercise from the catalog below.")
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

            HStack {
                Button("Rebuild DB Cache") {
                    Task {
                        await coordinator.triggerRebuildDBCache()
                    }
                }
                .buttonStyle(.bordered)
                .disabled(coordinator.isRebuildingDBCache)

                Button("Refresh DB Metrics") {
                    coordinator.refreshAnalytics()
                }
                .buttonStyle(.bordered)

                Button("Re-auth") {
                    coordinator.triggerReauth()
                }
                .buttonStyle(.bordered)
            }

            if coordinator.isRebuildingDBCache {
                ProgressView("Importing weekly sheets into local DB...")
                    .controlSize(.small)
            }

            if !coordinator.dbRebuildSummary.isEmpty {
                GroupBox("Last Rebuild") {
                    Text(coordinator.dbRebuildSummary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .font(.callout)
                }
            }

            if !coordinator.generationStatus.isEmpty {
                Text(coordinator.generationStatus)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }
}
