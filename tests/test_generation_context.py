import os
import tempfile
import unittest

from src.fort_compiler import build_fort_compiler_context
from src.generation_context import build_db_generation_context
from src.workout_db import WorkoutDB


FORT_SAMPLE = """
Monday 2.16.26
Gameday #10
PREP
90/90 HIP SWITCH
CLUSTER SET SINGLES
BACK SQUAT
THAW
ROWERG
"""


class GenerationContextTests(unittest.TestCase):
    def _seed_log(
        self,
        db,
        sheet_name,
        day_label,
        day_name,
        session_date,
        source_row,
        exercise_name,
        log_text,
        parsed_rpe=None,
    ):
        exercise_id = db.upsert_exercise(exercise_name)
        session_id = db.upsert_session(
            sheet_name=sheet_name,
            day_label=day_label,
            day_name=day_name,
            session_date=session_date,
        )
        db.upsert_exercise_log(
            session_id=session_id,
            exercise_id=exercise_id,
            source_row=source_row,
            block="A1",
            prescribed_sets="3",
            prescribed_reps="10",
            prescribed_load="20",
            prescribed_rest="90 seconds",
            prescribed_notes="",
            log_text=log_text,
            parsed_rpe=parsed_rpe,
            parsed_notes=None,
        )

    def test_db_context_includes_fort_anchor_and_prior_supplemental_targets(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            db_path = os.path.join(tmpdir, "history.db")
            db = WorkoutDB(db_path)
            db.init_schema()
            try:
                self._seed_log(
                    db,
                    sheet_name="Weekly Plan (2/9/2026)",
                    day_label="MONDAY",
                    day_name="MONDAY",
                    session_date="2026-02-09",
                    source_row=2,
                    exercise_name="Back Squat",
                    log_text="98 kg moved well | RPE 8",
                    parsed_rpe=8.0,
                )
                self._seed_log(
                    db,
                    sheet_name="Weekly Plan (2/9/2026)",
                    day_label="TUESDAY",
                    day_name="TUESDAY",
                    session_date="2026-02-10",
                    source_row=3,
                    exercise_name="Cable Lateral Raise",
                    log_text="hard last reps | RPE 8.5",
                    parsed_rpe=8.5,
                )
                db.conn.commit()
            finally:
                db.close()

            _ctx_text, fort_meta = build_fort_compiler_context(
                {"Monday": FORT_SAMPLE, "Wednesday": "", "Friday": ""}
            )
            prior_supplemental = {
                "Tuesday": [{"exercise": "Cable Lateral Raise"}],
                "Thursday": [],
                "Saturday": [],
            }
            context = build_db_generation_context(
                db_path=db_path,
                prior_supplemental=prior_supplemental,
                fort_compiler_meta=fort_meta,
                max_exercises=6,
                logs_per_exercise=1,
            )

            self.assertIsNotNone(context)
            self.assertIn("LONGITUDINAL DB CONTEXT", context)
            self.assertIn("BACK SQUAT", context)
            self.assertIn("Cable Lateral Raise", context)

    def test_db_context_falls_back_to_recent_history_without_targets(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            db_path = os.path.join(tmpdir, "history.db")
            db = WorkoutDB(db_path)
            db.init_schema()
            try:
                self._seed_log(
                    db,
                    sheet_name="Weekly Plan (2/2/2026)",
                    day_label="SATURDAY",
                    day_name="SATURDAY",
                    session_date="2026-02-07",
                    source_row=8,
                    exercise_name="Seated DB Shoulder Press",
                    log_text="strong set",
                    parsed_rpe=None,
                )
                db.conn.commit()
            finally:
                db.close()

            context = build_db_generation_context(
                db_path=db_path,
                prior_supplemental=None,
                fort_compiler_meta=None,
                max_exercises=3,
                logs_per_exercise=1,
            )

            self.assertIsNotNone(context)
            self.assertIn("Seated DB Shoulder Press", context)


if __name__ == "__main__":
    unittest.main()
