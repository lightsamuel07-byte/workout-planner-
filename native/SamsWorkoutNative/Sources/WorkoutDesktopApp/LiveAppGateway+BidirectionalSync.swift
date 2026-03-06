import Foundation
import WorkoutIntegrations
import WorkoutPersistence

private enum BidirectionalLogResolution: String {
    case unchanged = "unchanged"
    case pullFromSheet = "pull_from_sheet"
    case pushToSheets = "push_to_sheets"
    case conflictResolvedToSheet = "conflict_resolved_to_sheet"
    case conflictResolvedToDB = "conflict_resolved_to_db"
    case manualRepairToSheet = "manual_repair_to_sheet"
    case manualRepairToDB = "manual_repair_to_db"
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

    func summary(sheetName: String, conflictPolicy: BidirectionalSyncConflictPolicy) -> String {
        "Bidirectional sync (\(sheetName)): \(exerciseRowsProcessed) rows across \(daySessionsProcessed) day sessions | pulled \(pulledToDB) | pushed \(pushedToSheets) | conflicts \(conflicts) | unchanged \(unchanged) | policy \(conflictPolicy.rawValue)."
    }
}

private struct ManualConflictRepairDecision {
    let resolvedLog: String
    let resolution: BidirectionalLogResolution
    let didPushToSheets: Bool
    let didPullToDB: Bool
    let shouldWriteAudit: Bool
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
        let conflictPolicy = configStore.load().bidirectionalSyncConflictPolicy
        let syncRunID = UUID().uuidString
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
            var dayAuditEvents: [PersistedSyncAuditEvent] = []

            for exercise in workout.exercises {
                counters.exerciseRowsProcessed += 1

                let sheetLog = normalizeLogForSync(exercise.log)
                let dbLog = normalizeLogForSync(dbBySourceRow[exercise.sourceRow]?.logText ?? "")
                let syncState = stateBySourceRow[exercise.sourceRow]
                let decision = resolveBidirectionalLogDecision(
                    sheetLog: sheetLog,
                    dbLog: dbLog,
                    syncState: syncState,
                    conflictPolicy: conflictPolicy
                )

                if decision.countsAsConflict {
                    counters.conflicts += 1
                }

                switch decision.resolution {
                case .unchanged, .manualRepairToSheet, .manualRepairToDB:
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

                let didPushToSheets = decision.resolution == .pushToSheets || decision.resolution == .conflictResolvedToDB
                let didPullToDB = decision.resolution == .pullFromSheet || decision.resolution == .conflictResolvedToSheet
                dayAuditEvents.append(
                    PersistedSyncAuditEvent(
                        syncRunID: syncRunID,
                        sheetName: sheetName,
                        dayLabel: workout.dayLabel,
                        sourceRow: exercise.sourceRow,
                        exerciseName: exercise.exercise,
                        sheetLog: sheetLog,
                        dbLog: dbLog,
                        resolvedLog: decision.resolvedLog,
                        resolution: decision.resolution.rawValue,
                        conflictPolicy: conflictPolicy.rawValue,
                        didPushToSheets: didPushToSheets,
                        didPullToDB: didPullToDB,
                        countsAsConflict: decision.countsAsConflict
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

            for auditEvent in dayAuditEvents {
                try database.insertSyncAuditEvent(auditEvent)
            }
        }

        bidirectionalSyncSummary.set(counters.summary(sheetName: sheetName, conflictPolicy: conflictPolicy))
        return mutableValues
    }

    func repairSyncConflict(
        event: PersistedSyncAuditEvent,
        choice: SyncConflictRepairChoice
    ) async throws -> String {
        let config = try requireSheetsSetup()
        let sheetsClient = try await makeSheetsClient(config: config)
        let database = try openDatabase()
        let syncService = try makeSyncService()

        let values = try await sheetsClient.readSheetAtoH(sheetName: event.sheetName)
        let normalizedValues = values.map { GoogleSheetsClient.enforceEightColumnSchema($0) }
        let rowIndex = event.sourceRow - 1
        let currentSheetRow = (rowIndex >= 0 && rowIndex < normalizedValues.count) ? normalizedValues[rowIndex] : nil
        let currentSheetLog = normalizeLogForSync(currentSheetRow?[7] ?? event.sheetLog)
        let dbRow = try database
            .fetchSessionLogRows(sheetName: event.sheetName, dayLabel: event.dayLabel)
            .first { $0.sourceRow == event.sourceRow }
        let currentDBLog = normalizeLogForSync(dbRow?.logText ?? event.dbLog)

        let decision = manualConflictRepairDecision(
            currentSheetLog: currentSheetLog,
            currentDBLog: currentDBLog,
            choice: choice
        )

        if !decision.shouldWriteAudit {
            let summary = "Manual sync repair skipped for \(event.exerciseName) row \(event.sourceRow): both stores already match the chosen value."
            bidirectionalSyncSummary.set(summary)
            return summary
        }

        if decision.didPushToSheets {
            try await sheetsClient.batchUpdateLogs([
                ValueRangeUpdate(
                    range: "'\(event.sheetName)'!H\(event.sourceRow)",
                    values: [[decision.resolvedLog]]
                )
            ])
        }

        let entry = try makeManualRepairSyncEntry(
            event: event,
            sheetRow: currentSheetRow,
            dbRow: dbRow,
            resolvedLog: decision.resolvedLog
        )
        _ = try syncService.sync(
            input: WorkoutSyncSessionInput(
                sheetName: event.sheetName,
                dayLabel: event.dayLabel,
                fallbackDayName: GoogleSheetsClient.dayNameFromLabel(event.dayLabel) ?? event.dayLabel,
                fallbackDateISO: isoDate(nowProvider()),
                entries: [entry],
                includeEmptyLogs: true
            )
        )

        try database.upsertLogSyncState(
            PersistedLogSyncState(
                sheetName: event.sheetName,
                dayLabel: event.dayLabel,
                sourceRow: event.sourceRow,
                lastSyncedSheetLog: decision.resolvedLog,
                lastSyncedDBLog: decision.resolvedLog,
                lastResolution: decision.resolution.rawValue
            )
        )

        try database.insertSyncAuditEvent(
            PersistedSyncAuditEvent(
                syncRunID: UUID().uuidString,
                sheetName: event.sheetName,
                dayLabel: event.dayLabel,
                sourceRow: event.sourceRow,
                exerciseName: event.exerciseName,
                sheetLog: currentSheetLog,
                dbLog: currentDBLog,
                resolvedLog: decision.resolvedLog,
                resolution: decision.resolution.rawValue,
                conflictPolicy: configStore.load().bidirectionalSyncConflictPolicy.rawValue,
                didPushToSheets: decision.didPushToSheets,
                didPullToDB: decision.didPullToDB,
                countsAsConflict: true
            )
        )

        let selectedSide = choice == .applySheetsValue ? "Google Sheets" : "Local DB"
        let summary = "Applied \(selectedSide) value for \(event.exerciseName) row \(event.sourceRow) and refreshed sync checkpoints."
        bidirectionalSyncSummary.set(summary)
        return summary
    }

    private func resolveBidirectionalLogDecision(
        sheetLog: String,
        dbLog: String,
        syncState: PersistedLogSyncState?,
        conflictPolicy: BidirectionalSyncConflictPolicy
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
            let resolved = Self.preferredConflictLog(sheetLog: sheetLog, dbLog: dbLog, conflictPolicy: conflictPolicy)
            let resolution: BidirectionalLogResolution = resolved == sheetLog ? .conflictResolvedToSheet : .conflictResolvedToDB
            return BidirectionalDecision(resolvedLog: resolved, resolution: resolution, countsAsConflict: true)
        }

        let lastSheetLog = normalizeLogForSync(syncState.lastSyncedSheetLog)
        let lastDBLog = normalizeLogForSync(syncState.lastSyncedDBLog)
        let changedSheet = sheetLog != lastSheetLog
        let changedDB = dbLog != lastDBLog

        if !changedSheet && !changedDB {
            if sheetLog == dbLog {
                return BidirectionalDecision(resolvedLog: sheetLog, resolution: .unchanged, countsAsConflict: false)
            }
            let resolved = Self.preferredConflictLog(sheetLog: sheetLog, dbLog: dbLog, conflictPolicy: conflictPolicy)
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

        let resolved = Self.preferredConflictLog(sheetLog: sheetLog, dbLog: dbLog, conflictPolicy: conflictPolicy)
        let resolution: BidirectionalLogResolution = resolved == sheetLog ? .conflictResolvedToSheet : .conflictResolvedToDB
        return BidirectionalDecision(resolvedLog: resolved, resolution: resolution, countsAsConflict: true)
    }

    private static func preferredConflictLog(
        sheetLog: String,
        dbLog: String,
        conflictPolicy: BidirectionalSyncConflictPolicy
    ) -> String {
        if sheetLog.isEmpty && !dbLog.isEmpty {
            return dbLog
        }
        if dbLog.isEmpty && !sheetLog.isEmpty {
            return sheetLog
        }
        switch conflictPolicy {
        case .preferSheets:
            return sheetLog
        case .preferDatabase:
            return dbLog
        }
    }

    private func normalizeLogForSync(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func manualConflictRepairDecision(
        currentSheetLog: String,
        currentDBLog: String,
        choice: SyncConflictRepairChoice
    ) -> ManualConflictRepairDecision {
        let resolvedLog = choice == .applySheetsValue ? currentSheetLog : currentDBLog
        let didPushToSheets = currentSheetLog != resolvedLog
        let didPullToDB = currentDBLog != resolvedLog
        let resolution: BidirectionalLogResolution = choice == .applySheetsValue ? .manualRepairToSheet : .manualRepairToDB

        return ManualConflictRepairDecision(
            resolvedLog: resolvedLog,
            resolution: resolution,
            didPushToSheets: didPushToSheets,
            didPullToDB: didPullToDB,
            shouldWriteAudit: didPushToSheets || didPullToDB
        )
    }

    private func makeManualRepairSyncEntry(
        event: PersistedSyncAuditEvent,
        sheetRow: [String]?,
        dbRow: PersistedSessionLogRow?,
        resolvedLog: String
    ) throws -> WorkoutSyncEntry {
        let parsed = PlanTextParser.parseExistingLog(resolvedLog)
        if let dbRow {
            return WorkoutSyncEntry(
                sourceRow: event.sourceRow,
                exerciseName: dbRow.exerciseName,
                block: dbRow.block,
                prescribedSets: dbRow.prescribedSets,
                prescribedReps: dbRow.prescribedReps,
                prescribedLoad: dbRow.prescribedLoad,
                prescribedRest: dbRow.prescribedRest,
                prescribedNotes: dbRow.prescribedNotes,
                logText: resolvedLog,
                explicitRPE: parsed.rpe,
                parsedNotes: parsed.notes
            )
        }

        if let sheetRow {
            return WorkoutSyncEntry(
                sourceRow: event.sourceRow,
                exerciseName: sheetRow[1],
                block: sheetRow[0],
                prescribedSets: sheetRow[2],
                prescribedReps: sheetRow[3],
                prescribedLoad: sheetRow[4],
                prescribedRest: sheetRow[5],
                prescribedNotes: sheetRow[6],
                logText: resolvedLog,
                explicitRPE: parsed.rpe,
                parsedNotes: parsed.notes
            )
        }

        throw LiveGatewayError.manualSyncRepairTargetNotFound
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
        lastSyncedDBLog: String?,
        conflictPolicy: BidirectionalSyncConflictPolicy = .preferSheets
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
            syncState: state,
            conflictPolicy: conflictPolicy
        )

        return (decision.resolvedLog, decision.resolution.rawValue, decision.countsAsConflict)
    }

    static func testManualConflictRepairDecision(
        currentSheetLog: String,
        currentDBLog: String,
        choice: SyncConflictRepairChoice
    ) -> (resolvedLog: String, resolution: String, didPushToSheets: Bool, didPullToDB: Bool, shouldWriteAudit: Bool) {
        let gateway = LiveAppGateway(planWriteMode: .localOnly)
        let decision = gateway.manualConflictRepairDecision(
            currentSheetLog: gateway.normalizeLogForSync(currentSheetLog),
            currentDBLog: gateway.normalizeLogForSync(currentDBLog),
            choice: choice
        )
        return (
            decision.resolvedLog,
            decision.resolution.rawValue,
            decision.didPushToSheets,
            decision.didPullToDB,
            decision.shouldWriteAudit
        )
    }
}
