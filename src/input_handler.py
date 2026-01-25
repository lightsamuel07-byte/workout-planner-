"""
Handles user input for trainer workouts and weekly preferences.
"""


class InputHandler:
    """Handles collection of trainer workouts and user preferences."""

    def __init__(self):
        self.trainer_workouts = {}
        self.preferences = {}
        self.is_new_program = False

    def collect_trainer_workouts(self):
        """
        Collect the 3 trainer workouts from user via copy-paste.

        Returns:
            Dictionary with Monday, Wednesday, Friday workouts
        """
        print("\n" + "=" * 60)
        print("STEP 1: ENTER TRAINER WORKOUTS FROM TRAIN HEROIC")
        print("=" * 60)
        print("\nYou'll paste the 3 workouts from your trainer.")
        print("After pasting each workout, press Enter twice (empty line) to finish.\n")

        days = ["Monday", "Wednesday", "Friday"]
        workouts = {}

        for day in days:
            print(f"\n--- {day.upper()} WORKOUT ---")
            print(f"Paste your {day} workout from Train Heroic, then press Enter twice:\n")

            lines = []
            empty_line_count = 0

            while True:
                line = input()

                if line.strip() == "":
                    empty_line_count += 1
                    if empty_line_count >= 2:
                        break
                    lines.append(line)
                else:
                    empty_line_count = 0
                    lines.append(line)

            workout_text = "\n".join(lines).strip()

            if workout_text:
                workouts[day] = workout_text
                print(f"\n✓ {day} workout received ({len(workout_text)} characters)")
            else:
                print(f"\n⚠ Warning: No {day} workout entered. You can run this again if needed.")

        self.trainer_workouts = workouts

        # Ask if this is a new Fort program
        print("\n" + "=" * 60)
        print("Is this a new Fort program? (yes/no): ", end="")
        response = input().strip().lower()
        self.is_new_program = response in ['yes', 'y']

        if self.is_new_program:
            print("✓ Noted: New program - will design fresh supplemental workouts")
        else:
            print("✓ Noted: Same program - will maintain supplemental structure with progressive overload")

        return workouts

    def collect_preferences(self):
        """
        Set default preferences based on user's goals.
        No user input needed - preferences are fixed.

        Returns:
            Dictionary with user preferences
        """
        # Fixed preferences based on user requirements
        preferences = {
            'goal': 'maximize aesthetics without interfering with Mon/Wed/Fri Fort program',
            'training_approach': 'progressive overload',
            'supplemental_days': 'Tuesday, Thursday, Saturday',
            'rest_day': 'Sunday'
        }

        self.preferences = preferences
        return preferences

    def format_for_ai(self):
        """
        Format collected inputs for AI prompt.

        Returns:
            Formatted string for AI consumption
        """
        output = ""

        # Add trainer workouts
        if self.trainer_workouts:
            output += "TRAINER WORKOUTS FROM TRAIN HEROIC:\n\n"
            for day, workout in self.trainer_workouts.items():
                output += f"=== {day.upper()} ===\n{workout}\n\n"

        # Add preferences
        if self.preferences:
            output += "USER WEEKLY PREFERENCES:\n\n"
            for key, value in self.preferences.items():
                output += f"{key.replace('_', ' ').title()}: {value}\n"

        return output
