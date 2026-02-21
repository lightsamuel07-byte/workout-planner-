"""
Seed the exercise_aliases table from existing DB exercises.

Reads all exercise names from the SQLite database, runs each through
the ExerciseNormalizer, populates the alias table, and reports
merge statistics.

Usage:
    python3 scripts/seed_exercise_aliases.py
"""

import os
import sqlite3
import sys

# Ensure project root is on the path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from src.exercise_normalizer import ExerciseNormalizer
from src.workout_db import WorkoutDB


def main():
    db_path = os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
        "data",
        "workout_history.db",
    )
    if not os.path.exists(db_path):
        print(f"Database not found: {db_path}")
        return

    normalizer = ExerciseNormalizer()

    # Open DB and run migration (which handles merging + alias seeding)
    db = WorkoutDB(db_path)
    db.init_schema()

    # Report stats
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row

    exercises = conn.execute("SELECT COUNT(*) AS c FROM exercises").fetchone()["c"]
    aliases = conn.execute("SELECT COUNT(*) AS c FROM exercise_aliases").fetchone()["c"]
    unique_canonical = conn.execute(
        "SELECT COUNT(DISTINCT canonical_key) AS c FROM exercise_aliases"
    ).fetchone()["c"]

    print(f"\nSeed complete:")
    print(f"  Exercises in DB:       {exercises}")
    print(f"  Aliases registered:    {aliases}")
    print(f"  Unique canonical keys: {unique_canonical}")
    print(f"  Duplicates merged:     {aliases - exercises}")

    # Show canonical groups with multiple aliases
    groups = conn.execute(
        """
        SELECT canonical_key, canonical_display, COUNT(*) AS alias_count
        FROM exercise_aliases
        GROUP BY canonical_key
        HAVING alias_count > 1
        ORDER BY alias_count DESC
        """
    ).fetchall()

    if groups:
        print(f"\nCanonical groups with multiple aliases ({len(groups)} groups):")
        for g in groups[:20]:
            aliases_list = conn.execute(
                "SELECT raw_name FROM exercise_aliases WHERE canonical_key = ?",
                (g["canonical_key"],),
            ).fetchall()
            alias_names = [a["raw_name"] for a in aliases_list]
            print(f"  {g['canonical_display']} ({g['alias_count']} aliases):")
            for name in alias_names:
                print(f"    - {name}")

    conn.close()
    db.close()


if __name__ == "__main__":
    main()
