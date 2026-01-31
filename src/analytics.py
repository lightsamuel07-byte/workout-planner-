"""
Analytics module for processing historical workout data from Google Sheets.
"""

from datetime import datetime, timedelta
from collections import defaultdict
import re


class WorkoutAnalytics:
    """Analyze historical workout data for progress tracking."""

    def __init__(self, sheets_reader):
        """
        Initialize analytics with a configured SheetsReader.

        Args:
            sheets_reader: Authenticated SheetsReader instance
        """
        self.sheets_reader = sheets_reader
        self.historical_data = None

    def load_historical_data(self, weeks_back=8):
        """
        Load historical workout data from Google Sheets.

        Args:
            weeks_back: Number of weeks of history to load

        Returns:
            List of workout dictionaries with parsed exercise data
        """
        # Find all weekly plan sheets from the spreadsheet
        all_sheets = self.sheets_reader.get_all_weekly_plan_sheets()

        # Filter to most recent N weeks
        recent_sheets = all_sheets[-weeks_back:] if len(all_sheets) > weeks_back else all_sheets

        # Read data from each sheet
        historical_workouts = []
        for sheet_name in recent_sheets:
            self.sheets_reader.sheet_name = sheet_name
            week_data = self.sheets_reader.read_workout_history()
            historical_workouts.extend(week_data)

        self.historical_data = historical_workouts
        return historical_workouts

    def get_main_lift_progression(self, lift_name, weeks=8):
        """
        Track progression for a main lift (Back Squat, Bench Press, Deadlift).

        Args:
            lift_name: Name of the lift to track
            weeks: Number of weeks to analyze

        Returns:
            Dictionary with weekly max loads and progression percentage
        """
        if not self.historical_data:
            return None

        weekly_max = {}

        for workout in self.historical_data:
            date = workout.get('date', '')

            for exercise in workout.get('exercises', []):
                exercise_name = exercise.get('exercise', '').lower()

                # Match lift name (case insensitive, partial match)
                if lift_name.lower() in exercise_name:
                    load_str = exercise.get('load', '')

                    # Parse load (e.g., "96.5 kg" -> 96.5)
                    load_match = re.search(r'([\d\.]+)', load_str)
                    if load_match:
                        load = float(load_match.group(1))

                        # Track max for this week
                        if date not in weekly_max or load > weekly_max[date]:
                            weekly_max[date] = load

        # Calculate progression
        if len(weekly_max) >= 2:
            dates = sorted(weekly_max.keys())
            starting_load = weekly_max[dates[0]]
            current_load = weekly_max[dates[-1]]
            
            if starting_load > 0:
                progression_pct = ((current_load - starting_load) / starting_load) * 100
            else:
                progression_pct = 0

            return {
                'weekly_data': weekly_max,
                'starting_load': starting_load,
                'current_load': current_load,
                'progression_kg': current_load - starting_load,
                'progression_pct': round(progression_pct, 1)
            }

        return None

    def get_weekly_volume(self, weeks=8):
        """
        Calculate total training volume per week.

        Args:
            weeks: Number of weeks to analyze

        Returns:
            Dictionary with weekly volume totals
        """
        if not self.historical_data:
            return None

        weekly_volume = defaultdict(float)

        for workout in self.historical_data:
            date = workout.get('date', '')

            for exercise in workout.get('exercises', []):
                # Parse sets, reps, load
                sets_str = exercise.get('sets', '')
                reps_str = exercise.get('reps', '')
                load_str = exercise.get('load', '')

                sets_match = re.search(r'(\d+)', sets_str)
                reps_match = re.search(r'(\d+)', reps_str)
                load_match = re.search(r'([\d\.]+)', load_str)

                if sets_match and reps_match and load_match:
                    sets = int(sets_match.group(1))
                    reps = int(reps_match.group(1))
                    load = float(load_match.group(1))

                    volume = sets * reps * load
                    weekly_volume[date] += volume

        return dict(weekly_volume)

    def get_workout_completion_rate(self, weeks=4):
        """
        Calculate percentage of planned workouts completed.

        Args:
            weeks: Number of weeks to analyze

        Returns:
            Dictionary with completion stats
        """
        if not self.historical_data:
            return {'completed': 0, 'total': 0, 'rate': 0}

        # Count workouts with logged data
        completed = 0
        total = 0

        for workout in self.historical_data[-weeks*7:]:  # Last N weeks (7 days per week)
            total += 1

            # Check if any exercises have logged data
            has_logs = any(ex.get('log', '').strip() for ex in workout.get('exercises', []))

            if has_logs:
                completed += 1

        rate = (completed / total * 100) if total > 0 else 0

        return {
            'completed': completed,
            'total': total,
            'rate': round(rate, 1)
        }

    def get_bicep_grip_rotation_compliance(self, weeks=4):
        """
        Check if bicep training follows grip rotation rules.

        Rules from config:
        - Never same-grip two days in a row
        - Rotate grips: supinated → neutral → pronated
        - Keep ~48h before another long-length stimulus
        - Cap biceps hard sets at 10-12 per rolling 4 days

        Returns:
            Dictionary with compliance status
        """
        if not self.historical_data:
            return {'compliant': False, 'violations': []}

        # Track bicep exercises by date and grip type
        bicep_exercises = []

        for workout in self.historical_data[-weeks*7:]:
            date = workout.get('date', '')

            for exercise in workout.get('exercises', []):
                exercise_name = exercise.get('exercise', '').lower()

                # Identify bicep exercises
                if any(keyword in exercise_name for keyword in ['curl', 'bicep', 'biceps']):
                    # Infer grip type from exercise name
                    grip = self._infer_grip_type(exercise_name)

                    bicep_exercises.append({
                        'date': date,
                        'exercise': exercise.get('exercise'),
                        'grip': grip
                    })

        # Check for violations
        violations = []
        for i in range(1, len(bicep_exercises)):
            prev = bicep_exercises[i-1]
            curr = bicep_exercises[i]

            if prev['grip'] == curr['grip']:
                violations.append(f"Same grip ({curr['grip']}) used consecutively")

        return {
            'compliant': len(violations) == 0,
            'violations': violations,
            'total_bicep_sessions': len(bicep_exercises)
        }

    def _infer_grip_type(self, exercise_name):
        """Infer grip type from exercise name."""
        name_lower = exercise_name.lower()

        if 'hammer' in name_lower or 'neutral' in name_lower:
            return 'neutral'
        elif 'reverse' in name_lower or 'pronated' in name_lower:
            return 'pronated'
        else:
            return 'supinated'  # Default for most curls

    def get_muscle_group_volume(self, muscle_group, weeks=8):
        """
        Calculate volume for a specific muscle group.

        Args:
            muscle_group: Target muscle (e.g., 'arms', 'chest', 'back')
            weeks: Number of weeks to analyze

        Returns:
            Dictionary with weekly volume per muscle group
        """
        # Map exercises to muscle groups
        muscle_keywords = {
            'arms': ['curl', 'tricep', 'bicep', 'arm'],
            'chest': ['bench', 'chest', 'press', 'fly'],
            'back': ['row', 'pulldown', 'pull-up', 'lat', 'deadlift'],
            'shoulders': ['shoulder', 'press', 'raise', 'delt'],
            'legs': ['squat', 'leg', 'lunge', 'split']
        }

        keywords = muscle_keywords.get(muscle_group.lower(), [])
        weekly_volume = defaultdict(float)

        for workout in self.historical_data:
            date = workout.get('date', '')

            for exercise in workout.get('exercises', []):
                exercise_name = exercise.get('exercise', '').lower()

                # Check if exercise targets this muscle group
                if any(keyword in exercise_name for keyword in keywords):
                    # Calculate volume
                    sets_str = exercise.get('sets', '')
                    reps_str = exercise.get('reps', '')
                    load_str = exercise.get('load', '')

                    sets_match = re.search(r'(\d+)', sets_str)
                    reps_match = re.search(r'(\d+)', reps_str)
                    load_match = re.search(r'([\d\.]+)', load_str)

                    if sets_match and reps_match and load_match:
                        sets = int(sets_match.group(1))
                        reps = int(reps_match.group(1))
                        load = float(load_match.group(1))

                        volume = sets * reps * load
                        weekly_volume[date] += volume

        return dict(weekly_volume)
