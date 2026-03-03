import Foundation
import WorkoutIntegrations
import WorkoutPersistence

private enum BidirectionalLogResolution: String {
    case unchanged = "unchanged"
    case pullFromSheet = "pull_from_sheet"
    case pushToSheets = "push_to_sheets"
    case conflictResolvedToSheet = "conflict_resolved_to_sheet"
    case conflictResolvedToDB = "conflict_resolved_to_db"
}

private struct BidirectionalDecision {
    let resolvedLog: String
    let resolution: BidirectionalLogResolution
    let countsAsConflict: Bool
}

private struct BidirectionalSyncCounters {
    var daySessionsProcessed = 0
    var exerciseRowsProcessed = 0
    var pulledToDB = 0
    var pushedToSheets = 0
    var conflicts = 0
    var unchanged = 0

    func summary(sheetName: String) -> String {
        "Bidirectional sync (\(sheetName)): \(exerciseRowsProcessed) rows across \(daySessionsProcessed) day sessions | pulled \(pulledToDB) | pushed \(pushedToSheets) | conflicts \(conflicts) | unchanged \(unchanged)."
    }
}

extension LiveAppGateway {
    func reconcileBidirectionalLogs(
        sheetName: String,
        values: [[String]],
        sheetsClient: GoogleSheetsClient
    ) async throws -> [[String]] {
        var mutableValues = values.map { GoogleSheetsClient.enforceEightColumnSchema($0) }
        let workouts = GoogleSheetsClient.parseDayWorkouts(values: mutableValues)

        guard !workouts.isEmpty else {
            bidirectionalSyncSummary.set("Bidirectional sync skipped: no parseable day workouts in \(sheetName).")
            return mutableValues
        }

        let database = try openDatabase()
        let syncService = try makeSyncService()
        var counters = BidirectionalSyncCounters()

        for workout in workouts {
            counters.daySessionsProcessed += 1

            let dbRows = try database.fetchSessionLogRows(sheetName: sheetName, dayLabel: workout.dayLabel)
            let syncStateRows = try database.fetchLogSyncStateRows(sheetName: sheetName, dayLabel: workout.dayLabel)
            let dbBySourceRow = Dictionary(uniqueKeysWithValues: dbRows.map { ($0.sourceRow, $0) })
            let stateBySourceRow = Dictionary(uniqueKeysWithValues: syncStateRows.map { ($0.sourceRow, $0) })

            var daySheetUpdates: [ValueRangeUpdate] = []
            var dayEntries: [WorkoutSyncEntry] = []
            var daySyncStates: [PersistedLogSyncState] = []

            for exercise in workout.exercises {
                counters.exerciseRowsProcessed += 1

                let sheetLog = normalizeLogForSync(exercise.log)
                let dbLog = normalizeLogForSync(dbBySourceRow[exercise.sourceRow]?.logText ?? "")
                let syncState = stateBySourceRow[exercise.sourceRow]
                let decision = resolveBidirectionalLogDecision(
                    sheetLog: sheetLog,
                    dbLog: dbLog,
                    syncState: syncState
                )

                if decision.countsAsConflict {
                    counters.conflicts += 1
                }

                switch decision.resolution {
                case .unchanged:
                    counters.unchanged += 1
                case .pullFromSheet, .conflictResolvedToSheet:
                    counters.pulledToDB += 1
                case .pushToSheets, .conflictResolvedToDB:
                    counters.pushedToSheets += 1
                }

                if decision.resolution == .pushToSheets || decision.resolution == .conflictResolvedToDB {
                    if decision.resolvedLog != sheetLog {
                        daySheetUpdates.append(
                            ValueRangeUpdate(
                                range: "'\(sheetName)'!H\(exercise.sourceRow)",
                                values: [[decision.resolvedLog]]
                            )
                        )
                    }
                }

                applyResolvedLogToValues(&mutableValues, sourceRow: exercise.sourceRow, resolvedLog: decision.resolvedLog)

                let parsed = PlanTextParser.parseExistingLog(decision.resolvedLog)
                dayEntries.append(
                    WorkoutSyncEntry(
                        sourceRow: exercise.sourceRow,
                        exerciseName: exercise.exercise,
                        block: exercise.block,
                        prescribedSets: exercise.sets,
                        prescribedReps: exercise.reps,
                        prescribedLoad: exercise.load,
                        prescribedRest: exercise.rest,
                        prescribedNotes: exercise.notes,
                        logText: decision.resolvedLog,
                        explicitRPE: parsed.rpe,
                        parsedNotes: parsed.notes
                    )
                )

                daySyncStates.append(
                    PersistedLogSyncState(
                        sheetName: sheetName,
                        dayLabel: workout.dayLabel,
                        sourceRow: exercise.sourceRow,
                        lastSyncedSheetLog: decision.resolvedLog,
                        lastSyncedDBLog: decision.resolvedLog,
                        lastResolution: decision.resolution.rawValue
                    )
                )
            }

            if !daySheetUpdates.isEmpty {
                try await sheetsClient.batchUpdateLogs(daySheetUpdates)
            }

            if !dayEntries.isEmpty {
                _ = try syncService.sync(
                    input: WorkoutSyncSessionInput(
                        sheetName: sheetName,
                        dayLabel: workout.dayLabel,
                        fallbackDayName: workout.dayName,
                        fallbackDateISO: isoDate(nowProvider()),
                        entries: dayEntries,
                        includeEmptyLogs: true
                    )
                )
            }

            for syncState in daySyncStates {
                try database.upsertLogSyncState(syncState)
            }
        }

        bidirectionalSyncSummary.set(counters.summary(sheetName: sheetName))
        return mutableValues
    }

    private func resolveBidirectionalLogDecision(
        sheetLog: String,
        dbLog: String,
        syncState: PersistedLogSyncState?
    ) -> BidirectionalDecision {
        guard let syncState else {
            if sheetLog == dbLog {
                return BidirectionalDecision(resolvedLog: sheetLog, resolution: .unchanged, countsAsConflict: false)
            }
            if dbLog.isEmpty {
                return BidirectionalDecision(resolvedLog: sheetLog, resolution: .pullFromSheet, countsAsConflict: false)
            }
            if sheetLog.isEmpty {
                return BidirectionalDecision(resolvedLog: dbLog, resolution: .pushToSheets, countsAsConflict: false)
            }
            return BidirectionalDecision(resolvedLog: sheetLog, resolution: .conflictResolvedToSheet, countsAsConflict: true)
        }

        let lastSheetLog = normalizeLogForSync(syncState.lastSyncedSheetLog)
        let lastDBLog = normalizeLogForSync(syncState.lastSyncedDBLog)
        let changedSheet = sheetLog != lastSheetLog
        let changedDB = dbLog != lastDBLog

        if !changedSheet && !changedDB {
            if sheetLog == dbLog {
                return BidirectionalDecision(resolvedLog: sheetLog, resolution: .unchanged, countsAsConflict: false)
            }
            let resolved = Self.preferredConflictLog(sheetLog: sheetLog, dbLog: dbLog)
            let resolution: BidirectionalLogResolution = resolved == sheetLog ? .conflictResolvedToSheet : .conflictResolvedToDB
            return BidirectionalDecision(resolvedLog: resolved, resolution: resolution, countsAsConflict: true)
        }

        if changedSheet && !changedDB {
            return BidirectionalDecision(resolvedLog: sheetLog, resolution: .pullFromSheet, countsAsConflict: false)
        }

        if !changedSheet && changedDB {
            return BidirectionalDecision(resolvedLog: dbLog, resolution: .pushToSheets, countsAsConflict: false)
        }

        if sheetLog == dbLog {
            return BidirectionalDecision(resolvedLog: sheetLog, resolution: .unchanged, countsAsConflict: false)
        }

        let resolved = Self.preferredConflictLog(sheetLog: sheetLog, dbLog: dbLog)
        let resolution: BidirectionalLogResolution = resolved == sheetLog ? .conflictResolvedToSheet : .conflictResolvedToDB
        return BidirectionalDecision(resolvedLog: resolved, resolution: resolution, countsAsConflict: true)
    }

    private static func preferredConflictLog(sheetLog: String, dbLog: String) -> String {
        if sheetLog.isEmpty && !dbLog.isEmpty {
            return dbLog
        }
        if dbLog.isEmpty && !sheetLog.isEmpty {
            return sheetLog
        }
        // Tie-breaker remains deterministic: Google Sheets wins when both non-empty and different.
        return sheetLog
    }

    private func normalizeLogForSync(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func applyResolvedLogToValues(
        _ values: inout [[String]],
        sourceRow: Int,
        resolvedLog: String
    ) {
        let rowIndex = sourceRow - 1
        guard rowIndex >= 0, rowIndex < values.count else {
            return
        }

        var row = GoogleSheetsClient.enforceEightColumnSchema(values[rowIndex])
        row[7] = resolvedLog
        values[rowIndex] = row
    }
}

extension LiveAppGateway {
    static func testResolveBidirectionalLogDecision(
        sheetLog: String,
        dbLog: String,
        lastSyncedSheetLog: String?,
        lastSyncedDBLog: String?
    ) -> (resolvedLog: String, resolution: String, countsAsConflict: Bool) {
        let gateway = LiveAppGateway(planWriteMode: .localOnly)
        let state: PersistedLogSyncState?
        if let lastSyncedSheetLog, let lastSyncedDBLog {
            state = PersistedLogSyncState(
                sheetName: "Weekly Plan (2/23/2026)",
                dayLabel: "Tuesday 2/24",
                sourceRow: 3,
                lastSyncedSheetLog: lastSyncedSheetLog,
                lastSyncedDBLog: lastSyncedDBLog,
                lastResolution: "unchanged"
            )
        } else {
            state = nil
        }

        let decision = gateway.resolveBidirectionalLogDecision(
            sheetLog: gateway.normalizeLogForSync(sheetLog),
            dbLog: gateway.normalizeLogForSync(dbLog),
            syncState: state
        )

        return (decision.resolvedLog, decision.resolution.rawValue, decision.countsAsConflict)
    }
}
