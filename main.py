#!/usr/bin/env python3
"""
Workout Planning Automation Tool
Main entry point for the application.
"""

import os
import sys
import yaml
from dotenv import load_dotenv

# Add src to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'src'))

from sheets_reader import SheetsReader
from sheets_writer import SheetsWriter
from input_handler import InputHandler
from plan_generator import PlanGenerator
from fort_compiler import build_fort_compiler_context


def load_config():
    """Load configuration from config.yaml."""
    config_path = os.path.join(os.path.dirname(__file__), 'config.yaml')

    if not os.path.exists(config_path):
        print("Error: config.yaml not found!")
        sys.exit(1)

    with open(config_path, 'r') as f:
        config = yaml.safe_load(f)

    return config


def print_banner():
    """Print welcome banner."""
    banner = """
╔══════════════════════════════════════════════════════════════╗
║                                                              ║
║        WORKOUT PLANNING AUTOMATION TOOL                      ║
║        Powered by Claude AI                                  ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝
    """
    print(banner)


def main():
    """Main application flow."""
    print_banner()

    # Load environment variables
    load_dotenv()

    # Load configuration
    print("Loading configuration...")
    config = load_config()

    # Get API key
    api_key_env = config['claude']['api_key_env']
    api_key = os.getenv(api_key_env)

    if not api_key:
        print(f"\n❌ Error: {api_key_env} not found in environment variables!")
        print("\nPlease:")
        print("1. Copy .env.example to .env")
        print("2. Add your Anthropic API key to .env")
        print("3. Get your API key from: https://console.anthropic.com/")
        sys.exit(1)

    # Initialize components
    print("\nInitializing components...")

    sheets_reader = SheetsReader(
        credentials_file=config['google_sheets']['credentials_file'],
        spreadsheet_id=config['google_sheets']['spreadsheet_id'],
        sheet_name=config['google_sheets']['sheet_name'],
        service_account_file=config.get('google_sheets', {}).get('service_account_file')
    )

    # Calculate next Monday for the sheet name (the upcoming week)
    from datetime import datetime, timedelta
    today = datetime.now()
    days_until_monday = (7 - today.weekday()) % 7  # Days until next Monday
    if days_until_monday == 0:  # If today is Monday, use today
        next_monday = today
    else:
        next_monday = today + timedelta(days=days_until_monday)
    sheet_name = f"Weekly Plan ({next_monday.month}/{next_monday.day}/{next_monday.year})"

    sheets_writer = SheetsWriter(
        credentials_file=config['google_sheets']['credentials_file'],
        spreadsheet_id=config['google_sheets']['spreadsheet_id'],
        sheet_name=sheet_name,
        service_account_file=config.get('google_sheets', {}).get('service_account_file')
    )

    input_handler = InputHandler()

    plan_generator = PlanGenerator(
        api_key=api_key,
        config=config,  # Pass full config for athlete profile and rules
        model=config['claude']['model'],
        max_tokens=config['claude']['max_tokens']
    )

    # Step 1: Authenticate and read workout history
    print("\n" + "=" * 60)
    print("AUTHENTICATING WITH GOOGLE SHEETS")
    print("=" * 60)

    try:
        sheets_reader.authenticate()
        workout_history = sheets_reader.read_workout_history(num_recent_workouts=7)
        formatted_history = sheets_reader.format_history_for_ai(workout_history)

        # Read prior week's supplemental workouts for progressive overload
        prior_week_supplemental = sheets_reader.read_prior_week_supplemental()
        formatted_prior_supplemental = sheets_reader.format_supplemental_for_ai(prior_week_supplemental) if prior_week_supplemental else "No prior week supplemental data available."
    except Exception as e:
        print(f"\n❌ Error reading workout history: {e}")
        print("\nContinuing without workout history...")
        formatted_history = "No workout history available."
        formatted_prior_supplemental = "No prior week supplemental data available."

    # Step 2: Collect trainer workouts
    trainer_workouts = input_handler.collect_trainer_workouts()

    if not trainer_workouts:
        print("\n⚠ Warning: No trainer workouts entered. The plan may be incomplete.")
        proceed = input("Continue anyway? (yes/no): ").strip().lower()
        if proceed not in ['yes', 'y']:
            print("\nExiting. Run the program again when you have the trainer workouts.")
            sys.exit(0)

    # Step 3: Get fixed preferences (no user input needed)
    preferences = input_handler.collect_preferences()

    print("\n" + "=" * 60)
    print("PREFERENCES (FIXED)")
    print("=" * 60)
    print("  Goal: Maximize aesthetics")
    print("  Training: Progressive overload")
    print("  Supplemental Days: Tuesday, Thursday, Saturday")
    print("  Rest Day: Sunday")

    # Step 4: Generate the plan
    print("\n" + "=" * 60)
    print("GENERATING WORKOUT PLAN")
    print("=" * 60)

    formatted_trainer_workouts = input_handler.format_for_ai()
    fort_compiler_context = None
    fort_compiler_meta = None
    try:
        fort_compiler_context, fort_compiler_meta = build_fort_compiler_context(input_handler.trainer_workouts)
        print(f"Fort parser confidence: {fort_compiler_meta.get('overall_confidence', 0.0):.2f}")
    except Exception as parser_exc:
        print(f"Fort parser fallback to raw text: {parser_exc}")
        fort_compiler_context = None
        fort_compiler_meta = None

    # Add context about new program vs continuing program
    program_context = ""
    if input_handler.is_new_program:
        program_context = "\n\nNEW FORT PROGRAM: Design fresh supplemental workouts that complement this new program.\n"
    else:
        program_context = "\n\nCONTINUING FORT PROGRAM: Maintain the same supplemental workout structure with progressive overload based on prior week's data.\n"
        program_context += f"\n{formatted_prior_supplemental}\n"

    db_path = (config.get('database', {}) or {}).get('path', 'data/workout_history.db')
    plan, explanation, validation_summary = plan_generator.generate_plan(
        workout_history=formatted_history,
        trainer_workouts=formatted_trainer_workouts + program_context,
        preferences="",  # Already included in formatted_trainer_workouts
        fort_compiler_context=fort_compiler_context,
        fort_compiler_meta=fort_compiler_meta,
        db_path=db_path,
    )

    if not plan:
        print("\n❌ Failed to generate workout plan.")
        sys.exit(1)

    # Step 5: Display and save the plan
    print("\n" + "=" * 60)
    print("YOUR GENERATED WORKOUT PLAN")
    print("=" * 60)
    print("\n" + plan + "\n")

    if explanation:
        print("\n" + "=" * 60)
        print("PLAN EXPLANATION")
        print("=" * 60)
        print("\n" + explanation + "\n")
    if validation_summary:
        print("Validation:", validation_summary)

    # Save the plan to file
    output_folder = config['output']['folder']
    output_format = config['output']['format']

    plan_filepath, explanation_filepath = plan_generator.save_plan(
        plan=plan,
        output_folder=output_folder,
        format=output_format
    )

    # Step 6: Write the plan to Google Sheets
    print("\n" + "=" * 60)
    print("WRITING TO GOOGLE SHEETS")
    print("=" * 60)

    try:
        sheets_writer.authenticate()
        sheets_writer.write_workout_plan(
            plan,
            explanation_text=explanation,
            validation_summary=validation_summary,
        )
        print("\n✓ Successfully written to Google Sheets!")
    except Exception as e:
        print(f"\n⚠ Warning: Could not write to Google Sheets: {e}")
        print(f"Your plan was still saved to: {plan_filepath}")

    # Finish
    print("\n" + "=" * 60)
    print("✓ ALL DONE!")
    print("=" * 60)
    print(f"\nYour workout plan has been:")
    print(f"  • Written to Google Sheets (sheet: '{sheet_name}')")
    print(f"  • Saved locally to: {plan_filepath}")
    if explanation_filepath:
        print(f"  • Explanation saved locally to: {explanation_filepath}")
    print("\nGood luck with your training! 💪\n")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n\nExiting...")
        sys.exit(0)
    except Exception as e:
        print(f"\n❌ Unexpected error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
