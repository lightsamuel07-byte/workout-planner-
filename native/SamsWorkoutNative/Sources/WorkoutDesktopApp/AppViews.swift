import SwiftUI
import AppKit

struct NativeWorkoutRootView: View {
    @StateObject private var coordinator = AppCoordinator(gateway: LiveAppGateway())

    var body: some View {
        Group {
            if coordinator.isSetupComplete {
                NavigationSplitView(columnVisibility: $coordinator.sidebarVisibility) {
                    List(AppRoute.allCases, selection: $coordinator.route) { route in
                        Label(route.rawValue, systemImage: icon(for: route))
                            .tag(route)
                    }
                    .listStyle(.sidebar)
                    .frame(minWidth: 200)
                    .navigationTitle("Workouts")
                } detail: {
                    routeView(route: coordinator.route)
                        .padding(.leading, 12)
                }
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        Button(action: { coordinator.toggleSidebar() }) {
                            Image(systemName: "sidebar.leading")
                        }
                        .help("Toggle Sidebar (Cmd+0)")
                    }
                }
            } else {
                SetupFlowView(coordinator: coordinator)
                    .padding(20)
            }
        }
        .frame(minWidth: 1080, minHeight: 720)
        .background(KeyboardShortcutOverlay(coordinator: coordinator))
    }

    private func icon(for route: AppRoute) -> String {
        switch route {
        case .dashboard:
            return "house"
        case .generatePlan:
            return "wand.and.stars"
        case .viewPlan:
            return "list.bullet.rectangle"
        case .progress:
            return "chart.line.uptrend.xyaxis"
        case .weeklyReview:
            return "calendar"
        case .exerciseHistory:
            return "clock.arrow.circlepath"
        case .settings:
            return "gearshape"
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
        case .progress:
            ProgressPageView(coordinator: coordinator)
        case .weeklyReview:
            WeeklyReviewPageView(coordinator: coordinator)
        case .exerciseHistory:
            ExerciseHistoryPageView(coordinator: coordinator)
        case .settings:
            SettingsPageView(coordinator: coordinator)
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

/// All-caps section header with a thin rule — used in place of GroupBox titles
/// for top-level page sections.
struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(text.uppercased())
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .kerning(0.6)
            Divider()
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

struct KeyboardShortcutOverlay: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        Group {
            // Cmd+1-7 navigation
            Button("") { coordinator.quickNavigate(to: .dashboard) }
                .keyboardShortcut("1", modifiers: .command)
            Button("") { coordinator.quickNavigate(to: .generatePlan) }
                .keyboardShortcut("2", modifiers: .command)
            Button("") { coordinator.quickNavigate(to: .viewPlan) }
                .keyboardShortcut("3", modifiers: .command)
            Button("") { coordinator.quickNavigate(to: .progress) }
                .keyboardShortcut("4", modifiers: .command)
            Button("") { coordinator.quickNavigate(to: .weeklyReview) }
                .keyboardShortcut("5", modifiers: .command)
            Button("") { coordinator.quickNavigate(to: .exerciseHistory) }
                .keyboardShortcut("6", modifiers: .command)
            Button("") { coordinator.quickNavigate(to: .settings) }
                .keyboardShortcut("7", modifiers: .command)

            // Left/Right arrows for plan day navigation
            Button("") { coordinator.moveToAdjacentPlanDay(step: -1) }
                .keyboardShortcut(.leftArrow, modifiers: .command)
            Button("") { coordinator.moveToAdjacentPlanDay(step: 1) }
                .keyboardShortcut(.rightArrow, modifiers: .command)

            // Cmd+Shift+R = refresh analytics
            Button("") { coordinator.refreshAnalytics() }
                .keyboardShortcut("r", modifiers: [.command, .shift])

            // Cmd+0 = toggle sidebar
            Button("") { coordinator.toggleSidebar() }
                .keyboardShortcut("0", modifiers: .command)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .allowsHitTesting(false)
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
                        Text("If the token expires it will auto-refresh using the stored refresh token.")
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


struct DashboardPageView: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                // MARK: - Title row
                HStack(alignment: .firstTextBaseline) {
                    Text("Dashboard")
                        .font(.largeTitle.bold())
                    Spacer()
                    Text(coordinator.analyticsFreshnessText)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                StatusBannerView(banner: coordinator.statusBanner)

                // MARK: - Training Week Grid
                VStack(alignment: .leading, spacing: 14) {
                    SectionLabel("This Week")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                        ForEach(coordinator.dashboardDays) { day in
                            DashboardDayCard(day: day)
                                .onTapGesture {
                                    coordinator.selectedPlanDay = day.title.capitalized
                                    coordinator.quickNavigate(to: .viewPlan)
                                }
                        }
                    }
                }

                // MARK: - 1RM Strip
                if coordinator.oneRepMaxesAreFilled {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionLabel("1RM")
                        HStack(spacing: 32) {
                            ForEach(coordinator.oneRepMaxFields) { field in
                                if let value = field.parsedValue {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(field.liftName)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text(String(format: "%.0f kg", value))
                                            .font(.system(.title3, design: .rounded, weight: .heavy))
                                    }
                                }
                            }
                            Spacer()
                            Button("Edit") { coordinator.quickNavigate(to: .settings) }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
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
                    .padding(10)
                    .background(.orange.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                // MARK: - Recent Activity
                if !coordinator.recentSessions.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionLabel("Recent Sessions")
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(coordinator.recentSessions.prefix(5)) { session in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(session.dayLabel)
                                            .font(.callout.weight(.semibold))
                                        Text(session.sessionDateISO)
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                    Spacer()
                                    let pct = session.totalRows > 0 ? Double(session.loggedRows) / Double(session.totalRows) * 100 : 0
                                    Text("\(session.loggedRows)/\(session.totalRows)")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                    completionBadge(pct)
                                }
                            }
                        }
                    }
                }

                // MARK: - Quick Actions & Refresh
                VStack(alignment: .leading, spacing: 14) {
                    SectionLabel("Quick Actions")
                    HStack(spacing: 10) {
                        Button { coordinator.quickNavigate(to: .generatePlan) } label: {
                            Label("Generate", systemImage: "wand.and.stars")
                        }
                        Button { coordinator.quickNavigate(to: .viewPlan) } label: {
                            Label("View Plan", systemImage: "list.bullet.rectangle")
                        }
                        Button { coordinator.quickNavigate(to: .exerciseHistory) } label: {
                            Label("History", systemImage: "clock.arrow.circlepath")
                        }
                        Button { coordinator.quickNavigate(to: .progress) } label: {
                            Label("Progress", systemImage: "chart.line.uptrend.xyaxis")
                        }
                        Spacer()
                        Button { Task { await coordinator.refreshPlanSnapshot(forceRemote: true) } } label: {
                            Label("Refresh Plan", systemImage: "arrow.clockwise")
                        }
                        Button { coordinator.refreshAnalytics() } label: {
                            Label("Refresh Analytics", systemImage: "chart.bar")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                // MARK: - Timestamp footer
                HStack(spacing: 20) {
                    Label("Plan: \(coordinator.formatTimestamp(coordinator.lastPlanRefreshAt))", systemImage: "doc.text")
                    Label("Analytics: \(coordinator.formatTimestamp(coordinator.lastAnalyticsRefreshAt))", systemImage: "chart.bar")
                }
                .font(.caption2)
                .foregroundStyle(.quaternary)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
        }
        .task {
            coordinator.loadOneRepMaxFields()
            await coordinator.refreshPlanSnapshot(forceRemote: true)
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
        HStack(spacing: 0) {
            Rectangle()
                .fill(accentColor)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center) {
                    Text(day.title)
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Spacer()
                    if isFortDay {
                        Text("FORT")
                            .font(.system(.caption2, design: .rounded).bold())
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.blue.opacity(0.18))
                            .clipShape(Capsule())
                    } else if day.blocks > 0 {
                        Text("SUPP")
                            .font(.system(.caption2, design: .rounded).bold())
                            .foregroundStyle(.purple)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.purple.opacity(0.18))
                            .clipShape(Capsule())
                    }
                }
                Text("\(day.blocks)")
                    .font(.system(.title2, design: .rounded, weight: .heavy))
                    .foregroundStyle(accentColor)
                Text(day.blocks == 1 ? "exercise" : "exercises")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(accentColor.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct GeneratePlanPageView: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text("Generate Plan")
                    .font(.largeTitle.bold())

                Text("Target sheet: \(coordinator.generationTargetSheetName)")
                    .foregroundStyle(.secondary)

                StatusBannerView(banner: coordinator.statusBanner)

                Button("Clear") { coordinator.clearGenerationInput() }
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

                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel("Monday — FORT Input")
                        TextEditor(text: $coordinator.generationInput.monday)
                            .frame(height: 130)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        Text("Characters: \(coordinator.mondayCharacterCount) · Lines: \(coordinator.generationDayLineCounts["Monday"] ?? 0)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel("Wednesday — FORT Input")
                        TextEditor(text: $coordinator.generationInput.wednesday)
                            .frame(height: 130)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        Text("Characters: \(coordinator.wednesdayCharacterCount) · Lines: \(coordinator.generationDayLineCounts["Wednesday"] ?? 0)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel("Friday — FORT Input")
                        TextEditor(text: $coordinator.generationInput.friday)
                            .frame(height: 130)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        Text("Characters: \(coordinator.fridayCharacterCount) · Lines: \(coordinator.generationDayLineCounts["Friday"] ?? 0)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                Toggle(isOn: $coordinator.generationInput.isNewCycle) {
                    HStack(spacing: 6) {
                        Text("New Fort Cycle")
                            .font(.callout.weight(.medium))
                        Text("— signals Claude to rotate supplemental exercises")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .help("Enable for the first week of a new 4-week Fort cycle. Tells Claude it may choose fresh exercises for Tue/Thu/Sat rather than continuing prior-cycle selections.")

                Button(coordinator.isGenerating ? "Generating..." : "Generate") {
                    Task { await coordinator.runGeneration() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!coordinator.canGenerateNow)

                if coordinator.isGenerating || coordinator.generationStage != nil {
                    GroupBox("Live Generation") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Stage")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text((coordinator.generationStage ?? .preparing).rawValue)
                                    .font(.callout.weight(.semibold))
                                Spacer()
                                if coordinator.isGenerating {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                            }

                            HStack(spacing: 14) {
                                Label("\(coordinator.generationStreamedCharacters)", systemImage: "text.badge.plus")
                                    .font(.caption)
                                if let inputTokens = coordinator.generationInputTokenCount {
                                    Label("in \(inputTokens)", systemImage: "arrow.down.circle")
                                        .font(.caption)
                                }
                                if let outputTokens = coordinator.generationOutputTokenCount {
                                    Label("out \(outputTokens)", systemImage: "arrow.up.circle")
                                        .font(.caption)
                                }
                            }
                            .foregroundStyle(.secondary)

                            if !coordinator.generationPreviewTail.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Stream preview")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    ScrollView {
                                        Text(coordinator.generationPreviewTail)
                                            .font(.system(.caption, design: .monospaced))
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .textSelection(.enabled)
                                    }
                                    .frame(height: 90)
                                    .padding(8)
                                    .background(.thinMaterial)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                            }

                            if !coordinator.generationProgressLog.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Progress log")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    ForEach(Array(coordinator.generationProgressLog.suffix(4).enumerated()), id: \.offset) { _, line in
                                        Text("• \(line)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if !coordinator.generationDisabledReason.isEmpty {
                    Text(coordinator.generationDisabledReason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("Tip: keep day headers and section cues from Fort to improve deterministic parsing and anchor fidelity.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
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

struct DayPillBar: View {
    let days: [PlanDayDetail]
    @Binding var selectedDay: String
    let shortName: (String) -> String
    let subtitle: (String) -> String

    private func pillColor(for dayLabel: String) -> Color {
        let lower = dayLabel.lowercased()
        let isFort = lower.contains("monday") || lower.contains("wednesday") || lower.contains("friday")
        return isFort ? .blue : .purple
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(days) { day in
                    let isSelected = day.dayLabel == selectedDay
                    let color = pillColor(for: day.dayLabel)
                    Button {
                        selectedDay = day.dayLabel
                    } label: {
                        VStack(spacing: 3) {
                            Text(shortName(day.dayLabel))
                                .font(.system(.callout, design: .rounded, weight: isSelected ? .semibold : .regular))
                            let sub = subtitle(day.dayLabel)
                            if !sub.isEmpty {
                                Text(sub)
                                    .font(.caption2)
                                    .foregroundStyle(isSelected ? .white.opacity(0.85) : .secondary)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(isSelected ? color : color.opacity(0.08))
                        .foregroundStyle(isSelected ? .white : .primary)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(isSelected ? Color.clear : color.opacity(0.35), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
    }
}

struct ExerciseCardView: View {
    let exercise: PlanExerciseRow
    let showNotes: Bool
    let showLogs: Bool

    private var blockColor: Color {
        let upper = exercise.block.uppercased()
        if upper.contains("IGNITION") || upper.contains("PREP") { return .orange }
        if upper.contains("CLUSTER") || upper.contains("BREAKPOINT") || upper.contains("WORKING") { return .red }
        if upper.contains("AUXILIARY") { return .blue }
        if upper.contains("THAW") { return .green }
        return .secondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Text(exercise.block.uppercased())
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
                    .foregroundStyle(blockColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(blockColor.opacity(0.13))
                    .clipShape(Capsule())

                Text(exercise.exercise)
                    .font(.title3.bold())

                Spacer()

                if !exercise.log.isEmpty {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.callout)
                }
            }

            HStack(spacing: 20) {
                Label(exercise.sets, systemImage: "square.stack.3d.up")
                Label(exercise.reps, systemImage: "repeat")
                Label("\(exercise.load) kg", systemImage: "scalemass")
                if !exercise.rest.isEmpty {
                    Label(exercise.rest, systemImage: "clock")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.callout)

            if showNotes, !exercise.notes.isEmpty {
                Text(exercise.notes)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            if showLogs, !exercise.log.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "pencil.line")
                        .font(.caption2)
                    Text(exercise.log)
                        .font(.caption)
                }
                .foregroundStyle(.green)
            }
        }
        .padding(16)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct ViewPlanPageView: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        Group {
            if coordinator.planSnapshot.days.isEmpty {
                ContentUnavailableView {
                    Label("No Plan Available", systemImage: "list.bullet.rectangle")
                } description: {
                    Text(coordinator.viewPlanError.isEmpty
                         ? "Generate or load a plan to see exercises here."
                         : coordinator.viewPlanError)
                } actions: {
                    Button("Reload") {
                        Task { await coordinator.refreshPlanSnapshot(forceRemote: true) }
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        StatusBannerView(banner: coordinator.statusBanner)

                        DayPillBar(
                            days: coordinator.orderedPlanDays,
                            selectedDay: $coordinator.selectedPlanDay,
                            shortName: { coordinator.shortDayName(for: $0) },
                            subtitle: { coordinator.daySubtitle(for: $0) }
                        )
                        .onChange(of: coordinator.selectedPlanDay) {
                            if !coordinator.planBlockCatalog.contains(coordinator.planBlockFilter) {
                                coordinator.planBlockFilter = "All Blocks"
                            }
                        }

                        // Search and filter bar
                        HStack(spacing: 8) {
                            TextField("Search exercises, blocks, notes", text: $coordinator.planSearchQuery)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 300)

                            Text(coordinator.selectedPlanDayPositionText)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Spacer()

                            Text("\(coordinator.planVisibleExerciseCount) exercises")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text(String(format: "%.0f kg", coordinator.planDayStats.estimatedVolumeKG))
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                        }

                        // Exercise cards
                        if coordinator.filteredPlanExercises.isEmpty {
                            ContentUnavailableView {
                                Label("No Matches", systemImage: "magnifyingglass")
                            } description: {
                                Text("No exercises match the current filters.")
                            } actions: {
                                Button("Reset Filters") {
                                    coordinator.resetPlanFilters()
                                }
                                .buttonStyle(.bordered)
                            }
                        } else {
                            LazyVStack(spacing: 12) {
                                ForEach(coordinator.filteredPlanExercises) { exercise in
                                    ExerciseCardView(
                                        exercise: exercise,
                                        showNotes: coordinator.showPlanNotes,
                                        showLogs: coordinator.showPlanLogs
                                    )
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 20)
                }
            }
        }
        .navigationTitle("View Plan")
        .navigationSubtitle(coordinator.planSnapshot.title)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                HStack(spacing: 8) {
                    Button {
                        Task { await coordinator.refreshPlanSnapshot(forceRemote: true) }
                    } label: {
                        Label("Reload", systemImage: "arrow.clockwise")
                    }
                    .help("Reload plan from Google Sheets")

                    Button {
                        let text = coordinator.buildSelectedPlanDayExportText()
                        if !text.isEmpty {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(text, forType: .string)
                        }
                    } label: {
                        Label("Copy Day", systemImage: "doc.on.doc")
                    }
                    .help("Copy selected day to clipboard")
                }
            }

            ToolbarItem(placement: .automatic) {
                Menu {
                    Toggle("Show Notes", isOn: $coordinator.showPlanNotes)
                    Toggle("Show Logs", isOn: $coordinator.showPlanLogs)
                    Toggle("Logged Only", isOn: $coordinator.showPlanLoggedOnly)
                    Divider()
                    Picker("Block", selection: $coordinator.planBlockFilter) {
                        ForEach(coordinator.planBlockCatalog, id: \.self) { block in
                            Text(block).tag(block)
                        }
                    }
                    Divider()
                    Button("Reset Filters") {
                        coordinator.resetPlanFilters()
                    }
                } label: {
                    Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
                }
                .help("Filter exercises")
            }
        }
    }
}

struct ProgressPageView: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                Text("Progress")
                    .font(.largeTitle.bold())

                Text(coordinator.progressSummary.sourceText)
                    .foregroundStyle(.secondary)

                StatusBannerView(banner: coordinator.statusBanner)

                // MARK: - Body Composition (InBody)
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .center) {
                        SectionLabel("Body Composition")
                        Spacer()
                        Button {
                            coordinator.inBodyScanStatus = ""
                            coordinator.showAddScanSheet = true
                        } label: {
                            Label("Add Scan", systemImage: "plus.circle")
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                    }

                    if coordinator.inBodyScans.isEmpty {
                        Text("No InBody scans yet. Tap Add Scan to log data from your InBody printout.")
                            .foregroundStyle(.secondary)
                    } else {
                        // Delta summary cards (latest vs first)
                        if coordinator.inBodyScans.count >= 2,
                           let firstScan = coordinator.inBodyScans.first,
                           let latestScan = coordinator.inBodyScans.last {
                            HStack(spacing: 10) {
                                inBodyDeltaCard(
                                    title: "Weight", unit: "kg",
                                    value: latestScan.weightKG, previous: firstScan.weightKG,
                                    lowerIsBetter: false
                                )
                                inBodyDeltaCard(
                                    title: "Muscle", unit: "kg",
                                    value: latestScan.smmKG, previous: firstScan.smmKG,
                                    lowerIsBetter: false
                                )
                                inBodyDeltaCard(
                                    title: "Fat", unit: "kg",
                                    value: latestScan.bfmKG, previous: firstScan.bfmKG,
                                    lowerIsBetter: true
                                )
                                inBodyDeltaCard(
                                    title: "Body Fat %", unit: "%",
                                    value: latestScan.pbf, previous: firstScan.pbf,
                                    lowerIsBetter: true
                                )
                                inBodyDeltaCard(
                                    title: "Score", unit: "",
                                    value: latestScan.inbodyScore.map(Double.init),
                                    previous: firstScan.inbodyScore.map(Double.init),
                                    lowerIsBetter: false
                                )
                            }
                        }

                        // Scan history table
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: 0) {
                                Text("DATE").font(.caption2.bold()).foregroundStyle(.secondary).kerning(0.4).frame(width: 96, alignment: .leading)
                                Text("WEIGHT").font(.caption2.bold()).foregroundStyle(.secondary).kerning(0.4).frame(width: 62, alignment: .trailing)
                                Text("SMM").font(.caption2.bold()).foregroundStyle(.blue).kerning(0.4).frame(width: 56, alignment: .trailing)
                                Text("FAT").font(.caption2.bold()).foregroundStyle(.orange).kerning(0.4).frame(width: 56, alignment: .trailing)
                                Text("BF%").font(.caption2.bold()).foregroundStyle(.secondary).kerning(0.4).frame(width: 50, alignment: .trailing)
                                Text("VFA").font(.caption2.bold()).foregroundStyle(.secondary).kerning(0.4).frame(width: 50, alignment: .trailing)
                                Text("SCORE").font(.caption2.bold()).foregroundStyle(.secondary).kerning(0.4).frame(width: 50, alignment: .trailing)
                                Spacer()
                            }
                            .padding(.bottom, 6)
                            Divider()
                            ForEach(coordinator.inBodyScans.reversed()) { scan in
                                HStack(spacing: 0) {
                                    Text(formatScanDate(scan.scanDate))
                                        .font(.caption)
                                        .frame(width: 96, alignment: .leading)
                                    Text(scan.weightKG.map { String(format: "%.1f", $0) } ?? "—")
                                        .font(.caption)
                                        .frame(width: 62, alignment: .trailing)
                                    Text(scan.smmKG.map { String(format: "%.1f", $0) } ?? "—")
                                        .font(.caption).foregroundStyle(.blue)
                                        .frame(width: 56, alignment: .trailing)
                                    Text(scan.bfmKG.map { String(format: "%.1f", $0) } ?? "—")
                                        .font(.caption).foregroundStyle(.orange)
                                        .frame(width: 56, alignment: .trailing)
                                    Text(scan.pbf.map { String(format: "%.1f%%", $0) } ?? "—")
                                        .font(.caption).foregroundStyle(.secondary)
                                        .frame(width: 50, alignment: .trailing)
                                    Text(scan.vfaCM2.map { String(format: "%.0f", $0) } ?? "—")
                                        .font(.caption).foregroundStyle(.secondary)
                                        .frame(width: 50, alignment: .trailing)
                                    Text(scan.inbodyScore.map { String($0) } ?? "—")
                                        .font(.caption.bold())
                                        .frame(width: 50, alignment: .trailing)
                                    Spacer()
                                    Button {
                                        coordinator.deleteInBodyScan(scanDate: scan.scanDate)
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.borderless)
                                    .help("Delete this scan")
                                }
                                .padding(.vertical, 5)
                                Divider()
                            }
                        }
                    }
                }
                .sheet(isPresented: $coordinator.showAddScanSheet) {
                    AddInBodyScanSheet(coordinator: coordinator)
                }

                // MARK: - Summary Cards
                HStack(spacing: 12) {
                    MetricCardView(title: "Completion", value: coordinator.progressSummary.completionRateText)
                    MetricCardView(title: "Weekly Volume", value: coordinator.progressSummary.weeklyVolumeText)
                    MetricCardView(title: "Recent Logs (14d)", value: coordinator.progressSummary.recentLoggedText)
                    MetricCardView(title: "Volume Trend", value: coordinator.weeklyVolumeChangeText)
                    MetricCardView(title: "Avg RPE", value: coordinator.averageRPEText)
                }

                // MARK: - Volume Trend Chart
                VStack(alignment: .leading, spacing: 14) {
                    SectionLabel("Weekly Volume Trend")
                    if coordinator.weeklyVolumePoints.isEmpty {
                        Text("No weekly volume data yet. Rebuild DB cache in Settings.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            let reversed = Array(coordinator.weeklyVolumePoints.reversed())
                            let maxVol = coordinator.volumeChartMax
                            ForEach(reversed) { point in
                                HStack(spacing: 8) {
                                    Text(shortSheetLabel(point.sheetName))
                                        .font(.caption)
                                        .frame(width: 80, alignment: .trailing)
                                    GeometryReader { geo in
                                        let fraction = maxVol > 0 ? CGFloat(point.volume / maxVol) : 0
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(.blue.gradient)
                                            .frame(width: max(fraction * geo.size.width, 4))
                                    }
                                    .frame(height: 18)
                                    Text(String(format: "%.0f", point.volume))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 60, alignment: .leading)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } // end volume VStack

                // MARK: - RPE Trend Chart
                VStack(alignment: .leading, spacing: 14) {
                    SectionLabel("Weekly RPE Trend")
                    if coordinator.weeklyRPEPoints.isEmpty {
                        Text("No RPE data yet. Log workouts with RPE values to populate.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            let reversed = Array(coordinator.weeklyRPEPoints.reversed())
                            ForEach(reversed) { point in
                                HStack(spacing: 8) {
                                    Text(shortSheetLabel(point.sheetName))
                                        .font(.caption)
                                        .frame(width: 80, alignment: .trailing)
                                    GeometryReader { geo in
                                        let fraction = CGFloat(point.averageRPE / 10.0)
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(rpeColor(point.averageRPE).gradient)
                                            .frame(width: max(fraction * geo.size.width, 4))
                                    }
                                    .frame(height: 18)
                                    Text(String(format: "%.1f (%d)", point.averageRPE, point.rpeCount))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 80, alignment: .leading)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                // MARK: - Block Volume Breakdown
                VStack(alignment: .leading, spacing: 14) {
                    SectionLabel("Block Volume — Last 28 Days")
                    if coordinator.muscleGroupVolumes.isEmpty {
                        Text("No block volume data yet.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            let maxVol = coordinator.muscleGroupVolumeMax
                            ForEach(coordinator.muscleGroupVolumes) { group in
                                HStack(spacing: 8) {
                                    Text(group.muscleGroup)
                                        .font(.caption)
                                        .frame(width: 120, alignment: .trailing)
                                    GeometryReader { geo in
                                        let fraction = maxVol > 0 ? CGFloat(group.volume / maxVol) : 0
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(.purple.gradient)
                                            .frame(width: max(fraction * geo.size.width, 4))
                                    }
                                    .frame(height: 18)
                                    Text(String(format: "%.0f (%d ex)", group.volume, group.exerciseCount))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 100, alignment: .leading)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                // MARK: - Top Logged Exercises
                VStack(alignment: .leading, spacing: 14) {
                    SectionLabel("Top Logged Exercises")
                    if coordinator.topExercises.isEmpty {
                        Text("No top exercise data yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(coordinator.topExercises) { row in
                                HStack {
                                    Text(row.exerciseName)
                                        .font(.callout)
                                    Spacer()
                                    Text("\(row.loggedCount) logs / \(row.sessionCount) sessions")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                HStack {
                    Text("Metrics refreshed: \(coordinator.formatTimestamp(coordinator.lastAnalyticsRefreshAt))")
                        .font(.caption2)
                        .foregroundStyle(.quaternary)
                    Spacer()
                    Button("Refresh Metrics") {
                        coordinator.refreshAnalytics()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
        }
    }

    private func shortSheetLabel(_ sheetName: String) -> String {
        let cleaned = sheetName
            .replacingOccurrences(of: "Weekly Plan (", with: "")
            .replacingOccurrences(of: ")", with: "")
        return cleaned
    }

    private func rpeColor(_ rpe: Double) -> Color {
        if rpe >= 9.0 { return .red }
        if rpe >= 7.5 { return .orange }
        if rpe >= 6.0 { return .yellow }
        return .green
    }

    private func formatScanDate(_ iso: String) -> String {
        let parser = DateFormatter()
        parser.calendar = Calendar(identifier: .gregorian)
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: iso) else { return iso }
        let display = DateFormatter()
        display.calendar = Calendar(identifier: .gregorian)
        display.locale = Locale(identifier: "en_US_POSIX")
        display.dateFormat = "MMM d, yyyy"
        return display.string(from: date)
    }

    @ViewBuilder
    private func inBodyDeltaCard(
        title: String,
        unit: String,
        value: Double?,
        previous: Double?,
        lowerIsBetter: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
                .kerning(0.4)
            if let v = value {
                let fmt = unit == "%" || unit == "" ? "%.1f" : "%.1f"
                Text(String(format: fmt, v) + unit)
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            } else {
                Text("—").font(.title3).foregroundStyle(.tertiary)
            }
            if let v = value, let p = previous {
                let delta = v - p
                let isPositive = delta >= 0
                let isGood = lowerIsBetter ? !isPositive : isPositive
                let sign = isPositive ? "+" : ""
                Text("\(sign)\(String(format: "%.1f", delta))\(unit)")
                    .font(.caption2)
                    .foregroundStyle(isGood ? .green : .red)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct AddInBodyScanSheet: View {
    @ObservedObject var coordinator: AppCoordinator
    @Environment(\.dismiss) private var dismiss

    @State private var scanDate = Date()
    @State private var weightText = ""
    @State private var smmText = ""
    @State private var bfmText = ""
    @State private var pbfText = ""
    @State private var scoreText = ""
    @State private var vfaText = ""
    @State private var notes = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Add InBody Scan")
                .font(.title2.bold())

            HStack(spacing: 12) {
                Text("Scan Date")
                    .font(.callout)
                    .frame(width: 90, alignment: .leading)
                DatePicker("", selection: $scanDate, displayedComponents: .date)
                    .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 12) {
                SectionLabel("Measurements")
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    scanField("Weight (kg)", text: $weightText, placeholder: "e.g. 102.5")
                    scanField("InBody Score", text: $scoreText, placeholder: "e.g. 89")
                    scanField("Skeletal Muscle Mass (kg)", text: $smmText, placeholder: "SMM")
                    scanField("Body Fat Mass (kg)", text: $bfmText, placeholder: "BFM")
                    scanField("Body Fat % (PBF)", text: $pbfText, placeholder: "e.g. 22.8")
                    scanField("Visceral Fat Area (cm²)", text: $vfaText, placeholder: "VFA")
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Notes")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                TextField("Optional notes", text: $notes, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3)
            }

            if !coordinator.inBodyScanStatus.isEmpty {
                Text(coordinator.inBodyScanStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Save Scan") {
                    saveScan()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
            }
        }
        .padding(28)
        .frame(minWidth: 440, minHeight: 460)
    }

    private var canSave: Bool {
        !weightText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !smmText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func saveScan() {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let dateStr = formatter.string(from: scanDate)

        coordinator.saveInBodyScan(InBodyScan(
            scanDate: dateStr,
            weightKG: parseDouble(weightText),
            smmKG: parseDouble(smmText),
            bfmKG: parseDouble(bfmText),
            pbf: parseDouble(pbfText),
            inbodyScore: parseInt(scoreText),
            vfaCM2: parseDouble(vfaText),
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
        ))
    }

    private func parseDouble(_ text: String) -> Double? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        return t.isEmpty ? nil : Double(t)
    }

    private func parseInt(_ text: String) -> Int? {
        Int(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    @ViewBuilder
    private func scanField(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }
}

struct WeeklyReviewPageView: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text("Weekly Review")
                    .font(.largeTitle.bold())

                StatusBannerView(banner: coordinator.statusBanner)

                HStack(spacing: 12) {
                    TextField("Filter by sheet name", text: $coordinator.weeklyReviewQuery)
                        .textFieldStyle(.roundedBorder)
                    Picker("Sort", selection: $coordinator.weeklyReviewSort) {
                        ForEach(WeeklyReviewSortMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    Button("Refresh") { coordinator.refreshAnalytics() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }

                HStack(spacing: 12) {
                    MetricCardView(title: "Avg Completion", value: String(format: "%.1f%%", coordinator.weeklyReviewAverageCompletion))
                    MetricCardView(title: "Best Week", value: coordinator.weeklyReviewBestWeek?.completionRateText ?? "n/a")
                    MetricCardView(title: "Worst Week", value: coordinator.weeklyReviewWorstWeek?.completionRateText ?? "n/a")
                }

                HStack(spacing: 16) {
                    Text("Best: \(coordinator.weeklyReviewBestWeek?.sheetName ?? "n/a")")
                    Text("Worst: \(coordinator.weeklyReviewWorstWeek?.sheetName ?? "n/a")")
                }
                .font(.caption)
                .foregroundStyle(.tertiary)

                if coordinator.filteredWeeklyReviewSummaries.isEmpty {
                    Text("No weekly summaries in local DB yet.")
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        SectionLabel("Weeks — \(coordinator.filteredWeeklyReviewSummaries.count) total")
                            .padding(.bottom, 12)
                        ForEach(coordinator.filteredWeeklyReviewSummaries) { week in
                            VStack(alignment: .leading, spacing: 0) {
                                HStack(alignment: .center) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(week.sheetName)
                                            .font(.callout.weight(.semibold))
                                        Text("Sessions: \(week.sessions) · Logged: \(week.loggedCount)/\(week.totalCount)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(week.completionRateText)
                                        .font(.system(.caption, design: .monospaced).bold())
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 4)
                                        .background(completionBadgeColor(week))
                                        .clipShape(Capsule())
                                }
                                .padding(.vertical, 12)
                                Divider()
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
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
        VStack(alignment: .leading, spacing: 24) {
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
                    Text("No exercise catalog yet. Rebuild DB cache in Settings.")
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
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
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
            VStack(alignment: .leading, spacing: 28) {
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

                GroupBox("Database") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("The local DB cache stores your exercise history synced from Google Sheets. Rebuild it to pick up recent log entries.")
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            Button {
                                Task { await coordinator.triggerRebuildDBCache() }
                            } label: {
                                if coordinator.isRebuildingDBCache {
                                    Label("Rebuilding…", systemImage: "arrow.triangle.2.circlepath")
                                } else {
                                    Label("Rebuild DB Cache", systemImage: "arrow.triangle.2.circlepath")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(coordinator.isRebuildingDBCache)

                            if let rebuildAt = coordinator.lastDBRebuildAt {
                                Text("Last rebuilt: \(coordinator.formatTimestamp(rebuildAt))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if !coordinator.dbRebuildSummary.isEmpty {
                            Text(coordinator.dbRebuildSummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
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
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
        }
        .onAppear {
            coordinator.loadOneRepMaxFields()
        }
    }
}
