import Foundation
import WorkoutCore

enum PromptBuilder {
    static func buildGenerationPrompt(
        input: PlanGenerationInput,
        fortContext: String,
        dbContext: String,
        progressionDirectivesBlock: String,
        oneRepMaxes: [String: Double] = [:]
    ) -> String {
        let oneRMSection: String
        if oneRepMaxes.isEmpty {
            oneRMSection = "ATHLETE 1RM PROFILE:\nNo 1RM data provided. Use RPE feedback from recent logs to infer appropriate intensity."
        } else {
            let lines = oneRepMaxes.sorted(by: { $0.key < $1.key }).map { exercise, value in
                String(format: "- %@: %.1f kg", exercise, value)
            }
            oneRMSection = "ATHLETE 1RM PROFILE (use these for percentage-based load calculations):\n" + lines.joined(separator: "\n")
        }

        return """
        You are an expert strength and conditioning coach creating a personalized weekly workout plan.

        CRITICAL: NO RANGES - use single values only (e.g., "15 reps" not "12-15", "24 kg" not "22-26 kg")

        \(oneRMSection)

        \(fortContext)

        RECENT WORKOUT HISTORY (LOCAL DB CONTEXT):
        \(dbContext)

        \(progressionDirectivesBlock)

        LOAD CALCULATION RULE:
        - Training max override: if Fort coach notes define a "training max" or "working max" (e.g., "use 90% of your 1RM as training max"), apply that definition first, then calculate all set percentages from that training max — not from the raw 1RM.
        - Load rounding: barbell lifts → nearest 0.5 kg; DB loads → nearest even 2 kg step.

        FORT WORKOUT CONVERSION (CRITICAL):
        - The Fort workouts below (Mon/Wed/Fri) are raw inputs and MUST be converted into markdown exercise rows.
        - Treat "FORT COMPILER DIRECTIVES" section order and listed exercise anchors as hard constraints.
        - Keep day section order aligned with detected Fort sections and include each anchor exercise at least once.
        - Convert each exercise to:
          ### A1. [Exercise Name]
          - [Sets] x [Reps] @ [Load] kg
          - **Rest:** [period]
          - **Notes:** [coaching cues]
        - Never output section labels/instruction lines as exercises.

        Monday input:
        \(input.monday)

        Wednesday input:
        \(input.wednesday)

        Friday input:
        \(input.friday)

        CYCLE STATUS: \(input.isNewCycle ? "NEW CYCLE START" : "MID-CYCLE")
        \(input.isNewCycle ? """
        This is Week 1 of a new 4-week Fort cycle. The Fort exercises have changed.
        SUPPLEMENTAL DAYS (Tue/Thu/Sat): This is a CLEAN SLATE. Select a completely fresh set of upper-body exercises — do NOT carry over exercises from the prior cycle. Choose new movements that complement the new Fort structure and the athlete's aesthetic goals.
        Any PROGRESS / HOLD_LOCK / NEUTRAL directives in the context below reflect the PREVIOUS cycle. They are provided for load-reference only. They must NOT be used to lock in prior exercise choices or constrain which exercises you select. Prior-cycle progression signals do not override the clean-slate requirement.
        """ : """
        This is a mid-cycle week. Keep the same supplemental exercises as prior weeks unless a progression directive explicitly requires a swap.
        Apply PROGRESS / HOLD_LOCK / NEUTRAL signals from prior logs.
        """)

        SUPPLEMENTAL SELECTION GOAL:
        Supplemental days (Tue/Thu/Sat) exist for one purpose: maximum aesthetic impact on the upper body, without impairing Fort performance. This is the primary selection criterion — not variety for its own sake, not general fitness. Choose exercises that maximally develop the following, in priority order:
          1. Arms — biceps shape + triceps fullness (HIGH priority)
          2. Delts — medial delt cap for shoulder width, rear delt for 3D look (HIGH priority)
          3. Upper chest — clavicular pec "pop" via incline pressing and fly patterns (HIGH priority)
          4. Back detail — upper-back density, rear-delt tie-in, posture (HIGH priority)
        Favour isolation and cable/DB work that directly targets these groups. Avoid exercise drift into general conditioning or functional patterns that don't serve the aesthetic priority list. Stimulus-efficient hypertrophy only — no junk volume.

        INTERFERENCE PROTECTION (non-negotiable):
        - Tuesday: protect Wednesday bench — no heavy chest/triceps/front-delt loading, no barbell pressing.
        - Thursday: protect Friday deadlift — no loaded carries, no heavy rows, no heavy biceps (>6 hard sets), no grip-fatiguing work.
        - Saturday: protect Monday squat and overall recovery — no heavy lower back, no spinal fatigue, no junk volume.
        - THAW conditioning: THAW intensity must not compromise next-day Fort performance. Even low-load conditioning (walking intervals, bike) should not push into fatigue that blunts Tuesday's or Wednesday's training. This is a fatigue management constraint, not just a format rule.
        - Delt carry-over: If Monday Fort already included DB Lateral Raises, Tuesday must default to rear-delt / scapular hygiene work (e.g., Face Pull, Cable Y-Raise, Reverse Pec Deck, Rear Delt Fly) instead of lateral raise patterns. This protects Wednesday bench performance and avoids redundant medial-delt fatigue.

        CORE PRINCIPLES:
        - Supplemental days (Tue/Thu/Sat) are ALL strictly upper body. Program biceps, triceps, shoulders (lateral raises, rear delts, face pulls, Y-raises), upper chest (incline press), and upper back (rows, cable work). This applies equally to Tuesday, Thursday, and Saturday — there is no lower body supplemental day.
        - NEVER program lower body exercises on supplemental days. This ban includes: squats, deadlifts, Romanian deadlifts, hip hinges, kettlebell swings, hyperextensions, back extensions, leg press, lunges, leg curls, or any lower-body-dominant movement. Lower body work belongs exclusively to Fort days (Mon/Wed/Fri).
        - Supplemental days must be substantive: minimum 5 exercises on each of Tue, Thu, and Sat.
        - Every supplemental day (Tue, Thu, Sat) MUST include McGill Big-3 (curl-up, side bridge, bird-dog). Label it as one block entry "McGill Big-3" with coaching cues in the Notes field.
        - No exercise repeated across supplemental days within the same week. Tuesday, Thursday, and Saturday must each have a completely distinct, non-overlapping exercise selection. If you use Incline DB Press on Tuesday, do not use it on Thursday or Saturday.
        - Preserve explicit keep/stay-here progression constraints from prior logs.
        - Never increase both reps and load in the same week for the same exercise.
        - Notes must be clean coaching cues only: max 2 short sentences, execution-focused. Never include load calculations (e.g. "40% of 1RM = X kg"), percentage references, internal reasoning, or directive references.

        MANDATORY HARD RULES:
        - Equipment: No belt on pulls, standing calves only. No split squats on supplemental days (Tue/Thu/Sat). Fort-trainer-programmed split squats on Mon/Wed/Fri are permitted and must not be swapped.
        - Dumbbells: even-number loads only (no odd DB loads except main barbell lifts).
        - Biceps: rotate grips (supinated -> neutral -> pronated), no repeated adjacent supplemental-day grip.
        - Triceps: vary attachments across Tue/Thu/Sat. Fort Friday triceps: prefer straight-bar attachment with heavier loading (strength-emphasis day). No single-arm D-handle triceps on Saturday.
        - Carries: Tuesday only; use kettlebells exclusively — never dumbbells — to protect Friday deadlift grip.
        - Conditioning (THAW blocks): Sets = 1, Reps = total block duration (e.g. "12 min"), Load = 0. All interval structure, distances, pace targets, and effort cues go in Notes only. Example — correct: Reps = "12 min", Notes = "8 × 300m at tempo; 30 sec easy recovery between." Incorrect: Sets = 8, Reps = 300.
        - Canonical log format in sheets: performance | RPE x | Notes: ...

        OUTPUT REQUIREMENTS:
        - Use ## day headers and ### block.exercise headers.
        - Include six training days (Mon-Sat). Sunday is always complete rest — do not generate a Sunday block.
        - Keep A:H sheet compatibility (Block, Exercise, Sets, Reps, Load, Rest, Notes, Log).
        - American spelling.
        - Exercise names: Title Case only. Never use ALL CAPS for exercise names. Write "Pull Up" not "PULL UP", "Incline DB Press" not "INCLINE DB PRESS", "Barbell RDL" not "BARBELL RDL". Abbreviations (DB, KB, RDL, etc.) stay abbreviated but are not full caps of the entire name.
        - Notes: maximum 1-2 concise coaching cues per exercise (1 sentence each). Do not reproduce lengthy program descriptions or background context. Focus on execution — what the athlete should feel or do differently.
        - Sparse history rule: for Fort aux exercises with fewer than 2 logged sessions, infer an appropriate starting load from the athlete's overall strength profile, similar exercise history, the prescribed rep range, and a target RPE of 7-8. Use intelligent inference — not a fixed percentage formula.
        - Sauna: include a sauna block at the end of each training day (Mon-Sat) where contextually appropriate. Format it as a single block entry (e.g., "G1. Sauna") with a short duration note.
        """
    }

    static func buildCorrectionPrompt(
        plan: String,
        unresolvedViolations: [any ViolationDescribing],
        fortCompilerContext: String,
        fortFidelitySummary: String
    ) -> String {
        let rendered = unresolvedViolations.prefix(20).map { violation -> String in
            "- \(violation.code) | \(violation.day) | \(violation.exercise) | \(violation.message)"
        }.joined(separator: "\n")

        return """
        Correct this workout plan to satisfy all listed validation violations.

        Violations:
        \(rendered)

        Current fort fidelity status: \(fortFidelitySummary)

        FORT COMPILER DIRECTIVES:
        \(fortCompilerContext)

        Hard requirements:
        - Keep overall structure and exercise order unless violation requires change.
        - Preserve Fort day content and supplemental intent.
        - Keep no-range rule in prescription lines.
        - Keep dumbbell parity rule (even DB loads, except main barbell lifts).
        - Respect explicit keep/stay-here progression constraints from prior logs.
        - Never emit section labels or instructional lines as exercises.
        - Each supplemental day (Tue, Thu, Sat) must have at least 5 exercises.
        - Each supplemental day must include McGill Big-3 (curl-up, side bridge, bird-dog).

        Return ONLY the full corrected plan in the same markdown format, starting directly with the first markdown header (# or ##).
        Do not include analysis, reasoning, preamble, or any text before the plan markdown.

        PLAN:
        \(plan)
        """
    }

    static func buildExerciseSelectionPrompt(
        input: PlanGenerationInput,
        fortContext: String
    ) -> String {
        let cycleBlock = input.isNewCycle
            ? "NEW CYCLE: Select a completely fresh set of exercises — do NOT repeat prior-cycle choices."
            : "MID-CYCLE: Keep exercises consistent with prior weeks unless progression requires a swap."

        return """
        You are selecting supplemental exercises for Tue/Thu/Sat workout days.

        ATHLETE: Samuel Light | kg | Aesthetic hypertrophy focus
        SCHEDULE: Fort Mon/Wed/Fri | Supplemental Tue/Thu/Sat

        AESTHETIC PRIORITY ORDER (supplemental volume purpose):
          1. Arms — biceps shape + triceps fullness (HIGH priority)
          2. Delts — medial delt cap for width, rear delt for 3D look (HIGH priority)
          3. Upper chest — clavicular pec "pop" via incline pressing/fly patterns (HIGH priority)
          4. Back detail — upper-back density, rear-delt tie-in, posture (HIGH priority)

        FORT CONTEXT (Mon/Wed/Fri exercises already programmed):
        \(fortContext)

        \(cycleBlock)

        INTERFERENCE RULES:
        - Tuesday: no heavy chest/triceps/front-delt loading; protect Wednesday bench.
        - Thursday: no loaded carries, no heavy rows, no heavy biceps (>6 hard sets); protect Friday deadlift grip.
        - Saturday: upper body only; no heavy lower back; protect Monday squat.

        HARD RULES:
        - No split squats on supplemental days.
        - Standing calves only (never seated).
        - Biceps: rotate grips across Tue/Thu/Sat — supinated -> neutral -> pronated; never same grip on consecutive days.
        - Triceps: vary attachments across Tue/Thu/Sat (rope on Tue, straight-bar variant on Thu/Sat, no single-arm D-handle on Sat).
        - No same exercise repeated on two supplemental days in the same week.
        - Carries: Tuesday only, KB exclusively.
        - Every supplemental day must include McGill Big-3 (curl-up, side bridge, bird-dog) and an incline walk.
        - Minimum 5 exercises per supplemental day.

        TASK: List the exercise names you plan to use for Tuesday, Thursday, and Saturday.
        Include ALL exercises (McGill Big-3 warm-up, main hypertrophy work, isolation, incline walk).
        Apply all interference and hard rules above.

        Return ONLY a plain-text list in this exact format — no explanation, no sets, no reps, no markdown:
        Tuesday: Exercise A, Exercise B, Exercise C
        Thursday: Exercise D, Exercise E, Exercise F
        Saturday: Exercise G, Exercise H, Exercise I
        """
    }
}
