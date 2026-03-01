import Foundation
import WorkoutIntegrations

extension LiveAppGateway {
    func loadPlanSnapshot(forceRemote: Bool = false) async throws -> PlanSnapshot {
        // When not forcing remote, try local cache first for fast startup.
        if !forceRemote, let local = try? loadLocalPlanSnapshot(), !local.days.isEmpty {
            return local
        }

        // Try Google Sheets (primary source of truth).
        if let config = try? requireSheetsSetup() {
            do {
                let sheetsClient = try await makeSheetsClient(config: config)
                let sheetNames = try await sheetsClient.fetchSheetNames()
                if let preferredSheet = preferredWeeklyPlanSheetName(sheetNames) {
                    let values = try await sheetsClient.readSheetAtoH(sheetName: preferredSheet)
                    let days = PlanTextParser.sheetDaysToPlanDays(values: values, source: .googleSheets)
                    if !days.isEmpty {
                        return PlanSnapshot(
                            title: PlanTextParser.normalizedPlanTitle(preferredSheet),
                            source: .googleSheets,
                            days: days,
                            summary: PlanTextParser.normalizedPlanSummary(
                                forceRemote
                                    ? "Refreshed from Google Sheets."
                                    : "Loaded from Google Sheets."
                            )
                        )
                    }
                }
            } catch {
                // If forceRemote was requested and Sheets fails, propagate the error.
                if forceRemote {
                    throw error
                }
                // Otherwise fall through to local cache below.
            }
        }

        // Fallback: local cache (only reached when not forcing remote, or Sheets had no data).
        if let local = try? loadLocalPlanSnapshot(), !local.days.isEmpty {
            return local
        }

        throw LiveGatewayError.noPlanData
    }

    func loadExerciseAliases() -> [String: String] {
        var candidates: [URL] = []
        candidates.append(URL(fileURLWithPath: fileManager.currentDirectoryPath).appendingPathComponent("exercise_swaps.yaml"))
        candidates.append(appSupportDirectoryURL().appendingPathComponent("exercise_swaps.yaml"))

        for candidate in candidates where fileManager.fileExists(atPath: candidate.path) {
            if let content = try? String(contentsOf: candidate, encoding: .utf8) {
                let parsed = parseExerciseAliasesFromYAML(content)
                if !parsed.isEmpty {
                    return parsed
                }
            }
        }

        return [:]
    }

    func parseExerciseAliasesFromYAML(_ content: String) -> [String: String] {
        var mapping: [String: String] = [:]
        var inSwaps = false

        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.replacingOccurrences(of: "\t", with: "    ")
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }

            if trimmed == "exercise_swaps:" {
                inSwaps = true
                continue
            }

            if inSwaps, !line.hasPrefix("  "), !line.hasPrefix("\t") {
                inSwaps = false
            }

            if !inSwaps {
                continue
            }

            guard let separator = trimmed.firstIndex(of: ":") else {
                continue
            }
            let key = trimmed[..<separator].trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            let value = trimmed[trimmed.index(after: separator)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if !key.isEmpty, !value.isEmpty {
                mapping[String(key)] = String(value)
            }
        }

        return mapping
    }

    func savePlanLocally(
        planText: String,
        sheetName: String,
        validationSummary: String,
        fidelitySummary: String
    ) throws -> URL {
        let outputDirectory = try outputDirectoryURL()
        let planURL = outputDirectory.appendingPathComponent(localPlanFileName(for: sheetName))

        if fileManager.fileExists(atPath: planURL.path) {
            let archiveDir = outputDirectory.appendingPathComponent("archive", isDirectory: true)
            try fileManager.createDirectory(at: archiveDir, withIntermediateDirectories: true)
            let baseName = planURL.deletingPathExtension().lastPathComponent + "_archived_" + archiveTimestamp(nowProvider())
            var archivedURL = archiveDir.appendingPathComponent(baseName + ".md")
            var suffix = 1
            while fileManager.fileExists(atPath: archivedURL.path) {
                archivedURL = archiveDir.appendingPathComponent(baseName + "_\(suffix).md")
                suffix += 1
            }
            try fileManager.moveItem(at: planURL, to: archivedURL)
        }

        try planText.data(using: .utf8)?.write(to: planURL, options: [.atomic])

        let summaryURL = outputDirectory.appendingPathComponent(
            planURL.deletingPathExtension().lastPathComponent + "_summary.md"
        )
        let summaryText = """
        Sheet: \(sheetName)
        Validation: \(validationSummary)
        Fort fidelity: \(fidelitySummary)
        Generated at: \(isoDateTime(nowProvider()))
        """
        try summaryText.data(using: .utf8)?.write(to: summaryURL, options: [.atomic])

        return planURL
    }

    func loadLocalPlanSnapshot() throws -> PlanSnapshot {
        let outputDirectory = try outputDirectoryURL()
        let files = try fileManager.contentsOfDirectory(
            at: outputDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        let planFiles = files.filter { url in
            let name = url.lastPathComponent.lowercased()
            return name.hasPrefix("workout_plan_") && name.hasSuffix(".md") && !name.contains("_summary")
        }

        let datedCandidates = planFiles.compactMap { url -> (URL, Date)? in
            guard let date = Self.parseLocalPlanDate(from: url.lastPathComponent) else {
                return nil
            }
            return (url, date)
        }

        if let preferredLocal = Self.preferredCandidate(
            datedCandidates,
            referenceDate: nowProvider(),
            nearWindowDays: 35,
            fallbackToMostRecent: false
        )?.0 {
            let text = try String(contentsOf: preferredLocal, encoding: .utf8)
            let days = PlanTextParser.markdownDaysToPlanDays(planText: text, source: .localCache)
            return PlanSnapshot(
                title: PlanTextParser.normalizedPlanTitle(preferredLocal.lastPathComponent),
                source: .localCache,
                days: days,
                summary: PlanTextParser.normalizedPlanSummary("Loaded from local markdown artifact.")
            )
        }

        let sorted = planFiles.sorted { lhs, rhs in
            let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lhsDate > rhsDate
        }
        guard datedCandidates.isEmpty, let latest = sorted.first else {
            throw LiveGatewayError.noPlanData
        }

        let text = try String(contentsOf: latest, encoding: .utf8)
        let days = PlanTextParser.markdownDaysToPlanDays(planText: text, source: .localCache)
        return PlanSnapshot(
            title: PlanTextParser.normalizedPlanTitle(latest.lastPathComponent),
            source: .localCache,
            days: days,
            summary: PlanTextParser.normalizedPlanSummary("Loaded from local markdown artifact.")
        )
    }

    func localPlanFileName(for sheetName: String) -> String {
        let slug = sheetName
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return "workout_plan_\(slug).md"
    }

    func preferredWeeklyPlanSheetName(_ sheetNames: [String]) -> String? {
        Self.preferredWeeklyPlanSheetName(sheetNames, referenceDate: nowProvider())
    }

    static func preferredWeeklyPlanSheetName(_ sheetNames: [String], referenceDate: Date) -> String? {
        let candidates = sheetNames.compactMap { name -> (String, Date)? in
            guard let date = GoogleSheetsClient.parseWeeklyPlanSheetDate(name) else {
                return nil
            }
            return (name, date)
        }

        return preferredCandidate(
            candidates,
            referenceDate: referenceDate,
            nearWindowDays: 35,
            fallbackToMostRecent: true
        )?.0
    }

    static func parseLocalPlanDate(from fileName: String) -> Date? {
        let pattern = #"^workout_plan_weekly_plan_(\d{1,2})_(\d{1,2})_(\d{4})\.md$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: fileName, range: NSRange(fileName.startIndex..<fileName.endIndex, in: fileName)),
              let monthRange = Range(match.range(at: 1), in: fileName),
              let dayRange = Range(match.range(at: 2), in: fileName),
              let yearRange = Range(match.range(at: 3), in: fileName),
              let month = Int(fileName[monthRange]),
              let day = Int(fileName[dayRange]),
              let year = Int(fileName[yearRange])
        else {
            return nil
        }

        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        return components.date
    }

    static func preferredCandidate<T>(
        _ candidates: [(T, Date)],
        referenceDate: Date,
        nearWindowDays: Int,
        fallbackToMostRecent: Bool
    ) -> (T, Date)? {
        guard !candidates.isEmpty else {
            return nil
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let referenceDay = calendar.startOfDay(for: referenceDate)
        let maxDistance = TimeInterval(nearWindowDays * 86_400)

        let scored = candidates.map { candidate -> (T, Date, TimeInterval, Bool) in
            let candidateDay = calendar.startOfDay(for: candidate.1)
            let distance = abs(candidateDay.timeIntervalSince(referenceDay))
            let isFutureOrToday = candidateDay >= referenceDay
            return (candidate.0, candidate.1, distance, isFutureOrToday)
        }

        let nearby = scored.filter { $0.2 <= maxDistance }
        if let preferred = nearby.sorted(by: { lhs, rhs in
            if lhs.2 != rhs.2 {
                return lhs.2 < rhs.2
            }
            if lhs.3 != rhs.3 {
                return lhs.3 && !rhs.3
            }
            return lhs.1 > rhs.1
        }).first {
            return (preferred.0, preferred.1)
        }

        guard fallbackToMostRecent else {
            return nil
        }

        return candidates.sorted(by: { $0.1 < $1.1 }).last
    }
}
